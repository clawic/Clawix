import XCTest
@testable import Clawix

class AppCustomSurfaceCapabilityTestCase: XCTestCase {
    func makeDefaults() throws -> UserDefaults {
        let suite = "AppCustomSurfaceCapabilityTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func makeResource(
        id: String,
        kind: String,
        locator: AppResourceLocator,
        label: String? = nil
    ) -> AppResourceRecord {
        AppResourceRecord(
            schemaVersion: 1,
            id: id,
            kind: kind,
            status: "active",
            locator: locator,
            scope: [:],
            label: label,
            fingerprint: nil,
            bookmark: nil,
            fileIdentity: nil,
            createdAt: "2026-05-19T00:00:00Z",
            updatedAt: "2026-05-19T00:00:00Z",
            lastSeenAt: nil,
            missingSince: nil
        )
    }

    func writeResources(_ resources: [AppResourceRecord], to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let state = AppResourceRegistryState(
            schemaVersion: 1,
            resources: resources,
            updatedAt: "2026-05-19T00:00:00Z"
        )
        let data = try JSONEncoder().encode(state)
        try data.write(to: directory.appendingPathComponent(AppResourceRegistryStore.stateFileName))
    }

    func makeCollection(_ name: String) -> DBCollection {
        DBCollection(
            namespaceId: "clawix-local",
            name: name,
            displayName: name.capitalized,
            fields: [
                DBFieldDefinition(name: "title", type: .text, required: true, options: nil, relation: nil),
                DBFieldDefinition(name: "status", type: .select, required: false, options: nil, relation: nil)
            ],
            indexes: [],
            builtin: true,
            protected: false,
            coreFieldNames: ["title", "status"],
            createdAt: "2026-05-20T00:00:00Z",
            updatedAt: "2026-05-20T00:00:00Z"
        )
    }

    func makeDBRecord(id: String, title: String, status: String) -> DBRecord {
        DBRecord(
            id: id,
            createdAt: "2026-05-20T00:00:00Z",
            updatedAt: "2026-05-20T00:00:00Z",
            data: [
                "title": .string(title),
                "status": .string(status)
            ]
        )
    }

    func makeSwiftRunnerLaunch(
        result: AppSwiftSurfaceRunnerResult
    ) throws -> (launch: AppSwiftSurfaceRunnerLaunch, result: AppSwiftSurfaceRunnerResult) {
        let app = AppRecord(
            slug: "swift-dashboard",
            name: "Swift Dashboard",
            declaredCapabilities: ["search.query"],
            surfaceKind: .swiftDeclarative
        )
        let manifest = AppSwiftSurfaceManifest(
            root: AppSwiftSurfaceNode(
                kind: .button,
                text: "Search",
                action: AppSwiftSurfaceAction(
                    invocation: .sdkRead,
                    capabilityId: "search.query",
                    operation: "search.query"
                )
            ),
            requestedCapabilities: ["search.query"]
        )
        let plan = try AppSwiftSurfaceContract.runnerPlan(
            app: app,
            manifest: manifest,
            manifestPath: "/tmp/swift-dashboard/surface.json"
        )
        return (
            AppSwiftSurfaceRunnerLaunch(
                plan: plan,
                executablePath: "/tmp/clawix-swift-surface-runner",
                timeoutSeconds: 3
            ),
            result
        )
    }

    func makeCancellableSwiftRunnerFixture() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawix-swift-runner-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("runner.sh")
        try """
        #!/bin/sh
        sleep 5
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return executable
    }
}

final class AppCustomSurfaceFakeIoTClient: IoTClienting, @unchecked Sendable {
    let origin = URL(string: "http://127.0.0.1:1")!
    var bearerToken: String?
    var onRunAction: (IoTActionRequest, String?) async throws -> IoTActionResult = { _, _ in
        makeActionResult()
    }

    func health() async -> Bool { true }

    func listTools() async throws -> RemoteToolCatalog {
        RemoteToolCatalog(generatedAt: "2026-05-20T00:00:00Z", tools: [])
    }

    func invokeTool(id: String, arguments: [String: Any]) async throws -> RemoteToolInvocationResult {
        RemoteToolInvocationResult(ok: true, value: ToolJSONValue([String: Any]()), error: nil, invocationId: id, durationMs: 1)
    }

    func listHomes() async throws -> [HomeRecord] { [] }
    func listDevices(homeId: String?) async throws -> [IoTDeviceRecord] { [] }
    func listAreas(homeId: String?) async throws -> [AreaRecord] { [] }
    func listScenes(homeId: String?) async throws -> [SceneRecord] { [] }
    func listAutomations(homeId: String?) async throws -> [AutomationRecord] { [] }
    func listApprovals(homeId: String?) async throws -> [ApprovalRecord] { [] }

    func runAction(_ request: IoTActionRequest, homeId: String?) async throws -> IoTActionResult {
        try await onRunAction(request, homeId)
    }

    func activateScene(sceneId: String, homeId: String?) async throws -> IoTActionResult {
        Self.makeActionResult()
    }

    func setAutomationEnabled(automationId: String, enabled: Bool, homeId: String?) async throws -> AutomationRecord {
        AutomationRecord(id: automationId, homeId: homeId ?? "home", label: automationId, enabled: enabled, trigger: ToolJSONValue([String: Any]()), conditions: [], actions: [])
    }

    func runAutomation(automationId: String, homeId: String?) async throws -> IoTActionResult {
        Self.makeActionResult()
    }

    func approveApproval(approvalId: String, homeId: String?) async throws -> IoTActionResult {
        Self.makeActionResult()
    }

    func denyApproval(approvalId: String, homeId: String?) async throws -> ApprovalRecord {
        ApprovalRecord(
            id: approvalId,
            homeId: homeId ?? "home",
            status: "denied",
            reason: "Denied",
            action: IoTActionRequest(homeId: nil, selector: nil, area: nil, family: nil, capability: nil, action: "noop", value: nil, targets: nil),
            createdAt: "2026-05-20T00:00:00Z",
            updatedAt: "2026-05-20T00:00:00Z"
        )
    }

    func addDevice(input: IoTClient.AddDeviceInput) async throws -> IoTDeviceRecord {
        IoTDeviceRecord(
            id: input.label ?? "device",
            homeId: input.homeId ?? "home",
            areaId: nil,
            label: input.label ?? "Device",
            aliases: [],
            kind: .switchKind,
            risk: .caution,
            connectorId: "connector",
            targetRef: input.targetRef ?? "target",
            metadata: nil,
            capabilities: []
        )
    }

    func removeDevice(deviceId: String, homeId: String?) async throws {}
    func startDiscovery(timeoutMs: Int?) async throws {}
    func stopDiscovery() async throws {}

    static func makeActionResult(status: String = "ok") -> IoTActionResult {
        IoTActionResult(
            status: status,
            homeId: "home",
            decision: "executed",
            reasons: [],
            updatedAt: "2026-05-20T00:00:00Z",
            targets: [],
            capabilityUpdates: [],
            approvalId: nil
        )
    }
}

final class AppCustomSurfaceFakeDatabaseClient: DatabaseClienting {
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
            createdAt: "2026-05-20T00:00:00Z",
            updatedAt: "2026-05-20T00:00:00Z"
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
            createdAt: "2026-05-20T00:00:00Z",
            updatedAt: "2026-05-20T00:00:00Z"
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
        listRecordsCallCount += 1
        return try await onListRecords(namespaceId, collection, filter, sort, limit, offset)
    }

    func createRecord(namespaceId: String, collection: String, data: [String: DBJSON]) async throws -> DBRecord {
        DBRecord(id: "created", createdAt: "2026-05-20T00:00:00Z", updatedAt: "2026-05-20T00:00:00Z", data: data)
    }

    func updateRecord(namespaceId: String, collection: String, id: String, data: [String: DBJSON]) async throws -> DBRecord {
        DBRecord(id: id, createdAt: "2026-05-20T00:00:00Z", updatedAt: "2026-05-20T00:00:00Z", data: data)
    }

    func deleteRecord(namespaceId: String, collection: String, id: String) async throws -> Bool { true }

    func downloadFile(fileId: String) async throws -> Data { Data() }

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
            createdAt: "2026-05-20T00:00:00Z",
            downloadPath: "/files/file-1"
        )
    }
}

struct RecordingSwiftRunnerExecutor: AppSwiftSurfaceRunnerExecuting {
    let result: AppSwiftSurfaceRunnerResult

    func run(_ launch: AppSwiftSurfaceRunnerLaunch) -> AppSwiftSurfaceRunnerResult {
        result
    }
}

@MainActor
final class RecordingSwiftSurfaceActionDispatcher: AppHighRiskActionDispatcher {
    let result: AppHighRiskActionDispatchResult
    private(set) var requests: [AppHighRiskActionDispatchRequest] = []

    init(result: AppHighRiskActionDispatchResult) {
        self.result = result
    }

    func dispatch(_ request: AppHighRiskActionDispatchRequest) async -> AppHighRiskActionDispatchResult {
        requests.append(request)
        return result
    }
}
