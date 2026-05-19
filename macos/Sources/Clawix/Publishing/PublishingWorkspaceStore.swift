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
    struct BootstrapResult {
        let workspaceId: String?
        let families: [ClawJSPublishingClient.Family]
        let channels: [ClawJSPublishingClient.ChannelAccount]
    }

    typealias BootstrapAvailabilityOperation = @MainActor () -> String?
    typealias BootstrapOperation = @MainActor () async throws -> BootstrapResult
    typealias ListFamiliesOperation = @MainActor () async throws -> [ClawJSPublishingClient.Family]
    typealias ListChannelsOperation = @MainActor (_ workspaceId: String) async throws -> [ClawJSPublishingClient.ChannelAccount]
    typealias ListPostsOperation = @MainActor (
        _ workspaceId: String,
        _ from: Date,
        _ to: Date
    ) async throws -> [ClawJSPublishingClient.Post]
    typealias ConnectChannelOperation = @MainActor (
        _ workspaceId: String,
        _ familyId: String,
        _ payload: [String: String]
    ) async throws -> ClawJSPublishingClient.ChannelAccount
    typealias DisconnectChannelOperation = @MainActor (_ workspaceId: String, _ accountId: String) async throws -> Bool
    typealias ProbeChannelOperation = @MainActor (_ workspaceId: String, _ accountId: String) async throws -> Bool
    typealias CreatePostOperation = @MainActor (
        _ workspaceId: String,
        _ spec: ClawJSPublishingClient.PostSpec
    ) async throws -> ClawJSPublishingClient.Post

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
    private let bootstrapAvailabilityOperation: BootstrapAvailabilityOperation
    private let bootstrapOperation: BootstrapOperation?
    private let listFamiliesOperation: ListFamiliesOperation
    private let listChannelsOperation: ListChannelsOperation
    private let listPostsOperation: ListPostsOperation
    private let connectChannelOperation: ConnectChannelOperation
    private let disconnectChannelOperation: DisconnectChannelOperation
    private let probeChannelOperation: ProbeChannelOperation
    private let createPostOperation: CreatePostOperation

    nonisolated static let workspaceKey = "clawix.publishing.workspaceId.v1"

    private var bootstrapTask: Task<Void, Never>?
    private var bootstrapGeneration = 0
    private var familiesRefreshTask: Task<Void, Never>?
    private var familiesRefreshGeneration = 0
    private var channelsRefreshTask: Task<Void, Never>?
    private var channelsRefreshGeneration = 0
    private var calendarRefreshTask: Task<Void, Never>?
    private var calendarRefreshGeneration = 0
    private var connectTasks: [String: Task<Result<ClawJSPublishingClient.ChannelAccount, Swift.Error>, Never>] = [:]
    private var connectGenerations: [String: Int] = [:]
    private var channelActionTasks: [String: Task<Void, Never>] = [:]
    private var channelActionGenerations: [String: Int] = [:]
    private var createPostTask: Task<Result<ClawJSPublishingClient.Post, Swift.Error>, Never>?
    private var createPostGeneration = 0
    private var supervisorObserver: AnyCancellable?

    init(
        client: ClawJSPublishingClient? = nil,
        bootstrapAvailabilityOperation: BootstrapAvailabilityOperation? = nil,
        bootstrapOperation: BootstrapOperation? = nil,
        listFamiliesOperation: ListFamiliesOperation? = nil,
        listChannelsOperation: ListChannelsOperation? = nil,
        listPostsOperation: ListPostsOperation? = nil,
        connectChannelOperation: ConnectChannelOperation? = nil,
        disconnectChannelOperation: DisconnectChannelOperation? = nil,
        probeChannelOperation: ProbeChannelOperation? = nil,
        createPostOperation: CreatePostOperation? = nil,
        attachSupervisor: Bool = true,
        initialState: State = .idle,
        workspaceId initialWorkspaceId: String? = nil
    ) {
        let resolvedClient = client ?? ClawJSPublishingClient()
        self.client = resolvedClient
        self.bootstrapAvailabilityOperation = bootstrapAvailabilityOperation ?? {
            let snapshot = ClawJSServiceManager.shared.snapshots[.publishing]
            guard snapshot?.state.isReady == true else {
                return snapshot?.state.unavailableReason ?? "Publishing service is not running."
            }
            return nil
        }
        self.bootstrapOperation = bootstrapOperation
        self.listFamiliesOperation = listFamiliesOperation ?? {
            try await resolvedClient.listFamilies()
        }
        self.listChannelsOperation = listChannelsOperation ?? { workspaceId in
            try await resolvedClient.listChannels(workspaceId: workspaceId)
        }
        self.listPostsOperation = listPostsOperation ?? { workspaceId, from, to in
            try await resolvedClient.listPosts(workspaceId: workspaceId, from: from, to: to)
        }
        self.connectChannelOperation = connectChannelOperation ?? { workspaceId, familyId, payload in
            try await resolvedClient.connectChannel(workspaceId: workspaceId, familyId: familyId, payload: payload)
        }
        self.disconnectChannelOperation = disconnectChannelOperation ?? { workspaceId, accountId in
            try await resolvedClient.disconnectChannel(workspaceId: workspaceId, accountId: accountId)
        }
        self.probeChannelOperation = probeChannelOperation ?? { workspaceId, accountId in
            try await resolvedClient.probeChannel(workspaceId: workspaceId, accountId: accountId)
        }
        self.createPostOperation = createPostOperation ?? { workspaceId, spec in
            try await resolvedClient.createPost(workspaceId: workspaceId, spec: spec)
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
        familiesRefreshTask?.cancel()
        channelsRefreshTask?.cancel()
        calendarRefreshTask?.cancel()
        for task in connectTasks.values { task.cancel() }
        for task in channelActionTasks.values { task.cancel() }
        createPostTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Loads the host-session admin token and resolves (or creates) the
    /// "Default" workspace. Idempotent: re-entry while a bootstrap is in
    /// flight is a no-op.
    func bootstrap() {
        guard bootstrapTask == nil else { return }
        if let unavailableReason = bootstrapAvailabilityOperation() {
            state = .unavailable(unavailableReason)
            return
        }
        let generation = nextBootstrapGeneration()
        state = .bootstrapping
        bootstrapTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runBootstrap(generation: generation)
        }
    }

    private func runBootstrap(generation: Int) async {
        do {
            let result: BootstrapResult
            if let bootstrapOperation {
                result = try await bootstrapOperation()
            } else {
                result = try await performDefaultBootstrap()
            }
            try Task.checkCancellation()
            guard isCurrentBootstrap(generation) else { return }
            workspaceId = result.workspaceId
            client.workspaceId = result.workspaceId
            families = result.families
            channels = result.channels
            state = .ready
            lastError = nil
        } catch is CancellationError {
        } catch {
            guard isCurrentBootstrap(generation) else { return }
            state = .unavailable(error.localizedDescription)
            lastError = error.localizedDescription
        }
        finishBootstrapIfCurrent(generation)
    }

    private func performDefaultBootstrap() async throws -> BootstrapResult {
        guard let token = ClawJSServiceManager.shared.adminTokenIfSpawned(for: .publishing) else {
            throw NSError(domain: "PublishingWorkspaceStore", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Publishing admin token is available only to the host process that launched the service."
            ])
        }
        client.bearerToken = token
        try await ensureDefaultWorkspace()
        let resolvedWorkspaceId = workspaceId
        async let families = listFamiliesOperation()
        async let channels = listChannelsOperation(resolvedWorkspaceId ?? "")
        let resolvedFamilies = try await families
        let resolvedChannels = try await channels
        return BootstrapResult(
            workspaceId: resolvedWorkspaceId,
            families: resolvedFamilies,
            channels: resolvedChannels
        )
    }

    /// Drops any in-memory state. Used when the supervisor reports the
    /// service is down so views render an empty state instead of stale
    /// data from a previous boot.
    func reset(reason: String) {
        bootstrapGeneration += 1
        bootstrapTask?.cancel()
        bootstrapTask = nil
        familiesRefreshGeneration += 1
        familiesRefreshTask?.cancel()
        familiesRefreshTask = nil
        channelsRefreshGeneration += 1
        channelsRefreshTask?.cancel()
        channelsRefreshTask = nil
        calendarRefreshGeneration += 1
        calendarRefreshTask?.cancel()
        calendarRefreshTask = nil
        for task in connectTasks.values { task.cancel() }
        connectTasks.removeAll()
        for key in Array(connectGenerations.keys) {
            connectGenerations[key, default: 0] += 1
        }
        for task in channelActionTasks.values { task.cancel() }
        channelActionTasks.removeAll()
        for key in Array(channelActionGenerations.keys) {
            channelActionGenerations[key, default: 0] += 1
        }
        createPostGeneration += 1
        createPostTask?.cancel()
        createPostTask = nil
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
        let generation = nextFamiliesRefreshGeneration()
        familiesRefreshTask?.cancel()
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            await self.runFamiliesRefresh(generation: generation)
        }
        familiesRefreshTask = task
        await task.value
    }

    private func runFamiliesRefresh(generation: Int) async {
        do {
            let families = try await listFamiliesOperation()
            try Task.checkCancellation()
            guard isCurrentFamiliesRefresh(generation) else { return }
            self.families = families
            lastError = nil
        } catch is CancellationError {
        } catch {
            guard isCurrentFamiliesRefresh(generation) else { return }
            lastError = error.localizedDescription
        }
        finishFamiliesRefreshIfCurrent(generation)
    }

    func refreshChannels() async {
        guard let workspaceId, state == .ready else { return }
        let generation = nextChannelsRefreshGeneration()
        channelsRefreshTask?.cancel()
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            await self.runChannelsRefresh(workspaceId: workspaceId, generation: generation)
        }
        channelsRefreshTask = task
        await task.value
    }

    private func runChannelsRefresh(workspaceId: String, generation: Int) async {
        do {
            let channels = try await listChannelsOperation(workspaceId)
            try Task.checkCancellation()
            guard isCurrentChannelsRefresh(generation) else { return }
            self.channels = channels
            lastError = nil
        } catch is CancellationError {
        } catch {
            guard isCurrentChannelsRefresh(generation) else { return }
            lastError = error.localizedDescription
        }
        finishChannelsRefreshIfCurrent(generation)
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
        let generation = nextConnectGeneration(key: familyId)
        connectTasks[familyId]?.cancel()
        let task = Task<Result<ClawJSPublishingClient.ChannelAccount, Swift.Error>, Never> { @MainActor [weak self] in
            guard let self else { return .failure(CancellationError()) }
            return await self.runConnect(
                key: familyId,
                generation: generation,
                workspaceId: workspaceId,
                familyId: familyId,
                payload: payload
            )
        }
        connectTasks[familyId] = task
        switch await task.value {
        case .success(let account): return account
        case .failure(let error): throw error
        }
    }

    private func runConnect(
        key: String,
        generation: Int,
        workspaceId: String,
        familyId: String,
        payload: [String: String]
    ) async -> Result<ClawJSPublishingClient.ChannelAccount, Swift.Error> {
        do {
            let account = try await connectChannelOperation(
                workspaceId,
                familyId,
                payload
            )
            try Task.checkCancellation()
            guard isCurrentConnect(key: key, generation: generation) else { return .failure(CancellationError()) }
            upsertChannel(account)
            lastError = nil
            finishConnectIfCurrent(key: key, generation: generation)
            return .success(account)
        } catch is CancellationError {
            return .failure(CancellationError())
        } catch {
            guard isCurrentConnect(key: key, generation: generation) else { return .failure(CancellationError()) }
            lastError = error.localizedDescription
            finishConnectIfCurrent(key: key, generation: generation)
            return .failure(error)
        }
    }

    func disconnect(account: ClawJSPublishingClient.ChannelAccount) async {
        guard let workspaceId else { return }
        let key = "disconnect:\(account.id)"
        let generation = nextChannelActionGeneration(key: key)
        channelActionTasks[key]?.cancel()
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            await self.runDisconnect(key: key, generation: generation, workspaceId: workspaceId, account: account)
        }
        channelActionTasks[key] = task
        await task.value
    }

    private func runDisconnect(
        key: String,
        generation: Int,
        workspaceId: String,
        account: ClawJSPublishingClient.ChannelAccount
    ) async {
        do {
            _ = try await disconnectChannelOperation(workspaceId, account.id)
            try Task.checkCancellation()
            guard isCurrentChannelAction(key: key, generation: generation) else { return }
            channels.removeAll { $0.id == account.id }
            lastError = nil
        } catch is CancellationError {
        } catch {
            guard isCurrentChannelAction(key: key, generation: generation) else { return }
            lastError = error.localizedDescription
        }
        finishChannelActionIfCurrent(key: key, generation: generation)
    }

    func probe(account: ClawJSPublishingClient.ChannelAccount) async {
        guard let workspaceId else { return }
        let key = "probe:\(account.id)"
        let generation = nextChannelActionGeneration(key: key)
        channelActionTasks[key]?.cancel()
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            await self.runProbe(key: key, generation: generation, workspaceId: workspaceId, account: account)
        }
        channelActionTasks[key] = task
        await task.value
    }

    private func runProbe(
        key: String,
        generation: Int,
        workspaceId: String,
        account: ClawJSPublishingClient.ChannelAccount
    ) async {
        do {
            _ = try await probeChannelOperation(workspaceId, account.id)
            try Task.checkCancellation()
            guard isCurrentChannelAction(key: key, generation: generation) else { return }
            lastError = nil
        } catch is CancellationError {
        } catch {
            guard isCurrentChannelAction(key: key, generation: generation) else { return }
            lastError = error.localizedDescription
        }
        finishChannelActionIfCurrent(key: key, generation: generation)
    }

    @discardableResult
    func createPost(spec: ClawJSPublishingClient.PostSpec) async throws -> ClawJSPublishingClient.Post {
        guard let workspaceId else { throw ClawJSPublishingClient.Error.serviceNotReady }
        let generation = nextCreatePostGeneration()
        createPostTask?.cancel()
        let task = Task<Result<ClawJSPublishingClient.Post, Swift.Error>, Never> { @MainActor [weak self] in
            guard let self else { return .failure(CancellationError()) }
            return await self.runCreatePost(workspaceId: workspaceId, spec: spec, generation: generation)
        }
        createPostTask = task
        switch await task.value {
        case .success(let post): return post
        case .failure(let error): throw error
        }
    }

    private func runCreatePost(
        workspaceId: String,
        spec: ClawJSPublishingClient.PostSpec,
        generation: Int
    ) async -> Result<ClawJSPublishingClient.Post, Swift.Error> {
        do {
            let post = try await createPostOperation(workspaceId, spec)
            try Task.checkCancellation()
            guard isCurrentCreatePost(generation) else { return .failure(CancellationError()) }
            posts.append(post)
            lastError = nil
            finishCreatePostIfCurrent(generation)
            return .success(post)
        } catch is CancellationError {
            return .failure(CancellationError())
        } catch {
            guard isCurrentCreatePost(generation) else { return .failure(CancellationError()) }
            lastError = error.localizedDescription
            finishCreatePostIfCurrent(generation)
            return .failure(error)
        }
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

    private func upsertChannel(_ account: ClawJSPublishingClient.ChannelAccount) {
        if let index = channels.firstIndex(where: { $0.id == account.id }) {
            channels[index] = account
        } else {
            channels.append(account)
        }
    }

    private func nextBootstrapGeneration() -> Int {
        bootstrapGeneration += 1
        return bootstrapGeneration
    }

    private func isCurrentBootstrap(_ generation: Int) -> Bool {
        bootstrapGeneration == generation
    }

    private func finishBootstrapIfCurrent(_ generation: Int) {
        guard isCurrentBootstrap(generation) else { return }
        bootstrapTask = nil
    }

    private func nextFamiliesRefreshGeneration() -> Int {
        familiesRefreshGeneration += 1
        return familiesRefreshGeneration
    }

    private func isCurrentFamiliesRefresh(_ generation: Int) -> Bool {
        familiesRefreshGeneration == generation
    }

    private func finishFamiliesRefreshIfCurrent(_ generation: Int) {
        guard isCurrentFamiliesRefresh(generation) else { return }
        familiesRefreshTask = nil
    }

    private func nextChannelsRefreshGeneration() -> Int {
        channelsRefreshGeneration += 1
        return channelsRefreshGeneration
    }

    private func isCurrentChannelsRefresh(_ generation: Int) -> Bool {
        channelsRefreshGeneration == generation
    }

    private func finishChannelsRefreshIfCurrent(_ generation: Int) {
        guard isCurrentChannelsRefresh(generation) else { return }
        channelsRefreshTask = nil
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

    private func nextConnectGeneration(key: String) -> Int {
        let generation = (connectGenerations[key] ?? 0) + 1
        connectGenerations[key] = generation
        return generation
    }

    private func isCurrentConnect(key: String, generation: Int) -> Bool {
        connectGenerations[key] == generation
    }

    private func finishConnectIfCurrent(key: String, generation: Int) {
        guard isCurrentConnect(key: key, generation: generation) else { return }
        connectTasks.removeValue(forKey: key)
    }

    private func nextChannelActionGeneration(key: String) -> Int {
        let generation = (channelActionGenerations[key] ?? 0) + 1
        channelActionGenerations[key] = generation
        return generation
    }

    private func isCurrentChannelAction(key: String, generation: Int) -> Bool {
        channelActionGenerations[key] == generation
    }

    private func finishChannelActionIfCurrent(key: String, generation: Int) {
        guard isCurrentChannelAction(key: key, generation: generation) else { return }
        channelActionTasks.removeValue(forKey: key)
    }

    private func nextCreatePostGeneration() -> Int {
        createPostGeneration += 1
        return createPostGeneration
    }

    private func isCurrentCreatePost(_ generation: Int) -> Bool {
        createPostGeneration == generation
    }

    private func finishCreatePostIfCurrent(_ generation: Int) {
        guard isCurrentCreatePost(generation) else { return }
        createPostTask = nil
    }
}
