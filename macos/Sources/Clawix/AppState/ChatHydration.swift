import Foundation
import SwiftUI
import ClawixCore

private func scheduleChatMarkdownPrewarm(
    messages: [ChatMessage],
    timelineEntryLimit: Int = 0
) {
    Task.detached(priority: .utility) {
        await ChatMarkdownPrewarmer.prewarm(
            messages: messages,
            timelineEntryLimit: timelineEntryLimit
        )
    }
}

extension AppState {
    // MARK: - Clawix bridge helpers

    /// CWD reported to thread/start. Falls back to $HOME so Clawix never
    /// refuses to start. Order: current chat's project > selectedProject > $HOME.
    var threadCwd: String {
        if case let .chat(id) = currentRoute,
           let chat = chat(byId: id),
           let pid = chat.projectId,
           let proj = projects.first(where: { $0.id == pid }) {
            let expanded = (proj.path as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) { return expanded }
        }
        if let project = selectedProject {
            let expanded = (project.path as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) {
                return expanded
            }
        }
        return ClawixAgentBackendRoutes.defaultThreadCwd()
    }

    /// Maps the dropdown label ("5.5", "5.4 Mini", …) to a Clawix slug.
    var clawixModelSlug: String? {
        guard selectedAgentRuntime == .codex else { return nil }
        let raw = selectedModel.lowercased().replacingOccurrences(of: " ", with: "-")
        return "gpt-\(raw)"
    }

    var clawixEffort: String? {
        selectedIntelligence.clawixEffort
    }

    /// "fast" → priority queue (1.5× faster, higher usage).
    /// `nil` → default tier. The schema also accepts "flex" but the
    /// composer does not expose it today.
    var clawixServiceTier: String? {
        switch selectedSpeed {
        case .standard: return nil
        case .fast:     return "fast"
        }
    }

    @discardableResult
    func ensureSkillsStoreLoaded() -> SkillsStore {
        if let store = skillsStore {
            store.loadFullCatalogIfNeeded()
            return store
        }
        let store = makeSkillsStore(true, .fullCatalog)
        skillsStore = store
        return store
    }

    @discardableResult
    func ensureSkillsActiveStateLoaded() async -> SkillsStore {
        if let store = skillsStore {
            await store.loadActiveStateIfNeededAsync()
            return store
        }
        let store = makeSkillsStore(false, .none)
        skillsStore = store
        await store.loadActiveStateIfNeededAsync()
        return store
    }

    /// Resolve the active skills set for a chat at the moment we're
    /// about to dispatch a `thread/start` or `turn/start`. This loads only
    /// the compact active-state record unless the full Skills catalog has
    /// already been opened.
    func skillsActiveSnapshot(for chatId: UUID) async -> [ActiveSkill]? {
        let store = await ensureSkillsActiveStateLoaded()
        let projectId = chat(byId: chatId)?.projectId?.uuidString
        let states = store.resolveActive(projectId: projectId, chatId: chatId)
        guard !states.isEmpty else { return nil }
        return states.map { $0.toWire() }
    }

    func ensureSelectedChat(triggerHistoryHydration: Bool = true) {
        guard case let .chat(id) = currentRoute,
              let chat = chat(byId: id) else { return }
        if triggerHistoryHydration && shouldHydrateHistory(chat) {
            hydrateHistoryIfNeeded(chatId: id)
        }
    }

    private func shouldHydrateHistory(_ chat: Chat) -> Bool {
        if !chat.historyHydrated { return true }
        let transcriptIsEmpty = chatStore.transcript(for: chat.id)?.messageIds.isEmpty ?? true
        return transcriptIsEmpty && (chat.rolloutPath != nil || chat.clawixThreadId != nil)
    }

    /// Find a chat by id across both the active and archived lists. The
    /// sidebar's archived section opens chats via the same `.chat(id)`
    /// route, so any view that resolves the current chat must accept ids
    /// from either bucket.
    func chat(byId id: UUID) -> Chat? {
        if let chat = chatStore.snapshot(id: id) { return chat }
        if let chat = chats.first(where: { $0.id == id }) { return chat }
        return archivedChats.first(where: { $0.id == id })
    }

    /// Apply `mutate` to whichever array currently holds the chat. No-op
    /// if the id is unknown. Used by hydration paths that need to write
    /// back into the chat regardless of its archived state.
    private func mutateChat(id: UUID, _ mutate: (inout Chat) -> Void) {
        guard var snapshot = chat(byId: id) else { return }
        mutate(&snapshot)
        chatStore.upsert(snapshot, archived: snapshot.isArchived)
        syncLegacyChatFromStore(chatId: id)
    }

    /// True when the thread list is driven by a local fixture / dummy
    /// session / backend-disabled run, i.e. there is no live ClawJS
    /// sessions service to hydrate history from and every chat carries
    /// its rollout path directly. Computed once from the launch
    /// environment, which never changes during a process lifetime.
    static let prefersLocalRolloutHydration: Bool = {
        let env = ProcessInfo.processInfo.environment
        if env["CLAWIX_DISABLE_BACKEND"] == "1" { return true }
        if env["CLAWIX_DUMMY_MODE"] == "1" { return true }
        if let fixture = env["CLAWIX_THREAD_FIXTURE"], !fixture.isEmpty { return true }
        return false
    }()

    func hydrateHistoryIfNeeded(chatId: UUID, blocking: Bool = false) {
        guard let chat = chat(byId: chatId), shouldHydrateHistory(chat) else { return }
        if FeatureFlags.shared.isVisible(.git), !chat.hasGitRepo, let cwd = chat.cwd {
            if blocking {
                applyGitSnapshot(GitInspector.inspect(cwd: cwd), chatId: chatId)
            } else {
                scheduleGitInspection(chatId: chatId, cwd: cwd)
            }
        }
        // Fixture-driven runs (dummy session, showcase, E2E) and the
        // backend-disabled mode have no ClawJS sessions service to ask:
        // the thread list comes from a local fixture and every chat
        // already carries its rollout path. Read history straight from
        // that rollout so it loads instantly at full fidelity. Routing
        // these through the sessions client instead made every chat hang
        // on ~8 retries (~10s of backoff) and then surface a spurious
        // "service unavailable" error bubble, because the service is not
        // running and the codex-home fallback locator finds nothing.
        if !blocking,
           let path = chat.rolloutPath,
           FileManager.default.fileExists(atPath: path.path) {
            hydrateHistoryFromLocalRollout(path: path, chatId: chatId, blocking: false)
        } else if Self.prefersLocalRolloutHydration, let path = chat.rolloutPath {
            hydrateHistoryFromLocalRollout(path: path, chatId: chatId, blocking: blocking)
        } else if let threadId = chat.clawixThreadId {
            hydrateHistoryFromClawJSSessions(threadId: threadId, chatId: chatId, blocking: blocking)
        } else if let path = chat.rolloutPath {
            hydrateHistoryFromLocalRollout(path: path, chatId: chatId, blocking: blocking)
        }
        if blocking, let threadId = chat.clawixThreadId, let clawix {
            Task { @MainActor in
                RenderProbe.mark(
                    "ChatRuntimeAttachBlockingHydration",
                    fields: ["chat": chat.id.uuidString]
                )
                await clawix.attach(chatId: chat.id, threadId: threadId)
            }
        }
    }

    private func hydrateHistoryFromLocalRollout(path: URL, chatId: UUID, blocking: Bool) {
        // Mac UI path (`blocking == false`): read off the main actor AND
        // only the trailing window of the JSONL so a multi-hundred-MB
        // rollout doesn't stall hydration. Fixture/backend-disabled runs
        // also use this path because there is intentionally no session
        // service to ask.
        if blocking {
            applyRolloutResult(RolloutReader.readTailWithStatus(path: path), chatId: chatId)
        } else {
            guard localRolloutHydrationTasks[chatId] == nil else { return }
            RenderProbe.mark(
                "ChatHydrationLocalStart",
                fields: [
                    "chat": chatId.uuidString,
                    "path": path.lastPathComponent
                ]
            )
            localRolloutHydrationTasks[chatId] = Task.detached(priority: .userInitiated) { [weak self] in
                let readStarted = CFAbsoluteTimeGetCurrent()
                let result = RolloutReader.readTailWithStatus(path: path)
                let readMs = (CFAbsoluteTimeGetCurrent() - readStarted) * 1000
                RenderProbe.mark(
                    "ChatHydrationLocalRead",
                    fields: [
                        "chat": chatId.uuidString,
                        "entries": "\(result.entries.count)",
                        "parsedRecords": "\(result.parsedRecordCount)",
                        "readMode": result.readMode,
                        "readEntireFile": "\(result.readEntireFile)",
                        "totalBytes": "\(result.totalFileBytes)",
                        "readBytes": "\(result.readBytes)",
                        "requestedMaxBytes": "\(result.requestedMaxBytes)",
                        "alignedOffset": "\(result.alignedOffset)",
                        "hasMore": "\(result.hasMoreBefore)",
                        "ms": String(format: "%.1f", readMs)
                    ]
                )
                let convertStarted = CFAbsoluteTimeGetCurrent()
                let messages = rolloutChatMessages(from: result)
                let convertMs = (CFAbsoluteTimeGetCurrent() - convertStarted) * 1000
                scheduleChatMarkdownPrewarm(messages: messages)
                RenderProbe.mark(
                    "ChatHydrationLocalConvert",
                    fields: [
                        "chat": chatId.uuidString,
                        "messages": "\(messages.count)",
                        "ms": String(format: "%.1f", convertMs)
                    ]
                )
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.localRolloutHydrationTasks[chatId] = nil
                    RenderProbe.mark(
                        "ChatHydrationLocalApply",
                        fields: [
                            "chat": chatId.uuidString,
                            "messages": "\(messages.count)"
                        ]
                    )
                    let applyStarted = CFAbsoluteTimeGetCurrent()
                    self.messagesPaginationByChat[chatId] = ChatPagination(
                        oldestKnownId: result.entries.first?.id.uuidString,
                        hasMore: result.hasMoreBefore,
                        loadingOlder: false
                    )
                    if let plan = result.latestPlan {
                        self.planByChat[chatId] = plan
                    }
                    self.applyRolloutMessages(
                        messages,
                        lastTurnInterrupted: result.lastTurnInterrupted,
                        chatId: chatId
                    )
                    let applyMs = (CFAbsoluteTimeGetCurrent() - applyStarted) * 1000
                    RenderProbe.mark(
                        "ChatHydrationLocalApplyEnd",
                        fields: [
                            "chat": chatId.uuidString,
                            "ms": String(format: "%.1f", applyMs)
                        ]
                    )
                }
            }
        }
    }

    private func scheduleGitInspection(chatId: UUID, cwd: String) {
        guard gitInspectionTasks[chatId] == nil else { return }
        gitInspectionTasks[chatId] = Task.detached(priority: .utility) { [weak self] in
            let git = GitInspector.inspect(cwd: cwd)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.gitInspectionTasks[chatId] = nil
                guard self.chat(byId: chatId)?.cwd == cwd else { return }
                self.applyGitSnapshot(git, chatId: chatId)
            }
        }
    }

    private func applyGitSnapshot(_ git: GitSnapshot, chatId: UUID) {
        mutateChat(id: chatId) { c in
            c.hasGitRepo = git.hasRepo
            c.branch = git.branch
            c.availableBranches = git.branches
            c.uncommittedFiles = git.uncommittedFiles
        }
    }

    private func applyRolloutResult(_ result: RolloutReader.ReadResult, chatId: UUID) {
        messagesPaginationByChat[chatId] = ChatPagination(
            oldestKnownId: result.entries.first?.id.uuidString,
            hasMore: result.hasMoreBefore,
            loadingOlder: false
        )
        if let plan = result.latestPlan {
            planByChat[chatId] = plan
        }
        applyRolloutMessages(
            rolloutChatMessages(from: result),
            lastTurnInterrupted: result.lastTurnInterrupted,
            chatId: chatId
        )
    }

    private func activeStreamingMessageIds(chatId: UUID) -> Set<UUID> {
        guard let transcript = chatStore.transcript(for: chatId) else { return [] }
        return Set(transcript.messages.compactMap { message in
            message.role == .assistant && !message.streamingFinished ? message.id : nil
        })
    }

    private func hydrateHistoryFromClawJSSessions(threadId: String, chatId: UUID, blocking: Bool) {
        if blocking {
            // The bridge entry point is synchronous. Do not fall back to
            // scanning Codex rollouts here; the daemon/session sidecar is the
            // boundary. The async UI path below will hydrate the chat when it
            // can reach the service.
            return
        }
        guard sessionHistoryHydrationTasks[chatId] == nil else { return }
        if scheduleCodexRolloutFallbackBeforeSession(threadId: threadId, chatId: chatId) {
            return
        }
        startClawJSSessionHydrationTask(threadId: threadId, chatId: chatId)
    }

    private func scheduleCodexRolloutFallbackBeforeSession(threadId: String, chatId: UUID) -> Bool {
        if let localPath = chat(byId: chatId)?.rolloutPath,
           FileManager.default.fileExists(atPath: localPath.path) {
            hydrateHistoryFromLocalRollout(path: localPath, chatId: chatId, blocking: false)
            return true
        }
        if let cachedPath = codexRolloutPathByThreadId[threadId],
           FileManager.default.fileExists(atPath: cachedPath.path) {
            mutateChat(id: chatId) { c in
                c.rolloutPath = cachedPath
            }
            hydrateHistoryFromLocalRollout(path: cachedPath, chatId: chatId, blocking: false)
            return true
        }
        if missingCodexRolloutPathThreadIds.contains(threadId) {
            return false
        }

        let locator = codexRolloutLocator
        sessionHistoryHydrationTasks[chatId] = Task.detached(priority: .userInitiated) { [weak self] in
            let locateStarted = CFAbsoluteTimeGetCurrent()
            let path = CodexRolloutLocator.findLikelyDayMatch(threadId: threadId) ?? locator(threadId)
            guard let path else {
                let locateMs = (CFAbsoluteTimeGetCurrent() - locateStarted) * 1000
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.sessionHistoryHydrationTasks[chatId] = nil
                    self.missingCodexRolloutPathThreadIds.insert(threadId)
                    RenderProbe.mark(
                        "ChatHydrationLocalFallbackPathMissing",
                        fields: [
                            "chat": chatId.uuidString,
                            "thread": threadId,
                            "ms": String(format: "%.1f", locateMs)
                        ]
                    )
                    self.startClawJSSessionHydrationTask(threadId: threadId, chatId: chatId)
                }
                return
            }

            let locateMs = (CFAbsoluteTimeGetCurrent() - locateStarted) * 1000
            let readStarted = CFAbsoluteTimeGetCurrent()
            let result = RolloutReader.readTailWithStatus(path: path)
            let messages = rolloutChatMessages(from: result)
            let readMs = (CFAbsoluteTimeGetCurrent() - readStarted) * 1000
            scheduleChatMarkdownPrewarm(messages: messages)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.sessionHistoryHydrationTasks[chatId] = nil
                guard self.chat(byId: chatId)?.historyHydrated == false else { return }
                self.codexRolloutPathByThreadId[threadId] = path
                self.mutateChat(id: chatId) { c in
                    c.rolloutPath = path
                }
                RenderProbe.mark(
                    "ChatHydrationLocalFallbackBeforeSession",
                    fields: [
                        "chat": chatId.uuidString,
                        "thread": threadId,
                        "locateMs": String(format: "%.1f", locateMs),
                        "readMs": String(format: "%.1f", readMs)
                    ]
                )
                self.messagesPaginationByChat[chatId] = ChatPagination(
                    oldestKnownId: result.entries.first?.id.uuidString,
                    hasMore: result.hasMoreBefore,
                    loadingOlder: false
                )
                if let plan = result.latestPlan {
                    self.planByChat[chatId] = plan
                }
                self.applyRolloutMessages(
                    messages,
                    lastTurnInterrupted: result.lastTurnInterrupted,
                    chatId: chatId
                )
            }
        }
        return true
    }

    private func startClawJSSessionHydrationTask(threadId: String, chatId: UUID) {
        guard sessionHistoryHydrationTasks[chatId] == nil else { return }
        sessionHistoryHydrationTasks[chatId] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.sessionHistoryHydrationTasks[chatId] = nil }
            if await self.hydrateFromCodexRolloutFallback(threadId: threadId, chatId: chatId) {
                RenderProbe.mark(
                    "ChatHydrationLocalFallbackBeforeSession",
                    fields: [
                        "chat": chatId.uuidString,
                        "thread": threadId
                    ]
                )
                return
            }
            do {
                let page = try await self.loadClawJSSessionMessageTail(sessionId: threadId)
                let records = page.records
                if records.isEmpty, await self.hydrateFromCodexRolloutFallback(threadId: threadId, chatId: chatId) {
                    return
                }
                self.messagesPaginationByChat[chatId] = ChatPagination(
                    oldestKnownId: records.first?.id,
                    oldestOffset: page.messageOffset,
                    hasMore: page.hasMore,
                    loadingOlder: false
                )
                let messages = records.map(Self.chatMessage(fromClawJSSessionMessage:))
                scheduleChatMarkdownPrewarm(messages: messages)
                self.applyRolloutMessages(
                    messages,
                    lastTurnInterrupted: false,
                    chatId: chatId
                )
            } catch {
                if await self.hydrateFromCodexRolloutFallback(threadId: threadId, chatId: chatId) {
                    return
                }
                guard self.chat(byId: chatId)?.historyHydrated == false else { return }
                self.recordClawJSSessionHydrationFailure(
                    threadId: threadId,
                    chatId: chatId,
                    error: error
                )
            }
        }
    }

    private func recordClawJSSessionHydrationFailure(threadId: String, chatId: UUID, error: Error) {
        let message = "Could not load ClawJS session history: \(error.localizedDescription)"
        UserFacingFailure.classify(message).log(surface: "chat.historyHydration")
        RenderProbe.mark(
            "ChatHydrationSessionFailed",
            fields: [
                "chat": chatId.uuidString,
                "thread": threadId,
                "error": String(describing: type(of: error))
            ]
        )
    }

    private func hydrateFromCodexRolloutFallback(threadId: String, chatId: UUID) async -> Bool {
        // Prefer the chat's own rollout path when it already has one and
        // the file exists on disk. Fixture/dummy threads always carry it,
        // and real chats often cache it too; reading it directly renders
        // full history even when the sessions service is unreachable,
        // instead of re-scanning the codex home for a path we already know.
        if let localPath = chat(byId: chatId)?.rolloutPath,
           FileManager.default.fileExists(atPath: localPath.path) {
            let result = await Task.detached(priority: .userInitiated) {
                RolloutReader.readTailWithStatus(path: localPath)
            }.value
            applyRolloutResult(result, chatId: chatId)
            return true
        }
        guard let path = await resolveCodexRolloutPath(threadId: threadId) else { return false }
        let result = await Task.detached(priority: .userInitiated) {
            RolloutReader.readTailWithStatus(path: path)
        }.value
        let messages = rolloutChatMessages(from: result)
        scheduleChatMarkdownPrewarm(messages: messages)
        mutateChat(id: chatId) { c in
            c.rolloutPath = path
        }
        messagesPaginationByChat[chatId] = ChatPagination(
            oldestKnownId: result.entries.first?.id.uuidString,
            hasMore: result.hasMoreBefore,
            loadingOlder: false
        )
        if let plan = result.latestPlan {
            planByChat[chatId] = plan
        }
        applyRolloutMessages(
            messages,
            lastTurnInterrupted: result.lastTurnInterrupted,
            chatId: chatId
        )
        return true
    }

    private func resolveCodexRolloutPath(threadId: String) async -> URL? {
        if let cached = codexRolloutPathByThreadId[threadId] {
            return cached
        }
        if missingCodexRolloutPathThreadIds.contains(threadId) {
            return nil
        }
        let locator = codexRolloutLocator
        let found = await Task.detached(priority: .utility) {
            locator(threadId)
        }.value
        if let found {
            codexRolloutPathByThreadId[threadId] = found
        } else {
            missingCodexRolloutPathThreadIds.insert(threadId)
        }
        return found
    }

    private func loadClawJSSessionMessageTail(sessionId: String) async throws -> (records: [ClawJSSessionsClient.MessageRecord], hasMore: Bool, messageOffset: Int) {
        var delay = sessionHistoryHydrationInitialDelayNanos
        let attempts = max(1, sessionHistoryHydrationAttempts)
        var lastError: Error?
        for attempt in 1...attempts {
            do {
                let client = clawJSSessionsClientFactory()
                let hydrated = try await client.hydrateSession(
                    id: sessionId,
                    messageLimit: bridgeInitialPageLimit,
                    recent: true,
                    summaryLimit: 20,
                    includeEvents: false
                )
                return (
                    hydrated.messages,
                    hydrated.hasOlderMessages,
                    hydrated.messageOffset
                )
            } catch {
                lastError = error
                guard attempt < attempts, Self.shouldRetryClawJSSessionHistory(error) else {
                    throw error
                }
                try? await Task.sleep(nanoseconds: delay)
                delay = min(delay * 2, 2_000_000_000)
            }
        }
        throw lastError ?? ClawJSSessionsClient.Error.serviceNotReady
    }

    private static func shouldRetryClawJSSessionHistory(_ error: Error) -> Bool {
        if let sessionsError = error as? ClawJSSessionsClient.Error {
            switch sessionsError {
            case .serviceNotReady, .transport:
                return true
            case .invalidURL, .http, .decoding, .encoding:
                return false
            }
        }
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        return [
            NSURLErrorCannotConnectToHost,
            NSURLErrorCannotFindHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorTimedOut,
        ].contains(nsError.code)
    }

    private static func chatMessage(fromClawJSSessionMessage record: ClawJSSessionsClient.MessageRecord) -> ChatMessage {
        let seconds = record.timestamp > 10_000_000_000 ? Double(record.timestamp) / 1000.0 : Double(record.timestamp)
        return ChatMessage(
            role: record.role == "user" ? .user : .assistant,
            content: record.contentText,
            reasoningText: "",
            streamingFinished: record.streamingState != "streaming",
            timestamp: Date(timeIntervalSince1970: seconds)
        )
    }

    private func applyRolloutMessages(
        _ messages: [ChatMessage],
        lastTurnInterrupted: Bool,
        chatId: UUID
    ) {
        chatStore.replaceMessageTail(
            chatId: chatId,
            messages,
            limit: bridgeInitialPageLimit,
            keeping: activeStreamingMessageIds(chatId: chatId)
        )
        chatStore.updateSummary(id: chatId) { summary in
            summary.lastTurnInterrupted = lastTurnInterrupted
            summary.historyHydrated = true
            summary.lastMessageAt = messages.last?.timestamp ?? summary.lastMessageAt
        }
        syncLegacyChatFromStore(chatId: chatId)
    }

    func bridgeSessionId(forChatId chatId: UUID) -> String {
        guard let chat = chat(byId: chatId),
              let threadId = chat.clawixThreadId,
              let wire = cachedWireSessions.first(where: { $0.threadId == threadId })
        else { return chatId.uuidString }
        return wire.id
    }

    private func localChatId(forBridgeSessionId sessionId: String) -> UUID? {
        if let id = UUID(uuidString: sessionId), chatStore.summary(id: id) != nil {
            return id
        }
        guard let threadId = cachedWireSessions.first(where: { $0.id == sessionId })?.threadId else {
            return UUID(uuidString: sessionId)
        }
        return chatByThreadId(chats)[threadId]?.id
            ?? chatByThreadId(archivedChats)[threadId]?.id
            ?? UUID(uuidString: sessionId)
    }


    /// Bridge entry point. Hydrates a chat's history from its rollout
    /// file the first time the iPhone opens it, mirroring what the Mac
    /// UI does the moment a chat row is clicked. Without this the
    /// iPhone gets `messagesSnapshot([])` for every `notLoaded` thread
    /// and the user only sees the "no messages loaded" empty state.
    /// Idempotent: subsequent calls for the same chat are no-ops.
    func hydrateHistoryFromBridge(chatId: UUID) {
        guard chat(byId: chatId) != nil else { return }
        // Bridge response composes inline; the iPhone needs messages
        // before this returns, so this call site keeps the synchronous
        // rollout read.
        hydrateHistoryIfNeeded(chatId: chatId, blocking: true)
    }

    func applyDaemonChats(_ wireChats: [WireSession]) {
        let uniqueWireChats = boundedSidebarWireSessions(deduplicatedWireSessions(wireChats))
        if uniqueWireChats.isEmpty, shouldPreserveLocalSidebarAgainstEmptyCanonicalSource() {
            return
        }
        if shouldMergePartialDaemonChatSnapshot(uniqueWireChats) {
            for wire in uniqueWireChats {
                applyDaemonChat(wire)
            }
            return
        }
        cachedWireSessions = uniqueWireChats
        // Refresh `projects` from the latest backendState before
        // resolving each wire chat's project: the daemon may have
        // delivered a snapshot that references workspace roots Codex
        // has just learned about, and `chat(from:wire,old:)` reads
        // through the in-memory `projects` array.
        projects = mergedProjects()
        let oldById = Dictionary(uniqueKeysWithValues: chats.map { ($0.id, $0) })
        let oldArchivedById = Dictionary(uniqueKeysWithValues: archivedChats.map { ($0.id, $0) })
        // Wire chats from the daemon mint their own UUIDs each
        // process restart, so matching `old` only by UUID misses
        // every persisted chat. Add a thread-id index so we recover
        // any per-chat metadata (messages, hasGitRepo, branch, etc.)
        // the GUI had cached against the previous daemon UUID.
        let oldByThreadId = chatByThreadId(chats)
        let oldArchivedByThreadId = chatByThreadId(archivedChats)
        func resolveOld(for wire: WireSession) -> Chat? {
            if let id = UUID(uuidString: wire.id) {
                if let hit = oldById[id] ?? oldArchivedById[id] { return hit }
            }
            if let tid = wire.threadId {
                return oldByThreadId[tid] ?? oldArchivedByThreadId[tid]
            }
            return nil
        }
        var nextChats: [Chat] = uniqueWireChats.compactMap { wire in
            guard !wire.isArchived else { return nil }
            return chat(from: wire, old: resolveOld(for: wire))
        }
        var nextArchived: [Chat] = uniqueWireChats.compactMap { wire in
            guard wire.isArchived else { return nil }
            return chat(from: wire, old: resolveOld(for: wire))
        }
        if case let .chat(id) = currentRoute,
           let selected = chat(byId: id),
           let threadId = selected.clawixThreadId,
           !uniqueWireChats.contains(where: { $0.threadId?.caseInsensitiveCompare(threadId) == .orderedSame }) {
            if selected.isArchived {
                if !nextArchived.contains(where: { $0.id == selected.id || $0.clawixThreadId == selected.clawixThreadId }) {
                    nextArchived.insert(selected, at: 0)
                }
            } else if !nextChats.contains(where: { $0.id == selected.id || $0.clawixThreadId == selected.clawixThreadId }) {
                nextChats.insert(selected, at: 0)
            }
        }
        // Fast path: the daemon resends the same chat snapshot on every
        // streaming delta. When nothing actually changed, skip the
        // assignment (which would trigger `objectWillChange` and fan
        // out a full sidebar re-render) and skip the pinnedOrder
        // recompute too (pins haven't moved if the chat list is
        // identical).
        if chats == nextChats && archivedChats == nextArchived { return }
        // Identity-only diff: same ids in the same order, only some
        // slot's contents differ. Mutate those slots in place so each
        // updated row publishes a single change instead of triggering
        // an animated insert/remove transition on every row of the
        // sidebar via `withAnimation` over a wholesale array copy.
        let sameIdentity = chats.count == nextChats.count
            && zip(chats, nextChats).allSatisfy { $0.id == $1.id }
            && archivedChats.count == nextArchived.count
            && zip(archivedChats, nextArchived).allSatisfy { $0.id == $1.id }
        if sameIdentity {
            for idx in nextChats.indices where chats[idx] != nextChats[idx] {
                chats[idx] = nextChats[idx]
            }
            for idx in nextArchived.indices where archivedChats[idx] != nextArchived[idx] {
                archivedChats[idx] = nextArchived[idx]
            }
        } else {
            // Structural diff (insert / remove / reorder). Animate so
            // rows slide in/out via the accordion's per-row transition.
            withAnimation(.easeOut(duration: 0.20)) {
                chats = nextChats
                archivedChats = nextArchived
            }
        }
        // Recompute `pinnedOrder` against the freshly applied chats:
        // either honour the user's local pin order (if they've taken
        // control) or fall back to the external session state. Without
        // this the Pinned section would render unsorted because the
        // daemon's wire chats have brand-new UUIDs every reconnect.
        let pinIds = pinsRepo.orderedThreadIds()
        let threadToChat = chatIdByThreadId(chats)
        pinnedOrder = pinIds.compactMap { threadToChat[$0] }
    }

    private func shouldMergePartialDaemonChatSnapshot(_ wireChats: [WireSession]) -> Bool {
        let incomingActiveCount = wireChats.lazy.filter { !$0.isArchived }.count
        guard incomingActiveCount > 0 else { return false }
        let existingActiveCount = chats.lazy.filter { !$0.isArchived }.count
        guard existingActiveCount > incomingActiveCount else { return false }
        return shouldPreserveLocalSidebarAgainstEmptyCanonicalSource()
    }

    func applyDaemonChat(_ wire: WireSession) {
        guard let id = UUID(uuidString: wire.id) else { return }
        func sameWireIdentity(_ other: WireSession) -> Bool {
            if other.id == wire.id { return true }
            guard let incomingThreadId = wire.threadId,
                  let existingThreadId = other.threadId
            else { return false }
            return incomingThreadId.caseInsensitiveCompare(existingThreadId) == .orderedSame
        }
        func sameChatIdentity(_ chat: Chat) -> Bool {
            if chat.id == id { return true }
            guard let incomingThreadId = wire.threadId,
                  let existingThreadId = chat.clawixThreadId
            else { return false }
            return incomingThreadId.caseInsensitiveCompare(existingThreadId) == .orderedSame
        }

        if let idx = cachedWireSessions.firstIndex(where: sameWireIdentity) {
            cachedWireSessions[idx] = wire
        } else {
            cachedWireSessions.append(wire)
        }
        cachedWireSessions = boundedSidebarWireSessions(deduplicatedWireSessions(cachedWireSessions))
        withAnimation(.easeOut(duration: 0.20)) {
            if wire.isArchived {
                let old = chats.first(where: sameChatIdentity) ?? archivedChats.first(where: sameChatIdentity)
                chats.removeAll(where: sameChatIdentity)
                let chat = chat(from: wire, old: old)
                if let idx = archivedChats.firstIndex(where: sameChatIdentity) {
                    archivedChats[idx] = chat
                } else {
                    archivedChats.insert(chat, at: 0)
                }
            } else if let archivedIndex = archivedChats.firstIndex(where: sameChatIdentity) {
                let chat = chat(from: wire, old: archivedChats[archivedIndex])
                archivedChats.remove(at: archivedIndex)
                chats.insert(chat, at: 0)
            } else if let idx = chats.firstIndex(where: sameChatIdentity) {
                chats[idx] = chat(from: wire, old: chats[idx])
            } else {
                chats.insert(chat(from: wire, old: nil), at: 0)
            }
            chats = boundedSidebarChats(chats, preserving: chats.first(where: sameChatIdentity)?.id ?? id)
            archivedChats = Array(archivedChats.prefix(Self.archivedSidebarLimit))
        }
    }

    func applyDaemonMessages(chatId: String, messages: [WireMessage], hasMore: Bool? = nil) {
        cachedWireMessagesByChat[chatId] = messages
        guard let id = localChatId(forBridgeSessionId: chatId) else { return }
        // Reset pagination state regardless of where the chat lives:
        // the snapshot is the new baseline. Treat absent metadata as
        // "no older history known" so incomplete snapshots stay eager.
        messagesPaginationByChat[id] = ChatPagination(
            oldestKnownId: messages.first?.id,
            hasMore: hasMore ?? false,
            loadingOlder: false
        )
        guard let transcript = chatStore.transcript(for: id),
              chatStore.summary(id: id) != nil
        else { return }
        // Wholesale rehydrate from the daemon: drop any buffered text
        // delta that would otherwise pile on top of the canonical body.
        dropPendingAssistantText(chatId: id)
        dropPendingReasoning(chatId: id)
        if messages.isEmpty,
           chatStore.summary(id: id)?.forkedFromChatId != nil,
           !transcript.messages.isEmpty {
            chatStore.updateSummary(id: id) { summary in
                summary.historyHydrated = true
            }
            syncLegacyChatFromStore(chatId: id)
            return
        }
        if messages.isEmpty,
           !transcript.messages.isEmpty,
           (chatStore.summary(id: id)?.rolloutPath != nil || chatStore.summary(id: id)?.clawixThreadId != nil) {
            chatStore.updateSummary(id: id) { summary in
                summary.historyHydrated = true
            }
            syncLegacyChatFromStore(chatId: id)
            return
        }
        if messages.isEmpty,
           transcript.messages.isEmpty,
           (chatStore.summary(id: id)?.rolloutPath != nil || chatStore.summary(id: id)?.clawixThreadId != nil) {
            return
        }
        // The daemon's `RolloutHistory` reader is intentionally minimal
        // and never populates `timeline` / `workSummary`, so a fresh
        // `messagesSnapshot` would wipe both fields off any local message
        // that already had them (e.g. hydrated from cache or seeded by an
        // earlier `RolloutReader` pass on this Mac). Carry them forward
        // by id so the chat row's "Worked for Xs" header doesn't flash
        // and disappear when the daemon snapshot lands.
        let oldById = Dictionary(uniqueKeysWithValues: transcript.messages.map { ($0.id, $0) })
        chatStore.replaceMessages(chatId: id, messages.compactMap { wire in
            chatMessage(from: wire, fallbackingTo: UUID(uuidString: wire.id).flatMap { oldById[$0] })
        })
        optimisticUserMessageIdsByChat[id] = nil
        chatStore.updateSummary(id: id) { summary in
            summary.historyHydrated = true
        }
        syncLegacyChatFromStore(chatId: id)
    }

    func trackOptimisticUserMessage(chatId: UUID, messageId: UUID) {
        optimisticUserMessageIdsByChat[chatId, default: []].insert(messageId)
    }

    func appendDaemonMessage(chatId: String, message: WireMessage) {
        // Mirror first so the snapshot persist sees the same shape the
        // chat detail does, regardless of whether the chat exists in
        // the local model yet (newChat path lands a `messageAppended`
        // before `sessionUpdated`).
        if let mIdx = cachedWireMessagesByChat[chatId]?.firstIndex(where: { $0.id == message.id }) {
            cachedWireMessagesByChat[chatId]?[mIdx] = message
        } else {
            cachedWireMessagesByChat[chatId, default: []].append(message)
        }
        guard let id = localChatId(forBridgeSessionId: chatId),
              let transcript = chatStore.transcript(for: id)
        else { return }
        // Same fallback as `applyDaemonMessages`: preserve any local
        // `workSummary` / `timeline` the daemon's wire form drops on the
        // floor, keyed by message id.
        let existing = UUID(uuidString: message.id).flatMap { mid in
            transcript.messages.first(where: { $0.id == mid })
        }
        guard let msg = chatMessage(from: message, fallbackingTo: existing) else { return }
        // The daemon's wire message is authoritative; any locally
        // buffered delta would double-append on top of it.
        dropPendingAssistantText(chatId: id)
        dropPendingReasoning(chatId: id)
        if msg.role == .user,
           let replacementIdx = optimisticUserReplacementIndex(chatId: id, remote: msg, messages: transcript.messages) {
            let localId = transcript.messages[replacementIdx].id
            transcript.replace(id: localId, with: msg)
            optimisticUserMessageIdsByChat[id]?.remove(localId)
            if optimisticUserMessageIdsByChat[id]?.isEmpty == true {
                optimisticUserMessageIdsByChat[id] = nil
            }
            syncLegacyChatFromStore(chatId: id)
            return
        }
        if transcript.messageStore(id: msg.id) != nil {
            transcript.replace(id: msg.id, with: msg)
        } else {
            chatStore.appendMessage(chatId: id, msg)
        }
        syncLegacyChatFromStore(chatId: id)
    }

    private func optimisticUserReplacementIndex(
        chatId: UUID,
        remote: ChatMessage,
        messages: [ChatMessage]
    ) -> Int? {
        guard let pending = optimisticUserMessageIdsByChat[chatId], !pending.isEmpty else { return nil }
        if let exact = messages.firstIndex(where: {
            pending.contains($0.id) && $0.role == .user && $0.content == remote.content
        }) {
            return exact
        }
        return messages.firstIndex(where: {
            pending.contains($0.id) && $0.role == .user
        })
    }


    /// Daemon-bridge mode counterpart of `ClawixService.refreshRateLimits`:
    /// the GUI's own backend never bootstraps when the LaunchAgent owns
    /// Codex, so the daemon ships its `account/rateLimits/read` view
    /// over the bridge and we land it on the same `@Published` fields
    /// the sidebar / Settings → Usage page already render off.
    func applyDaemonRateLimits(
        snapshot: WireRateLimitSnapshot?,
        byLimitId: [String: WireRateLimitSnapshot]
    ) {
        rateLimits = snapshot.map(rateLimitSnapshot(from:))
        var mapped: [String: RateLimitSnapshot] = [:]
        for (key, value) in byLimitId {
            mapped[key] = rateLimitSnapshot(from: value)
        }
        rateLimitsByLimitId = mapped
    }

    private func rateLimitSnapshot(from wire: WireRateLimitSnapshot) -> RateLimitSnapshot {
        RateLimitSnapshot(
            primary: wire.primary.map { RateLimitWindow(
                usedPercent: $0.usedPercent,
                resetsAt: $0.resetsAt,
                windowDurationMins: $0.windowDurationMins
            )},
            secondary: wire.secondary.map { RateLimitWindow(
                usedPercent: $0.usedPercent,
                resetsAt: $0.resetsAt,
                windowDurationMins: $0.windowDurationMins
            )},
            credits: wire.credits.map { CreditsSnapshot(
                hasCredits: $0.hasCredits,
                unlimited: $0.unlimited,
                balance: $0.balance
            )},
            limitId: wire.limitId,
            limitName: wire.limitName
        )
    }

    func applyDaemonStreaming(
        chatId: String,
        messageId: String,
        content: String,
        reasoningText: String,
        finished: Bool
    ) {
        guard let id = localChatId(forBridgeSessionId: chatId),
              let msgId = UUID(uuidString: messageId),
              let transcript = chatStore.transcript(for: id)
        else { return }
        // Same reasoning as `appendDaemonMessage`: the daemon-supplied
        // content replaces ours wholesale, so any pending tick of
        // local deltas would double up on top of the canonical body.
        dropPendingAssistantText(chatId: id)
        dropPendingReasoning(chatId: id)
        if transcript.messageStore(id: msgId) != nil {
            transcript.mutateMessage(id: msgId) { message in
                message.content = content
                message.reasoningText = reasoningText
                message.streamingFinished = finished
                if finished {
                    message.streamCheckpoints = StreamingFade.settledSentinel(prefixCount: content.count)
                    message.streamPendingTail = ""
                    settleReasoningCheckpoints(&message)
                }
            }
        } else {
            chatStore.appendMessage(chatId: id, ChatMessage(
                id: msgId,
                role: .assistant,
                content: content,
                reasoningText: reasoningText,
                streamingFinished: finished
            ))
        }
        chatStore.updateSummary(id: id) { summary in
            summary.hasActiveTurn = !finished
        }
        if finished {
            syncLegacyChatFromStore(chatId: id)
            scheduleStreamingCheckpointSettlement(chatId: id, messageId: msgId)
        }
    }

    /// Apply a server-delivered page of older messages. Prepended to
    /// the chat's transcript, deduped by id. Updates the pagination
    /// cursor + clears the in-flight flag so the scroll-up sentinel
    /// can fire again. Mirrors `BridgeStore.applyMessagesPage`.
    func applyDaemonMessagesPage(chatId: String, messages: [WireMessage], hasMore: Bool) {
        guard let id = localChatId(forBridgeSessionId: chatId) else { return }
        let beforeCount = chatStore.transcript(for: id)?.messageIds.count ?? 0
        var pag = messagesPaginationByChat[id] ?? ChatPagination(oldestKnownId: nil, hasMore: hasMore, loadingOlder: false)
        pag.loadingOlder = false
        pag.hasMore = hasMore
        messagesPaginationByChat[id] = pag
        guard !messages.isEmpty else { return }
        let existing = cachedWireMessagesByChat[chatId] ?? []
        let existingWireIds = Set(existing.map(\.id))
        let prependWire = messages.filter { !existingWireIds.contains($0.id) }
        guard !prependWire.isEmpty else { return }
        cachedWireMessagesByChat[chatId] = prependWire + existing
        let transcript = chatStore.transcript(forCreating: id)
        let existingChatIds = Set(transcript.messages.map(\.id))
        let toInsert = prependWire.compactMap { chatMessage(from: $0) }
            .filter { !existingChatIds.contains($0.id) }
        guard !toInsert.isEmpty else { return }
        transcript.prepend(toInsert)
        syncLegacyChatFromStore(chatId: id)
        messagesPaginationByChat[id]?.oldestKnownId = cachedWireMessagesByChat[chatId]?.first?.id
        RenderProbe.mark(
            "ChatOlderPageApplied",
            fields: [
                "before": "\(beforeCount)",
                "chat": chatId,
                "hasMore": "\(hasMore)",
                "inserted": "\(toInsert.count)",
                "oldest": messagesPaginationByChat[id]?.oldestKnownId ?? "",
                "received": "\(messages.count)",
                "total": "\(transcript.messageIds.count)"
            ]
        )
    }

    /// Ask the daemon for the next page of older messages if we have a
    /// cursor, the daemon told us there are more, and we don't already
    /// have a page in flight. Called by the chat transcript's scroll-
    /// up sentinel; the guards short-circuit cheaply because the
    /// callback can fire on every onScrollGeometryChange tick.
    func requestOlderIfNeeded(chatId: UUID) {
        guard let pag = messagesPaginationByChat[chatId],
              pag.hasMore,
              !pag.loadingOlder,
              let cursor = pag.oldestKnownId else { return }
        messagesPaginationByChat[chatId]?.loadingOlder = true
        RenderProbe.mark(
            "ChatOlderPageRequest",
            fields: [
                "chat": chatId.uuidString,
                "cursor": cursor,
                "loaded": "\(chatStore.transcript(for: chatId)?.messageIds.count ?? 0)"
            ]
        )
        if let path = chat(byId: chatId)?.rolloutPath,
           FileManager.default.fileExists(atPath: path.path) {
            Task { @MainActor [weak self] in
                let started = CFAbsoluteTimeGetCurrent()
                let result = await Task.detached(priority: .userInitiated) {
                    RolloutReader.readWindowBefore(path: path, beforeMessageId: cursor)
                }.value
                let messages = rolloutChatMessages(from: result).map { $0.toWire() }
                RenderProbe.mark(
                    "ChatOlderPageLoaded",
                    fields: [
                        "chat": chatId.uuidString,
                        "cursor": cursor,
                        "hasMore": "\(result.hasMoreBefore)",
                        "ms": String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - started) * 1000),
                        "parsedRecords": "\(result.parsedRecordCount)",
                        "readBytes": "\(result.readBytes)",
                        "readEntireFile": "\(result.readEntireFile)",
                        "received": "\(messages.count)"
                    ]
                )
                self?.applyDaemonMessagesPage(
                    chatId: chatId.uuidString,
                    messages: messages,
                    hasMore: result.hasMoreBefore
                )
            }
            return
        }
        guard let client = daemonBridgeClient,
              client.loadOlderMessages(sessionId: bridgeSessionId(forChatId: chatId), beforeMessageId: cursor)
        else {
            if let threadId = chat(byId: chatId)?.clawixThreadId {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        let client = self.clawJSSessionsClientFactory()
                        let endOffset: Int
                        if let oldestOffset = self.messagesPaginationByChat[chatId]?.oldestOffset {
                            endOffset = oldestOffset
                        } else {
                            let session = try await client.getSession(id: threadId, includeMessages: false).session
                            let loaded = self.chatStore.transcript(for: chatId)?.messageIds.count ?? 0
                            endOffset = max(0, session.messageCount - loaded)
                        }
                        let offset = max(0, endOffset - bridgeOlderPageLimit)
                        let limit = max(0, endOffset - offset)
                        guard limit > 0 else {
                            self.messagesPaginationByChat[chatId]?.loadingOlder = false
                            self.messagesPaginationByChat[chatId]?.hasMore = false
                            return
                        }
                        let page = try await client.hydrateSession(
                            id: threadId,
                            messageLimit: limit,
                            messageOffset: offset,
                            recent: false,
                            includeEvents: false
                        )
                        let records = page.messages
                        let messages = records.map(Self.chatMessage(fromClawJSSessionMessage:))
                        let transcript = self.chatStore.transcript(forCreating: chatId)
                        let existing = Set(transcript.messageIds)
                        transcript.prepend(messages.filter { !existing.contains($0.id) })
                        self.messagesPaginationByChat[chatId] = ChatPagination(
                            oldestKnownId: records.first?.id ?? cursor,
                            oldestOffset: page.messageOffset,
                            hasMore: page.hasOlderMessages,
                            loadingOlder: false
                        )
                    } catch {
                        self.messagesPaginationByChat[chatId]?.loadingOlder = false
                    }
                }
                return
            }
            if let path = chat(byId: chatId)?.rolloutPath {
                Task { @MainActor [weak self] in
                    let result = await Task.detached(priority: .userInitiated) {
                        RolloutReader.readWindowBefore(path: path, beforeMessageId: cursor)
                    }.value
                    let messages = rolloutChatMessages(from: result).map { $0.toWire() }
                    self?.applyDaemonMessagesPage(
                        chatId: chatId.uuidString,
                        messages: messages,
                        hasMore: result.hasMoreBefore
                    )
                }
                return
            }
            messagesPaginationByChat[chatId]?.loadingOlder = false
            return
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard let self,
                  var pag = self.messagesPaginationByChat[chatId],
                  pag.loadingOlder,
                  pag.oldestKnownId == cursor
            else { return }
            pag.loadingOlder = false
            self.messagesPaginationByChat[chatId] = pag
        }
    }

    /// Restore the on-disk snapshot if one exists. Called once at
    /// startup right after `applySnapshotForFirstPaint()` so the chat
    /// detail renders the last-known transcript immediately while the
    /// daemon's `messagesSnapshot` is still in flight. Bridge frames
    /// shortly overwrite this with the canonical truth.
    func loadCachedSnapshot() {
        guard let payload = SnapshotCache.load() else { return }
        cachedWireSessions = payload.chats
        cachedWireMessagesByChat = payload.messagesBySession
        if chats.isEmpty && archivedChats.isEmpty {
            // Fresh install / no SQLite: populate `chats` from the
            // snapshot. No animation; the user is staring at a launch
            // screen, not at a list mutating under their cursor.
            let active: [Chat] = payload.chats.compactMap { wire in
                guard !wire.isArchived else { return nil }
                var c = chat(from: wire, old: nil)
                if let cached = payload.messagesBySession[wire.id] {
                    c.messages = cached.compactMap { chatMessage(from: $0) }
                    c.historyHydrated = true
                }
                return c
            }
            let arch: [Chat] = payload.chats.compactMap { wire in
                guard wire.isArchived else { return nil }
                var c = chat(from: wire, old: nil)
                if let cached = payload.messagesBySession[wire.id] {
                    c.messages = cached.compactMap { chatMessage(from: $0) }
                    c.historyHydrated = true
                }
                return c
            }
            chats = active
            archivedChats = arch
        } else {
            // SQLite already populated `chats`. Just hydrate messages
            // for those that match a snapshot entry; leave the rest
            // alone so the daemon can fill them in or the rollout
            // fallback can.
            for (chatIdString, msgs) in payload.messagesBySession {
                guard let id = UUID(uuidString: chatIdString) else { continue }
                mutateChat(id: id) { c in
                    guard c.messages.isEmpty else { return }
                    c.messages = msgs.compactMap { chatMessage(from: $0) }
                    c.historyHydrated = true
                }
            }
        }
        // Seed pagination cursors so a scroll-up sentinel firing
        // before the daemon (re)delivers `messagesSnapshot` still has
        // an `oldestKnownId` to send. `hasMore` defaults to `false`
        // because we don't know yet; the daemon will refresh on
        // `messagesSnapshot`.
        for (chatIdString, msgs) in payload.messagesBySession {
            guard let id = UUID(uuidString: chatIdString) else { continue }
            messagesPaginationByChat[id] = ChatPagination(
                oldestKnownId: msgs.first?.id,
                hasMore: false,
                loadingOlder: false
            )
        }
    }

    /// Schedule a persist of the wire mirror after 500ms of quiet.
    /// Streaming chunks and rapid chat updates collapse into a single
    /// write; the IO runs on a background queue so the main thread is
    /// never blocked. Safe to call from any of the bridge inbound
    /// paths after a mutation.
    func persistSnapshotDebounced() {
        persistTask?.cancel()
        persistTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            let chatsSnap = self.cachedWireSessions
            let messagesSnap = self.cachedWireMessagesByChat
            await Task.detached(priority: .background) {
                SnapshotCache.save(chats: chatsSnap, messages: messagesSnap)
            }.value
        }
    }

    private func chat(from wire: WireSession, old: Chat?) -> Chat {
        // Wire chats from the daemon don't share UUIDs with our
        // persisted snapshot, so `old` is usually nil and the chat
        // arrives without `clawixThreadId` / `projectId`. The new
        // `wire.threadId` field (and the daemon's pin-aware
        // `wire.isPinned`) lets us reconstruct both: stamp the thread
        // id, then resolve the project via the same `rootPath`
        // logic `chatFromThread` uses for runtime-sourced summaries.
        let threadId = wire.threadId ?? old?.clawixThreadId
        let projectByPath = Dictionary(uniqueKeysWithValues: projects.map { ($0.path, $0) })
        let resolvedRoot = rootPath(
            threadId: threadId,
            cwd: wire.cwd ?? old?.cwd,
            projectByPath: projectByPath
        )
        let resolvedProjectId: UUID? = resolvedRoot.flatMap { projectByPath[$0]?.id } ?? old?.projectId
        return Chat(
            id: old?.id ?? UUID(uuidString: wire.id) ?? UUID(),
            title: wire.title,
            messages: [],
            createdAt: wire.lastMessageAt ?? wire.createdAt,
            clawixThreadId: threadId,
            rolloutPath: old?.rolloutPath,
            historyHydrated: old?.historyHydrated ?? false,
            hasActiveTurn: wire.hasActiveTurn,
            projectId: resolvedProjectId,
            isArchived: wire.isArchived,
            isPinned: wire.isPinned,
            hasUnreadCompletion: old?.hasUnreadCompletion ?? false,
            cwd: wire.cwd,
            hasGitRepo: old?.hasGitRepo ?? false,
            branch: wire.branch ?? old?.branch,
            availableBranches: old?.availableBranches ?? [],
            uncommittedFiles: old?.uncommittedFiles,
            forkedFromChatId: old?.forkedFromChatId,
            forkedFromTitle: old?.forkedFromTitle,
            forkBannerAfterMessageId: old?.forkBannerAfterMessageId,
            lastTurnInterrupted: wire.lastTurnInterrupted
        )
    }

    func chatMessage(from wire: WireMessage, fallbackingTo old: ChatMessage? = nil) -> ChatMessage? {
        guard let id = UUID(uuidString: wire.id) else { return nil }
        // Daemon-bridge mode: the helper's `RolloutHistory` reader does
        // not populate `timeline` / `workSummary` / `attachments` on the
        // wire. When this assistant message already exists locally with
        // those fields filled in (cache hydrate, earlier full-fidelity
        // rollout pass, live streaming via ClawixService), preserve them
        // so the chat row's "Worked for Xs" header and inline file/image
        // cards survive the snapshot replay.
        let timeline = wire.timeline.compactMap(timelineEntry(from:))
        let resolvedTimeline = timeline.isEmpty ? (old?.timeline ?? []) : timeline
        let resolvedSummary = wire.workSummary.map(workSummary(from:)) ?? old?.workSummary
        let resolvedAttachments = wire.attachments.isEmpty ? (old?.attachments ?? []) : wire.attachments
        return ChatMessage(
            id: id,
            role: wire.role == .user ? .user : .assistant,
            content: wire.content,
            reasoningText: wire.reasoningText,
            streamingFinished: wire.streamingFinished,
            isError: wire.isError,
            timestamp: wire.timestamp,
            workSummary: resolvedSummary,
            timeline: resolvedTimeline,
            audioRef: wire.audioRef,
            attachments: resolvedAttachments,
            goalOutcome: old?.goalOutcome
        )
    }

    private func workSummary(from wire: WireWorkSummary) -> WorkSummary {
        WorkSummary(
            startedAt: wire.startedAt,
            endedAt: wire.endedAt,
            items: wire.items.compactMap(workItem(from:))
        )
    }

    private func timelineEntry(from wire: WireTimelineEntry) -> AssistantTimelineEntry? {
        switch wire {
        case .reasoning(let id, let text):
            return UUID(uuidString: id).map { .reasoning(id: $0, text: text) }
        case .message(let id, let text):
            return UUID(uuidString: id).map { .message(id: $0, text: text) }
        case .steered(let id):
            return UUID(uuidString: id).map { .steered(id: $0) }
        case .divider(let id, let text):
            return UUID(uuidString: id).map { .divider(id: $0, text: text) }
        case .tools(let id, let items):
            guard let uuid = UUID(uuidString: id) else { return nil }
            let workItems = items.compactMap(workItem(from:))
            return .tools(
                id: uuid,
                items: workItems,
                presentation: ToolTimelinePresentation.snapshot(groupID: uuid, items: workItems)
            )
        }
    }

    private func workItem(from wire: WireWorkItem) -> WorkItem? {
        let status: WorkItemStatus
        switch wire.status {
        case .inProgress: status = .inProgress
        case .completed: status = .completed
        case .failed: status = .failed
        }
        let kind: WorkItemKind
        switch wire.kind {
        case "command":
            kind = .command(text: wire.commandText, actions: (wire.commandActions ?? []).map { CommandActionKind(rawValue: $0) ?? .unknown })
        case "fileChange":
            kind = .fileChange(paths: wire.paths ?? [])
        case "webSearch":
            kind = .webSearch
        case "mcpTool":
            // The browser-use plugin reports through the synthetic
            // `node_repl` MCP server. The daemon doesn't yet ship a
            // dedicated wire kind, so we relabel here so the live
            // streaming pill reads `Used Node Repl` instead of the raw
            // server/tool dump. Once we reload the chat from the rollout,
            // RolloutReader's classifier upgrades the browser calls to
            // `.jsCall(.browser)` so the timeline picks up the proper
            // `Used the browser` pill.
            let server = wire.mcpServer ?? ""
            let tool = wire.mcpTool ?? ""
            if server == "node_repl" {
                kind = tool == "js_reset"
                    ? .jsReset
                    : .jsCall(title: nil, flavor: .repl)
            } else {
                kind = .mcpTool(server: server, tool: tool)
            }
        case "dynamicTool":
            kind = .dynamicTool(name: wire.dynamicToolName ?? "")
        case "imageGeneration":
            kind = .imageGeneration
        case "imageView":
            kind = .imageView
        default:
            return nil
        }
        return WorkItem(
            id: wire.id,
            kind: kind,
            status: status,
            generatedImagePath: wire.generatedImagePath
        )
    }
}
