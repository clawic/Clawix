import AppKit
import SwiftUI
import ClawixCore

struct ChatMessageEntryView: View {
    let appState: AppState
    let chat: Chat
    @ObservedObject var messageStore: ChatMessageStore
    let lastUserMessageId: UUID?
    let lastAssistantMessageId: UUID?
    let responseStreaming: Bool
    let activeFindQuery: String
    let publishingReady: Bool
    let proxy: ScrollViewProxy

    var body: some View {
        let message = messageStore.message
        let responseStreamingForRow = responseStreaming
            && message.role == .assistant
            && !message.streamingFinished
            && !message.isError
        MessageRow(
            chatId: chat.id,
            message: message,
            isLastUserMessage: message.id == lastUserMessageId,
            isLastAssistantMessage: message.id == lastAssistantMessageId,
            responseStreaming: responseStreamingForRow,
            codeBlockWordWrap: appState.chatCodeBlockWordWrap,
            findQuery: activeFindQuery,
            onTimelineExpanded: { expandedId in
                // Pin the bottom of the expanded bubble so inserted content grows upward.
                DispatchQueue.main.async {
                    proxy.scrollTo(expandedId, anchor: .bottom)
                }
            },
            onUserBubbleExpanded: { expandedId in
                DispatchQueue.main.async {
                    proxy.scrollTo(expandedId, anchor: .bottom)
                }
            },
            onEditUserMessage: { newContent in
                appState.editUserMessage(
                    chatId: chat.id,
                    messageId: message.id,
                    newContent: newContent
                )
            },
            onForkConversation: {
                appState.forkConversation(
                    chatId: chat.id,
                    atMessageId: message.id,
                    sourceSnapshot: chat
                )
            },
            onOpenImage: { url in
                appState.imagePreviewURL = url
            },
            onOpenLink: { url in
                appState.openLinkInBrowser(url)
            },
            onCopyMessage: { content, copied in
                LegalSafetyStore.shared.requestSensitiveActionReview(action: .exportShare, appState: appState) {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(LegalSafetyStore.shared.reviewedSensitiveOutputText(content), forType: .string)
                    copied()
                }
            },
            onPushToPublishing: { body in
                appState.navigate(to: .publishingComposer(prefillBody: body, prefillScheduleAt: nil))
            },
            onToggleCodeBlockWordWrap: {
                appState.chatCodeBlockWordWrap.toggle()
            },
            publishingReady: publishingReady
        )
        .equatable()
        .id(message.id)
        .transaction { transaction in
            transaction.animation = nil
        }

        if message.id == chat.forkBannerAfterMessageId,
           let parentChatId = chat.forkedFromChatId {
            ForkedFromBanner(parentChatId: parentChatId)
                .padding(.top, -20)
        }
    }
}
