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

        if openSessionBeforeSend, !daemonBridgeClient.openSession(chatId) {
            appendErrorBubble(
                chatId: chatId,
                message: "Background bridge is not ready. Try again once it reconnects."
            )
            return false
        }

        trackOptimisticUserMessage(chatId: chatId, messageId: optimisticMessageId)
        guard daemonBridgeClient.sendMessage(chatId: chatId, text: text, attachments: attachments) else {
            appendErrorBubble(
                chatId: chatId,
                message: "Background bridge is not ready. Try again once it reconnects."
            )
            return false
        }
        return true
    }
}
