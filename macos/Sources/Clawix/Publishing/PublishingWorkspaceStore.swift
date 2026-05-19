import Foundation
import SwiftUI
import Combine

/// Top-level `@MainActor` observable for the Publishing UI. Wraps the typed
/// HTTP client and watches `ClawJSServiceManager` for liveness transitions
/// so views can react when the helper crashes / restarts. Mirrors the
/// app's surface-store pattern: one state machine, no hidden globals, all
/// mutations flow through this object.
@MainActor
final class PublishingWorkspaceStore: ObservableObject {
    typealias ListPostsOperation = @MainActor (
        _ workspaceId: String,
        _ from: Date,
        _ to: Date
    ) async throws -> [ClawJSPublishingClient.Post]

    enum State: Equatable {
        case idle
        case bootstrapping
        case ready
        case unavailable(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var workspaceId: String?
    @Published private(set) var families: [ClawJSPublishingClient.Family] = []
    @Published private(set) var channels: [ClawJSPublishingClient.ChannelAccount] = []
    @Published private(set) var posts: [ClawJSPublishingClient.Post] = []
    @Published private(set) var lastError: String?

    let client: ClawJSPublishingClient
    private let listPostsOperation: ListPostsOperation

    nonisolated static let workspaceKey = "clawix.publishing.workspaceId.v1"

    private var bootstrapTask: Task<Void, Never>?
    private var calendarRefreshTask: Task<Void, Never>?
    private var calendarRefreshGeneration = 0
    private var supervisorObserver: AnyCancellable?

    init(
        client: ClawJSPublishingClient? = nil,
        listPostsOperation: ListPostsOperation? = nil,
        attachSupervisor: Bool = true,
        initialState: State = .idle,
        workspaceId initialWorkspaceId: String? = nil
    ) {
        let resolvedClient = client ?? ClawJSPublishingClient()
        self.client = resolvedClient
        self.listPostsOperation = listPostsOperation ?? { workspaceId, from, to in
            try await resolvedClient.listPosts(workspaceId: workspaceId, from: from, to: to)
        }
        let stored = initialWorkspaceId ?? UserDefaults.standard.string(forKey: Self.workspaceKey)
        self.workspaceId = (stored?.isEmpty == false) ? stored : nil
        self.client.workspaceId = self.workspaceId
        self.state = initialState
        if attachSupervisor {
            attachSupervisorObserver()
        }
    }

    deinit {
        bootstrapTask?.cancel()
        calendarRefreshTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Loads the host-session admin token and resolves (or creates) the
    /// "Default" workspace. Idempotent: re-entry while a bootstrap is in
    /// flight is a no-op.
    func bootstrap() {
        guard bootstrapTask == nil else { return }
        let snapshot = ClawJSServiceManager.shared.snapshots[.publishing]
        guard snapshot?.state.isReady == true else {
            state = .unavailable(snapshot?.state.unavailableReason ?? "Publishing service is not running.")
            return
        }
        state = .bootstrapping
        bootstrapTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.bootstrapTask = nil }
            do {
                guard let token = ClawJSServiceManager.shared.adminTokenIfSpawned(for: .publishing) else {
                    throw NSError(domain: "PublishingWorkspaceStore", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "Publishing admin token is available only to the host process that launched the service."
                    ])
                }
                self.client.bearerToken = token
                try await self.ensureDefaultWorkspace()
                async let families = self.client.listFamilies()
                async let channels = self.client.listChannels(workspaceId: self.workspaceId ?? "")
                let resolvedFamilies = try await families
                let resolvedChannels = try await channels
                self.families = resolvedFamilies
                self.channels = resolvedChannels
                self.state = .ready
                self.lastError = nil
            } catch {
                self.state = .unavailable(error.localizedDescription)
                self.lastError = error.localizedDescription
            }
        }
    }

    /// Drops any in-memory state. Used when the supervisor reports the
    /// service is down so views render an empty state instead of stale
    /// data from a previous boot.
    func reset(reason: String) {
        bootstrapTask?.cancel()
        bootstrapTask = nil
        calendarRefreshGeneration += 1
        calendarRefreshTask?.cancel()
        calendarRefreshTask = nil
        families = []
        channels = []
        posts = []
        state = .unavailable(reason)
    }

    private func ensureDefaultWorkspace() async throws {
        if let id = workspaceId, !id.isEmpty {
            client.workspaceId = id
            // Confirm it still exists; if the daemon was wiped between
            // launches the stored id will dangle.
            let workspaces = try await client.listWorkspaces()
            if workspaces.contains(where: { $0.id == id }) { return }
        }
        let workspaces = try await client.listWorkspaces()
        let resolved: ClawJSPublishingClient.Workspace
        if let existing = workspaces.first {
            resolved = existing
        } else {
            resolved = try await client.createWorkspace(name: "Default")
        }
        workspaceId = resolved.id
        client.workspaceId = resolved.id
        UserDefaults.standard.set(resolved.id, forKey: Self.workspaceKey)
    }

    // MARK: - Refresh

    func refreshFamilies() async {
        guard state == .ready else { return }
        do {
            families = try await client.listFamilies()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshChannels() async {
        guard let workspaceId, state == .ready else { return }
        do {
            channels = try await client.listChannels(workspaceId: workspaceId)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshCalendar(from: Date, to: Date) async {
        guard let workspaceId, state == .ready else { return }
        let generation = nextCalendarRefreshGeneration()
        calendarRefreshTask?.cancel()
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            await self.runCalendarRefresh(workspaceId: workspaceId, from: from, to: to, generation: generation)
        }
        calendarRefreshTask = task
        await task.value
    }

    private func runCalendarRefresh(workspaceId: String, from: Date, to: Date, generation: Int) async {
        do {
            let posts = try await listPostsOperation(workspaceId, from, to)
            try Task.checkCancellation()
            guard isCurrentCalendarRefresh(generation) else { return }
            self.posts = posts
            lastError = nil
        } catch is CancellationError {
        } catch {
            guard isCurrentCalendarRefresh(generation) else { return }
            lastError = error.localizedDescription
        }
        finishCalendarRefreshIfCurrent(generation)
    }

    // MARK: - Mutations

    func connect(familyId: String, payload: [String: String]) async throws -> ClawJSPublishingClient.ChannelAccount {
        guard let workspaceId else { throw ClawJSPublishingClient.Error.serviceNotReady }
        let account = try await client.connectChannel(
            workspaceId: workspaceId,
            familyId: familyId,
            payload: payload
        )
        channels.append(account)
        return account
    }

    func disconnect(account: ClawJSPublishingClient.ChannelAccount) async {
        guard let workspaceId else { return }
        do {
            _ = try await client.disconnectChannel(workspaceId: workspaceId, accountId: account.id)
            channels.removeAll { $0.id == account.id }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func probe(account: ClawJSPublishingClient.ChannelAccount) async {
        guard let workspaceId else { return }
        do {
            _ = try await client.probeChannel(workspaceId: workspaceId, accountId: account.id)
        } catch {
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    func createPost(spec: ClawJSPublishingClient.PostSpec) async throws -> ClawJSPublishingClient.Post {
        guard let workspaceId else { throw ClawJSPublishingClient.Error.serviceNotReady }
        let post = try await client.createPost(workspaceId: workspaceId, spec: spec)
        posts.append(post)
        return post
    }

    // MARK: - Supervisor wiring

    private func attachSupervisorObserver() {
        supervisorObserver = ClawJSServiceManager.shared.$snapshots.sink { [weak self] snapshots in
            guard let self, let snap = snapshots[.publishing] else { return }
            switch snap.state {
            case .ready, .readyFromDaemon:
                if self.state == .idle || self.state == .bootstrapping {
                    self.bootstrap()
                } else if case .unavailable = self.state {
                    self.bootstrap()
                }
            case .blocked, .crashed, .daemonUnavailable:
                self.reset(reason: snap.state.unavailableReason ?? "Publishing service is unavailable.")
            case .idle:
                if self.state != .idle {
                    self.reset(reason: "Publishing service has not started yet.")
                }
            case .starting:
                if case .ready = self.state {
                    // keep current state until the next ready flip
                } else {
                    self.state = .bootstrapping
                }
            }
        }
    }

    private func nextCalendarRefreshGeneration() -> Int {
        calendarRefreshGeneration += 1
        return calendarRefreshGeneration
    }

    private func isCurrentCalendarRefresh(_ generation: Int) -> Bool {
        calendarRefreshGeneration == generation
    }

    private func finishCalendarRefreshIfCurrent(_ generation: Int) {
        guard isCurrentCalendarRefresh(generation) else { return }
        calendarRefreshTask = nil
    }
}
