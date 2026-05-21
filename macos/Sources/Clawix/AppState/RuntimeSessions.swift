import Foundation
import SwiftUI
import ClawixCore

extension AppState {
    func loadThreadsFromRuntime() async {
        // When a thread fixture drives the sidebar (showcase / E2E /
        // demo recordings), the runtime is intentionally empty and a
        // runtime sweep here would call `applyThreads([])`, wiping the
        // curated dataset. The fixture is the source of truth for the
        // whole session.
        if AgentThreadStore.fixtureThreads() != nil { return }
        if await loadThreadsFromClawJSSessions() {
            return
        }
        let pageLoader: (_ cursor: String?, _ limit: Int) async throws -> ClawixService.ThreadListPage
        if let runtimeThreadPageLoader {
            pageLoader = runtimeThreadPageLoader
        } else {
            guard let clawix, case .ready = clawix.status else { return }
            pageLoader = { cursor, limit in
                try await clawix.listThreadsPage(
                    archived: false,
                    cursor: cursor,
                    limit: limit,
                    useStateDbOnly: true
                )
            }
        }
        do {
            let result = try await pageLoader(nil, Self.sidebarBootstrapRecentLimit)
            applyThreads(result.threads)
        } catch {
            appendRuntimeStatusError(L10n.runtimeIndexReadFailed("\(error)"))
        }
    }

    @discardableResult
    func ensureAgentRuntimeReady(reason: AgentRuntimeDemandReason) async -> Bool {
        let daemonBridgeEnabled = daemonBridgeClient != nil
        if daemonBridgeEnabled { return true }
        guard ProcessInfo.processInfo.environment["CLAWIX_DISABLE_BACKEND"] != "1",
           !daemonBridgeEnabled else {
            return false
        }
        if let agentRuntimeStartTask {
            return await agentRuntimeStartTask.value
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return false }
            await ClawJSServiceManager.shared.start(
                [.runtime, .sessions],
                reason: .capability(reason.triggerDescription)
            )
            guard let clawix = self.clawix else { return false }
            let ready = await clawix.startIfNeeded(reason: reason)
            self.clawixBackendStatus = clawix.status
            if ready {
                await self.seedArchivesIfNeeded()
                self.drainProjectRefreshQueue()
            }
            return ready
        }
        agentRuntimeStartTask = task
        let ready = await task.value
        agentRuntimeStartTask = nil
        return ready
    }

    func scheduleChatRuntimeDemandIfReady(chatId: UUID) {
        guard postFirstFramePersistenceStarted else { return }
        scheduleChatRuntimeDemand(chatId: chatId)
    }

    func scheduleChatRuntimeDemand(chatId: UUID) {
        chatRuntimeDemandTask?.cancel()
        chatRuntimeDemandTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled,
                  let self,
                  case let .chat(currentChatId) = self.currentRoute,
                  currentChatId == chatId
            else { return }
            guard await self.ensureAgentRuntimeReady(reason: .chatOpened) else { return }
            guard let threadId = self.chat(byId: chatId)?.clawixThreadId,
                  let clawix = self.clawix,
                  case .ready = clawix.status
            else { return }
            await clawix.attach(chatId: chatId, threadId: threadId)
        }
    }

    private func loadThreadsFromClawJSSessions() async -> Bool {
        let client = clawJSSessionsClientFactory()
        do {
            _ = try await client.probeHealth()
            async let pinnedRequest = client.listSessions(
                pinned: true,
                archived: false,
                sidebarVisible: true,
                limit: Self.startupPinnedSessionLimit
            )
            async let recentRequest = client.listSessions(
                pinned: false,
                archived: false,
                sidebarVisible: true,
                limit: Self.startupRecentSessionLimit
            )
            let pinned = try await pinnedRequest
            let recent = try await recentRequest
            let sessions = mergeClawJSSessions(pinned: pinned, recent: recent)
            if sessions.isEmpty, shouldPreserveLocalSidebarAgainstEmptyCanonicalSource() {
                clawJSSessionsCanonicalActive = false
                return false
            }
            clawJSSessionsCanonicalActive = true
            clawJSSessionsProjectsLoaded = false
            applyThreads(
                sessions.map(threadSummary(from:)),
                extraPinnedThreadIds: pinned.map { $0.id }
            )
            return true
        } catch {
            clawJSSessionsCanonicalActive = false
            clawJSSessionsProjectsLoaded = false
            return false
        }
    }

    func scheduleDeferredCodexImport() {
        guard snapshotEnabled else { return }
        guard deferredCodexImportTask == nil else { return }
        deferredCodexImportTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_250_000_000)
            guard !Task.isCancelled else { return }
            await self?.runDeferredCodexImport()
        }
    }

    func runDeferredCodexImport() async {
        let client = clawJSSessionsClientFactory()
        do {
            let result = try await client.importCodex(
                budgetMs: 400,
                maxFiles: 64,
                mode: .incremental
            )
            guard (result.changedFiles ?? 0) > 0 else { return }
            await clawJSAppStateCacheRefresh()
            await loadThreadsFromRuntime()
        } catch {
            // Best-effort only: first paint and explicit refreshes must not
            // surface a startup warning just because the deferred mirror pass
            // missed its idle window or the sessions service was unavailable.
        }
    }

    func startPostFirstFramePersistence() {
        guard !postFirstFramePersistenceStarted else { return }
        postFirstFramePersistenceStarted = true
        startPostFirstFrameFaviconCache()
        if case let .chat(id) = currentRoute {
            scheduleChatRuntimeDemand(chatId: id)
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let provider = self.databaseProvider
            let state = await Task.detached(priority: .utility) {
                provider.openIfNeeded()
            }.value
            await self.handlePostFirstFrameDatabaseState(state)
        }
    }

    private func startPostFirstFrameFaviconCache() {
        guard !postFirstFrameFaviconCacheStarted else { return }
        postFirstFrameFaviconCacheStarted = true
        Task { @MainActor in
            FaviconCache.shared.primeDiskCache()
        }
    }

    private func handlePostFirstFrameDatabaseState(_ state: LazyDatabaseProviderState) async {
        switch state {
        case .ready:
            manualProjectOrder = projectOrdersRepo.orderedIds()
            titlesRepo.reload()
            guard snapshotEnabled else { return }
            applySnapshotForFirstPaint()
            loadCachedSnapshot()
        case .failed(let failure):
            rescueDecision = RescueSurvivalPolicy.evaluate(
                signals: [failure.signal],
                availableRuntimeCount: 1
            )
            appendRuntimeStatusError("Local database unavailable: \(failure.error.localizedDescription)")
        case .idle, .opening:
            break
        }
    }

    func scheduleIdleAppStateCanonicalReconciliation(delayNanos: UInt64 = 1_500_000_000) {
        appStateCanonicalReconciliationTask?.cancel()
        appStateCanonicalReconciliationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayNanos)
            guard !Task.isCancelled, let self else { return }
            await self.clawJSAppStateCacheRefresh()
            guard !Task.isCancelled else { return }
            self.applySnapshotForFirstPaint()
            self.scheduleSidebarSnapshotProjectIDBackfill()
            await self.loadThreadsFromRuntime()
            if !Task.isCancelled {
                self.appStateCanonicalReconciliationTask = nil
            }
        }
    }

    private func mergeClawJSSessions(
        pinned: [ClawJSSessionsClient.SessionRecord],
        recent: [ClawJSSessionsClient.SessionRecord]
    ) -> [ClawJSSessionsClient.SessionRecord] {
        var seen: Set<String> = []
        var merged: [ClawJSSessionsClient.SessionRecord] = []
        for session in pinned + recent where seen.insert(session.id).inserted {
            merged.append(session)
        }
        return merged
    }

    func threadSummary(from session: ClawJSSessionsClient.SessionRecord) -> AgentThreadSummary {
        AgentThreadSummary(
            id: session.id,
            cwd: session.cwd ?? session.projectPath,
            name: session.title,
            preview: "",
            path: nil,
            createdAt: session.createdAt / 1000,
            updatedAt: (session.lastMessageAt ?? session.createdAt) / 1000,
            archived: session.archived
        )
    }

    func loadCanonicalProjectsIfNeeded(force: Bool = false) async {
        if AgentThreadStore.fixtureThreads() != nil { return }
        guard clawJSSessionsCanonicalActive || force else { return }
        if clawJSSessionsProjectsLoading { return }
        if clawJSSessionsProjectsLoaded && !force { return }
        clawJSSessionsProjectsLoading = true
        defer { clawJSSessionsProjectsLoading = false }
        do {
            let client = clawJSSessionsClientFactory()
            let pageSize = 500
            var offset = 0
            var canonicalProjects: [ClawJSSessionsClient.Project] = []
            while true {
                let page = try await client.listProjects(
                    hidden: false,
                    archived: false,
                    limit: pageSize,
                    offset: offset
                )
                canonicalProjects.append(contentsOf: page)
                if page.count < pageSize { break }
                offset += pageSize
            }
            projects = canonicalProjects.map { project in
                Project(
                    id: project.resourceId.map(StableProjectID.uuid(forResourceId:))
                        ?? UUID(uuidString: project.id)
                        ?? StableProjectID.uuid(for: project.path),
                    resourceId: project.resourceId,
                    name: project.displayName,
                    path: project.path
                )
            }
            if let selectedProject,
               let refreshed = projects.first(where: { $0.id == selectedProject.id }) {
                self.selectedProject = refreshed
            }
            clawJSSessionsProjectsLoaded = true
        } catch {
            clawJSSessionsProjectsLoaded = false
        }
    }

    func shouldPreserveLocalSidebarAgainstEmptyCanonicalSource() -> Bool {
        !chats.isEmpty || snapshotRepo.count() > 0 || pinsRepo.count() > 0 || projectsRepo.count() > 0
    }

    /// Legacy direct refresh used by older call sites. New sidebar
    /// paths should go through `requestVisibleProjectRefresh` or
    /// `requestExpandedProjectRefresh` so work is retained, deduped,
    /// prioritised and cancelable.
}
