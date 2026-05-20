import Foundation
import Combine

/// One in-process cache + HTTP client per vertical, keyed by id.
/// All verticals share the same daemon authentication: a bearer token
/// negotiated by the bridge (see `DaemonBridgeClient`).
@MainActor
final class LifeVerticalsStore: ObservableObject {
    static let shared = LifeVerticalsStore()

    @Published private(set) var verticals: [String: LifeVerticalState] = [:]
    @Published private(set) var enabledVerticalIds: [String] = LifeVerticalsStore.loadEnabledIds()
    @Published private(set) var hiddenVerticalIds: Set<String> = LifeVerticalsStore.loadHiddenIds()

    private let urlSession: URLSession
    private let host: String
    private let signalsPort: Int
    private let tokenProvider: () -> String?
    private var catalogGenerations: [String: Int] = [:]
    private var observationsGenerations: [String: Int] = [:]
    private var mutationGenerations: [String: Int] = [:]

    init(
        urlSession: URLSession = .shared,
        host: String = "127.0.0.1",
        tokenProvider: @escaping () -> String? = LifeVerticalsStore.defaultToken
    ) {
        self.urlSession = urlSession
        self.host = host
        self.signalsPort = LifeRegistry.signalsServicePort
        self.tokenProvider = tokenProvider
    }

    func state(for verticalId: String) -> LifeVerticalState {
        if let existing = verticals[verticalId] {
            return existing
        }
        let fresh = LifeVerticalState(verticalId: verticalId)
        verticals[verticalId] = fresh
        return fresh
    }

    /// Replaces the persisted enabled-set. Caller decides the new order.
    func setEnabled(_ ids: [String]) {
        enabledVerticalIds = ids
        UserDefaults(suiteName: appPrefsSuite)?.set(ids, forKey: ClawixPersistentSurfaceKeys.lifeEnabledVerticals)
    }

    /// Toggle whether a vertical is hidden from the sidebar (but still
    /// reachable via Cmd+K or LifeSettings).
    func setHidden(id: String, hidden: Bool) {
        if hidden {
            hiddenVerticalIds.insert(id)
        } else {
            hiddenVerticalIds.remove(id)
        }
        UserDefaults(suiteName: appPrefsSuite)?.set(
            Array(hiddenVerticalIds),
            forKey: ClawixPersistentSurfaceKeys.lifeHiddenVerticals
        )
    }

    // MARK: - Network

    func reloadCatalog(for verticalId: String) async {
        guard let url = endpoint(for: verticalId, path: "catalog") else { return }
        let generation = nextCatalogGeneration(for: verticalId)
        do {
            let envelope: CatalogEnvelope = try await get(url)
            try Task.checkCancellation()
            guard isCurrentCatalog(verticalId: verticalId, generation: generation) else { return }
            var entry = state(for: verticalId)
            entry.catalog = envelope.items
            entry.lastError = nil
            verticals[verticalId] = entry
        } catch is CancellationError {
        } catch {
            guard isCurrentCatalog(verticalId: verticalId, generation: generation) else { return }
            var entry = state(for: verticalId)
            entry.lastError = error.localizedDescription
            verticals[verticalId] = entry
        }
    }

    func reloadObservations(
        for verticalId: String,
        variableId: String?,
        limit: Int = 200
    ) async {
        var components = URLComponents()
        var queryItems: [URLQueryItem] = []
        queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        if let variableId {
            queryItems.append(URLQueryItem(name: "variableId", value: variableId))
        }
        components.queryItems = queryItems
        guard let suffix = components.url?.query else { return }
        guard let url = endpoint(for: verticalId, path: "observations?\(suffix)") else { return }
        let generation = nextObservationsGeneration(for: verticalId)
        do {
            let envelope: ObservationsEnvelope = try await get(url)
            try Task.checkCancellation()
            guard isCurrentObservations(verticalId: verticalId, generation: generation) else { return }
            var entry = state(for: verticalId)
            entry.observations = envelope.items
            entry.lastError = nil
            verticals[verticalId] = entry
        } catch is CancellationError {
        } catch {
            guard isCurrentObservations(verticalId: verticalId, generation: generation) else { return }
            var entry = state(for: verticalId)
            entry.lastError = error.localizedDescription
            verticals[verticalId] = entry
        }
    }

    func upsertObservation(
        verticalId: String,
        input: LifeUpsertObservationInput
    ) async {
        guard let url = endpoint(for: verticalId, path: "observations") else { return }
        let generation = nextMutationGeneration(for: verticalId)
        do {
            let _: LifeObservation = try await post(url, body: input)
            try Task.checkCancellation()
            guard isCurrentMutation(verticalId: verticalId, generation: generation) else { return }
            await reloadObservations(for: verticalId, variableId: input.variableId)
        } catch is CancellationError {
        } catch {
            guard isCurrentMutation(verticalId: verticalId, generation: generation) else { return }
            var entry = state(for: verticalId)
            entry.lastError = error.localizedDescription
            verticals[verticalId] = entry
        }
    }

    func deleteObservation(verticalId: String, observationId: String) async {
        guard let url = endpoint(
            for: verticalId,
            path: "observations/\(observationId)"
        ) else { return }
        let generation = nextMutationGeneration(for: verticalId)
        do {
            let _: DeletedEnvelope = try await delete(url)
            try Task.checkCancellation()
            guard isCurrentMutation(verticalId: verticalId, generation: generation) else { return }
            await reloadObservations(for: verticalId, variableId: nil)
        } catch is CancellationError {
        } catch {
            guard isCurrentMutation(verticalId: verticalId, generation: generation) else { return }
            var entry = state(for: verticalId)
            entry.lastError = error.localizedDescription
            verticals[verticalId] = entry
        }
    }

    func cancelSurfaceWork(for verticalId: String? = nil) {
        if let verticalId {
            bumpCatalogGeneration(for: verticalId)
            bumpObservationsGeneration(for: verticalId)
            bumpMutationGeneration(for: verticalId)
            return
        }
        for verticalId in Set(catalogGenerations.keys)
            .union(Set(observationsGenerations.keys))
            .union(Set(mutationGenerations.keys)) {
            bumpCatalogGeneration(for: verticalId)
            bumpObservationsGeneration(for: verticalId)
            bumpMutationGeneration(for: verticalId)
        }
    }

    // MARK: - URL plumbing

    private func endpoint(for verticalId: String, path: String) -> URL? {
        guard LifeRegistry.entry(byId: verticalId, includeDevOnly: true) != nil else { return nil }
        return URL(string: "http://\(host):\(signalsPort)/v1/\(verticalId)/\(path)")
    }

    private func nextCatalogGeneration(for verticalId: String) -> Int {
        let generation = (catalogGenerations[verticalId] ?? 0) + 1
        catalogGenerations[verticalId] = generation
        return generation
    }

    private func bumpCatalogGeneration(for verticalId: String) {
        catalogGenerations[verticalId] = (catalogGenerations[verticalId] ?? 0) + 1
    }

    private func isCurrentCatalog(verticalId: String, generation: Int) -> Bool {
        catalogGenerations[verticalId] == generation
    }

    private func nextObservationsGeneration(for verticalId: String) -> Int {
        let generation = (observationsGenerations[verticalId] ?? 0) + 1
        observationsGenerations[verticalId] = generation
        return generation
    }

    private func bumpObservationsGeneration(for verticalId: String) {
        observationsGenerations[verticalId] = (observationsGenerations[verticalId] ?? 0) + 1
    }

    private func isCurrentObservations(verticalId: String, generation: Int) -> Bool {
        observationsGenerations[verticalId] == generation
    }

    private func nextMutationGeneration(for verticalId: String) -> Int {
        let generation = (mutationGenerations[verticalId] ?? 0) + 1
        mutationGenerations[verticalId] = generation
        return generation
    }

    private func bumpMutationGeneration(for verticalId: String) {
        mutationGenerations[verticalId] = (mutationGenerations[verticalId] ?? 0) + 1
    }

    private func isCurrentMutation(verticalId: String, generation: Int) -> Bool {
        mutationGenerations[verticalId] == generation
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await urlSession.data(for: request)
        try Self.check(response, data: data, url: url)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post<I: Encodable, O: Decodable>(_ url: URL, body: I) async throws -> O {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await urlSession.data(for: request)
        try Self.check(response, data: data, url: url)
        return try JSONDecoder().decode(O.self, from: data)
    }

    private func delete<O: Decodable>(_ url: URL) async throws -> O {
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        if let token = tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await urlSession.data(for: request)
        try Self.check(response, data: data, url: url)
        return try JSONDecoder().decode(O.self, from: data)
    }

    private static func check(_ response: URLResponse, data: Data, url: URL) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw NSError(
                domain: "LifeVerticalsStore",
                code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey: "HTTP \(http.statusCode) on \(url.absoluteString)"
                ]
            )
        }
    }

    // MARK: - Persistence

    nonisolated private static var appPrefsSuiteName: String { appPrefsSuite }

    nonisolated private static func loadEnabledIds() -> [String] {
        if let stored = UserDefaults(suiteName: appPrefsSuiteName)?.stringArray(
            forKey: ClawixPersistentSurfaceKeys.lifeEnabledVerticals
        ), !stored.isEmpty {
            return stored
        }
        // Default: every stable product-v1 vertical visible the first time the
        // app launches. Dev-only verticals stay behind the developer switch.
        return [
            "health", "sleep", "workouts", "emotions", "journal",
            "habits", "time-tracking", "goals", "finance", "nutrition"
        ]
    }

    nonisolated private static func loadHiddenIds() -> Set<String> {
        let array = UserDefaults(suiteName: appPrefsSuiteName)?
            .stringArray(forKey: ClawixPersistentSurfaceKeys.lifeHiddenVerticals) ?? []
        return Set(array)
    }

    nonisolated static func defaultToken() -> String? {
        UserDefaults(suiteName: ClawixPersistentSurfaceKeys.bridgeDefaultsSuite)?
            .string(forKey: ClawixPersistentSurfaceKeys.bridgeBearer)
    }
}

/// Per-vertical state cached in memory while the app is running.
struct LifeVerticalState: Equatable {
    let verticalId: String
    var catalog: [LifeCatalogEntry] = []
    var observations: [LifeObservation] = []
    var lastError: String?
}

struct LifeUpsertObservationInput: Codable {
    var id: String?
    var variableId: String
    var value: LifeObservationValue
    var unitId: String?
    var recordedAt: Double?
    var source: LifeObservationSource?
    var notes: String?
    var sessionId: String?
    var externalId: String?
}

private struct CatalogEnvelope: Decodable {
    let items: [LifeCatalogEntry]
}

private struct ObservationsEnvelope: Decodable {
    let items: [LifeObservation]
}

private struct DeletedEnvelope: Decodable {
    let deleted: Bool
}
