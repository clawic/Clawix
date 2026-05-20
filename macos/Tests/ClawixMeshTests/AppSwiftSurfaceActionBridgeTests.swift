import XCTest
@testable import Clawix

final class AppSwiftSurfaceActionBridgeTests: AppCustomSurfaceCapabilityTestCase {
    @MainActor
    func testSwiftSurfaceReadActionDoesNotRequestInterruptiveApproval() async throws {
        let app = AppRecord(
            slug: "swift-dashboard",
            name: "Swift Dashboard",
            declaredCapabilities: ["search.query"],
            surfaceKind: .swiftDeclarative
        )
        var reports: [SurfaceRouteReport] = []
        let reporter = SurfaceRouteReporter(surfaceID: "app:swift-dashboard") { report in
            reports.append(report)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let appsStore = AppsStore(rootURL: root)
        let action = AppSwiftSurfaceRenderedAction(
            action: AppSwiftSurfaceAction(
                invocation: .sdkRead,
                capabilityId: "search.query",
                operation: "search.query"
            )
        )

        let result = await AppSwiftSurfaceActionBridge(
            app: app,
            appsStore: appsStore,
            surfaceReporter: reporter,
            highRiskActionDispatcher: AppUnavailableHighRiskActionDispatcher(),
            approvalHandler: { _, _, _ in
                XCTFail("Read actions should not request interruptive approval")
            }
        ).handle(action)

        XCTAssertEqual(result, .failed("Swift surface search bridge is unavailable"))
        XCTAssertTrue(reports.contains(.error(message: "Swift surface search bridge is unavailable")))
    }

    @MainActor
    func testSwiftSurfaceResourceListExecutesThroughRegisteredResources() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let registryRoot = root.appendingPathComponent("registry", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = AppRecord(
            slug: "swift-dashboard",
            name: "Swift Dashboard",
            declaredCapabilities: ["resources.list"],
            surfaceKind: .swiftDeclarative
        )
        let appsStore = AppsStore(rootURL: root.appendingPathComponent("apps", isDirectory: true))
        let resource = makeResource(
            id: "res_swift1",
            kind: "instruction",
            locator: AppResourceLocator(kind: "path", value: "/tmp/swift-resource.md")
        )
        try writeResources([resource], to: registryRoot)
        let registry = AppResourceRegistryStore(directory: registryRoot)
        var reports: [SurfaceRouteReport] = []
        let reporter = SurfaceRouteReporter(surfaceID: "app:swift-dashboard") { report in
            reports.append(report)
        }
        let action = AppSwiftSurfaceRenderedAction(
            action: AppSwiftSurfaceAction(
                invocation: .sdkRead,
                capabilityId: "resources.list",
                operation: "resources.list",
                arguments: ["kind": .string("instruction")]
            )
        )

        let result = await AppSwiftSurfaceActionBridge(
            app: app,
            appsStore: appsStore,
            resourceRegistry: registry,
            surfaceReporter: reporter,
            highRiskActionDispatcher: AppUnavailableHighRiskActionDispatcher(),
            approvalHandler: { _, _, _ in
                XCTFail("Resource lists should not request interruptive approval")
            }
        ).handle(action)

        XCTAssertEqual(result, .executedRead("resources.list", 1))
        XCTAssertTrue(reports.contains(.loading(message: "Listing Swift surface resources", progress: 0.2)))
        XCTAssertTrue(reports.contains(.partial(message: "Swift surface listed 1 resources")))
    }

    @MainActor
    func testSwiftSurfaceResourceReadExecutesThroughRegisteredResources() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let registryRoot = root.appendingPathComponent("registry", isDirectory: true)
        let fileURL = root.appendingPathComponent("swift-resource.md", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "swift resource content".write(to: fileURL, atomically: true, encoding: .utf8)
        let app = AppRecord(
            slug: "swift-dashboard",
            name: "Swift Dashboard",
            declaredCapabilities: ["resources.read"],
            surfaceKind: .swiftDeclarative
        )
        let appsStore = AppsStore(rootURL: root.appendingPathComponent("apps", isDirectory: true))
        let resource = makeResource(
            id: "res_swift1",
            kind: "instruction",
            locator: AppResourceLocator(kind: "path", value: fileURL.path)
        )
        try writeResources([resource], to: registryRoot)
        let registry = AppResourceRegistryStore(directory: registryRoot)
        var reports: [SurfaceRouteReport] = []
        let reporter = SurfaceRouteReporter(surfaceID: "app:swift-dashboard") { report in
            reports.append(report)
        }
        let action = AppSwiftSurfaceRenderedAction(
            action: AppSwiftSurfaceAction(
                invocation: .sdkRead,
                capabilityId: "resources.read",
                operation: "resources.read",
                arguments: [
                    "id": .string("res_swift1"),
                    "maxBytes": .int(5)
                ]
            )
        )

        let result = await AppSwiftSurfaceActionBridge(
            app: app,
            appsStore: appsStore,
            resourceRegistry: registry,
            surfaceReporter: reporter,
            highRiskActionDispatcher: AppUnavailableHighRiskActionDispatcher(),
            approvalHandler: { _, _, _ in
                XCTFail("Resource reads should not request interruptive approval")
            }
        ).handle(action)

        XCTAssertEqual(result, .executedRead("resources.read", 1))
        XCTAssertTrue(reports.contains(.loading(message: "Reading Swift surface resource", progress: 0.2)))
        XCTAssertTrue(reports.contains(.partial(message: "Swift surface read resource: res_swift1")))
    }

    @MainActor
    func testSwiftSurfaceDBQueryExecutesThroughDatabaseManager() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let appsStore = AppsStore(rootURL: root)
        let client = AppCustomSurfaceFakeDatabaseClient()
        client.onListRecords = { namespace, collection, filter, sort, limit, offset in
            XCTAssertEqual(namespace, "clawix-local")
            XCTAssertEqual(collection, "tasks")
            XCTAssertEqual(filter?["status"] as? String, "todo")
            XCTAssertEqual(sort, "-updatedAt")
            XCTAssertEqual(limit, 10)
            XCTAssertEqual(offset, 0)
            return DBListResponse(total: 1, items: [
                self.makeDBRecord(id: "task-1", title: "Launch", status: "todo")
            ])
        }
        let manager = DatabaseManager(
            userDefaults: try makeDefaults(),
            client: client,
            attachSupervisor: false,
            initialState: .ready,
            initialCollections: [makeCollection("tasks")]
        )
        let app = AppRecord(
            slug: "swift-dashboard",
            name: "Swift Dashboard",
            declaredCapabilities: ["db.query"],
            surfaceKind: .swiftDeclarative
        )
        var reports: [SurfaceRouteReport] = []
        let reporter = SurfaceRouteReporter(surfaceID: "app:swift-dashboard") { report in
            reports.append(report)
        }
        let action = AppSwiftSurfaceRenderedAction(
            action: AppSwiftSurfaceAction(
                invocation: .sdkRead,
                capabilityId: "db.query",
                operation: "db.query",
                arguments: [
                    "collection": .string("tasks"),
                    "filter": .object(["status": .string("todo")]),
                    "sort": .string("-updatedAt"),
                    "limit": .int(10)
                ]
            )
        )

        let result = await AppSwiftSurfaceActionBridge(
            app: app,
            appsStore: appsStore,
            databaseManager: manager,
            surfaceReporter: reporter,
            highRiskActionDispatcher: AppUnavailableHighRiskActionDispatcher()
        ).handle(action)

        XCTAssertEqual(result, .executedRead("db.query", 1))
        XCTAssertEqual(client.listRecordsCallCount, 1)
        XCTAssertTrue(reports.contains(.partial(message: "Swift surface queried 1 database records")))
    }

    @MainActor
    func testSwiftSurfaceSearchQueryExecutesThroughDatabaseManager() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let appsStore = AppsStore(rootURL: root)
        let client = AppCustomSurfaceFakeDatabaseClient()
        client.onListRecords = { _, collection, _, sort, limit, offset in
            XCTAssertEqual(collection, "tasks")
            XCTAssertEqual(sort, "-updatedAt")
            XCTAssertEqual(limit, 100)
            XCTAssertEqual(offset, 0)
            return DBListResponse(total: nil, items: [
                self.makeDBRecord(id: "task-1", title: "Launch agent", status: "todo"),
                self.makeDBRecord(id: "task-2", title: "Ignore", status: "done")
            ])
        }
        let manager = DatabaseManager(
            userDefaults: try makeDefaults(),
            client: client,
            attachSupervisor: false,
            initialState: .ready,
            initialCollections: [makeCollection("tasks")]
        )
        let app = AppRecord(
            slug: "swift-dashboard",
            name: "Swift Dashboard",
            declaredCapabilities: ["search.query"],
            surfaceKind: .swiftDeclarative
        )
        var reports: [SurfaceRouteReport] = []
        let reporter = SurfaceRouteReporter(surfaceID: "app:swift-dashboard") { report in
            reports.append(report)
        }
        let action = AppSwiftSurfaceRenderedAction(
            action: AppSwiftSurfaceAction(
                invocation: .sdkRead,
                capabilityId: "search.query",
                operation: "search.query",
                arguments: [
                    "query": .string("agent"),
                    "collections": .array([.string("tasks")]),
                    "limit": .int(5)
                ]
            )
        )

        let result = await AppSwiftSurfaceActionBridge(
            app: app,
            appsStore: appsStore,
            databaseManager: manager,
            surfaceReporter: reporter,
            highRiskActionDispatcher: AppUnavailableHighRiskActionDispatcher()
        ).handle(action)

        XCTAssertEqual(result, .executedRead("search.query", 1))
        XCTAssertEqual(client.listRecordsCallCount, 1)
        XCTAssertTrue(reports.contains(.partial(message: "Swift surface found 1 search results")))
    }

    @MainActor
    func testSwiftSurfaceHighRiskActionUsesApprovalDispatcherAndAudit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let appsStore = AppsStore(rootURL: root)
        let app = AppRecord(
            slug: "swift-iot-dashboard",
            name: "Swift IoT Dashboard",
            declaredCapabilities: ["iot.device.action.invoke"],
            surfaceKind: .swiftDeclarative
        )
        let dispatcher = RecordingSwiftSurfaceActionDispatcher(result: .dispatched(["ok": true]))
        let action = AppSwiftSurfaceRenderedAction(
            action: AppSwiftSurfaceAction(
                invocation: .sdkAction,
                capabilityId: "iot.device.action.invoke",
                operation: "iot.device.toggle"
            )
        )

        let result = await AppSwiftSurfaceActionBridge(
            app: app,
            appsStore: appsStore,
            highRiskActionDispatcher: dispatcher,
            approvalHandler: { _, _, completion in completion(.once) }
        ).handle(action)

        XCTAssertEqual(result, .dispatched(.dispatched))
        XCTAssertEqual(dispatcher.requests.map(\.tool), ["iot.device.toggle"])
        XCTAssertEqual(dispatcher.requests.first?.descriptor.id, "iot.device.action.invoke")
        let receipts = try AppHighRiskActionAudit.read(from: appsStore.highRiskActionAuditURL(for: app))
        XCTAssertEqual(receipts.count, 1)
        XCTAssertEqual(receipts[0].capabilityId, "iot.device.action.invoke")
        XCTAssertEqual(receipts[0].action, "iot.device.toggle")
        XCTAssertEqual(receipts[0].decision, .approvedOnce)
        XCTAssertEqual(receipts[0].outcome, .dispatched)
    }
}
