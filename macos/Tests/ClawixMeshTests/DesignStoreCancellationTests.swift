import Foundation
import XCTest
@testable import Clawix

@MainActor
final class DesignStoreCancellationTests: XCTestCase {
    func testSecondDesignReloadSuppressesFirstStaleSnapshot() async {
        let staleStarted = expectation(description: "Stale design reload started")
        let staleReturned = expectation(description: "Stale design reload returned")
        let freshReturned = expectation(description: "Fresh design reload returned")
        var calls = 0
        let store = makeStore { _ in
            calls += 1
            if calls == 1 {
                staleStarted.fulfill()
                try? await Task.sleep(nanoseconds: 100_000_000)
                staleReturned.fulfill()
                return Self.snapshot(styleId: "stale")
            }
            freshReturned.fulfill()
            return Self.snapshot(styleId: "fresh")
        }

        let first = Task { await store.refresh() }
        await fulfillment(of: [staleStarted], timeout: 1)
        let second = Task { await store.refresh() }

        await fulfillment(of: [freshReturned, staleReturned], timeout: 1)
        await first.value
        await second.value
        XCTAssertEqual(store.styles.map(\.id), ["fresh"])
        XCTAssertFalse(store.isLoading)
    }

    func testCancelSurfaceWorkSuppressesLateDesignReload() async {
        let loadStarted = expectation(description: "Design reload started")
        let loadReturned = expectation(description: "Design reload returned after teardown")
        let store = makeStore { _ in
            loadStarted.fulfill()
            try? await Task.sleep(nanoseconds: 50_000_000)
            loadReturned.fulfill()
            return Self.snapshot(styleId: "closed")
        }

        let task = Task { await store.refresh() }
        await fulfillment(of: [loadStarted], timeout: 1)
        store.cancelSurfaceWork()

        await fulfillment(of: [loadReturned], timeout: 1)
        await task.value
        XCTAssertTrue(store.styles.isEmpty)
        XCTAssertFalse(store.isLoading)
    }

    private func makeStore(
        loadOperation: @escaping DesignStore.LoadOperation
    ) -> DesignStore {
        DesignStore(
            rootURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true),
            autoLoad: false,
            startPolling: false,
            loadOperation: loadOperation
        )
    }

    private static func snapshot(styleId: String) -> DesignStore.DesignSnapshot {
        var style = DesignBuiltins.styles()[0]
        style.id = styleId
        style.name = styleId
        return DesignStore.DesignSnapshot(styles: [style], templates: [], references: [])
    }
}
