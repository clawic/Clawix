import AppKit
import SwiftUI
import ClawixCore

struct ChatMessageEntryView: View {
    let appState: AppState
    let chat: Chat
    @ObservedObject var messageStore: ChatMessageStore
    /// The session compute layer for this open chat. The row's draw-only
    /// display model is sourced from here (precomputed once per named per-chat
    /// event), never derived in the row body.
    @ObservedObject var presentation: SessionPresentationStore
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
        // Draw-only boundary: the transcript mounts MessageRowView fed by the
        // precomputed model from SessionPresentationStore. The store re-derives
        // only the row whose message changed, so a delta updates exactly this
        // one row's model and leaves siblings untouched. The model is `make`d
        // here as a cheap fallback only when the store has not yet produced one
        // for this id (first frame before the structure subscription lands).
        let displayModel = presentation.model(for: message.id)
            ?? MessageRowDisplayModel.make(from: message, now: Date())
        MessageRowView(
            displayModel: displayModel,
            chatId: chat.id,
            message: message,
            isLastUserMessage: message.id == lastUserMessageId,
            isLastAssistantMessage: message.id == lastAssistantMessageId,
            responseStreaming: responseStreamingForRow,
            codeBlockWordWrap: appState.chatCodeBlockWordWrap,
            findQuery: activeFindQuery,
            publishingReady: publishingReady,
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
            }
        )
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
