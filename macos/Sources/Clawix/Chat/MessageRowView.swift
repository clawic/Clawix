import SwiftUI
import ClawixCore

/// Draw-only session row.
///
/// This is the render-layer-thinness leaf for the chat transcript: it receives
/// an already-computed `MessageRowDisplayModel` and only draws it. By
/// construction it performs ZERO derivation in `body`:
///   - no `Date`/`Calendar` math (timestamp arrives pre-formatted),
///   - no `PlanSegmenter.segments` / segmentation (content arrives pre-split
///     into `contentBlocks`),
///   - no `MarkdownParseCache.parse` (the off-body parse lives in
///     `AssistantMarkdownText`'s render model),
///   - no timeline window/coalesce or canonical-body normalize (the compute
///     layer, `SessionPresentationStore`, owns all of it).
///
/// The intricate live-streaming/timeline-expand surface stays in the existing
/// `MessageRow` until P3 moves the heavy detail behind `TimelineDetailProvider`;
/// this view is the thin boundary the charter requires, wired and verifiable.
struct MessageRowView: View, Equatable {
    let displayModel: MessageRowDisplayModel
    var codeBlockWordWrap: Bool = true
    var findQuery: String = ""
    var openLink: (URL) -> Void = { _ in }
    var onToggleCodeBlockWordWrap: () -> Void = {}

    static func == (lhs: MessageRowView, rhs: MessageRowView) -> Bool {
        lhs.displayModel == rhs.displayModel
            && lhs.codeBlockWordWrap == rhs.codeBlockWordWrap
            && lhs.findQuery == rhs.findQuery
    }

    var body: some View {
        let _ = RenderProbe.tick("MessageRowView")
        VStack(alignment: displayModel.isUser ? .trailing : .leading, spacing: 12) {
            if displayModel.timeline.workedForExists {
                workedForLabel
            }
            ForEach(displayModel.contentBlocks) { block in
                contentBlock(block)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            timestamp
        }
        .frame(maxWidth: .infinity, alignment: displayModel.isUser ? .trailing : .leading)
    }

    @ViewBuilder
    private func contentBlock(_ block: MessageContentBlock) -> some View {
        switch block {
        case .text(let id, let body):
            AssistantMarkdownText(
                text: body,
                renderKey: .custom(id),
                weight: displayModel.isError ? .regular : .light,
                color: displayModel.isError ? Palette.danger : Palette.textPrimary,
                streamingFinished: displayModel.state == .done,
                codeBlockWordWrap: codeBlockWordWrap,
                findQuery: findQuery,
                openLink: openLink,
                onToggleCodeBlockWordWrap: onToggleCodeBlockWordWrap
            )
        case .plan(_, let body, let completed):
            PlanCardView(content: body, completed: completed)
        }
    }

    private var workedForLabel: some View {
        // Compact collapsed descriptor only: count + bounded file names +
        // elapsed. The full timeline materializes lazily on expand (P3).
        Text(verbatim: workedForText)
            .font(BodyFont.system(size: 12, wght: 500))
            .foregroundColor(Palette.textSecondary)
    }

    private var workedForText: String {
        let elapsed = displayModel.timeline.elapsedSeconds
        var label = elapsed > 0 ? "Worked for \(elapsed)s" : "Worked"
        if !displayModel.timeline.fileNames.isEmpty {
            label += " · " + displayModel.timeline.fileNames.joined(separator: ", ")
        }
        return label
    }

    private var timestamp: some View {
        Text(verbatim: displayModel.formattedTimestamp)
            .font(BodyFont.system(size: 11, wght: 500))
            .foregroundColor(Color.gray(light: 0.50, dark: 0.45))
            .padding(.horizontal, 4)
    }
}
