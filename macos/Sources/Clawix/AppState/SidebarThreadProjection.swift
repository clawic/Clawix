import Foundation
import SwiftUI

extension AppState {
    /// First-paint pre-population of `chats[]` and `pinnedOrder` from
    /// the compact JSON snapshot of the last applied state. This keeps
    /// launch away from SQLite; the post-first-frame SQLite pass only
    /// hydrates the globally recent rows, while project accordions load
    /// their own small pages on demand.
    /// No-op when both snapshots are empty (fresh install).
    func applyFirstPaintCacheForLaunch() {
        guard snapshotEnabled, let payload = FirstPaintCache.load() else { return }
        var restoredProjects: [Project] = payload.projects.compactMap { item in
            guard let id = UUID(uuidString: item.id) else { return nil }
            return Project(id: id, resourceId: item.resourceId, name: item.name, path: item.path)
        }
        var seenProjectPaths = Set(restoredProjects.map(\.path).filter { !$0.isEmpty })
        for path in payload.projectPathHints where !seenProjectPaths.contains(path) {
            seenProjectPaths.insert(path)
            restoredProjects.append(Project(
                id: StableProjectID.uuid(for: path),
                name: URL(fileURLWithPath: path).lastPathComponent.isEmpty ? path : URL(fileURLWithPath: path).lastPathComponent,
                path: path
            ))
        }
        projects = restoredProjects

        let projectById = Dictionary(uniqueKeysWithValues: projects.map { ($0.id.uuidString, $0) })
        let projectByPath = Dictionary(uniqueKeysWithValues: projects.map { ($0.path, $0) })
        let pinnedSet = Set(payload.pinnedThreadIds)
        var threadToChat: [String: UUID] = [:]
        chats = payload.chats.compactMap { item in
            guard let id = UUID(uuidString: item.chatUuid) else { return nil }
            let projectId = item.projectId.flatMap { projectById[$0]?.id }
                ?? item.projectPath.flatMap { projectByPath[$0]?.id }
            threadToChat[item.threadId] = id
            return Chat(
                id: id,
                title: item.title,
                messages: [],
                createdAt: Date(timeIntervalSince1970: TimeInterval(item.updatedAt)),
                clawixThreadId: item.threadId,
                rolloutPath: nil,
                historyHydrated: false,
                hasActiveTurn: false,
                projectId: projectId,
                isArchived: false,
                isPinned: item.pinned || pinnedSet.contains(item.threadId),
                hasUnreadCompletion: false,
                cwd: item.cwd,
                hasGitRepo: false,
                branch: nil,
                availableBranches: [],
                uncommittedFiles: nil
            )
        }
        pinnedOrder = payload.pinnedThreadIds.compactMap { threadToChat[$0] }
    }

    func applySnapshotForFirstPaint() {
        guard snapshotEnabled else { return }
        // Populate projects unconditionally so the sidebar's project
        // sections are present from the very first paint, even on a
        // fresh install where the snapshot is still empty.
        projects = mergedProjects()
        let projectByPath = Dictionary(uniqueKeysWithValues: projects.map { ($0.path, $0) })
        let projectById = Dictionary(uniqueKeysWithValues: projects.map { ($0.id.uuidString, $0) })

        var restored: [Chat] = []
        // Drive `isPinned` from the live local repo (which already
        // mirrors Codex on boot) rather than the snapshot's `pinned`
        // column, so a pin added in Codex CLI shows up on first paint
        // even though the snapshot was written before that pin existed.
        let pinIds = pinsRepo.orderedThreadIds()
        let pinnedSet = Set(pinIds)

        let firstPaintLimit = 200
        let topRows = snapshotRepo.loadTop(limit: firstPaintLimit)
        for row in topRows {
            guard let id = UUID(uuidString: row.chatUuid) else { continue }
            let projectId = row.projectId.flatMap { projectById[$0]?.id }
                ?? row.projectPath.flatMap { path in projectByPath[path]?.id }
            let archived = row.archived != 0
            restored.append(Chat(
                id: id,
                title: row.title,
                messages: [],
                createdAt: Date(timeIntervalSince1970: TimeInterval(row.updatedAt)),
                clawixThreadId: row.threadId,
                rolloutPath: nil,
                historyHydrated: false,
                hasActiveTurn: false,
                projectId: projectId,
                isArchived: archived,
                isPinned: !archived && pinnedSet.contains(row.threadId),
                hasUnreadCompletion: false,
                cwd: row.cwd,
                hasGitRepo: false,
                branch: nil,
                availableBranches: [],
                uncommittedFiles: nil
            ))
        }

        guard !restored.isEmpty else { return }

        // Single sort by recency so Pinned and Chronological land in
        // the order the runtime would have produced.
        restored.sort { $0.createdAt > $1.createdAt }
        chats = restored

        let threadToChat = chatIdByThreadId(chats)
        pinnedOrder = pinIds.compactMap { threadToChat[$0] }
    }

    nonisolated static func resolveSnapshotProject(
        _ row: SidebarSnapshotProjectRow,
        projectById: [String: Project],
        projectByPath: [String: Project]
    ) -> Project? {
        row.projectId.flatMap { projectById[$0] } ?? projectByPath[row.projectPath]
    }

    /// Rewrite the SQLite snapshots from the current in-memory `chats`
    /// list. Called after every applyThreads / mergeThreads. Skipped
    /// when fixtures drive the threads list so tests stay deterministic.
    /// The actual writes go off-main via GRDB's serialized queue.
    ///
    /// Two snapshots:
    ///  - `sidebar_snapshot`: every chat (Pinned + Chrono first paint).
    ///  - `sidebar_snapshot_project`: capped per-project for demand
    ///    loading when a project row becomes visible or expanded. Cap
    ///    aligns with the per-project `listThreads` limit so the
    ///    persisted set is never larger than what a refresh would replace.
    private func persistSidebarSnapshot() {
        guard snapshotEnabled else { return }
        let projectsById = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        let now = Int64(Date().timeIntervalSince1970)
        let rows: [SidebarSnapshotRow] = chats.compactMap { chat in
            guard let threadId = chat.clawixThreadId else { return nil }
            return SidebarSnapshotRow(
                threadId: threadId,
                chatUuid: chat.id.uuidString,
                title: chat.title,
                cwd: chat.cwd,
                projectId: chat.projectId?.uuidString,
                projectPath: chat.projectId.flatMap { projectsById[$0]?.path },
                updatedAt: Int64(chat.createdAt.timeIntervalSince1970),
                archived: chat.isArchived ? 1 : 0,
                pinned: chat.isPinned ? 1 : 0,
                capturedAt: now
            )
        }

        // Per-project view: chats whose project is resolved, archived
        // ones dropped (sidebar accordions never list them). Group by
        // project_id, sort each bucket by recency, truncate to the
        // per-project cap.
        let perProjectCap = Self.snapshotPerProjectCap
        let globalCap = Self.snapshotGlobalCap
        var bucketed: [String: [SidebarSnapshotProjectRow]] = [:]
        for chat in chats where !chat.isArchived {
            guard let threadId = chat.clawixThreadId else { continue }
            guard
                let projectId = chat.projectId,
                let project = projectsById[projectId]
            else { continue }
            let row = SidebarSnapshotProjectRow(
                threadId: threadId,
                chatUuid: chat.id.uuidString,
                title: chat.title,
                cwd: chat.cwd,
                projectId: project.id.uuidString,
                projectPath: project.path,
                updatedAt: Int64(chat.createdAt.timeIntervalSince1970),
                archived: 0,
                pinned: chat.isPinned ? 1 : 0,
                capturedAt: now
            )
            bucketed[project.id.uuidString, default: []].append(row)
        }
        var perProjectRows: [SidebarSnapshotProjectRow] = []
        for var bucket in bucketed.values {
            bucket.sort { $0.updatedAt > $1.updatedAt }
            perProjectRows.append(contentsOf: bucket.prefix(perProjectCap))
        }
        if perProjectRows.count > globalCap {
            perProjectRows.sort { $0.updatedAt > $1.updatedAt }
            perProjectRows = Array(perProjectRows.prefix(globalCap))
        }

        let repo = snapshotRepo
        let cacheChats = chats
        let cacheProjects = projects
        let cachePinnedOrder = pinnedOrder
        Task.detached(priority: .background) {
            FirstPaintCache.save(chats: cacheChats, projects: cacheProjects, pinnedOrder: cachePinnedOrder)
            repo.replaceAll(rows)
            repo.replaceProjectIndex(perProjectRows)
        }
    }

    func applyThreads(_ threads: [AgentThreadSummary], extraPinnedThreadIds: [String] = []) {
        if !clawJSSessionsCanonicalActive {
            projects = mergedProjects()
        }
        let projectByPath = Dictionary(uniqueKeysWithValues: projects.map { ($0.path, $0) })
        let pinIds = pinsRepo.orderedThreadIds()
        let orderedPinIds = pinIds + extraPinnedThreadIds.filter { !pinIds.contains($0) }
        let pinnedSet = Set(orderedPinIds)

        reconcileArchivesFromRuntime(threads)

        let oldByThread = chatByThreadId(chats)
        let oldArchivedByThread = chatByThreadId(archivedChats)

        let sorted = threads.sorted { $0.updatedAt > $1.updatedAt }
        let selectedSnapshotChat: Chat?
        if case let .chat(id) = currentRoute,
           let selected = chat(byId: id),
           let threadId = selected.clawixThreadId,
           !sorted.contains(where: { $0.id.caseInsensitiveCompare(threadId) == .orderedSame }) {
            selectedSnapshotChat = selected
        } else {
            selectedSnapshotChat = nil
        }
        var nextChats: [Chat] = []
        var nextArchived: [Chat] = []
        nextChats.reserveCapacity(sorted.count)
        for thread in sorted {
            let old = oldByThread[thread.id] ?? oldArchivedByThread[thread.id]
            let chat = chatFromThread(thread,
                                      old: old,
                                      projectByPath: projectByPath,
                                      pinnedSet: pinnedSet)
            if chat.isArchived {
                nextArchived.append(chat)
            } else {
                nextChats.append(chat)
            }
        }
        if let selectedSnapshotChat {
            if selectedSnapshotChat.isArchived {
                if !nextArchived.contains(where: { $0.id == selectedSnapshotChat.id || $0.clawixThreadId == selectedSnapshotChat.clawixThreadId }) {
                    nextArchived.insert(selectedSnapshotChat, at: 0)
                }
            } else if !nextChats.contains(where: { $0.id == selectedSnapshotChat.id || $0.clawixThreadId == selectedSnapshotChat.clawixThreadId }) {
                nextChats.insert(selectedSnapshotChat, at: 0)
            }
        }
        chats = nextChats
        // Only overwrite archivedChats when the payload actually carries
        // archived rows (fixture / showcase mode). The runtime path calls
        // `applyThreads` with `archived: false` only, so an empty
        // `nextArchived` here means "no info", not "the archived list is
        // empty" — preserve whatever `loadArchivedChats` already cached.
        if !nextArchived.isEmpty {
            archivedChats = Array(nextArchived.prefix(Self.archivedSidebarLimit))
            archivedLoaded = true
        }

        let threadToChat = chatIdByThreadId(chats)
        pinnedOrder = orderedPinIds.compactMap { threadToChat[$0] }
        openFirstE2EChatIfRequested()
        writeE2EStateReportIfRequested()
        persistSidebarSnapshot()
    }

    /// Like `applyThreads` but additive: refreshes existing chats from the
    /// new payload and appends previously-unknown ones, instead of
    /// replacing the whole list. Used by per-project lazy loads so they
    /// don't wipe chats from other projects already in memory.
    func mergeThreads(_ threads: [AgentThreadSummary]) {
        if !clawJSSessionsCanonicalActive {
            projects = mergedProjects()
        }
        let projectByPath = Dictionary(uniqueKeysWithValues: projects.map { ($0.path, $0) })
        let pinIds = pinsRepo.orderedThreadIds()
        let pinnedSet = Set(pinIds)

        reconcileArchivesFromRuntime(threads)

        var indexByThread: [String: Int] = [:]
        for (idx, chat) in chats.enumerated() {
            if let tid = chat.clawixThreadId { indexByThread[tid] = idx }
        }

        var updated = chats
        for thread in threads {
            if let idx = indexByThread[thread.id] {
                updated[idx] = chatFromThread(thread,
                                              old: updated[idx],
                                              projectByPath: projectByPath,
                                              pinnedSet: pinnedSet)
            } else {
                updated.append(chatFromThread(thread,
                                              old: nil,
                                              projectByPath: projectByPath,
                                              pinnedSet: pinnedSet))
            }
        }
        chats = updated

        let threadToChat = chatIdByThreadId(chats)
        pinnedOrder = pinIds.compactMap { threadToChat[$0] }
        writeE2EStateReportIfRequested()
        persistSidebarSnapshot()
    }

    func chatFromThread(_ thread: AgentThreadSummary,
                                old: Chat?,
                                projectByPath: [String: Project],
                                pinnedSet: Set<String>) -> Chat {
        let rootPath = rootPath(for: thread, projectByPath: projectByPath)
        let archived = archivesRepo.isArchived(thread.id)
        return Chat(
            id: old?.id ?? UUID(),
            title: resolveTitle(for: thread),
            messages: [],
            createdAt: thread.updatedDate,
            clawixThreadId: thread.id,
            rolloutPath: thread.path.map { URL(fileURLWithPath: $0) } ?? old?.rolloutPath,
            historyHydrated: old?.historyHydrated ?? false,
            hasActiveTurn: old?.hasActiveTurn ?? false,
            projectId: rootPath.flatMap { projectByPath[$0]?.id },
            isArchived: archived,
            isPinned: !archived && pinnedSet.contains(thread.id),
            hasUnreadCompletion: old?.hasUnreadCompletion ?? false,
            cwd: thread.cwd,
            hasGitRepo: old?.hasGitRepo ?? false,
            branch: old?.branch,
            availableBranches: old?.availableBranches ?? [],
            uncommittedFiles: old?.uncommittedFiles
        )
    }

    /// When sync is on, reflect the runtime's archive flag into local_archives.
    /// Captures changes made externally (Codex CLI, Electron app) so the next
    /// chatFromThread call sees the right state via the repo. No-op when sync
    /// is off — the local DB stays independent.
    private func reconcileArchivesFromRuntime(_ threads: [AgentThreadSummary]) {
        guard SyncSettings.syncArchiveWithCodex else { return }
        for thread in threads {
            let runtimeSays = thread.archived
            let localSays = archivesRepo.isArchived(thread.id)
            if runtimeSays == localSays { continue }
            if runtimeSays {
                archivesRepo.archive(thread.id)
            } else {
                archivesRepo.unarchive(thread.id)
            }
        }
    }

    private func rootPath(for thread: AgentThreadSummary, projectByPath: [String: Project]) -> String? {
        rootPath(threadId: thread.id, cwd: thread.cwd, projectByPath: projectByPath)
    }

    /// Same project-resolution logic as the `AgentThreadSummary`
    /// variant but parameterised on the thread id + cwd directly so
    /// wire chats coming from the daemon (which carry both via the
    /// `threadId` field added to `WireSession`) can be reconciled
    /// without first being re-wrapped as an `AgentThreadSummary`.
    /// Returns nil when the thread id is missing, keeping incomplete
    /// session records in the flat list instead of guessing a project.
    func rootPath(threadId: String?, cwd: String?, projectByPath: [String: Project]) -> String? {
        if let threadId {
            if chatProjectsRepo.isProjectless(threadId) {
                return nil
            }
            if let local = chatProjectsRepo.overridePath(for: threadId), projectByPath[local] != nil {
                return local
            }
            if backendState.projectlessThreadIds.contains(threadId) {
                return nil
            }
            if let official = backendState.threadWorkspaceRootHints[threadId], projectByPath[official] != nil {
                return official
            }
        }
        guard let cwd else { return nil }
        return bestProjectRoot(for: cwd, in: projectByPath.keys)
    }

    private func bestProjectRoot(for cwd: String, in roots: Dictionary<String, Project>.Keys) -> String? {
        let normalizedCwd = (cwd as NSString).expandingTildeInPath
        return roots
            .filter { root in
                normalizedCwd == root || normalizedCwd.hasPrefix(root.hasSuffix("/") ? root : root + "/")
            }
            .max { $0.count < $1.count }
    }

    private func resolveTitle(for thread: AgentThreadSummary) -> String {
        if let name = thread.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        let preview = thread.preview.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preview.isEmpty { return String(preview.prefix(60)) }
        return "Conversation"
    }

    func appendRuntimeStatusError(_ message: String) {
        guard case let .chat(chatId) = currentRoute else { return }
        appendErrorBubble(chatId: chatId, message: message)
    }

    private func writeE2EStateReportIfRequested() {
        guard
            let raw = ProcessInfo.processInfo.environment["CLAWIX_E2E_STATE_REPORT"],
            !raw.isEmpty
        else { return }
        if ProcessInfo.processInfo.environment["CLAWIX_E2E_HYDRATE_REPORT"] == "1" {
            for chatId in (chats + archivedChats).map(\.id) {
                hydrateHistoryIfNeeded(chatId: chatId, blocking: true)
            }
        }
        let projectsById = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        let payload: [String: Any] = [
            "projects": projects.map { ["name": $0.name, "path": $0.path] },
            "chats": chats.map { chat in
                let messages = chatStore.transcript(for: chat.id)?.messages ?? []
                return [
                    "threadId": chat.clawixThreadId ?? "",
                    "title": chat.title,
                    "projectPath": chat.projectId.flatMap { projectsById[$0]?.path } ?? "",
                    "isPinned": chat.isPinned,
                    "isArchived": chat.isArchived,
                    "messages": messages.map { message in
                        let renderedUser = message.role == .user
                            ? UserBubbleContent.parse(message.content, attachments: message.attachments)
                            : nil
                        return [
                            "role": message.role == .user ? "user" : "assistant",
                            "content": message.content,
                            "attachmentCount": message.attachments.count,
                            "renderedText": renderedUser?.text ?? message.content,
                            "renderedImageCount": renderedUser?.images.count ?? 0,
                            "workElapsedSeconds": message.workSummary.map { $0.elapsedSeconds(asOf: Date()) } ?? NSNull()
                        ] as [String: Any]
                    },
                    "toolRows": e2eToolRows(for: messages)
                ] as [String: Any]
            },
            "pinnedCount": chats.filter { $0.isPinned }.count,
            "archivedCount": chats.filter { $0.isArchived }.count,
            "featureVisibility": [
                "remoteMesh": FeatureFlags.shared.isVisible(.remoteMesh),
                "simulators": FeatureFlags.shared.isVisible(.simulators)
            ],
            "visibleSettingsCategories": SettingsCategory.visibleCases(isVisible: FeatureFlags.shared.isVisible).map(\.rawValue),
            "selectedMeshTarget": selectedMeshTarget.isLocal ? "local" : "peer"
        ]
        let url = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func e2eToolRows(for messages: [ChatMessage]) -> [[String: String]] {
        messages.flatMap { message in
            message.timeline.flatMap { entry -> [[String: String]] in
                guard case .tools(_, let items, let presentation) = entry else { return [] }
                let rows = presentation?.aggregateRows
                    ?? ToolTimelinePresentation.aggregateRows(for: items)
                return rows.map {
                    ["id": $0.id, "icon": $0.icon, "text": $0.text]
                }
            }
        }
    }

    private func openFirstE2EChatIfRequested() {
        guard ProcessInfo.processInfo.environment["CLAWIX_E2E_OPEN_FIRST_CHAT"] == "1",
              let first = chats.first
        else { return }
        currentRoute = .chat(first.id)
        hydrateHistoryIfNeeded(chatId: first.id, blocking: true)
    }

}
