import Foundation
import XCTest
@testable import Clawix

@MainActor
final class AppsStoreCancellationTests: XCTestCase {
    func testSecondAppsReloadSuppressesFirstStaleSnapshot() async {
        let staleStarted = expectation(description: "Stale apps reload started")
        let staleReturned = expectation(description: "Stale apps reload returned")
        let freshReturned = expectation(description: "Fresh apps reload returned")
        var calls = 0
        let store = makeStore { _, _ in
            calls += 1
            if calls == 1 {
                staleStarted.fulfill()
                try? await Task.sleep(nanoseconds: 100_000_000)
                staleReturned.fulfill()
                return Self.snapshot(slug: "stale")
            }
            freshReturned.fulfill()
            return Self.snapshot(slug: "fresh")
        }

        let first = Task { await store.refresh() }
        await fulfillment(of: [staleStarted], timeout: 1)
        let second = Task { await store.refresh() }

        await fulfillment(of: [freshReturned, staleReturned], timeout: 1)
        await first.value
        await second.value
        XCTAssertEqual(store.apps.map(\.slug), ["fresh"])
        XCTAssertFalse(store.isLoading)
    }

    func testCancelSurfaceWorkSuppressesLateAppsReload() async {
        let loadStarted = expectation(description: "Apps reload started")
        let loadReturned = expectation(description: "Apps reload returned after teardown")
        let store = makeStore { _, _ in
            loadStarted.fulfill()
            try? await Task.sleep(nanoseconds: 50_000_000)
            loadReturned.fulfill()
            return Self.snapshot(slug: "closed")
        }

        let task = Task { await store.refresh() }
        await fulfillment(of: [loadStarted], timeout: 1)
        store.cancelSurfaceWork()

        await fulfillment(of: [loadReturned], timeout: 1)
        await task.value
        XCTAssertTrue(store.apps.isEmpty)
        XCTAssertFalse(store.isLoading)
    }

    func testUpdateRemainsImmediatelyVisibleWhileReloadIsAsync() throws {
        let store = makeStore { _, _ in
            try? await Task.sleep(nanoseconds: 100_000_000)
            return Self.snapshot(slug: "disk")
        }
        let app = AppRecord(slug: "instant", name: "Instant")

        try store.update(app)

        XCTAssertEqual(store.apps.map(\.slug), ["instant"])
        store.cancelSurfaceWork()
    }

    private func makeStore(
        loadOperation: @escaping AppsStore.LoadOperation
    ) -> AppsStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return AppsStore(
            rootURL: root,
            autoLoad: false,
            startPolling: false,
            loadOperation: loadOperation
        )
    }

    private static func snapshot(slug: String) -> AppsStore.AppsSnapshot {
        AppsStore.AppsSnapshot(
            apps: [AppRecord(slug: slug, name: slug)],
            mtimes: [slug: Date()]
        )
    }
}
