import Foundation
import XCTest
@testable import Clawix

@MainActor
final class EditorStoreCancellationTests: XCTestCase {
    func testSecondEditorReloadSuppressesFirstStaleSnapshot() async {
        let staleStarted = expectation(description: "Stale editor reload started")
        let staleReturned = expectation(description: "Stale editor reload returned")
        let freshReturned = expectation(description: "Fresh editor reload returned")
        var calls = 0
        let store = makeStore { _, _ in
            calls += 1
            if calls == 1 {
                staleStarted.fulfill()
                try? await Task.sleep(nanoseconds: 100_000_000)
                staleReturned.fulfill()
                return Self.snapshot(id: "stale")
            }
            freshReturned.fulfill()
            return Self.snapshot(id: "fresh")
        }

        let first = Task { await store.refresh() }
        await fulfillment(of: [staleStarted], timeout: 1)
        let second = Task { await store.refresh() }

        await fulfillment(of: [freshReturned, staleReturned], timeout: 1)
        await first.value
        await second.value
        XCTAssertEqual(store.documents.map(\.id), ["fresh"])
        XCTAssertFalse(store.isLoading)
    }

    func testCancelSurfaceWorkSuppressesLateEditorReload() async {
        let loadStarted = expectation(description: "Editor reload started")
        let loadReturned = expectation(description: "Editor reload returned after teardown")
        let store = makeStore { _, _ in
            loadStarted.fulfill()
            try? await Task.sleep(nanoseconds: 50_000_000)
            loadReturned.fulfill()
            return Self.snapshot(id: "closed")
        }

        let task = Task { await store.refresh() }
        await fulfillment(of: [loadStarted], timeout: 1)
        store.cancelSurfaceWork()

        await fulfillment(of: [loadReturned], timeout: 1)
        await task.value
        XCTAssertTrue(store.documents.isEmpty)
        XCTAssertFalse(store.isLoading)
    }

    func testUpdateRemainsImmediatelyVisibleWhileReloadIsAsync() throws {
        let store = makeStore { _, _ in
            try? await Task.sleep(nanoseconds: 100_000_000)
            return Self.snapshot(id: "disk")
        }
        let document = Self.document(id: "instant", updatedAt: "2026-05-20T00:00:00.000Z")

        try store.update(document)

        XCTAssertEqual(store.documents.map(\.id), ["instant"])
        store.cancelSurfaceWork()
    }

    private func makeStore(
        loadOperation: @escaping EditorStore.LoadOperation
    ) -> EditorStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return EditorStore(
            rootURL: root,
            autoLoad: false,
            loadOperation: loadOperation
        )
    }

    private static func snapshot(id: String) -> EditorStore.EditorSnapshot {
        EditorStore.EditorSnapshot(documents: [document(id: id, updatedAt: "2026-05-20T00:00:00.000Z")])
    }

    private static func document(id: String, updatedAt: String) -> EditorDocument {
        EditorDocument(
            id: id,
            name: id,
            templateId: "template",
            styleId: "style",
            data: [:],
            createdAt: "2026-05-20T00:00:00.000Z",
            updatedAt: updatedAt
        )
    }
}
