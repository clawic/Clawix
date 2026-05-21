import XCTest
@testable import Clawix

@MainActor
final class SkillsStoreCancellationTests: XCTestCase {
    func testCancelSurfaceWorkCancelsInFlightSync() async {
        let syncStarted = expectation(description: "Skill sync started")
        let syncCancelled = expectation(description: "Skill sync cancelled after teardown")
        let syncReturned = expectation(description: "Skill sync should not return after teardown")
        syncReturned.isInverted = true
        let staleDate = Date(timeIntervalSince1970: 100)
        let store = SkillsStore(
            seedBuiltins: false,
            frameworkClient: Self.emptyFrameworkClient(),
            syncOperation: {
                syncStarted.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 50_000_000)
                    syncReturned.fulfill()
                    return staleDate
                } catch is CancellationError {
                    syncCancelled.fulfill()
                    throw CancellationError()
                }
            }
        )

        let task = Task { await store.syncNow() }
        await fulfillment(of: [syncStarted], timeout: 1)
        XCTAssertEqual(store.pendingOperation, "Syncing")

        store.cancelSurfaceWork()

        XCTAssertNil(store.pendingOperation)
        await fulfillment(of: [syncCancelled, syncReturned], timeout: 1)
        await task.value

        XCTAssertNil(store.lastSyncedAt)
        XCTAssertNil(store.pendingOperation)
    }

    func testStartingSecondSyncCancelsStaleFirstResult() async {
        let staleStarted = expectation(description: "Stale skill sync started")
        let staleCancelled = expectation(description: "Stale skill sync cancelled")
        let staleReturned = expectation(description: "Stale skill sync should not return")
        staleReturned.isInverted = true
        let freshStarted = expectation(description: "Fresh skill sync started")
        let staleDate = Date(timeIntervalSince1970: 100)
        let freshDate = Date(timeIntervalSince1970: 200)
        var calls = 0
        let store = SkillsStore(
            seedBuiltins: false,
            frameworkClient: Self.emptyFrameworkClient(),
            syncOperation: {
                calls += 1
                if calls == 1 {
                    staleStarted.fulfill()
                    do {
                        try await Task.sleep(nanoseconds: 80_000_000)
                        staleReturned.fulfill()
                        return staleDate
                    } catch is CancellationError {
                        staleCancelled.fulfill()
                        throw CancellationError()
                    }
                }
                freshStarted.fulfill()
                return freshDate
            }
        )

        let first = Task { await store.syncNow() }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task { await store.syncNow() }

        await fulfillment(of: [freshStarted, staleCancelled, staleReturned], timeout: 1)
        await first.value
        await second.value

        XCTAssertEqual(store.lastSyncedAt, freshDate)
        XCTAssertNil(store.pendingOperation)
    }

    private static func emptyFrameworkClient() -> ClawJSFrameworkRecordsClient {
        ClawJSFrameworkRecordsClient(runner: .init { args in
            if args == ["skills", "list", "--json", "--kind", "clawix_skill"] {
                return Data(#"{"ok":true,"data":{"items":[]}}"#.utf8)
            }
            if args == ["skills", "get", "clawix-active-skills", "--json"] {
                return Data(#"{"ok":true,"data":null}"#.utf8)
            }
            return Data(#"{"ok":true,"data":{}}"#.utf8)
        })
    }
}
