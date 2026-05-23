import SwiftUI

struct GitPage: View {
    @EnvironmentObject var appState: AppState

    private var selectedProject: Project? {
        appState.selectedProject
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Git",
                subtitle: "Git settings only expose state or actions backed by the current project and runtime contracts."
            )

            SectionLabel(title: "Current project")
            SettingsCard {
                GitStatusRow(
                    title: "Project",
                    detail: selectedProject?.name ?? "No project selected",
                    status: selectedProject == nil ? L10n.t("Unavailable") : L10n.t("Selected")
                )
                CardDivider()
                GitStatusRow(
                    title: "Folder state",
                    detail: folderStateDetail,
                    status: folderStateStatus
                )
                CardDivider()
                ActionPillRow(
                    title: "Project folder",
                    detail: selectedProject.map { LocalizedStringKey($0.path) } ?? "Select a project before opening its folder.",
                    primaryLabel: "Open",
                    isEnabled: selectedProject != nil,
                    onPrimary: openProjectFolder
                )
            }

            SectionLabel(title: "Automation defaults")
            SettingsCard {
                GitStatusRow(
                    title: "Branch and PR defaults",
                    detail: "Disabled until ClawJS exposes a Git defaults route consumed by chat and commit actions.",
                    status: L10n.t("Blocked")
                )
                CardDivider()
                GitStatusRow(
                    title: "Commit instructions",
                    detail: "No active prompt path reads Git-specific instructions, so this field is not editable here.",
                    status: L10n.t("Not wired")
                )
                CardDivider()
                GitStatusRow(
                    title: "Destructive Git actions",
                    detail: "Force-push, merge, and worktree cleanup require explicit signed-host approval and route evidence before Settings can expose controls.",
                    status: L10n.t("External pending")
                )
            }
        }
    }

    private var folderStateDetail: String {
        guard let project = selectedProject else {
            return "No selected project folder to inspect."
        }
        switch project.folderState {
        case .active:
            return "Project folder is present at \(project.path)."
        case .missing:
            return "Project folder is missing at \(project.path)."
        case .detached:
            return "Project folder is detached at \(project.path)."
        case .duplicate:
            return "Project folder is attached to another workspace at \(project.path)."
        }
    }

    private var folderStateStatus: String {
        guard let project = selectedProject else { return L10n.t("Unavailable") }
        switch project.folderState {
        case .active: return L10n.t("Ready")
        case .missing: return L10n.t("Missing")
        case .detached: return L10n.t("Detached")
        case .duplicate: return L10n.t("Duplicate")
        }
    }

    private func openProjectFolder() {
        guard let project = selectedProject else { return }
        let url = URL(fileURLWithPath: (project.path as NSString).expandingTildeInPath, isDirectory: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

struct GitStatusRow: View {
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
                .font(BodyFont.system(size: 11.5, wght: 600))
                .foregroundColor(Palette.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
