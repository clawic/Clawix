import XCTest
import Combine
@testable import Clawix

@MainActor
final class IndexStoreCancellationTests: XCTestCase {
    func testStartingSecondRunSearchCancelsStaleRun() async {
        let staleStarted = expectation(description: "Stale run search started")
        let staleCancelled = expectation(description: "Stale run search cancelled")
        let staleReturned = expectation(description: "Stale run search returned")
        staleReturned.isInverted = true
        let freshReturned = expectation(description: "Fresh run search returned")
        let client = FakeIndexClient()
        var calls = 0
        client.onRunSearch = { id in
            calls += 1
            if calls == 1 {
                staleStarted.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    staleCancelled.fulfill()
                    throw CancellationError()
                }
                staleReturned.fulfill()
                return Self.run(id: "stale", searchId: id)
            }
            freshReturned.fulfill()
            return Self.run(id: "fresh", searchId: id)
        }
        let store = IndexStore(client: client, attachSupervisor: false)

        let first = Task { try? await store.runSearch(id: "search") }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task { try? await store.runSearch(id: "search") }

        await fulfillment(of: [staleCancelled, freshReturned], timeout: 1)
        await fulfillment(of: [staleReturned], timeout: 0.1)
        let firstResult = await first.value
        let secondResult = await second.value
        XCTAssertNil(firstResult)
        XCTAssertEqual(secondResult?.id, "fresh")

        XCTAssertEqual(store.runs.map(\.id), ["fresh"])
        XCTAssertNil(store.state.errorMessage)
    }

    func testCancelSurfaceWorkCancelsInFlightRunSearch() async {
        let runStarted = expectation(description: "Run search started")
        let runCancelled = expectation(description: "Run search cancelled")
        let runReturned = expectation(description: "Run search returned after teardown")
        runReturned.isInverted = true
        let client = FakeIndexClient()
        client.onRunSearch = { id in
            runStarted.fulfill()
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                runCancelled.fulfill()
                throw CancellationError()
            }
            runReturned.fulfill()
            return Self.run(id: "late", searchId: id)
        }
        let store = IndexStore(client: client, attachSupervisor: false)

        let task = Task { try? await store.runSearch(id: "search") }
        await fulfillment(of: [runStarted], timeout: 1)

        store.cancelSurfaceWork()

        await fulfillment(of: [runCancelled], timeout: 1)
        await fulfillment(of: [runReturned], timeout: 0.1)
        let result = await task.value
        XCTAssertNil(result)
        XCTAssertTrue(store.runs.isEmpty)
        XCTAssertNil(store.state.errorMessage)
    }

    func testCancelSurfaceWorkCancelsInFlightIndexAction() async {
        let deleteStarted = expectation(description: "Delete search started")
        let deleteReturned = expectation(description: "Delete search returned after teardown")
        deleteReturned.isInverted = true
        let deleteCancelled = expectation(description: "Delete search cancelled")
        let client = FakeIndexClient()
        client.onDeleteSearch = { _ in
            deleteStarted.fulfill()
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                deleteCancelled.fulfill()
                throw CancellationError()
            }
            deleteReturned.fulfill()
            throw ClawJSIndexClient.Error.serviceNotReady
        }
        let store = IndexStore(client: client, attachSupervisor: false)

        let task = Task { await store.deleteSearch(id: "search") }
        await fulfillment(of: [deleteStarted], timeout: 1)

        store.cancelSurfaceWork()

        await fulfillment(of: [deleteCancelled], timeout: 1)
        await fulfillment(of: [deleteReturned], timeout: 0.1)
        await task.value

        XCTAssertNil(store.state.errorMessage)
    }

    func testSurfaceActionErrorUsesClassifiedLocalizedMessage() {
        let client = FakeIndexClient()
        let store = IndexStore(client: client, attachSupervisor: false)

        store.surfaceActionError(TestFailure(errorDescription: "HTTP 401: invalid API key"))

        XCTAssertEqual(
            store.state.errorMessage,
            L10n.t("Permission was denied. Review permissions, then try again.")
        )
    }

    func testEntityDetailLoadCancelsStaleDetailRequest() async {
        let staleStarted = expectation(description: "Stale entity detail started")
        let staleCancelled = expectation(description: "Stale entity detail cancelled")
        let freshReturned = expectation(description: "Fresh entity detail returned")
        let client = FakeIndexClient()
        client.onGetEntity = { id in
            if id == "stale" {
                staleStarted.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    staleCancelled.fulfill()
                    throw CancellationError()
                }
                return Self.detail(id: "stale", title: "Stale")
            }
            freshReturned.fulfill()
            return Self.detail(id: "fresh", title: "Fresh")
        }
        let store = IndexStore(client: client, attachSupervisor: false)
        let detailStore = IndexEntityDetailStore()

        let first = Task { await detailStore.load(entityId: "stale", using: store) }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task { await detailStore.load(entityId: "fresh", using: store) }

        await fulfillment(of: [staleCancelled, freshReturned], timeout: 1)
        await first.value
        await second.value

        XCTAssertEqual(detailStore.detail?.entity.id, "fresh")
        XCTAssertNil(detailStore.loadError)
    }

    func testEntityDetailFailureUsesClassifiedLocalizedMessage() async {
        let client = FakeIndexClient()
        client.onGetEntity = { _ in
            throw TestFailure(errorDescription: "HTTP 403: forbidden")
        }
        let store = IndexStore(client: client, attachSupervisor: false)
        let detailStore = IndexEntityDetailStore()

        await detailStore.load(entityId: "denied", using: store)

        XCTAssertNil(detailStore.detail)
        XCTAssertEqual(
            detailStore.loadError,
            L10n.t("Permission was denied. Review permissions, then try again.")
        )
    }

    func testCancelSurfaceWorkSuppressesInFlightDetailLoad() async {
        let started = expectation(description: "Entity detail started")
        let cancelled = expectation(description: "Entity detail cancelled")
        let client = FakeIndexClient()
        client.onGetEntity = { _ in
            started.fulfill()
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                cancelled.fulfill()
                throw CancellationError()
            }
            return Self.detail(id: "late", title: "Late")
        }
        let store = IndexStore(client: client, attachSupervisor: false)
        let detailStore = IndexEntityDetailStore()

        let task = Task { await detailStore.load(entityId: "late", using: store) }
        await fulfillment(of: [started], timeout: 1)

        detailStore.cancelSurfaceWork()

        await fulfillment(of: [cancelled], timeout: 1)
        await task.value

        XCTAssertNil(detailStore.detail)
        XCTAssertNil(detailStore.loadError)
    }

    func testEntityChangeCancelsStaleHistoryRequest() async {
        let historyStarted = expectation(description: "Entity history started")
        let historyCancelled = expectation(description: "Entity history cancelled")
        let client = FakeIndexClient()
        client.onGetEntity = { id in
            Self.detail(id: id, title: id.capitalized)
        }
        client.onHistory = { entityId, field in
            _ = (entityId, field)
            historyStarted.fulfill()
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                historyCancelled.fulfill()
                throw CancellationError()
            }
            return [Self.historyPoint(field: field, value: "stale")]
        }
        let store = IndexStore(client: client, attachSupervisor: false)
        let detailStore = IndexEntityDetailStore()
        await detailStore.load(entityId: "first", using: store)

        let history = Task { await detailStore.loadHistory("status", using: store) }
        await fulfillment(of: [historyStarted], timeout: 1)

        await detailStore.load(entityId: "second", using: store)

        await fulfillment(of: [historyCancelled], timeout: 1)
        await history.value

        XCTAssertEqual(detailStore.detail?.entity.id, "second")
        XCTAssertTrue(detailStore.history(for: "status").isEmpty)
    }

    func testCancelInFlightWorkSuppressesRefreshAndReturnsToIdle() async {
        let refreshStarted = expectation(description: "Index refresh started")
        let refreshCancelled = expectation(description: "Index refresh cancelled")
        let client = FakeIndexClient()
        client.onListTypes = {
            refreshStarted.fulfill()
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                refreshCancelled.fulfill()
                throw CancellationError()
            }
            return []
        }
        let store = IndexStore(client: client, attachSupervisor: false)

        let task = Task { await store.refresh() }
        await fulfillment(of: [refreshStarted], timeout: 1)

        store.cancelInFlightWork()

        await fulfillment(of: [refreshCancelled], timeout: 1)
        await task.value

        XCTAssertEqual(store.state, .idle)
        XCTAssertTrue(store.types.isEmpty)
        XCTAssertTrue(store.entities.isEmpty)
    }

    func testRefreshPublishesOneReadySnapshot() async {
        let readyPublished = expectation(description: "Ready snapshot published")
        let client = FakeIndexClient()
        let store = IndexStore(client: client, attachSupervisor: false)
        var readySnapshots = 0
        var cancellables = Set<AnyCancellable>()
        store.$snapshot
            .dropFirst()
            .sink { snapshot in
                if snapshot.state == .ready {
                    readySnapshots += 1
                    readyPublished.fulfill()
                }
            }
            .store(in: &cancellables)

        await store.refresh()

        await fulfillment(of: [readyPublished], timeout: 1)
        XCTAssertEqual(readySnapshots, 1)
        XCTAssertEqual(store.state, .ready)
        _ = cancellables
    }

    func testRefreshFailureUsesClassifiedLocalizedMessage() async {
        let client = FakeIndexClient()
        client.onListTypes = {
            throw TestFailure(errorDescription: "ClawJS index service is not running.")
        }
        let store = IndexStore(client: client, attachSupervisor: false)

        await store.refresh()

        XCTAssertEqual(
            store.state.errorMessage,
            L10n.t("The service is unavailable. Try again in a moment.")
        )
        XCTAssertFalse(store.snapshot.isLoadingEntities)
    }

    func testEntityLoadFailureUsesClassifiedLocalizedMessage() async {
        let client = FakeIndexClient()
        client.onListEntities = { _ in
            throw TestFailure(errorDescription: "The Internet connection appears to be offline.")
        }
        let store = IndexStore(client: client, attachSupervisor: false)

        await store.loadEntities()

        XCTAssertEqual(
            store.state.errorMessage,
            L10n.t("The network appears to be offline. Reconnect, then try again.")
        )
        XCTAssertFalse(store.snapshot.isLoadingEntities)
        XCTAssertTrue(store.entities.isEmpty)
    }

    func testEntityLoadSuccessClearsPreviousFailure() async {
        let client = FakeIndexClient()
        client.onListEntities = { _ in
            ClawJSIndexClient.EntityPage(
                entities: [Self.entity(id: "recovered", title: "Recovered")],
                nextCursor: nil
            )
        }
        let store = IndexStore(client: client, attachSupervisor: false)
        store.surfaceActionError(TestFailure(errorDescription: "ClawJS index service is not running."))

        await store.loadEntities()

        XCTAssertEqual(store.state, .ready)
        XCTAssertEqual(store.entities.map(\.id), ["recovered"])
    }

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
                return ClawJSIndexClient.EntityPage(
                    entities: [Self.entity(id: "slow", title: "Slow")],
                    nextCursor: nil
                )
            }
            if type == "fast" {
                fastReturned.fulfill()
                return ClawJSIndexClient.EntityPage(
                    entities: [Self.entity(id: "fast", title: "Fast")],
                    nextCursor: nil
                )
            }
            return ClawJSIndexClient.EntityPage(entities: [], nextCursor: nil)
        }
        let store = IndexStore(client: client, attachSupervisor: false)

        store.selectTypeFilter("slow")
        await fulfillment(of: [slowStarted], timeout: 1)

        store.selectTypeFilter("fast")

        await fulfillment(of: [slowCancelled, fastReturned], timeout: 1)
        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(store.entities.map(\.id), ["fast"])
    }

    func testDebouncedSearchOnlyIssuesFinalQuery() async {
        let finalReturned = expectation(description: "Final search returned")
        let client = FakeIndexClient()
        var payloads: [[String: AnyJSON]] = []
        client.onListEntities = { payload in
            payloads.append(payload)
            if payload["fullText"]?.asString == "final" {
                finalReturned.fulfill()
                return ClawJSIndexClient.EntityPage(
                    entities: [Self.entity(id: "final", title: "Final")],
                    nextCursor: nil
                )
            }
            return ClawJSIndexClient.EntityPage(entities: [], nextCursor: nil)
        }
        let store = IndexStore(client: client, attachSupervisor: false)

        store.updateFullTextQuery("first")
        store.updateFullTextQuery("final")

        await fulfillment(of: [finalReturned], timeout: 1)
        XCTAssertEqual(payloads.compactMap { $0["fullText"]?.asString }, ["final"])
        XCTAssertEqual(store.entities.map(\.id), ["final"])
    }

    func testEntityFilterBodyIncludesCriteriaAndCursorAppendPreservesRows() async {
        let firstReturned = expectation(description: "First page returned")
        let secondReturned = expectation(description: "Second page returned")
        let client = FakeIndexClient()
        var payloads: [[String: AnyJSON]] = []
        client.onListEntities = { payload in
            payloads.append(payload)
            if payload["cursor"]?.asString == "next-page" {
                secondReturned.fulfill()
                return ClawJSIndexClient.EntityPage(
                    entities: [Self.entity(id: "second", title: "Second")],
                    nextCursor: nil
                )
            }
            if payload["fullText"]?.asString == "alpha" {
                firstReturned.fulfill()
                return ClawJSIndexClient.EntityPage(
                    entities: [Self.entity(id: "first", title: "First")],
                    nextCursor: "next-page"
                )
            }
            return ClawJSIndexClient.EntityPage(entities: [], nextCursor: nil)
        }
        let store = IndexStore(client: client, attachSupervisor: false)

        store.selectTypeFilter("article")
        store.selectTagFilter("tag-important")
        store.selectCollectionFilter("collection-research")
        store.updateFullTextQuery("alpha")

        await fulfillment(of: [firstReturned], timeout: 1)
        await waitForEntityIds(["first"], in: store)
        store.loadMoreEntitiesIfNeeded(currentEntityId: "first")
        await fulfillment(of: [secondReturned], timeout: 1)
        await waitForEntityIds(["first", "second"], in: store)

        guard let firstPayload = payloads.first(where: { $0["fullText"]?.asString == "alpha" }) else {
            return XCTFail("Expected debounced full-text entity payload")
        }
        XCTAssertEqual(firstPayload["type"]?.asString, "article")
        XCTAssertEqual(firstPayload["tagIds"]?.asArray?.compactMap(\.asString), ["tag-important"])
        XCTAssertEqual(firstPayload["collectionId"]?.asString, "collection-research")
        XCTAssertEqual(firstPayload["fullText"]?.asString, "alpha")
        XCTAssertEqual(store.entities.map(\.id), ["first", "second"])
    }

    private func waitForEntityIds(
        _ ids: [String],
        in store: IndexStore,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<100 {
            if ids == store.entities.map(\.id) { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(store.entities.map(\.id), ids, file: file, line: line)
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

    private static func detail(id: String, title: String) -> ClawJSIndexClient.EntityDetailResponse {
        ClawJSIndexClient.EntityDetailResponse(
            entity: entity(id: id, title: title),
            observations: [],
            relationsFrom: [],
            relationsTo: [],
            tags: []
        )
    }

    private static func historyPoint(field: String, value: String) -> ClawJSIndexClient.HistoryPoint {
        ClawJSIndexClient.HistoryPoint(
            fieldPath: field,
            value: .string(value),
            validFrom: "2026-05-19T00:00:00Z",
            runId: nil
        )
    }

    private static func run(id: String, searchId: String) -> ClawJSIndexClient.Run {
        ClawJSIndexClient.Run(
            id: id,
            monitorId: nil,
            searchId: searchId,
            kind: "manual",
            status: "succeeded",
            startedAt: "2026-05-19T00:00:00Z",
            endedAt: "2026-05-19T00:00:01Z",
            codexSessionId: nil,
            error: nil,
            entitiesSeen: 1,
            observationsCount: 1,
            alertsFired: 0,
            tokensIn: nil,
            tokensOut: nil,
            prompt: nil,
            createdAt: "2026-05-19T00:00:00Z"
        )
    }
}

private extension IndexStore.State {
    var errorMessage: String? {
        if case .error(let message) = self { return message }
        return nil
    }
}

private struct TestFailure: LocalizedError {
    let errorDescription: String?
}

private final class FakeIndexClient: ClawJSIndexClienting {
    var bearerToken: String? = "test-token"
    var onListTypes: () async throws -> [ClawJSIndexClient.EntityType] = { [] }
    var onListEntities: ([String: AnyJSON]) async throws -> ClawJSIndexClient.EntityPage = { _ in
        ClawJSIndexClient.EntityPage(entities: [], nextCursor: nil)
    }
    var onGetEntity: (String) async throws -> ClawJSIndexClient.EntityDetailResponse = { _ in
        throw ClawJSIndexClient.Error.serviceNotReady
    }
    var onHistory: (String, String) async throws -> [ClawJSIndexClient.HistoryPoint] = { _, _ in [] }
    var onRunSearch: (String) async throws -> ClawJSIndexClient.Run = { _ in
        throw ClawJSIndexClient.Error.serviceNotReady
    }
    var onDeleteSearch: (String) async throws -> Void = { _ in }

    func listTypes() async throws -> [ClawJSIndexClient.EntityType] {
        try await onListTypes()
    }

    func countsByType() async throws -> ClawJSIndexClient.CountsResponse {
        ClawJSIndexClient.CountsResponse(counts: [])
    }

    func listEntities(payload: [String: AnyJSON]) async throws -> ClawJSIndexClient.EntityPage {
        try await onListEntities(payload)
    }

    func getEntity(id: String) async throws -> ClawJSIndexClient.EntityDetailResponse {
        try await onGetEntity(id)
    }

    func history(entityId: String, field: String) async throws -> [ClawJSIndexClient.HistoryPoint] {
        try await onHistory(entityId, field)
    }

    func listSearches() async throws -> [ClawJSIndexClient.Search] { [] }

    func createSearch(payload: [String: AnyJSON]) async throws -> ClawJSIndexClient.Search {
        throw ClawJSIndexClient.Error.serviceNotReady
    }

    func deleteSearch(id: String) async throws {
        try await onDeleteSearch(id)
    }

    func runSearch(id: String, prompt: String?) async throws -> ClawJSIndexClient.Run {
        _ = prompt
        return try await onRunSearch(id)
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
