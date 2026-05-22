import SwiftUI
import KeyboardShortcuts

// MARK: - Cloud backends row

struct CloudBackendsRow: View {
    var body: some View {
        SettingsRow {
            VStack(alignment: .leading, spacing: 3) {
                Text("Cloud STT provider")
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textPrimary)
                Text("Provider, account and model route")
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } trailing: {
            FeatureProviderPicker(featureId: .sttCloud, capability: .stt)
                .frame(width: 260)
        }
    }
}

// MARK: - KeyboardShortcuts recorder row

/// Wraps the framework's `KeyboardShortcuts.Recorder` in the page's
/// row chrome so the picker reads the same as every other row in
/// Settings. Recording starts on click; clearing happens via the
/// little reset button the framework already provides inside the
/// recorder.
struct KeyboardShortcutsRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let name: KeyboardShortcuts.Name

    var body: some View {
        SettingsRow {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textPrimary)
                Text(detail)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } trailing: {
            KeyboardShortcuts.Recorder(for: name)
        }
    }
}

// MARK: - Onboarding trigger row

/// One-row entry in Avanzado that launches `DictationOnboardingView`
/// on demand. Same view that #28 will auto-present after login lands;
/// for now users discover it from Settings.
struct OnboardingTriggerRow: View {
    @State private var sheetOpen = false

    var body: some View {
        SettingsRow {
            VStack(alignment: .leading, spacing: 3) {
                Text("Voice setup walk-through")
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textPrimary)
                Text("Re-run the first-time setup: permissions checklist + model download in one screen.")
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } trailing: {
            Button {
                DictationOnboardingTrigger.reset()
                sheetOpen = true
            } label: {
                Text("Show")
                    .font(BodyFont.system(size: 12, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule(style: .continuous).fill(Color(white: 0.165)))
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $sheetOpen) {
            DictationOnboardingView(isPresented: $sheetOpen)
        }
    }
}

// MARK: - Avanzados disclosure

/// Collapsible disclosure that hides advanced controls behind a single
/// "Avanzado" trigger row. Persistent expansion state is owned by the
/// parent page (via `@Binding`) and stored in UserDefaults so the
/// section stays open across launches if the user opted in.
///
/// Reuses the page's section/card styling so collapsed it reads as a
/// single subtle row, and expanded the children look indistinguishable
/// from the always-visible sections above.
struct DSPAdvancedSection<Content: View>: View {
    @Binding var expanded: Bool
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    LucideIcon(.chevronRight, size: 11)
                        .foregroundColor(Palette.textSecondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text("Advanced")
                        .font(BodyFont.system(size: 13, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 28)
            .padding(.bottom, expanded ? 0 : 10)

            if expanded {
                content
            }
        }
    }

    private func toggle() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
            expanded.toggle()
        }
    }
}

// MARK: - Custom sound picker row

/// Row for choosing / previewing / resetting one of the custom
/// dictation sounds. The bound `currentPath` is the absolute filesystem
/// path of the user-installed file, or "" if the bundled default
/// should be used.
struct CustomSoundRow: View {
    let title: LocalizedStringKey
    @Binding var currentPath: String
    @State private var error: String?

    var body: some View {
        SettingsRow {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                Text(detailText)
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let error {
                    Text(error)
                        .font(BodyFont.system(size: 10.5, wght: 500))
                        .foregroundColor(Color(red: 0.94, green: 0.45, blue: 0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } trailing: {
            HStack(spacing: 8) {
                CustomSoundIconButton(systemName: "play.fill", action: preview)
                    .disabled(!hasPlayable)
                CustomSoundIconButton(systemName: "folder", action: choose)
                if !currentPath.isEmpty {
                    CustomSoundIconButton(systemName: "arrow.uturn.backward", action: reset)
                }
            }
        }
    }

    private var hasPlayable: Bool {
        if currentPath.isEmpty { return true }
        return FileManager.default.fileExists(atPath: currentPath)
    }

    private var detailText: LocalizedStringKey {
        if currentPath.isEmpty { return "Default" }
        let url = URL(fileURLWithPath: currentPath)
        return LocalizedStringKey(url.lastPathComponent)
    }

    private func preview() {
        let url: URL
        if currentPath.isEmpty {
            // Try bundle URL — preview should mirror what plays during
            // recording.
            return
        } else {
            url = URL(fileURLWithPath: currentPath)
        }
        DictationSoundPlayer.shared.preview(url: url)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Choose dictation sound"
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        switch DictationSoundPlayer.validate(url: chosen) {
        case .success:
            do {
                let installed = try CustomSoundLibrary.install(chosen)
                if !currentPath.isEmpty {
                    CustomSoundLibrary.remove(at: currentPath)
                }
                currentPath = installed.path
                error = nil
            } catch {
                self.error = "Couldn't install file: \(error.localizedDescription)"
            }
        case .failure(let validationError):
            self.error = validationError.localizedDescription
        }
    }

    private func reset() {
        if !currentPath.isEmpty {
            CustomSoundLibrary.remove(at: currentPath)
            currentPath = ""
        }
        error = nil
    }
}

struct CustomSoundIconButton: View {
    let systemName: String
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            LucideIcon.auto(systemName, size: 11)
                .foregroundColor(isEnabled ? Palette.textPrimary : Palette.textSecondary)
                .frame(width: 24, height: 24)
                .background(
                    Circle().fill(hovered && isEnabled ? Color(white: 0.22) : Color(white: 0.14))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - Vocabulary hints row + sheet

/// Compact one-line row that shows the vocabulary count and opens
/// a sheet for editing. Vocabulary boosts proper nouns in the
/// transcription model itself (Whisper's `initial_prompt`) — orthogonal
/// to the post-processing word replacements stored next to it.
struct VocabularyHintsRow: View {
    @ObservedObject var vocabulary: DictationVocabularyStore
    @State private var sheetOpen = false

    var body: some View {
        SettingsRow {
            VStack(alignment: .leading, spacing: 3) {
                Text("Vocabulary")
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textPrimary)
                Text(detail)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } trailing: {
            DSPSecondaryButton(label: "Manage") { sheetOpen = true }
        }
        .sheet(isPresented: $sheetOpen) {
            VocabularySheet(vocabulary: vocabulary, isPresented: $sheetOpen)
        }
    }

    private var detail: LocalizedStringKey {
        let count = vocabulary.entries.count
        if count == 0 {
            return "Add proper nouns and jargon Whisper should bias toward."
        }
        return "\(count) terms boosted"
    }
}

struct VocabularySheet: View {
    @ObservedObject var vocabulary: DictationVocabularyStore
    @Binding var isPresented: Bool
    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Vocabulary boost")
                    .font(BodyFont.system(size: 14, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)

            Text("Whisper sees these as part of the initial prompt, biasing decoding toward them. ~244 token limit.")
                .font(BodyFont.system(size: 11, wght: 500))
                .foregroundColor(Palette.textSecondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            HStack(spacing: 10) {
                TextField("Add a term", text: $draft)
                    .textFieldStyle(.plain)
                    .font(BodyFont.system(size: 12, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(white: 0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                            )
                    )
                    .onSubmit(submit)
                Button(action: submit) {
                    LucideIcon(.plus, size: 13)
                        .foregroundColor(canSubmit ? Palette.textPrimary : Palette.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color(white: 0.18)))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)

            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(vocabulary.entries.enumerated()), id: \.offset) { idx, term in
                        if idx > 0 {
                            Rectangle()
                                .fill(Color.white.opacity(0.05))
                                .frame(height: 0.5)
                                .padding(.leading, 16)
                        }
                        HStack {
                            Text(term)
                                .font(BodyFont.system(size: 12.5, wght: 500))
                                .foregroundColor(Palette.textPrimary)
                            Spacer()
                            Button {
                                vocabulary.remove(at: idx)
                            } label: {
                                LucideIcon(.trash, size: 11)
                                    .foregroundColor(Palette.textPrimary)
                                    .frame(width: 24, height: 24)
                                    .background(Circle().fill(Color(white: 0.14)))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                }
            }
            .thinScrollers()

            HStack {
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 480, height: 420)
        .background(Color(white: 0.10))
    }

    private var canSubmit: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        vocabulary.add(draft)
        draft = ""
    }
}

// MARK: - Whisper prompt editor row

/// Row that exposes the per-language Whisper `initial_prompt`. Reads
/// the active language from Settings so editing always targets the
/// language the user is dictating in. "Auto-detect" maps to a special
/// "auto" key which the store applies as a global fallback.
struct WhisperPromptEditorRow: View {
    @ObservedObject var store: WhisperPromptStore
    let activeLanguage: String
    @State private var editing: Bool = false

    var body: some View {
        SettingsRow {
            VStack(alignment: .leading, spacing: 3) {
                Text("Output style prompt")
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textPrimary)
                Text(detail)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } trailing: {
            DSPSecondaryButton(label: "Edit") { editing = true }
        }
        .sheet(isPresented: $editing) {
            WhisperPromptEditorSheet(
                store: store,
                language: activeLanguage,
                isPresented: $editing
            )
        }
    }

    private var detail: LocalizedStringKey {
        let key = activeLanguage == "auto" ? "auto" : activeLanguage
        let value = store.prompts[key] ?? ""
        if value.isEmpty {
            return "Currently using the default. Edit to bias punctuation, casing, or terminology."
        }
        return "Custom prompt active for this language."
    }
}

struct WhisperPromptEditorSheet: View {
    @ObservedObject var store: WhisperPromptStore
    let language: String
    @Binding var isPresented: Bool
    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Whisper prompt — \(language)")
                    .font(BodyFont.system(size: 14, wght: 700))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
            }

            Text("This text is sent to Whisper as `initial_prompt` and biases formatting + capitalization in the transcription. Keep it short — Whisper has a ~244-token window.")
                .font(BodyFont.system(size: 11, wght: 500))
                .foregroundColor(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $draft)
                .font(BodyFont.system(size: 12.5, wght: 500))
                .foregroundColor(Palette.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 140)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(white: 0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                )

            HStack {
                Button("Reset to default") {
                    store.resetToDefault(for: language)
                    draft = store.prompts[language] ?? ""
                }
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    store.setPrompt(draft, for: language)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 360)
        .background(Color(white: 0.10))
        .onAppear {
            draft = store.prompts[language] ?? ""
        }
    }
}
