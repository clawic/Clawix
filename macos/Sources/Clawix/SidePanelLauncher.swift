import SwiftUI

// MARK: - Side-panel launcher
//
// Empty-state of the right side panel: a small grid of tiles that pick
// what the panel should show — Files (project tree), Browser (a website),
// Review (git changes) and Terminal (the bottom shell). Shown when the
// side panel is opened with nothing active yet. Tiles reuse the card
// recipe from STYLE.md §6.7.

struct SidePanelLauncher: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var flags: FeatureFlags

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                LazyVGrid(columns: columns, spacing: 12) {
                    LauncherTile(
                        icon: .files,
                        title: L10n.t("Files"),
                        subtitle: L10n.t("Browse project files")
                    ) { appState.openFileTreeInSidebar() }

                    if flags.isVisible(.browserUsage) {
                        LauncherTile(
                            icon: .browser,
                            title: L10n.t("Browser"),
                            subtitle: L10n.t("Open a website")
                        ) { appState.openBrowser() }
                    }

                    LauncherTile(
                        icon: .review,
                        title: L10n.t("Review"),
                        subtitle: L10n.t("View code changes")
                    ) { appState.openReviewInSidebar() }

                    LauncherTile(
                        icon: .terminal,
                        title: L10n.t("Terminal"),
                        subtitle: L10n.t("Start an interactive shell"),
                        enabled: appState.canHostIntegratedTerminal
                    ) { appState.openIntegratedTerminal() }
                }

                if flags.isVisible(.simulators) {
                    LazyVGrid(columns: columns, spacing: 12) {
                        LauncherTile(
                            icon: .iosSimulator,
                            title: L10n.t("iOS Simulator"),
                            subtitle: L10n.t("Run an iOS device")
                        ) { appState.openIOSSimulator() }

                        LauncherTile(
                            icon: .androidSimulator,
                            title: L10n.t("Android Emulator"),
                            subtitle: L10n.t("Run an Android device")
                        ) { appState.openAndroidSimulator() }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 22)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
        .thinScrollers()
    }
}

private struct LauncherTile: View {
    enum Icon {
        case files, browser, review, terminal, iosSimulator, androidSimulator
    }

    let icon: Icon
    let title: String
    let subtitle: String
    var enabled: Bool = true
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                glyph
                    .foregroundColor(enabled ? Color(white: 0.92) : Color(white: 0.45))
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(BodyFont.system(size: 13.5, wght: 600))
                        .foregroundColor(enabled ? Palette.textPrimary : Palette.textSecondary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(BodyFont.system(size: 11.5, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(hovered && enabled ? Palette.cardHover : Palette.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Palette.popupStroke, lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }

    @ViewBuilder
    private var glyph: some View {
        switch icon {
        case .files:            FolderStackIcon(size: 21)
        case .browser:          GlobeIcon(size: 22)
        case .review:           GitCompareIcon(size: 22)
        case .terminal:         TerminalIcon(size: 22)
        case .iosSimulator:     LucideIcon(.appWindow, size: 21)
        case .androidSimulator: LucideIcon.auto("smartphone", size: 21)
        }
    }
}
