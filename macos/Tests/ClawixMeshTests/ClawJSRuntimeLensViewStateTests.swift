import XCTest
@testable import Clawix

final class ClawJSRuntimeLensViewStateTests: XCTestCase {
    func testRuntimeLensRefreshPlanScopesToSelectedRuntimeOnly() {
        let plan = ClawJSRuntimeLensRefreshPlan.scoped(to: .hermes)

        XCTAssertEqual(plan.runtimes, [.hermes])
        XCTAssertFalse(plan.runtimes.contains(.openclaw))

        let viewStatePresentation = ClawJSRuntimeLensViewStatePresentation.make(
            runtime: .hermes,
            isRefreshing: false,
            loadError: nil,
            actionError: nil,
            hasSnapshot: false
        )
        XCTAssertEqual(viewStatePresentation.runtimeId, "hermes")
        XCTAssertEqual(viewStatePresentation.runtimeLabel, "Hermes")
        XCTAssertEqual(viewStatePresentation.rowCount, 1)
        XCTAssertEqual(viewStatePresentation.rows.first?.kind, "empty")
        XCTAssertEqual(viewStatePresentation.rows.first?.message, "Hermes snapshot pending")
        XCTAssertTrue(viewStatePresentation.accessibilityLabel.contains("snapshot false"))

        let errorStatePresentation = ClawJSRuntimeLensViewStatePresentation.make(
            runtime: .openclaw,
            isRefreshing: true,
            loadError: " portal unavailable ",
            actionError: "local overlay failed",
            hasSnapshot: true
        )
        XCTAssertEqual(errorStatePresentation.rowCount, 3)
        XCTAssertEqual(errorStatePresentation.rows.map(\.kind), ["refreshing", "load_error", "action_error"])
        XCTAssertEqual(errorStatePresentation.rows.first { $0.kind == "load_error" }?.message, "portal unavailable")
        XCTAssertEqual(errorStatePresentation.rows.first { $0.kind == "action_error" }?.severity, "warning")
        XCTAssertTrue(errorStatePresentation.hasLoadError)
        XCTAssertTrue(errorStatePresentation.hasActionError)
        XCTAssertTrue(errorStatePresentation.accessibilityLabel.contains("Runtime lens view state"))
    }

    func testRuntimeLensStatusToneKeepsBlockedAndLocalStateSemanticsCentralized() {
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.sessionActionStatus("implemented"), .success)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.sessionActionStatus("local_overlay_only"), .info)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.sessionActionStatus("blocked"), .warning)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.sessionActionDisposition("would write"), .warning)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.commandDisposition("blocked write"), .warning)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.commandDisposition("no write"), .muted)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.overlayConflictStatus("native_and_local"), .success)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.overlayConflictStatus("local_only"), .warning)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.closureStatus("direct_blocker"), .danger)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.closureStatus("external_pending"), .warning)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.evidenceReentryStatus("approval_required"), .warning)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.ecosystemStage("native_parity"), .success)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.ecosystemStage("dev_only"), .warning)
        XCTAssertEqual(
            ClawJSRuntimeLensStatusTone.runtimeDomainStatus(status: "ready", supported: true),
            .success
        )
        XCTAssertEqual(
            ClawJSRuntimeLensStatusTone.runtimeDomainStatus(status: "unknown", supported: false),
            .muted
        )
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.supportClaim("operable"), .success)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.supportClaim("blocked"), .muted)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.evidenceBlockerClass("external_pending"), .warning)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.evidenceBlockerClass("pre_existing_dirty"), .muted)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.resourceStatus("configured"), .success)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.resourceStatus("failed"), .danger)
    }
}
