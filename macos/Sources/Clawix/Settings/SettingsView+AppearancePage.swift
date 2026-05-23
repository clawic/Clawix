import SwiftUI

struct AppearancePage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Appearance",
                subtitle: "Appearance controls are hidden until Settings has a persisted theme contract and renderer acknowledgement."
            )

            SectionLabel(title: "Theme")
            SettingsCard {
                AppearanceCapabilityStatusRow(
                    title: "Theme mode",
                    detail: "Blocked until theme mode is backed by a registered preference and consumed by the app shell.",
                    status: "Blocked"
                )
                CardDivider()
                AppearanceCapabilityStatusRow(
                    title: "Theme library",
                    detail: "Blocked until theme import, export, validation, and persistence routes exist.",
                    status: "Blocked"
                )
                CardDivider()
                AppearanceCapabilityStatusRow(
                    title: "Renderer acknowledgement",
                    detail: "Blocked until Settings must receive success or failure from the renderer before claiming a theme is active.",
                    status: "Blocked"
                )
            }
        }
    }
}

private struct AppearanceCapabilityStatusRow: View {
    let title: LocalizedStringKey
    let detail: String
    let status: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textPrimary)
                Text(verbatim: detail)
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Text(verbatim: status)
                .font(BodyFont.system(size: 11, wght: 600))
                .foregroundColor(Palette.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.overlay(0.06))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.overlay(0.10), lineWidth: 0.5)
                        )
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
