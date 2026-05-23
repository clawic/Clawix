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
            SettingsRow {
                RowLabel(
                    title: "Export full backup",
                    detail: ".clawbackup includes canonical data, files, instructions, skills, sessions, audit metadata, policies, grants, and encrypted secrets envelopes."
                )
            } trailing: {
                PortableArchiveActionStatus(label: "Blocked")
            }
            CardDivider()
            SettingsRow {
                RowLabel(
                    title: "Verify archive",
                    detail: "Check manifest.json, hashes, compatibility, external references, cache exclusions, and restore graph."
                )
            } trailing: {
                PortableArchiveActionStatus(label: "Blocked")
            }
            CardDivider()
            SettingsRow {
                RowLabel(
                    title: "Inspect manifest",
                    detail: "Show deterministic .clawexport and .clawbackup inventory, counts, restore report schema, redacted receipts, and referenced external sources."
                )
            } trailing: {
                PortableArchiveActionStatus(label: "Blocked")
            }
        }
    }

    @ViewBuilder
    private var restoreSection: some View {
        SectionLabel(title: "Import and restore")
        SettingsCard {
            SettingsRow {
                RowLabel(
                    title: "Import preview",
                    detail: "Map archive contents into a new or selected target before anything is applied."
                )
            } trailing: {
                PortableArchiveActionStatus(label: "Blocked")
            }
            CardDivider()
            SettingsRow {
                RowLabel(
                    title: "Restore",
                    detail: "Apply only after successful verification, explicit approval, exact target confirmation, and signed-host proof for encrypted secrets."
                )
            } trailing: {
                PortableArchiveActionStatus(label: "Blocked")
            }
            CardDivider()
            SettingsRow {
                RowLabel(
                    title: "Restore report",
                    detail: "Review restored counts, target root, blocked reasons, approvals, file hashes, and redacted receipts."
                )
            } trailing: {
                PortableArchiveActionStatus(label: "Pending")
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
                    PortableArchiveActionStatus(label: LocalizedStringKey(item.status))
                }
            }
        }
    }
}

private struct PortableArchiveActionStatus: View {
    let label: LocalizedStringKey

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
    }
}
