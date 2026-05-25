import XCTest
@testable import Clawix

final class ClawJSRuntimeLensSessionActionRunPresentationTests: XCTestCase {
    func testHermesSendCanCheckGateOnlyAfterRequiredInput() {
        let missingInput = ClawJSRuntimeLensSessionActionRunPresentation.make(
            runtime: .hermes,
            action: "send",
            sessionId: "sqlite-session",
            message: "",
            title: "",
            gatewayURL: "",
            inFlightKeys: []
        )

        XCTAssertTrue(missingInput.supportsGatewayFixture)
        XCTAssertTrue(missingInput.requiresSession)
        XCTAssertTrue(missingInput.requiresMessage)
        XCTAssertFalse(missingInput.hasRequiredInput)
        XCTAssertFalse(missingInput.canCheckGate)
        XCTAssertFalse(missingInput.canRunConfirmedFixture)
        XCTAssertEqual(missingInput.disabledReason, "missing required input")

        let readyForGateCheck = ClawJSRuntimeLensSessionActionRunPresentation.make(
            runtime: .hermes,
            action: "send",
            sessionId: "sqlite-session",
            message: "fixture hello",
            title: "",
            gatewayURL: "",
            inFlightKeys: []
        )

        XCTAssertTrue(readyForGateCheck.canCheckGate)
        XCTAssertFalse(readyForGateCheck.canRunConfirmedFixture)
        XCTAssertEqual(readyForGateCheck.disabledReason, "confirmed run requires loopback gateway URL")
        XCTAssertTrue(readyForGateCheck.accessibilityLabel.contains("can check gate true"))
    }

    func testHermesConfirmedFixtureRunRequiresLoopbackGateway() {
        let remoteGateway = ClawJSRuntimeLensSessionActionRunPresentation.make(
            runtime: .hermes,
            action: "inject",
            sessionId: "sqlite-session",
            message: "steer this",
            title: "",
            gatewayURL: "https://example.com",
            inFlightKeys: []
        )

        XCTAssertTrue(remoteGateway.canCheckGate)
        XCTAssertFalse(remoteGateway.hasLoopbackGateway)
        XCTAssertFalse(remoteGateway.canRunConfirmedFixture)

        let loopbackGateway = ClawJSRuntimeLensSessionActionRunPresentation.make(
            runtime: .hermes,
            action: "inject",
            sessionId: "sqlite-session",
            message: "steer this",
            title: "",
            gatewayURL: "http://127.0.0.1:18789",
            inFlightKeys: []
        )

        XCTAssertTrue(loopbackGateway.hasLoopbackGateway)
        XCTAssertTrue(loopbackGateway.canRunConfirmedFixture)
        XCTAssertNil(loopbackGateway.disabledReason)
        XCTAssertEqual(loopbackGateway.actionKey, "hermes::session-action::inject")
        XCTAssertEqual(loopbackGateway.accessibilityIdentifier, "runtime-lens-session-action-run-hermes-inject")
    }

    func testHermesCreateUsesTitleWithoutSessionOrMessage() {
        let create = ClawJSRuntimeLensSessionActionRunPresentation.make(
            runtime: .hermes,
            action: "create",
            sessionId: "",
            message: "",
            title: "Fixture Session",
            gatewayURL: "http://localhost:18789",
            inFlightKeys: []
        )

        XCTAssertFalse(create.requiresSession)
        XCTAssertFalse(create.requiresMessage)
        XCTAssertTrue(create.requiresTitle)
        XCTAssertTrue(create.canCheckGate)
        XCTAssertTrue(create.canRunConfirmedFixture)
    }

    func testNonHermesRuntimeAndInFlightActionsAreDisabled() {
        let openClaw = ClawJSRuntimeLensSessionActionRunPresentation.make(
            runtime: .openclaw,
            action: "send",
            sessionId: "runtime-session",
            message: "hello",
            title: "",
            gatewayURL: "http://127.0.0.1:18789",
            inFlightKeys: []
        )

        XCTAssertFalse(openClaw.supportsGatewayFixture)
        XCTAssertFalse(openClaw.canCheckGate)
        XCTAssertFalse(openClaw.canRunConfirmedFixture)
        XCTAssertEqual(openClaw.disabledReason, "no fixture-backed gateway action")

        let inFlight = ClawJSRuntimeLensSessionActionRunPresentation.make(
            runtime: .hermes,
            action: "abort",
            sessionId: "runtime-session",
            message: "",
            title: "",
            gatewayURL: "http://[::1]:18789",
            inFlightKeys: ["hermes::session-action::abort"]
        )

        XCTAssertTrue(inFlight.hasLoopbackGateway)
        XCTAssertTrue(inFlight.inFlight)
        XCTAssertFalse(inFlight.canCheckGate)
        XCTAssertFalse(inFlight.canRunConfirmedFixture)
        XCTAssertEqual(inFlight.disabledReason, "action in flight")
    }
}
