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
            ShortcutItem(label: "Command menu", keys: "⌘K"),
            ShortcutItem(label: "Shortcuts", keys: "⌘/"),
            ShortcutItem(label: "Settings", keys: "⌘,"),
        ]),
        ShortcutGroup(title: "Chats", items: [
            ShortcutItem(label: "Search chats", keys: "⌘G"),
            ShortcutItem(label: "Find in chat", keys: "⌘F"),
            ShortcutItem(label: "Close", keys: "⌘W"),
        ]),
        ShortcutGroup(title: "Panels", items: [
            ShortcutItem(label: "Toggle sidebar", keys: "⌘B"),
            ShortcutItem(label: "Toggle terminal", keys: "⌘J"),
        ]),
        ShortcutGroup(title: "Terminal", items: [
            ShortcutItem(label: "New terminal", keys: "⇧⌘T"),
            ShortcutItem(label: "Close terminal tab", keys: "⇧⌘W"),
        ]),
        ShortcutGroup(title: "Browser", items: [
            ShortcutItem(label: "New tab", keys: "⌘T"),
            ShortcutItem(label: "Reload page", keys: "⌘R"),
            ShortcutItem(label: "Focus address bar", keys: "⌘L"),
        ]),
        ShortcutGroup(title: "Composer", items: [
            ShortcutItem(label: "Send message", keys: "↩"),
            ShortcutItem(label: "Toggle plan mode", keys: "⇧⇥"),
        ]),
        ShortcutGroup(title: "Zoom", items: [
            ShortcutItem(label: "Zoom in", keys: "⌘+"),
            ShortcutItem(label: "Zoom out", keys: "⌘−"),
            ShortcutItem(label: "Actual size", keys: "⌘0"),
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
                        .foregroundColor(Color.white.opacity(0.5))
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
                .background(Capsule().fill(Color.white.opacity(0.06)))
                .padding(.horizontal, 18)
                .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(filtered) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.title)
                                .font(BodyFont.system(size: 11, wght: 600))
                                .foregroundColor(Palette.textSecondary)
                                .padding(.horizontal, 18)
                                .padding(.bottom, 2)
                            ForEach(group.items) { item in
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

private struct KeyCapsule: View {
    let keys: String
    var body: some View {
        Text(keys)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundColor(Color.white.opacity(0.85))
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Palette.popupStroke, lineWidth: Palette.popupStrokeWidth)
            )
    }
}
