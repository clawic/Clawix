import XCTest
@testable import Clawix

final class ClawJSRuntimeLensSettingsPresentationTests: XCTestCase {
    func testSettingsPresentationAggregatesRuntimeLensSemantics() throws {
        let snapshot = try ClawJSRuntimeLensTestFixtures.decodedRuntimePortalSnapshot()

        let presentation = ClawJSRuntimeLensSettingsPresentation.make(
            runtime: .hermes,
            isRefreshing: false,
            loadError: nil,
            actionError: nil,
            snapshot: snapshot
        )

        XCTAssertEqual(presentation.runtimeId, "hermes")
        XCTAssertEqual(presentation.runtimeLabel, "Hermes")
        XCTAssertTrue(presentation.hasSnapshot)
        XCTAssertGreaterThan(presentation.sectionCount, 8)
        XCTAssertGreaterThan(presentation.rowCount, 20)
        XCTAssertTrue(presentation.sections.map(\.id).contains("runtime"))
        XCTAssertTrue(presentation.sections.map(\.id).contains("support-audit"))
        XCTAssertTrue(presentation.sections.map(\.id).contains("session-actions"))
        XCTAssertTrue(presentation.sections.map(\.id).contains("commands"))
        XCTAssertTrue(presentation.sections.map(\.id).contains("domains"))
        XCTAssertTrue(presentation.sections.map(\.id).contains("support-contracts"))
        XCTAssertTrue(presentation.sections.map(\.id).contains("inventory"))
        XCTAssertEqual(presentation.runtimeSummary?.runtimeId, "example")
        XCTAssertEqual(presentation.domainPresentation?.domainCount, ClawJSRuntimeLensSnapshot.canonicalDomains.count)
        XCTAssertTrue(presentation.validationAccessibilityLabel.contains("Runtime lens validation"))

        let supportAudit = try XCTUnwrap(presentation.sections.first { $0.id == "support-audit" })
        XCTAssertTrue(supportAudit.accessibilityLabel.contains("Runtime support audit"))
        XCTAssertTrue(supportAudit.rows.first?.pills.map(\.tone).contains(.warning) == true)

        let reentry = try XCTUnwrap(presentation.sections.first { $0.id == "evidence-reentry" })
        XCTAssertEqual(reentry.rows.first { $0.id == "example.channels.live_evidence" }?.value, "claw runtime example domain channels --json")
        XCTAssertTrue(reentry.rows.first { $0.id == "example.channels.live_evidence" }?.detailLines.contains("redacted_values_only_in_commands_outputs_and_evidence") == true)
        XCTAssertTrue(reentry.rows.first { $0.id == "example.sessions.create.action_contract" }?.detailLines.contains("blocked_until_approved_production_transport_lifecycle_policy_and_non_loopback_endpoint_approval") == true)

        let sessionActions = try XCTUnwrap(presentation.sections.first { $0.id == "session-actions" })
        XCTAssertTrue(sessionActions.accessibilityLabel.contains("Runtime session actions"))
        XCTAssertTrue(sessionActions.rows.contains { $0.pills.contains { $0.label == "would write" } })

        let inventory = try XCTUnwrap(presentation.sections.first { $0.id == "inventory" })
        XCTAssertTrue(inventory.accessibilityLabel.contains("Runtime inventory"))
        XCTAssertTrue(inventory.rows.contains { $0.label == "sessions" || $0.label == "Sessions" })
    }

    func testSettingsPresentationKeepsViewStateWhenSnapshotIsMissing() {
        let presentation = ClawJSRuntimeLensSettingsPresentation.make(
            runtime: .openclaw,
            isRefreshing: true,
            loadError: " portal unavailable ",
            actionError: " overlay failed ",
            snapshot: nil
        )

        XCTAssertEqual(presentation.runtimeId, "openclaw")
        XCTAssertFalse(presentation.hasSnapshot)
        XCTAssertEqual(presentation.viewState.rowCount, 3)
        XCTAssertEqual(presentation.sections.map(\.id), ["view-state"])
        XCTAssertEqual(presentation.sections.first?.rows.map(\.label), [
            "refreshing",
            "load_error",
            "action_error"
        ])
        XCTAssertTrue(presentation.validationAccessibilityLabel.contains("Runtime lens view state"))
    }
}
