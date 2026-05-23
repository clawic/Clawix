import SwiftUI

/// Settings tab for the global Skills system. Per-skill configuration
/// (activation, parameters, sync targets) lives in `SkillDetailView`.
/// This page is for everything that applies across the whole library:
///
/// - Registered sync targets (Codex, Hermes, Cursor, custom).
/// - External dirs projected for discovery.
/// - Blocked auto-import and sync-target editing states until the framework
///   exposes a persisted scan/sync-target route.
///
/// Visual language matches the rest of Settings (`PageHeader`,
/// `SectionLabel`, `SettingsCard`, `CardDivider`, `Palette`). The page
/// returns a bare `VStack`; the host `SettingsView` owns the scroll
/// container, max width and padding.
struct SkillsSettingsPage: View {
    @EnvironmentObject var appState: AppState

    private var store: SkillsStore? { appState.skillsStore }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Skills",
                subtitle: "System-wide settings for the Skills library. Per-skill configuration lives in the catalog."
            )

            SectionLabel(title: "Auto-import")
            SettingsCard {
                SkillsCapabilityStatusRow(
                    title: "Startup scan",
                    detail: "Blocked until the framework exposes a persisted scan policy and last-scan report consumed by the Skills boot path.",
                    status: "Blocked"
                )
            }

            SectionLabel(title: "Sync targets")
            SettingsCard {
                CardCaption("Default routes projected by ClawixSkillsRoutes. Settings shows the current in-memory targets but cannot edit them until a framework sync-target registry persists changes.")
                CardDivider()
                ForEach(store?.syncTargets ?? []) { target in
                    syncTargetRow(target)
                    CardDivider()
                }
                SkillsCapabilityStatusRow(
                    title: "Custom targets",
                    detail: "Blocked until target create/remove writes through a persisted framework record and returns sync evidence.",
                    status: "Blocked"
                )
            }

            SectionLabel(title: "External dirs")
            SettingsCard {
                CardCaption("Known external skill folders, read-only. Settings only reports whether they exist; no import or symlink operation runs from this page.")
                CardDivider()
                ForEach(Array(ClawixSkillsRoutes.defaultExternalDirectories.prefix(2))) { directory in
                    externalDirRow(path: directory.displayPath, agent: directory.label)
                    CardDivider()
                }
                SkillsCapabilityStatusRow(
                    title: "Custom directories",
                    detail: "Blocked until a persisted directory registry and scan report are available.",
                    status: "Blocked"
                )
            }
        }
        .onAppear {
            appState.ensureSkillsStoreLoaded()
        }
    }

    private func syncTargetRow(_ target: SkillSyncTarget) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(target.label)
                    .font(BodyFont.system(size: 12.5, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text(target.home)
                    .font(BodyFont.system(size: 11, design: .monospaced))
                    .foregroundColor(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            StatusBadge(text: target.mode.rawValue, tone: .neutral)
            Text("Read-only")
                .font(BodyFont.system(size: 11, wght: 500))
                .foregroundColor(Palette.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func externalDirRow(path: String, agent: String) -> some View {
        let exists = FileManager.default.fileExists(atPath: (path as NSString).expandingTildeInPath)
        return HStack(spacing: 12) {
            IconImage("folder", size: 14)
                .foregroundColor(Palette.textSecondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(path)
                    .font(BodyFont.system(size: 12, design: .monospaced))
                    .foregroundColor(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(agent)
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer(minLength: 12)
            StatusBadge(text: exists ? "Found" : "Not present",
                        tone: exists ? .positive : .neutral)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

/// Leading descriptive caption inside a `SettingsCard`, for context that
/// the canon `SectionLabel` (label-only) cannot carry.
private struct CardCaption: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(BodyFont.system(size: 11.5, wght: 500))
            .foregroundColor(Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
    }
}

/// Small capsule status badge matching the canonical row badge
/// (`WorkspaceDependencyStatusRow`). `positive` tints a muted brand-safe
/// green for "exists"; `neutral` is the standard white-on-dark chip.
private struct StatusBadge: View {
    enum Tone { case neutral, positive }
    let text: String
    var tone: Tone = .neutral

    private static let positiveColor = Color(red: 0.45, green: 0.78, blue: 0.55)

    var body: some View {
        Text(text)
            .font(BodyFont.system(size: 11, wght: 600))
            .foregroundColor(tone == .positive ? Self.positiveColor : Palette.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(tone == .positive
                          ? Self.positiveColor.opacity(0.12)
                          : Color.white.opacity(0.06))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(tone == .positive
                                    ? Self.positiveColor.opacity(0.22)
                                    : Color.white.opacity(0.10),
                                    lineWidth: 0.5)
                    )
            )
    }
}

private struct SkillsCapabilityStatusRow: View {
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
            StatusBadge(text: status, tone: .neutral)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
