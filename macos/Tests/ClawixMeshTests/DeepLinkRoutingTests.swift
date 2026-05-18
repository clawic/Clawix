import XCTest
@testable import Clawix

final class DeepLinkRoutingTests: XCTestCase {
    @MainActor
    override func setUp() {
        super.setUp()
        setenv("CLAWIX_DISABLE_BACKEND", "1", 1)
        setenv("CLAWIX_BRIDGE_DISABLE", "1", 1)
    }

    override func tearDown() {
        unsetenv("CLAWIX_DISABLE_BACKEND")
        unsetenv("CLAWIX_BRIDGE_DISABLE")
        super.tearDown()
    }

    func testParsesSessionDeepLink() throws {
        let url = try XCTUnwrap(URL(string: "clawix://session/04CD35A5-E5D0-4CFA-A332-F6B5666C584B"))
        XCTAssertEqual(ClawixDeepLink.parse(url), .session("04CD35A5-E5D0-4CFA-A332-F6B5666C584B"))
    }

    func testParsesAuthCallbackDeepLink() throws {
        let url = try XCTUnwrap(URL(string: "clawix://auth/callback/anthropic?code=abc"))
        XCTAssertEqual(ClawixDeepLink.parse(url), .authCallback(provider: "anthropic"))
    }

    func testParsesRescueDeepLink() throws {
        let url = try XCTUnwrap(URL(string: "clawix://rescue"))
        XCTAssertEqual(ClawixDeepLink.parse(url), .rescue)
    }

    @MainActor
    func testRescueSurfaceUsesDedicatedRouteWithoutDiagnosticsSideEffects() {
        let state = AppState()

        XCTAssertTrue(state.openRescueSurface(exportDiagnostics: false))

        XCTAssertEqual(state.currentRoute, .rescue)
        XCTAssertEqual(state.currentRoute.visibleRoute(isVisible: { _ in false }), .rescue)
    }

    func testRejectsNestedRescueDeepLink() throws {
        let url = try XCTUnwrap(URL(string: "clawix://rescue/extra"))
        XCTAssertNil(ClawixDeepLink.parse(url))
    }

    func testRejectsRetiredChatDeepLink() throws {
        let url = try XCTUnwrap(URL(string: "clawix://chat/04CD35A5-E5D0-4CFA-A332-F6B5666C584B"))
        XCTAssertNil(ClawixDeepLink.parse(url))
    }

    func testRejectsRetiredOAuthCallbackDeepLink() throws {
        let url = try XCTUnwrap(URL(string: "clawix://oauth-callback/anthropic?code=abc"))
        XCTAssertNil(ClawixDeepLink.parse(url))
    }

    func testIgnoresNonClawixSchemes() throws {
        let url = try XCTUnwrap(URL(string: "https://chat/04CD35A5-E5D0-4CFA-A332-F6B5666C584B"))
        XCTAssertNil(ClawixDeepLink.parse(url))
    }
}
