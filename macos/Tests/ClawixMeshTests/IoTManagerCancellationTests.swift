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
        await task.value
        XCTAssertTrue(manager.devices.isEmpty)
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

private final class FakeIoTClient: IoTClienting, @unchecked Sendable {
    let origin = URL(string: "http://127.0.0.1:1")!
    var bearerToken: String?
    var onListDevices: (String?) async throws -> [IoTDeviceRecord] = { _ in
        [makeDevice()]
    }

    func health() async -> Bool { true }

    func listTools() async throws -> RemoteToolCatalog {
        RemoteToolCatalog(generatedAt: "2026-05-19T00:00:00Z", tools: [])
    }

    func invokeTool(id: String, arguments: [String: Any]) async throws -> RemoteToolInvocationResult {
        RemoteToolInvocationResult(ok: true, value: ToolJSONValue([String: Any]()), error: nil, invocationId: id, durationMs: 1)
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
        makeActionResult()
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

    func startDiscovery(timeoutMs: Int?) async throws {}

    func stopDiscovery() async throws {}
}
