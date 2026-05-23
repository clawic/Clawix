import SwiftUI

struct ConfigurationPage: View {
    @EnvironmentObject var appState: AppState
    @AppStorage(ClawixPersistentSurfaceKeys.settingsConfigurationScope) private var configScope: String = "User settings"
    @State private var openingConfig = false

    private var projectConfigUnavailable: Bool {
        configScope == "Project settings" && (appState.selectedProject?.path.isEmpty ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Settings",
                subtitle: "Configure the approval policy and sandbox settings. Learn more"
            )

            Text("Custom config.toml settings")
                .font(BodyFont.system(size: 13, wght: 600))
                .foregroundColor(Palette.textPrimary)
                .padding(.bottom, 14)

            ReplacementBanner()
                .padding(.bottom, 14)

            HStack {
                SettingsDropdown(
                    options: [
                        ("User settings", "User settings"),
                        ("Project settings", "Project settings")
                    ],
                    selection: $configScope,
                    minWidth: 230
                )
                Spacer()
                Button {
                    openConfigToml()
                } label: {
                    HStack(spacing: 4) {
                        Text(openingConfig ? "Opening…" : "Open config.toml")
                            .font(BodyFont.system(size: 12, wght: 500))
                            .foregroundColor(Palette.textSecondary)
                        LucideIcon(.arrowUpRight, size: 10)
                            .foregroundColor(Palette.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(openingConfig || projectConfigUnavailable)
            }
            .padding(.bottom, 8)
            .liftWhenSettingsDropdownOpen()

            if projectConfigUnavailable {
                InfoBanner(
                    text: "Select a project before opening project config.",
                    kind: .danger
                )
                .padding(.bottom, 8)
            }

            SectionLabel(title: "Permissions")
            SettingsCard {
                PermissionToggleRow(
                    mode: .defaultPermissions,
                    title: "Default permissions",
                    detail: "By default, Clawix can read and edit files in your workspace. It can request additional access when needed."
                )
                CardDivider()
                PermissionToggleRow(
                    mode: .autoReview,
                    title: "Automatic review",
                    detail: "Clawix can read and edit files in your workspace. Clawix automatically reviews requests for additional access. Auto-review may make mistakes. Learn more about the elevated risks."
                )
                CardDivider()
                PermissionToggleRow(
                    mode: .fullAccess,
                    title: "Full access",
                    detail: "When Clawix runs with full access, it can edit any file on your computer and run commands over the network without your authorization. This significantly increases the risk of data loss, leaks, or unexpected behavior. Learn more about the elevated risks."
                )
            }

            SectionLabel(title: "Workspace dependencies")
            SettingsCard {
                HStack {
                    Text("Current version")
                        .font(BodyFont.system(size: 13, wght: 500))
                        .foregroundColor(Palette.textPrimary)
                    Spacer()
                    Text(AppVersion.displayString)
                        .font(BodyFont.system(size: 12, design: .monospaced))
                        .foregroundColor(Palette.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                CardDivider()
                WorkspaceDependencyStatusRow(
                    title: "Bundled dependencies",
                    detail: "Bundled Node.js and Python tools are packaged with the app; Settings does not enable or install them directly.",
                    status: "Packaged"
                )
                CardDivider()
                ActionPillRow(
                    title: "Diagnose Clawix Workspace issues",
                    detail: "Check the current bundle and save diagnostic logs",
                    primaryLabel: "Diagnose",
                    onPrimary: { SettingsUtilities.revealDiagnosticsFolder() }
                )
                CardDivider()
                ReinstallRow()
            }
        }
        .onAppear(perform: normalizeConfigScope)
    }

    private func normalizeConfigScope() {
        guard configScope == "User settings" || configScope == "Project settings" else {
            configScope = "User settings"
            return
        }
    }

    private func openConfigToml() {
        openingConfig = true
        Task { @MainActor in
            await SettingsUtilities.openConfigToml(scope: configScope, selectedProject: appState.selectedProject)
            openingConfig = false
        }
    }
}

struct PermissionToggleRow: View {
    @EnvironmentObject var appState: AppState
    let mode: PermissionMode
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        let binding = Binding<Bool>(
            get: { appState.permissionMode == mode },
            set: { newValue in
                guard newValue else { return }
                appState.permissionMode = mode
            }
        )
        ToggleRow(title: title, detail: detail, isOn: binding)
    }
}

struct ReplacementBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            LucideIcon(.circleAlert, size: 13)
                .foregroundColor(Palette.warning)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 0) {
                    InlineCode("[features].collab")
                    Text(" has been replaced. Use ")
                        .foregroundColor(Color.gray(light: 0.20, dark: 0.85))
                    InlineCode("[features].multi_agent")
                    Text(" instead.")
                        .foregroundColor(Color.gray(light: 0.20, dark: 0.85))
                }
                .font(BodyFont.system(size: 12, wght: 500))
                HStack(spacing: 0) {
                    Text("Enable it with ").foregroundColor(Color.gray(light: 0.28, dark: 0.75))
                    InlineCode("--enable multi_agent")
                    Text(" or ").foregroundColor(Color.gray(light: 0.28, dark: 0.75))
                    InlineCode("[features].multi_agent")
                    Text(" in config.toml. See").foregroundColor(Color.gray(light: 0.28, dark: 0.75))
                }
                .font(BodyFont.system(size: 11.5, wght: 500))
                HStack(spacing: 4) {
                    LucideIcon(.globe, size: 11)
                        .foregroundColor(Palette.pastelBlue)
                    Text("Toggle developer-only surfaces by editing the configuration file.")
                        .font(BodyFont.system(size: 11.5, wght: 500))
                        .foregroundColor(Palette.pastelBlue)
                    Text("for details.")
                        .font(BodyFont.system(size: 11.5, wght: 500))
                        .foregroundColor(Color.gray(light: 0.28, dark: 0.75))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.18, green: 0.10, blue: 0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(red: 0.55, green: 0.30, blue: 0.10), lineWidth: 0.7)
                )
        )
    }
}

struct InlineCode: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(BodyFont.system(size: 11.5, design: .monospaced))
            .foregroundColor(Color.gray(light: 0.11, dark: 0.95))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.overlay(0.08))
            )
    }
}

struct ReinstallRow: View {
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Reset and install workspace")
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                Text("Unavailable here until a signed launcher route can reset dependencies with a dry-run report.")
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer(minLength: 12)
            Text("Blocked")
                .font(BodyFont.system(size: 11.5, wght: 600))
                .foregroundColor(Palette.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
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

struct WorkspaceDependencyStatusRow: View {
    let title: LocalizedStringKey
    let detail: String
    let status: LocalizedStringKey

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
            Text(status)
                .font(BodyFont.system(size: 11.5, wght: 600))
                .foregroundColor(Palette.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
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
