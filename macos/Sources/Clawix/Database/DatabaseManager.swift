import Foundation
import SwiftUI
import Combine
import ClawixCore

/// Singleton observable manager for the bundled `@clawjs/database`
/// daemon. Mirrors the role of `SecretsManager` for Secrets service.
///
/// Owns:
///   - The HTTP client (`DatabaseClient`) with a fresh JWT.
///   - The realtime WebSocket client.
///   - The list of collections discovered in the active namespace.
///   - Per-collection in-memory record caches, refreshed on subscribe.
///
/// State machine:
///   .loading -> .bootstrapping -> .ready
///   any state -> .failed(reason) on hard error
///   .ready re-enters .bootstrapping when the supervisor restarts the
///   daemon (we observe `ClawJSServiceManager` snapshots).
@MainActor
final class DatabaseManager: ObservableObject {
    typealias AdminTokenOperation = @MainActor () throws -> String
    static let defaultRecordPageLimit = 100

    enum State: Equatable {
        case loading
        case bootstrapping
        case ready
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var lastError: String?
    @Published private(set) var collections: [DBCollection] = []
    @Published private(set) var currentNamespace: String = "clawix-local"
    @Published private(set) var lastEventAt: Date?

    /// Per-collection visible record windows. Keys are collection names; values
    /// are bounded pages returned by the server plus realtime patches applied
    /// inside the active window.
    @Published private(set) var recordWindowsByCollection: [String: DBRecordWindow] = [:]

    /// Per-collection filter+sort state, persisted in UserDefaults.
    @Published var filterByCollection: [String: DBFilterState] = [:]

    /// In-flight tasks per collection so we can cancel a stale fetch when
    /// the user changes filter quickly.
    private var inFlight: [String: Task<Void, Never>] = [:]
    private var realtimeRefreshTasks: [String: Task<Void, Never>] = [:]
    private var recordRefreshGeneration: [String: Int] = [:]
    private var mutationTasks: [DatabaseMutationKey: DatabaseMutationTask] = [:]
    private var mutationGenerations: [DatabaseMutationKey: Int] = [:]

    private(set) var client: any DatabaseClienting
    let realtime = DatabaseRealtimeClient()

    private let userDefaults: UserDefaults
    private let filterStateKey = "clawix.database.filterStates.v1"
    private let isDisabled: Bool

    private var supervisorObserver: AnyCancellable?
    private var bootstrapTask: Task<Void, Never>?
    private var bootstrapTimeoutTask: Task<Void, Never>?
    private var bootstrapGeneration = 0
    private let adminTokenOperation: AdminTokenOperation

    init(
        userDefaults: UserDefaults = .standard,
        client: (any DatabaseClienting)? = nil,
        adminTokenOperation: AdminTokenOperation? = nil,
        attachSupervisor: Bool = true,
        initialState: State = .loading,
        initialCollections: [DBCollection] = []
    ) {
        self.userDefaults = userDefaults
        self.client = client ?? DatabaseClient()
        self.adminTokenOperation = adminTokenOperation ?? {
            try DatabaseAdminToken.currentAdminToken()
        }
        self.isDisabled = ClawixEnv.isEnabled(ClawixEnv.databaseDisable)
        self.state = initialState
        self.collections = initialCollections
        loadFilterStates()
        realtime.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.applyEvent(event)
            }
        }
        guard !isDisabled else {
            state = .failed("Database service is disabled for this launch.")
            return
        }
        if attachSupervisor {
            attachSupervisorObserver()
        }
    }

    deinit {
        bootstrapTask?.cancel()
        bootstrapTimeoutTask?.cancel()
        for task in inFlight.values { task.cancel() }
        for task in realtimeRefreshTasks.values { task.cancel() }
        for task in mutationTasks.values { task.cancel() }
        Task { @MainActor [realtime] in
            realtime.disconnect()
        }
    }

    /// Observes `ClawJSServiceManager.shared.snapshots[.database]` and
    /// kicks off `bootstrap()` whenever the supervisor flips that service
    /// to `.ready`. If the daemon crashes and gets restarted, we re-issue
    /// `bootstrap()` so we get a fresh JWT, recover the WS subscription,
    /// and reload collections. Cheap: bootstrap is idempotent.
    private func attachSupervisorObserver() {
        let supervisor = ClawJSServiceManager.shared
        supervisorObserver = supervisor.$snapshots.sink { [weak self] snapshots in
            guard let self else { return }
            guard let snap = snapshots[.database] else { return }
            switch snap.state {
            case .ready, .readyFromDaemon:
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if case .ready = self.state { return }
                    await self.bootstrap()
                }
            case .crashed, .blocked, .idle, .daemonUnavailable:
                self.cancelSurfaceWork(disconnectRealtime: true)
                self.collections = []
                self.recordWindowsByCollection = [:]
                self.state = .failed(snap.state.unavailableReason ?? "Database service is unavailable.")
            case .availableOnDemand:
                self.cancelSurfaceWork(disconnectRealtime: true)
                self.collections = []
                self.recordWindowsByCollection = [:]
                self.state = .loading
            case .starting:
                if case .ready = self.state { self.realtime.disconnect() }
                self.state = .bootstrapping
                break
            }
        }
    }

    // MARK: - Bootstrap

    /// Establishes a JWT-authenticated client and ensures the namespace
    /// exists. Idempotent. Called automatically when the supervisor
    /// flips `database` to `.ready` and on app foregrounding.
    func bootstrap(force: Bool = false) async {
        guard !isDisabled else { return }
        if case .ready = state, !force { return }
        let generation = nextBootstrapGeneration()
        bootstrapTask?.cancel()
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            await self.runBootstrap(generation: generation)
        }
        bootstrapTask = task
        await task.value
    }

    private func runBootstrap(generation: Int) async {
        state = .bootstrapping
        bootstrapTimeoutTask?.cancel()
        bootstrapTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, self.bootstrapGeneration == generation else { return }
            if case .bootstrapping = self.state {
                self.state = .failed("Database service did not become ready within 8 seconds.")
            }
        }
        do {
            client.bearerToken = try adminTokenOperation()
            _ = try await client.ensureNamespace(id: currentNamespace, displayName: "Clawix Local")
            try Task.checkCancellation()
            guard isCurrentBootstrap(generation) else { return }
            let listedCollections = try await client.listCollections(namespaceId: currentNamespace)
            try Task.checkCancellation()
            guard isCurrentBootstrap(generation) else { return }
            let collections = try await ensureArchivalFields(in: listedCollections)
            try Task.checkCancellation()
            guard isCurrentBootstrap(generation) else { return }
            self.collections = collections.sorted { lhs, rhs in
                if lhs.builtin != rhs.builtin { return lhs.builtin && !rhs.builtin }
                return lhs.displayName < rhs.displayName
            }
            realtime.configure(
                origin: client.origin,
                bearer: client.bearerToken
            )
            realtime.connect()
            state = .ready
            lastError = nil
        } catch is CancellationError {
        } catch {
            guard isCurrentBootstrap(generation) else { return }
            let message = Self.failureMessage(for: error, surface: "database.bootstrap")
            state = .failed(message)
            lastError = message
        }
        finishBootstrapIfCurrent(generation)
    }

    private func ensureArchivalFields(in collections: [DBCollection]) async throws -> [DBCollection] {
        var normalized = collections
        for (index, collection) in collections.enumerated() where collection.builtin {
            guard !collection.fields.contains(where: { $0.name == "archivedAt" }) else { continue }
            let archivedAt = DBFieldDefinition(
                name: "archivedAt",
                type: .date,
                required: nil,
                options: nil,
                relation: nil
            )
            normalized[index] = try await client.updateCollection(
                namespaceId: currentNamespace,
                name: collection.name,
                displayName: collection.displayName,
                fields: collection.fields + [archivedAt],
                indexes: collection.indexes
            )
        }
        return normalized
    }

    // MARK: - Records

    func collection(named name: String) -> DBCollection? {
        collections.first(where: { $0.name == name })
    }

    func filterState(for collection: String) -> DBFilterState {
        filterByCollection[collection] ?? DBFilterState()
    }

    func setFilterState(_ state: DBFilterState, for collection: String) {
        filterByCollection[collection] = state
        persistFilterStates()
        requestRefreshRecords(collection: collection)
    }

    func requestRefreshRecords(collection name: String) {
        inFlight[name]?.cancel()
        inFlight[name] = Task { @MainActor [weak self] in
            await self?.refreshRecords(collection: name)
        }
    }

    func cancelRecordRefresh(collection name: String) {
        inFlight[name]?.cancel()
        inFlight[name] = nil
        recordRefreshGeneration[name, default: 0] += 1
    }

    func cancelCollectionSurfaceWork(collection name: String) {
        cancelRecordRefresh(collection: name)
        realtimeRefreshTasks[name]?.cancel()
        realtimeRefreshTasks[name] = nil
    }

    func cancelSurfaceWork(disconnectRealtime: Bool = true) {
        bootstrapGeneration += 1
        bootstrapTask?.cancel()
        bootstrapTask = nil
        bootstrapTimeoutTask?.cancel()
        bootstrapTimeoutTask = nil
        if case .bootstrapping = state {
            state = .loading
        }
        for name in Array(inFlight.keys) {
            cancelRecordRefresh(collection: name)
        }
        for task in realtimeRefreshTasks.values { task.cancel() }
        realtimeRefreshTasks.removeAll()
        for key in Array(mutationGenerations.keys) {
            mutationGenerations[key, default: 0] += 1
        }
        for task in mutationTasks.values { task.cancel() }
        mutationTasks.removeAll()
        if disconnectRealtime {
            realtime.disconnect()
        } else {
            realtime.unsubscribe()
        }
    }

    func refreshRecords(collection name: String) async {
        await loadRecordWindow(collection: name, offset: 0, appending: false)
    }

    func requestLoadNextRecordsPage(collection name: String) {
        inFlight[name]?.cancel()
        inFlight[name] = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.loadNextRecordsPage(collection: name)
        }
    }

    func loadNextRecordsPage(collection name: String) async {
        guard let window = recordWindowsByCollection[name], window.hasNextPage else { return }
        await loadRecordWindow(collection: name, offset: window.nextOffset, appending: true)
    }

    private func loadRecordWindow(collection name: String, offset: Int, appending: Bool) async {
        guard let _ = collection(named: name) else { return }
        guard case .ready = state else { return }
        let filter = filterState(for: name)
        recordRefreshGeneration[name, default: 0] += 1
        let generation = recordRefreshGeneration[name, default: 0]
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let response = try await self.client.listRecords(
                    namespaceId: self.currentNamespace,
                    collection: name,
                    filter: filter.backendFilterJSON(),
                    sort: filter.sortString(),
                    limit: Self.defaultRecordPageLimit,
                    offset: offset
                )
                try Task.checkCancellation()
                guard self.recordRefreshGeneration[name] == generation else { return }
                let post = filter.clientSidePostFilter(records: response.items)
                let existing = appending ? self.recordWindowsByCollection[name]?.records ?? [] : []
                let records = self.mergeRecords(existing + post, using: filter.sort)
                let total = response.total ?? max(records.count, offset + response.items.count)
                self.recordWindowsByCollection[name] = DBRecordWindow(
                    records: records,
                    total: total,
                    limit: Self.defaultRecordPageLimit,
                    offset: offset
                )
                self.inFlight[name] = nil
            } catch is CancellationError {
                if self.recordRefreshGeneration[name] == generation {
                    self.inFlight[name] = nil
                }
            } catch {
                if self.recordRefreshGeneration[name] == generation {
                    self.lastError = Self.failureMessage(for: error, surface: "database.records.refresh")
                    self.inFlight[name] = nil
                }
            }
        }
        inFlight[name] = task
        _ = await task.value
    }

    func subscribeRealtime(collection name: String) {
        realtime.subscribe(namespaceId: currentNamespace, collection: name)
    }

    func createRecord(collection name: String, data: [String: DBJSON]) async throws -> DBRecord {
        let key = DatabaseMutationKey(kind: .create, collection: name, id: UUID().uuidString)
        let generation = nextMutationGeneration(for: key)
        let record = try await performMutation(key: key, generation: generation) {
            try await self.client.createRecord(
                namespaceId: self.currentNamespace,
                collection: name,
                data: data
            )
        }
        upsertRecordInCache(record, collection: name)
        return record
    }

    func updateRecord(
        collection name: String,
        id: String,
        data: [String: DBJSON]
    ) async throws -> DBRecord {
        let key = DatabaseMutationKey(kind: .update, collection: name, id: id)
        let generation = nextMutationGeneration(for: key)
        let updated = try await performMutation(key: key, generation: generation) {
            try await self.client.updateRecord(
                namespaceId: self.currentNamespace,
                collection: name,
                id: id,
                data: data
            )
        }
        upsertRecordInCache(updated, collection: name)
        return updated
    }

    func deleteRecord(collection name: String, id: String) async throws {
        let key = DatabaseMutationKey(kind: .delete, collection: name, id: id)
        let generation = nextMutationGeneration(for: key)
        _ = try await performMutation(key: key, generation: generation) {
            try await self.client.deleteRecord(namespaceId: self.currentNamespace, collection: name, id: id)
        }
        if let window = recordWindowsByCollection[name] {
            var current = window.records
            current.removeAll { $0.id == id }
            recordWindowsByCollection[name] = DBRecordWindow(
                records: current,
                total: max(0, window.total - 1),
                limit: window.limit,
                offset: window.offset
            )
        }
    }

    func archiveRecord(collection name: String, id: String) async throws {
        let nowIso = ISO8601DateFormatter().string(from: Date())
        _ = try await updateRecord(
            collection: name,
            id: id,
            data: ["archivedAt": .string(nowIso)]
        )
    }

    func restoreRecord(collection name: String, id: String) async throws {
        _ = try await updateRecord(
            collection: name,
            id: id,
            data: ["archivedAt": .null]
        )
    }

    private func performMutation<T>(
        key: DatabaseMutationKey,
        generation: Int,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        mutationTasks[key]?.cancel()
        let task = Task<T, Error> {
            try await operation()
        }
        mutationTasks[key] = DatabaseMutationTask(cancel: { task.cancel() })
        do {
            let value = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            try Task.checkCancellation()
            guard isCurrentMutation(key: key, generation: generation) else { throw CancellationError() }
            lastError = nil
            finishMutationIfCurrent(key: key, generation: generation)
            return value
        } catch is CancellationError {
            finishMutationIfCurrent(key: key, generation: generation)
            throw CancellationError()
        } catch {
            guard isCurrentMutation(key: key, generation: generation) else { throw CancellationError() }
            lastError = Self.failureMessage(for: error, surface: "database.mutation")
            finishMutationIfCurrent(key: key, generation: generation)
            throw error
        }
    }

    private static func failureMessage(for error: Error, surface: String) -> String {
        let rawMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return UserFacingFailure.displayMessage(for: rawMessage, surface: surface)
    }

    /// Returns a flat list of records with the current filter applied
    /// (server-side + client-side post filter). Used by views.
    func records(for collection: String) -> [DBRecord] {
        recordWindowsByCollection[collection]?.records ?? []
    }

    func recordWindow(for collection: String) -> DBRecordWindow? {
        recordWindowsByCollection[collection]
    }

    // MARK: - Realtime

    private func applyEvent(_ event: DBRecordEvent) {
        guard event.namespaceId == currentNamespace else { return }
        let name = event.collectionName
        var current = recordWindowsByCollection[name]?.records ?? []
        switch event.type {
        case .created:
            if let record = event.record {
                upsertRecordInCache(record, collection: name)
                scheduleRealtimeRefresh(collection: name)
                return
            }
        case .updated:
            if let record = event.record {
                upsertRecordInCache(record, collection: name)
                scheduleRealtimeRefresh(collection: name)
                return
            }
        case .deleted:
            let removedFromWindow = current.contains { $0.id == event.recordId }
            current.removeAll { $0.id == event.recordId }
            scheduleRealtimeRefresh(collection: name)
            if let window = recordWindowsByCollection[name] {
                recordWindowsByCollection[name] = DBRecordWindow(
                    records: current,
                    total: removedFromWindow ? max(0, window.total - 1) : window.total,
                    limit: window.limit,
                    offset: window.offset
                )
            }
            lastEventAt = Date()
            return
        }
        lastEventAt = Date()
    }

    private func scheduleRealtimeRefresh(collection name: String) {
        realtimeRefreshTasks[name]?.cancel()
        realtimeRefreshTasks[name] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await self?.refreshRecords(collection: name)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await self?.refreshRecords(collection: name)
        }
    }

    private func upsertRecordInCache(_ record: DBRecord, collection name: String) {
        let filter = filterState(for: name)
        let matches = !filter.clientSidePostFilter(records: [record]).isEmpty
        let window = recordWindowsByCollection[name]
        var current = window?.records ?? []
        current.removeAll { $0.id == record.id }
        if matches {
            current.insert(record, at: 0)
        }
        recordWindowsByCollection[name] = DBRecordWindow(
            records: mergeRecords(current, using: filter.sort),
            total: max(window?.total ?? 0, current.count),
            limit: window?.limit ?? Self.defaultRecordPageLimit,
            offset: window?.offset ?? 0
        )
        lastEventAt = Date()
    }

    private func mergeRecords(_ records: [DBRecord], using sort: DBFilterState.Sort?) -> [DBRecord] {
        var seen = Set<String>()
        let unique = records.filter { record in
            guard !seen.contains(record.id) else { return false }
            seen.insert(record.id)
            return true
        }
        return sortRecords(unique, using: sort)
    }

    private func sortRecords(_ records: [DBRecord], using sort: DBFilterState.Sort?) -> [DBRecord] {
        guard let sort else { return records }
        return records.sorted { lhs, rhs in
            let result = compareSortValue(
                sortValue(for: lhs, field: sort.field),
                sortValue(for: rhs, field: sort.field)
            )
            if result == .orderedSame {
                return lhs.updatedAt > rhs.updatedAt
            }
            return sort.descending ? result == .orderedDescending : result == .orderedAscending
        }
    }

    private func sortValue(for record: DBRecord, field: String) -> DBJSON {
        switch field {
        case "id": return .string(record.id)
        case "createdAt": return .string(record.createdAt)
        case "updatedAt": return .string(record.updatedAt)
        default: return record.data[field] ?? .null
        }
    }

    private func compareSortValue(_ lhs: DBJSON, _ rhs: DBJSON) -> ComparisonResult {
        if let lhsNumber = lhs.doubleValue, let rhsNumber = rhs.doubleValue {
            if lhsNumber < rhsNumber { return .orderedAscending }
            if lhsNumber > rhsNumber { return .orderedDescending }
            return .orderedSame
        }
        let lhsString = lhs.stringValue ?? ""
        let rhsString = rhs.stringValue ?? ""
        return lhsString.localizedStandardCompare(rhsString)
    }

    // MARK: - Persistence

    private func loadFilterStates() {
        guard let data = userDefaults.data(forKey: filterStateKey) else { return }
        if let decoded = try? JSONDecoder().decode([String: DBFilterState].self, from: data) {
            filterByCollection = decoded
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
        bootstrapTimeoutTask?.cancel()
        bootstrapTimeoutTask = nil
    }

    private func nextMutationGeneration(for key: DatabaseMutationKey) -> Int {
        let generation = (mutationGenerations[key] ?? 0) + 1
        mutationGenerations[key] = generation
        return generation
    }

    private func isCurrentMutation(key: DatabaseMutationKey, generation: Int) -> Bool {
        mutationGenerations[key] == generation
    }

    private func finishMutationIfCurrent(key: DatabaseMutationKey, generation: Int) {
        guard isCurrentMutation(key: key, generation: generation) else { return }
        mutationTasks[key] = nil
        mutationGenerations[key] = generation
    }

    private struct DatabaseMutationTask {
        let cancel: () -> Void
    }

    private struct DatabaseMutationKey: Hashable {
        let kind: Kind
        let collection: String
        let id: String

        enum Kind: Hashable {
            case create
            case update
            case delete
        }
    }

    private func persistFilterStates() {
        if let data = try? JSONEncoder().encode(filterByCollection) {
            userDefaults.set(data, forKey: filterStateKey)
        }
    }
}
