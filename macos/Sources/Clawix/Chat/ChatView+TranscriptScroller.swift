import AppKit
import SwiftUI
import ClawixCore

/// The minimal value that, when it changes, must re-run the find-match scroll.
/// Threaded from `ChatView` (which observes the narrow shell observer) so the
/// scroller reacts to find navigation without observing the god object.
struct ChatFindReactivityKey: Equatable {
    let isFindBarOpen: Bool
    let findChatId: UUID?
    let findQuery: String
    let currentFindIndex: Int
    let matchCount: Int
}

struct ChatTranscriptEmptyStatePresentation: Equatable {
    enum Kind: Equatable {
        case loading
        case empty
    }

    let kind: Kind
    let message: String
    let showsProgress: Bool
    let controlRole: String

    static func make(
        messageCount: Int,
        historyHydrated: Bool,
        hasHistorySource: Bool
    ) -> ChatTranscriptEmptyStatePresentation? {
        guard messageCount == 0, hasHistorySource else { return nil }
        if historyHydrated {
            return ChatTranscriptEmptyStatePresentation(
                kind: .empty,
                message: UserFacingEmptyState.chatTranscriptEmpty.message,
                showsProgress: false,
                controlRole: "status"
            )
        }
        return nil
    }
}

struct ChatTranscriptScrollerView: View {
    let appState: AppState
    let chatId: UUID
    let chat: Chat
    @ObservedObject var transcript: ChatTranscriptStore
    @ObservedObject var paginationStore: AppState.ChatPaginationStore
    /// The session compute layer for this open chat (ADR 0042). Threaded down so
    /// each row sources its precomputed draw-only model from it.
    @ObservedObject var presentation: SessionPresentationStore
    let visibleMessageStores: [ChatMessageStore]
    let hiddenLocalMessageCount: Int
    @Binding var visibleMessageLimit: Int
    @Binding var visibleMessageEndOffset: Int
    let newerLocalMessageCount: Int
    @Binding var lastLocalRevealAt: Date
    @Binding var bottomId: String?
    let chatTailId: String
    let publishingReady: Bool
    /// Find-bar state, threaded from `ChatView` (which observes the narrow shell
    /// observer) instead of read off the non-observed `appState`, so find
    /// navigation re-evaluates this scroller. The authoritative match value is
    /// still resolved from `appState` at trigger time.
    let activeFindQuery: String
    let findReactivityKey: ChatFindReactivityKey

    /// True once the reader has scrolled meaningfully above the tail of
    /// an overflowing transcript; gates the scroll-to-bottom button.
    @State private var awayFromBottom = false
    @State private var revealAfterOlderPage = false
    @State private var messageFrames: [UUID: CGRect] = [:]
    @State private var olderAnchorProbeSequence = 0
    @State private var deferredOlderPageRequest: Task<Void, Never>?

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

    private var canTriggerOlderHistory: Bool {
        if hiddenLocalMessageCount > 0 { return true }
        return canRequestOlderPage
    }

    private var canRequestOlderPage: Bool {
        guard let pagination = paginationStore.values[chatId] else { return false }
        return pagination.hasMore
            && !pagination.loadingOlder
            && pagination.oldestKnownId != nil
    }

    private var emptyState: ChatTranscriptEmptyStatePresentation? {
        ChatTranscriptEmptyStatePresentation.make(
            messageCount: transcript.messageIds.count,
            historyHydrated: chat.historyHydrated,
            hasHistorySource: chat.clawixThreadId != nil || chat.rolloutPath != nil
        )
    }

    private var shouldArmBottomAnchorOnMount: Bool {
        isResponseStreaming(chat)
            || chat.hasActiveTurn
            || visibleMessageStores.count > 3
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 44) {
                        if let emptyState {
                            ChatTranscriptEmptyStateView(presentation: emptyState)
                                .frame(maxWidth: .infinity, minHeight: 360, alignment: .center)
                                .transition(.opacity)
                        }
                        if paginationStore.values[chatId]?.loadingOlder == true {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .controlSize(.small)
                                Spacer()
                            }
                            .frame(height: 28)
                            .transition(.opacity)
                            .clxControl("app.loadingState", role: "loader", label: "Loading older messages")
                        }
                        let lastUserMessageId = transcript.lastMessageId { $0.role == .user }
                        let lastAssistantMessageId = transcript.lastMessageId {
                            $0.role == .assistant && $0.streamingFinished && !$0.isError
                        }
                        let responseStreaming = isResponseStreaming(chat)
                        ForEach(visibleMessageStores) { messageStore in
                            ChatMessageEntryView(
                                appState: appState,
                                chat: chat,
                                messageStore: messageStore,
                                presentation: presentation,
                                lastUserMessageId: lastUserMessageId,
                                lastAssistantMessageId: lastAssistantMessageId,
                                responseStreaming: responseStreaming,
                                activeFindQuery: activeFindQuery,
                                publishingReady: publishingReady,
                                proxy: proxy
                            )
                            .background {
                                ZStack {
                                    ChatMessageFrameProbe(id: messageStore.id)
                                    ChatMessageNativeFrameProbe(id: messageStore.id)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(chatId)
                    Color.clear
                        .frame(height: CGFloat(newerLocalMessageCount) * ChatView.virtualizedTranscriptRowEstimate)
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
                        ChatTopScrollTriggerInstaller(
                            controlId: "chat.transcript.scroll",
                            isEnabled: canTriggerOlderHistory
                        ) {
                            handleScrollUpTrigger(proxy: proxy)
                        }
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
                isEnabled: canTriggerOlderHistory,
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
            .clxControl("chat.transcript.scroll", role: "scroll", label: "Chat transcript")
            .onAppear {
                appState.hydrateInitialTailForNavigation(chatId: chatId)
                resetInitialWindowState(reason: "appear")
            }
            .onChange(of: chatId) { _, _ in
                deferredOlderPageRequest?.cancel()
                deferredOlderPageRequest = nil
                appState.hydrateInitialTailForNavigation(chatId: chatId)
                appState.requestComposerFocus()
                resetInitialWindowState(reason: "chat-change")
            }
            .onDisappear {
                deferredOlderPageRequest?.cancel()
                deferredOlderPageRequest = nil
            }
            .onChange(of: findReactivityKey) { _, _ in
                scrollToCurrentFindMatch(proxy: proxy)
            }
            .onChange(of: transcript.messageIds.count) { oldCount, newCount in
                guard revealAfterOlderPage, hiddenLocalMessageCount > 0 else { return }
                revealAfterOlderPage = false
                lastLocalRevealAt = .distantPast
                RenderProbe.mark(
                    "ChatOlderPageInsertionObserved",
                    fields: [
                        "chat": chatId.uuidString,
                        "hiddenBefore": "\(hiddenLocalMessageCount)",
                        "inserted": "\(max(0, newCount - oldCount))",
                        "oldTotal": "\(oldCount)",
                        "total": "\(newCount)",
                        "visible": "\(visibleMessageLimit)"
                    ]
                    .merging(rowProbeFields()) { current, _ in current }
                    .merging(scrollProbeFields(prefix: "scroll")) { current, _ in current }
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
        visibleMessageLimit = ChatView.initialVisibleMessageLimit
        visibleMessageEndOffset = 0
        bottomId = chatTailId
        markBottomAnchor("return-to-tail")
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(chatTailId, anchor: .bottom)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                scrollNativeToBottom(reason: "return-to-tail-settled")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.90) {
                scrollNativeToBottom(reason: "return-to-tail-layout-final")
            }
        }
    }

    private func scrollNativeToBottom(reason: String) {
        guard let scrollView = ClxScrollRegistry.shared.get("chat.transcript.scroll"),
              let documentView = scrollView.documentView else {
            return
        }
        scrollView.layoutSubtreeIfNeeded()
        documentView.layoutSubtreeIfNeeded()
        let clipView = scrollView.contentView
        let visibleSize = clipView.bounds.size
        let documentSize = documentView.bounds.size
        let maxY = max(0, documentSize.height - visibleSize.height)
        clipView.scroll(to: CGPoint(x: clipView.bounds.origin.x, y: maxY))
        scrollView.reflectScrolledClipView(clipView)
        RenderProbe.mark(
            "ChatNativeScrollToBottom",
            fields: [
                "chat": chatId.uuidString,
                "maxY": Self.format(maxY),
                "reason": reason
            ].merging(scrollProbeFields(prefix: "tail")) { current, _ in current }
        )
    }

    private func resetInitialWindowState(reason: String) {
        if visibleMessageLimit != ChatView.initialVisibleMessageLimit {
            visibleMessageLimit = ChatView.initialVisibleMessageLimit
        }
        if visibleMessageEndOffset != 0 {
            visibleMessageEndOffset = 0
        }
        if lastLocalRevealAt != .distantPast {
            lastLocalRevealAt = .distantPast
        }
        let targetBottomId = shouldArmBottomAnchorOnMount ? chatTailId : nil
        if bottomId != targetBottomId {
            bottomId = targetBottomId
            markBottomAnchor(reason)
        }
        if awayFromBottom {
            awayFromBottom = false
        }
    }

    private func handleScrollUpTrigger(proxy: ScrollViewProxy) {
        if hiddenLocalMessageCount > 0 {
            let now = Date()
            guard now.timeIntervalSince(lastLocalRevealAt) >= ChatView.localRevealThrottle else {
                return
            }
            lastLocalRevealAt = now
            let anchorId = currentScrollAnchorMessageId()
            let anchorFrameBefore = anchorId.flatMap { messageFrames[$0] }
            let nativeAnchorFrameBefore = anchorId.flatMap { nativeMessageFrame(id: $0) }
            olderAnchorProbeSequence += 1
            let probeId = olderAnchorProbeSequence
            let oldVisibleLimit = visibleMessageLimit
            let oldEndOffset = visibleMessageEndOffset
            bottomId = nil
            RenderProbe.mark(
                "ChatOlderAnchorProbeStart",
                fields: [
                    "anchor": anchorId?.uuidString ?? "none",
                    "bottomArmed": "false",
                    "chat": chatId.uuidString,
                    "endOffset": "\(oldEndOffset)",
                    "fromVisible": "\(oldVisibleLimit)",
                    "hiddenBefore": "\(hiddenLocalMessageCount)",
                    "last": visibleMessageStores.last?.id.uuidString ?? "none",
                    "probe": "\(probeId)",
                    "total": "\(transcript.messageIds.count)",
                    "nativeYBefore": nativeAnchorFrameBefore.map { Self.format($0.minY) } ?? "none",
                    "yBefore": anchorFrameBefore.map { Self.format($0.minY) } ?? "none"
                ]
                .merging(rowProbeFields()) { current, _ in current }
                .merging(scrollProbeFields(prefix: "before")) { current, _ in current }
            )
            let insertedOlderRows = min(hiddenLocalMessageCount, ChatView.visibleMessagePageSize)
            let canMountContiguousWindow = visibleMessageLimit + visibleMessageEndOffset + insertedOlderRows
                <= ChatView.maxMountedScrollbackMessages
            let absorbedNewerRows: Int
            if canMountContiguousWindow {
                absorbedNewerRows = visibleMessageEndOffset
                visibleMessageLimit = min(
                    transcript.messageIds.count,
                    visibleMessageLimit + visibleMessageEndOffset + insertedOlderRows
                )
                visibleMessageEndOffset = 0
            } else {
                absorbedNewerRows = 0
                visibleMessageEndOffset = min(
                    max(0, transcript.messageIds.count - max(1, visibleMessageLimit)),
                    visibleMessageEndOffset + insertedOlderRows
                )
            }
            let exhaustedLocalWindow = hiddenLocalMessageCount - insertedOlderRows <= 0
            let insertedLocalRows = insertedOlderRows
            if let anchorId {
                DispatchQueue.main.async {
                    RenderProbe.mark(
                        "ChatOlderAnchorProbeInserted",
                        fields: [
                            "absorbedNewerRows": "\(absorbedNewerRows)",
                            "anchor": anchorId.uuidString,
                            "chat": chatId.uuidString,
                            "endOffset": "\(visibleMessageEndOffset)",
                            "insertedLocalRows": "\(insertedLocalRows)",
                            "last": visibleMessageStores.last?.id.uuidString ?? "none",
                            "probe": "\(probeId)",
                            "toVisible": "\(visibleMessageLimit)"
                        ]
                        .merging(rowProbeFields()) { current, _ in current }
                        .merging(scrollProbeFields(prefix: "afterInsert")) { current, _ in current }
                    )
                    recordAnchorShift(
                        anchorId: anchorId,
                        before: anchorFrameBefore,
                        nativeBefore: nativeAnchorFrameBefore,
                        phase: "immediate",
                        probeId: probeId,
                        insertedRows: insertedLocalRows
                    )
                    restoreNativeAnchorIfNeeded(
                        anchorId: anchorId,
                        nativeBefore: nativeAnchorFrameBefore,
                        phase: "immediate",
                        probeId: probeId,
                        insertedRows: insertedLocalRows
                    )
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        restoreNativeAnchorIfNeeded(
                            anchorId: anchorId,
                            nativeBefore: nativeAnchorFrameBefore,
                            phase: "settled",
                            probeId: probeId,
                            insertedRows: insertedLocalRows
                        )
                        recordAnchorShift(
                            anchorId: anchorId,
                            before: anchorFrameBefore,
                            nativeBefore: nativeAnchorFrameBefore,
                            phase: "settled",
                            probeId: probeId,
                            insertedRows: insertedLocalRows
                        )
                    }
                    if exhaustedLocalWindow, canRequestOlderPage {
                        revealAfterOlderPage = true
                        RenderProbe.mark(
                            "ChatOlderHistoryRequestAfterLocalReveal",
                            fields: [
                                "anchor": anchorId.uuidString,
                                "chat": chatId.uuidString,
                                "endOffset": "\(visibleMessageEndOffset)",
                                "probe": "\(probeId)",
                                "visible": "\(visibleMessageLimit)"
                            ]
                            .merging(rowProbeFields()) { current, _ in current }
                            .merging(scrollProbeFields(prefix: "request")) { current, _ in current }
                        )
                        appState.requestOlderIfNeeded(chatId: chatId)
                    }
                }
            }
        } else {
            guard canRequestOlderPage else { return }
            RenderProbe.mark(
                "ChatOlderAnchorProbeRequestOnly",
                fields: [
                    "chat": chatId.uuidString,
                    "total": "\(transcript.messageIds.count)",
                    "visible": "\(visibleMessageLimit)"
                ]
                .merging(rowProbeFields()) { current, _ in current }
                .merging(scrollProbeFields(prefix: "request")) { current, _ in current }
            )
            scheduleDeferredOlderPageRequest()
        }
    }

    private func scheduleDeferredOlderPageRequest() {
        deferredOlderPageRequest?.cancel()
        let targetChatId = chatId
        RenderProbe.mark(
            "ChatOlderPageRequestDeferred",
            fields: [
                "chat": targetChatId.uuidString
            ].merging(scrollProbeFields(prefix: "defer")) { current, _ in current }
        )
        deferredOlderPageRequest = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 320_000_000)
            guard !Task.isCancelled else { return }
            guard case let .chat(currentChatId) = appState.currentRoute,
                  currentChatId == targetChatId,
                  let pagination = appState.messagesPaginationByChat[targetChatId],
                  pagination.hasMore,
                  !pagination.loadingOlder,
                  pagination.oldestKnownId != nil
            else { return }
            guard isStillNearTopForDeferredOlderRequest() else {
                RenderProbe.mark(
                    "ChatOlderPageRequestDeferredSkipped",
                    fields: [
                        "chat": targetChatId.uuidString,
                        "reason": "not-near-top"
                    ].merging(scrollProbeFields(prefix: "deferSkip")) { current, _ in current }
                )
                return
            }
            RenderProbe.mark(
                "ChatOlderPageRequestDeferredFire",
                fields: [
                    "chat": targetChatId.uuidString
                ].merging(scrollProbeFields(prefix: "deferFire")) { current, _ in current }
            )
            appState.requestOlderIfNeeded(chatId: targetChatId)
        }
    }

    private func isStillNearTopForDeferredOlderRequest() -> Bool {
        guard let scrollView = ClxScrollRegistry.shared.get("chat.transcript.scroll"),
              let documentView = scrollView.documentView
        else { return true }
        scrollView.layoutSubtreeIfNeeded()
        documentView.layoutSubtreeIfNeeded()
        let clipView = scrollView.contentView
        let origin = clipView.bounds.origin
        let visibleSize = clipView.bounds.size
        let documentSize = documentView.bounds.size
        let maxY = max(0, documentSize.height - visibleSize.height)
        let topDistance = documentView.isFlipped ? origin.y : maxY - origin.y
        return maxY <= 0.5 || topDistance <= ChatView.loadOlderThreshold
    }

    private func restoreNativeAnchorIfNeeded(
        anchorId: UUID,
        nativeBefore: CGRect?,
        phase: String,
        probeId: Int,
        insertedRows: Int
    ) {
        guard let nativeBefore,
              let scrollView = ClxScrollRegistry.shared.get("chat.transcript.scroll"),
              let documentView = scrollView.documentView
        else {
            RenderProbe.mark(
                "ChatOlderNativeAnchorRestoreSkipped",
                fields: [
                    "anchor": anchorId.uuidString,
                    "chat": chatId.uuidString,
                    "insertedRows": "\(insertedRows)",
                    "phase": phase,
                    "probe": "\(probeId)",
                    "reason": nativeBefore == nil ? "missing-before" : "missing-scroll"
                ]
            )
            return
        }

        scrollView.layoutSubtreeIfNeeded()
        documentView.layoutSubtreeIfNeeded()
        guard let nativeAfter = nativeMessageFrame(id: anchorId) else {
            RenderProbe.mark(
                "ChatOlderNativeAnchorRestoreSkipped",
                fields: [
                    "anchor": anchorId.uuidString,
                    "chat": chatId.uuidString,
                    "insertedRows": "\(insertedRows)",
                    "phase": phase,
                    "probe": "\(probeId)",
                    "reason": "missing-after"
                ].merging(scrollProbeFields(prefix: "restore")) { current, _ in current }
            )
            return
        }

        let deltaY = nativeAfter.minY - nativeBefore.minY
        guard abs(deltaY) > 0.5 else {
            RenderProbe.mark(
                "ChatOlderNativeAnchorRestore",
                fields: [
                    "anchor": anchorId.uuidString,
                    "chat": chatId.uuidString,
                    "deltaPx": Self.format(deltaY),
                    "insertedRows": "\(insertedRows)",
                    "phase": phase,
                    "probe": "\(probeId)",
                    "status": "already-stable"
                ].merging(scrollProbeFields(prefix: "restore")) { current, _ in current }
            )
            return
        }

        let clipView = scrollView.contentView
        let oldOrigin = clipView.bounds.origin
        let visibleSize = clipView.bounds.size
        let documentSize = documentView.bounds.size
        let maxY = max(0, documentSize.height - visibleSize.height)
        let targetY = min(max(oldOrigin.y + deltaY, 0), maxY)
        let targetOrigin = CGPoint(x: oldOrigin.x, y: targetY)
        clipView.scroll(to: targetOrigin)
        scrollView.reflectScrolledClipView(clipView)
        scrollView.layoutSubtreeIfNeeded()
        documentView.layoutSubtreeIfNeeded()
        let correctedAfter = nativeMessageFrame(id: anchorId)
        RenderProbe.mark(
            "ChatOlderNativeAnchorRestore",
            fields: [
                "anchor": anchorId.uuidString,
                "chat": chatId.uuidString,
                "correctedDeltaPx": correctedAfter.map { Self.format($0.minY - nativeBefore.minY) } ?? "missing",
                "deltaPx": Self.format(deltaY),
                "insertedRows": "\(insertedRows)",
                "oldY": Self.format(oldOrigin.y),
                "phase": phase,
                "probe": "\(probeId)",
                "status": "corrected",
                "targetY": Self.format(targetY)
            ].merging(scrollProbeFields(prefix: "restore")) { current, _ in current }
        )
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

    private func currentScrollAnchorMessageId() -> UUID? {
        if let scrollView = ClxScrollRegistry.shared.get("chat.transcript.scroll") {
            let nativeCandidates = visibleMessageStores.compactMap { store -> (id: UUID, minY: CGFloat)? in
                guard let frame = ChatMessageNativeFrameRegistry.shared.frame(
                    id: store.id,
                    in: scrollView
                ) else { return nil }
                return (store.id, frame.minY)
            }
            if let nativeAnchor = nativeCandidates.min(by: { abs($0.minY) < abs($1.minY) })?.id {
                return nativeAnchor
            }
        }
        let candidates = visibleMessageStores.compactMap { store -> (id: UUID, minY: CGFloat)? in
            guard let frame = messageFrames[store.id] else { return nil }
            return (store.id, frame.minY)
        }
        return candidates.min { abs($0.minY) < abs($1.minY) }?.id
            ?? visibleMessageStores.first?.id
    }

    private func recordAnchorShift(
        anchorId: UUID,
        before: CGRect?,
        nativeBefore: CGRect?,
        phase: String,
        probeId: Int,
        insertedRows: Int
    ) {
        var fields = [
            "anchor": anchorId.uuidString,
            "chat": chatId.uuidString,
            "hitch100": "\(RenderProbe.snapshotCounts()["hitch>100ms"] ?? 0)",
            "hitch250": "\(RenderProbe.snapshotCounts()["hitch>250ms"] ?? 0)",
            "hitch33": "\(RenderProbe.snapshotCounts()["hitch>33ms"] ?? 0)",
            "insertedRows": "\(insertedRows)",
            "phase": phase,
            "probe": "\(probeId)"
        ]
        .merging(rowProbeFields()) { current, _ in current }
        .merging(scrollProbeFields(prefix: "after")) { current, _ in current }
        if let nativeBefore {
            fields["nativeYBefore"] = Self.format(nativeBefore.minY)
            if let nativeAfter = nativeMessageFrame(id: anchorId) {
                fields["nativeDeltaPx"] = Self.format(nativeAfter.minY - nativeBefore.minY)
                fields["nativeStatus"] = "measured"
                fields["nativeYAfter"] = Self.format(nativeAfter.minY)
            } else {
                fields["nativeStatus"] = "missing-after"
            }
        } else {
            fields["nativeStatus"] = "missing-before"
        }
        guard let before else {
            fields["status"] = "missing-before"
            RenderProbe.mark("ChatOlderAnchorProbeDelta", fields: fields)
            return
        }
        guard let after = messageFrames[anchorId] else {
            fields["status"] = "missing-after"
            fields["yBefore"] = Self.format(before.minY)
            RenderProbe.mark("ChatOlderAnchorProbeDelta", fields: fields)
            return
        }
        let deltaY = after.minY - before.minY
        fields["deltaPx"] = Self.format(deltaY)
        fields["status"] = "measured"
        fields["yAfter"] = Self.format(after.minY)
        fields["yBefore"] = Self.format(before.minY)
        RenderProbe.mark("ChatOlderAnchorProbeDelta", fields: fields)
    }

    private func nativeMessageFrame(id: UUID) -> CGRect? {
        guard let scrollView = ClxScrollRegistry.shared.get("chat.transcript.scroll") else { return nil }
        return ChatMessageNativeFrameRegistry.shared.frame(id: id, in: scrollView)
    }

    private func scrollProbeFields(prefix: String) -> [String: String] {
        guard let scrollView = ClxScrollRegistry.shared.get("chat.transcript.scroll"),
              let documentView = scrollView.documentView
        else { return ["\(prefix)Scroll": "unavailable"] }
        scrollView.layoutSubtreeIfNeeded()
        documentView.layoutSubtreeIfNeeded()
        let clipView = scrollView.contentView
        let origin = clipView.bounds.origin
        let documentSize = documentView.bounds.size
        let visibleSize = clipView.bounds.size
        let maxY = max(0, documentSize.height - visibleSize.height)
        return [
            "\(prefix)DocH": Self.format(documentSize.height),
            "\(prefix)Flipped": "\(documentView.isFlipped)",
            "\(prefix)MaxY": Self.format(maxY),
            "\(prefix)VisibleH": Self.format(visibleSize.height),
            "\(prefix)Y": Self.format(origin.y)
        ]
    }

    private func rowProbeFields() -> [String: String] {
        [
            "measuredRows": "\(messageFrames.count)",
            "mountedRows": "\(ChatMessageNativeFrameRegistry.shared.mountedCount)",
            "newerLocalRows": "\(newerLocalMessageCount)",
            "renderWindowRows": "\(visibleMessageStores.count)"
        ]
    }

    private static func format(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
    }
}

private struct ChatTranscriptEmptyStateView: View {
    let presentation: ChatTranscriptEmptyStatePresentation

    var body: some View {
        VStack(spacing: 10) {
            if presentation.showsProgress {
                ProgressView()
                    .controlSize(.small)
            }
            Text(presentation.message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .clxControl(
            "chat.transcript.emptyState",
            role: presentation.controlRole,
            label: presentation.message
        )
    }
}

private struct ChatMessageFrameProbe: View {
    static let coordinateSpaceName = "ChatTranscriptViewport"

    let id: UUID

    var body: some View {
        if RenderProbe.isEnabled, ClxAgentInstance.isAgent {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ChatMessageFramePreferenceKey.self,
                    value: [id: proxy.frame(in: .named(Self.coordinateSpaceName))]
                )
            }
        } else {
            EmptyView()
        }
    }
}

private struct ChatMessageFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct ChatMessageNativeFrameProbe: NSViewRepresentable {
    let id: UUID

    func makeNSView(context: Context) -> ChatMessageNativeFrameProbeView {
        ChatMessageNativeFrameProbeView(id: id)
    }

    func updateNSView(_ nsView: ChatMessageNativeFrameProbeView, context: Context) {
        nsView.update(id: id)
    }

    static func dismantleNSView(_ nsView: ChatMessageNativeFrameProbeView, coordinator: ()) {
        ChatMessageNativeFrameRegistry.shared.remove(id: nsView.id, view: nsView)
    }
}

private final class ChatMessageNativeFrameProbeView: NSView {
    private(set) var id: UUID

    init(id: UUID) {
        self.id = id
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(id nextId: UUID) {
        guard id != nextId else {
            register()
            return
        }
        ChatMessageNativeFrameRegistry.shared.remove(id: id, view: self)
        id = nextId
        register()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        register()
    }

    private func register() {
        guard window != nil else { return }
        ChatMessageNativeFrameRegistry.shared.upsert(id: id, view: self)
    }
}

private final class ChatMessageNativeFrameRegistry {
    static let shared = ChatMessageNativeFrameRegistry()

    private final class WeakView {
        weak var value: NSView?
        init(_ value: NSView) {
            self.value = value
        }
    }

    private var views: [UUID: WeakView] = [:]

    private init() {}

    var mountedCount: Int {
        views = views.filter { $0.value.value != nil }
        return views.count
    }

    func upsert(id: UUID, view: NSView) {
        views[id] = WeakView(view)
    }

    func remove(id: UUID, view: NSView) {
        if views[id]?.value === view {
            views.removeValue(forKey: id)
        }
    }

    func frame(id: UUID, in scrollView: NSScrollView) -> CGRect? {
        guard let view = views[id]?.value else {
            views.removeValue(forKey: id)
            return nil
        }
        scrollView.layoutSubtreeIfNeeded()
        view.layoutSubtreeIfNeeded()
        guard let documentView = scrollView.documentView else { return nil }
        let frameInDocument = view.convert(view.bounds, to: documentView)
        let visibleOrigin = scrollView.contentView.bounds.origin
        return frameInDocument.offsetBy(dx: -visibleOrigin.x, dy: -visibleOrigin.y)
    }
}
