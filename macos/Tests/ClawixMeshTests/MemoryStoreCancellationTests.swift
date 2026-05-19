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

    func testResetCancelsInFlightCreate() async {
        let createStarted = expectation(description: "Create started")
        let createCancelled = expectation(description: "Create cancelled")
        let refreshUnexpected = expectation(description: "Refresh should not run after cancelled create")
        refreshUnexpected.isInverted = true
        let store = MemoryStore(
            listNotesOperation: {
                refreshUnexpected.fulfill()
                return [Self.note(id: "unexpected")]
            },
            createNoteOperation: { _ in
                createStarted.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    createCancelled.fulfill()
                    throw CancellationError()
                }
                return Self.createResponse(id: "stale")
            },
            attachSupervisor: false
        )

        let task = Task {
            try await store.create(Self.createInput(title: "Stale"))
        }
        await fulfillment(of: [createStarted], timeout: 1)

        store.reset(reason: "Memory stopped")

        await fulfillment(of: [createCancelled], timeout: 1)
        await fulfillment(of: [refreshUnexpected], timeout: 0.05)
        do {
            _ = try await task.value
            XCTFail("Cancelled create unexpectedly succeeded")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected create error: \(error)")
        }

        XCTAssertEqual(store.state, .error("Memory stopped"))
        XCTAssertTrue(store.notes.isEmpty)
    }

    func testStartingSecondUpdateCancelsStaleUpdate() async throws {
        let staleStarted = expectation(description: "Stale update started")
        let staleCancelled = expectation(description: "Stale update cancelled")
        let freshStarted = expectation(description: "Fresh update started")
        var calls = 0
        let store = MemoryStore(
            listNotesOperation: { [Self.note(id: "fresh")] },
            listCapturesOperation: { [] },
            statsOperation: { Self.stats(total: 1) },
            updateNoteOperation: { id, _, _ in
                calls += 1
                if calls == 1 {
                    staleStarted.fulfill()
                    do {
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                    } catch is CancellationError {
                        staleCancelled.fulfill()
                        throw CancellationError()
                    }
                    return Self.updateResponse(id: id)
                }
                freshStarted.fulfill()
                return Self.updateResponse(id: id)
            },
            attachSupervisor: false
        )

        let first = Task {
            try await store.update(id: "note", patch: Self.updatePatch(title: "Stale"))
        }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task {
            try await store.update(id: "note", patch: Self.updatePatch(title: "Fresh"))
        }

        await fulfillment(of: [staleCancelled, freshStarted], timeout: 1)
        do {
            _ = try await first.value
            XCTFail("Stale update unexpectedly succeeded")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected stale update error: \(error)")
        }
        let response = try await second.value

        XCTAssertEqual(response.id, "note")
        XCTAssertEqual(store.state, .ready)
        XCTAssertEqual(store.notes.map(\.id), ["fresh"])
    }

    func testStartingSecondDeleteCancelsStaleDelete() async throws {
        let staleStarted = expectation(description: "Stale delete started")
        let staleCancelled = expectation(description: "Stale delete cancelled")
        let freshStarted = expectation(description: "Fresh delete started")
        var calls = 0
        let store = MemoryStore(
            listNotesOperation: { [Self.note(id: "remaining")] },
            listCapturesOperation: { [] },
            statsOperation: { Self.stats(total: 1) },
            deleteNoteOperation: { id in
                calls += 1
                if calls == 1 {
                    staleStarted.fulfill()
                    do {
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                    } catch is CancellationError {
                        staleCancelled.fulfill()
                        throw CancellationError()
                    }
                    return Self.deleteResponse(id: id)
                }
                freshStarted.fulfill()
                return Self.deleteResponse(id: id)
            },
            attachSupervisor: false
        )

        let first = Task {
            try await store.delete(id: "note")
        }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task {
            try await store.delete(id: "note")
        }

        await fulfillment(of: [staleCancelled, freshStarted], timeout: 1)
        do {
            _ = try await first.value
            XCTFail("Stale delete unexpectedly succeeded")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected stale delete error: \(error)")
        }
        let response = try await second.value

        XCTAssertTrue(response.deleted)
        XCTAssertEqual(store.state, .ready)
        XCTAssertEqual(store.notes.map(\.id), ["remaining"])
    }

    func testResetCancelsInFlightPromote() async {
        let promoteStarted = expectation(description: "Promote started")
        let promoteCancelled = expectation(description: "Promote cancelled")
        let store = MemoryStore(
            promoteCaptureOperation: { id in
                promoteStarted.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    promoteCancelled.fulfill()
                    throw CancellationError()
                }
                return Self.promoteResponse(id: id)
            },
            attachSupervisor: false
        )

        let task = Task {
            try await store.promote(captureId: "capture")
        }
        await fulfillment(of: [promoteStarted], timeout: 1)

        store.reset(reason: "Memory stopped")

        await fulfillment(of: [promoteCancelled], timeout: 1)
        do {
            _ = try await task.value
            XCTFail("Cancelled promote unexpectedly succeeded")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected promote error: \(error)")
        }

        XCTAssertEqual(store.state, .error("Memory stopped"))
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

    private static func createInput(title: String) -> ClawJSMemoryClient.CreateNoteInput {
        .init(
            noteKind: "memory",
            title: title,
            body: title,
            memoryClass: nil,
            type: "observation",
            tags: nil,
            scopeUser: nil,
            scopeAgent: nil,
            scopeProject: nil
        )
    }

    private static func updatePatch(title: String) -> ClawJSMemoryClient.UpdateNotePatch {
        .init(
            title: title,
            body: title,
            tags: nil,
            scopeUser: nil,
            scopeAgent: nil,
            scopeProject: nil,
            memoryClass: nil
        )
    }

    private static func createResponse(id: String) -> ClawJSMemoryClient.CreateNoteResponse {
        .init(
            saved: true,
            id: id,
            title: id.capitalized,
            memoryClass: nil,
            path: nil
        )
    }

    private static func updateResponse(id: String) -> ClawJSMemoryClient.UpdateNoteResponse {
        .init(
            updated: true,
            id: id,
            path: nil,
            lastEditedBy: "test",
            lastEditedAt: "2026-05-19T00:00:00.000Z"
        )
    }

    private static func deleteResponse(id: String) -> ClawJSMemoryClient.DeleteNoteResponse {
        .init(deleted: true, id: id, path: nil)
    }

    private static func promoteResponse(id: String) -> ClawJSMemoryClient.PromoteResponse {
        .init(promoted: true, captureId: id, memory: createResponse(id: "promoted-\(id)"))
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
