import Foundation
import XCTest
@testable import Clawix

@MainActor
final class DatabaseManagerCancellationTests: XCTestCase {
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
        XCTAssertEqual(manager.records(for: "tasks").map(\.id), ["fast"])
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

}

private final class FakeDatabaseClient: DatabaseClienting {
    var bearerToken: String? = "test-token"
    let origin = URL(string: "http://127.0.0.1:1")!
    var listRecordsCallCount = 0
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
        DBNamespace(
            id: id,
            displayName: displayName ?? id,
            createdAt: "2026-05-19T00:00:00Z",
            updatedAt: "2026-05-19T00:00:00Z"
        )
    }

    func listCollections(namespaceId: String) async throws -> [DBCollection] { [] }

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
