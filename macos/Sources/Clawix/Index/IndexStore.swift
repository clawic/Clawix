import Combine
import Foundation

/// State store for the Index tab. Owns the loopback HTTP client and exposes
/// `@Published` state SwiftUI binds to. Mirrors the Memory store pattern
/// without a master-password lock.
@MainActor
final class IndexStore: ObservableObject {

    enum State: Equatable {
        case idle
        case loading
        case ready
        case error(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var types: [ClawJSIndexClient.EntityType] = []
    @Published private(set) var typeCounts: [String: Int] = [:]
    @Published private(set) var entities: [ClawJSIndexClient.Entity] = []
    @Published private(set) var searches: [ClawJSIndexClient.Search] = []
    @Published private(set) var monitors: [ClawJSIndexClient.Monitor] = []
    @Published private(set) var runs: [ClawJSIndexClient.Run] = []
    @Published private(set) var alerts: [ClawJSIndexClient.Alert] = []
    @Published private(set) var unreadAlerts: Int = 0
    @Published private(set) var tags: [ClawJSIndexClient.Tag] = []
    @Published private(set) var collections: [ClawJSIndexClient.Collection] = []
    @Published var selectedTypeFilter: String? = nil
    @Published var selectedSubtypeFilter: String? = nil
    @Published var fullTextQuery: String = ""

    private var client: any ClawJSIndexClienting
    private var supervisorObserver: AnyCancellable?
    private var refreshTask: Task<Void, Never>?
    private var entityLoadTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private var entityLoadGeneration = 0

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

    func surfaceActionError(_ error: Error) {
        state = .error(error.localizedDescription)
    }

    func requestRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            await self?.refresh()
        }
    }

    func requestLoadEntities() {
        entityLoadTask?.cancel()
        entityLoadTask = Task { @MainActor [weak self] in
            await self?.loadEntities()
        }
    }

    func cancelInFlightWork() {
        refreshTask?.cancel()
        refreshTask = nil
        entityLoadTask?.cancel()
        entityLoadTask = nil
        refreshGeneration += 1
        entityLoadGeneration += 1
    }

    func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        entityLoadTask?.cancel()
        entityLoadGeneration += 1
        ensureToken()
        state = .loading
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
            let entities = try await fetchEntities(limit: 500)
            try Task.checkCancellation()
            guard generation == refreshGeneration else { return }
            self.types = types
            var countsMap: [String: Int] = [:]
            for entry in countsResp.counts { countsMap[entry.typeName] = entry.total }
            self.typeCounts = countsMap
            self.searches = searches
            self.monitors = monitors
            self.runs = runs
            self.alerts = alertsResp.alerts
            self.unreadAlerts = alertsResp.unread
            self.tags = tags
            self.collections = collections
            self.entities = entities
            for alert in alertsResp.alerts where alert.ackAt == nil {
                let entityTitle = alert.entityId.flatMap { id in
                    self.entities.first { $0.id == id }?.title
                }
                IndexNotificationsBridge.shared.surface(alert, entityTitle: entityTitle)
            }
            state = .ready
            if generation == refreshGeneration {
                refreshTask = nil
            }
        } catch is CancellationError {
            if generation == refreshGeneration {
                state = .idle
                refreshTask = nil
            }
        } catch {
            if generation == refreshGeneration {
                state = .error(error.localizedDescription)
                refreshTask = nil
            }
        }
    }

    func loadEntities() async {
        entityLoadGeneration += 1
        let generation = entityLoadGeneration
        ensureToken()
        do {
            let entities = try await fetchEntities(limit: 500)
            try Task.checkCancellation()
            guard generation == entityLoadGeneration else { return }
            self.entities = entities
            entityLoadTask = nil
        } catch is CancellationError {
            if generation == entityLoadGeneration {
                entityLoadTask = nil
            }
        } catch {
            if generation == entityLoadGeneration {
                self.entities = []
                entityLoadTask = nil
            }
        }
    }

    func searchEntitiesFullText() async -> [ClawJSIndexClient.Entity] {
        ensureToken()
        let trimmed = fullTextQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entities }
        do {
            let raw = try await fetchEntities(limit: 200)
            try Task.checkCancellation()
            return raw.filter { entity in
                let haystack = (entity.title ?? "") + " " + (entity.sourceUrl ?? "")
                return haystack.localizedCaseInsensitiveContains(trimmed)
            }
        } catch is CancellationError {
            return entities
        } catch {
            return entities
        }
    }

    private func fetchEntities(limit: Double) async throws -> [ClawJSIndexClient.Entity] {
        var payload: [String: AnyJSON] = ["limit": .number(limit)]
        if let typeFilter = selectedTypeFilter {
            payload["type"] = .string(typeFilter)
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
        ensureToken()
        var payload: [String: AnyJSON] = [
            "name": .string(name),
            "criteria": .object(criteria),
        ]
        if let type { payload["type"] = .string(type) }
        if let prompt { payload["promptTemplate"] = .string(prompt) }
        let search = try await client.createSearch(payload: payload)
        searches.insert(search, at: 0)
        return search
    }

    @discardableResult
    func runSearch(id: String) async throws -> ClawJSIndexClient.Run {
        ensureToken()
        let run = try await client.runSearch(id: id)
        runs.insert(run, at: 0)
        return run
    }

    func deleteSearch(id: String) async {
        ensureToken()
        do {
            try await client.deleteSearch(id: id)
            searches.removeAll { $0.id == id }
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    @discardableResult
    func createMonitor(searchId: String, cron: String, name: String?, alertRules: [ClawJSIndexClient.AlertRule]) async throws -> ClawJSIndexClient.Monitor {
        ensureToken()
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
        let monitor = try await client.createMonitor(payload: payload)
        monitors.insert(monitor, at: 0)
        return monitor
    }

    @discardableResult
    func fireMonitor(id: String) async throws -> ClawJSIndexClient.Run {
        ensureToken()
        let run = try await client.fireMonitor(id: id)
        runs.insert(run, at: 0)
        return run
    }

    func ackAlert(id: String) async {
        ensureToken()
        do {
            try await client.ackAlert(id: id)
            if let index = alerts.firstIndex(where: { $0.id == id }) {
                let alert = alerts[index]
                if alert.ackAt == nil { unreadAlerts = max(0, unreadAlerts - 1) }
            }
            alerts.removeAll { $0.id == id }
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    @discardableResult
    func applyTag(entityId: String, name: String, color: String? = nil) async throws -> ClawJSIndexClient.Tag {
        ensureToken()
        let tag = try await client.applyTag(entityId: entityId, name: name, color: color)
        if !tags.contains(where: { $0.id == tag.id }) {
            tags.append(tag)
        }
        return tag
    }

    @discardableResult
    func createCollection(name: String, description: String? = nil) async throws -> ClawJSIndexClient.Collection {
        ensureToken()
        let collection = try await client.createCollection(name: name, description: description)
        collections.insert(collection, at: 0)
        return collection
    }

    func addToCollection(collectionId: String, entityId: String) async throws {
        ensureToken()
        try await client.addToCollection(collectionId: collectionId, entityId: entityId)
    }
}
