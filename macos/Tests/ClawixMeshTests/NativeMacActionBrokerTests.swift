import XCTest
@testable import Clawix

@MainActor
final class NativeMacActionBrokerTests: XCTestCase {
    func testWifiConnectPlanRejectsPlaintextPasswordAndRedactsSSID() throws {
        let request = NativeMacActionRequest(
            requestId: "macreq_test_wifi_connect",
            capabilityId: "mac.wifi.connect",
            actorId: "actor_test",
            origin: .agent,
            arguments: ["ssid": "Office", "password": "not-allowed"],
            dryRun: true
        )

        let plan = try NativeMacActionBroker.plan(for: request)

        XCTAssertEqual(plan.planId, "macplan_macreq_test_wifi_connect")
        XCTAssertEqual(plan.risk, .high)
        XCTAssertTrue(plan.requiresApproval)
        XCTAssertTrue(plan.continuityBreaker)
        XCTAssertEqual(plan.revertLevel, .bestEffort)
        XCTAssertEqual(plan.blockedReason, "Plaintext Wi-Fi passwords are not accepted by the Mac Action Broker. Use a secret reference.")
        XCTAssertEqual(plan.steps.first?.preview, "Connect Wi-Fi to <ssid:6 chars>")
        XCTAssertEqual(plan.steps.first?.arguments, ["-setairportnetwork", "en0", "Office"])
    }

    func testAgentWindowCloseRequiresApprovalAndAuditsDecision() throws {
        let defaults = try makeDefaults()
        let auditURL = temporaryAuditURL()
        let request = NativeMacActionRequest(
            requestId: "macreq_test_window_close",
            capabilityId: "mac.window.close",
            actorId: "agent_test",
            origin: .agent
        )

        let receipt = NativeMacActionBroker.evaluate(
            request,
            defaults: defaults,
            auditURL: auditURL,
            runner: RecordingMacActionRunner()
        )

        XCTAssertEqual(receipt.outcome, .approvalRequired)
        XCTAssertEqual(receipt.error, "Requires explicit host approval.")
        let events = try readAuditEvents(auditURL)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].surface, .macControl)
        XCTAssertEqual(events[0].action, "mac.window.close")
        XCTAssertEqual(events[0].origin, .agent)
        XCTAssertEqual(events[0].outcome, "requiresApproval")
    }

    func testApprovedShortcutRunUsesShortcutsCLI() throws {
        let runner = RecordingMacActionRunner()
        let defaults = try makeDefaults()
        let auditURL = temporaryAuditURL()
        let request = NativeMacActionRequest(
            requestId: "macreq_test_shortcut_run",
            capabilityId: "mac.shortcut.run",
            actorId: "owner",
            origin: .userInterface,
            arguments: ["name": "Daily Plan"],
            approved: true
        )

        let receipt = NativeMacActionBroker.evaluate(request, defaults: defaults, auditURL: auditURL, runner: runner)

        XCTAssertEqual(receipt.outcome, .executed)
        XCTAssertEqual(runner.processCalls, [
            RecordingMacActionRunner.ProcessCall(executable: "/usr/bin/shortcuts", arguments: ["run", "Daily Plan"]),
        ])
        let events = try readAuditEvents(auditURL)
        XCTAssertEqual(events.first?.surface, .macControl)
        XCTAssertEqual(events.first?.action, "mac.shortcut.run")
        XCTAssertEqual(events.first?.outcome, "approved")
    }

    func testDryRunDoesNotExecuteNativeSteps() throws {
        let runner = RecordingMacActionRunner()
        let defaults = try makeDefaults()
        let request = NativeMacActionRequest(
            requestId: "macreq_test_wifi_status",
            capabilityId: "mac.wifi.status",
            actorId: "agent_test",
            origin: .agent,
            dryRun: true
        )

        let receipt = NativeMacActionBroker.evaluate(request, defaults: defaults, runner: runner)

        XCTAssertEqual(receipt.outcome, .planned)
        XCTAssertTrue(runner.processCalls.isEmpty)
        XCTAssertTrue(runner.appleScriptCalls.isEmpty)
    }

    func testWirePlanMatchesMacActionPlanContractShape() throws {
        let request = try wireRequestJSON(
            requestId: "macreq_wire_wifi_off",
            capabilityId: "mac.wifi.power.off",
            actorKind: "agent",
            arguments: ["device": "en0"],
            dryRun: true
        )

        let data = try NativeMacActionWire.planJSON(for: request)
        let plan = try JSONDecoder().decode(NativeMacActionWirePlan.self, from: data)

        XCTAssertEqual(plan.schemaVersion, 1)
        XCTAssertEqual(plan.planId, "macplan_macreq_wire_wifi_off")
        XCTAssertEqual(plan.requestId, "macreq_wire_wifi_off")
        XCTAssertEqual(plan.capabilityId, "mac.wifi.power.off")
        XCTAssertEqual(plan.risk, "critical")
        XCTAssertEqual(plan.coverageState, "executable")
        XCTAssertEqual(plan.actor.kind, "agent")
        XCTAssertEqual(plan.host.bundleId, "com.clawix.app")
        XCTAssertEqual(plan.requiredApprovals.first?.approverRoles, ["owner", "admin"])
        XCTAssertEqual(plan.rollback.level, "best_effort")
        XCTAssertEqual(plan.rollback.timerSeconds, 120)
        XCTAssertTrue(plan.executable)
    }

    func testWireEvaluationMapsNativeReceiptToClawJSResultValues() throws {
        let runner = RecordingMacActionRunner()
        let defaults = try makeDefaults()
        let request = try wireRequestJSON(
            requestId: "macreq_wire_shortcut",
            capabilityId: "mac.shortcut.run",
            actorKind: "owner_cli",
            arguments: ["name": "Daily Plan", "secretRef": "sec_shortcut_input"],
            approved: true
        )

        let data = try NativeMacActionWire.evaluateJSON(for: request, defaults: defaults, runner: runner)
        let evaluation = try JSONDecoder().decode(NativeMacActionWireEvaluation.self, from: data)

        XCTAssertEqual(evaluation.schemaVersion, 1)
        XCTAssertEqual(evaluation.decision, "allow")
        XCTAssertEqual(evaluation.capabilityId, "mac.shortcut.run")
        XCTAssertEqual(evaluation.receipt?.result, "ok")
        XCTAssertEqual(evaluation.receipt?.secretRefs, ["sec_shortcut_input"])
        XCTAssertEqual(evaluation.auditEvent?.receiptId, evaluation.receipt?.id)
        XCTAssertEqual(runner.processCalls, [
            RecordingMacActionRunner.ProcessCall(executable: "/usr/bin/shortcuts", arguments: ["run", "Daily Plan"]),
        ])
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "NativeMacActionBrokerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func temporaryAuditURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("native-mac-action-broker-\(UUID().uuidString)")
            .appendingPathComponent(HostActionPolicy.auditFilename)
    }

    private func readAuditEvents(_ url: URL) throws -> [HostActionPolicy.AuditEvent] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
        return try lines.map { try decoder.decode(HostActionPolicy.AuditEvent.self, from: Data($0.utf8)) }
    }

    private func wireRequestJSON(
        requestId: String,
        capabilityId: String,
        actorKind: String,
        arguments: [String: String],
        dryRun: Bool = false,
        approved: Bool = false
    ) throws -> Data {
        let request = NativeMacActionWireRequest(
            requestId: requestId,
            capabilityId: capabilityId,
            actor: NativeMacActionWireActor(kind: actorKind, id: "actor_test", role: "owner", assignmentId: nil, runId: nil),
            host: NativeMacActionWireHost(
                hostId: "host_test",
                bundleId: "com.clawix.app",
                signingIdentity: "PLACEHOLDER_SIGNING_IDENTITY",
                teamId: "TEAMID",
                appVariant: "debug",
                appVersion: "1.0"
            ),
            arguments: arguments.mapValues { .string($0) },
            dryRun: dryRun,
            approved: approved
        )
        return try JSONEncoder().encode(request)
    }
}

final class RecordingMacActionRunner: NativeMacActionCommandRunning {
    struct ProcessCall: Equatable {
        var executable: String
        var arguments: [String]
    }

    private(set) var processCalls: [ProcessCall] = []
    private(set) var appleScriptCalls: [String] = []

    func runProcess(_ executable: String, arguments: [String]) throws -> String {
        processCalls.append(ProcessCall(executable: executable, arguments: arguments))
        return "ok"
    }

    func runAppleScript(_ source: String) throws -> String {
        appleScriptCalls.append(source)
        return "ok"
    }
}
