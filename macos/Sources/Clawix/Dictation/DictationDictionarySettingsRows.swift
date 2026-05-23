import SwiftUI

// MARK: - Dictionary section

/// One-line summary inside the Voice to Text card. Shows how many
/// replacements are configured and exposes a button that opens the
/// management sheet, so the page itself stays compact.
struct DictionarySummaryRow: View {
    @ObservedObject var store: DictationReplacementStore
    @State private var sheetOpen: Bool = false

    var body: some View {
        SettingsRow {
            VStack(alignment: .leading, spacing: 3) {
                Text("Word replacements")
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textPrimary)
                Text(detailText)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } trailing: {
            DSPSecondaryButton(label: "Manage") { sheetOpen = true }
        }
        .sheet(isPresented: $sheetOpen) {
            DictionaryManageSheet(store: store, isPresented: $sheetOpen)
        }
    }

    private var detailText: LocalizedStringKey {
        let count = store.entries.count
        if count == 0 {
            return "Auto-fix words Whisper gets wrong. Smart-case keeps emphasis."
        }
        let active = store.entries.filter { $0.enabled }.count
        if count == active {
            return "\(count) replacements active"
        }
        return "\(active) of \(count) replacements active"
    }
}

/// Pop-up window with the full dictionary editor. Compact macOS sheet:
/// minimal header, inline add form, scrollable list, Done at the
/// bottom. The Voice to Text card itself stays a one-liner — this is
/// where the actual editing happens.
struct DictionaryManageSheet: View {
    @ObservedObject var store: DictationReplacementStore
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Dictionary")
                    .font(BodyFont.system(size: 14, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            DictionaryAddRow(store: store)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            Rectangle()
                .fill(Color.overlay(0.06))
                .frame(height: 0.5)

            if store.entries.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(store.entries.enumerated()), id: \.element.id) { idx, entry in
                            if idx > 0 {
                                Rectangle()
                                    .fill(Color.overlay(0.05))
                                    .frame(height: 0.5)
                                    .padding(.leading, 16)
                            }
                            DictionaryRow(entry: entry, store: store)
                        }
                    }
                }
                .thinScrollers()
            }

            HStack {
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 540, height: 440)
        .background(Color.gray(light: 0.95, dark: 0.10))
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text("No replacements yet")
                .font(BodyFont.system(size: 12, weight: .medium))
                .foregroundColor(Palette.textSecondary)
            Text("Use commas above to cover variants Whisper gets wrong.")
                .font(BodyFont.system(size: 11))
                .foregroundColor(Palette.textSecondary.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 24)
    }
}

/// Inline form to create a new replacement. Two text fields and an
/// add button. Submits on Enter from either field. Validation errors
/// surface inline for ~2.5s, then auto-clear.
struct DictionaryAddRow: View {
    @ObservedObject var store: DictationReplacementStore
    @State private var original: String = ""
    @State private var replacement: String = ""
    @State private var feedback: String?
    @State private var feedbackTask: Task<Void, Never>?
    @State private var addHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                DictionaryFieldStyle(
                    placeholder: "Word Whisper gets wrong (commas for variants)",
                    text: $original,
                    onSubmit: submit
                )
                LucideIcon(.arrowRight, size: 11)
                    .foregroundColor(Palette.textSecondary)
                DictionaryFieldStyle(
                    placeholder: "Replacement",
                    text: $replacement,
                    onSubmit: submit
                )
                Button(action: submit) {
                    LucideIcon(.plus, size: 13)
                        .foregroundColor(canSubmit ? Palette.textPrimary : Palette.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(addButtonFill))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .onHover { addHovered = $0 }
            }
            if let feedback {
                Text(feedback)
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
    }

    private var addButtonFill: Color {
        if !canSubmit { return Color.gray(light: 0.945, dark: 0.12) }
        return addHovered ? Color(white: 0.24) : Color.gray(light: 0.905, dark: 0.18)
    }

    private var canSubmit: Bool {
        !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        let result = store.add(original: original, replacement: replacement)
        switch result {
        case .success:
            original = ""
            replacement = ""
            showFeedback(nil)
        case .failure(let error):
            showFeedback(message(for: error))
        }
    }

    private func showFeedback(_ message: String?) {
        feedbackTask?.cancel()
        feedback = message
        guard message != nil else { return }
        feedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if !Task.isCancelled { feedback = nil }
        }
    }

    private func message(for error: DictationReplacementStore.AddError) -> String {
        switch error {
        case .emptyOriginal:
            return "Add at least one word to replace."
        case .emptyReplacement:
            return "The replacement text can't be empty."
        case .duplicateVariant(let conflict, let variant):
            return "\"\(variant)\" is already a variant of \"\(conflict)\"."
        }
    }
}

/// Single read-only row showing one replacement with toggle, edit, and
/// delete controls. The full text is displayed; long variant lists wrap
/// to a second line so the user can see exactly what is matched.
struct DictionaryRow: View {
    let entry: DictationReplacement
    @ObservedObject var store: DictationReplacementStore
    @State private var editing: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            PillToggle(isOn: Binding(
                get: { entry.enabled },
                set: { store.setEnabled(entry.id, $0) }
            ))

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.original)
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(entry.enabled ? Palette.textPrimary : Palette.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    LucideIcon(.arrowRight, size: 11)
                        .foregroundColor(Palette.textSecondary)
                    Text(entry.replacement)
                        .font(BodyFont.system(size: 12, wght: 500))
                        .foregroundColor(entry.enabled ? Palette.textPrimary : Palette.textSecondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)

            DictionaryIconButton(systemName: "pencil") { editing = true }
            DictionaryIconButton(systemName: "trash") { store.delete(entry.id) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .opacity(entry.enabled ? 1.0 : 0.55)
        .sheet(isPresented: $editing) {
            DictionaryEditSheet(entry: entry, store: store, isPresented: $editing)
        }
    }
}

struct DictionaryIconButton: View {
    let systemName: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            LucideIcon.auto(systemName, size: 11)
                .foregroundColor(Palette.textPrimary)
                .frame(width: 24, height: 24)
                .background(
                    Circle().fill(hovered ? Color.gray(light: 0.87, dark: 0.22) : Color.gray(light: 0.94, dark: 0.14))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

/// Modal editor for an existing entry. Same two fields as the inline
/// add row but with multi-line `TextEditor` to give breathing room for
/// long variant lists. Validates before saving and surfaces conflicts
/// inline.
struct DictionaryEditSheet: View {
    let entry: DictationReplacement
    @ObservedObject var store: DictationReplacementStore
    @Binding var isPresented: Bool

    @State private var original: String
    @State private var replacement: String
    @State private var error: String?

    init(entry: DictationReplacement, store: DictationReplacementStore, isPresented: Binding<Bool>) {
        self.entry = entry
        self.store = store
        self._isPresented = isPresented
        self._original = State(initialValue: entry.original)
        self._replacement = State(initialValue: entry.replacement)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit replacement")
                .font(BodyFont.system(size: 16, wght: 700))
                .foregroundColor(Palette.textPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Words Whisper gets wrong")
                    .font(BodyFont.system(size: 11, wght: 600))
                    .foregroundColor(Palette.textSecondary)
                DictionaryEditorBox(text: $original, minHeight: 70)
                Text("Separate variants with commas, e.g. \"Super base, Supabase, Superbase\".")
                    .font(BodyFont.system(size: 10.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Replacement")
                    .font(BodyFont.system(size: 11, wght: 600))
                    .foregroundColor(Palette.textSecondary)
                DictionaryEditorBox(text: $replacement, minHeight: 50)
            }

            if let error {
                Text(error)
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 460, height: 360)
        .background(Color.gray(light: 0.95, dark: 0.10))
    }

    private var canSave: Bool {
        !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        var draft = entry
        draft.original = original
        draft.replacement = replacement
        switch store.update(draft) {
        case .success:
            isPresented = false
        case .failure(.emptyOriginal):
            error = "Add at least one word to replace."
        case .failure(.emptyReplacement):
            error = "The replacement text can't be empty."
        case .failure(.duplicateVariant(let conflict, let variant)):
            error = "\"\(variant)\" is already a variant of \"\(conflict)\"."
        }
    }
}

struct DictionaryEditorBox: View {
    @Binding var text: String
    var minHeight: CGFloat

    var body: some View {
        TextEditor(text: $text)
            .font(BodyFont.system(size: 12.5, wght: 500))
            .foregroundColor(Palette.textPrimary)
            .scrollContentBackground(.hidden)
            .frame(minHeight: minHeight)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.gray(light: 0.96, dark: 0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.overlay(0.12), lineWidth: 0.5)
                    )
            )
    }
}

struct DictionaryFieldStyle: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    let onSubmit: () -> Void

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(BodyFont.system(size: 12, wght: 500))
            .foregroundColor(Palette.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.gray(light: 0.96, dark: 0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.overlay(0.12), lineWidth: 0.5)
                    )
            )
            .onSubmit(onSubmit)
    }
}
