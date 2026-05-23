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
                if let error = settings.policySyncError {
                    InfoBanner(text: error, kind: .error)
                    CardDivider()
                }
                ToggleRow(
                    title: "Any app",
                    detail: "Allow the agent to request control of any running app. Accessibility is still required and unlisted apps still go through the per-app approval path.",
                    isOn: $settings.anyAppEnabled
                )
                CardDivider()
                ComputerUseCapabilityStatusRow(
                    title: "Use while locked",
                    detail: "Blocked until the signed host consumes lock-screen state and the persisted locked-use policy.",
                    status: "Blocked"
                )
            }

            SectionLabel(title: "Always-allowed apps")
            SettingsCard {
                if let error = settings.allowedAppsLoadError {
                    InfoBanner(text: error, kind: .error)
                    CardDivider()
                }
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
                                .accessibilityLabel(Text("Remove \(app.name) from always-allowed apps"))
                                .help(String(
                                    format: L10n.t("Remove %@ from always-allowed apps"),
                                    locale: AppLocale.current,
                                    app.name
                                ))
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

private struct ComputerUseCapabilityStatusRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let status: LocalizedStringKey

    var body: some View {
        SettingsRow {
            RowLabel(title: title, detail: detail)
        } trailing: {
            Text(status)
                .font(BodyFont.system(size: 11, wght: 700))
                .foregroundColor(Color.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.orange.opacity(0.12))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.orange.opacity(0.25), lineWidth: 0.5)
                        )
                )
                .accessibilityLabel(Text(status))
        }
    }
}
