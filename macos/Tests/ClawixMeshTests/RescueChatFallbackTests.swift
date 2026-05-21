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
        let messages = try! XCTUnwrap(state.chatStore.transcript(for: chat.id)?.messages)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, .user)
        XCTAssertEqual(messages[0].content, "Can you repair this?")
        XCTAssertEqual(messages[1].role, .assistant)
        XCTAssertTrue(messages[1].content.contains("Diagnostics are available"))
        XCTAssertEqual(chat.messages.count, 0)
        XCTAssertFalse(chat.hasActiveTurn)
        XCTAssertEqual(state.composer.text, "")
    }

    func testMainComposerDoesNotSilentlySwallowSendWhenBridgeIsNotReady() async {
        let state = AppState()
        state.chats = []
        state.currentRoute = .home
        state.clawJSSessionsCanonicalActive = false
        state.rescueDecision = RescueSurvivalPolicy.evaluate(
            signals: [],
            availableRuntimeCount: 1
        )
        state.daemonBridgeClient = DaemonBridgeClient(
            appState: state,
            pairing: state.sharedBridgePairingService()
        )
        state.composer.text = "reply OK"

        state.sendMessage()
        try? await Task.sleep(nanoseconds: 100_000_000)

        let chat = try! XCTUnwrap(state.chats.first)
        let messages = try! XCTUnwrap(state.chatStore.transcript(for: chat.id)?.messages)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, .user)
        XCTAssertEqual(messages[1].role, .assistant)
        XCTAssertTrue(messages[1].isError)
        XCTAssertTrue(messages[1].content.contains("Agent runtime is unavailable"))
        XCTAssertFalse(chat.hasActiveTurn)
        XCTAssertEqual(state.composer.text, "")
    }
}
