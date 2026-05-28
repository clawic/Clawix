import Foundation
import ClawixCore

extension AppState {
    @discardableResult
    func sendBridgeMessageOrReport(
        chatId: UUID,
        text: String,
        optimisticMessageId: UUID,
        attachments: [WireAttachment] = [],
        openSessionBeforeSend: Bool = false
    ) -> Bool {
        guard let daemonBridgeClient, daemonBridgeClient.isReadyForRequests else {
            appendErrorBubble(
                chatId: chatId,
                message: "Background bridge is not ready. Try again once it reconnects."
            )
            return false
        }

        let bridgeSessionId = bridgeSessionId(forChatId: chatId)
        if openSessionBeforeSend, !daemonBridgeClient.openSession(bridgeSessionId) {
            appendErrorBubble(
                chatId: chatId,
                message: "Background bridge is not ready. Try again once it reconnects."
            )
            return false
        }

        trackOptimisticUserMessage(chatId: chatId, messageId: optimisticMessageId)
        guard daemonBridgeClient.sendMessage(sessionId: bridgeSessionId, text: text, attachments: attachments) else {
            appendErrorBubble(
                chatId: chatId,
                message: "Background bridge is not ready. Try again once it reconnects."
            )
            return false
        }
        return true
    }
}
