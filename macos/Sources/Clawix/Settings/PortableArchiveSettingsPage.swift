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

    var detail: String {
        switch self {
        case .ready:
            return ".clawbackup can be planned, verified, previewed, and restored after approval."
        case .verificationFailed:
            return "The archive manifest, hashes, compatibility range, or restore graph did not verify."
        case .secretsRequireReauth:
            return ".clawsecrets export, import, and restore require strong reauthentication in this signed host."
        case .externalSourceReferenced:
            return "External read-only sources are referenced with provenance and sync metadata."
        case .cacheWillRebuild:
            return "Rebuildable caches and search indexes are excluded and rebuilt from canonical data."
        case .restoreBlocked:
            return "Restore waits for import preview, verification, signed-host proof when needed, and explicit approval."
        case .restoreComplete:
            return "Restore report is available with counts, target root, approvals, and redacted receipts."
        }
    }
}

struct PortableArchiveSettingsPage: View {
    @State private var state: PortableArchiveUXState = .ready

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Data",
                subtitle: "Export, verify, import, and restore full portable archives."
            )

            InfoBanner(text: state.detail, kind: bannerKind)
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
                IconChipButton(symbol: "archivebox", label: "Export", isPrimary: true) {
                    state = .secretsRequireReauth
                }
            }
            CardDivider()
            SettingsRow {
                RowLabel(
                    title: "Verify archive",
                    detail: "Check manifest.json, hashes, compatibility, external references, cache exclusions, and restore graph."
                )
            } trailing: {
                IconChipButton(symbol: "checkmark.shield", label: "Verify") {
                    state = .ready
                }
            }
            CardDivider()
            SettingsRow {
                RowLabel(
                    title: "Inspect manifest",
                    detail: "Show deterministic inventory, counts, restore report schema, redacted receipts, and referenced external sources."
                )
            } trailing: {
                IconChipButton(symbol: "doc.text.magnifyingglass", label: "Inspect") {
                    state = .externalSourceReferenced
                }
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
                IconChipButton(symbol: "arrow.down.doc", label: "Preview") {
                    state = .cacheWillRebuild
                }
            }
            CardDivider()
            SettingsRow {
                RowLabel(
                    title: "Restore",
                    detail: "Apply only after successful verification, explicit approval, and signed-host proof for encrypted secrets."
                )
            } trailing: {
                IconChipButton(symbol: "arrow.counterclockwise", label: "Restore") {
                    state = .restoreBlocked
                }
            }
            CardDivider()
            SettingsRow {
                RowLabel(
                    title: "Restore report",
                    detail: "Review restored counts, target root, blocked reasons, approvals, file hashes, and redacted receipts."
                )
            } trailing: {
                IconChipButton(symbol: "doc.text", label: "Report") {
                    state = .restoreComplete
                }
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
                    Text(item == state ? "Current" : "")
                        .font(BodyFont.system(size: 11.5, wght: 600))
                        .foregroundColor(item == state ? Palette.textPrimary : .clear)
                }
            }
        }
    }

    private var bannerKind: InfoBanner.Kind {
        switch state {
        case .verificationFailed, .restoreBlocked:
            return .error
        case .secretsRequireReauth:
            return .danger
        default:
            return .ok
        }
    }
}
