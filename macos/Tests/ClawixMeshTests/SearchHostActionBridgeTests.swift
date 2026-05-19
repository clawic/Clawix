import ClawHostKit
import XCTest
@testable import Clawix

@MainActor
final class SearchHostActionBridgeTests: XCTestCase {
    func testSearchHostActionPlanMapsToNativeMacWireRequest() throws {
        let host = NativeMacActionWireHost(
            hostId: "host_test",
            bundleId: "com.clawix.app",
            signingIdentity: "PLACEHOLDER_SIGNING_IDENTITY",
            teamId: "TEAMID",
            appVariant: "debug",
            appVersion: "1.0"
        )

        let requestData = try SearchHostActionBridge.nativeRequestData(
            from: Self.searchPlanJSON(dryRun: true, approved: false, commandAction: "plan"),
            host: host
        )
        let planData = try NativeMacActionWire.planJSON(for: requestData)
        let plan = try JSONDecoder().decode(NativeMacActionWirePlan.self, from: planData)

        XCTAssertEqual(plan.schemaVersion, 1)
        XCTAssertEqual(plan.requestId, "searchreq_shortcut_daily_plan")
        XCTAssertEqual(plan.capabilityId, "mac.shortcut.run")
        XCTAssertEqual(plan.actor.kind, "agent")
        XCTAssertEqual(plan.actor.id, "agent:codex")
        XCTAssertEqual(plan.host.bundleId, "com.clawix.app")
        XCTAssertEqual(plan.resolvedTarget?.kind, "shortcut")
        XCTAssertEqual(plan.resolvedTarget?.name, "Daily Plan")
        XCTAssertEqual(plan.requiredApprovals.first?.reason, "Run native Shortcut from Search result")
        XCTAssertTrue(plan.executable)
    }

    func testApprovedSearchHostActionCanEvaluateThroughNativeMacWire() throws {
        let host = NativeMacActionWireHost(hostId: "host_test", bundleId: "com.clawix.app")
        let requestData = try SearchHostActionBridge.nativeRequestData(
            from: Self.searchPlanJSON(dryRun: false, approved: true, commandAction: "execute"),
            host: host
        )
        let runner = RecordingMacActionRunner()
        let evaluationData = try NativeMacActionWire.evaluateJSON(for: requestData, runner: runner)
        let evaluation = try JSONDecoder().decode(NativeMacActionWireEvaluation.self, from: evaluationData)

        XCTAssertEqual(evaluation.decision, "allow")
        XCTAssertEqual(evaluation.capabilityId, "mac.shortcut.run")
        XCTAssertEqual(evaluation.receipt?.result, "ok")
        XCTAssertEqual(runner.processCalls, [
            RecordingMacActionRunner.ProcessCall(executable: "/usr/bin/shortcuts", arguments: ["run", "Daily Plan"]),
        ])
    }

    func testSearchHostActionBridgeFailsClosedWithoutHostRequest() throws {
        let data = #"{"id":"search-action:test","resultId":"native.system:test","actionId":"run"}"#.data(using: .utf8)!
        XCTAssertThrowsError(try SearchHostActionBridge.nativeRequest(
            from: data,
            host: NativeMacActionWireHost(hostId: "host_test", bundleId: "com.clawix.app")
        )) { error in
            XCTAssertEqual(error as? SearchHostActionBridgeError, .missingHostRequest)
        }
    }

    private static func searchPlanJSON(dryRun: Bool, approved: Bool, commandAction: String) -> Data {
        """
        {
          "id": "search-action:native.system:shortcut:daily-plan:run",
          "resultId": "native.system:shortcut:daily-plan",
          "actionId": "run",
          "hostRequest": {
            "system": "mac-control",
            "schemaVersion": 1,
            "requestId": "searchreq_shortcut_daily_plan",
            "capabilityId": "mac.shortcut.run",
            "actor": {
              "kind": "agent",
              "id": "agent:codex",
              "role": "agent"
            },
            "target": {
              "kind": "shortcut",
              "name": "Daily Plan",
              "selector": {
                "source": "native.system"
              }
            },
            "arguments": {
              "name": "Daily Plan",
              "resultId": "native.system:shortcut:daily-plan",
              "actionId": "run",
              "source": "native.system",
              "domain": "native"
            },
            "dryRun": \(dryRun),
            "reason": "Run native Shortcut from Search result",
            "approved": \(approved),
            "hostApprovalId": "approval_native_shortcut",
            "command": {
              "resource": "mac",
              "action": "\(commandAction)",
              "requestJsonFlag": "request-json"
            }
          }
        }
        """.data(using: .utf8)!
    }
}
