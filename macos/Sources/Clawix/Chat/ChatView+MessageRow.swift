import AppKit
import SwiftUI
import ClawixCore

enum TimestampFormatters {
    private static let lock = NSLock()
    private static var lastLocaleId: String = ""
    private static let time = DateFormatter()
    private static let weekday = DateFormatter()
    private static let dateSameYear = DateFormatter()
    private static let dateOtherYear = DateFormatter()

    static func resolved() -> (
        time: DateFormatter,
        weekday: DateFormatter,
        dateSameYear: DateFormatter,
        dateOtherYear: DateFormatter
    ) {
        lock.lock(); defer { lock.unlock() }
        let locale = AppLocale.current
        let id = locale.identifier
        if id != lastLocaleId {
            time.locale = locale
            time.dateStyle = .none
            time.timeStyle = .short

            weekday.locale = locale
            weekday.dateFormat = "EEEE"

            dateSameYear.locale = locale
            dateSameYear.setLocalizedDateFormatFromTemplate("MMMdjmm")

            dateOtherYear.locale = locale
            dateOtherYear.setLocalizedDateFormatFromTemplate("MMMdyjmm")

            lastLocaleId = id
        }
        return (time, weekday, dateSameYear, dateOtherYear)
    }
}

struct ChatMarkdownPrewarmKey: Hashable {
    let chatId: UUID
    let visibleMessageCount: Int
    let firstMessageId: UUID?
    let lastMessageId: UUID?
    let lastTimelineCount: Int
}

enum ChatMarkdownPrewarmer {
    static func prewarm(messages: [ChatMessage], timelineEntryLimit: Int) async {
        let prewarmSet = markdownTexts(messages: messages, timelineEntryLimit: timelineEntryLimit)
        PerfSignpost.renderMarkdown.event("prewarm.content_texts", prewarmSet.contentCount)
        PerfSignpost.renderMarkdown.event("prewarm.timeline_texts", prewarmSet.timelineCount)
        RenderProbe.mark(
            "MarkdownPrewarmSet",
            fields: [
                "content": "\(prewarmSet.contentCount)",
                "timeline": "\(prewarmSet.timelineCount)",
                "total": "\(prewarmSet.texts.count)"
            ]
        )
        let texts = prewarmSet.texts
        if !texts.isEmpty {
            PerfSignpost.renderMarkdown.event("prewarm.texts", texts.count)
        }
        guard !texts.isEmpty else { return }
        await Task.detached(priority: .utility) {
            for text in texts {
                MarkdownParseCache.prewarm(text)
            }
        }.value
    }

    private struct PrewarmTextSet {
        var texts: [String] = []
        var contentCount = 0
        var timelineCount = 0
    }

    private static func markdownTexts(messages: [ChatMessage], timelineEntryLimit: Int) -> PrewarmTextSet {
        var result = PrewarmTextSet()
        result.texts.reserveCapacity(messages.count * 2)
        for message in messages where message.role == .assistant {
            if !message.content.isEmpty {
                result.texts.append(message.content)
                result.contentCount += 1
            }
            let timeline = message.timeline.suffix(timelineEntryLimit)
            for entry in timeline {
                switch entry {
                case .reasoning(_, let text), .message(_, let text):
                    if !text.isEmpty {
                        result.texts.append(text)
                        result.timelineCount += 1
                    }
                case .steered, .divider, .tools:
                    break
                }
            }
        }
        return result
    }

}

enum TimelineEntryWindow {
    static func visibleEntries(
        in timeline: [AssistantTimelineEntry],
        isStreaming: Bool,
        visibleLimit: Int
    ) -> [AssistantTimelineEntry] {
        guard visibleLimit > 0 else { return [] }
        let entries = visibleLimit < timeline.count
            ? Array(timeline.suffix(visibleLimit))
            : timeline
        return coalescingAdjacentToolEntries(entries)
    }

    private static func coalescingAdjacentToolEntries(
        _ entries: [AssistantTimelineEntry]
    ) -> [AssistantTimelineEntry] {
        var result: [AssistantTimelineEntry] = []
        var pendingTools: [(id: UUID, items: [WorkItem], presentation: ToolTimelinePresentationSnapshot?)] = []

        func flushPendingTools() {
            guard !pendingTools.isEmpty else { return }
            if pendingTools.count == 1, let first = pendingTools.first {
                result.append(.tools(id: first.id, items: first.items, presentation: first.presentation))
            } else if let first = pendingTools.first {
                let mergedItems = pendingTools.flatMap(\.items)
                result.append(.tools(
                    id: first.id,
                    items: mergedItems,
                    presentation: ToolTimelinePresentation.snapshot(groupID: first.id, items: mergedItems)
                ))
            }
            pendingTools.removeAll(keepingCapacity: true)
        }

        for entry in entries {
            switch entry {
            case .tools(let id, let items, let presentation):
                pendingTools.append((id, items, presentation))
            default:
                flushPendingTools()
                result.append(entry)
            }
        }
        flushPendingTools()
        return result
    }

    static func shouldShowCanonicalBody(
        in timeline: [AssistantTimelineEntry],
        content: String,
        isStreaming: Bool,
        timelineExpanded: Bool
    ) -> Bool {
        let canonical = normalizedTimelineText(content)
        guard !canonical.isEmpty else { return false }
        guard !isStreaming else { return false }
        guard timelineExpanded else { return true }
        return !timeline.contains { entry in
            guard case .message(_, let text) = entry else { return false }
            let timelineText = normalizedTimelineText(text)
            return timelineText == canonical
                || timelineText.hasSuffix("\n\n\(canonical)")
        }
    }

    private static func normalizedTimelineText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct MessageRow: View, Equatable {
    let chatId: UUID
    let message: ChatMessage
    var isLastUserMessage: Bool = false
    var isLastAssistantMessage: Bool = false
    var responseStreaming: Bool = false
    var codeBlockWordWrap: Bool = true
    /// Empty unless the in-page find bar is open. Threaded down from
    /// `ChatView` instead of read off `AppState` here so an unrelated
    /// `@Published` change on `AppState` (any streaming delta, hover
    /// state on the sidebar, etc.) does not invalidate every visible
    /// row's body. Combined with `.equatable()` on the row's call site,
    /// a delta on a single message only re-renders that one row.
    var findQuery: String = ""
    var closedMetadataReady: Bool = true
    var onTimelineExpanded: ((UUID) -> Void)? = nil
    var onUserBubbleExpanded: ((UUID) -> Void)? = nil
    /// Closures bridge back to the `AppState` mutation surface from the
    /// row's parent (`ChatView`). They are intentionally NOT compared by
    /// `Equatable` so swapping them across rebuilds doesn't force a
    /// re-render of the bubble.
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
    var publishingReady: Bool = false
    @State private var rowHovered = false
    @State private var justCopied = false
    @State private var copyResetTask: Task<Void, Never>? = nil
    @State private var isEditing = false
    @State private var editDraft: String = ""
    /// Toggled by the in-bubble "N previous messages" disclosure. The
    /// hidden portion = every timeline entry up to and including the last
    /// `.tools` group; the visible portion is the closing reasoning chunk
    /// (the final answer Clawix writes after the work is done).
    @State private var timelineExpanded = false
    @State private var visibleTimelineEntryLimit = Self.initialTimelineEntryLimit
    @State private var lastTimelineRevealAt: Date = .distantPast

    private var isUser: Bool { message.role == .user }
    private var exposeMessageAccessibility: Bool { NSWorkspace.shared.isVoiceOverEnabled }
    static let initialTimelineEntryLimit = 8
    private static let timelineEntryPageSize = 8
    private static let timelineRevealThrottle: TimeInterval = 0.15

    static func == (lhs: MessageRow, rhs: MessageRow) -> Bool {
        lhs.chatId == rhs.chatId
            && lhs.message == rhs.message
            && lhs.isLastUserMessage == rhs.isLastUserMessage
            && lhs.isLastAssistantMessage == rhs.isLastAssistantMessage
            && lhs.responseStreaming == rhs.responseStreaming
            && lhs.codeBlockWordWrap == rhs.codeBlockWordWrap
            && lhs.findQuery == rhs.findQuery
            && lhs.closedMetadataReady == rhs.closedMetadataReady
            && lhs.publishingReady == rhs.publishingReady
    }

    var body: some View {
        let _ = RenderProbe.tick("MessageRow")
        let _ = tickStreamingRowCategory()
        let _ = PerfSignpost.uiChat.event("row.body")
        let _ = markLiveStreamRowBodyIfNeeded()
        let _ = markLiveStreamRenderableModelIfNeeded()
        VStack(alignment: isUser ? .trailing : .leading, spacing: 24) {
            if isUser {
                if message.steeredByAnnotation {
                    SteeredConversationDivider()
                        .frame(maxWidth: .infinity)
                }
                if isEditing {
                    UserMessageEditor(
                        text: $editDraft,
                        onCancel: { isEditing = false },
                        onSubmit: {
                            let trimmed = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            onEditUserMessage(trimmed)
                            isEditing = false
                        }
                    )
                    .frame(maxWidth: CGFloat.infinity)
                } else {
                    let parsed = UserBubbleContent.parse(message.content, attachments: message.attachments)
                    if !parsed.images.isEmpty || !parsed.files.isEmpty {
                        UserMentionPreviews(parsed: parsed, onOpenImage: onOpenImage)
                    }
                    if let audioRef = message.audioRef {
                        UserAudioBubble(audioRef: audioRef)
                    }
                    if !parsed.text.isEmpty {
                        let paragraphs = parsed.text
                            .replacingOccurrences(of: "\r\n", with: "\n")
                            .components(separatedBy: "\n\n")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        UserMessageTextBubble(
                            paragraphs: paragraphs,
                            findQuery: findQuery,
                            exposeAccessibility: exposeMessageAccessibility,
                            accessibilityText: AccessibilityText.clipped(parsed.text),
                            onExpand: { onUserBubbleExpanded?(message.id) }
                        )
                    }
                    if message.sentAsGoal {
                        GoalMessageBadge(label: "Sent as goal", icon: .circleDot)
                            .padding(.top, -14)
                            .padding(.trailing, 2)
                    }
                }
            } else {
                // One streaming-state header sits at the top of the
                // bubble and walks through three visual states:
                //   1. "Working" while the very first reasoning chunk is
                //      being typed (no seconds, no chevron).
                //   2. "Working for Xs" once a second action has begun
                //      (live ticking seconds, no chevron).
                //   3. "Worked for Xs ›" once the turn fully completes
                //      (chevron, expandable). The reasoning + tool
                //      entries that accumulated while streaming collapse
                //      behind the chevron so the user focuses on the
                //      final answer.
                //
                // Crucial nuance: the collapse only happens when the
                // turn ends, not when the final reply starts arriving.
                // While streaming, a bounded live window of the freshest
                // reasoning chunks and tool calls stays visible below
                // the header. The full timeline remains recorded on the
                // message and only becomes browsable through the
                // disclosure once streaming finishes.
                let isStreaming = !message.streamingFinished && !message.isError
                if let summary = message.workSummary, !message.isError {
                    if isStreaming {
                        if !message.timeline.isEmpty {
                            LiveWorkingHeader(
                                summary: summary,
                                timelineCount: message.timeline.count
                            )
                        }
                    } else if !message.timeline.isEmpty || !summary.items.isEmpty {
                        WorkSummaryHeader(
                            summary: summary,
                            expanded: $timelineExpanded,
                            controlId: "chat.workSummary.\(message.id.uuidString)",
                            onToggle: { willExpand in
                                markWorkSummaryToggle(willExpand: willExpand)
                            }
                        ) {
                            onTimelineExpanded?(message.id)
                        }
                    }
                }

                // During streaming, keep the live timeline bounded to
                // the freshest entries so each delta does not remount a
                // long historical tool/reasoning stack. After the turn
                // ends, the entries collapse behind the chevron and only
                // resurface when the user expands the disclosure.
                let showTimeline = isStreaming || timelineExpanded
                if showTimeline {
                    let timelineEntries = visibleTimelineEntries(isStreaming: isStreaming)
                    let _ = markWorkSummaryTimelineVisible(entries: timelineEntries, isStreaming: isStreaming)
                    let _ = PerfSignpost.uiChat.event("timeline.entries.visible", timelineEntries.count)
                    if !isStreaming, hiddenTimelineEntryCount > 0 {
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                revealMoreTimelineEntriesIfNeeded()
                            }
                    }
                    ForEach(timelineEntries) { entry in
                        timelineEntry(entry)
                            .transaction { transaction in
                                transaction.animation = nil
                            }
                    }
                }

                // After the turn ends and the chevron is collapsed, the
                // timeline is hidden and the bubble shows only the
                // canonical assistant body. When the user expands the
                // timeline, keep that body visible after the historical
                // work log to match the desktop "Worked for" view.
                let showCanonicalBody = TimelineEntryWindow.shouldShowCanonicalBody(
                    in: message.timeline,
                    content: message.content,
                    isStreaming: isStreaming,
                    timelineExpanded: timelineExpanded
                )
                if showCanonicalBody, !message.content.isEmpty {
                    let segments = PlanSegmenter.segments(from: message.content)
                    let onlyTextSegment: Bool = {
                        guard segments.count == 1, case .text = segments[0] else { return false }
                        return true
                    }()
                    ForEach(Array(segments.enumerated()), id: \.offset) { segmentIndex, segment in
                        switch segment {
                        case .text(let body):
                            AssistantMarkdownText(
                                text: body,
                                renderKey: .custom("message:\(message.id.uuidString):segment:\(segmentIndex)"),
                                weight: message.isError ? .regular : .light,
                                color: message.isError
                                    ? Palette.danger
                                    : Palette.textPrimary,
                                checkpoints: onlyTextSegment ? message.streamCheckpoints : [],
                                streamingFinished: message.streamingFinished,
                                codeBlockWordWrap: codeBlockWordWrap,
                                findQuery: findQuery,
                                openLink: onOpenLink,
                                onToggleCodeBlockWordWrap: onToggleCodeBlockWordWrap
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityHidden(!exposeMessageAccessibility)
                        case .plan(let body, let completed):
                            PlanCardView(content: body, completed: completed)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityHidden(!exposeMessageAccessibility)
                        }
                    }
                }

                let fileLinks = finalAssistantFileLinkPreview
                if !responseStreaming,
                   message.streamingFinished,
                   !message.isError,
                   !PlanSegmenter.containsPlan(message.content),
                   !fileLinks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(fileLinks.visiblePaths, id: \.self) { path in
                            FileLinkCard(path: path)
                                .frame(maxWidth: chatRailMaxWidth * 0.7, alignment: .leading)
                        }
                        if fileLinks.remainingCount > 0 {
                            Text(verbatim: "Show \(fileLinks.remainingCount) more")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundColor(Palette.textSecondary)
                                .padding(.top, 1)
                        }
                    }
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if isLastAssistantMessage,
                   !responseStreaming,
                   message.streamingFinished,
                   !message.isError,
                   !PlanSegmenter.containsPlan(message.content),
                   let lastURL = finalAssistantLinkPreviewURL {
                    LinkPreviewCard(url: lastURL)
                        .padding(.top, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !message.streamingFinished && !message.isError {
                    ThinkingShimmer(text: String(localized: "Thinking", bundle: AppLocale.bundle, locale: AppLocale.current))
                        .padding(.top, 2)
                }
            }

            // Action bar (copy / branch / edit / timestamp) only shows
            // once the assistant turn finishes. While streaming, the
            // bubble's chrome stays clean: no actions, no timestamp.
            let actionBarAvailable = isUser || message.streamingFinished
            if !isEditing, actionBarAvailable {
                let alwaysVisible = (isUser && isLastUserMessage) || (!isUser && isLastAssistantMessage)
                actionBar
                    .opacity(alwaysVisible ? 1 : (rowHovered ? 1 : 0))
                    .allowsHitTesting(alwaysVisible || rowHovered)
                    .animation(.easeOut(duration: 0.15), value: rowHovered)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            rowHovered = hovering
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(.leading, isUser ? chatRailMaxWidth * 0.2 : 0)
        .onChange(of: timelineExpanded) { _, expanded in
            lastTimelineRevealAt = .distantPast
            if expanded {
                visibleTimelineEntryLimit = message.timeline.count
                prewarmVisibleTimelineMarkdown(limit: message.timeline.count)
            } else {
                visibleTimelineEntryLimit = Self.initialTimelineEntryLimit
            }
        }
        .onChange(of: message.id) { _, _ in
            visibleTimelineEntryLimit = Self.initialTimelineEntryLimit
            lastTimelineRevealAt = .distantPast
        }
        .clxControl("chat.message.row", role: "row", label: "Message row")
        .clxControl(isUser ? "chat.message.user" : "chat.message.assistant", role: "text", label: isUser ? "User message" : "Assistant message")
        .clxControl(message.streamingFinished ? "chat.message.final" : "chat.streaming.deltaTarget", role: "text", label: message.streamingFinished ? "Final message" : "Streaming message")
    }

    private var hiddenTimelineEntryCount: Int {
        max(0, message.timeline.count - visibleTimelineEntryLimit)
    }

    private func markWorkSummaryToggle(willExpand: Bool) {
        RenderProbe.mark(
            "WorkSummaryToggleRequested",
            fields: [
                "chat": chatId.uuidString,
                "hidden": "\(hiddenTimelineEntryCount)",
                "message": message.id.uuidString,
                "timeline": "\(message.timeline.count)",
                "visibleLimit": "\(visibleTimelineEntryLimit)",
                "willExpand": "\(willExpand)"
            ]
        )
    }

    private func markWorkSummaryTimelineVisible(entries: [AssistantTimelineEntry], isStreaming: Bool) {
        guard !isStreaming else { return }
        var messageEntries = 0
        var reasoningEntries = 0
        var toolEntries = 0
        var toolItems = 0
        for entry in entries {
            switch entry {
            case .message:
                messageEntries += 1
            case .reasoning:
                reasoningEntries += 1
            case .steered:
                break
            case .divider:
                break
            case .tools(_, let items, _):
                toolEntries += 1
                toolItems += items.count
            }
        }
        RenderProbe.mark(
            "WorkSummaryTimelineVisible",
            fields: [
                "chat": chatId.uuidString,
                "hidden": "\(hiddenTimelineEntryCount)",
                "message": message.id.uuidString,
                "messageEntries": "\(messageEntries)",
                "reasoningEntries": "\(reasoningEntries)",
                "timeline": "\(message.timeline.count)",
                "toolEntries": "\(toolEntries)",
                "toolItems": "\(toolItems)",
                "visible": "\(entries.count)",
                "visibleLimit": "\(visibleTimelineEntryLimit)"
            ]
        )
    }

    private var finalAssistantLinkPreviewURL: URL? {
        AssistantWebLinkPreviewPolicy.url(for: message)
    }

    private var finalAssistantFileLinkPreview: FileLinkPreview {
        FileLinkPreviewCache.shared.preview(for: message)
    }

    private func tickStreamingRowCategory() {
        guard responseStreaming else { return }
        if message.role == .assistant, !message.streamingFinished, !message.isError {
            RenderProbe.tick("MessageRow.activeStreaming")
        } else {
            RenderProbe.tick("MessageRow.nonActiveDuringStream")
        }
    }

    private func markLiveStreamRowBodyIfNeeded() {
        guard message.role == .assistant, !message.streamingFinished, !message.isError else { return }
        RenderProbe.mark(
            "LiveStreamRowBody",
            fields: [
                "chat": chatId.uuidString,
                "message": message.id.uuidString,
                "contentChars": "\(message.content.count)",
                "reasoningChars": "\(message.reasoningText.count)",
                "timeline": "\(message.timeline.count)",
                "checkpoints": "\(message.streamCheckpoints.count)",
                "pendingTail": "\(message.streamPendingTail.count)"
            ]
        )
    }

    private func markLiveStreamRenderableModelIfNeeded() {
        guard message.role == .assistant, !message.streamingFinished, !message.isError else { return }
        var timelineMessageEntries = 0
        var timelineReasoningEntries = 0
        var timelineToolEntries = 0
        for entry in message.timeline {
            switch entry {
            case .message:
                timelineMessageEntries += 1
            case .reasoning:
                timelineReasoningEntries += 1
            case .steered:
                break
            case .divider:
                break
            case .tools:
                timelineToolEntries += 1
            }
        }
        let reasoningCheckpointCount = message.reasoningCheckpoints.values.reduce(0) { $0 + $1.count }
        RenderProbe.mark(
            "LiveStreamRenderableModelAvailable",
            fields: [
                "chat": chatId.uuidString,
                "message": message.id.uuidString,
                "contentChars": "\(message.content.count)",
                "contentCheckpoints": "\(message.streamCheckpoints.count)",
                "pendingTail": "\(message.streamPendingTail.count)",
                "reasoningChars": "\(message.reasoningText.count)",
                "reasoningCheckpoints": "\(reasoningCheckpointCount)",
                "timeline": "\(message.timeline.count)",
                "timelineMessages": "\(timelineMessageEntries)",
                "timelineReasoning": "\(timelineReasoningEntries)",
                "timelineTools": "\(timelineToolEntries)"
            ]
        )
    }

    private func visibleTimelineEntries(isStreaming: Bool) -> [AssistantTimelineEntry] {
        TimelineEntryWindow.visibleEntries(
            in: message.timeline,
            isStreaming: isStreaming,
            visibleLimit: visibleTimelineEntryLimit
        )
    }

    private func revealMoreTimelineEntriesIfNeeded() {
        guard timelineExpanded, hiddenTimelineEntryCount > 0 else { return }
        let now = Date()
        guard now.timeIntervalSince(lastTimelineRevealAt) >= Self.timelineRevealThrottle else {
            return
        }
        lastTimelineRevealAt = now
        let nextLimit = min(message.timeline.count, visibleTimelineEntryLimit + Self.timelineEntryPageSize)
        guard nextLimit != visibleTimelineEntryLimit else { return }
        PerfSignpost.uiChat.event("timeline.entries.revealed", nextLimit)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            visibleTimelineEntryLimit = nextLimit
        }
        prewarmVisibleTimelineMarkdown(limit: nextLimit)
    }

    private func prewarmVisibleTimelineMarkdown(limit: Int? = nil) {
        let count = min(message.timeline.count, limit ?? visibleTimelineEntryLimit)
        let entries = count >= message.timeline.count
            ? message.timeline
            : Array(message.timeline.suffix(count))
        let texts = Self.markdownTexts(in: entries)
        guard !texts.isEmpty else { return }
        Task.detached(priority: .utility) {
            for text in texts {
                MarkdownParseCache.prewarm(text)
            }
        }
    }

    private static func markdownTexts(in entries: [AssistantTimelineEntry]) -> [String] {
        entries.compactMap { entry in
            switch entry {
            case .reasoning(_, let text), .message(_, let text):
                return text.isEmpty ? nil : text
            case .steered, .divider, .tools:
                return nil
            }
        }
    }

    @ViewBuilder
    private func timelineEntry(_ entry: AssistantTimelineEntry) -> some View {
        switch entry {
        case .reasoning(let entryId, let text):
            AssistantMarkdownText(
                text: text,
                renderKey: .timeline(entryId),
                weight: .light,
                color: Palette.textPrimary,
                checkpoints: message.reasoningCheckpoints[entryId] ?? [],
                streamingFinished: message.streamingFinished,
                codeBlockWordWrap: codeBlockWordWrap,
                findQuery: findQuery,
                openLink: onOpenLink,
                onToggleCodeBlockWordWrap: onToggleCodeBlockWordWrap
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(!exposeMessageAccessibility)
        case .message(let entryId, let text):
            messageEntryBody(entryId: entryId, text: text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(!exposeMessageAccessibility)
        case .steered:
            SteeredConversationDivider()
                .frame(maxWidth: .infinity)
                .accessibilityHidden(!exposeMessageAccessibility)
        case .divider(_, let text):
            TimelineDivider(text: text)
                .accessibilityHidden(!exposeMessageAccessibility)
        case .tools(_, let items, let presentation):
            ToolGroupView(items: items, presentation: presentation)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(!exposeMessageAccessibility)
        }
    }

    /// Render a `.message` timeline entry. Mirrors how the bubble used
    /// to render `message.content` (PlanSegmenter + AssistantMarkdownText)
    /// so a preamble that flowed through `nAgentMsgDelta` reads exactly
    /// the same as the final answer once collapsed. The streaming fade
    /// only attaches when this is the single, trailing `.message` entry
    /// AND the body is a contiguous text segment, because
    /// `streamCheckpoints` are character offsets over the full
    /// concatenated message body.
    @ViewBuilder
    private func messageEntryBody(entryId: UUID, text: String) -> some View {
        let segments = PlanSegmenter.segments(from: text)
        let isTrailingMessage: Bool = {
            guard case .message(let lastId, _) = message.timeline.last else { return false }
            return lastId == entryId
        }()
        let messageEntryCount = message.timeline.reduce(0) { acc, e in
            if case .message = e { return acc + 1 } else { return acc }
        }
        let onlyTextSegment: Bool = {
            guard segments.count == 1, case .text = segments[0] else { return false }
            return true
        }()
        let useCheckpoints =
            isTrailingMessage && messageEntryCount == 1 && onlyTextSegment
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(segments.enumerated()), id: \.offset) { segmentIndex, segment in
                switch segment {
                case .text(let body):
                    AssistantMarkdownText(
                        text: body,
                        renderKey: .custom("timeline:\(entryId.uuidString):segment:\(segmentIndex)"),
                        weight: message.isError ? .regular : .light,
                        color: message.isError
                            ? Palette.danger
                            : Palette.textPrimary,
                        checkpoints: useCheckpoints ? message.streamCheckpoints : [],
                        streamingFinished: message.streamingFinished,
                        codeBlockWordWrap: codeBlockWordWrap,
                        findQuery: findQuery,
                        openLink: onOpenLink,
                        onToggleCodeBlockWordWrap: onToggleCodeBlockWordWrap
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                case .plan(let body, let completed):
                    PlanCardView(content: body, completed: completed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        let copyLabel = justCopied
            ? String(localized: "Copied", bundle: AppLocale.bundle, locale: AppLocale.current)
            : String(localized: "Copy", bundle: AppLocale.bundle, locale: AppLocale.current)
        let editLabel = String(localized: "Edit", bundle: AppLocale.bundle, locale: AppLocale.current)
        let forkLabel = String(localized: "Fork conversation", bundle: AppLocale.bundle, locale: AppLocale.current)

        HStack(spacing: -1) {
            if isUser {
                Spacer(minLength: 0)
                timestampLabel
                    .opacity(isLastUserMessage ? (rowHovered ? 1 : 0) : 1)
                    .animation(.easeOut(duration: 0.15), value: rowHovered)
                MessageActionIcon(kind: .copy(showCheck: justCopied),
                                  label: copyLabel,
                                  action: handleCopy)
                if isLastUserMessage && !responseStreaming {
                    MessageActionIcon(kind: .pencil,
                                      label: editLabel) {
                        editDraft = message.content
                        isEditing = true
                    }
                }
            } else {
                MessageActionIcon(kind: .copy(showCheck: justCopied),
                                  label: copyLabel,
                                  action: handleCopy)
                MessageActionIcon(kind: .branchArrows,
                                  label: forkLabel) {
                    onForkConversation()
                }
                if publishingReady {
                    MessageActionIcon(
                        kind: .system("megaphone"),
                        label: String(localized: "Push to publishing",
                                      bundle: AppLocale.bundle,
                                      locale: AppLocale.current)
                    ) {
                        onPushToPublishing(message.content)
                    }
                }
                timestampLabel
                    .opacity(isLastAssistantMessage ? (rowHovered ? 1 : 0) : 1)
                    .animation(.easeOut(duration: 0.15), value: rowHovered)
                if let outcome = message.goalOutcome {
                    Rectangle()
                        .fill(Color.overlay(0.16))
                        .frame(width: 1, height: 12)
                        .padding(.horizontal, 5)
                    GoalMessageBadge(label: outcome.label, icon: .circleCheck)
                }
            }
        }
        .padding(.leading, isUser ? 0 : 2)
        .padding(.trailing, isUser ? 6 : 0)
        .padding(.top, isUser ? -22 : -18)
    }

    private var timestampLabel: some View {
        Text(verbatim: formattedTimestamp)
            .font(BodyFont.system(size: 11, wght: 500))
            .foregroundColor(Color.gray(light: 0.50, dark: 0.45))
            .padding(.horizontal, 4)
    }

    private var formattedTimestamp: String {
        let cal = Calendar.current
        let fmts = TimestampFormatters.resolved()
        if cal.isDateInToday(message.timestamp) {
            return fmts.time.string(from: message.timestamp)
        }
        let startOfMsg = cal.startOfDay(for: message.timestamp)
        let now = Date()
        let startOfToday = cal.startOfDay(for: now)
        let dayDiff = cal.dateComponents([.day], from: startOfMsg, to: startOfToday).day ?? 0
        if dayDiff >= 1 && dayDiff <= 6 {
            return "\(fmts.weekday.string(from: message.timestamp)), \(fmts.time.string(from: message.timestamp))"
        }
        let sameYear = cal.component(.year, from: message.timestamp) == cal.component(.year, from: now)
        let formatter = sameYear ? fmts.dateSameYear : fmts.dateOtherYear
        return formatter.string(from: message.timestamp)
    }

    private func handleCopy() {
        onCopyMessage(message.content) {
            copyResetTask?.cancel()
            withAnimation(.easeOut(duration: 0.15)) {
                justCopied = true
            }
            copyResetTask = Task {
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(.easeIn(duration: 0.2)) {
                        justCopied = false
                    }
                }
            }
        }
    }
}

private struct TimelineDivider: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            line
            Text(verbatim: text)
                .font(BodyFont.system(size: 11.5, wght: 600))
                .foregroundColor(Color.gray(light: 0.45, dark: 0.55))
                .fixedSize()
            line
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: text))
    }

    private var line: some View {
        Rectangle()
            .fill(Color.overlay(0.08))
            .frame(height: 1)
    }
}

struct MessageActionIcon: View {
    enum Kind {
        case copy(showCheck: Bool)
        case pencil
        case branchArrows
        case system(String)
    }

    let kind: Kind
    let label: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.overlay(hovered ? 0.07 : 0))
                iconView
            }
            .frame(width: 27, height: 27)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.12)) { hovered = h }
        }
        .accessibilityLabel(Text(verbatim: label))
        .hoverHint(label)
    }

    @ViewBuilder
    private var iconView: some View {
        switch kind {
        case .copy(let showCheck):
            if showCheck {
                CheckIcon(size: 14.3)
                    .foregroundColor((hovered ? Color.gray(light: 0.12, dark: 0.94) : Color.gray(light: 0.27, dark: 0.78)))
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            } else {
                CopyIconViewSquircle(color: (hovered ? Color.gray(light: 0.17, dark: 0.88) : Color.gray(light: 0.45, dark: 0.55)), lineWidth: 0.85)
                    .frame(width: 14.3, height: 14.3)
                    .transition(.opacity)
            }
        case .pencil:
            PencilIconView(color: (hovered ? Color.gray(light: 0.17, dark: 0.88) : Color.gray(light: 0.45, dark: 0.55)), lineWidth: 0.85)
                .frame(width: 16.5, height: 16.5)
        case .branchArrows:
            BranchArrowsIconView(color: (hovered ? Color.gray(light: 0.17, dark: 0.88) : Color.gray(light: 0.45, dark: 0.55)), lineWidth: 0.85)
                .frame(width: 14.3, height: 14.3)
        case .system(let name):
            IconImage(name, size: 14.3)
                .foregroundColor((hovered ? Color.gray(light: 0.23, dark: 0.82) : Color.gray(light: 0.50, dark: 0.45)))
        }
    }
}

struct GoalMessageBadge: View {
    let label: String
    let icon: LucideIcon.Kind

    var body: some View {
        HStack(spacing: 4) {
            LucideIcon(icon, size: 11)
                .foregroundColor(Color.gray(light: 0.45, dark: 0.55))
            Text(verbatim: label)
                .font(BodyFont.system(size: 11, wght: 500))
                .foregroundColor(Color.gray(light: 0.45, dark: 0.55))
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: label))
    }
}


struct FileLinkPreview: Equatable {
    let visiblePaths: [String]
    let remainingCount: Int

    var isEmpty: Bool {
        visiblePaths.isEmpty
    }
}

enum AssistantFileLinkOutputs {
    static func paths(in message: ChatMessage) -> [String] {
        guard message.role == .assistant else { return [] }
        return paths(in: message.content)
    }

    static func paths(in text: String) -> [String] {
        var seen: Set<String> = []
        return AssistantMarkdown
            .extractLinkURLs(in: text)
            .filter(\.isFileURL)
            .map(\.path)
            .compactMap(previewableFileLinkPath)
            .filter {
                seen.insert($0).inserted
            }
    }

    private static func previewableFileLinkPath(_ path: String) -> String? {
        let normalized = stripLineColumnSuffix(from: path)
        guard !normalized.isEmpty else { return nil }
        let ext = URL(fileURLWithPath: normalized).pathExtension.lowercased()
        let previewableExtensions = [
            "md", "markdown", "mdx",
            "png", "jpg", "jpeg", "gif", "webp", "tiff", "tif", "heic"
        ]
        guard previewableExtensions.contains(ext) else { return nil }
        return normalized
    }

    private static func stripLineColumnSuffix(from path: String) -> String {
        var normalized = path
        for _ in 0..<2 {
            guard let colon = normalized.lastIndex(of: ":") else { break }
            if let slash = normalized.lastIndex(of: "/"), colon < slash {
                break
            }
            let suffix = normalized[normalized.index(after: colon)...]
            guard !suffix.isEmpty, suffix.allSatisfy(\.isNumber) else {
                break
            }
            normalized = String(normalized[..<colon])
        }
        return normalized
    }
}

final class FileLinkPreviewCache {
    static let shared = FileLinkPreviewCache()

    private var values: [Key: FileLinkPreview] = [:]
    private var order: [Key] = []
    private let limit = 256
    private let previewLimit = 3

    private init() {}

    func preview(for message: ChatMessage) -> FileLinkPreview {
        let key = Key(message: message)
        if let cached = values[key] {
            return cached
        }

        RenderProbe.mark(
            "FileLinkPreviewExtract",
            fields: [
                "message": message.id.uuidString,
                "bytes": "\(message.content.utf8.count)"
            ]
        )

        let paths = AssistantFileLinkOutputs.paths(in: message)
        let preview: FileLinkPreview
        if paths.count > previewLimit {
            preview = FileLinkPreview(
                visiblePaths: Array(paths.prefix(previewLimit)),
                remainingCount: paths.count - previewLimit
            )
        } else {
            preview = FileLinkPreview(visiblePaths: paths, remainingCount: 0)
        }
        store(preview, for: key)
        return preview
    }

    private func store(_ value: FileLinkPreview, for key: Key) {
        values[key] = value
        order.append(key)
        if order.count > limit {
            let removeCount = order.count - limit
            for old in order.prefix(removeCount) {
                values.removeValue(forKey: old)
            }
            order.removeFirst(removeCount)
        }
    }

    private struct Key: Hashable {
        let id: UUID
        let contentHash: Int

        init(message: ChatMessage) {
            id = message.id
            contentHash = message.content.hashValue
        }
    }
}

enum AssistantWebLinkPreviewPolicy {
    static func url(for message: ChatMessage) -> URL? {
        nil
    }
}
