import SwiftUI

/// Settings → Computer Use: an Accessibility permission row (required), an
/// "Any app" toggle, a "Use while locked" toggle, and the removable
/// always-allowed apps list. The agent drives apps through the signed host
/// (AXUIElement + per-process events); the system pointer never moves and the
/// target app stays backgrounded.
struct ComputerUseSettingsPage: View {
    @StateObject private var settings = ComputerUseSettings.shared
    @State private var permissions: [MacControlPermissionSnapshot] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Computer Use",
                subtitle: "Let the agent control other Mac apps through the signed host. Actions use accessibility, so your pointer never moves and the target app stays in the background."
            )

            SectionLabel(title: "Permission")
            SettingsCard {
                accessibilityRow
            }

            SectionLabel(title: "Access")
            SettingsCard {
                ToggleRow(
                    title: "Any app",
                    detail: "Allow the agent to control any running app. Turn this off to limit control to the always-allowed list below.",
                    isOn: $settings.anyAppEnabled
                )
                CardDivider()
                ToggleRow(
                    title: "Use while locked",
                    detail: "Allow Computer Use to keep running while the Mac is locked.",
                    isOn: $settings.lockedUseEnabled
                )
            }

            SectionLabel(title: "Always-allowed apps")
            SettingsCard {
                if settings.alwaysAllowedApps.isEmpty {
                    SettingsRow {
                        RowLabel(
                            title: "No always-allowed apps",
                            detail: "Apps you approve with \u{201C}Always allow\u{201D} appear here and skip the per-app prompt."
                        )
                    } trailing: {
                        EmptyView()
                    }
                } else {
                    let apps = settings.alwaysAllowedApps
                    ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                        SettingsRow {
                            RowLabel(
                                title: LocalizedStringKey(app.name),
                                detail: app.bundleId.map { LocalizedStringKey($0) }
                            )
                        } trailing: {
                            Button("Remove") { settings.remove(app) }
                                .buttonStyle(.plain)
                                .font(BodyFont.system(size: 12, wght: 600))
                                .foregroundColor(Palette.textSecondary)
                        }
                        if index < apps.count - 1 { CardDivider() }
                    }
                }
            }
        }
        .onAppear { permissions = MacControlPermissionSnapshot.current }
    }

    private var accessibilityRow: some View {
        let snapshot = permissions.first {
            $0.id == NativeMacPermissionBroker.PermissionID.accessibility.rawValue
        }
        let blocked = snapshot?.isBlocked ?? true
        return SettingsRow {
            RowLabel(
                title: "Accessibility",
                detail: "Required. Computer Use reads the accessibility tree and posts events to the target app."
            )
        } trailing: {
            HStack(spacing: 10) {
                Text(verbatim: snapshot?.status ?? "Unknown")
                    .font(BodyFont.system(size: 12, wght: 600))
                    .foregroundColor(blocked ? Palette.textPrimary : Palette.textSecondary)
                if blocked {
                    Button("Open Settings") {
                        NativeMacPermissionBroker.openSettings(for: .accessibility)
                    }
                    .buttonStyle(.plain)
                    .font(BodyFont.system(size: 12, wght: 600))
                    .foregroundColor(Color.accentColor)
                }
            }
        }
    }
}
