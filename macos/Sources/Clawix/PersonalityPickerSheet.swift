import SwiftUI

// MARK: - Personality quick picker
//
// An inline picker for the assistant personality, opened from the
// `/personalidad` composer command. The full personalization surface still
// lives in Settings; this is the fast in-chat switch between the persisted
// `Personality` cases without leaving the conversation. It writes straight to
// `AppState.personality`, which persists itself.

struct PersonalityPickerSheet: View {
    @ObservedObject var appState: AppState
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.t("Personality"))
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
            .padding(.bottom, 12)

            VStack(spacing: 8) {
                ForEach(Personality.allCases) { option in
                    PersonalityRow(
                        option: option,
                        isSelected: appState.personality == option
                    ) {
                        withAnimation(.easeOut(duration: 0.16)) {
                            appState.personality = option
                        }
                        onClose()
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .frame(width: 360)
        .background(Palette.background)
    }
}

private struct PersonalityRow: View {
    let option: Personality
    let isSelected: Bool
    let onTap: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(BodyFont.system(size: 13, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                    Text(option.blurb)
                        .font(BodyFont.system(size: 11.5))
                        .foregroundColor(Palette.textTertiary)
                }
                Spacer(minLength: 8)
                if isSelected {
                    LucideIcon(.check, size: 14)
                        .foregroundColor(Palette.pastelBlue)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected || hovered ? Color.overlay(0.06) : Palette.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? Palette.pastelBlue.opacity(0.4) : Palette.border,
                                    lineWidth: 0.5)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
