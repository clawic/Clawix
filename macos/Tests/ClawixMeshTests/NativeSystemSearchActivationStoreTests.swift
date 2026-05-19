import XCTest
@testable import Clawix

@MainActor
final class NativeSystemSearchActivationStoreTests: XCTestCase {
    func testManualRebuildReportsIndexedNativeSystemItems() async {
        let store = NativeSystemSearchActivationStore {
            NativeSystemSearchIndexResult(
                ok: true,
                data: NativeSystemSearchIndexResult.DataPayload(
                    rebuilt: true,
                    reindexed: 2,
                    indexedBySource: ["native.system": 2],
                    pendingSources: []
                )
            )
        }

        await store.rebuildNow()

        XCTAssertEqual(store.state, .indexed(2))
        XCTAssertEqual(store.statusText, "Indexed 2 native items.")
    }

    func testManualRebuildKeepsSourcePendingWhenNoHostItemsAreIndexed() async {
        let store = NativeSystemSearchActivationStore {
            NativeSystemSearchIndexResult(
                ok: true,
                data: NativeSystemSearchIndexResult.DataPayload(
                    rebuilt: true,
                    reindexed: 0,
                    indexedBySource: ["native.system": 0],
                    pendingSources: []
                )
            )
        }

        await store.rebuildNow()

        XCTAssertEqual(store.state, .externalPending)
        XCTAssertEqual(store.statusText, "Shortcuts access is pending on this host.")
    }
}
