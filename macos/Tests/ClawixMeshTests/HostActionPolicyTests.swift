import XCTest
@testable import Clawix

final class HostActionPolicyTests: XCTestCase {
    func testUserInitiatedActionsAreAuditedAndAllowedByDefault() throws {
        let defaults = try makeDefaults()
        let auditURL = temporaryAuditURL()

        let result = HostActionPolicy.authorize(
            surface: .screenTools,
            action: "captureArea",
            origin: .userInterface,
            defaults: defaults,
            auditURL: auditURL,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertTrue(result.allowed)
        let events = try readAuditEvents(auditURL)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].surface, .screenTools)
        XCTAssertEqual(events[0].action, "captureArea")
        XCTAssertEqual(events[0].origin, .userInterface)
        XCTAssertEqual(events[0].approval, .alwaysAsk)
        XCTAssertEqual(events[0].outcome, "allowed")
        XCTAssertEqual(events[0].schemaVersion, HostActionPolicy.schemaVersion)
        XCTAssertEqual(events[0].surfaceId, "screen-tools")
        XCTAssertEqual(events[0].capabilityId, "screen-tools.captureArea")
        XCTAssertEqual(events[0].risk, .high)
        XCTAssertEqual(events[0].decision, "allow")
        XCTAssertTrue(events[0].planId.hasPrefix("gate_plan_"))
        XCTAssertTrue(events[0].auditId.hasPrefix("gate_audit_"))
        XCTAssertTrue(events[0].receiptId?.hasPrefix("gate_receipt_") == true)
        XCTAssertEqual(events[0].rollback.level, "best_effort")
        XCTAssertEqual(events[0].redaction.policy, "host_action_gate_v1")
    }

    func testAgentActionsRequireExplicitApprovalByDefault() throws {
        let defaults = try makeDefaults()
        let auditURL = temporaryAuditURL()

        let result = HostActionPolicy.authorize(
            surface: .macUtilities,
            action: "clearClipboard",
            origin: .agent,
            defaults: defaults,
            auditURL: auditURL
        )

        XCTAssertFalse(result.allowed)
        XCTAssertEqual(result.outcome, "requiresApproval")
        XCTAssertEqual(result.reason, "Requires explicit host approval.")
        let events = try readAuditEvents(auditURL)
        XCTAssertEqual(events.first?.surface, .macUtilities)
        XCTAssertEqual(events.first?.outcome, "requiresApproval")
        XCTAssertEqual(events.first?.surfaceId, "mac-utilities")
        XCTAssertEqual(events.first?.capabilityId, "mac-utilities.clearClipboard")
        XCTAssertEqual(events.first?.risk, .high)
        XCTAssertEqual(events.first?.decision, "requires_approval")
        XCTAssertNil(events.first?.receiptId)
        XCTAssertEqual(events.first?.rollback.refs.last, "no_execution_receipt")
    }

    func testAlwaysBlockPolicyBlocksEvenUserInitiatedActions() throws {
        let defaults = try makeDefaults()
        let auditURL = temporaryAuditURL()
        defaults.set(HostActionPolicy.Approval.alwaysBlock.rawValue, forKey: HostActionSurface.macUtilities.approvalKey)

        let result = HostActionPolicy.authorize(
            surface: .macUtilities,
            action: "sleepDisplays",
            origin: .userInterface,
            defaults: defaults,
            auditURL: auditURL
        )

        XCTAssertFalse(result.allowed)
        XCTAssertEqual(result.outcome, "blocked")
        let events = try readAuditEvents(auditURL)
        XCTAssertEqual(events.first?.approval, .alwaysBlock)
    }

    func testApprovedOverrideAllowsAgentWhenPolicyAsks() throws {
        let defaults = try makeDefaults()
        let auditURL = temporaryAuditURL()

        let result = HostActionPolicy.authorize(
            surface: .macControl,
            action: "mac.shortcut.run",
            origin: .agent,
            defaults: defaults,
            auditURL: auditURL,
            approvedOverride: true
        )

        XCTAssertTrue(result.allowed)
        XCTAssertEqual(result.outcome, "approved")
        XCTAssertEqual(result.risk, .high)
        XCTAssertNotNil(result.receiptId)
        let events = try readAuditEvents(auditURL)
        XCTAssertEqual(events.first?.surface, .macControl)
        XCTAssertEqual(events.first?.outcome, "approved")
        XCTAssertEqual(events.first?.surfaceId, "mac-control")
        XCTAssertEqual(events.first?.decision, "allow")
        XCTAssertEqual(events.first?.receiptId, result.receiptId)
        XCTAssertEqual(events.first?.planId, result.planId)
    }

    func testMacUtilitiesLowRiskActionsStillEmitGateCompatibleAudit() throws {
        let defaults = try makeDefaults()
        let auditURL = temporaryAuditURL()

        let result = HostActionPolicy.authorize(
            surface: .macUtilities,
            action: "openFinder",
            origin: .userInterface,
            defaults: defaults,
            auditURL: auditURL
        )

        XCTAssertTrue(result.allowed)
        XCTAssertEqual(result.risk, .low)
        let event = try XCTUnwrap(readAuditEvents(auditURL).first)
        XCTAssertEqual(event.schemaVersion, 1)
        XCTAssertEqual(event.surfaceId, "mac-utilities")
        XCTAssertEqual(event.risk, .low)
        XCTAssertEqual(event.rollback.level, "none")
        XCTAssertTrue(event.redaction.fields.contains("processOutput"))
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "HostActionPolicyTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func temporaryAuditURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("host-action-policy-\(UUID().uuidString)")
            .appendingPathComponent(HostActionPolicy.auditFilename)
    }

    private func readAuditEvents(_ url: URL) throws -> [HostActionPolicy.AuditEvent] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
        return try lines.map { try decoder.decode(HostActionPolicy.AuditEvent.self, from: Data($0.utf8)) }
    }
}
