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

    func testSettingsPresentationShowsOfficialSnapshotRows() async throws {
        let snapshot = try await ClawJSRuntimeLensTestFixtures.hermesRuntimePortalSnapshot()

        let presentation = ClawJSRuntimeLensSettingsPresentation.make(
            runtime: .hermes,
            isRefreshing: false,
            loadError: nil,
            actionError: nil,
            snapshot: snapshot
        )
        let support = try XCTUnwrap(presentation.sections.first { $0.id == "support" })
        let details = try XCTUnwrap(support.rows.first?.detailLines)

        XCTAssertTrue(details.contains("Official snapshot: captured 2026-05-26, source snapshot 2026-05-26, sources 8"))
        XCTAssertTrue(details.contains("Drift policy: hermes_remains_dev_only_until_snapshot_total_and_write_policy_are_complete"))
        XCTAssertTrue(support.accessibilityLabel.contains("official snapshot 2026-05-26"))

        let commands = try XCTUnwrap(presentation.sections.first { $0.id == "commands" })
        let sendCommand = try XCTUnwrap(commands.rows.first {
            $0.label == "runtime hermes sessions send --session-key <id> --message <text> --confirm-runtime-write"
        })
        XCTAssertTrue(sendCommand.detailLines.contains("blocker direct_blocker"))
        XCTAssertTrue(sendCommand.detailLines.contains("native write-back blocked_until_tui_gateway_wrapper_fixture"))
        XCTAssertTrue(sendCommand.detailLines.contains("fixture required true"))
        XCTAssertTrue(sendCommand.detailLines.contains("native safe default keep_unpromoted_and_do_not_synthesize_runtime_state"))
        XCTAssertTrue(sendCommand.detailLines.contains("safe default keep_unpromoted_and_do_not_synthesize_runtime_state"))
        XCTAssertTrue(sendCommand.detailLines.contains("user visible contract non_executable_until_tui_gateway_wrapper_fixture_exists"))
        XCTAssertTrue(sendCommand.detailLines.contains("claim effect blocks_recommended_production_native_parity"))
        XCTAssertTrue(sendCommand.detailLines.contains("support resolution explicitly_product_blocked_not_a_silent_gap"))
        XCTAssertTrue(sendCommand.detailLines.contains("evidence hermes.sessions.send.action_contract"))
        XCTAssertTrue(sendCommand.detailLines.contains("required evidence tui_gateway_prompt_submit_fixture, non_destructive_fixture, confirmation_or_dry_run_policy, round_trip_native_visibility"))

        let sessionActions = try XCTUnwrap(presentation.sections.first { $0.id == "session-actions" })
        let pinAction = try XCTUnwrap(sessionActions.rows.first { $0.label == "pin" })
        XCTAssertTrue(pinAction.detailLines.contains("user visible contract local_overlay_only_until_official_runtime_pin_api_exists"))
        XCTAssertTrue(pinAction.detailLines.contains("claim effect blocks_native_write_back_parity_not_local_overlay"))

        let actionContracts = try XCTUnwrap(presentation.sections.first { $0.id == "session-action-contracts" })
        let pinContract = try XCTUnwrap(actionContracts.rows.first { $0.label == "pin" })
        XCTAssertTrue(pinContract.detailLines.contains("native write-back blocked_until_official_runtime_write_back_contract"))
        XCTAssertTrue(pinContract.detailLines.contains("safe default keep_local_overlay_and_do_not_write_runtime_pin_state"))
        XCTAssertTrue(pinContract.detailLines.contains("evidence hermes.sessions.pin.native_write_back_contract"))
        XCTAssertTrue(pinContract.detailLines.contains("user visible contract local_overlay_only_until_official_runtime_pin_api_exists"))
        XCTAssertTrue(pinContract.detailLines.contains("claim effect blocks_native_write_back_parity_not_local_overlay"))
    }
}
