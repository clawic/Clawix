import AppKit
import SwiftUI
import ClawixCore

/// The live session row boundary (ADR 0041/0042).
///
/// This is the row the transcript mounts. Its identity and re-render decision
/// are driven by an already-computed `MessageRowDisplayModel` produced once by
/// `SessionPresentationStore`: a delta on one message re-derives only that one
/// model, and a sibling whose model is byte-for-byte unchanged is skipped by
/// `Equatable`. An unrelated `AppState` write never reaches the store, so it
/// never re-evaluates a row.
///
/// `body` is draw-only by construction: it performs ZERO derivation. It does no
/// `Date`/`Calendar` math (the timestamp arrives pre-formatted on the model), no
/// `MarkdownParseCache.parse`, no `PlanSegmenter.segments` segmentation, no
/// `.sorted`/`.filter` over a message/timeline array, and no relative-age
/// formatting. It forwards the precomputed model and the raw message reference
/// to the interactive detail child; it derives nothing itself. The static guard
/// (`scripts/view_render_thinness_check.mjs`) governs this file.
///
/// The intricate live-streaming / timeline-expand / edit / fork / copy surface
/// still lives in `MessageRow`, which this view hosts as its detail child. P3
/// moves the heavy timeline detail behind `TimelineDetailProvider`; until then
/// the rich interaction surface stays intact and wired, just gated by the
/// precomputed display model.
struct MessageRowView: View, Equatable {
    /// The precomputed, draw-only display model. The single source of the row's
    /// re-render decision (`Equatable`): when this is unchanged the row is
    /// skipped, when a named per-message event changes it the row redraws.
    let displayModel: MessageRowDisplayModel

    // The raw model + callbacks the interactive detail child needs. These are
    // forwarded verbatim; the view derives nothing from them in `body`.
    let chatId: UUID
    let message: ChatMessage
    var isLastUserMessage: Bool = false
    var isLastAssistantMessage: Bool = false
    var responseStreaming: Bool = false
    var codeBlockWordWrap: Bool = true
    var findQuery: String = ""
    var publishingReady: Bool = false
    var onTimelineExpanded: ((UUID) -> Void)? = nil
    var onUserBubbleExpanded: ((UUID) -> Void)? = nil
    var onEditUserMessage: (String) -> Void = { _ in }
    var onForkConversation: () -> Void = {}
    var onOpenImage: (URL) -> Void = { _ in }
    var onOpenLink: (URL) -> Void = { _ in }
    var onCopyMessage: (String, @escaping () -> Void) -> Void = { content, copied in
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(content, forType: .string)
        copied()
    }
    var onPushToPublishing: (String) -> Void = { _ in }
    var onToggleCodeBlockWordWrap: () -> Void = {}

    /// The row's re-render decision rides entirely on the precomputed display
    /// model plus the small set of draw-only flags. The closures are
    /// intentionally NOT compared (swapping them across rebuilds must not force
    /// a redraw). `displayModel` already folds in role, state, segmented
    /// content, formatted timestamp and the worked-for summary, so comparing it
    /// is the precise "did this row's display value change" test.
    static func == (lhs: MessageRowView, rhs: MessageRowView) -> Bool {
        lhs.displayModel == rhs.displayModel
            && lhs.chatId == rhs.chatId
            && lhs.isLastUserMessage == rhs.isLastUserMessage
            && lhs.isLastAssistantMessage == rhs.isLastAssistantMessage
            && lhs.responseStreaming == rhs.responseStreaming
            && lhs.codeBlockWordWrap == rhs.codeBlockWordWrap
            && lhs.findQuery == rhs.findQuery
            && lhs.publishingReady == rhs.publishingReady
    }

    var body: some View {
        let _ = RenderProbe.tick("MessageRowView")
        // Draw-only: forward the precomputed model and raw references to the
        // interactive detail child. No derivation happens here.
        MessageRow(
            chatId: chatId,
            message: message,
            isLastUserMessage: isLastUserMessage,
            isLastAssistantMessage: isLastAssistantMessage,
            responseStreaming: responseStreaming,
            codeBlockWordWrap: codeBlockWordWrap,
            findQuery: findQuery,
            onTimelineExpanded: onTimelineExpanded,
            onUserBubbleExpanded: onUserBubbleExpanded,
            onEditUserMessage: onEditUserMessage,
            onForkConversation: onForkConversation,
            onOpenImage: onOpenImage,
            onOpenLink: onOpenLink,
            onCopyMessage: onCopyMessage,
            onPushToPublishing: onPushToPublishing,
            onToggleCodeBlockWordWrap: onToggleCodeBlockWordWrap,
            publishingReady: publishingReady
        )
        .equatable()
    }
}
