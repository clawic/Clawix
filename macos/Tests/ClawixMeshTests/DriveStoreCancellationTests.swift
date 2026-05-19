import Foundation
import XCTest
@testable import Clawix

@MainActor
final class DriveStoreCancellationTests: XCTestCase {
    func testStartingSecondRefreshCancelsStaleListing() async {
        let staleStarted = expectation(description: "Stale Drive listing started")
        let staleCancelled = expectation(description: "Stale Drive listing cancelled")
        let freshReturned = expectation(description: "Fresh Drive listing returned")
        let client = FakeDriveClient()
        var calls = 0
        client.onListItems = { _, _, _ in
            calls += 1
            if calls == 1 {
                staleStarted.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    staleCancelled.fulfill()
                    throw CancellationError()
                }
                return Self.response(ids: ["stale"])
            }
            freshReturned.fulfill()
            return Self.response(ids: ["fresh"])
        }
        let store = DriveStore(client: client, realtime: FakeDriveRealtimeClient(), attachSupervisor: false)

        let first = Task { await store.refresh() }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task { await store.refresh() }

        await fulfillment(of: [staleCancelled, freshReturned], timeout: 1)
        await first.value
        await second.value
        XCTAssertEqual(store.items.map(\.id), ["fresh"])
    }

    func testStaleRefreshCannotOverwriteFreshListing() async {
        let staleStarted = expectation(description: "Stale Drive listing started")
        let staleReturned = expectation(description: "Stale Drive listing returned")
        let freshReturned = expectation(description: "Fresh Drive listing returned")
        let client = FakeDriveClient()
        var calls = 0
        client.onListItems = { _, _, _ in
            calls += 1
            if calls == 1 {
                staleStarted.fulfill()
                try? await Task.sleep(nanoseconds: 100_000_000)
                staleReturned.fulfill()
                return Self.response(ids: ["stale"])
            }
            freshReturned.fulfill()
            return Self.response(ids: ["fresh"])
        }
        let store = DriveStore(client: client, realtime: FakeDriveRealtimeClient(), attachSupervisor: false)

        let first = Task { await store.refresh() }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task { await store.refresh() }

        await fulfillment(of: [freshReturned, staleReturned], timeout: 1)
        await first.value
        await second.value
        XCTAssertEqual(store.items.map(\.id), ["fresh"])
    }

    func testQueryDebounceCancelsStaleRefreshBeforeListing() async {
        let client = FakeDriveClient()
        var queries: [String?] = []
        client.onListItems = { _, _, query in
            queries.append(query)
            return Self.response(ids: [query ?? "empty"])
        }
        let store = DriveStore(client: client, realtime: FakeDriveRealtimeClient(), attachSupervisor: false)

        store.setQuery("stale")
        store.setQuery("fresh")

        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(queries, ["fresh"])
        XCTAssertEqual(store.items.map(\.id), ["fresh"])
    }

    func testCancelSurfaceWorkStopsRealtimeAndSuppressesRefreshResult() async {
        let staleStarted = expectation(description: "Drive listing started")
        let staleCancelled = expectation(description: "Drive listing cancelled")
        let client = FakeDriveClient()
        let realtime = FakeDriveRealtimeClient()
        client.onListItems = { _, _, _ in
            staleStarted.fulfill()
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                staleCancelled.fulfill()
                throw CancellationError()
            }
            return Self.response(ids: ["stale"])
        }
        let store = DriveStore(client: client, realtime: realtime, attachSupervisor: false)

        let task = Task { await store.refresh() }
        await fulfillment(of: [staleStarted], timeout: 1)

        store.cancelSurfaceWork()

        await fulfillment(of: [staleCancelled], timeout: 1)
        await task.value
        XCTAssertEqual(realtime.stopCount, 1)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testCancelSurfaceWorkSuppressesInFlightCreateFolderRefresh() async {
        let createStarted = expectation(description: "Drive folder create started")
        let createReturned = expectation(description: "Drive folder create returned")
        let client = FakeDriveClient()
        var refreshCalls = 0
        client.onListItems = { _, _, _ in
            refreshCalls += 1
            return Self.response(ids: ["stale-refresh"])
        }
        client.onCreateFolder = { name, _ in
            createStarted.fulfill()
            try? await Task.sleep(nanoseconds: 100_000_000)
            createReturned.fulfill()
            return makeDriveDetail(id: name)
        }
        let store = DriveStore(client: client, realtime: FakeDriveRealtimeClient(), attachSupervisor: false)

        let task = Task { await store.createFolder(name: "late", parentId: nil) }
        await fulfillment(of: [createStarted], timeout: 1)

        store.cancelSurfaceWork()

        await fulfillment(of: [createReturned], timeout: 1)
        await task.value
        XCTAssertNil(store.lastError)
        XCTAssertEqual(refreshCalls, 0)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testCancelSurfaceWorkSuppressesInFlightUploadError() async {
        let uploadStarted = expectation(description: "Drive upload started")
        let uploadReturned = expectation(description: "Drive upload returned")
        let client = FakeDriveClient()
        var refreshCalls = 0
        client.onListItems = { _, _, _ in
            refreshCalls += 1
            return Self.response(ids: ["stale-refresh"])
        }
        client.onUpload = { _, _, _ in
            uploadStarted.fulfill()
            try? await Task.sleep(nanoseconds: 100_000_000)
            uploadReturned.fulfill()
            throw ClawJSDriveClient.Error.http(status: 500, body: "stale")
        }
        let store = DriveStore(client: client, realtime: FakeDriveRealtimeClient(), attachSupervisor: false)

        let task = Task {
            await store.upload(fileURL: URL(fileURLWithPath: "/tmp/late.txt"), parentId: nil)
        }
        await fulfillment(of: [uploadStarted], timeout: 1)

        store.cancelSurfaceWork()

        await fulfillment(of: [uploadReturned], timeout: 1)
        let result = await task.value
        guard case .failure = result else {
            XCTFail("Cancelled upload unexpectedly succeeded")
            return
        }
        XCTAssertNil(store.lastError)
        XCTAssertEqual(refreshCalls, 0)
    }

    func testCancelSurfaceWorkSuppressesReplaceDuplicateErrorRefresh() async {
        let trashReturned = expectation(description: "Drive duplicate trash returned")
        let uploadStarted = expectation(description: "Drive duplicate replacement started")
        let uploadReturned = expectation(description: "Drive duplicate replacement returned")
        let client = FakeDriveClient()
        var refreshCalls = 0
        client.onListItems = { _, _, _ in
            refreshCalls += 1
            return Self.response(ids: ["stale-refresh"])
        }
        client.onTrashItem = { id in
            trashReturned.fulfill()
            return makeDriveDetail(id: id)
        }
        client.onUpload = { _, _, _ in
            uploadStarted.fulfill()
            try? await Task.sleep(nanoseconds: 100_000_000)
            uploadReturned.fulfill()
            throw ClawJSDriveClient.Error.http(status: 500, body: "stale")
        }
        let store = DriveStore(client: client, realtime: FakeDriveRealtimeClient(), attachSupervisor: false)

        let task = Task {
            await store.replaceDuplicate(
                existingId: "old",
                fileURL: URL(fileURLWithPath: "/tmp/late.txt"),
                parentId: nil
            )
        }
        await fulfillment(of: [trashReturned, uploadStarted], timeout: 1)

        store.cancelSurfaceWork()

        await fulfillment(of: [uploadReturned], timeout: 1)
        await task.value
        XCTAssertNil(store.lastError)
        XCTAssertEqual(refreshCalls, 0)
    }

    func testCancelSurfaceWorkSuppressesInFlightThumbnailCacheWrite() async {
        let thumbnailStarted = expectation(description: "Drive thumbnail load started")
        let thumbnailReturned = expectation(description: "Drive thumbnail load returned")
        let client = FakeDriveClient()
        client.onLoadThumbnailBytes = { id, _ in
            thumbnailStarted.fulfill()
            try? await Task.sleep(nanoseconds: 100_000_000)
            thumbnailReturned.fulfill()
            return Data(id.utf8)
        }
        let store = DriveStore(client: client, realtime: FakeDriveRealtimeClient(), attachSupervisor: false)

        let task = Task {
            await store.thumbnail(for: "late-thumbnail")
        }
        await fulfillment(of: [thumbnailStarted], timeout: 1)

        store.cancelSurfaceWork()

        await fulfillment(of: [thumbnailReturned], timeout: 1)
        let result = await task.value
        XCTAssertNil(result)
        XCTAssertNil(store.thumbnailCache["late-thumbnail"])
    }

    private static func response(ids: [String]) -> ClawJSDriveClient.ListItemsResponse {
        ClawJSDriveClient.ListItemsResponse(
            items: ids.map { item(id: $0) },
            counts: .init(myDrive: ids.count, recent: 0, starred: 0, shared: 0, trash: 0),
            breadcrumbs: []
        )
    }

    private static func item(id: String) -> ClawJSDriveClient.DriveItem {
        ClawJSDriveClient.DriveItem(
            id: id,
            name: id.capitalized,
            kind: "file",
            parentId: nil,
            mimeType: "text/plain",
            sizeBytes: 1,
            starred: false,
            trashedAt: nil,
            previewKind: "text",
            previewText: id,
            currentRevisionId: nil,
            childCount: 0,
            commentCount: 0,
            revisionCount: 1,
            shareCount: 0,
            createdAt: "2026-05-19T00:00:00Z",
            updatedAt: "2026-05-19T00:00:00Z",
            lastViewedAt: nil
        )
    }

}

private final class FakeDriveClient: ClawJSDriveClienting, @unchecked Sendable {
    var bearerToken: String?
    var onListItems: (String, String?, String?) async throws -> ClawJSDriveClient.ListItemsResponse = { _, _, _ in
        ClawJSDriveClient.ListItemsResponse(
            items: [],
            counts: .init(myDrive: 0, recent: 0, starred: 0, shared: 0, trash: 0),
            breadcrumbs: []
        )
    }
    var onCreateFolder: (String, String?) async throws -> ClawJSDriveClient.DriveItemDetail = { name, _ in
        makeDriveDetail(id: name)
    }
    var onUpdateItem: (String, String?, Bool?, String?) async throws -> ClawJSDriveClient.DriveItemDetail = { id, _, _, _ in
        makeDriveDetail(id: id)
    }
    var onTrashItem: (String) async throws -> ClawJSDriveClient.DriveItemDetail = { id in
        makeDriveDetail(id: id)
    }
    var onRestoreItem: (String) async throws -> ClawJSDriveClient.DriveItemDetail = { id in
        makeDriveDetail(id: id)
    }
    var onDeleteItem: (String) async throws -> Bool = { _ in true }
    var onUpload: (URL, String?, String?) async throws -> ClawJSDriveClient.DriveItemDetail = { filePath, _, _ in
        makeDriveDetail(id: filePath.lastPathComponent)
    }
    var onUploadBytes: (Data, String, String, String?) async throws -> ClawJSDriveClient.DriveItemDetail = { _, fileName, _, _ in
        makeDriveDetail(id: fileName)
    }
    var onMarkViewed: (String) async throws -> Void = { _ in }
    var onLoadThumbnailBytes: (String, Int) async throws -> Data = { id, _ in
        Data(id.utf8)
    }

    func bootstrap() async throws -> ClawJSDriveClient.BootstrapResponse {
        ClawJSDriveClient.BootstrapResponse(counts: .init(myDrive: 0, recent: 0, starred: 0, shared: 0, trash: 0))
    }

    func listItems(view: String, parentId: String?, query: String?) async throws -> ClawJSDriveClient.ListItemsResponse {
        try await onListItems(view, parentId, query)
    }

    func getItem(_ id: String) async throws -> ClawJSDriveClient.DriveItemDetail {
        makeDriveDetail(id: id)
    }

    func markViewed(_ id: String) async throws {
        try await onMarkViewed(id)
    }

    func createFolder(name: String, parentId: String?) async throws -> ClawJSDriveClient.DriveItemDetail {
        try await onCreateFolder(name, parentId)
    }

    func updateItem(_ id: String, name: String?, starred: Bool?, parentId: String?) async throws -> ClawJSDriveClient.DriveItemDetail {
        try await onUpdateItem(id, name, starred, parentId)
    }

    func moveItem(_ id: String, parentId: String?) async throws -> ClawJSDriveClient.DriveItemDetail {
        makeDriveDetail(id: id)
    }

    func trashItem(_ id: String) async throws -> ClawJSDriveClient.DriveItemDetail {
        try await onTrashItem(id)
    }

    func restoreItem(_ id: String) async throws -> ClawJSDriveClient.DriveItemDetail {
        try await onRestoreItem(id)
    }

    func deleteItem(_ id: String) async throws -> Bool {
        try await onDeleteItem(id)
    }

    func upload(filePath: URL, parentId: String?, duplicatePolicy: String?) async throws -> ClawJSDriveClient.DriveItemDetail {
        try await onUpload(filePath, parentId, duplicatePolicy)
    }

    func uploadBytes(_ data: Data, fileName: String, mimeType: String, parentId: String?) async throws -> ClawJSDriveClient.DriveItemDetail {
        try await onUploadBytes(data, fileName, mimeType, parentId)
    }

    func downloadItem(_ id: String, to destination: URL) async throws {
        try Data().write(to: destination)
    }

    func loadThumbnailBytes(_ id: String, size: Int) async throws -> Data {
        try await onLoadThumbnailBytes(id, size)
    }

    func getExif(_ id: String) async throws -> ClawJSDriveClient.ExifRecord? { nil }

    func searchText(_ query: String) async throws -> [ClawJSDriveClient.DriveItem] { [] }

    func searchSemantic(_ query: String, limit: Int) async throws -> [ClawJSDriveClient.SemanticResult] { [] }

    func listAllShares(_ itemId: String) async throws -> ClawJSDriveClient.AllSharesResponse {
        ClawJSDriveClient.AllSharesResponse(read: [], tailnet: [], tunnel: [], agent: [])
    }

    func createReadShare(_ itemId: String, label: String) async throws -> ClawJSDriveClient.CreateReadShareResponse {
        ClawJSDriveClient.CreateReadShareResponse(
            share: .init(id: "share", itemId: itemId, label: label, mode: "read"),
            token: "token",
            url: "https://example.invalid"
        )
    }

    func createTailnetShare(_ itemId: String) async throws -> ClawJSDriveClient.TailnetShareRecord {
        ClawJSDriveClient.TailnetShareRecord(id: "tailnet", itemId: itemId, magicdnsName: "drive.tailnet", createdAt: "", revokedAt: nil)
    }

    func createTunnelShare(_ itemId: String) async throws -> ClawJSDriveClient.TunnelShareRecord {
        ClawJSDriveClient.TunnelShareRecord(id: "tunnel", itemId: itemId, tunnelUrl: "https://example.invalid", startedAt: "", stoppedAt: nil, status: "running")
    }

    func createAgentShare(
        _ itemId: String,
        capabilityKind: String,
        ttlMinutes: Int,
        reason: String?,
        agentName: String
    ) async throws -> ClawJSDriveClient.CreateAgentShareResponse {
        let record = ClawJSDriveClient.AgentShareRecord(
            id: "agent",
            itemId: itemId,
            agentName: agentName,
            createdAt: "",
            expiresAt: "",
            revokedAt: nil,
            usedCount: 0,
            lastUsedAt: nil
        )
        return ClawJSDriveClient.CreateAgentShareResponse(mode: "agent", record: record, token: "token")
    }

    func ensureProjectFolder(slug: String) async throws -> String {
        "project-\(slug)"
    }
}

private func makeDriveDetail(id: String) -> ClawJSDriveClient.DriveItemDetail {
    ClawJSDriveClient.DriveItemDetail(
        id: id,
        name: id.capitalized,
        kind: "file",
        parentId: nil,
        mimeType: "text/plain",
        sizeBytes: 1,
        starred: false,
        trashedAt: nil,
        previewKind: "text",
        previewText: id,
        currentRevisionId: nil,
        childCount: 0,
        commentCount: 0,
        revisionCount: 1,
        shareCount: 0,
        createdAt: "2026-05-19T00:00:00Z",
        updatedAt: "2026-05-19T00:00:00Z",
        lastViewedAt: nil,
        breadcrumbs: []
    )
}

@MainActor
private final class FakeDriveRealtimeClient: ClawJSDriveRealtimeClienting {
    var onEvent: ((ClawJSDriveRealtimeClient.Event) -> Void)?
    var onDisconnect: ((Swift.Error?) -> Void)?
    var token: String?
    var subscribeCount = 0
    var stopCount = 0

    func setToken(_ token: String?) {
        self.token = token
    }

    func subscribe(parentId: String?, itemId: String?, kinds: [String]?) {
        subscribeCount += 1
    }

    func stop() {
        stopCount += 1
    }
}
