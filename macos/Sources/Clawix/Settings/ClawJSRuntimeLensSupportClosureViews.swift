import SwiftUI

extension ClawJSRuntimeLensSection {
    func runtimeLensClosureChecklist(
        _ checklist: [ClawJSRuntimeLensSnapshot.SupportAudit.ClosureChecklistItem],
        summary: [String: Int]?
    ) -> some View {
        let presentation = ClawJSRuntimeLensClosureChecklistPresentation.make(
            checklist: checklist,
            summary: summary
        )
        let pageKey = ClawJSRuntimeLensPageKey("closure-checklist")
        let slice = page(presentation.rows, key: pageKey)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                statusPill(text: presentation.totalLabel, color: .blue)
                ForEach(presentation.statusPills) { pill in
                    statusPill(text: pill.label, color: runtimeLensClosureStatusColor(pill.status))
                }
                Spacer()
            }
            ForEach(slice.rows) { item in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.domain)
                            .font(BodyFont.system(size: 10.5, weight: .medium))
                            .foregroundColor(Palette.textPrimary)
                        statusPill(text: item.closureStatus, color: runtimeLensClosureStatusColor(item.closureStatus))
                        if let readProjectionStatus = item.readProjectionStatus {
                            statusPill(text: "read \(readProjectionStatus)", color: .blue)
                        }
                        if item.evidenceCount > 0 {
                            statusPill(text: "evidence \(item.evidenceCount)", color: .orange)
                        }
                        if item.blockingFacetCount > 0 {
                            statusPill(text: "blocked \(item.blockingFacetCount)", color: .red)
                        }
                        Spacer()
                    }
                    if let projectionDisposition = item.projectionDisposition {
                        Text(projectionDisposition)
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let claim = item.claim {
                        Text("Claim: \(claim)")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let runtimeStatus = item.runtimeStatus {
                        Text("Runtime status: \(runtimeStatus)")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let writeBackPolicy = item.writeBackPolicy {
                        Text("Write-back: \(writeBackPolicy)")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let validation = item.validation {
                        Text("Validation: \(validation)")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let blockerClasses = item.blockerClassesLabel {
                        Text("Blockers: \(blockerClasses)")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let evidenceIds = item.evidenceRequirementIdsLabel {
                        Text("Evidence ids: \(evidenceIds)")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let supportResolutions = item.supportResolutionsLabel {
                        Text("Resolution: \(supportResolutions)")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let safeDefault = item.safeDefault {
                        Text(safeDefault)
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let next = item.nextAction {
                        Text(next)
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .accessibilityIdentifier("runtime-lens-closure-checklist-row-\(item.domain)")
                .accessibilityLabel(Text(item.accessibilityLabel))
            }
            pager(slice, key: pageKey)
        }
        .accessibilityIdentifier("runtime-lens-closure-checklist")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    func runtimeLensClosureStatusColor(_ status: String) -> Color {
        runtimeLensColor(ClawJSRuntimeLensStatusTone.closureStatus(status))
    }

    func runtimeLensFinalPromotionReview(
        _ review: ClawJSRuntimeLensSnapshot.SupportAudit.FinalPromotionReview
    ) -> some View {
        let presentation = ClawJSRuntimeLensSupportDecisionPresentation.make(review: review)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                statusPill(text: presentation.status, color: presentation.finalPromotionAllowed ? .green : .orange)
                statusPill(
                    text: presentation.claimDisposition,
                    color: presentation.claimDisposition == "all_claims_supported_by_current_evidence" ? .green : .orange
                )
                Spacer()
            }
            HStack(spacing: 8) {
                if presentation.productBlockedCount > 0 {
                    statusPill(text: "product-blocked \(presentation.productBlockedCount)", color: .orange)
                }
                if presentation.externalPendingCount > 0 {
                    statusPill(text: "external \(presentation.externalPendingCount)", color: .orange)
                }
                if presentation.unresolvedNativeRequirementCount > 0 {
                    statusPill(text: "unresolved \(presentation.unresolvedNativeRequirementCount)", color: .red)
                }
                Spacer()
            }
            if let required = presentation.requiredForPromotionLabel, !required.isEmpty {
                Text("Promotion needs: \(required)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.78))
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            if let productIds = presentation.productBlockedIdsLabel {
                Text("Product ids: \(productIds)")
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
            if let unresolvedIds = presentation.unresolvedNativeIdsLabel {
                Text("Unresolved ids: \(unresolvedIds)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let status = presentation.userVisibleStatus {
                Text(status)
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .accessibilityIdentifier("runtime-lens-final-promotion-review")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    func runtimeLensFinalSupportClaimDecision(
        _ decision: ClawJSRuntimeLensSnapshot.SupportAudit.FinalSupportClaimDecision
    ) -> some View {
        let presentation = ClawJSRuntimeLensSupportDecisionPresentation.make(decision: decision)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                statusPill(text: presentation.status, color: presentation.status == "promoted" ? .green : .orange)
                statusPill(text: "claim \(presentation.effectiveSupportStage)", color: claimColor(presentation.effectiveSupportStage))
                if let parity = presentation.uiParityDisposition {
                    statusPill(text: parity, color: parity == "ui_parity_promoted" ? .green : .orange)
                }
                Spacer()
            }
            if let decision = presentation.decision {
                Text("Decision: \(decision)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.78))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let claim = presentation.uiParityClaim {
                Text("UI parity claim: \(claim)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text("Recommended: \(presentation.recommended ? "yes" : "no") · Production: \(presentation.production ? "yes" : "no")")
                .font(BodyFont.system(size: 10.5))
                .foregroundColor(Palette.textSecondary.opacity(0.72))
                .lineLimit(1)
                .truncationMode(.middle)
            if let blocked = presentation.blockedPromotionClaimsLabel {
                Text("Blocked claims: \(blocked)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(.orange)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let classes = presentation.blockerClassesLabel {
                Text("Blocker classes: \(classes)")
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
            if let externalIds = presentation.externalPendingIdsLabel {
                Text("External ids: \(externalIds)")
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
            if let evidence = presentation.promotionEvidenceRequiredLabel {
                Text("Evidence: \(evidence)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            if let policy = presentation.reentryPolicy {
                Text(policy)
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.78))
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
        .accessibilityIdentifier("runtime-lens-final-support-claim-decision")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    func runtimeLensEvidenceReentryPackets(
        _ packets: [ClawJSRuntimeLensSnapshot.SupportAudit.EvidenceReentryPacket]
    ) -> some View {
        let presentation = ClawJSRuntimeLensEvidenceReentryPresentation.make(packets: packets)
        let pageKey = ClawJSRuntimeLensPageKey("evidence-reentry-packets")
        let slice = page(presentation.rows, key: pageKey)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                statusPill(text: presentation.totalLabel, color: .orange)
                ForEach(presentation.statusPills) { pill in
                    statusPill(text: pill.label, color: runtimeLensEvidenceReentryStatusColor(pill.status))
                }
                Spacer()
            }
            ForEach(slice.rows) { row in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(row.requirementId)
                            .font(BodyFont.system(size: 10.5, weight: .medium))
                            .foregroundColor(Palette.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if row.approvalRequired {
                            statusPill(text: "approval", color: .orange)
                        }
                        Spacer()
                    }
                    if let command = row.commandShape {
                        Text(command)
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.78))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let safeDefault = row.safeDefault {
                        Text(safeDefault)
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let condition = row.reentryCondition {
                        Text(condition)
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let evidence = row.expectedEvidenceLabel {
                        Text("Evidence: \(evidence)")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let controls = row.riskControlsLabel {
                        Text("Risk controls: \(controls)")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let effect = row.claimEffect {
                        Text("Claim: \(effect)")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let resolution = row.supportResolution {
                        Text("Resolution: \(resolution)")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let decision = row.productDecision {
                        Text("Product: \(decision)")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let contract = row.userVisibleContract {
                        Text("Contract: \(contract)")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .accessibilityIdentifier("runtime-lens-evidence-reentry-row-\(row.requirementId)")
                .accessibilityLabel(Text(row.accessibilityLabel))
            }
            pager(slice, key: pageKey)
        }
        .accessibilityIdentifier("runtime-lens-evidence-reentry-packets")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    func runtimeLensEvidenceReentryStatusColor(_ status: String) -> Color {
        runtimeLensColor(ClawJSRuntimeLensStatusTone.evidenceReentryStatus(status))
    }
}
