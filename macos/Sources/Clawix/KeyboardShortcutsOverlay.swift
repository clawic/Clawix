import SwiftUI

// MARK: - Keyboard shortcuts reference
//
// A read-only, searchable reference of the app's keyboard shortcuts, distinct
// from the editable settings page. Bindings here mirror the real menu-command
// shortcuts so the reference stays truthful. Opened via the `/shortcuts`
// composer command.

struct ShortcutItem: Identifiable {
    let id = UUID()
    let label: String
    /// Display glyphs, e.g. "⌘N", "⇧⌘N", "↩".
    let keys: String
}

struct ShortcutGroup: Identifiable {
    let id = UUID()
    let title: String
    let items: [ShortcutItem]
}

enum ShortcutCatalog {
    static let groups: [ShortcutGroup] = [
        ShortcutGroup(title: "General", items: [
            ShortcutItem(label: "New chat", keys: "⌘N"),
            ShortcutItem(label: "New window", keys: "⇧⌘N"),
            ShortcutItem(label: "Quick chat", keys: "⌥⌘N"),
            ShortcutItem(label: "Open folder", keys: "⌘O"),
            ShortcutItem(label: "Command palette", keys: "⌘K"),
            ShortcutItem(label: "Keyboard shortcuts", keys: "⌘?"),
            ShortcutItem(label: "Settings", keys: "⌘,"),
            ShortcutItem(label: "Close", keys: "⌘W"),
        ]),
        ShortcutGroup(title: "Navigation", items: [
            ShortcutItem(label: "Back", keys: "⌘["),
            ShortcutItem(label: "Forward", keys: "⌘]"),
            ShortcutItem(label: "Previous chat", keys: "⇧⌘["),
            ShortcutItem(label: "Next chat", keys: "⇧⌘]"),
            ShortcutItem(label: "Go to chat 1–9", keys: "⌘1–⌘9"),
            ShortcutItem(label: "Next recently viewed", keys: "⌃⇥"),
            ShortcutItem(label: "Previous recently viewed", keys: "⌃⇧⇥"),
        ]),
        ShortcutGroup(title: "Chat", items: [
            ShortcutItem(label: "Pin chat", keys: "⌥⌘P"),
            ShortcutItem(label: "Rename chat", keys: "⌥⌘R"),
            ShortcutItem(label: "Archive chat", keys: "⇧⌘A"),
            ShortcutItem(label: "Copy working directory", keys: "⇧⌘C"),
            ShortcutItem(label: "Copy session ID", keys: "⌥⌘C"),
            ShortcutItem(label: "Copy deeplink", keys: "⌥⌘L"),
        ]),
        ShortcutGroup(title: "Search", items: [
            ShortcutItem(label: "Search chats", keys: "⌘G"),
            ShortcutItem(label: "Find in chat", keys: "⌘F"),
        ]),
        ShortcutGroup(title: "Panels", items: [
            ShortcutItem(label: "Toggle sidebar", keys: "⌘B"),
            ShortcutItem(label: "Toggle side panel", keys: "⌥⌘B"),
            ShortcutItem(label: "Toggle terminal", keys: "⌘J"),
            ShortcutItem(label: "Toggle file tree", keys: "⇧⌘E"),
        ]),
        ShortcutGroup(title: "Terminal", items: [
            ShortcutItem(label: "Toggle terminal panel", keys: "⌃`"),
            ShortcutItem(label: "New terminal", keys: "⇧⌘T"),
            ShortcutItem(label: "Close terminal tab", keys: "⇧⌘W"),
        ]),
        ShortcutGroup(title: "Browser", items: [
            ShortcutItem(label: "New tab", keys: "⌘T"),
            ShortcutItem(label: "Reload page", keys: "⌘R"),
            ShortcutItem(label: "Force reload", keys: "⇧⌘R"),
            ShortcutItem(label: "Focus address bar", keys: "⌘L"),
        ]),
        ShortcutGroup(title: "Composer", items: [
            ShortcutItem(label: "Send message", keys: "↩"),
            ShortcutItem(label: "Toggle plan mode", keys: "⇧⇥"),
            ShortcutItem(label: "Open model picker", keys: "⌃⇧M"),
            ShortcutItem(label: "Start dictation", keys: "⌃⇧D"),
        ]),
        ShortcutGroup(title: "Zoom", items: [
            ShortcutItem(label: "Zoom in", keys: "⌘+"),
            ShortcutItem(label: "Zoom out", keys: "⌘−"),
            ShortcutItem(label: "Actual size", keys: "⌘0"),
        ]),
        ShortcutGroup(title: "Tools", items: [
            ShortcutItem(label: "Performance trace", keys: "⇧⌘S"),
        ]),
    ]
}

struct KeyboardShortcutsOverlay: View {
    let onClose: () -> Void
    @State private var query = ""

    private var filtered: [ShortcutGroup] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return ShortcutCatalog.groups }
        return ShortcutCatalog.groups.compactMap { group in
            let items = group.items.filter {
                $0.label.lowercased().contains(q) || $0.keys.lowercased().contains(q)
            }
            return items.isEmpty ? nil : ShortcutGroup(title: group.title, items: items)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.t("Keyboard shortcuts"))
                    .font(BodyFont.system(size: 15, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                Button { onClose() } label: {
                    XIcon(size: 12)
                        .foregroundColor(Color.overlay(0.5))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("Close"))
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 10)

            TextField(L10n.t("Search shortcuts"), text: $query)
                .textFieldStyle(.plain)
                .font(BodyFont.system(size: 12.5))
                .foregroundColor(Palette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.overlay(0.06)))
                .padding(.horizontal, 18)
                .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(filtered.prefix(12)) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.title)
                                .font(BodyFont.system(size: 11, wght: 600))
                                .foregroundColor(Palette.textSecondary)
                                .padding(.horizontal, 18)
                                .padding(.bottom, 2)
                            ForEach(group.items.prefix(16)) { item in
                                HStack {
                                    Text(item.label)
                                        .font(BodyFont.system(size: 12.5))
                                        .foregroundColor(Palette.textPrimary.opacity(0.9))
                                    Spacer()
                                    KeyCapsule(keys: item.keys)
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 3)
                            }
                        }
                    }
                    if filtered.isEmpty {
                        Text(L10n.t("No matching shortcuts"))
                            .font(BodyFont.system(size: 12.5))
                            .foregroundColor(Palette.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .frame(width: 420, height: 540)
        .background(Palette.background)
    }
}

// MARK: - Overlay mount

/// App-level mount for the keyboard-shortcut reference, opened from the Help
/// menu (⌘?) or the `/shortcuts` composer command. Mirrors
/// `CommandPaletteOverlay` so the two reference surfaces dismiss the same way
/// (tap-outside or Escape).
struct KeyboardShortcutsReferenceOverlay: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ZStack {
            if appState.isKeyboardShortcutsOpen {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { appState.isKeyboardShortcutsOpen = false }
                    .transition(.opacity)

                KeyboardShortcutsOverlay { appState.isKeyboardShortcutsOpen = false }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Palette.popupStroke, lineWidth: Palette.popupStrokeWidth)
                    )
                    .shadow(color: .black.opacity(0.45), radius: 30, y: 12)
                    .background(
                        Button("") { appState.isKeyboardShortcutsOpen = false }
                            .keyboardShortcut(.cancelAction)
                            .opacity(0)
                    )
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.98)),
                        removal: .opacity
                    ))
            }
        }
        .animation(.easeOut(duration: 0.16), value: appState.isKeyboardShortcutsOpen)
    }
}

private struct KeyCapsule: View {
    let keys: String
    var body: some View {
        Text(keys)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundColor(Color.overlay(0.85))
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.overlay(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Palette.popupStroke, lineWidth: Palette.popupStrokeWidth)
            )
    }
}
