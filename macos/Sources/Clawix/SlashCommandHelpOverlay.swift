import SwiftUI

// MARK: - Slash command reference
//
// A read-only, searchable reference of every composer slash command, distinct
// from the inline autocomplete menu (which only shows matches as you type).
// This is the "what can I type after /" overview, opened via the `/help`
// composer command. It reads the same `SlashCommandCatalog.all` the live menu
// uses, so the reference can never drift from the real commands.

struct SlashCommandHelpOverlay: View {
    let onClose: () -> Void
    @State private var query = ""

    private var filtered: [SlashCommand] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return SlashCommandCatalog.all }
        return SlashCommandCatalog.all.filter { cmd in
            cmd.id.lowercased().contains(q)
                || cmd.label.lowercased().contains(q)
                || (cmd.description?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.t("Slash commands"))
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

            TextField(L10n.t("Search commands"), text: $query)
                .textFieldStyle(.plain)
                .font(BodyFont.system(size: 12.5))
                .foregroundColor(Palette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.overlay(0.06)))
                .padding(.horizontal, 18)
                .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(filtered) { cmd in
                        HStack(spacing: 10) {
                            IconImage(cmd.iconName, size: 12)
                                .foregroundColor(Palette.textSecondary)
                                .frame(width: 16, alignment: .center)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(cmd.label)
                                    .font(BodyFont.system(size: 12.5, wght: 600))
                                    .foregroundColor(Palette.textPrimary.opacity(0.92))
                                if let desc = cmd.description {
                                    Text(desc)
                                        .font(BodyFont.system(size: 11.5))
                                        .foregroundColor(Palette.textTertiary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }
                            Spacer(minLength: 8)
                            CommandCapsule(id: cmd.id)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 5)
                    }
                    if filtered.isEmpty {
                        Text(L10n.t("No matching commands"))
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

private struct CommandCapsule: View {
    let id: String
    var body: some View {
        Text("/\(id)")
            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
            .foregroundColor(Color.overlay(0.8))
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
