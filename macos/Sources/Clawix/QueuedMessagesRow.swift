import SwiftUI

/// Compact list of follow-ups the user lined up while the agent is still
/// working. Renders just above the composer input, oldest at the top, each
/// row removable on hover. Dispatch happens automatically as turns complete
/// (see `AppState.dispatchNextQueuedMessage`); this view is purely the
/// pending-state surface. Visual language mirrors `ComposerAttachmentChip`.
struct QueuedMessagesRow: View {
    let messages: [QueuedMessage]
    let onRemove: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(messages) { message in
                QueuedMessageChip(
                    message: message,
                    onRemove: { onRemove(message.id) }
                )
                .transition(.opacity)
            }
        }
    }
}

private struct QueuedMessageChip: View {
    let message: QueuedMessage
    let onRemove: () -> Void

    @State private var hovered = false
    @State private var removeHovered = false

    var body: some View {
        HStack(spacing: 6) {
            LucideIcon(.clock, size: 11)
                .foregroundColor(Color.gray(light: 0.45, dark: 0.55))
                .frame(width: 16, height: 16)

            Text(message.preview)
                .font(BodyFont.system(size: 12.5, wght: 500))
                .foregroundColor(Color.gray(light: 0.27, dark: 0.78))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(0)

            if !message.attachments.isEmpty {
                HStack(spacing: 3) {
                    LucideIcon(.fileText, size: 9)
                        .foregroundColor(Color.gray(light: 0.46, dark: 0.5))
                    Text("\(message.attachments.count)")
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Color.gray(light: 0.46, dark: 0.5))
                        .monospacedDigit()
                }
                .layoutPriority(1)
            }

            Spacer(minLength: 0)

            Button(action: onRemove) {
                LucideIcon(.x, size: 11)
                    .foregroundColor((removeHovered ? Color.gray(light: 0.05, dark: 1.0) : Color.gray(light: 0.27, dark: 0.78)))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hovered ? 1 : 0.001)
            .onHover { removeHovered = $0 }
            .accessibilityLabel(Text(L10n.t("Remove queued message")))
            .accessibilityAction(named: Text(L10n.t("Remove queued message"))) { onRemove() }
            .help(L10n.t("Remove queued message"))
            .layoutPriority(1)
        }
        .padding(.leading, 8)
        .padding(.trailing, hovered ? 7 : 11)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Capsule(style: .continuous)
                .fill(Color.overlay(hovered ? 0.03 : 0))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.overlay(0.18), lineWidth: 0.6)
        )
        .animation(.easeOut(duration: 0.14), value: hovered)
        .contentShape(Capsule(style: .continuous))
        .onHover { hovered = $0 }
        .help(message.preview)
    }
}
