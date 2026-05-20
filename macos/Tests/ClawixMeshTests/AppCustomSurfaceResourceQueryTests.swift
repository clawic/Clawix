import XCTest
@testable import Clawix

final class AppCustomSurfaceResourceQueryTests: AppCustomSurfaceCapabilityTestCase {
    func testResourceRegistryReadsOnlyRegisteredPathResources() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let registryRoot = root.appendingPathComponent("registry", isDirectory: true)
        let fileURL = root.appendingPathComponent("instruction.md", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "read me\nand keep going".write(to: fileURL, atomically: true, encoding: .utf8)

        let resource = makeResource(
            id: "res_instruction1",
            kind: "instruction",
            locator: AppResourceLocator(kind: "path", value: fileURL.path),
            label: "Instruction"
        )
        try writeResources([resource], to: registryRoot)

        let store = AppResourceRegistryStore(directory: registryRoot)
        XCTAssertEqual(try store.list(kind: "instruction").map(\.id), ["res_instruction1"])

        let read = try store.read("res_instruction1", maxBytes: 7)
        XCTAssertEqual(read.content, "read me")
        XCTAssertEqual(read.truncated, true)
        XCTAssertNil(read.error)
        XCTAssertEqual(read.bridgeValue["redactionPolicy"] as? String, AppBridgeRedactionPolicy.policyId)
    }

    func testResourceRegistryRejectsUnregisteredDirectoryAndNonFileResources() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let registryRoot = root.appendingPathComponent("registry", isDirectory: true)
        let registeredDirectory = root.appendingPathComponent("folder", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: registeredDirectory, withIntermediateDirectories: true)

        let secret = makeResource(
            id: "res_secretref1",
            kind: "secret-ref",
            locator: AppResourceLocator(kind: "secret-ref", value: "vault://demo")
        )
        let directory = makeResource(
            id: "res_directory1",
            kind: "folder",
            locator: AppResourceLocator(kind: "path", value: registeredDirectory.path)
        )
        try writeResources([secret, directory], to: registryRoot)

        let store = AppResourceRegistryStore(directory: registryRoot)
        let read = try store.read("res_secretref1")
        XCTAssertNil(read.content)
        XCTAssertEqual(read.error, "Resource res_secretref1 is not a readable filesystem path.")
        let directoryRead = try store.read("res_directory1")
        XCTAssertNil(directoryRead.content)
        XCTAssertEqual(directoryRead.error, "Resource res_directory1 is a directory.")
        XCTAssertThrowsError(try store.read("res_missing1"))
    }

    func testDBQueryDSLNormalizesFiltersSortAndLimits() throws {
        let query = try AppBridgeQueryDSL.dbQuery(from: [
            "collection": "tasks",
            "filter": [
                "status": "todo",
                "archivedAt": ["isNull": true],
                "priority": ["neq": "low"]
            ],
            "search": "launch",
            "sort": "-updatedAt",
            "limit": 999,
            "offset": -10,
            "facets": ["status", "priority"]
        ])

        XCTAssertEqual(query.collection, "tasks")
        XCTAssertEqual(query.search, "launch")
        XCTAssertEqual(query.limit, 100)
        XCTAssertEqual(query.offset, 0)
        XCTAssertEqual(query.effectiveOffset, 0)
        XCTAssertEqual(query.facets, ["status", "priority"])
        XCTAssertEqual(query.sort, DBFilterState.Sort(field: "updatedAt", descending: true))
        XCTAssertEqual(query.backendFilterJSON?["status"] as? String, "todo")
        XCTAssertEqual(query.filterChips.first(where: { $0.field == "archivedAt" })?.op, .isNull)
        XCTAssertEqual(query.filterChips.first(where: { $0.field == "priority" })?.op, .neq)
    }

    func testDBQueryDSLAcceptsOpaqueCursorOverOffset() throws {
        let cursor = AppBridgeDBQuery.cursor(forOffset: 75)

        let query = try AppBridgeQueryDSL.dbQuery(from: [
            "collection": "tasks",
            "offset": 10,
            "cursor": cursor
        ])

        XCTAssertEqual(query.offset, 10)
        XCTAssertEqual(query.cursor, cursor)
        XCTAssertEqual(query.effectiveOffset, 75)
        XCTAssertEqual(AppBridgeDBQuery.offset(fromCursor: "not-a-cursor"), nil)
    }

    func testDBQueryDSLRejectsCollectionEscapesAndDDLKeys() throws {
        let valid = try AppBridgeQueryDSL.dbQuery(from: [
            "collection": "lab_results",
            "filter": ["patientId": "fixture_patient_ada"],
            "limit": 25
        ])
        XCTAssertEqual(valid.collection, "lab_results")

        XCTAssertThrowsError(try AppBridgeQueryDSL.dbQuery(from: [
            "collection": "../core.sqlite",
            "filter": [:]
        ])) { error in
            XCTAssertEqual(error as? AppBridgeQueryDSL.QueryError, .invalidCollection("../core.sqlite"))
        }
        XCTAssertThrowsError(try AppBridgeQueryDSL.dbQuery(from: [
            "collection": "sqlite_master",
            "filter": [:]
        ])) { error in
            XCTAssertEqual(error as? AppBridgeQueryDSL.QueryError, .invalidCollection("sqlite_master"))
        }
        XCTAssertThrowsError(try AppBridgeQueryDSL.dbQuery(from: [
            "collection": "tasks",
            "sql": "SELECT * FROM tasks"
        ])) { error in
            XCTAssertEqual(error as? AppBridgeQueryDSL.QueryError, .unsupportedQueryKey("sql"))
        }
        XCTAssertThrowsError(try AppBridgeQueryDSL.dbQuery(from: [
            "collection": "tasks",
            "schema": ["fields": [["name": "value", "type": "number"]]]
        ])) { error in
            XCTAssertEqual(error as? AppBridgeQueryDSL.QueryError, .unsupportedQueryKey("schema"))
        }
        XCTAssertThrowsError(try AppBridgeQueryDSL.dbQuery(from: [
            "collection": "tasks",
            "migration": "ALTER TABLE tasks ADD COLUMN raw_secret TEXT"
        ])) { error in
            XCTAssertEqual(error as? AppBridgeQueryDSL.QueryError, .unsupportedQueryKey("migration"))
        }
    }

    func testBridgeValuesRedactSensitiveFieldsAndBuildFacets() {
        let records = [
            DBRecord(
                id: "task-1",
                createdAt: "2026-05-19T00:00:00Z",
                updatedAt: "2026-05-19T00:00:00Z",
                data: [
                    "title": .string("Launch"),
                    "status": .string("todo"),
                    "apiKey": .string("secret-value")
                ]
            ),
            DBRecord(
                id: "task-2",
                createdAt: "2026-05-19T00:00:00Z",
                updatedAt: "2026-05-19T00:00:00Z",
                data: [
                    "title": .string("Ship"),
                    "status": .string("done"),
                    "password": .string("hidden")
                ]
            ),
            DBRecord(
                id: "task-3",
                createdAt: "2026-05-19T00:00:00Z",
                updatedAt: "2026-05-19T00:00:00Z",
                data: [
                    "title": .string("Review"),
                    "status": .string("todo")
                ]
            )
        ]

        let bridge = AppBridgeQueryDSL.bridgeValue(collection: "tasks", record: records[0])
        let data = bridge["data"] as? [String: Any]

        XCTAssertEqual(data?["title"] as? String, "Launch")
        XCTAssertNil(data?["apiKey"])
        XCTAssertEqual(bridge["redactedFields"] as? [String], ["apiKey"])
        XCTAssertEqual(bridge["redactionPolicy"] as? String, AppBridgeRedactionPolicy.policyId)

        let facets = AppBridgeQueryDSL.facetBridgeValue(records: records, fields: ["status", "apiKey"])
        let statusFacet = facets["status"] as? [[String: Any]]
        XCTAssertEqual(statusFacet?.first?["value"] as? String, "todo")
        XCTAssertEqual(statusFacet?.first?["count"] as? Int, 2)
        XCTAssertNil(facets["apiKey"])
    }

    func testBridgeRedactionPolicyMatchesSharedCustomAppContract() {
        XCTAssertEqual(AppBridgeRedactionPolicy.policyId, "claw.customApps.redaction.v1")
        XCTAssertTrue(AppBridgeRedactionPolicy.isSensitiveField("api_key"))
        XCTAssertTrue(AppBridgeRedactionPolicy.isSensitiveField("refresh-token"))
        XCTAssertTrue(AppBridgeRedactionPolicy.isSensitiveField("private key"))
        XCTAssertFalse(AppBridgeRedactionPolicy.isSensitiveField("displayName"))
    }

    func testNextCursorOnlyAppearsWhenMoreResultsMayExist() {
        let cursor = AppBridgeQueryDSL.nextCursor(offset: 20, returnedCount: 10, limit: 10, total: 100)
        XCTAssertEqual(AppBridgeDBQuery.offset(fromCursor: cursor), 30)
        XCTAssertNil(AppBridgeQueryDSL.nextCursor(offset: 90, returnedCount: 10, limit: 10, total: 100))
        XCTAssertNil(AppBridgeQueryDSL.nextCursor(offset: 20, returnedCount: 3, limit: 10, total: nil))
    }

    func testSearchQueryDSLNormalizesCollectionsAndLimits() throws {
        let query = try AppBridgeQueryDSL.searchQuery(from: [
            "query": "agent",
            "collections": ["tasks", "", "notes"],
            "limit": 0,
            "cursor": AppBridgeDBQuery.cursor(forOffset: 8),
            "facets": ["status"]
        ])

        XCTAssertEqual(query.query, "agent")
        XCTAssertEqual(query.collections, ["tasks", "notes"])
        XCTAssertEqual(query.limit, 1)
        XCTAssertEqual(query.effectiveOffset, 8)
        XCTAssertEqual(query.facets, ["status"])
    }

    func testSearchQueryDSLRejectsCollectionEscapes() throws {
        XCTAssertThrowsError(try AppBridgeQueryDSL.searchQuery(from: [
            "query": "agent",
            "collections": ["tasks", "sqlite_master"]
        ])) { error in
            XCTAssertEqual(error as? AppBridgeQueryDSL.QueryError, .invalidCollection("sqlite_master"))
        }
        XCTAssertThrowsError(try AppBridgeQueryDSL.searchQuery(from: [
            "query": "agent",
            "collections": ["../core.sqlite"]
        ])) { error in
            XCTAssertEqual(error as? AppBridgeQueryDSL.QueryError, .invalidCollection("../core.sqlite"))
        }
        XCTAssertThrowsError(try AppBridgeQueryDSL.searchQuery(from: [
            "query": "agent",
            "collections": ["tasks"],
            "sql": "SELECT * FROM tasks"
        ])) { error in
            XCTAssertEqual(error as? AppBridgeQueryDSL.QueryError, .unsupportedQueryKey("sql"))
        }
    }
}
