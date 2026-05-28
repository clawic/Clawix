import XCTest
@testable import Clawix

@MainActor
final class UserFacingFailureTests: XCTestCase {
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

    func testClassifiesCommonRecoverableFailures() {
        XCTAssertEqual(
            UserFacingFailure.classify("Clawix backend is not running.").kind,
            .backendUnavailable
        )
        XCTAssertEqual(
            UserFacingFailure.classify("daemonUnreachable").kind,
            .daemonUnavailable
        )
        XCTAssertEqual(
            UserFacingFailure.classify("background bridge registered but not loaded").kind,
            .daemonUnavailable
        )
        XCTAssertEqual(
            UserFacingFailure.classify("workspace is denied on this host").kind,
            .permissionDenied
        )
        XCTAssertEqual(
            UserFacingFailure.classify("HTTP 401: invalid API key").kind,
            .permissionDenied
        )
        XCTAssertEqual(
            UserFacingFailure.classify("model not found: local-test").kind,
            .modelUnavailable
        )
        XCTAssertEqual(
            UserFacingFailure.classify("No model available for this provider.").kind,
            .modelUnavailable
        )
        XCTAssertEqual(
            UserFacingFailure.classify("The Internet connection appears to be offline.").kind,
            .networkOffline
        )
        XCTAssertEqual(
            UserFacingFailure.classify("Network is unreachable").kind,
            .networkOffline
        )
        XCTAssertEqual(
            UserFacingFailure.classify("ClawJS index service is not running.").kind,
            .serviceUnavailable
        )
        XCTAssertEqual(
            UserFacingFailure.classify("opaque provider error").displayMessage,
            L10n.t("Request failed. Try again in a moment.")
        )
    }

    func testEmptyStateMessagesAreLocalizedThroughSharedPresentation() {
        XCTAssertEqual(UserFacingEmptyState.chats.message, L10n.t("No chats"))
        XCTAssertEqual(UserFacingEmptyState.chatsFiltered.message, L10n.t("No chats match the filter"))
        XCTAssertEqual(UserFacingEmptyState.projectChats.message, L10n.t("No chats in this project yet"))
        XCTAssertEqual(UserFacingEmptyState.chatTranscriptLoading.message, L10n.t("Loading conversation..."))
        XCTAssertEqual(UserFacingEmptyState.chatTranscriptEmpty.message, L10n.t("No messages loaded"))
        XCTAssertEqual(UserFacingEmptyState.searchPrompt.message, L10n.t("Search by chat title"))
        XCTAssertEqual(UserFacingEmptyState.mcpServers.message, L10n.t("No MCP servers connected yet."))
        XCTAssertEqual(UserFacingEmptyState.providers.message, L10n.t("No providers match."))
        XCTAssertEqual(
            UserFacingEmptyState.providersQuery("local").message,
            String(format: L10n.t("No providers match \"%@\"."), locale: AppLocale.current, "local")
        )
        XCTAssertEqual(
            UserFacingEmptyState.providerAPIKeyAccounts.message,
            L10n.t("No accounts yet. Add an API key to start using this provider.")
        )
        XCTAssertEqual(
            UserFacingEmptyState.providerOAuthAccounts.message,
            L10n.t("No accounts yet. Sign in to start using this provider.")
        )
    }

    func testAppendErrorBubbleUsesClassifiedLocalizedMessage() {
        let state = AppState(backgroundBridgeIsActive: { false })
        let chatId = UUID()
        state.chats = [
            Chat(id: chatId, title: "Failure", messages: [], createdAt: Date())
        ]

        state.appendErrorBubble(chatId: chatId, message: "model not found: local-test")

        let message = state.chatStore.transcript(for: chatId)?.messages.last
        XCTAssertEqual(message?.isError, true)
        XCTAssertEqual(
            message?.content,
            String(format: L10n.t("Error: %@"), L10n.t("That model is not available. Pick another model and try again."))
        )
        XCTAssertEqual(state.chatStore.summary(id: chatId)?.hasActiveTurn, false)
    }

    func testAssistantFailureKeepsPartialTextAndUsesClassifiedLine() {
        let state = AppState(backgroundBridgeIsActive: { false })
        let chatId = UUID()
        let assistant = ChatMessage(role: .assistant, content: "partial", streamingFinished: false)
        state.chats = [
            Chat(id: chatId, title: "Partial", messages: [assistant], createdAt: Date(), hasActiveTurn: true)
        ]

        state.markAssistantFailed(
            chatId: chatId,
            messageId: assistant.id,
            error: "The Internet connection appears to be offline."
        )

        let message = state.chatStore.transcript(for: chatId)?.messages.last
        XCTAssertEqual(message?.isError, true)
        XCTAssertEqual(
            message?.content,
            "partial\n\n\(String(format: L10n.t("Error: %@"), L10n.t("The network appears to be offline. Reconnect, then try again.")))"
        )
        XCTAssertEqual(state.chatStore.summary(id: chatId)?.hasActiveTurn, false)
    }
}
