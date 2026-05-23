import SwiftUI

// A follow-up prompt the user lined up while a turn was still running.
// Queued drafts flush one at a time as each turn finishes, so the user
// can keep their train of thought without waiting on the agent or
// losing the default "stop" affordance.
struct QueuedDraft: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var attachments: [ComposerAttachment]

    /// One-line preview for the chip. Falls back to an attachment
    /// summary when the draft is photos-only.
    var preview: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if attachments.count == 1 { return L10n.t("Photo") }
        return L10n.format("%d photos", attachments.count)
    }
}

// Horizontal rail of queued follow-ups, rendered just above the
// composer. Each chip is a small glass capsule with a preview and a
// remove button; the leading chip is the next one that will be sent.
struct QueuedDraftsPanel: View {
    let drafts: [QueuedDraft]
    let onRemove: (QueuedDraft) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                LucideIcon.auto("clock", size: 13)
                    .foregroundStyle(Palette.textTertiary)
                Text(L10n.format("%d queued", drafts.count))
                    .font(Typography.captionFont)
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(.leading, 6)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(drafts) { draft in
                        chip(for: draft)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 14)
    }

    private func chip(for draft: QueuedDraft) -> some View {
        HStack(spacing: 8) {
            if !draft.attachments.isEmpty {
                LucideIcon.auto("photo", size: 14)
                    .foregroundStyle(Palette.textSecondary)
            }
            Text(draft.preview)
                .font(Typography.secondaryFont)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 200, alignment: .leading)
            Button {
                onRemove(draft)
            } label: {
                LucideIcon(.x, size: 13)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("Remove queued prompt"))
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
        .glassCapsule()
    }
}
