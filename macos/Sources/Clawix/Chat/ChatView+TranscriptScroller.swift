import AppKit
import SwiftUI
import ClawixCore

struct ChatTranscriptScrollerView: View {
    let appState: AppState
    let chatId: UUID
    let chat: Chat
    @ObservedObject var transcript: ChatTranscriptStore
    let visibleMessageStores: [ChatMessageStore]
    let hiddenLocalMessageCount: Int
    @Binding var visibleMessageLimit: Int
    @Binding var lastLocalRevealAt: Date
    @Binding var bottomId: String?
    let closedMetadataReady: Bool
    let chatTailId: String
    let publishingReady: Bool

    /// True once the reader has scrolled meaningfully above the tail of
    /// an overflowing transcript; gates the scroll-to-bottom button.
    @State private var awayFromBottom = false
    @State private var revealAfterOlderPage = false
    @State private var messageFrames: [UUID: CGRect] = [:]
    @StateObject private var scrollViewBox = ChatScrollViewBox()

    private var bottomScrollBinding: Binding<String?> {
        Binding<String?>(
            get: { bottomId },
            set: { newValue in
                let normalized = newValue == chatTailId ? chatTailId : nil
                if bottomId != normalized {
                    bottomId = normalized
                }
            }
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 44) {
                    if appState.messagesPaginationByChat[chatId]?.loadingOlder == true {
                        HStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                            Spacer()
                        }
                        .frame(height: 28)
                        .transition(.opacity)
                    }
                    let lastUserMessageId = transcript.lastMessageId { $0.role == .user }
                    let lastAssistantMessageId = transcript.lastMessageId {
                        $0.role == .assistant && $0.streamingFinished && !$0.isError
                    }
                    let responseStreaming = isResponseStreaming(chat)
                    let activeFindQuery = appState.isFindBarOpen ? appState.findQuery : ""
                    ForEach(visibleMessageStores) { messageStore in
                        ChatMessageEntryView(
                            appState: appState,
                            chat: chat,
                            messageStore: messageStore,
                            lastUserMessageId: lastUserMessageId,
                            lastAssistantMessageId: lastAssistantMessageId,
                            responseStreaming: responseStreaming,
                            activeFindQuery: activeFindQuery,
                            closedMetadataReady: closedMetadataReady,
                            publishingReady: publishingReady,
                            proxy: proxy
                        )
                        .background(ChatMessageFrameProbe(id: messageStore.id))
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(chatTailId)
                }
                .frame(maxWidth: chatRailMaxWidth)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 12)
                .background {
                    ZStack {
                        ThinScrollerInstaller(
                            style: .clawixAlwaysVisible,
                            controlId: "chat.transcript.scroll"
                        )
                        ChatScrollViewLocator(box: scrollViewBox)
                    }
                    .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: ChatMessageFrameProbe.coordinateSpaceName)
            .onPreferenceChange(ChatMessageFramePreferenceKey.self) { frames in
                if messageFrames != frames {
                    messageFrames = frames
                }
            }
            .scrollPosition(id: bottomScrollBinding, anchor: .bottom)
            .modifier(ChatScrollDeclarativeAnchors())
            .modifier(ChatScrollUpSentinel(
                threshold: ChatView.loadOlderThreshold,
                onTrigger: {
                    handleScrollUpTrigger(proxy: proxy)
                }
            ))
            .modifier(ChatScrollBottomSentinel(
                threshold: 220,
                awayFromBottom: $awayFromBottom
            ))
            .overlay(alignment: .bottom) {
                if awayFromBottom {
                    ScrollToBottomButton {
                        returnToTail(proxy: proxy)
                    }
                    .padding(.bottom, 16)
                    .transition(.softNudge(y: 6))
                }
            }
            .animation(.easeOut(duration: 0.18), value: awayFromBottom)
            .onAppear {
                appState.ensureSelectedChat()
                visibleMessageLimit = ChatView.initialVisibleMessageLimit
                lastLocalRevealAt = .distantPast
                bottomId = chatTailId
                awayFromBottom = false
                markBottomAnchor("appear")
            }
            .onChange(of: chatId) { _, _ in
                appState.ensureSelectedChat()
                appState.requestComposerFocus()
                visibleMessageLimit = ChatView.initialVisibleMessageLimit
                lastLocalRevealAt = .distantPast
                bottomId = chatTailId
                awayFromBottom = false
                markBottomAnchor("chat-change")
            }
            .onChange(of: appState.currentFindIndex) { _, _ in
                scrollToCurrentFindMatch(proxy: proxy)
            }
            .onChange(of: appState.findMatches.count) { _, _ in
                scrollToCurrentFindMatch(proxy: proxy)
            }
            .onChange(of: transcript.messageIds.count) { _, _ in
                guard revealAfterOlderPage, hiddenLocalMessageCount > 0 else { return }
                revealAfterOlderPage = false
                lastLocalRevealAt = .distantPast
                RenderProbe.mark(
                    "ChatOlderHistoryRevealAfterPage",
                    fields: [
                        "chat": chatId.uuidString,
                        "hiddenBefore": "\(hiddenLocalMessageCount)",
                        "total": "\(transcript.messageIds.count)",
                        "visible": "\(visibleMessageLimit)"
                    ]
                )
                handleScrollUpTrigger(proxy: proxy)
            }
            .task(id: prewarmKey) {
                if visibleMessageStores.last?.message.streamingFinished == false {
                    RenderProbe.mark(
                        "MarkdownPrewarmSkippedActiveStream",
                        fields: [
                            "chat": chat.id.uuidString,
                            "visible": "\(visibleMessageStores.count)"
                        ]
                    )
                    return
                }
                if bottomId != chatTailId,
                   visibleMessageStores.count > ChatView.initialVisibleMessageLimit {
                    RenderProbe.mark(
                        "MarkdownPrewarmSkippedScrollback",
                        fields: [
                            "chat": chat.id.uuidString,
                            "hidden": "\(hiddenLocalMessageCount)",
                            "visible": "\(visibleMessageStores.count)"
                        ]
                    )
                    return
                }
                await ChatMarkdownPrewarmer.prewarm(
                    messages: visibleMessageStores.map(\.message),
                    timelineEntryLimit: 0
                )
            }
        }
    }

    private var prewarmKey: ChatMarkdownPrewarmKey {
        let lastMessage = visibleMessageStores.last?.message
        return ChatMarkdownPrewarmKey(
            chatId: chat.id,
            visibleMessageCount: visibleMessageStores.count,
            firstMessageId: visibleMessageStores.first?.id,
            lastMessageId: visibleMessageStores.last?.id,
            lastTimelineCount: lastMessage?.streamingFinished == false
                ? 0
                : lastMessage?.timeline.count ?? 0
        )
    }

    private func scrollToCurrentFindMatch(proxy: ScrollViewProxy) {
        guard appState.isFindBarOpen,
              appState.findChatId == chatId,
              let match = appState.currentFindMatch else { return }
        withAnimation(.easeOut(duration: 0.20)) {
            proxy.scrollTo(match.messageId, anchor: .center)
        }
    }

    /// Snaps the transcript back to its tail and re-arms the bottom
    /// anchor so subsequent streaming keeps following the bottom.
    private func returnToTail(proxy: ScrollViewProxy) {
        awayFromBottom = false
        bottomId = chatTailId
        markBottomAnchor("return-to-tail")
        withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo(chatTailId, anchor: .bottom)
        }
    }

    private func handleScrollUpTrigger(proxy: ScrollViewProxy) {
        if hiddenLocalMessageCount > 0 {
            let now = Date()
            guard now.timeIntervalSince(lastLocalRevealAt) >= ChatView.localRevealThrottle else {
                return
            }
            lastLocalRevealAt = now
            guard let anchorId = currentScrollAnchorMessageId(),
                  let anchorFrameBefore = messageFrames[anchorId] else {
                RenderProbe.mark(
                    "ChatOlderHistoryRevealAnchorUnavailable",
                    fields: [
                        "chat": chatId.uuidString,
                        "frames": "\(messageFrames.count)",
                        "visible": "\(visibleMessageStores.count)"
                    ]
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    lastLocalRevealAt = .distantPast
                    handleScrollUpTrigger(proxy: proxy)
                }
                return
            }
            bottomId = nil
            RenderProbe.mark(
                "ChatOlderHistoryRevealStart",
                fields: [
                    "anchor": anchorId.uuidString,
                    "bottomArmed": "false",
                    "chat": chatId.uuidString,
                    "frameMinY": Self.format(anchorFrameBefore.minY),
                    "fromVisible": "\(visibleMessageLimit)",
                    "hiddenBefore": "\(hiddenLocalMessageCount)",
                    "last": visibleMessageStores.last?.id.uuidString ?? "none",
                    "total": "\(transcript.messageIds.count)"
                ]
            )
            let nextVisibleLimit = min(
                transcript.messageIds.count,
                visibleMessageLimit + ChatView.visibleMessagePageSize
            )
            let exhaustedLocalWindow = nextVisibleLimit >= transcript.messageIds.count
            visibleMessageLimit = nextVisibleLimit
            DispatchQueue.main.async {
                restoreScrollAnchor(anchorId: anchorId, before: anchorFrameBefore)
                RenderProbe.mark(
                    "ChatOlderHistoryRevealAnchored",
                    fields: [
                        "anchor": anchorId.uuidString,
                        "chat": chatId.uuidString,
                        "last": visibleMessageStores.last?.id.uuidString ?? "none",
                        "toVisible": "\(visibleMessageLimit)"
                    ]
                )
                recordAnchorShift(
                    anchorId: anchorId,
                    before: anchorFrameBefore,
                    phase: "immediate"
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    restoreScrollAnchor(anchorId: anchorId, before: anchorFrameBefore)
                    recordAnchorShift(
                        anchorId: anchorId,
                        before: anchorFrameBefore,
                        phase: "settled"
                    )
                    if exhaustedLocalWindow {
                        revealAfterOlderPage = true
                        RenderProbe.mark(
                            "ChatOlderHistoryRequestAfterLocalReveal",
                            fields: [
                                "anchor": anchorId.uuidString,
                                "chat": chatId.uuidString,
                                "visible": "\(nextVisibleLimit)"
                            ]
                        )
                        appState.requestOlderIfNeeded(chatId: chatId)
                    } else if isNearTopOfTranscript() {
                        RenderProbe.mark(
                            "ChatOlderHistoryRevealContinuedAtTop",
                            fields: [
                                "chat": chatId.uuidString,
                                "hidden": "\(hiddenLocalMessageCount)",
                                "visible": "\(visibleMessageLimit)"
                            ]
                        )
                        DispatchQueue.main.asyncAfter(deadline: .now() + ChatView.localRevealThrottle) {
                            lastLocalRevealAt = .distantPast
                            handleScrollUpTrigger(proxy: proxy)
                        }
                    }
                }
            }
        } else {
            appState.requestOlderIfNeeded(chatId: chatId)
        }
    }

    private func markBottomAnchor(_ reason: String) {
        RenderProbe.mark(
            "ChatBottomAnchorArmed",
            fields: [
                "bottomId": bottomId ?? "nil",
                "chat": chatId.uuidString,
                "reason": reason,
                "tail": chatTailId
            ]
        )
    }

    private func isResponseStreaming(_ chat: Chat) -> Bool {
        if let lastAssistant = transcript.lastMessage(where: { $0.role == .assistant }) {
            return !lastAssistant.streamingFinished
        }
        return chat.hasActiveTurn
    }

    private func isNearTopOfTranscript() -> Bool {
        guard let scrollView = scrollViewBox.scrollView else { return false }
        return scrollView.contentView.bounds.origin.y <= ChatView.loadOlderThreshold + 1
    }

    private func currentScrollAnchorMessageId() -> UUID? {
        let candidates = visibleMessageStores.compactMap { store -> (id: UUID, minY: CGFloat)? in
            guard let frame = messageFrames[store.id] else { return nil }
            return (store.id, frame.minY)
        }
        return candidates.min { abs($0.minY) < abs($1.minY) }?.id
    }

    private func recordAnchorShift(anchorId: UUID, before: CGRect?, phase: String) {
        guard let before else {
            RenderProbe.mark(
                "ChatOlderHistoryAnchorShift",
                fields: [
                    "anchor": anchorId.uuidString,
                    "chat": chatId.uuidString,
                    "phase": phase,
                    "status": "missing-before"
                ]
            )
            return
        }
        guard let after = messageFrames[anchorId] else {
            RenderProbe.mark(
                "ChatOlderHistoryAnchorShift",
                fields: [
                    "anchor": anchorId.uuidString,
                    "beforeMinY": Self.format(before.minY),
                    "chat": chatId.uuidString,
                    "phase": phase,
                    "status": "missing-after"
                ]
            )
            return
        }
        let deltaY = after.minY - before.minY
        RenderProbe.mark(
            "ChatOlderHistoryAnchorShift",
            fields: [
                "afterMinY": Self.format(after.minY),
                "anchor": anchorId.uuidString,
                "beforeMinY": Self.format(before.minY),
                "chat": chatId.uuidString,
                "deltaY": Self.format(deltaY),
                "phase": phase,
                "status": "measured"
            ]
        )
    }

    private func restoreScrollAnchor(anchorId: UUID, before: CGRect?) {
        guard let before else {
            RenderProbe.mark(
                "ChatOlderHistoryScrollAnchorPreserved",
                fields: [
                    "anchor": anchorId.uuidString,
                    "chat": chatId.uuidString,
                    "status": "missing-before"
                ]
            )
            return
        }
        guard let scrollView = scrollViewBox.scrollView,
              let documentView = scrollView.documentView else {
            RenderProbe.mark(
                "ChatOlderHistoryScrollAnchorPreserved",
                fields: [
                    "anchor": anchorId.uuidString,
                    "chat": chatId.uuidString,
                    "status": "missing-scroll-view"
                ]
            )
            return
        }
        guard let after = messageFrames[anchorId] else {
            RenderProbe.mark(
                "ChatOlderHistoryScrollAnchorPreserved",
                fields: [
                    "anchor": anchorId.uuidString,
                    "chat": chatId.uuidString,
                    "status": "missing-after"
                ]
            )
            return
        }

        let deltaY = after.minY - before.minY
        scrollView.layoutSubtreeIfNeeded()
        documentView.layoutSubtreeIfNeeded()
        let beforeOrigin = scrollView.contentView.bounds.origin
        let visibleHeight = scrollView.contentView.bounds.height
        let maxY = max(0, documentView.bounds.height - visibleHeight)
        var nextOrigin = beforeOrigin
        nextOrigin.y += deltaY
        nextOrigin.y = min(max(0, nextOrigin.y), maxY)
        if abs(nextOrigin.y - beforeOrigin.y) > 0.5 {
            scrollView.contentView.scroll(to: nextOrigin)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            scrollView.layoutSubtreeIfNeeded()
        }

        RenderProbe.mark(
            "ChatOlderHistoryScrollAnchorPreserved",
            fields: [
                "adjustedBy": Self.format(nextOrigin.y - beforeOrigin.y),
                "anchor": anchorId.uuidString,
                "beforeOriginY": Self.format(beforeOrigin.y),
                "chat": chatId.uuidString,
                "deltaY": Self.format(deltaY),
                "documentFlipped": "\(documentView.isFlipped)",
                "maxY": Self.format(maxY),
                "status": "preserved"
            ]
        )
    }

    fileprivate static func format(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
    }
}

private struct ChatMessageFrameProbe: View {
    static let coordinateSpaceName = "ChatTranscriptViewport"

    let id: UUID

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: ChatMessageFramePreferenceKey.self,
                value: [id: proxy.frame(in: .named(Self.coordinateSpaceName))]
            )
        }
    }
}

private struct ChatMessageFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private final class ChatScrollViewBox: ObservableObject {
    weak var scrollView: NSScrollView?
}

private struct ChatScrollViewLocator: NSViewRepresentable {
    @ObservedObject var box: ChatScrollViewBox

    func makeNSView(context: Context) -> ChatScrollViewLocatorView {
        ChatScrollViewLocatorView(box: box)
    }

    func updateNSView(_ nsView: ChatScrollViewLocatorView, context: Context) {
        nsView.box = box
        nsView.locateIfNeeded()
    }
}

private final class ChatScrollViewLocatorView: NSView {
    weak var box: ChatScrollViewBox?

    init(box: ChatScrollViewBox) {
        self.box = box
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            self?.locateIfNeeded()
        }
    }

    func locateIfNeeded() {
        var current: NSView? = superview
        while let view = current {
            if let scrollView = view as? NSScrollView {
                box?.scrollView = scrollView
                return
            }
            current = view.superview
        }
    }
}
