import Foundation
import SwiftUI
import ClawixCore

extension AppState {
    func loadThreadsForProject(_ project: Project) async {
        await performProjectRefresh(project, reportErrors: true)
    }

    /// Queue a quiet best-effort refresh for a project row that has
    /// become visible in the sidebar. This only reads a tiny local
    /// snapshot page; runtime refreshes are reserved for explicit
    /// expansion so first paint never fans out across every project.
    func requestVisibleProjectRefresh(_ project: Project) {
        applyCachedProjectSnapshotIfNeeded(project)
    }

    /// Queue a user-initiated refresh for an expanded project. If a
    /// lower-priority visible refresh is already queued or running for
    /// the same project/path, replace it with this explicit request.
    func requestExpandedProjectRefresh(_ project: Project) {
        applyCachedProjectSnapshotIfNeeded(project)
        requestProjectRefresh(project, intent: .expanded)
    }

    func cancelProjectRefresh(_ project: Project) {
        guard let key = projectRefreshKey(for: project) else { return }
        cancelProjectRefresh(key: key)
    }

    /// Fetches a generous slice of a project's threads — enough to
    /// power the per-project "View all" popup — and merges them into
    /// `chats[]` so navigation lands on a fully populated chat. The
    /// sidebar accordion's per-project cap is intentionally tiny (10);
    /// this routine bypasses that cap and the debounce because the
    /// user explicitly asked to see everything in this folder.
    /// `useStateDbOnly` keeps the call latency down to a SQLite read.
    func loadAllThreadsForProject(_ project: Project) async {
        // Fixture / dummy mode: `chats[]` is already pre-loaded from
        // the seeded thread fixture, and the runtime backend that
        // would otherwise serve `listThreads` is ephemeral. Skipping
        // the round-trip avoids replacing the curated dataset with an
        // empty result on the first popup open.
        if AgentThreadStore.fixtureThreads() != nil { return }
        guard await ensureAgentRuntimeReady(reason: .manualRefresh),
              let clawix,
              case .ready = clawix.status else { return }
        do {
            let threads = try await clawix.listThreads(
                archived: false,
                cwd: project.path,
                limit: Self.popupFullProjectFetchLimit,
                useStateDbOnly: true
            )
            withAnimation(.easeOut(duration: 0.20)) {
                mergeThreads(threads)
            }
            persistProjectIndexFor(project)
        } catch {
            appendRuntimeStatusError("Could not load threads for project \(project.name): \(error)")
        }
    }

    private func applyCachedProjectSnapshotIfNeeded(_ project: Project) {
        guard snapshotEnabled, snapshotRepo.isAvailable() else { return }
        let key = projectSnapshotCacheKey(project)
        guard !loadedProjectSnapshotKeys.contains(key) else { return }
        loadedProjectSnapshotKeys.insert(key)

        let rows = snapshotRepo.loadProjectIndexed(
            projectId: project.id.uuidString,
            projectPath: project.path,
            limit: Self.snapshotPerProjectCap
        )
        applyCachedProjectSnapshotRows(rows, for: project)
    }

    private func projectSnapshotCacheKey(_ project: Project) -> String {
        if !project.path.isEmpty { return project.path }
        return project.id.uuidString
    }

    private func applyCachedProjectSnapshotRows(
        _ rows: [SidebarSnapshotProjectRow],
        for project: Project
    ) {
        guard !rows.isEmpty else { return }
        let pinIds = pinsRepo.orderedThreadIds()
        let pinnedSet = Set(pinIds)
        var indexByThread: [String: Int] = [:]
        var indexByChatId: [UUID: Int] = [:]
        for (idx, chat) in chats.enumerated() {
            if let threadId = chat.clawixThreadId {
                indexByThread[threadId] = idx
            }
            indexByChatId[chat.id] = idx
        }

        var updated = chats
        var changed = false
        for row in rows {
            guard row.archived == 0,
                  let id = UUID(uuidString: row.chatUuid)
            else { continue }
            let updatedAt = Date(timeIntervalSince1970: TimeInterval(row.updatedAt))
            let isPinned = pinnedSet.contains(row.threadId)
            if let idx = indexByThread[row.threadId] ?? indexByChatId[id] {
                var chat = updated[idx]
                chat.title = row.title
                chat.createdAt = updatedAt
                chat.clawixThreadId = row.threadId
                chat.projectId = project.id
                chat.isArchived = false
                chat.isPinned = isPinned
                chat.cwd = row.cwd
                updated[idx] = chat
                changed = true
            } else {
                let chat = Chat(
                    id: id,
                    title: row.title,
                    messages: [],
                    createdAt: updatedAt,
                    clawixThreadId: row.threadId,
                    rolloutPath: nil,
                    historyHydrated: false,
                    hasActiveTurn: false,
                    projectId: project.id,
                    isArchived: false,
                    isPinned: isPinned,
                    hasUnreadCompletion: false,
                    cwd: row.cwd,
                    hasGitRepo: false,
                    branch: nil,
                    availableBranches: [],
                    uncommittedFiles: nil
                )
                indexByThread[row.threadId] = updated.count
                indexByChatId[id] = updated.count
                updated.append(chat)
                changed = true
            }
        }
        guard changed else { return }
        updated.sort { $0.createdAt > $1.createdAt }
        chats = updated
        let threadToChat = Dictionary(uniqueKeysWithValues: chats.compactMap { chat in
            chat.clawixThreadId.map { ($0, chat.id) }
        })
        pinnedOrder = pinIds.compactMap { threadToChat[$0] }
        PerfSignpost.uiSidebar.event("project_snapshot.rows", rows.count)
    }

    private func requestProjectRefresh(_ project: Project, intent: ProjectRefreshIntent) {
        if let key = projectRefreshKey(for: project) {
            guard var job = projectRefreshJobs[key] else { return }
            if job.intent.rawValue >= intent.rawValue {
                return
            }
            job.intent = intent
            job.project = project
            if let task = job.task {
                task.cancel()
                job.task = nil
                job.token = nil
            } else {
                projectRefreshQueue.removeAll { $0 == key }
            }
            projectRefreshJobs[key] = job
            enqueueProjectRefresh(key, intent: intent)
            drainProjectRefreshQueue()
            return
        }

        guard !isProjectRefreshDebounced(project) else { return }
        projectRefreshJobs[project.id] = ProjectRefreshJob(
            project: project,
            intent: intent,
            token: nil,
            task: nil
        )
        if !project.path.isEmpty {
            projectRefreshIdsByPath[project.path] = project.id
        }
        enqueueProjectRefresh(project.id, intent: intent)
        drainProjectRefreshQueue()
    }

    private func enqueueProjectRefresh(_ key: UUID, intent: ProjectRefreshIntent) {
        projectRefreshQueue.removeAll { $0 == key }
        switch intent {
        case .visible:
            projectRefreshQueue.append(key)
        case .expanded:
            projectRefreshQueue.insert(key, at: 0)
        }
    }

    func drainProjectRefreshQueue() {
        var running = projectRefreshJobs.values.filter { $0.task != nil }.count
        while running < Self.projectRefreshConcurrency,
              let key = projectRefreshQueue.first {
            projectRefreshQueue.removeFirst()
            guard var job = projectRefreshJobs[key] else { continue }
            if !canRefreshProjectsFromRuntime {
                projectRefreshQueue.insert(key, at: 0)
                return
            }
            if isProjectRefreshDebounced(job.project) {
                removeProjectRefreshJob(key: key)
                continue
            }

            let token = UUID()
            let project = job.project
            let intent = job.intent
            job.token = token
            job.task = Task<Void, Never>(priority: intent.priority) { @MainActor [weak self] in
                guard let self else { return }
                defer { self.finishProjectRefresh(key: key, token: token) }
                await self.performProjectRefresh(project, reportErrors: intent.reportErrors)
            }
            projectRefreshJobs[key] = job
            running += 1
        }
    }

    private func performProjectRefresh(_ project: Project, reportErrors: Bool) async {
        guard AgentThreadStore.fixtureThreads() == nil else { return }
        guard canRefreshProjectsFromRuntime else { return }
        guard !isProjectRefreshDebounced(project) else { return }
        do {
            let threads = try await fetchProjectThreads(project, limit: Self.snapshotPerProjectCap)
            try Task.checkCancellation()
            lastProjectRefreshAt[project.path] = Date()
            withAnimation(.easeOut(duration: 0.20)) {
                self.mergeThreads(threads)
            }
            self.persistProjectIndexFor(project)
        } catch is CancellationError {
            // Canceled visible/expanded refreshes are expected when a
            // row disappears or an explicit expand supersedes a lazy
            // visible request.
        } catch {
            if reportErrors {
                appendRuntimeStatusError("Could not load threads for project \(project.name): \(error)")
            }
        }
    }

    private var canRefreshProjectsFromRuntime: Bool {
        if projectThreadListLoader != nil { return true }
        guard let clawix, case .ready = clawix.status else { return false }
        return true
    }

    private func fetchProjectThreads(_ project: Project, limit: Int) async throws -> [AgentThreadSummary] {
        if let projectThreadListLoader {
            return try await projectThreadListLoader(project, limit)
        }
        guard let clawix, case .ready = clawix.status else { return [] }
        return try await clawix.listThreads(
            archived: false,
            cwd: project.path,
            limit: limit,
            useStateDbOnly: true
        )
    }

    private func isProjectRefreshDebounced(_ project: Project) -> Bool {
        if let last = lastProjectRefreshAt[project.path],
           Date().timeIntervalSince(last) < Self.projectRefreshDebounce {
            return true
        }
        return false
    }

    private func projectRefreshKey(for project: Project) -> UUID? {
        if projectRefreshJobs[project.id] != nil {
            return project.id
        }
        if !project.path.isEmpty,
           let key = projectRefreshIdsByPath[project.path],
           projectRefreshJobs[key] != nil {
            return key
        }
        return nil
    }

    private func finishProjectRefresh(key: UUID, token: UUID) {
        guard let job = projectRefreshJobs[key], job.token == token else { return }
        removeProjectRefreshJob(key: key)
        drainProjectRefreshQueue()
    }

    private func cancelProjectRefresh(key: UUID) {
        projectRefreshJobs[key]?.task?.cancel()
        removeProjectRefreshJob(key: key)
    }

    private func removeProjectRefreshJob(key: UUID) {
        guard let job = projectRefreshJobs.removeValue(forKey: key) else { return }
        projectRefreshQueue.removeAll { $0 == key }
        if !job.project.path.isEmpty, projectRefreshIdsByPath[job.project.path] == key {
            projectRefreshIdsByPath.removeValue(forKey: job.project.path)
        }
    }

    private func cancelAllProjectRefreshes() {
        for job in projectRefreshJobs.values {
            job.task?.cancel()
        }
        projectRefreshJobs.removeAll()
        projectRefreshIdsByPath.removeAll()
        projectRefreshQueue.removeAll()
    }

    /// Persists the in-memory chats for a single project to
    /// `sidebar_snapshot_project`. Called after a per-project refresh
    /// so the next cold start hydrates this project from the freshest
    /// data we have seen, without rewriting every other project's rows.
    private func persistProjectIndexFor(_ project: Project) {
        guard snapshotEnabled else { return }
        let now = Int64(Date().timeIntervalSince1970)
        let cap = Self.snapshotPerProjectCap
        var bucket: [SidebarSnapshotProjectRow] = []
        for chat in chats where !chat.isArchived
            && chat.projectId == project.id {
            guard let threadId = chat.clawixThreadId else { continue }
            bucket.append(SidebarSnapshotProjectRow(
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
            ))
        }
        bucket.sort { $0.updatedAt > $1.updatedAt }
        let trimmed = Array(bucket.prefix(cap))
        let projectId = project.id.uuidString
        let projectPath = project.path
        let repo = snapshotRepo
        Task.detached(priority: .background) {
            repo.replaceProjectIndexFor(projectId: projectId, projectPath: projectPath, rows: trimmed)
        }
    }

    func scheduleSidebarSnapshotProjectIDBackfill() {
        let backfill = SidebarSnapshotProjectIDBackfill()
        sidebarSnapshotProjectIDBackfillTask?.cancel()
        sidebarSnapshotProjectIDBackfillTask = Task.detached(priority: .utility) {
            await backfill.runUntilComplete()
        }
    }
}
