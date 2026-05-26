import SwiftUI

extension ClawJSRuntimeLensSection {
    func runtimeLensSupport(
        _ support: ClawJSRuntimeLensSnapshot.Support,
        officialSnapshot: ClawJSRuntimeLensSnapshot.OfficialSnapshot? = nil
    ) -> some View {
        let presentation = ClawJSRuntimeLensSupportOverviewPresentation.make(
            support: support,
            officialSnapshot: officialSnapshot
        )

        return VStack(alignment: .leading, spacing: 6) {
            row(label: "Support") {
                HStack(spacing: 8) {
                    if let adapterLevel = presentation.adapterSupportLevel {
                        statusPill(text: "adapter \(adapterLevel)", color: adapterLevel == "production" ? .green : .blue)
                    }
                    if let stage = presentation.ecosystemSupportStage {
                        statusPill(text: "ecosystem \(stage)", color: runtimeEcosystemStageColor(stage))
                    }
                    if presentation.notPromoted {
                        statusPill(text: "not promoted", color: .orange)
                    }
                    Spacer()
                }
            }
            if let summary = presentation.summary {
                Text(summary)
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let blockers = presentation.blockingReasonsLabel {
                Text("Blocked: \(blockers)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(.orange)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let source = presentation.sourceLabel {
                Text("Source: \(source)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let snapshot = presentation.officialSnapshotLabel {
                Text("Official snapshot: \(snapshot)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let drift = presentation.officialSnapshotDriftPolicy {
                Text("Drift policy: \(drift)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let evidence = support.ecosystem?.evidenceRequirements, !evidence.isEmpty {
                runtimeLensEvidenceRequirements(evidence, limit: 3)
            }
        }
        .accessibilityIdentifier("runtime-lens-support-overview")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    func runtimeEcosystemStageColor(_ stage: String) -> Color {
        runtimeLensColor(ClawJSRuntimeLensStatusTone.ecosystemStage(stage))
    }
}
