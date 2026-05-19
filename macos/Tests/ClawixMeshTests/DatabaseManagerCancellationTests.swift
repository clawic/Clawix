import Foundation
import XCTest
@testable import Clawix

@MainActor
final class DatabaseManagerCancellationTests: XCTestCase {
    func testStartingSecondBootstrapCancelsStaleBootstrap() async throws {
        let staleStarted = expectation(description: "Stale database bootstrap started")
        let staleCancelled = expectation(description: "Stale database bootstrap cancelled")
        let freshStarted = expectation(description: "Fresh database bootstrap started")
        let client = FakeDatabaseClient()
        client.onEnsureNamespace = { _, displayName in
            client.ensureNamespaceCallCount += 1
            if client.ensureNamespaceCallCount == 1 {
                staleStarted.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    staleCancelled.fulfill()
                    throw CancellationError()
                }
                return Self.namespace(displayName: displayName)
            }
            freshStarted.fulfill()
            return Self.namespace(displayName: displayName)
        }
        client.onListCollections = { _ in
            [Self.collection(name: "fresh")]
        }
        let manager = DatabaseManager(
            userDefaults: try makeDefaults(),
            client: client,
            adminTokenOperation: { "test-token" },
            attachSupervisor: false,
            initialState: .loading
        )

        let first = Task { await manager.bootstrap(force: true) }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task { await manager.bootstrap(force: true) }

        await fulfillment(of: [staleCancelled, freshStarted], timeout: 1)
        await first.value
        await second.value

        XCTAssertEqual(manager.state, .ready)
        XCTAssertEqual(manager.collections.map(\.name), ["fresh"])
    }

    func testCancelSurfaceWorkSuppressesInFlightBootstrap() async throws {
        let bootstrapStarted = expectation(description: "Database bootstrap started")
        let bootstrapCancelled = expectation(description: "Database bootstrap cancelled")
        let listUnexpected = expectation(description: "Database collection list should not run after surface cancellation")
        listUnexpected.isInverted = true
        let client = FakeDatabaseClient()
        client.onEnsureNamespace = { _, displayName in
            bootstrapStarted.fulfill()
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                bootstrapCancelled.fulfill()
                throw CancellationError()
            }
            return Self.namespace(displayName: displayName)
        }
        client.onListCollections = { _ in
            listUnexpected.fulfill()
            return [Self.collection(name: "unexpected")]
        }
        let manager = DatabaseManager(
            userDefaults: try makeDefaults(),
            client: client,
            adminTokenOperation: { "test-token" },
            attachSupervisor: false,
            initialState: .loading
        )

        let task = Task { await manager.bootstrap(force: true) }
        await fulfillment(of: [bootstrapStarted], timeout: 1)

        manager.cancelSurfaceWork()

        await fulfillment(of: [bootstrapCancelled], timeout: 1)
        await task.value
        await fulfillment(of: [listUnexpected], timeout: 0.05)

        XCTAssertEqual(manager.state, .loading)
        XCTAssertTrue(manager.collections.isEmpty)
    }

    func testRecordReloadCancelsStaleCollectionRequest() async throws {
        let slowStarted = expectation(description: "Slow database request started")
        let slowCancelled = expectation(description: "Slow database request cancelled")
        let fastReturned = expectation(description: "Fast database request returned")
        let client = FakeDatabaseClient()
        client.onListRecords = { _, _, _, _, _, _ in
            client.listRecordsCallCount += 1
            if client.listRecordsCallCount == 1 {
                slowStarted.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    slowCancelled.fulfill()
                    throw CancellationError()
                }
                return DBListResponse(total: 1, items: [makeDatabaseRecord(id: "slow", title: "Slow")])
            }
            fastReturned.fulfill()
            return DBListResponse(total: 1, items: [makeDatabaseRecord(id: "fast", title: "Fast")])
        }
        let manager = DatabaseManager(
            userDefaults: try makeDefaults(),
            client: client,
            attachSupervisor: false,
            initialState: .ready,
            initialCollections: [Self.collection(name: "tasks")]
        )

        manager.requestRefreshRecords(collection: "tasks")
        await fulfillment(of: [slowStarted], timeout: 1)

        manager.requestRefreshRecords(collection: "tasks")

        await fulfillment(of: [slowCancelled, fastReturned], timeout: 1)
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(manager.records(for: "tasks").map(\.id), ["fast"])
    }

    func testCancelCollectionSurfaceWorkCancelsInFlightRecordRefresh() async throws {
        let refreshStarted = expectation(description: "Database record refresh started")
        let refreshCancelled = expectation(description: "Database record refresh cancelled")
        let client = FakeDatabaseClient()
        client.onListRecords = { _, _, _, _, _, _ in
            refreshStarted.fulfill()
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                refreshCancelled.fulfill()
                throw CancellationError()
            }
            return DBListResponse(total: 1, items: [makeDatabaseRecord(id: "stale", title: "Stale")])
        }
        let manager = DatabaseManager(
            userDefaults: try makeDefaults(),
            client: client,
            attachSupervisor: false,
            initialState: .ready,
            initialCollections: [Self.collection(name: "tasks")]
        )

        manager.requestRefreshRecords(collection: "tasks")
        await fulfillment(of: [refreshStarted], timeout: 1)

        manager.cancelCollectionSurfaceWork(collection: "tasks")

        await fulfillment(of: [refreshCancelled], timeout: 1)
        XCTAssertTrue(manager.records(for: "tasks").isEmpty)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "DatabaseManagerCancellationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private static func collection(name: String) -> DBCollection {
        DBCollection(
            namespaceId: "clawix-local",
            name: name,
            displayName: "Tasks",
            fields: [DBFieldDefinition(name: "title", type: .text)],
            indexes: [],
            builtin: true,
            protected: false,
            coreFieldNames: ["title"],
            createdAt: "2026-05-19T00:00:00Z",
            updatedAt: "2026-05-19T00:00:00Z"
        )
    }

    private static func namespace(displayName: String?) -> DBNamespace {
        DBNamespace(
            id: "clawix-local",
            displayName: displayName ?? "clawix-local",
            createdAt: "2026-05-19T00:00:00Z",
            updatedAt: "2026-05-19T00:00:00Z"
        )
    }

}

private final class FakeDatabaseClient: DatabaseClienting {
    var bearerToken: String? = "test-token"
    let origin = URL(string: "http://127.0.0.1:1")!
    var ensureNamespaceCallCount = 0
    var listCollectionsCallCount = 0
    var listRecordsCallCount = 0
    var onEnsureNamespace: (String, String?) async throws -> DBNamespace = { id, displayName in
        DBNamespace(
            id: id,
            displayName: displayName ?? id,
            createdAt: "2026-05-19T00:00:00Z",
            updatedAt: "2026-05-19T00:00:00Z"
        )
    }
    var onListCollections: (String) async throws -> [DBCollection] = { _ in [] }
    var onListRecords: (
        String,
        String,
        [String: Any]?,
        String?,
        Int?,
        Int?
    ) async throws -> DBListResponse<DBRecord> = { _, _, _, _, _, _ in
        DBListResponse(total: 0, items: [])
    }

    func ensureNamespace(id: String, displayName: String?) async throws -> DBNamespace {
        try await onEnsureNamespace(id, displayName)
    }

    func listCollections(namespaceId: String) async throws -> [DBCollection] {
        listCollectionsCallCount += 1
        return try await onListCollections(namespaceId)
    }

    func updateCollection(
        namespaceId: String,
        name: String,
        displayName: String,
        fields: [DBFieldDefinition],
        indexes: [DBIndexDefinition]
    ) async throws -> DBCollection {
        DBCollection(
            namespaceId: namespaceId,
            name: name,
            displayName: displayName,
            fields: fields,
            indexes: indexes,
            builtin: false,
            protected: false,
            coreFieldNames: [],
            createdAt: "2026-05-19T00:00:00Z",
            updatedAt: "2026-05-19T00:00:00Z"
        )
    }

    func listRecords(
        namespaceId: String,
        collection: String,
        filter: [String: Any]?,
        sort: String?,
        limit: Int?,
        offset: Int?
    ) async throws -> DBListResponse<DBRecord> {
        try await onListRecords(namespaceId, collection, filter, sort, limit, offset)
    }

    func createRecord(namespaceId: String, collection: String, data: [String: DBJSON]) async throws -> DBRecord {
        makeDatabaseRecord(id: "created", title: "Created")
    }

    func updateRecord(namespaceId: String, collection: String, id: String, data: [String: DBJSON]) async throws -> DBRecord {
        makeDatabaseRecord(id: id, title: "Updated")
    }

    func deleteRecord(namespaceId: String, collection: String, id: String) async throws -> Bool {
        true
    }

    func downloadFile(fileId: String) async throws -> Data {
        Data()
    }

    func uploadFile(
        namespaceId: String,
        collectionName: String?,
        recordId: String?,
        filename: String,
        contentType: String,
        data: Data
    ) async throws -> DBFileAsset {
        DBFileAsset(
            id: "file-1",
            namespaceId: namespaceId,
            collectionName: collectionName,
            recordId: recordId,
            filename: filename,
            contentType: contentType,
            sizeBytes: Int64(data.count),
            createdAt: "2026-05-19T00:00:00Z",
            downloadPath: "/files/file-1"
        )
    }
}

private func makeDatabaseRecord(id: String, title: String) -> DBRecord {
    DBRecord(
        id: id,
        createdAt: "2026-05-19T00:00:00Z",
        updatedAt: "2026-05-19T00:00:00Z",
        data: ["title": .string(title)]
    )
}
