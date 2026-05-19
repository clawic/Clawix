import XCTest
@testable import Clawix

@MainActor
final class IndexStoreCancellationTests: XCTestCase {
    func testEntityReloadCancelsStaleFilterRequest() async {
        let slowStarted = expectation(description: "Slow entity request started")
        let slowCancelled = expectation(description: "Slow entity request cancelled")
        let fastReturned = expectation(description: "Fast entity request returned")
        let client = FakeIndexClient()
        client.onListEntities = { payload in
            let type = payload["type"]?.asString
            if type == "slow" {
                slowStarted.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    slowCancelled.fulfill()
                    throw CancellationError()
                }
                return [Self.entity(id: "slow", title: "Slow")]
            }
            if type == "fast" {
                fastReturned.fulfill()
                return [Self.entity(id: "fast", title: "Fast")]
            }
            return []
        }
        let store = IndexStore(client: client, attachSupervisor: false)

        store.selectedTypeFilter = "slow"
        store.requestLoadEntities()
        await fulfillment(of: [slowStarted], timeout: 1)

        store.selectedTypeFilter = "fast"
        store.requestLoadEntities()

        await fulfillment(of: [slowCancelled, fastReturned], timeout: 1)
        XCTAssertEqual(store.entities.map(\.id), ["fast"])
    }

    private static func entity(id: String, title: String) -> ClawJSIndexClient.Entity {
        ClawJSIndexClient.Entity(
            id: id,
            typeId: "type-\(id)",
            typeName: "note",
            identityKey: id,
            data: [:],
            firstSeenAt: "2026-05-19T00:00:00Z",
            lastSeenAt: "2026-05-19T00:00:00Z",
            observationCount: 1,
            sourceUrl: nil,
            title: title,
            thumbnailUrl: nil
        )
    }
}

private final class FakeIndexClient: ClawJSIndexClienting {
    var bearerToken: String? = "test-token"
    var onListEntities: ([String: AnyJSON]) async throws -> [ClawJSIndexClient.Entity] = { _ in [] }

    func listTypes() async throws -> [ClawJSIndexClient.EntityType] { [] }

    func countsByType() async throws -> ClawJSIndexClient.CountsResponse {
        ClawJSIndexClient.CountsResponse(counts: [])
    }

    func listEntities(payload: [String: AnyJSON]) async throws -> [ClawJSIndexClient.Entity] {
        try await onListEntities(payload)
    }

    func getEntity(id: String) async throws -> ClawJSIndexClient.EntityDetailResponse {
        throw ClawJSIndexClient.Error.serviceNotReady
    }

    func history(entityId: String, field: String) async throws -> [ClawJSIndexClient.HistoryPoint] { [] }

    func listSearches() async throws -> [ClawJSIndexClient.Search] { [] }

    func createSearch(payload: [String: AnyJSON]) async throws -> ClawJSIndexClient.Search {
        throw ClawJSIndexClient.Error.serviceNotReady
    }

    func deleteSearch(id: String) async throws {}

    func runSearch(id: String, prompt: String?) async throws -> ClawJSIndexClient.Run {
        throw ClawJSIndexClient.Error.serviceNotReady
    }

    func listMonitors() async throws -> [ClawJSIndexClient.Monitor] { [] }

    func createMonitor(payload: [String: AnyJSON]) async throws -> ClawJSIndexClient.Monitor {
        throw ClawJSIndexClient.Error.serviceNotReady
    }

    func fireMonitor(id: String) async throws -> ClawJSIndexClient.Run {
        throw ClawJSIndexClient.Error.serviceNotReady
    }

    func listRuns(monitorId: String?) async throws -> [ClawJSIndexClient.Run] { [] }

    func getRun(id: String) async throws -> ClawJSIndexClient.RunDetail {
        throw ClawJSIndexClient.Error.serviceNotReady
    }

    func listAlerts() async throws -> ClawJSIndexClient.AlertsResponse {
        ClawJSIndexClient.AlertsResponse(alerts: [], unread: 0)
    }

    func ackAlert(id: String) async throws {}

    func listTags() async throws -> [ClawJSIndexClient.Tag] { [] }

    func applyTag(entityId: String, name: String, color: String?) async throws -> ClawJSIndexClient.Tag {
        throw ClawJSIndexClient.Error.serviceNotReady
    }

    func listCollections() async throws -> [ClawJSIndexClient.Collection] { [] }

    func createCollection(name: String, description: String?) async throws -> ClawJSIndexClient.Collection {
        throw ClawJSIndexClient.Error.serviceNotReady
    }

    func addToCollection(collectionId: String, entityId: String) async throws {}
}
