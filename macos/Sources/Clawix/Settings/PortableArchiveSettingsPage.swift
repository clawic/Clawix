import SwiftUI

enum PortableArchiveUXState: String, CaseIterable {
    case ready
    case verificationFailed
    case secretsRequireReauth
    case externalSourceReferenced
    case cacheWillRebuild
    case restoreBlocked
    case restoreComplete

    var label: String {
        switch self {
        case .ready: return "Ready"
        case .verificationFailed: return "Verification failed"
        case .secretsRequireReauth: return "Secrets require reauth"
        case .externalSourceReferenced: return "External source referenced"
        case .cacheWillRebuild: return "Cache will rebuild"
        case .restoreBlocked: return "Restore blocked"
        case .restoreComplete: return "Restore complete"
        }
    }

    var status: String {
        switch self {
        case .ready, .cacheWillRebuild:
            return "Contract"
        case .restoreComplete:
            return "Report"
        default:
            return "Gate"
        }
    }

    var detail: String {
        switch self {
        case .ready:
            return ".clawbackup can be planned, verified, previewed, and restored only through a signed host route with approval evidence."
        case .verificationFailed:
            return "The archive manifest, hashes, compatibility range, or restore graph did not verify."
        case .secretsRequireReauth:
            return ".clawsecrets export, import, and restore require strong reauthentication in this signed host."
        case .externalSourceReferenced:
            return "External read-only sources are referenced with provenance and sync metadata."
        case .cacheWillRebuild:
            return "Rebuildable caches and search indexes are excluded and rebuilt from canonical data."
        case .restoreBlocked:
            return "Restore waits for import preview, verification, signed-host proof when needed, explicit approval, and exact target confirmation."
        case .restoreComplete:
            return "Restore report is available with counts, target root, approvals, and redacted receipts."
        }
    }
}

private enum PortableArchiveAction: CaseIterable {
    case exportFullBackup
    case verifyArchive
    case inspectManifest
    case importPreview
    case restore
    case restoreReport

    var title: LocalizedStringKey {
        switch self {
        case .exportFullBackup: return "Export full backup"
        case .verifyArchive: return "Verify archive"
        case .inspectManifest: return "Inspect manifest"
        case .importPreview: return "Import preview"
        case .restore: return "Restore"
        case .restoreReport: return "Restore report"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .exportFullBackup:
            return ".clawbackup includes canonical data, files, instructions, skills, sessions, audit metadata, policies, grants, and encrypted secrets envelopes."
        case .verifyArchive:
            return "Check manifest.json, hashes, compatibility, external references, cache exclusions, and restore graph."
        case .inspectManifest:
            return "Show deterministic .clawexport and .clawbackup inventory, counts, restore report schema, redacted receipts, and referenced external sources."
        case .importPreview:
            return "Map archive contents into a new or selected target before anything is applied."
        case .restore:
            return "Apply only after successful verification, explicit approval, exact target confirmation, and signed-host proof for encrypted secrets."
        case .restoreReport:
            return "Review restored counts, target root, blocked reasons, approvals, file hashes, and redacted receipts."
        }
    }

    var status: String {
        switch self {
        case .restoreReport:
            return L10n.t("External pending")
        default:
            return L10n.t("Blocked")
        }
    }

    var blockedReason: String {
        switch self {
        case .exportFullBackup:
            return L10n.t("Blocked until the signed host route returns a dry-run archive plan and approval evidence.")
        case .verifyArchive:
            return L10n.t("Blocked until Settings receives a verification report from the signed host route.")
        case .inspectManifest:
            return L10n.t("Blocked until the signed host route returns a redacted manifest inspection result.")
        case .importPreview:
            return L10n.t("Blocked until the signed host route returns an import preview without applying changes.")
        case .restore:
            return L10n.t("Blocked until import preview, verification, signed-host proof, explicit approval, and exact target confirmation all pass.")
        case .restoreReport:
            return L10n.t("External pending until a completed restore report exists; Settings does not synthesize one.")
        }
    }

    var source: String {
        switch self {
        case .exportFullBackup:
            return L10n.t("Source: claw archive plan/export --signed-host")
        case .verifyArchive:
            return L10n.t("Source: claw archive verify --signed-host")
        case .inspectManifest:
            return L10n.t("Source: claw archive inspect --signed-host")
        case .importPreview:
            return L10n.t("Source: claw archive import --signed-host")
        case .restore:
            return L10n.t("Source: claw archive restore --signed-host")
        case .restoreReport:
            return L10n.t("Source: PortableArchiveRestoreReport from signed host")
        }
    }
}

struct PortableArchiveSettingsPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Data",
                subtitle: "Export, verify, import, and restore full portable archives."
            )

            InfoBanner(
                text: "Portable archive contracts are documented, but Settings cannot execute export, verify, preview, restore, or report actions until a signed host route returns dry-run and result evidence.",
                kind: .danger
            )
                .padding(.bottom, 10)

            archiveSection
            restoreSection
            statusSection
        }
    }

    @ViewBuilder
    private var archiveSection: some View {
        SectionLabel(title: "Portable archive")
        SettingsCard {
            portableArchiveActionRows([
                .exportFullBackup,
                .verifyArchive,
                .inspectManifest
            ])
        }
    }

    @ViewBuilder
    private var restoreSection: some View {
        SectionLabel(title: "Import and restore")
        SettingsCard {
            portableArchiveActionRows([
                .importPreview,
                .restore,
                .restoreReport
            ])
        }
    }

    @ViewBuilder
    private func portableArchiveActionRows(_ actions: [PortableArchiveAction]) -> some View {
        ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
            if index > 0 {
                CardDivider()
            }
            SettingsRow {
                VStack(alignment: .leading, spacing: 6) {
                    RowLabel(title: action.title, detail: action.detail)
                    Text(action.blockedReason)
                        .font(BodyFont.system(size: 10.8, wght: 600))
                        .foregroundColor(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(action.source)
                        .font(BodyFont.system(size: 10.5, wght: 600))
                        .foregroundColor(Palette.textTertiary)
                        .textSelection(.enabled)
                }
            } trailing: {
                PortableArchiveActionStatus(
                    label: action.status,
                    reason: action.blockedReason,
                    source: action.source
                )
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        SectionLabel(title: "Status")
        SettingsCard {
            ForEach(Array(PortableArchiveUXState.allCases.enumerated()), id: \.element.rawValue) { index, item in
                if index > 0 {
                    CardDivider()
                }
                SettingsRow {
                    RowLabel(title: LocalizedStringKey(item.label), detail: LocalizedStringKey(item.detail))
                } trailing: {
                    PortableArchiveActionStatus(
                        label: item.status,
                        reason: L10n.t("Canonical portable archive state exposed for Settings/Data inspection."),
                        source: L10n.t("Source: ADR 0034 mirror and ClawJS portable archive contract")
                    )
                }
            }
        }
    }
}

private struct PortableArchiveActionStatus: View {
    let label: String
    let reason: String
    let source: String

    var body: some View {
        Text(label)
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
            .accessibilityLabel(Text(label))
            .accessibilityHint(Text("\(reason) \(source)"))
    }
}
