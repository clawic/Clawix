import Foundation
import XCTest
@testable import Clawix

@MainActor
final class IoTManagerCancellationTests: XCTestCase {
    func testStartingSecondRefreshCancelsStaleIoTLoad() async {
        let staleStarted = expectation(description: "Stale IoT refresh started")
        let staleCancelled = expectation(description: "Stale IoT refresh cancelled")
        let freshReturned = expectation(description: "Fresh IoT refresh returned")
        let client = FakeIoTClient()
        var calls = 0
        client.onListDevices = { _ in
            calls += 1
            if calls == 1 {
                staleStarted.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    staleCancelled.fulfill()
                    throw CancellationError()
                }
                return [makeDevice(id: "stale")]
            }
            freshReturned.fulfill()
            return [makeDevice(id: "fresh")]
        }
        let manager = IoTManager(client: client, adminTokenOperation: { "token" }, attachSupervisor: false)

        let first = Task { try? await manager.refreshAll() }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task { try? await manager.refreshAll() }

        await fulfillment(of: [staleCancelled, freshReturned], timeout: 1)
        await first.value
        await second.value
        XCTAssertEqual(manager.devices.map(\.id), ["fresh"])
    }

    func testStaleIoTRefreshCannotOverwriteFreshState() async {
        let staleStarted = expectation(description: "Stale IoT refresh started")
        let staleReturned = expectation(description: "Stale IoT refresh returned")
        let freshReturned = expectation(description: "Fresh IoT refresh returned")
        let client = FakeIoTClient()
        var calls = 0
        client.onListDevices = { _ in
            calls += 1
            if calls == 1 {
                staleStarted.fulfill()
                try? await Task.sleep(nanoseconds: 100_000_000)
                staleReturned.fulfill()
                return [makeDevice(id: "stale")]
            }
            freshReturned.fulfill()
            return [makeDevice(id: "fresh")]
        }
        let manager = IoTManager(client: client, adminTokenOperation: { "token" }, attachSupervisor: false)

        let first = Task { try? await manager.refreshAll() }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task { try? await manager.refreshAll() }

        await fulfillment(of: [freshReturned, staleReturned], timeout: 1)
        await first.value
        await second.value
        XCTAssertEqual(manager.devices.map(\.id), ["fresh"])
    }

    func testCancelSurfaceWorkSuppressesInFlightIoTRefresh() async {
        let refreshStarted = expectation(description: "IoT refresh started")
        let refreshCancelled = expectation(description: "IoT refresh cancelled")
        let client = FakeIoTClient()
        client.onListDevices = { _ in
            refreshStarted.fulfill()
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                refreshCancelled.fulfill()
                throw CancellationError()
            }
            return [makeDevice(id: "stale")]
        }
        let manager = IoTManager(client: client, adminTokenOperation: { "token" }, attachSupervisor: false)

        let task = Task { try? await manager.refreshAll() }
        await fulfillment(of: [refreshStarted], timeout: 1)

        manager.cancelSurfaceWork()

        await fulfillment(of: [refreshCancelled], timeout: 1)
        _ = await task.value
        XCTAssertTrue(manager.devices.isEmpty)
    }

    func testCancelSurfaceWorkCancelsInFlightIoTActionError() async {
        let actionStarted = expectation(description: "IoT action started")
        let actionCancelled = expectation(description: "IoT action cancelled")
        let client = FakeIoTClient()
        client.onRunAction = { _, _ in
            actionStarted.fulfill()
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                actionCancelled.fulfill()
                throw CancellationError()
            }
            throw IoTTestError.serviceNotReady
        }
        let manager = IoTManager(client: client, adminTokenOperation: { "token" }, attachSupervisor: false)

        let task = Task { try? await manager.runAction(makeActionRequest(action: "turn_on")) }
        await fulfillment(of: [actionStarted], timeout: 1)

        manager.cancelSurfaceWork()

        await fulfillment(of: [actionCancelled], timeout: 1)
        _ = await task.value
        XCTAssertNil(manager.lastError)
    }

    func testCancelSurfaceWorkCancelsInFlightIoTActionRefresh() async {
        let actionStarted = expectation(description: "IoT action started")
        let actionCancelled = expectation(description: "IoT action cancelled")
        let refreshStarted = expectation(description: "IoT refresh should not start")
        refreshStarted.isInverted = true
        let client = FakeIoTClient()
        client.onRunAction = { _, _ in
            actionStarted.fulfill()
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                actionCancelled.fulfill()
                throw CancellationError()
            }
            return makeActionResult()
        }
        client.onListDevices = { _ in
            refreshStarted.fulfill()
            return [makeDevice(id: "unexpected")]
        }
        let manager = IoTManager(client: client, adminTokenOperation: { "token" }, attachSupervisor: false)

        let task = Task { try? await manager.runAction(makeActionRequest(action: "turn_on")) }
        await fulfillment(of: [actionStarted], timeout: 1)

        manager.cancelSurfaceWork()

        await fulfillment(of: [actionCancelled, refreshStarted], timeout: 1)
        _ = await task.value
        XCTAssertTrue(manager.devices.isEmpty)
        XCTAssertNil(manager.lastError)
    }

    func testCancelSurfaceWorkCancelsInFlightDiscoveryError() async {
        let discoveryStarted = expectation(description: "IoT discovery started")
        let discoveryCancelled = expectation(description: "IoT discovery cancelled")
        let client = FakeIoTClient()
        client.onStartDiscovery = { _ in
            discoveryStarted.fulfill()
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                discoveryCancelled.fulfill()
                throw CancellationError()
            }
            throw IoTTestError.serviceNotReady
        }
        let manager = IoTManager(client: client, adminTokenOperation: { "token" }, attachSupervisor: false)

        let task = Task { try? await manager.startDiscovery(timeoutMs: 100) }
        await fulfillment(of: [discoveryStarted], timeout: 1)

        manager.cancelSurfaceWork()

        await fulfillment(of: [discoveryCancelled], timeout: 1)
        await task.value
        XCTAssertNil(manager.lastError)
    }

    func testCancelSurfaceWorkCancelsInFlightProtocolToolResult() async {
        let toolStarted = expectation(description: "IoT protocol tool started")
        let toolCancelled = expectation(description: "IoT protocol tool cancelled")
        let client = FakeIoTClient()
        client.onInvokeTool = { id, _ in
            XCTAssertEqual(id, "iot.mqtt.connect")
            toolStarted.fulfill()
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                toolCancelled.fulfill()
                throw CancellationError()
            }
            return RemoteToolInvocationResult(
                ok: true,
                value: ToolJSONValue(["connected": true]),
                error: nil,
                invocationId: id,
                durationMs: 1
            )
        }
        let manager = IoTManager(client: client, adminTokenOperation: { "token" }, attachSupervisor: false)

        let task = Task { try? await manager.connectMqtt(url: "mqtt://broker", username: nil, password: nil) }
        await fulfillment(of: [toolStarted], timeout: 1)

        manager.cancelSurfaceWork()

        await fulfillment(of: [toolCancelled], timeout: 1)
        let result = await task.value
        XCTAssertNil(result)
        XCTAssertNil(manager.lastError)
    }
}

private func makeHome(id: String = "home") -> HomeRecord {
    HomeRecord(
        id: id,
        label: id,
        isDefault: true,
        createdAt: "2026-05-19T00:00:00Z"
    )
}

private func makeArea(id: String = "area") -> AreaRecord {
    AreaRecord(
        id: id,
        homeId: "home",
        label: id,
        aliases: []
    )
}

private func makeDevice(id: String = "device") -> IoTDeviceRecord {
    IoTDeviceRecord(
        id: id,
        homeId: "home",
        areaId: "area",
        label: id,
        aliases: [],
        kind: .light,
        risk: .safe,
        connectorId: "connector",
        targetRef: "\(id)-target",
        metadata: nil,
        capabilities: []
    )
}

private func makeScene(id: String = "scene") -> SceneRecord {
    SceneRecord(
        id: id,
        homeId: "home",
        label: id,
        description: nil,
        actions: []
    )
}

private func makeAutomation(id: String = "automation") -> AutomationRecord {
    AutomationRecord(
        id: id,
        homeId: "home",
        label: id,
        enabled: true,
        trigger: ToolJSONValue([String: Any]()),
        conditions: [],
        actions: []
    )
}

private func makeApproval(id: String = "approval", status: String = "pending") -> ApprovalRecord {
    ApprovalRecord(
        id: id,
        homeId: "home",
        status: status,
        reason: "safe",
        action: IoTActionRequest(
            homeId: nil,
            selector: nil,
            area: nil,
            family: nil,
            capability: nil,
            action: "turn_on",
            value: nil,
            targets: nil
        ),
        createdAt: "2026-05-19T00:00:00Z",
        updatedAt: "2026-05-19T00:00:00Z"
    )
}

private func makeActionRequest(action: String = "turn_on") -> IoTActionRequest {
    IoTActionRequest(
        homeId: nil,
        selector: nil,
        area: nil,
        family: nil,
        capability: nil,
        action: action,
        value: nil,
        targets: nil
    )
}

private func makeActionResult(status: String = "ok") -> IoTActionResult {
    IoTActionResult(
        status: status,
        homeId: "home",
        decision: "allowed",
        reasons: [],
        updatedAt: "2026-05-19T00:00:00Z",
        targets: [],
        capabilityUpdates: [],
        approvalId: nil
    )
}

private enum IoTTestError: Error {
    case serviceNotReady
}

private final class FakeIoTClient: IoTClienting, @unchecked Sendable {
    let origin = URL(string: "http://127.0.0.1:1")!
    var bearerToken: String?
    var onListDevices: (String?) async throws -> [IoTDeviceRecord] = { _ in
        [makeDevice()]
    }
    var onRunAction: (IoTActionRequest, String?) async throws -> IoTActionResult = { _, _ in
        makeActionResult()
    }
    var onStartDiscovery: (Int?) async throws -> Void = { _ in }
    var onInvokeTool: (String, [String: Any]) async throws -> RemoteToolInvocationResult = { id, _ in
        RemoteToolInvocationResult(ok: true, value: ToolJSONValue([String: Any]()), error: nil, invocationId: id, durationMs: 1)
    }

    func health() async -> Bool { true }

    func listTools() async throws -> RemoteToolCatalog {
        RemoteToolCatalog(generatedAt: "2026-05-19T00:00:00Z", tools: [])
    }

    func invokeTool(id: String, arguments: [String: Any]) async throws -> RemoteToolInvocationResult {
        try await onInvokeTool(id, arguments)
    }

    func listHomes() async throws -> [HomeRecord] {
        [makeHome()]
    }

    func listDevices(homeId: String?) async throws -> [IoTDeviceRecord] {
        try await onListDevices(homeId)
    }

    func listAreas(homeId: String?) async throws -> [AreaRecord] {
        [makeArea()]
    }

    func listScenes(homeId: String?) async throws -> [SceneRecord] {
        [makeScene()]
    }

    func listAutomations(homeId: String?) async throws -> [AutomationRecord] {
        [makeAutomation()]
    }

    func listApprovals(homeId: String?) async throws -> [ApprovalRecord] {
        [makeApproval()]
    }

    func runAction(_ request: IoTActionRequest, homeId: String?) async throws -> IoTActionResult {
        try await onRunAction(request, homeId)
    }

    func activateScene(sceneId: String, homeId: String?) async throws -> IoTActionResult {
        makeActionResult()
    }

    func setAutomationEnabled(automationId: String, enabled: Bool, homeId: String?) async throws -> AutomationRecord {
        makeAutomation(id: automationId)
    }

    func runAutomation(automationId: String, homeId: String?) async throws -> IoTActionResult {
        makeActionResult()
    }

    func approveApproval(approvalId: String, homeId: String?) async throws -> IoTActionResult {
        makeActionResult()
    }

    func denyApproval(approvalId: String, homeId: String?) async throws -> ApprovalRecord {
        makeApproval(id: approvalId, status: "denied")
    }

    func addDevice(input: IoTClient.AddDeviceInput) async throws -> IoTDeviceRecord {
        makeDevice(id: input.label ?? "added")
    }

    func removeDevice(deviceId: String, homeId: String?) async throws {}

    func startDiscovery(timeoutMs: Int?) async throws {
        try await onStartDiscovery(timeoutMs)
    }

    func stopDiscovery() async throws {}
}
