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

    func testBootstrapFailureUsesClassifiedLocalizedMessage() async throws {
        let manager = DatabaseManager(
            userDefaults: try makeDefaults(),
            client: FakeDatabaseClient(),
            adminTokenOperation: {
                throw TestFailure(errorDescription: "Could not reach database service: connection refused")
            },
            attachSupervisor: false,
            initialState: .loading
        )

        await manager.bootstrap(force: true)

        let expected = L10n.t("The background bridge is unavailable. Try again after it reconnects.")
        XCTAssertEqual(manager.state, .failed(expected))
        XCTAssertEqual(manager.lastError, expected)
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

    func testRecordRefreshFailureUsesClassifiedLocalizedMessage() async throws {
        let client = FakeDatabaseClient()
        client.onListRecords = { _, _, _, _, _, _ in
            throw TestFailure(errorDescription: "The Internet connection appears to be offline.")
        }
        let manager = DatabaseManager(
            userDefaults: try makeDefaults(),
            client: client,
            attachSupervisor: false,
            initialState: .ready,
            initialCollections: [Self.collection(name: "tasks")]
        )

        await manager.refreshRecords(collection: "tasks")

        XCTAssertEqual(
            manager.lastError,
            L10n.t("The network appears to be offline. Reconnect, then try again.")
        )
        XCTAssertTrue(manager.records(for: "tasks").isEmpty)
    }

    func testRecordRefreshUsesBoundedWindowsAndLoadsNextPageOnDemand() async throws {
        var requests: [(limit: Int?, offset: Int?)] = []
        let client = FakeDatabaseClient()
        client.onListRecords = { _, _, _, _, limit, offset in
            requests.append((limit: limit, offset: offset))
            let start = offset ?? 0
            let end = min(start + (limit ?? 0), 150)
            let records = (start..<end).map { index in
                makeDatabaseRecord(
                    id: "record-\(index)",
                    title: "Record \(index)"
                )
            }
            return DBListResponse(total: 150, items: records)
        }
        let manager = DatabaseManager(
            userDefaults: try makeDefaults(),
            client: client,
            attachSupervisor: false,
            initialState: .ready,
            initialCollections: [Self.collection(name: "tasks")]
        )

        await manager.refreshRecords(collection: "tasks")

        XCTAssertEqual(requests.map(\.limit), [DatabaseManager.defaultRecordPageLimit])
        XCTAssertEqual(requests.map(\.offset), [0])
        XCTAssertEqual(manager.records(for: "tasks").count, DatabaseManager.defaultRecordPageLimit)
        XCTAssertEqual(manager.recordWindow(for: "tasks")?.total, 150)
        XCTAssertEqual(manager.recordWindow(for: "tasks")?.hasNextPage, true)

        await manager.loadNextRecordsPage(collection: "tasks")

        XCTAssertEqual(requests.map(\.limit), [
            DatabaseManager.defaultRecordPageLimit,
            DatabaseManager.defaultRecordPageLimit,
        ])
        XCTAssertEqual(requests.map(\.offset), [0, DatabaseManager.defaultRecordPageLimit])
        XCTAssertEqual(manager.records(for: "tasks").count, 150)
        XCTAssertEqual(manager.records(for: "tasks").first?.id, "record-0")
        XCTAssertEqual(manager.records(for: "tasks").last?.id, "record-149")
        XCTAssertEqual(manager.recordWindow(for: "tasks")?.hasNextPage, false)
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

    func testCancelSurfaceWorkCancelsInFlightCreateRecord() async throws {
        let createStarted = expectation(description: "Database create started")
        let createCancelled = expectation(description: "Database create cancelled")
        let client = FakeDatabaseClient()
        client.onCreateRecord = { _, collection, _ in
            createStarted.fulfill()
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                createCancelled.fulfill()
                throw CancellationError()
            }
            return makeDatabaseRecord(id: "stale", title: collection)
        }
        let manager = DatabaseManager(
            userDefaults: try makeDefaults(),
            client: client,
            attachSupervisor: false,
            initialState: .ready,
            initialCollections: [Self.collection(name: "tasks")]
        )

        let task = Task {
            try await manager.createRecord(collection: "tasks", data: ["title": .string("Stale")])
        }
        await fulfillment(of: [createStarted], timeout: 1)

        manager.cancelSurfaceWork()

        await fulfillment(of: [createCancelled], timeout: 1)
        do {
            _ = try await task.value
            XCTFail("Cancelled create unexpectedly succeeded")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected create error after surface cancellation: \(error)")
        }

        XCTAssertTrue(manager.records(for: "tasks").isEmpty)
        XCTAssertNil(manager.lastError)
    }

    func testCancelSurfaceWorkCancelsInFlightUpdateRecord() async throws {
        let updateStarted = expectation(description: "Database update started")
        let updateCancelled = expectation(description: "Database update cancelled")
        let client = FakeDatabaseClient()
        client.onUpdateRecord = { _, _, id, _ in
            updateStarted.fulfill()
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                updateCancelled.fulfill()
                throw CancellationError()
            }
            throw TestError(message: "stale update failed for \(id)")
        }
        let manager = DatabaseManager(
            userDefaults: try makeDefaults(),
            client: client,
            attachSupervisor: false,
            initialState: .ready,
            initialCollections: [Self.collection(name: "tasks")]
        )

        let task = Task {
            try await manager.updateRecord(collection: "tasks", id: "stale", data: ["title": .string("Stale")])
        }
        await fulfillment(of: [updateStarted], timeout: 1)

        manager.cancelSurfaceWork()

        await fulfillment(of: [updateCancelled], timeout: 1)
        do {
            _ = try await task.value
            XCTFail("Cancelled update unexpectedly succeeded")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected update error after surface cancellation: \(error)")
        }

        XCTAssertNil(manager.lastError)
    }

    func testCancelSurfaceWorkCancelsInFlightDeleteRecord() async throws {
        let deleteStarted = expectation(description: "Database delete started")
        let deleteCancelled = expectation(description: "Database delete cancelled")
        let client = FakeDatabaseClient()
        client.onCreateRecord = { _, _, _ in
            makeDatabaseRecord(id: "existing", title: "Existing")
        }
        client.onDeleteRecord = { _, _, id in
            deleteStarted.fulfill()
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                deleteCancelled.fulfill()
                throw CancellationError()
            }
            return id == "existing"
        }
        let manager = DatabaseManager(
            userDefaults: try makeDefaults(),
            client: client,
            attachSupervisor: false,
            initialState: .ready,
            initialCollections: [Self.collection(name: "tasks")]
        )
        _ = try await manager.createRecord(collection: "tasks", data: ["title": .string("Existing")])

        let task = Task {
            try await manager.deleteRecord(collection: "tasks", id: "existing")
        }
        await fulfillment(of: [deleteStarted], timeout: 1)

        manager.cancelSurfaceWork()

        await fulfillment(of: [deleteCancelled], timeout: 1)
        do {
            try await task.value
            XCTFail("Cancelled delete unexpectedly succeeded")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected delete error after surface cancellation: \(error)")
        }

        XCTAssertEqual(manager.records(for: "tasks").map(\.id), ["existing"])
        XCTAssertNil(manager.lastError)
    }

    func testMultipartUploadBodyStreamsSourceFileIntoTemporaryBody() throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("database-upload-source-\(UUID().uuidString).txt")
        try Data("hello streamed upload".utf8).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let body = try DatabaseClient.makeMultipartUploadBody(
            namespaceId: "main",
            collectionName: "notes",
            recordId: "record-1",
            sourceFileURL: sourceURL,
            filename: "hello.txt",
            contentType: "text/plain"
        )
        defer { try? FileManager.default.removeItem(at: body.fileURL) }

        let bodyData = try Data(contentsOf: body.fileURL)
        let bodyText = try XCTUnwrap(String(data: bodyData, encoding: .utf8))
        XCTAssertEqual(Int64(bodyData.count), body.contentLength)
        XCTAssertTrue(bodyText.contains("name=\"namespaceId\""))
        XCTAssertTrue(bodyText.contains("main"))
        XCTAssertTrue(bodyText.contains("filename=\"hello.txt\""))
        XCTAssertTrue(bodyText.contains("Content-Type: text/plain"))
        XCTAssertTrue(bodyText.contains("hello streamed upload"))
        XCTAssertTrue(bodyText.contains("--\(body.boundary)--"))
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

    private struct TestError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
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
    var onCreateRecord: (String, String, [String: DBJSON]) async throws -> DBRecord = { _, _, _ in
        makeDatabaseRecord(id: "created", title: "Created")
    }
    var onUpdateRecord: (String, String, String, [String: DBJSON]) async throws -> DBRecord = { _, _, id, _ in
        makeDatabaseRecord(id: id, title: "Updated")
    }
    var onDeleteRecord: (String, String, String) async throws -> Bool = { _, _, _ in
        true
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
        try await onCreateRecord(namespaceId, collection, data)
    }

    func updateRecord(namespaceId: String, collection: String, id: String, data: [String: DBJSON]) async throws -> DBRecord {
        try await onUpdateRecord(namespaceId, collection, id, data)
    }

    func deleteRecord(namespaceId: String, collection: String, id: String) async throws -> Bool {
        try await onDeleteRecord(namespaceId, collection, id)
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

    func uploadFile(
        namespaceId: String,
        collectionName: String?,
        recordId: String?,
        fileURL: URL,
        filename: String,
        contentType: String
    ) async throws -> DBFileAsset {
        let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        return DBFileAsset(
            id: "file-1",
            namespaceId: namespaceId,
            collectionName: collectionName,
            recordId: recordId,
            filename: filename,
            contentType: contentType,
            sizeBytes: size,
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

private struct TestFailure: LocalizedError {
    let errorDescription: String?
}
