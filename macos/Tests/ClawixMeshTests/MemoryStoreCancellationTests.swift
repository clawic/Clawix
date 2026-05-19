import XCTest
@testable import Clawix

@MainActor
final class MemoryStoreCancellationTests: XCTestCase {
    func testStartingSecondRefreshCancelsStaleRefresh() async {
        let staleStarted = expectation(description: "Stale refresh started")
        let staleCancelled = expectation(description: "Stale refresh cancelled")
        let freshStarted = expectation(description: "Fresh refresh started")
        var calls = 0
        let store = MemoryStore(
            listNotesOperation: {
                calls += 1
                if calls == 1 {
                    staleStarted.fulfill()
                    do {
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                    } catch is CancellationError {
                        staleCancelled.fulfill()
                        throw CancellationError()
                    }
                    return [Self.note(id: "stale")]
                }
                freshStarted.fulfill()
                return [Self.note(id: "fresh")]
            },
            listCapturesOperation: { [] },
            statsOperation: { Self.stats(total: 1) },
            attachSupervisor: false
        )

        let first = Task { await store.refresh() }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task { await store.refresh() }

        await fulfillment(of: [staleCancelled, freshStarted], timeout: 1)
        await first.value
        await second.value

        XCTAssertEqual(store.state, .ready)
        XCTAssertEqual(store.notes.map(\.id), ["fresh"])
    }

    func testResetCancelsInFlightRefresh() async {
        let refreshStarted = expectation(description: "Refresh started")
        let refreshCancelled = expectation(description: "Refresh cancelled")
        let store = MemoryStore(
            listNotesOperation: {
                refreshStarted.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    refreshCancelled.fulfill()
                    throw CancellationError()
                }
                return [Self.note(id: "stale")]
            },
            listCapturesOperation: { [] },
            statsOperation: { Self.stats(total: 1) },
            attachSupervisor: false
        )

        let task = Task { await store.refresh() }
        await fulfillment(of: [refreshStarted], timeout: 1)

        store.reset(reason: "Memory stopped")

        await fulfillment(of: [refreshCancelled], timeout: 1)
        await task.value

        XCTAssertEqual(store.state, .error("Memory stopped"))
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertTrue(store.captures.isEmpty)
        XCTAssertNil(store.stats)
    }

    func testStaleRefreshCannotOverwriteFreshRefresh() async {
        let staleStarted = expectation(description: "Stale refresh started")
        let staleReturned = expectation(description: "Stale refresh returned")
        let freshStarted = expectation(description: "Fresh refresh started")
        var calls = 0
        let store = MemoryStore(
            listNotesOperation: {
                calls += 1
                if calls == 1 {
                    staleStarted.fulfill()
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    staleReturned.fulfill()
                    return [Self.note(id: "stale")]
                }
                freshStarted.fulfill()
                return [Self.note(id: "fresh")]
            },
            listCapturesOperation: { [] },
            statsOperation: { Self.stats(total: 1) },
            attachSupervisor: false
        )

        let first = Task { await store.refresh() }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task { await store.refresh() }

        await fulfillment(of: [freshStarted, staleReturned], timeout: 1)
        await first.value
        await second.value

        XCTAssertEqual(store.state, .ready)
        XCTAssertEqual(store.notes.map(\.id), ["fresh"])
    }

    func testStartingSecondSearchCancelsStaleSearch() async {
        let staleStarted = expectation(description: "Stale search started")
        let staleCancelled = expectation(description: "Stale search cancelled")
        let freshStarted = expectation(description: "Fresh search started")
        var queries: [String] = []
        let store = MemoryStore(
            searchOperation: { query in
                queries.append(query)
                if query == "stale" {
                    staleStarted.fulfill()
                    do {
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                    } catch is CancellationError {
                        staleCancelled.fulfill()
                        throw CancellationError()
                    }
                    return Self.search(query: "stale")
                }
                freshStarted.fulfill()
                return Self.search(query: query)
            },
            attachSupervisor: false
        )

        store.search("stale")
        await fulfillment(of: [staleStarted], timeout: 1)

        store.search("fresh")

        await fulfillment(of: [staleCancelled, freshStarted], timeout: 1)
        await Task.yield()

        XCTAssertEqual(queries, ["stale", "fresh"])
        XCTAssertEqual(store.lastSearch?.query, "fresh")
        XCTAssertFalse(store.isSearching)
    }

    private static func note(id: String) -> ClawJSMemoryClient.MemoryNote {
        .init(
            id: id,
            slug: id,
            kind: "memory",
            type: "observation",
            title: id.capitalized,
            semanticKind: "observation",
            schemaVersion: 1,
            frontmatter: [:],
            body: id
        )
    }

    private static func stats(total: Int) -> ClawJSMemoryClient.MemoryStatsResponse {
        .init(
            total: total,
            entities: 0,
            memories: total,
            valid: true,
            byType: [:],
            byKind: ["memory": total],
            schemaVersion: 1
        )
    }

    private static func search(query: String) -> ClawJSMemoryClient.SearchResponse {
        .init(
            query: query,
            mode: "keyword",
            count: 0,
            minScore: nil,
            results: []
        )
    }
}
