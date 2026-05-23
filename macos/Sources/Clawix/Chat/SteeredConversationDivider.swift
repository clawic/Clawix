import SwiftUI

/// Synthetic transcript separator shown above a user message that carried
/// one or more browser annotations. The pinned comments redirect the agent,
/// so the turn reads as a deliberate course correction rather than a plain
/// follow-up. Mirrors the muted, centered-label divider idiom used elsewhere
/// in the transcript.
struct SteeredConversationDivider: View {
    var body: some View {
        HStack(spacing: 10) {
            line
            HStack(spacing: 6) {
                LucideIcon.auto("bubble.left", size: 11)
                    .foregroundColor(Color.gray(light: 0.46, dark: 0.50))
                Text("Steered conversation")
                    .font(BodyFont.system(size: 11.5, wght: 600))
                    .foregroundColor(Color.gray(light: 0.45, dark: 0.55))
                    .fixedSize()
            }
            line
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(L10n.t("Steered conversation")))
    }

    private var line: some View {
        Rectangle()
            .fill(Color.overlay(0.08))
            .frame(height: 1)
    }
}
