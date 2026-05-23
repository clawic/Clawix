import Combine
import Foundation

enum IndexStoreState: Equatable {
    case idle
    case loading
    case ready
    case error(String)
}

struct IndexQueryCriteria: Equatable {
    var type: String?
    var tagIds: [String] = []
    var collectionId: String?
    var fullText: String = ""
    var limit: Int = 100
}

struct IndexSnapshot: Equatable {
    var state: IndexStoreState = .idle
    var types: [ClawJSIndexClient.EntityType] = []
    var typeCounts: [String: Int] = [:]
    var entities: [ClawJSIndexClient.Entity] = []
    var entityNextCursor: String?
    var entityCriteria = IndexQueryCriteria()
    var isLoadingEntities = false
    var searches: [ClawJSIndexClient.Search] = []
    var monitors: [ClawJSIndexClient.Monitor] = []
    var runs: [ClawJSIndexClient.Run] = []
    var alerts: [ClawJSIndexClient.Alert] = []
    var unreadAlerts: Int = 0
    var tags: [ClawJSIndexClient.Tag] = []
    var collections: [ClawJSIndexClient.Collection] = []
}

/// State store for the Index tab. Owns the loopback HTTP client and exposes
/// one published snapshot SwiftUI binds to. Mirrors the Memory store pattern
/// without a master-password lock.
@MainActor
final class IndexStore: ObservableObject {

    typealias State = IndexStoreState

    @Published private(set) var snapshot = IndexSnapshot()

    private var client: any ClawJSIndexClienting
    private var supervisorObserver: AnyCancellable?
    private var refreshTask: Task<Void, Never>?
    private var entityLoadTask: Task<Void, Never>?
    private var searchDebounceTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private var entityLoadGeneration = 0
    private var actionGenerations: [IndexActionKey: Int] = [:]
    private var actionTaskCancellations: [IndexActionKey: [UUID: () -> Void]] = [:]

    var state: State { snapshot.state }
    var types: [ClawJSIndexClient.EntityType] { snapshot.types }
    var typeCounts: [String: Int] { snapshot.typeCounts }
    var entities: [ClawJSIndexClient.Entity] { snapshot.entities }
    var searches: [ClawJSIndexClient.Search] { snapshot.searches }
    var monitors: [ClawJSIndexClient.Monitor] { snapshot.monitors }
    var runs: [ClawJSIndexClient.Run] { snapshot.runs }
    var alerts: [ClawJSIndexClient.Alert] { snapshot.alerts }
    var unreadAlerts: Int { snapshot.unreadAlerts }
    var tags: [ClawJSIndexClient.Tag] { snapshot.tags }
    var collections: [ClawJSIndexClient.Collection] { snapshot.collections }

    init(
        client: (any ClawJSIndexClienting)? = nil,
        attachSupervisor: Bool = true
    ) {
        if let client {
            self.client = client
        } else {
            let token = ClawJSServiceManager.shared.adminTokenIfSpawned(for: .index)
                ?? (try? ClawJSServiceManager.adminTokenFromTokenFile(for: .index))
            self.client = ClawJSIndexClient(bearerToken: token)
        }
        if attachSupervisor {
            attachSupervisorObserver()
        }
    }

    deinit {
        refreshTask?.cancel()
        entityLoadTask?.cancel()
        searchDebounceTask?.cancel()
        for cancellations in actionTaskCancellations.values {
            cancellations.values.forEach { $0() }
        }
    }

    private func attachSupervisorObserver() {
        supervisorObserver = ClawJSServiceManager.shared.$snapshots
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshots in
                guard let self else { return }
                if let snap = snapshots[.index], snap.state.isReady, self.state == .idle {
                    self.requestRefresh()
                }
            }
    }

    func ensureToken() {
        if client.bearerToken == nil {
            let token = ClawJSServiceManager.shared.adminTokenIfSpawned(for: .index)
                ?? (try? ClawJSServiceManager.adminTokenFromTokenFile(for: .index))
            client.bearerToken = token
        }
    }

    private func updateSnapshot(_ mutate: (inout IndexSnapshot) -> Void) {
        var next = snapshot
        mutate(&next)
        snapshot = next
    }

    func surfaceActionError(_ error: Error) {
        if error is CancellationError { return }
        updateSnapshot { $0.state = .error(Self.failureMessage(for: error, surface: "index.action")) }
    }

    func requestRefresh() {
        _ = startRefresh()
    }

    func requestLoadEntities() {
        _ = startEntityLoad(reset: true)
    }

    func selectTypeFilter(_ type: String?) {
        var criteria = snapshot.entityCriteria
        criteria.type = type
        applyEntityCriteria(criteria)
    }

    func selectTagFilter(_ tagId: String?) {
        var criteria = snapshot.entityCriteria
        criteria.tagIds = tagId.map { [$0] } ?? []
        applyEntityCriteria(criteria)
    }

    func selectCollectionFilter(_ collectionId: String?) {
        var criteria = snapshot.entityCriteria
        criteria.collectionId = collectionId
        applyEntityCriteria(criteria)
    }

    func updateFullTextQuery(_ query: String) {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
                guard let self else { return }
                var criteria = self.snapshot.entityCriteria
                criteria.fullText = query
                self.applyEntityCriteria(criteria)
            } catch is CancellationError {
            } catch {
            }
        }
    }

    func loadMoreEntitiesIfNeeded(currentEntityId: String?) {
        guard currentEntityId == snapshot.entities.last?.id else { return }
        guard snapshot.entityNextCursor != nil, !snapshot.isLoadingEntities else { return }
        _ = startEntityLoad(reset: false)
    }

    private func applyEntityCriteria(_ criteria: IndexQueryCriteria) {
        searchDebounceTask?.cancel()
        updateSnapshot {
            $0.entityCriteria = criteria
            $0.entities = []
            $0.entityNextCursor = nil
        }
        _ = startEntityLoad(reset: true)
    }

    func cancelInFlightWork() {
        refreshTask?.cancel()
        refreshTask = nil
        entityLoadTask?.cancel()
        entityLoadTask = nil
        refreshGeneration += 1
        entityLoadGeneration += 1
        for key in Array(actionGenerations.keys) {
            actionGenerations[key, default: 0] += 1
        }
        cancelAllActionTasks()
        searchDebounceTask?.cancel()
        searchDebounceTask = nil
        if state == .loading {
            updateSnapshot {
                $0.state = .idle
                $0.isLoadingEntities = false
            }
        }
    }

    func cancelSurfaceWork() {
        cancelInFlightWork()
    }

    func refresh() async {
        await startRefresh().value
    }

    @discardableResult
    private func startRefresh() -> Task<Void, Never> {
        let generation = nextRefreshGeneration()
        entityLoadTask?.cancel()
        entityLoadGeneration += 1
        refreshTask?.cancel()
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            await self.runRefresh(generation: generation)
        }
        refreshTask = task
        return task
    }

    private func runRefresh(generation: Int) async {
        guard generation == refreshGeneration else { return }
        ensureToken()
        updateSnapshot { $0.state = .loading }
        do {
            async let typesTask = client.listTypes()
            async let countsTask = client.countsByType()
            async let searchesTask = client.listSearches()
            async let monitorsTask = client.listMonitors()
            async let runsTask = client.listRuns()
            async let alertsTask = client.listAlerts()
            async let tagsTask = client.listTags()
            async let collectionsTask = client.listCollections()
            let (types, countsResp, searches, monitors, runs, alertsResp, tags, collections) = try await (
                typesTask, countsTask, searchesTask, monitorsTask, runsTask, alertsTask, tagsTask, collectionsTask
            )
            try Task.checkCancellation()
            guard generation == refreshGeneration else { return }
            let entityPage = try await fetchEntities(criteria: snapshot.entityCriteria, cursor: nil)
            try Task.checkCancellation()
            guard generation == refreshGeneration else { return }
            var countsMap: [String: Int] = [:]
            for entry in countsResp.counts { countsMap[entry.typeName] = entry.total }
            updateSnapshot {
                $0.types = types
                $0.typeCounts = countsMap
                $0.searches = searches
                $0.monitors = monitors
                $0.runs = runs
                $0.alerts = alertsResp.alerts
                $0.unreadAlerts = alertsResp.unread
                $0.tags = tags
                $0.collections = collections
                $0.entities = entityPage.entities
                $0.entityNextCursor = entityPage.nextCursor
                $0.isLoadingEntities = false
                $0.state = .ready
            }
            for alert in alertsResp.alerts where alert.ackAt == nil {
                let entityTitle = alert.entityId.flatMap { id in
                    self.entities.first { $0.id == id }?.title
                }
                IndexNotificationsBridge.shared.surface(alert, entityTitle: entityTitle)
            }
            finishRefreshIfCurrent(generation)
        } catch is CancellationError {
            if generation == refreshGeneration {
                updateSnapshot {
                    $0.state = .idle
                    $0.isLoadingEntities = false
                }
                finishRefreshIfCurrent(generation)
            }
        } catch {
            if generation == refreshGeneration {
                updateSnapshot {
                    $0.state = .error(Self.failureMessage(for: error, surface: "index.refresh"))
                    $0.isLoadingEntities = false
                }
                finishRefreshIfCurrent(generation)
            }
        }
    }

    func loadEntities() async {
        await startEntityLoad(reset: true).value
    }

    @discardableResult
    private func startEntityLoad(reset: Bool) -> Task<Void, Never> {
        let generation = nextEntityLoadGeneration()
        let criteria = snapshot.entityCriteria
        let cursor = reset ? nil : snapshot.entityNextCursor
        entityLoadTask?.cancel()
        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            await self.runLoadEntities(generation: generation, criteria: criteria, cursor: cursor, reset: reset)
        }
        entityLoadTask = task
        return task
    }

    private func runLoadEntities(generation: Int, criteria: IndexQueryCriteria, cursor: String?, reset: Bool) async {
        guard generation == entityLoadGeneration else { return }
        ensureToken()
        updateSnapshot { $0.isLoadingEntities = true }
        do {
            let page = try await fetchEntities(criteria: criteria, cursor: cursor)
            try Task.checkCancellation()
            guard generation == entityLoadGeneration else { return }
            updateSnapshot {
                $0.entityCriteria = criteria
                $0.entities = reset ? page.entities : $0.entities + page.entities
                $0.entityNextCursor = page.nextCursor
                $0.isLoadingEntities = false
                if case .error = $0.state {
                    $0.state = .ready
                }
            }
            finishEntityLoadIfCurrent(generation)
        } catch is CancellationError {
            if generation == entityLoadGeneration {
                updateSnapshot { $0.isLoadingEntities = false }
                finishEntityLoadIfCurrent(generation)
            }
        } catch {
            if generation == entityLoadGeneration {
                updateSnapshot {
                    if reset { $0.entities = [] }
                    $0.entityNextCursor = nil
                    $0.isLoadingEntities = false
                    $0.state = .error(Self.failureMessage(for: error, surface: "index.entities"))
                }
                finishEntityLoadIfCurrent(generation)
            }
        }
    }

    private func nextRefreshGeneration() -> Int {
        refreshGeneration += 1
        return refreshGeneration
    }

    private func finishRefreshIfCurrent(_ generation: Int) {
        guard generation == refreshGeneration else { return }
        refreshTask = nil
    }

    private func nextEntityLoadGeneration() -> Int {
        entityLoadGeneration += 1
        return entityLoadGeneration
    }

    private func finishEntityLoadIfCurrent(_ generation: Int) {
        guard generation == entityLoadGeneration else { return }
        entityLoadTask = nil
    }

    func searchEntitiesFullText() async -> [ClawJSIndexClient.Entity] {
        ensureToken()
        let trimmed = snapshot.entityCriteria.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entities }
        do {
            var criteria = snapshot.entityCriteria
            criteria.fullText = trimmed
            criteria.limit = 200
            let page = try await fetchEntities(criteria: criteria, cursor: nil)
            try Task.checkCancellation()
            return page.entities
        } catch is CancellationError {
            return entities
        } catch {
            _ = Self.failureMessage(for: error, surface: "index.fullTextSearch")
            return entities
        }
    }

    private static func failureMessage(for error: Error, surface: String) -> String {
        let rawMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return UserFacingFailure.displayMessage(for: rawMessage, surface: surface)
    }

    private func fetchEntities(criteria: IndexQueryCriteria, cursor: String?) async throws -> ClawJSIndexClient.EntityPage {
        var payload: [String: AnyJSON] = [
            "limit": .number(Double(criteria.limit)),
            "orderBy": .object([
                "field": .string("last_seen_at"),
                "direction": .string("desc"),
            ]),
        ]
        if let type = criteria.type {
            payload["type"] = .string(type)
        }
        if !criteria.tagIds.isEmpty {
            payload["tagIds"] = .array(criteria.tagIds.map { .string($0) })
        }
        if let collectionId = criteria.collectionId {
            payload["collectionId"] = .string(collectionId)
        }
        let fullText = criteria.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fullText.isEmpty {
            payload["fullText"] = .string(fullText)
        }
        if let cursor {
            payload["cursor"] = .string(cursor)
        }
        return try await client.listEntities(payload: payload)
    }

    func detail(for id: String) async throws -> ClawJSIndexClient.EntityDetailResponse {
        ensureToken()
        return try await client.getEntity(id: id)
    }

    func history(for entityId: String, field: String) async throws -> [ClawJSIndexClient.HistoryPoint] {
        ensureToken()
        return try await client.history(entityId: entityId, field: field)
    }

    @discardableResult
    func createSearch(name: String, type: String?, criteria: [String: AnyJSON], prompt: String?) async throws -> ClawJSIndexClient.Search {
        let key = IndexActionKey(kind: .createSearch, id: name)
        let generation = nextActionGeneration(for: key)
        var payload: [String: AnyJSON] = [
            "name": .string(name),
            "criteria": .object(criteria),
        ]
        if let type { payload["type"] = .string(type) }
        if let prompt { payload["promptTemplate"] = .string(prompt) }
        return try await runIndexAction(key: key, generation: generation) { store in
            store.ensureToken()
            let search = try await store.client.createSearch(payload: payload)
            try Task.checkCancellation()
            guard store.isCurrentAction(key: key, generation: generation) else { throw CancellationError() }
            store.updateSnapshot { $0.searches.insert(search, at: 0) }
            store.finishActionIfCurrent(key: key, generation: generation)
            return search
        }
    }

    @discardableResult
    func runSearch(id: String) async throws -> ClawJSIndexClient.Run {
        let key = IndexActionKey(kind: .runSearch, id: id)
        let generation = nextActionGeneration(for: key)
        return try await runIndexAction(key: key, generation: generation) { store in
            store.ensureToken()
            let run = try await store.client.runSearch(id: id)
            try Task.checkCancellation()
            guard store.isCurrentAction(key: key, generation: generation) else { throw CancellationError() }
            store.updateSnapshot { $0.runs.insert(run, at: 0) }
            store.finishActionIfCurrent(key: key, generation: generation)
            return run
        }
    }

    func deleteSearch(id: String) async {
        let key = IndexActionKey(kind: .deleteSearch, id: id)
        let generation = nextActionGeneration(for: key)
        do {
            try await runIndexAction(key: key, generation: generation) { store in
                store.ensureToken()
                try await store.client.deleteSearch(id: id)
                try Task.checkCancellation()
                guard store.isCurrentAction(key: key, generation: generation) else { throw CancellationError() }
                store.updateSnapshot { $0.searches.removeAll { $0.id == id } }
                store.finishActionIfCurrent(key: key, generation: generation)
            }
        } catch is CancellationError {
        } catch {
            guard isCurrentAction(key: key, generation: generation) else { return }
            surfaceActionError(error)
            finishActionIfCurrent(key: key, generation: generation)
        }
    }

    @discardableResult
    func createMonitor(searchId: String, cron: String, name: String?, alertRules: [ClawJSIndexClient.AlertRule]) async throws -> ClawJSIndexClient.Monitor {
        let key = IndexActionKey(kind: .createMonitor, id: "\(searchId):\(name ?? "")")
        let generation = nextActionGeneration(for: key)
        let rulesJson: [AnyJSON] = alertRules.map { rule in
            var obj: [String: AnyJSON] = [
                "id": .string(rule.id),
                "when": .string(rule.when),
            ]
            if let field = rule.field { obj["field"] = .string(field) }
            if let pct = rule.thresholdPct { obj["thresholdPct"] = .number(pct) }
            if let abs = rule.thresholdAbs { obj["thresholdAbs"] = .number(abs) }
            if let match = rule.match { obj["match"] = match }
            return .object(obj)
        }
        var payload: [String: AnyJSON] = [
            "searchId": .string(searchId),
            "cronExpr": .string(cron),
            "alertRules": .array(rulesJson),
        ]
        if let name { payload["name"] = .string(name) }
        return try await runIndexAction(key: key, generation: generation) { store in
            store.ensureToken()
            let monitor = try await store.client.createMonitor(payload: payload)
            try Task.checkCancellation()
            guard store.isCurrentAction(key: key, generation: generation) else { throw CancellationError() }
            store.updateSnapshot { $0.monitors.insert(monitor, at: 0) }
            store.finishActionIfCurrent(key: key, generation: generation)
            return monitor
        }
    }

    @discardableResult
    func fireMonitor(id: String) async throws -> ClawJSIndexClient.Run {
        let key = IndexActionKey(kind: .fireMonitor, id: id)
        let generation = nextActionGeneration(for: key)
        return try await runIndexAction(key: key, generation: generation) { store in
            store.ensureToken()
            let run = try await store.client.fireMonitor(id: id)
            try Task.checkCancellation()
            guard store.isCurrentAction(key: key, generation: generation) else { throw CancellationError() }
            store.updateSnapshot { $0.runs.insert(run, at: 0) }
            store.finishActionIfCurrent(key: key, generation: generation)
            return run
        }
    }

    func ackAlert(id: String) async {
        let key = IndexActionKey(kind: .ackAlert, id: id)
        let generation = nextActionGeneration(for: key)
        do {
            try await runIndexAction(key: key, generation: generation) { store in
                store.ensureToken()
                try await store.client.ackAlert(id: id)
                try Task.checkCancellation()
                guard store.isCurrentAction(key: key, generation: generation) else { throw CancellationError() }
                store.updateSnapshot { snapshot in
                    if let index = snapshot.alerts.firstIndex(where: { $0.id == id }) {
                        let alert = snapshot.alerts[index]
                        if alert.ackAt == nil { snapshot.unreadAlerts = max(0, snapshot.unreadAlerts - 1) }
                    }
                    snapshot.alerts.removeAll { $0.id == id }
                }
                store.finishActionIfCurrent(key: key, generation: generation)
            }
        } catch is CancellationError {
        } catch {
            guard isCurrentAction(key: key, generation: generation) else { return }
            surfaceActionError(error)
            finishActionIfCurrent(key: key, generation: generation)
        }
    }

    @discardableResult
    func applyTag(entityId: String, name: String, color: String? = nil) async throws -> ClawJSIndexClient.Tag {
        let key = IndexActionKey(kind: .applyTag, id: "\(entityId):\(name)")
        let generation = nextActionGeneration(for: key)
        return try await runIndexAction(key: key, generation: generation) { store in
            store.ensureToken()
            let tag = try await store.client.applyTag(entityId: entityId, name: name, color: color)
            try Task.checkCancellation()
            guard store.isCurrentAction(key: key, generation: generation) else { throw CancellationError() }
            store.updateSnapshot { snapshot in
                if !snapshot.tags.contains(where: { $0.id == tag.id }) {
                    snapshot.tags.append(tag)
                }
            }
            store.finishActionIfCurrent(key: key, generation: generation)
            return tag
        }
    }

    @discardableResult
    func createCollection(name: String, description: String? = nil) async throws -> ClawJSIndexClient.Collection {
        let key = IndexActionKey(kind: .createCollection, id: name)
        let generation = nextActionGeneration(for: key)
        return try await runIndexAction(key: key, generation: generation) { store in
            store.ensureToken()
            let collection = try await store.client.createCollection(name: name, description: description)
            try Task.checkCancellation()
            guard store.isCurrentAction(key: key, generation: generation) else { throw CancellationError() }
            store.updateSnapshot { $0.collections.insert(collection, at: 0) }
            store.finishActionIfCurrent(key: key, generation: generation)
            return collection
        }
    }

    func addToCollection(collectionId: String, entityId: String) async throws {
        let key = IndexActionKey(kind: .addToCollection, id: "\(collectionId):\(entityId)")
        let generation = nextActionGeneration(for: key)
        try await runIndexAction(key: key, generation: generation) { store in
            store.ensureToken()
            try await store.client.addToCollection(collectionId: collectionId, entityId: entityId)
            try Task.checkCancellation()
            guard store.isCurrentAction(key: key, generation: generation) else { throw CancellationError() }
            store.finishActionIfCurrent(key: key, generation: generation)
        }
    }

    private func runIndexAction<T>(
        key: IndexActionKey,
        generation: Int,
        _ operation: @escaping @MainActor (IndexStore) async throws -> T
    ) async throws -> T {
        cancelActionTasks(for: key)
        let taskId = UUID()
        let task = Task<T, Error> { @MainActor [weak self] in
            guard let self else { throw CancellationError() }
            return try await operation(self)
        }
        actionTaskCancellations[key, default: [:]][taskId] = { task.cancel() }
        do {
            let result = try await task.value
            finishActionTask(key: key, taskId: taskId)
            return result
        } catch {
            finishActionTask(key: key, taskId: taskId)
            throw error
        }
    }

    private func nextActionGeneration(for key: IndexActionKey) -> Int {
        let generation = (actionGenerations[key] ?? 0) + 1
        actionGenerations[key] = generation
        return generation
    }

    private func isCurrentAction(key: IndexActionKey, generation: Int) -> Bool {
        actionGenerations[key] == generation
    }

    private func finishActionIfCurrent(key: IndexActionKey, generation: Int) {
        guard isCurrentAction(key: key, generation: generation) else { return }
        actionGenerations[key] = generation
    }

    private func cancelActionTasks(for key: IndexActionKey) {
        actionTaskCancellations[key]?.values.forEach { $0() }
        actionTaskCancellations[key] = nil
    }

    private func cancelAllActionTasks() {
        for key in Array(actionTaskCancellations.keys) {
            cancelActionTasks(for: key)
        }
    }

    private func finishActionTask(key: IndexActionKey, taskId: UUID) {
        actionTaskCancellations[key]?[taskId] = nil
        if actionTaskCancellations[key]?.isEmpty == true {
            actionTaskCancellations[key] = nil
        }
    }

    private struct IndexActionKey: Hashable {
        let kind: Kind
        let id: String

        enum Kind: Hashable {
            case createSearch
            case runSearch
            case deleteSearch
            case createMonitor
            case fireMonitor
            case ackAlert
            case applyTag
            case createCollection
            case addToCollection
        }
    }
}
