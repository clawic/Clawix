import XCTest
@testable import Clawix

@MainActor
final class RescueChatFallbackTests: XCTestCase {
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

    func testMainComposerStaysResponsiveWhenRescueRuntimeCannotChat() {
        let state = AppState()
        state.chats = []
        state.currentRoute = .home
        state.daemonBridgeClient = nil
        state.clawJSSessionsCanonicalActive = false
        state.rescueDecision = RescueSurvivalPolicy.evaluate(
            signals: [.bridgeRuntimeDown],
            availableRuntimeCount: 0
        )
        state.composer.text = "Can you repair this?"

        state.sendMessage()

        let chat = try! XCTUnwrap(state.chats.first)
        XCTAssertEqual(chat.messages.count, 2)
        XCTAssertEqual(chat.messages[0].role, .user)
        XCTAssertEqual(chat.messages[0].content, "Can you repair this?")
        XCTAssertEqual(chat.messages[1].role, .assistant)
        XCTAssertTrue(chat.messages[1].content.contains("Diagnostics are available"))
        XCTAssertFalse(chat.hasActiveTurn)
        XCTAssertEqual(state.composer.text, "")
    }
}
