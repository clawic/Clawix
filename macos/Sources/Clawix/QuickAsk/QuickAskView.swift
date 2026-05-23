import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Floating composer rendered inside `QuickAskPanel`. Visual language
/// mirrors the macOS composer (`ComposerView`): same `MicIcon`, same
/// white-circle `arrow.up` send button, same model-pill dropdown
/// styling. Buttons that exist in the main composer (globe / context
/// indicator / paperclip / permissions) are intentionally absent here
/// because QuickAsk is a HUD-scale ask-anywhere surface, not a full
/// chat thread. The plus menu is the single entry point for
/// attachments and screen captures.
///
/// Two layout modes, driven by `controller.isExpanded`:
///   - Compact (~500x100): just the prompt field + controls row, used
///     before the user has submitted anything.
///   - Expanded (~520x540): a scrollable conversation transcript above
///     the same prompt + controls row. The input row stays anchored at
///     the bottom (the controller pins the panel's bottom-center on
///     resize) so the prompt cursor does not jump under the user.
struct QuickAskView: View {

    @ObservedObject var controller: QuickAskController

    /// QuickAsk lives in an `NSPanel`-hosted `NSHostingView`, outside the
    /// main `WindowGroup`'s environment, so `@EnvironmentObject` does
    /// not reach here. The controller hands AppState in at construction
    /// time so the panel can observe it directly: without this, the
    /// view only redraws when `controller`'s @Published values change,
    /// which means streaming deltas to `ChatMessage.content` and new
    /// assistant messages never trigger a rebuild — the user message
    /// appears once (because `activeChatId` flips) and the assistant
    /// reply stays invisible.
    @ObservedObject var appState: AppState

    @ObservedObject private var dictation = DictationCoordinator.shared
    @ObservedObject private var flags = FeatureFlags.shared

    @State private var prompt: String = ""
    @State private var promptHeight: CGFloat = 28
    @State private var promptFocusToken: Int = 0
    @State private var sendOnStop = false
    @State private var micHover = false
    @State private var hoveringPanel = false
    @State private var dropTargeted = false
    @State private var cameraSheetPresented = false
    @State private var recentChatsPickerPresented = false
    @State private var workWithAppsPickerPresented = false
    @State private var visibleMessageLimit = Self.initialVisibleMessageLimit
    @State private var lastLocalRevealAt: Date = .distantPast
    @State private var bottomAnchor: QuickAskScrollAnchor?
    @ObservedObject private var slashStore = QuickAskSlashCommandsStore.shared
    @ObservedObject private var mentionsStore = QuickAskMentionsStore.shared
    @FocusState private var inputFocused: Bool

    private let cornerRadius: CGFloat = 24
    private static let loadOlderThreshold = ChatView.loadOlderThreshold
    private static let initialVisibleMessageLimit = ChatView.initialVisibleMessageLimit
    private static let visibleMessagePageSize = ChatView.visibleMessagePageSize
    private static let localRevealThrottle = ChatView.localRevealThrottle

    /// The QuickAsk conversation lives inside `AppState.chats` (it is a
    /// real persisted chat, not an ephemeral HUD-only buffer). We pull
    /// the chat by id off the controller so streaming deltas the
    /// runtime emits show up inside the panel without any extra
    /// plumbing: the assistant bubble redraws as the underlying
    /// `ChatMessage.content` mutates.
    private var currentChat: Chat? {
        guard let id = controller.activeChatId else { return nil }
        return appState.chatStore.snapshot(id: id)
    }

    private var currentTranscript: ChatTranscriptStore? {
        guard let id = controller.activeChatId else { return nil }
        return appState.chatStore.transcript(for: id)
    }

    private var visibleSize: NSSize {
        controller.isExpanded
            ? QuickAskController.expandedVisibleSize
            : controller.compactVisibleSize
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            shape
            content
            if controller.isExpanded {
                hoverControls
                    .opacity(hoveringPanel ? 1 : 0)
                    .animation(.easeOut(duration: 0.14), value: hoveringPanel)
            }
            if dropTargeted {
                dropHighlightOverlay
            }
            newConversationShortcut
            // Slash / mention completion dropdown anchored at the
            // bottom edge so it floats above the controls row without
            // shifting the input layout.
            completionDropdown
                .padding(.bottom, 50)
                .padding(.horizontal, 12)
        }
        // Explicit visible size so the squircle's footprint matches
        // what the controller treats as the "real" panel; the
        // surrounding `.padding(QuickAskController.shadowMargin)`
        // gives the drop shadow room to render past the squircle's
        // edge without being clipped by the NSPanel's bounds.
        .frame(width: visibleSize.width, height: visibleSize.height)
        .padding(QuickAskController.shadowMargin)
        .animation(.easeOut(duration: 0.22), value: controller.isExpanded)
        .onHover { hoveringPanel = $0 }
        .onDrop(of: [.fileURL, .image, .pdf], isTargeted: $dropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .sheet(isPresented: $cameraSheetPresented) {
            QuickAskCameraSheet(isPresented: $cameraSheetPresented) { capturedURL in
                controller.addAttachment(
                    QuickAskAttachment(url: capturedURL, kind: .camera)
                )
            }
        }
        .onAppear {
            focusInput()
            controller.noteDraftChanged(prompt)
        }
        .onReceive(NotificationCenter.default.publisher(for: QuickAskController.didShowNotification)) { _ in
            focusInput()
        }
        .onReceive(NotificationCenter.default.publisher(for: QuickAskController.presentCameraSheetNotification)) { _ in
            cameraSheetPresented = true
        }
        .onChange(of: prompt) { newValue in
            controller.noteDraftChanged(newValue)
        }
        // Mirror the editor's measured content height into the controller
        // so the compact HUD's NSPanel resizes vertically with the
        // prompt. In expanded mode this is a no-op (the inputBox handles
        // its own growth inside the fixed expanded panel size).
        .onChange(of: promptHeight) { newValue in
            controller.setCompactPromptHeight(newValue)
        }
    }

    /// Translucent overlay shown while a drag with a file or image
    /// is over the panel. The user's drag-handler decides whether to
    /// accept or reject the drop on release.
    private var dropHighlightOverlay: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.black.opacity(0.45))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.overlay(0.55), style: StrokeStyle(lineWidth: 1.4, dash: [6, 4]))
            )
            .overlay(
                VStack(spacing: 6) {
                    LucideIcon(.inbox, size: 17)
                        .foregroundColor(Color.overlay(0.92))
                    Text("Drop to attach")
                        .font(BodyFont.system(size: 13, wght: 600))
                        .foregroundColor(Color.overlay(0.92))
                }
            )
            .allowsHitTesting(false)
            .transition(.opacity)
    }

    /// Walks the `NSItemProvider`s the user dropped, asking each one
    /// for a file URL. Anything that resolves to a real file becomes a
    /// `.drop` attachment; ad-hoc image data without a backing URL is
    /// written to a tmp PNG and attached the same way.
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var added = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    DispatchQueue.main.async {
                        controller.addAttachment(
                            QuickAskAttachment(url: url, kind: .drop)
                        )
                    }
                }
                added = true
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data, let url = persistDroppedImage(data: data) else { return }
                    DispatchQueue.main.async {
                        controller.addAttachment(
                            QuickAskAttachment(url: url, kind: .drop)
                        )
                    }
                }
                added = true
            }
        }
        return added
    }

    private func persistDroppedImage(data: Data) -> URL? {
        guard let url = QuickAskCaptureRoutes.captureFileURL(prefix: "drop") else {
            return nil
        }
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    // Cluster of hidden zero-size buttons that keep the QuickAsk
    // keyboard shortcuts alive regardless of whether the visible
    // affordance is on screen. Each one mirrors a button somewhere in
    // the panel chrome but stays valid in compact mode (no header,
    // no chat title, etc.).
    private var newConversationShortcut: some View {
        ZStack {
            Button("New conversation") {
                controller.startNewConversation()
                prompt = ""
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New temporary conversation") {
                controller.startTemporaryConversation()
                prompt = ""
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Open in main app") {
                controller.openInMainApp()
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Close panel") {
                controller.hide()
            }
            .keyboardShortcut("w", modifiers: .command)

            Button("Open settings") {
                controller.openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("Previous chat") {
                controller.cycleRecentChats(direction: 1)
            }
            .keyboardShortcut("[", modifiers: .command)

            Button("Next chat") {
                controller.cycleRecentChats(direction: -1)
            }
            .keyboardShortcut("]", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // Sidebar-style behind-window blur (heavier distortion than
    // `.ultraThinMaterial`, picks up the wallpaper / windows behind
    // the panel like the macOS sidebar does) plus a dark tint so the
    // panel still reads as a translucent dark glass surface, not as a
    // light vibrancy chrome. Hairline border kept thin and slightly
    // less opaque than before so it reads as a faint bevel rather
    // than a hard outline. Shadow stays soft per prior tuning.
    private var shape: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.clear)
            .background(
                VisualEffectBlur(
                    material: .sidebar,
                    blendingMode: .behindWindow
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.22))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.overlay(0.32), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.32), radius: 18, x: 0, y: 8)
    }

    /// Bumps `promptFocusToken` so `ComposerTextEditor` re-runs its
    /// "make first responder" path. SwiftUI's `@FocusState` does not
    /// cross the NSViewRepresentable boundary; the editor watches the
    /// token and calls `makeFirstResponder` whenever it changes.
    private func focusInput() {
        promptFocusToken &+= 1
        inputFocused = false
        DispatchQueue.main.async { inputFocused = true }
    }

    private func resetConversationWindow() {
        visibleMessageLimit = Self.initialVisibleMessageLimit
        lastLocalRevealAt = .distantPast
        bottomAnchor = .bottom
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: controller.isExpanded ? 6 : 0) {
            if controller.isExpanded {
                conversationScroll
                inputBox
            } else {
                // Compact: selection-suggestion pill (when a snapshot
                // is pending), chips on top (auto-hidden when empty),
                // multi-line input under them, controls hugging the
                // bottom edge.
                selectionSuggestion
                QuickAskChipsBar(controller: controller)
                promptField
                Spacer(minLength: 0)
                controlsRow(alignment: .center, sendBottomInset: 4)
            }
        }
        .padding(.horizontal, controller.isExpanded ? 14 : 7)
        .padding(.top, controller.isExpanded ? 4 : 3)
        .padding(.bottom, controller.isExpanded ? 16 : 6)
        .frame(maxHeight: .infinity)
    }

    /// In expanded mode the prompt + controls row live inside their
    /// own bordered, slightly-brighter frosted box so the input reads
    /// as a discrete surface stacked under the transcript instead of
    /// floating loose at the bottom edge of the panel. Compact mode
    /// keeps the bare layout because the panel itself is the box.
    private var inputBox: some View {
        // Mirror the compact panel's footprint so the input row inside
        // the expanded transcript reads as a smaller version of the
        // closed-state HUD: same generous squircle, same ~7pt
        // horizontal padding, controls hugging the bottom edge. We use
        // `.bottom` alignment + an explicit bottom padding on the send
        // disc so the row hugs the inputBox bottom while the send disc
        // stays lifted as the "primary" target — pushing the +/model
        // pill/mic down without dragging the disc with them.
        VStack(alignment: .leading, spacing: 0) {
            selectionSuggestion
            QuickAskChipsBar(controller: controller)
            promptField
                .padding(.top, controller.pendingAttachments.isEmpty ? 5 : 4)
            Spacer(minLength: 0)
            controlsRow(alignment: .bottom, sendBottomInset: -2, secondaryDrop: 1)
        }
        .padding(.horizontal, 7)
        .padding(.bottom, 9)
        // Grow the input box vertically with the prompt up to ~5 lines
        // worth of text. Below that floor we keep the historical 85pt
        // footprint so the closed-state HUD doesn't squish.
        .frame(height: max(85, min(160, promptHeight + 60)))
        .background(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(Color.overlay(0.028))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .strokeBorder(Color.overlay(0.14), lineWidth: 0.7)
        )
    }

    // MARK: - Conversation (expanded mode)

    /// Top-edge controls that ONLY appear on hover: close button on
    /// the left, new-chat (custom ComposeIcon, same shape used by the
    /// sidebar's "New chat" row) and open-in-main-app on the right.
    /// No persistent title and no permanent icons — the panel chrome
    /// stays clean until the user reaches the top edge with the
    /// pointer.
    private var hoverControls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                hoverIconButton(
                    action: { controller.hide() },
                    tooltip: "Close (⎋)"
                ) {
                    LucideIcon(.circleX, size: 14)
                        .foregroundColor(Color.overlay(0.50))
                }
                if let chat = currentChat {
                    Button(action: { recentChatsPickerPresented.toggle() }) {
                        HStack(spacing: 4) {
                            Text(chat.title)
                                .font(BodyFont.system(size: 11, wght: 600))
                                .foregroundColor(Color.overlay(0.70))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            LucideIcon(.chevronDown, size: 10)
                                .foregroundColor(Color.overlay(0.50))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.overlay(recentChatsPickerPresented ? 0.10 : 0))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Recent chats (⌘[ / ⌘])")
                    .quickAskIconHover()
                    .popover(isPresented: $recentChatsPickerPresented, arrowEdge: .bottom) {
                        QuickAskRecentChatsPicker(
                            appState: appState,
                            controller: controller,
                            isPresented: $recentChatsPickerPresented
                        )
                    }
                }
                Spacer(minLength: 0)
                hoverIconButton(
                    action: { controller.toggleTemporary() },
                    tooltip: controller.isTemporary
                        ? "Temporary chat — won't be saved"
                        : "Switch to Temporary chat (⌘⇧N)"
                ) {
                    LucideIcon.auto(controller.isTemporary
                          ? "eyeglasses.slash"
                          : "eyeglasses", size: 11)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(
                            controller.isTemporary
                                ? Color.overlay(0.95)
                                : Color.overlay(0.50)
                        )
                }
                hoverIconButton(
                    action: { controller.openInMainApp() },
                    tooltip: "Open in app (⌘O)"
                ) {
                    OpenInAppIcon()
                        .stroke(
                            Color.overlay(0.50),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: 15, height: 15)
                }
                hoverIconButton(
                    action: {
                        controller.startNewConversation()
                        prompt = ""
                    },
                    tooltip: "New conversation (⌘N)"
                ) {
                    ComposeIcon()
                        .stroke(
                            Color.overlay(0.50),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: 15, height: 15)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            Spacer(minLength: 0)
        }
    }

    private func hoverIconButton<Content: View>(
        action: @escaping () -> Void,
        tooltip: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        QuickAskHoverIconButton(
            action: action,
            tooltip: tooltip,
            content: content
        )
    }

    /// Scrollable transcript. We auto-scroll to the latest message id
    /// on every append AND on streaming-content mutation so the
    /// assistant reply stays in view as it types itself out. Top and
    /// bottom edges fade into the panel's dark glass per the user's
    /// "fade-edge into background" rule.
    private var conversationScroll: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if let chatId = controller.activeChatId,
                       let transcript = currentTranscript {
                        QuickAskConversationMessages(
                            chatId: chatId,
                            transcript: transcript,
                            appState: appState,
                            visibleMessageLimit: $visibleMessageLimit,
                            bottomAnchor: $bottomAnchor,
                            onRequestScroll: {
                                scrollToBottom(proxy: proxy)
                            }
                        )
                    }
                    // Anchor at the very bottom so we can always scroll
                    // past the trailing message's intrinsic height when
                    // a streaming token grows it. Without this anchor
                    // ScrollViewReader sometimes settles a few points
                    // short of the real bottom on rapid deltas.
                    Color.clear.frame(height: 1).id(QuickAskScrollAnchor.bottom)
                }
                // Generous horizontal inset so messages live inside
                // the conversation column instead of hugging the dark
                // glass edge. Top padding pushes the first message past
                // the 6% top fade so it never reads as half-erased even
                // when the transcript is short.
                .padding(.horizontal, 14)
                .padding(.top, 36)
                .padding(.bottom, 4)
            }
            .frame(maxHeight: .infinity)
            .scrollContentBackground(.hidden)
            .scrollPosition(id: $bottomAnchor, anchor: .bottom)
            .modifier(ChatScrollDeclarativeAnchors())
            .modifier(ChatScrollUpSentinel(
                threshold: Self.loadOlderThreshold,
                onTrigger: {
                    revealOlderLocalMessages(proxy: proxy)
                }
            ))
            // Same low-opacity capsule the sidebar paints. Legacy style
            // (vs the default overlay) reserves the scroller's 14pt column
            // outside the clipView, which sidesteps the private collapse-
            // when-idle animation that clips our right-anchored knob's
            // left edge. The bar still effectively disappears when the
            // content fits because `drawKnob()` short-circuits at
            // `knobProportion >= 0.999`.
            .thinScrollers(style: .clawixAlwaysVisible)
            .onAppear {
                bottomAnchor = .bottom
                scrollToBottom(proxy: proxy, animated: false)
            }
            .onChange(of: controller.activeChatId) { _ in
                resetConversationWindow()
                scrollToBottom(proxy: proxy, animated: false)
            }
            .onReceive(NotificationCenter.default.publisher(for: QuickAskController.didShowNotification)) { _ in
                scrollToBottom(proxy: proxy, animated: false)
            }
        }
        .mask(
            // Soft fade on both edges so messages dissolve into the
            // dark glass instead of slamming against an invisible
            // straight cut. 6% top / 6% bottom matches the visual
            // weight of the input row underneath.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black, location: 0.06),
                    .init(color: .black, location: 0.94),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        bottomAnchor = .bottom
        if animated {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(QuickAskScrollAnchor.bottom, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(QuickAskScrollAnchor.bottom, anchor: .bottom)
        }
    }

    private func revealOlderLocalMessages(proxy: ScrollViewProxy) {
        guard let chatId = controller.activeChatId,
              let transcript = currentTranscript else { return }
        let visibleCount = min(visibleMessageLimit, transcript.messageStores.count)
        let hiddenLocalMessageCount = max(0, transcript.messageStores.count - visibleCount)
        guard hiddenLocalMessageCount > 0 else {
            appState.requestOlderIfNeeded(chatId: chatId)
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastLocalRevealAt) >= Self.localRevealThrottle else {
            return
        }
        lastLocalRevealAt = now
        let visibleStores = Array(transcript.messageStores.suffix(visibleMessageLimit))
        let anchorId = visibleStores.first?.id
        bottomAnchor = nil
        visibleMessageLimit = min(
            transcript.messageStores.count,
            visibleMessageLimit + Self.visibleMessagePageSize
        )
        if let anchorId {
            DispatchQueue.main.async {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    proxy.scrollTo(anchorId, anchor: .top)
                }
            }
        }
    }

    private struct QuickAskConversationMessages: View {
        let chatId: UUID
        @ObservedObject var transcript: ChatTranscriptStore
        @ObservedObject var appState: AppState
        @Binding var visibleMessageLimit: Int
        @Binding var bottomAnchor: QuickAskScrollAnchor?
        let onRequestScroll: () -> Void

        var body: some View {
            if appState.messagesPaginationByChat[chatId]?.loadingOlder == true {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Spacer()
                }
                .frame(height: 24)
                .transition(.opacity)
            }

            let visibleMessageStores = Array(transcript.messageStores.suffix(visibleMessageLimit))
            let _ = PerfSignpost.uiChat.event("quickask.messages.visible", visibleMessageStores.count)
            ForEach(visibleMessageStores) { messageStore in
                QuickAskObservedMessageBubble(
                    messageStore: messageStore,
                    appState: appState,
                    onRequestScroll: onRequestScroll
                )
            }
            .onChange(of: transcript.messageIds.last) { _ in
                bottomAnchor = .bottom
                onRequestScroll()
            }
            .task(id: prewarmKey(for: visibleMessageStores)) {
                await ChatMarkdownPrewarmer.prewarm(
                    messages: visibleMessageStores.map(\.message),
                    timelineEntryLimit: 0
                )
            }
        }

        private func prewarmKey(for visibleMessageStores: [ChatMessageStore]) -> ChatMarkdownPrewarmKey {
            ChatMarkdownPrewarmKey(
                chatId: chatId,
                visibleMessageCount: visibleMessageStores.count,
                firstMessageId: visibleMessageStores.first?.id,
                lastMessageId: visibleMessageStores.last?.id,
                lastTimelineCount: 0
            )
        }
    }

    private struct QuickAskObservedMessageBubble: View {
        @ObservedObject var messageStore: ChatMessageStore
        let appState: AppState
        let onRequestScroll: () -> Void

        var body: some View {
            QuickAskMessageBubble(message: messageStore.message, appState: appState)
                .id(messageStore.id)
                .onChange(of: messageStore.message.content) { _ in
                    onRequestScroll()
                }
        }
    }

    // MARK: - Composer row

    /// Multi-line input. Uses the same `ComposerTextEditor` the macOS
    /// composer uses, so Enter submits and Shift+Enter inserts a line
    /// break — and the whole HUD inherits the composer's caret style,
    /// undo handling, and disabled-text-replacement behaviour for free.
    /// `promptHeight` flows up so the expanded `inputBox` grows with
    /// the text up to ~5 lines.
    private var promptField: some View {
        ZStack(alignment: .topLeading) {
            ComposerTextEditor(
                text: $prompt,
                contentHeight: $promptHeight,
                autofocus: true,
                focusToken: promptFocusToken,
                onSubmit: submitIfReady
            )
            // In expanded mode the inputBox is the box that scrolls past
            // ~5 lines, so we keep the historical 120pt cap there. In
            // compact mode the panel itself grows (driven by the
            // controller's `compactPromptHeight`), so we let the editor
            // stretch up to ~15 lines before falling back to internal
            // scroll, matching `compactMaxVisibleHeight` minus the
            // controls row + paddings.
            .frame(minHeight: 28, maxHeight: controller.isExpanded ? 120 : 280)
            .padding(.leading, 5)

            if prompt.isEmpty {
                Text(placeholderText)
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Color.gray(light: 0.45, dark: 0.55))
                    .padding(.leading, 9)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Default controls row: `+` / model / mic / send. Mirrors the
    /// macOS composer layout and behaviour 1:1 — during transcription
    /// the mic slot becomes a `TranscribingSpinner`. The compact
    /// (closed) HUD passes `.center` + `4` so the disc sits ~2pt above
    /// the rest of the row's center, matching the historical look.
    /// The expanded inputBox passes `.bottom` + a larger
    /// `sendBottomInset`, which anchors `+ / model / mic` to the row
    /// bottom while the send disc rides higher: pushing the secondary
    /// controls toward the bottom edge without dragging the primary
    /// disc with them.
    @ViewBuilder
    private func normalControlsRow(
        alignment: VerticalAlignment,
        sendBottomInset: CGFloat,
        secondaryDrop: CGFloat = 0
    ) -> some View {
        HStack(alignment: alignment, spacing: 6) {
            QuickAskPlusMenu()
                .padding(.leading, 4)
                .padding(.bottom, -secondaryDrop)
            webSearchToggle
                .padding(.bottom, -secondaryDrop)
            workWithAppsButton
                .padding(.bottom, -secondaryDrop)
            QuickAskModelPicker(
                selection: $appState.selectedModel,
                runtime: $appState.selectedAgentRuntime,
                primary: appState.availableModels,
                others: appState.otherModels
            )
            Spacer(minLength: 0)

            if flags.isVisible(.voiceToText),
               dictation.state == .transcribing,
               dictation.activeSource == .quickAsk {
                TranscribingSpinner()
                    .frame(width: 26, height: 26)
                    .padding(.bottom, -secondaryDrop)
                    .accessibilityLabel("Transcribing voice note")
            } else if flags.isVisible(.voiceToText) {
                micButton
                    .padding(.bottom, -secondaryDrop)
            }

            sendButton(extraBottomPadding: sendBottomInset)
        }
    }

    /// Recording controls row: `+` / waveform / elapsed timer / stop /
    /// send. Stop just transcribes into the prompt field; send
    /// transcribes and auto-submits the resulting prompt.
    private var recordingControlsRow: some View {
        HStack(spacing: 8) {
            QuickAskPlusMenu()
                .padding(.leading, 4)

            ComposerRecordingWaveform(
                isActive: dictation.state == .recording,
                levels: dictation.barLevels
            )
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .padding(.horizontal, 4)

            Text(dictation.formattedElapsed)
                .font(BodyFont.system(size: 12, design: .monospaced))
                .foregroundColor(Color.gray(light: 0.27, dark: 0.78))
                .monospacedDigit()
                .padding(.horizontal, 2)

            Button {
                stopAndAppendTranscription()
            } label: {
                StopSquircle()
                    .fill(Color.gray(light: 0.14, dark: 0.92))
                    .frame(width: 13, height: 13)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.gray(light: 0.87, dark: 0.22)))
            }
            .buttonStyle(.plain)
            .quickAskDiscHover()
            .accessibilityLabel("Stop recording")

            Button {
                stopAndSend()
            } label: {
                ArrowUpIcon(size: 14)
                    .foregroundColor(Color.gray(light: 0.96, dark: 0.06))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Palette.textPrimary))
            }
            .buttonStyle(.plain)
            .quickAskDiscHover()
            .accessibilityLabel("Send voice note")
        }
    }

    @ViewBuilder
    private func controlsRow(
        alignment: VerticalAlignment,
        sendBottomInset: CGFloat,
        secondaryDrop: CGFloat = 0
    ) -> some View {
        if dictation.state == .recording, dictation.activeSource == .quickAsk {
            recordingControlsRow
        } else {
            normalControlsRow(
                alignment: alignment,
                sendBottomInset: sendBottomInset,
                secondaryDrop: secondaryDrop
            )
        }
    }

    /// Toggle for the web-search prefix (`/search …`) the controller
    /// applies on submit. Filled icon when on, outline when off.
    private var webSearchToggle: some View {
        Button {
            controller.webSearchEnabled.toggle()
        } label: {
            LucideIcon.auto(controller.webSearchEnabled ? "globe.americas.fill" : "globe", size: 14)
                .foregroundColor(
                    controller.webSearchEnabled
                        ? Color.overlay(0.95)
                        : Color.overlay(0.62)
                )
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(controller.webSearchEnabled ? "Web search ON" : "Web search OFF")
        .quickAskIconHover()
    }

    /// Opens `QuickAskWorkWithAppsPicker` as a popover. The selected
    /// app's name shows next to the icon when active so the user can
    /// see at a glance what context the next prompt will inherit.
    private var workWithAppsButton: some View {
        Button {
            workWithAppsPickerPresented.toggle()
        } label: {
            HStack(spacing: 4) {
                LucideIcon(.squareDashed, size: 14)
                    .foregroundColor(
                        controller.workWithBundleId != nil
                            ? Color.overlay(0.95)
                            : Color.overlay(0.62)
                    )
                if let bundleId = controller.workWithBundleId,
                   let appName = NSWorkspace.shared.runningApplications
                       .first(where: { $0.bundleIdentifier == bundleId })?.localizedName
                {
                    Text(appName)
                        .font(BodyFont.system(size: 11, wght: 600))
                        .foregroundColor(Color.overlay(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 80)
                }
            }
            .padding(.horizontal, 4)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Work with app")
        .quickAskIconHover()
        .popover(isPresented: $workWithAppsPickerPresented, arrowEdge: .bottom) {
            QuickAskWorkWithAppsPicker(
                controller: controller,
                isPresented: $workWithAppsPickerPresented
            )
        }
    }

    // Same `MicIcon` and visual treatment as `ComposerView` so the
    // QuickAsk panel and the in-app composer feel like the same family.
    private var micButton: some View {
        Button {
            startVoice()
        } label: {
            MicIcon(lineWidth: 1.5)
                .foregroundColor(Palette.textPrimary)
                .opacity(micHover ? 1.0 : 0.88)
                .frame(width: 20, height: 20)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { micHover = $0 }
        .animation(.easeOut(duration: 0.12), value: micHover)
        .accessibilityLabel("Start voice recording")
    }

    // 33pt white disc with a heavy black `arrow.up`, dimmed when the
    // input is empty. `extraBottomPadding` controls how far the
    // visible disc sits above the rest of the row: under `.center`
    // alignment it lifts the disc by `extraBottomPadding / 2`; under
    // `.bottom` alignment it lifts by the full inset, so the inputBox
    // can keep the disc visually high while pushing `+ / model / mic`
    // down toward the bottom edge.
    private func sendButton(extraBottomPadding: CGFloat) -> some View {
        Button(action: submitIfReady) {
            ArrowUpIcon(size: 12)
                .foregroundColor(canSend ? Color.gray(light: 0.96, dark: 0.06) : Color.overlay(0.55))
                .frame(width: 33, height: 33)
                .background(
                    Circle().fill(canSend ? Palette.textPrimary : Color.overlay(0.14))
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .quickAskDiscHover()
        .padding(.bottom, extraBottomPadding)
    }

    /// Placeholder string shown inside the prompt input. Switches to
    /// the "Ask about selected text" hint when the controller has
    /// captured a selection from the previous frontmost app.
    private var placeholderText: String {
        if controller.pendingSelection != nil {
            return String(localized: "Ask about the selected text…", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
        return String(localized: "Ask anything", bundle: AppLocale.bundle, locale: AppLocale.current)
    }

    /// Inline "Use selection" pill the panel surfaces above the chips
    /// bar when a selection snapshot is pending. Dismissable: the `x`
    /// drops the snapshot without staging anything.
    @ViewBuilder
    private var selectionSuggestion: some View {
        if let snap = controller.pendingSelection {
            HStack(spacing: 6) {
                LucideIcon(.textAlignStart, size: 11)
                    .foregroundColor(Color.overlay(0.85))
                Text(snap.appName.map { "Use selection from \($0)" } ?? "Use selection")
                    .font(BodyFont.system(size: 11, wght: 600))
                    .foregroundColor(Color.overlay(0.92))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    let url = QuickAskCaptureRoutes.placeholderAttachmentURL()
                    controller.addAttachment(
                        QuickAskAttachment(
                            url: url,
                            kind: .selection,
                            previewText: snap.text
                        )
                    )
                    controller.pendingSelection = nil
                } label: {
                    Text("Use")
                        .font(BodyFont.system(size: 11, wght: 700))
                        .foregroundColor(Color.overlay(0.92))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.overlay(0.16))
                        )
                }
                .buttonStyle(.plain)
                Button {
                    controller.pendingSelection = nil
                } label: {
                    LucideIcon(.x, size: 10)
                        .foregroundColor(Color.overlay(0.6))
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.overlay(0.10)))
                }
                .buttonStyle(.plain)
                .quickAskIconHover()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
        }
    }

    private var canSend: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitIfReady() {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        controller.submitPrompt(trimmed)
        prompt = ""
    }

    // MARK: - Voice recording

    /// Mirrors `ComposerView.startVoice()`. The completion fires once
    /// when transcription finishes; we re-use the same `sendOnStop`
    /// trick so a "stop" press appends the text and a "stop + send"
    /// press appends + auto-submits.
    private func startVoice() {
        sendOnStop = false
        let pendingSend = $sendOnStop
        dictation.startFromQuickAsk(language: nil) { text in
            appendTranscribedText(text)
            if pendingSend.wrappedValue,
               !prompt.trimmingCharacters(in: .whitespaces).isEmpty {
                submitIfReady()
            }
            pendingSend.wrappedValue = false
        }
    }

    private func stopAndAppendTranscription() {
        sendOnStop = false
        dictation.stop()
    }

    private func stopAndSend() {
        sendOnStop = true
        dictation.stop()
    }

    // MARK: - Slash / mention completions

    /// Slash-command fragment when the prompt's first line is exactly
    /// a `/<token>`. Returns nil when the user has typed a space (the
    /// command has been "committed" and what follows is the argument)
    /// or when there's a second line.
    private var slashFragment: String? {
        guard let firstLine = prompt.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first
        else { return nil }
        let line = String(firstLine)
        guard line.hasPrefix("/") else { return nil }
        if line.contains(" ") { return nil }
        return line
    }

    /// Trailing `@<token>` in the prompt. The fragment is the text
    /// AFTER the `@` so the dropdown can use it as a search query.
    /// Returns nil when there's no open mention or the mention has
    /// already been committed (whitespace after the token).
    private var mentionFragment: (range: Range<String.Index>, query: String)? {
        guard let atRange = prompt.range(of: "@", options: .backwards) else { return nil }
        // Must be at the start of the prompt or preceded by a space/newline.
        if atRange.lowerBound > prompt.startIndex {
            let prev = prompt.index(before: atRange.lowerBound)
            let char = prompt[prev]
            if !(char == " " || char == "\n") { return nil }
        }
        let after = prompt[atRange.upperBound...]
        if after.contains(" ") || after.contains("\n") { return nil }
        return (atRange.upperBound..<prompt.endIndex, String(after))
    }

    /// Active project root, when there is one. Used by the mentions
    /// store to walk the directory tree for `@file` autocompletion.
    private var activeProjectRoot: URL? {
        guard let path = appState.selectedProject?.path else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    @ViewBuilder
    private var completionDropdown: some View {
        if let frag = slashFragment {
            QuickAskCompletionPanel(
                title: "Slash commands",
                rows: slashStore.suggestions(for: frag).map { cmd in
                    QuickAskCompletionRow(
                        title: cmd.trigger,
                        subtitle: cmd.description,
                        action: { applySlashCommand(cmd) }
                    )
                }
            )
        } else if let mention = mentionFragment {
            let items = mentionsStore.suggestions(
                fragment: mention.query,
                projectRoot: activeProjectRoot
            )
            if !items.isEmpty {
                QuickAskCompletionPanel(
                    title: "Mentions",
                    rows: items.map { item in
                        QuickAskCompletionRow(
                            title: item.displayName,
                            subtitle: item.description,
                            action: { applyMention(item, replacing: mention.range) }
                        )
                    }
                )
            }
        }
    }

    private func applySlashCommand(_ cmd: QuickAskSlashCommand) {
        // Replace the first line entirely with the command + a
        // trailing space so the user can keep typing the argument.
        let lines = prompt.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let rest = lines.count > 1 ? "\n\(lines[1])" : ""
        if let expansion = cmd.expansion {
            prompt = "\(expansion)\(rest)"
        } else {
            prompt = "\(cmd.trigger) \(rest.trimmingCharacters(in: .whitespaces))"
        }
    }

    private func applyMention(_ item: QuickAskMentionItem, replacing range: Range<String.Index>) {
        switch item {
        case .file(let f):
            prompt.replaceSubrange(range, with: f.absolutePath + " ")
        case .prompt(let p):
            // Custom prompt: drop the `@<name>` token entirely and
            // splice the prompt body in its place. Trailing space
            // keeps the cursor flowing into the next sentence.
            let beforeAt = prompt.index(before: range.lowerBound)
            // beforeAt currently sits on the `@` character.
            prompt.replaceSubrange(beforeAt..<prompt.endIndex, with: "\(p.body) ")
        }
    }

    private func appendTranscribedText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if prompt.isEmpty {
            prompt = trimmed
        } else {
            let needsSpace = !prompt.hasSuffix(" ") && !prompt.hasSuffix("\n")
            prompt += (needsSpace ? " " : "") + trimmed
        }
    }
}
