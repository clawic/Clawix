import AppKit
import SwiftUI
import ClawixCore

let chatRailMaxWidth: CGFloat = 720

private struct ChatVisibleWindowEvidence: Equatable {
    let chatId: UUID
    let visibleCount: Int
    let totalCount: Int
    let hiddenCount: Int
    let firstMessageId: UUID?
    let lastMessageId: UUID?
    let bottomArmed: Bool
    let messages: [ChatVisibleWindowMessageEvidence]
}

private struct ChatVisibleWindowMessageEvidence: Equatable {
    let id: UUID
    let role: String
    let contentReady: Bool
    let streamingFinished: Bool
    let isError: Bool

    init(message: ChatMessage) {
        id = message.id
        switch message.role {
        case .user:
            role = "user"
            contentReady = !message.content.isEmpty
        case .assistant:
            role = "assistant"
            contentReady = message.streamingFinished && !message.isError && !message.content.isEmpty
        }
        streamingFinished = message.streamingFinished
        isError = message.isError
    }
}

private enum ChatVisibleWindowRenderLog {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var lastEvidence: ChatVisibleWindowEvidence?
    nonisolated(unsafe) private static var lastLoggedAt: CFAbsoluteTime = 0
    private static let duplicateWindow: TimeInterval = 0.25
    private static let detailedMessageLimit = 12

    static func record(_ evidence: ChatVisibleWindowEvidence, reason: String) {
        guard evidence.visibleCount > 0 else { return }
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        if lastEvidence == evidence, now - lastLoggedAt < duplicateWindow {
            lock.unlock()
            return
        }
        let previousEvidence = lastEvidence
        lastEvidence = evidence
        lastLoggedAt = now
        lock.unlock()

        PerfSignpost.uiChat.event("visible.window", evidence.visibleCount)
        RenderProbe.mark(
            "ChatVisibleWindow",
            fields: [
                "chat": evidence.chatId.uuidString,
                "first": evidence.firstMessageId?.uuidString ?? "none",
                "hidden": "\(evidence.hiddenCount)",
                "last": evidence.lastMessageId?.uuidString ?? "none",
                "bottomArmed": "\(evidence.bottomArmed)",
                "reason": reason,
                "total": "\(evidence.totalCount)",
                "visible": "\(evidence.visibleCount)"
            ]
        )
        recordCompleteFinalWindow(evidence, reason: reason, batch: now)
        if let previousEvidence {
            recordOlderHistoryInsertionIfNeeded(
                previous: previousEvidence,
                next: evidence,
                reason: reason
            )
        }
    }

    private static func recordCompleteFinalWindow(
        _ evidence: ChatVisibleWindowEvidence,
        reason: String,
        batch: CFAbsoluteTime
    ) {
        let batchId = String(format: "%.6f", batch)
        let userRows = evidence.messages.filter { $0.role == "user" }.count
        let assistantRows = evidence.messages.filter { $0.role == "assistant" }.count
        let assistantReadyRows = evidence.messages.filter {
            $0.role == "assistant" && $0.contentReady
        }.count
        let incompleteRows = evidence.messages.filter { !$0.contentReady }.count
        let roleSequence = evidence.messages
            .map { $0.role == "assistant" ? "a" : "u" }
            .joined()
        let shouldRecordMessageDetails = evidence.visibleCount <= detailedMessageLimit
        RenderProbe.mark(
            "ChatFinalWindow",
            fields: [
                "batch": batchId,
                "bottomArmed": "\(evidence.bottomArmed)",
                "chat": evidence.chatId.uuidString,
                "first": evidence.firstMessageId?.uuidString ?? "none",
                "hidden": "\(evidence.hiddenCount)",
                "incompleteRows": "\(incompleteRows)",
                "last": evidence.lastMessageId?.uuidString ?? "none",
                "messageDetailLogged": "\(shouldRecordMessageDetails)",
                "reason": reason,
                "roleSequence": roleSequence.isEmpty ? "none" : roleSequence,
                "assistantReady": "\(assistantReadyRows)",
                "assistantRows": "\(assistantRows)",
                "total": "\(evidence.totalCount)",
                "userRows": "\(userRows)",
                "visible": "\(evidence.visibleCount)",
                "windowComplete": "\(incompleteRows == 0 && evidence.bottomArmed)"
            ]
        )
        guard shouldRecordMessageDetails else { return }
        for (index, message) in evidence.messages.enumerated() {
            RenderProbe.mark(
                "ChatFinalWindowMessage",
                fields: [
                    "batch": batchId,
                    "chat": evidence.chatId.uuidString,
                    "contentReady": "\(message.contentReady)",
                    "id": message.id.uuidString,
                    "index": "\(index)",
                    "isError": "\(message.isError)",
                    "role": message.role,
                    "streamingFinished": "\(message.streamingFinished)",
                    "visible": "\(evidence.visibleCount)"
                ]
            )
        }
    }

    private static func recordOlderHistoryInsertionIfNeeded(
        previous: ChatVisibleWindowEvidence,
        next: ChatVisibleWindowEvidence,
        reason: String
    ) {
        guard previous.chatId == next.chatId,
              previous.lastMessageId == next.lastMessageId,
              previous.firstMessageId != next.firstMessageId,
              next.visibleCount > previous.visibleCount
        else { return }
        RenderProbe.mark(
            "ChatOlderHistoryInsertedAbove",
            fields: [
                "chat": next.chatId.uuidString,
                "fromFirst": previous.firstMessageId?.uuidString ?? "none",
                "fromVisible": "\(previous.visibleCount)",
                "last": next.lastMessageId?.uuidString ?? "none",
                "reason": reason,
                "toFirst": next.firstMessageId?.uuidString ?? "none",
                "toVisible": "\(next.visibleCount)",
                "bottomArmed": "\(next.bottomArmed)",
                "anchorStableCandidate": "\((previous.lastMessageId == next.lastMessageId) && next.bottomArmed)"
            ]
        )
    }
}

struct ChatView: View {
    let chatId: UUID
    /// True when this ChatView lives inside a parent chat's right
    /// sidebar as a "side chat" tab. Drives two divergences from the
    /// main route: the composer reads from a view-owned
    /// `ComposerState` (so typing in the side chat doesn't bleed into
    /// the main composer and vice versa), and the send button routes
    /// to this `chatId` directly instead of going through
    /// `currentRoute`. Default `false` keeps the main route untouched.
    var isSideChat: Bool = false
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var meshStore: MeshStore
    @EnvironmentObject private var flags: FeatureFlags

    private var publishingReady: Bool {
        flags.isVisible(.publishing)
    }
    /// View-owned composer used only when `isSideChat == true`.
    /// Created once per ChatView identity (the right-sidebar tab keys
    /// the view by `chatId`, so each side chat keeps its draft across
    /// re-renders) and injected into the descendants' environment so
    /// the inner `ComposerView` reads/writes this one instead of the
    /// global `appState.composer`.
    @StateObject private var sideComposer = ComposerState()
    @StateObject private var remoteProjectionStore = ClawJSRemoteProjectionStore()

    @State private var workMenuOpen = false
    @State private var branchMenuOpen = false
    @State private var branchCreateOpen = false
    @State private var branchSearch = ""
    @State private var visibleMessageLimit = Self.initialVisibleMessageLimit
    @State private var lastLocalRevealAt: Date = .distantPast
    @State private var firstVisibleRuntimeDemandChatId: UUID?
    @State private var closedMetadataReadyChatId: UUID?
    @State private var closedMetadataScheduledChatId: UUID?
    /// Drives `scrollPosition`. `chatTailId` is the canonical "you are
    /// at the tail" marker; an `id`'d clear rectangle at the end of
    /// the LazyVStack carries the same id so SwiftUI knows where the
    /// bottom is. Stays `nil` whenever the user scrolls up so we
    /// don't fight their position.
    @State private var bottomId: String?

    private var chat: Chat? {
        appState.chat(byId: chatId)
    }

    private var transcript: ChatTranscriptStore? {
        appState.chatStore.transcript(for: chatId)
    }

    /// Stable id for the trailing sentinel inside the chat's LazyVStack.
    /// Per-chat so switching chats reanchors at the new tail instead of
    /// keeping the old chat's sentinel reference and animating between
    /// them.
    private var chatTailId: String { "chat-tail-\(chatId.uuidString)" }

    /// Scroll-up sentinel threshold and spinner height tuned to match
    /// the iPhone client (`ChatDetailView.loadOlderThreshold`). Firing
    /// at 80pt from the top gives the daemon a chance to deliver the
    /// next page before the user sees the gap.
    static let loadOlderThreshold: CGFloat = 80
    static let initialVisibleMessageLimit = 8
    static let visibleMessagePageSize = 6
    static let localRevealThrottle: TimeInterval = 0.5

    var body: some View {
        RenderProbe.tick("ChatView")
        return Group {
            if let chat, let transcript {
                let visibleMessageStores: [ChatMessageStore] = Array(transcript.messageStores.suffix(visibleMessageLimit))
                let hiddenLocalMessageCount = max(0, transcript.messageIds.count - visibleMessageStores.count)
                let visibleWindowEvidence = ChatVisibleWindowEvidence(
                    chatId: chatId,
                    visibleCount: visibleMessageStores.count,
                    totalCount: transcript.messageIds.count,
                    hiddenCount: hiddenLocalMessageCount,
                    firstMessageId: visibleMessageStores.first?.id,
                    lastMessageId: visibleMessageStores.last?.id,
                    bottomArmed: bottomId == chatTailId,
                    messages: visibleMessageStores.map {
                        ChatVisibleWindowMessageEvidence(message: $0.message)
                    }
                )
                let _ = PerfSignpost.uiChat.event("messages.visible", visibleMessageStores.count)
                VStack(spacing: 0) {
                    ChatTranscriptScrollerView(
                        appState: appState,
                        chatId: chatId,
                        chat: chat,
                        transcript: transcript,
                        visibleMessageStores: visibleMessageStores,
                        hiddenLocalMessageCount: hiddenLocalMessageCount,
                        visibleMessageLimit: $visibleMessageLimit,
                        lastLocalRevealAt: $lastLocalRevealAt,
                        bottomId: $bottomId,
                        closedMetadataReady: closedMetadataReadyChatId == chatId,
                        chatTailId: chatTailId,
                        publishingReady: publishingReady
                    )
                    .onAppear {
                        recordVisibleWindowIfNeeded(visibleWindowEvidence, reason: "appear")
                        notifyFirstVisibleWindowIfNeeded(visibleWindowEvidence)
                        markClosedMetadataReadyIfNeeded(visibleWindowEvidence)
                    }
                    .onChange(of: visibleWindowEvidence) { _, next in
                        recordVisibleWindowIfNeeded(next, reason: "change")
                        notifyFirstVisibleWindowIfNeeded(next)
                        markClosedMetadataReadyIfNeeded(next)
                    }

                    VStack(spacing: 14) {
                        let activeRemoteJobs = flags.isVisible(.remoteMesh)
                            ? meshStore.jobs(forChat: chatId)
                            : []
                        if !activeRemoteJobs.isEmpty {
                            VStack(spacing: 8) {
                                ForEach(activeRemoteJobs) { job in
                                    RemoteJobCard(
                                        state: job,
                                        remoteProjectionState: remoteProjectionStore.state,
                                        onDismiss: { meshStore.clearJob(job.id) }
                                    )
                                }
                            }
                            .frame(maxWidth: chatRailMaxWidth)
                            .task { remoteProjectionStore.load() }
                            .onDisappear { remoteProjectionStore.cancel() }
                        }

                        GoalBannerView(chatId: chatId)
                            .frame(maxWidth: chatRailMaxWidth)

                        ComposerView(
                            chatMode: true,
                            sideChatId: isSideChat ? chatId : nil
                        )
                            .frame(maxWidth: chatRailMaxWidth)
                            .environmentObject(isSideChat ? sideComposer : appState.composer)

                        if flags.isVisible(.remoteMesh) || (flags.isVisible(.git) && chat.hasGitRepo) {
                            HStack(spacing: 14) {
                                if flags.isVisible(.remoteMesh) {
                                    ChatFooterPill(
                                        icon: "desktopcomputer",
                                        label: String(localized: "Work locally", bundle: AppLocale.bundle, locale: AppLocale.current),
                                        accessibilityLabel: "Work mode",
                                        isOpen: workMenuOpen
                                    ) {
                                        workMenuOpen.toggle()
                                    }
                                    .anchorPreference(key: WorkPillAnchorKey.self, value: .bounds) { $0 }
                                }

                            if flags.isVisible(.git), chat.hasGitRepo {
                                ChatFooterPill(
                                    icon: "arrow.triangle.branch",
                                    label: chat.branch ?? "main",
                                    accessibilityLabel: "Change branch",
                                    isOpen: branchMenuOpen
                                ) {
                                    branchMenuOpen.toggle()
                                }
                                .anchorPreference(key: BranchPillAnchorKey.self, value: .bounds) { $0 }
                            }

                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: chatRailMaxWidth)
                            .padding(.leading, 6)
                        }
                    }
                    .padding(.horizontal, 38)
                    .padding(.top, 14)
                    .padding(.bottom, 22)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.background)
                .overlay(alignment: .topTrailing) {
                    if appState.isFindBarOpen, appState.findChatId == chatId {
                        FindBarView()
                            .padding(.top, 14)
                            .padding(.trailing, 18)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .zIndex(10)
                    }
                }
                .animation(.easeOut(duration: 0.18), value: appState.isFindBarOpen)
                .overlayPreferenceValue(WorkPillAnchorKey.self) { anchor in
                    GeometryReader { proxy in
                        if flags.isVisible(.remoteMesh), workMenuOpen, let anchor {
                            let buttonFrame = proxy[anchor]
                            WorkLocallyMenuPopup(isPresented: $workMenuOpen)
                                .anchoredPopupPlacement(
                                    buttonFrame: buttonFrame,
                                    proxy: proxy,
                                    horizontal: .leading(offset: 4),
                                    direction: .above
                                )
                                .transition(.softNudge(y: 4))
                        }
                    }
                    .allowsHitTesting(workMenuOpen)
                }
                .overlayPreferenceValue(BranchPillAnchorKey.self) { anchor in
                    GeometryReader { proxy in
                        if flags.isVisible(.git), branchMenuOpen, let anchor {
                            let buttonFrame = proxy[anchor]
                            BranchPickerPopup(
                                isPresented: $branchMenuOpen,
                                searchText: $branchSearch,
                                branches: chat.availableBranches,
                                currentBranch: chat.branch,
                                uncommittedFiles: chat.uncommittedFiles,
                                onSelect: { branch in
                                    appState.switchBranch(chatId: chat.id, to: branch)
                                    branchMenuOpen = false
                                },
                                onCreate: {
                                    branchMenuOpen = false
                                    branchCreateOpen = true
                                }
                            )
                            .anchoredPopupPlacement(
                                buttonFrame: buttonFrame,
                                proxy: proxy,
                                horizontal: .leading(offset: 4),
                                direction: .above
                            )
                            .transition(.softNudge(y: 4))
                        }
                    }
                    .allowsHitTesting(branchMenuOpen)
                }
                .animation(.easeOut(duration: 0.20), value: workMenuOpen)
                .animation(.easeOut(duration: 0.20), value: branchMenuOpen)
                .sheet(isPresented: $branchCreateOpen) {
                    if flags.isVisible(.git) {
                    BranchCreateSheet(
                        initialName: suggestedNewBranchName(for: chat),
                        onCancel: { branchCreateOpen = false },
                        onCreate: { name in
                            appState.createBranch(chatId: chat.id, name: name)
                            branchCreateOpen = false
                        }
                    )
                    }
                }
            } else {
                    Text(verbatim: "Chat not found")
                    .foregroundColor(Palette.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.background)
        }
    }
    }

    private func recordVisibleWindowIfNeeded(_ evidence: ChatVisibleWindowEvidence, reason: String) {
        ChatVisibleWindowRenderLog.record(evidence, reason: reason)
    }

    private func notifyFirstVisibleWindowIfNeeded(_ evidence: ChatVisibleWindowEvidence) {
        guard firstVisibleRuntimeDemandChatId != evidence.chatId,
              evidence.visibleCount > 0
        else { return }
        firstVisibleRuntimeDemandChatId = evidence.chatId
        appState.noteChatFirstVisibleForRuntimeDemand(chatId: evidence.chatId)
    }

    private func markClosedMetadataReadyIfNeeded(_ evidence: ChatVisibleWindowEvidence) {
        guard closedMetadataReadyChatId != evidence.chatId else { return }
        guard closedMetadataScheduledChatId != evidence.chatId else { return }
        guard evidence.visibleCount > 0, evidence.bottomArmed else { return }
        guard evidence.messages.allSatisfy(\.contentReady) else { return }
        closedMetadataScheduledChatId = evidence.chatId
        DispatchQueue.main.async {
            guard closedMetadataReadyChatId != evidence.chatId else { return }
            RenderProbe.mark(
                "ChatClosedMetadataReady",
                fields: [
                    "chat": evidence.chatId.uuidString,
                    "visible": "\(evidence.visibleCount)"
                ]
            )
            closedMetadataReadyChatId = evidence.chatId
        }
    }

    private func suggestedNewBranchName(for chat: Chat) -> String {
        // Prefix `clawix/` + slug derived from title.
        let slugSource = chat.title.lowercased()
        let allowed = CharacterSet.lowercaseLetters
            .union(.decimalDigits)
            .union(CharacterSet(charactersIn: "-/"))
        var slug = ""
        for scalar in slugSource.unicodeScalars {
            if allowed.contains(scalar) {
                slug.unicodeScalars.append(scalar)
            } else if scalar == " " || scalar == "_" {
                slug.append("-")
            }
        }
        slug = slug.replacingOccurrences(of: "--", with: "-")
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if slug.isEmpty { slug = "feature" }
        return "clawix/" + String(slug.prefix(40))
    }
}

/// macOS 15+ layered anchors. macOS 14 falls back to the
/// `scrollPosition` binding alone (already applied at the call site).

/// Scroll-up sentinel that fires `onTrigger` once the user is near
/// the top of the transcript and there is real overflow. macOS 15+
/// only because `onScrollGeometryChange` is a 15.0 API; macOS 14 ships
/// without scroll-up pagination, which is acceptable degradation —
/// the initial `bridgeInitialPageLimit` messages still load eagerly.

// MARK: - Anchor keys for footer pills


// MARK: - User mention parsing
//
// On send, the composer flattens staged attachments into the message body
// as `@/absolute/path` tokens prefixed before the text (see
// `AppState.sendMessage`). Rendering them verbatim in the user bubble
// would show raw paths to the reader, so we parse them back out and
// render image mentions as squircle thumbnails above the bubble. The
// raw `message.content` is preserved untouched so copy and edit still
// see the mention syntax.


/// Per-process cache for the three `DateFormatter`s `MessageRow` uses to
/// render its timestamp. Allocating + configuring a `DateFormatter` is
/// surprisingly expensive (it lazily walks `cf-locale`/ICU on first use)
/// and `formattedTimestamp` is called inside `actionBar`, which is
/// re-evaluated whenever the row's `body` runs. Caching the three
/// formatters and only re-configuring when the locale identifier
/// changes turns three allocations per render into a dictionary lookup.


// MARK: - Message row

// [QUICKASK<->CHAT PARITY]
//
// This is the main chat's user/assistant bubble. There is a SECOND
// surface that renders the same `ChatMessage` model: the QuickAsk HUD
// bubble in `Sources/Clawix/QuickAsk/QuickAskView.swift`
// (`QuickAskMessageBubble`).
//
// Both surfaces reuse `AssistantMarkdownText`
// (Sources/Clawix/AgentBackend/AssistantMarkdownText.swift) and
// `ThinkingShimmer` (Sources/Clawix/AgentBackend/ThinkingShimmer.swift)
// so markdown parsing, streaming fade, error coloring and the
// "thinking" indicator stay in lockstep. When you change message
// format here (new segment kind, error styling, streaming behaviour),
// check whether the HUD also needs the change.
//
// The HUD is intentionally simpler (no edit affordance, no work-summary
// chevron, no tool-call timeline, no PlanCard segmenting, no link
// preview card, no changed-file pills) so changes that are part of
// the HUD's "minimal" mandate stay confined to MessageRow. The
// dispatch counterpart of `sendMessage()` is `submitQuickAsk(...)`
// in `AppState.swift`; see its doc for why QuickAsk must call
// `openSession` explicitly.


// MARK: - Inline editor for user messages


// MARK: - "Continue in" popup (work-locally pill)


// MARK: - Branch picker popup


// MARK: - "Create and switch branch" sheet


// MARK: - Forked from conversation banner

/// Centered separator with a branch glyph and a tappable label that
/// navigates back to the parent chat. Sits between the copied parent
/// transcript and any new turns the user adds in the forked chat.


// MARK: - Trailing "Website" preview card

/// Compact link card shown under the last assistant answer when the body
/// embeds a URL. Renders the "Memory · Website · Open" affordance:
/// favicon-style globe pill, resolved `<title>` (or host while the fetch
/// is in flight), subtitle "Website", and an "Open" button that hands
/// off to the right-sidebar browser.

/// Wrapping flow layout used for paragraph lines: places children left to
/// right, breaking to a new line whenever the next subview would overflow
/// the proposed width. Handles word-by-word atoms so link/code chips can
/// sit inline with surrounding prose without breaking text wrap.
