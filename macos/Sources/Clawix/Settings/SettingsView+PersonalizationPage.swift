import SwiftUI

struct PersonalizationPage: View {
    @EnvironmentObject var flags: FeatureFlags
    @EnvironmentObject var appState: AppState
    @State private var expanded: Bool = false
    @State private var instructions: String = ""
    @State private var savedSnapshot: String = ""
    @State private var loadError: String? = nil
    @State private var saveError: String? = nil
    @State private var didLoad: Bool = false
    @State private var isSaving: Bool = false

    private var isDirty: Bool { instructions != savedSnapshot }
    private var canSave: Bool { didLoad && isDirty && !isSaving }

    private func localizedPersonalityLabel(_ personality: Personality) -> String {
        switch personality {
        case .friendly: return L10n.t("Friendly")
        case .pragmatic: return L10n.t("Pragmatic")
        }
    }

    private func localizedPersonalityBlurb(_ personality: Personality) -> String {
        switch personality {
        case .friendly: return L10n.t("Warm, collaborative, and helpful")
        case .pragmatic: return L10n.t("Concise, task-focused, and direct")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Personalization")

            SettingsCard {
                DropdownRow(
                    title: "Personality",
                    detail: "Choose a default tone for Clawix's responses",
                    options: Personality.allCases.map { ($0.rawValue, localizedPersonalityLabel($0)) },
                    selection: Binding(
                        get: { appState.personality.rawValue },
                        set: { newValue in
                            if let next = Personality(rawValue: newValue) {
                                appState.personality = next
                            }
                        }
                    ),
                    descriptionForOption: { key in
                        Personality(rawValue: key).map { localizedPersonalityBlurb($0) }
                    }
                )
            }
            .padding(.bottom, 28)

            Text("Custom instructions")
                .font(BodyFont.system(size: 13, wght: 600))
                .foregroundColor(Palette.textPrimary)
            Text("Give Codex extra instructions and context for your project. Learn more")
                .font(BodyFont.system(size: 11, wght: 500))
                .foregroundColor(Palette.textSecondary)
                .padding(.bottom, 14)

            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.gray(light: 0.96, dark: 0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.overlay(0.08), lineWidth: 0.5)
                    )
                InstructionsTextEditor(
                    text: $instructions,
                    isEditable: didLoad && !isSaving
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                ExpandIconButton { expanded = true }
                    .padding(8)
            }
            .frame(height: 240)

            HStack(spacing: 10) {
                if let loadError {
                    HStack(spacing: 8) {
                        Text("Could not load AGENTS.md: \(loadError)")
                            .font(BodyFont.system(size: 11, wght: 500))
                            .foregroundColor(Palette.danger)
                        Button("Retry") { load() }
                            .buttonStyle(.bordered)
                            .disabled(isSaving)
                    }
                } else if let saveError {
                    Text("Save failed: \(saveError)")
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Palette.danger)
                } else if isDirty {
                    Text("Unsaved changes")
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                }
                Spacer()
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                }
                Button { save() } label: {
                    Text("Save")
                        .font(BodyFont.system(size: 12, wght: 600))
                        .foregroundColor(canSave ? Palette.textPrimary : Palette.textSecondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.overlay(canSave ? 0.12 : 0.06))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
            }
            .padding(.top, 14)

            if flags.isVisible(.secrets) {
                SecretsCodexInjectionCard()
                    .padding(.top, 28)
            }
        }
        .onAppear { load() }
        .sheet(isPresented: $expanded) {
            InstructionsExpandedSheet(text: $instructions, isPresented: $expanded)
        }
    }

    private func load() {
        guard !isSaving else { return }
        do {
            let text = try CodexInstructionsFile.sentinelBlockBody(id: CodexPersonalizationBlock.id) ?? ""
            instructions = text
            savedSnapshot = text
            loadError = nil
            saveError = nil
            didLoad = true
        } catch {
            loadError = SettingsUtilities.failureMessage(for: error, surface: "settings.personalization.load")
            didLoad = false
            instructions = savedSnapshot
        }
    }

    private func save() {
        guard canSave else { return }
        let bodyToSave = instructions
        appState.pendingConfirmation = ConfirmationRequest(
            title: "Save Codex instructions?",
            body: "This writes only Clawix's delimited personalization block into Codex's AGENTS.md. The rest of the file stays untouched, and clearing this field removes only that block.",
            confirmLabel: "Save"
        ) {
            persistInstructions(bodyToSave)
        }
    }

    private func persistInstructions(_ body: String) {
        guard didLoad else {
            saveError = "AGENTS.md must load before saving."
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try CodexInstructionsFile.removeSentinelBlock(id: CodexPersonalizationBlock.id)
            } else {
                try CodexInstructionsFile.replaceSentinelBlock(id: CodexPersonalizationBlock.id, body: body)
            }
            instructions = body
            savedSnapshot = body
            saveError = nil
        } catch {
            saveError = SettingsUtilities.failureMessage(for: error, surface: "settings.personalization.save")
        }
    }
}

struct InstructionsTextEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.scrollerInsets = NSEdgeInsets(top: 40, left: 0, bottom: 8, right: 0)

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let bigSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        let textContainer = NSTextContainer(size: bigSize)
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 4
        layoutManager.addTextContainer(textContainer)

        let textView = InstructionsNSTextView(frame: .zero, textContainer: textContainer)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = .width
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = NSColor.dynamicGray(light: 0.12, dark: 1.0)
        textView.insertionPointColor = NSColor.dynamicGray(light: 0.12, dark: 1.0)
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.usesFindPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: 6, height: 12)
        textView.string = text
        textView.isEditable = isEditable

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.isEditable = isEditable
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: InstructionsTextEditor
        init(_ parent: InstructionsTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let snapshot = textView.string
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.parent.text != snapshot {
                    self.parent.text = snapshot
                }
            }
        }
    }
}

struct ExpandIconButton: View {
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            CornerBracketsIcon(size: 12, variant: .expanded, lineWidth: 1.5)
                .foregroundColor((hovered ? Color.gray(light: 0.11, dark: 0.95) : Color.gray(light: 0.27, dark: 0.78)))
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.overlay(hovered ? 0.10 : 0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.overlay(0.08), lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .hoverHint(L10n.t("Edit in large view"))
    }
}

final class InstructionsNSTextView: NSTextView {
    /// Square corner reserved for the overlay button, in screen-stable
    /// (visibleRect) coordinates. Matches `ExpandIconButton.padding(8)`
    /// plus its content size with a couple of pixels of slack.
    private let pointerCornerSize: CGFloat = 40

    private var pointerCornerRect: NSRect {
        let visible = visibleRect
        let s = pointerCornerSize
        return NSRect(x: visible.maxX - s, y: visible.minY, width: s, height: s)
    }

    override func cursorUpdate(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if pointerCornerRect.contains(p) {
            NSCursor.pointingHand.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if pointerCornerRect.contains(p) {
            NSCursor.pointingHand.set()
            return
        }
        super.mouseMoved(with: event)
    }
}

struct InstructionsExpandedSheet: View {
    @Binding var text: String
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Custom instructions")
                    .font(BodyFont.system(size: 14, wght: 700))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                Button { isPresented = false } label: {
                    LucideIcon(.x, size: 11)
                        .foregroundColor(Color.gray(light: 0.27, dark: 0.78))
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.overlay(0.06))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Rectangle()
                .fill(Color.overlay(0.06))
                .frame(height: 1)

            TextEditor(text: $text)
                .font(BodyFont.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(18)
                .background(Color.gray(light: 0.96, dark: 0.06))

            Rectangle()
                .fill(Color.overlay(0.06))
                .frame(height: 1)

            HStack {
                Spacer()
                Button { isPresented = false } label: {
                    Text("Done")
                        .font(BodyFont.system(size: 12, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.overlay(0.10))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .stroke(Color.overlay(0.10), lineWidth: 0.5)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 820, idealWidth: 980, maxWidth: 1200,
               minHeight: 600, idealHeight: 720, maxHeight: 900)
        .background(Color.gray(light: 0.955, dark: 0.07))
    }
}
