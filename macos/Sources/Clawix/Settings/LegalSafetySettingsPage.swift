import SwiftUI

struct LegalSafetySettingsPage: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var legal = LegalSafetyStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Legal & Safety",
                subtitle: "Local consent, sensitive-domain review, external data sharing, and audit defaults."
            )

            SectionLabel(title: "Acceptance")
            SettingsCard {
                LegalStatusRow(legal: legal)
                CardDivider()
                ActionPillRow(
                    title: "Current legal documents",
                    detail: "Terms, Privacy, Disclaimer, Safety, Regulated Domains, and EULA versions are 2026-05-18.",
                    primaryLabel: legal.hasAcceptedCurrentLegal ? "Accepted" : "Accept",
                    trailingDisabled: legal.hasAcceptedCurrentLegal ? "Current" : "Required",
                    isEnabled: !legal.hasAcceptedCurrentLegal,
                    onPrimary: { legal.acceptCurrentLegal() }
                )
                CardDivider()
                ActionPillRow(
                    title: "Review acceptance again",
                    detail: "Clears the local acceptance record so the next app surface shows the legal acceptance gate again.",
                    primaryLabel: "Reset",
                    trailingDisabled: "Local",
                    isEnabled: true,
                    onPrimary: { legal.resetAcceptanceForReview() }
                )
            }

            SectionLabel(title: "Sensitive actions")
            SettingsCard {
                ToggleRow(
                    title: "Confirm sensitive exports and shares",
                    detail: "Require an explicit review before exporting or sharing material that may include regulated or sensitive data.",
                    isOn: $legal.sensitiveExportConfirmationRequired
                )
                CardDivider()
                ToggleRow(
                    title: "Remote and sync opt-in",
                    detail: "Allow sensitive data to use remote or sync flows only after explicit local opt-in. Individual sensitive actions still show review gates.",
                    isOn: $legal.remoteSyncOptIn
                )
                CardDivider()
                ToggleRow(
                    title: "Provider disclosure opt-in",
                    detail: "Allow configured providers to receive sensitive prompts or records only after explicit local opt-in. Provider terms remain the user's responsibility.",
                    isOn: $legal.providerDisclosureOptIn
                )
                CardDivider()
                ToggleRow(
                    title: "Support diagnostics opt-in",
                    detail: "Allow manually selected support diagnostics to be shared. Logs, screenshots, databases, provider traces, and workspaces should be redacted first.",
                    isOn: $legal.supportDiagnosticsOptIn
                )
            }

            SectionLabel(title: "Audit")
            SettingsCard {
                LegalAuditRetentionRow(legal: legal)
            }

            SectionLabel(title: "Output labels")
            SettingsCard {
                LegalLabelsRow()
            }

            InfoBanner(
                text: LegalSafetyPolicy.crisisDisclaimer,
                kind: .danger
            )
            .padding(.top, 18)
        }
    }
}

private struct LegalStatusRow: View {
    @ObservedObject var legal: LegalSafetyStore

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("18+ and legal acceptance")
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                Text(legal.acceptedVersionSummary)
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer(minLength: 12)
            Text(legal.hasAcceptedCurrentLegal ? "Current" : "Required")
                .font(BodyFont.system(size: 11, wght: 700))
                .foregroundColor(legal.hasAcceptedCurrentLegal ? .green : .orange)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct LegalAuditRetentionRow: View {
    @ObservedObject var legal: LegalSafetyStore

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            RowLabel(
                title: "Local audit retention",
                detail: "How long local legal/safety review receipts should be retained by default."
            )
            Spacer(minLength: 12)
            Stepper(value: $legal.localAuditRetentionDays, in: 7...3650, step: 30) {
                Text("\(legal.localAuditRetentionDays) days")
                    .font(BodyFont.system(size: 12, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                    .frame(width: 84, alignment: .trailing)
            }
            .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct LegalLabelsRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RowLabel(
                title: "Mandatory sensitive output labels",
                detail: "Sensitive outputs carry review labels that exports, provider flows, remote/sync, and external actions must preserve."
            )
            Text(LegalSafetyPolicy.defaultOutputLabels.joined(separator: " · "))
                .font(BodyFont.system(size: 11, wght: 600))
                .foregroundColor(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
