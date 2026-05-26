import SwiftUI

extension ClawJSRuntimeLensSection {
    func runtimeLensSupportAudit(_ audit: ClawJSRuntimeLensSnapshot.SupportAudit) -> some View {
        let presentation = ClawJSRuntimeLensSupportAuditPresentation.make(audit: audit)

        return VStack(alignment: .leading, spacing: 6) {
            row(label: "Closure") {
                HStack(spacing: 8) {
                    statusPill(
                        text: presentation.closureState,
                        color: presentation.supportComplete ? .green : .orange
                    )
                    if presentation.allDomainsAccountedFor {
                        statusPill(text: "all domains", color: .blue)
                    } else {
                        statusPill(text: "coverage gap", color: .orange)
                    }
                    statusPill(
                        text: "evidence \(presentation.evidenceRequirementCount)",
                        color: presentation.evidenceRequirementCount == 0 ? .green : .orange
                    )
                    Spacer()
                }
            }
            HStack(spacing: 8) {
                if presentation.directBlockerCount > 0 {
                    statusPill(text: "direct \(presentation.directBlockerCount)", color: .red)
                }
                if presentation.externalPendingCount > 0 {
                    statusPill(text: "external \(presentation.externalPendingCount)", color: .orange)
                }
                if presentation.productBlockedRequirementCount > 0 {
                    statusPill(text: "product \(presentation.productBlockedRequirementCount)", color: .orange)
                }
                if let stage = presentation.supportStage {
                    statusPill(text: stage, color: runtimeEcosystemStageColor(stage))
                }
                Spacer()
            }
            if let blockerClasses = presentation.blockerClassLabel {
                Text("Blocker classes: \(blockerClasses)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let directDomains = presentation.directBlockerDomainsLabel {
                Text("Direct blockers: \(directDomains)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(.orange)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let externalDomains = presentation.externalPendingDomainsLabel {
                Text("External evidence: \(externalDomains)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(.orange)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let blockedWriteBackDomains = presentation.blockedWriteBackDomainsLabel {
                Text("Blocked write-back: \(blockedWriteBackDomains)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(.orange)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let ecosystemExternalDomains = presentation.ecosystemExternalPendingDomainsLabel {
                Text("Ecosystem external: \(ecosystemExternalDomains)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let gate = presentation.promotionGate {
                Text(gate)
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.78))
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            if let provenance = presentation.provenanceLabel {
                Text("Audit source: \(provenance)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let syncSummary = audit.syncPolicySummary {
                runtimeLensSyncPolicySummary(syncSummary)
            }
            if let projectionSummary = audit.projectionSummary {
                runtimeLensProjectionSummary(projectionSummary)
            }
            if let readinessSummary = audit.evidenceReadinessSummary {
                runtimeLensEvidenceReadinessSummary(readinessSummary)
            }
        }
        .accessibilityIdentifier("runtime-lens-support-audit")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    func runtimeLensProjectionSummary(
        _ summary: ClawJSRuntimeLensSnapshot.SupportAudit.ProjectionSummary
    ) -> some View {
        let presentation = ClawJSRuntimeLensSupportSummaryPresentation.make(projection: summary)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                statusPill(
                    text: "read projected \(presentation.projectedDomainCount)",
                    color: presentation.projectedDomainCount > 0 ? .blue : .orange
                )
                if presentation.unsupportedDomainCount > 0 {
                    statusPill(text: "unsupported \(presentation.unsupportedDomainCount)", color: .orange)
                }
                if presentation.productBlockedButProjectedDomainCount > 0 {
                    statusPill(text: "blocked+read \(presentation.productBlockedButProjectedDomainCount)", color: .orange)
                }
                Spacer()
            }
            if let readStatusLabel = presentation.readStatusLabel {
                Text(readStatusLabel)
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let implementedFacets = presentation.implementedFacetLabel {
                Text("Implemented: \(implementedFacets)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let blockingFacets = presentation.blockingFacetLabel {
                Text("Blocked: \(blockingFacets)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(.orange)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .accessibilityIdentifier("runtime-lens-projection-summary")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    func runtimeLensSyncPolicySummary(
        _ summary: ClawJSRuntimeLensSnapshot.SupportAudit.SyncPolicySummary
    ) -> some View {
        let presentation = ClawJSRuntimeLensSupportSummaryPresentation.make(sync: summary)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                statusPill(text: "sync domains \(presentation.domainCount)", color: .blue)
                if presentation.readOnlyDomainCount > 0 {
                    statusPill(text: "read-only \(presentation.readOnlyDomainCount)", color: .blue)
                }
                if presentation.localOverlayDomainCount > 0 {
                    statusPill(text: "local overlay \(presentation.localOverlayDomainCount)", color: .orange)
                }
                if presentation.writeBackAllowedDomainCount > 0 {
                    statusPill(text: "write-back \(presentation.writeBackAllowedDomainCount)", color: .orange)
                }
                Spacer()
            }
            if let mode = presentation.defaultSyncMode {
                Text(mode)
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.78))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let blocked = presentation.blockedWriteBackLabel {
                Text("Blocked write-back: \(blocked)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(.orange)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let canonicalAuthority = presentation.canonicalAuthorityLabel {
                Text("Canonical authority: \(canonicalAuthority)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let writeBackPolicy = presentation.writeBackPolicyLabel {
                Text("Write-back policy: \(writeBackPolicy)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let persistence = presentation.persistenceLabel {
                Text("Persistence: \(persistence)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let relation = presentation.relationLabel {
                Text("Relation: \(relation)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let lossPolicy = presentation.lossPolicyLabel {
                Text("Loss policy: \(lossPolicy)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let freshness = presentation.freshnessLabel {
                Text("Freshness: \(freshness)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let safeDefault = presentation.safeDefault {
                Text(safeDefault)
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .accessibilityIdentifier("runtime-lens-sync-policy-summary")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    func runtimeLensEvidenceReadinessSummary(
        _ summary: ClawJSRuntimeLensSnapshot.SupportAudit.EvidenceReadinessSummary
    ) -> some View {
        let presentation = ClawJSRuntimeLensSupportSummaryPresentation.make(evidenceReadiness: summary)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                statusPill(
                    text: "requirements \(presentation.totalRequirementCount)",
                    color: presentation.totalRequirementCount == 0 ? .green : .orange
                )
                if presentation.approvalRequiredCount > 0 {
                    statusPill(text: "approval \(presentation.approvalRequiredCount)", color: .orange)
                }
                if presentation.upstreamContractBlockedCount > 0 {
                    statusPill(text: "upstream \(presentation.upstreamContractBlockedCount)", color: .orange)
                }
                if presentation.approvalGateBlockedCount > 0 {
                    statusPill(text: "approval gate \(presentation.approvalGateBlockedCount)", color: .orange)
                }
                if presentation.unresolvedNativeRequirementCount > 0 {
                    statusPill(text: "unresolved \(presentation.unresolvedNativeRequirementCount)", color: .red)
                }
                Spacer()
            }
            if let actions = presentation.nextRequiredActionsLabel {
                Text("Next: \(actions)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.78))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let blockerClasses = presentation.blockerClassLabel {
                Text("Blockers: \(blockerClasses)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let safeDefaults = presentation.safeDefaultLabel {
                Text("Safe defaults: \(safeDefaults)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let approvalIds = presentation.approvalRequiredIdsLabel {
                Text("Approval ids: \(approvalIds)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let externalIds = presentation.externalPendingIdsLabel {
                Text("External ids: \(externalIds)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let upstreamIds = presentation.upstreamContractIdsLabel {
                Text("Upstream ids: \(upstreamIds)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let approvalGateIds = presentation.approvalGateIdsLabel {
                Text("Approval gate ids: \(approvalGateIds)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let productIds = presentation.productBlockedIdsLabel {
                Text("Product ids: \(productIds)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let unresolvedIds = presentation.unresolvedNativeIdsLabel {
                Text("Unresolved ids: \(unresolvedIds)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let safeDefault = presentation.safeDefault {
                Text(safeDefault)
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .accessibilityIdentifier("runtime-lens-evidence-readiness-summary")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }
}
