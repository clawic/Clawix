import SwiftUI

// Slash-command palette for the chat composer, surfaced only in
// Advanced mode. It mirrors how the desktop Clawix treats a leading
// "/" : as a launcher for in-app actions rather than text shipped to
// the agent. Every entry maps to something the chat surface can
// actually do right now, so the palette never offers a dead command.
//
// Trigger: the composer text is exactly "/" or "/<prefix>" (no spaces,
// no newline). Selecting a row runs the action and clears the "/" token.

enum ChatCommandID: String, CaseIterable {
    case newChat
    case project
    case rename
    case archive
    case voice
    case scrollToBottom
}

struct ChatCommand: Identifiable, Equatable {
    let id: ChatCommandID
    /// The typed trigger, e.g. "/new". Matching is prefix-based on this.
    let trigger: String
    let label: String
    let description: String
    /// SF-symbol-style name resolved through the Lucide bridge
    /// (`LucideIcon.auto`) so it matches the rest of the iOS chrome.
    let iconName: String
}

enum ChatCommandCatalog {
    static let all: [ChatCommand] = [
        ChatCommand(id: .newChat, trigger: "/new",
                    label: "New chat", description: "Start a fresh conversation",
                    iconName: "square.and.pencil"),
        ChatCommand(id: .project, trigger: "/project",
                    label: "Project", description: "Switch the working folder",
                    iconName: "folder"),
        ChatCommand(id: .rename, trigger: "/rename",
                    label: "Rename", description: "Rename this chat",
                    iconName: "pencil"),
        ChatCommand(id: .scrollToBottom, trigger: "/bottom",
                    label: "Jump to latest", description: "Scroll to the newest message",
                    iconName: "arrow.down"),
        ChatCommand(id: .voice, trigger: "/voice",
                    label: "Voice", description: "Record a voice prompt",
                    iconName: "mic"),
        ChatCommand(id: .archive, trigger: "/archive",
                    label: "Archive", description: "Archive and leave this chat",
                    iconName: "archivebox"),
    ]

    /// Returns the matching commands when `text` is a bare slash token
    /// (`"/"`, `"/re"`, …). Any whitespace means the user has moved on
    /// to a real prompt, so the palette stays hidden.
    static func matches(for text: String) -> [ChatCommand] {
        guard text.hasPrefix("/") else { return [] }
        if text.contains(" ") || text.contains("\n") { return [] }
        let query = text.dropFirst().lowercased()
        if query.isEmpty { return all }
        return all.filter { cmd in
            cmd.trigger.dropFirst().lowercased().hasPrefix(query)
                || cmd.label.lowercased().contains(query)
        }
    }
}

// Floating glass panel rendered just above the composer. Same dark
// translucent menu language as the rest of the iPhone chrome: a
// rounded glass card with icon + label + trailing description rows.
struct CommandPalettePanel: View {
    let commands: [ChatCommand]
    let onSelect: (ChatCommand) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(commands.enumerated()), id: \.element.id) { index, cmd in
                if index > 0 {
                    Rectangle()
                        .fill(Palette.borderSubtle)
                        .frame(height: 0.5)
                        .padding(.leading, 46)
                }
                Button {
                    onSelect(cmd)
                } label: {
                    HStack(spacing: 12) {
                        LucideIcon.auto(cmd.iconName, size: 21)
                            .foregroundStyle(Palette.textPrimary)
                            .frame(width: 22, alignment: .center)
                        Text(cmd.trigger)
                            .font(BodyFont.system(size: 15, weight: .medium))
                            .foregroundStyle(Palette.textPrimary)
                            .fixedSize(horizontal: true, vertical: false)
                        Text(cmd.description)
                            .font(Typography.secondaryFont)
                            .foregroundStyle(Palette.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .glassRounded(radius: AppLayout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: AppLayout.cardCornerRadius, style: .continuous)
                .stroke(Palette.popupStroke, lineWidth: Palette.popupStrokeWidth)
        )
        .padding(.horizontal, 14)
    }
}
