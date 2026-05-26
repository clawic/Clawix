import Foundation

struct ClawJSRuntimeLensValidationSummary: Equatable {
    let runtimeId: String
    let runtimeName: String
    let coverageStatus: String
    let missingDomains: [String]
    let closureState: String
    let finalDecision: String
    let finalDecisionId: String?
    let effectiveSupportStage: String
    let recommended: Bool
    let production: Bool
    let uiParityClaim: String?
    let uiParityDisposition: String?
    let blockedPromotionClaims: [String]
    let finalDecisionBlockerClassesLabel: String?
    let finalDecisionProductBlockedIdsLabel: String?
    let finalDecisionExternalPendingIdsLabel: String?
    let finalDecisionUnresolvedNativeIdsLabel: String?
    let finalDecisionPromotionEvidenceLabel: String?
    let externalPendingRequirementCount: Int
    let productBlockedRequirementCount: Int
    let projectedDomainCount: Int
    let unsupportedDomainCount: Int
    let productBlockedButProjectedDomainCount: Int
    let syncReadOnlyDomainCount: Int
    let syncLocalOverlayDomainCount: Int
    let syncWriteBackAllowedDomainCount: Int
    let syncFreshnessLabel: String?
    let evidenceApprovalRequiredCount: Int
    let evidenceUpstreamContractBlockedCount: Int
    let evidenceApprovalGateBlockedCount: Int
    let evidenceTuiGatewayBlockedCount: Int
    let evidenceTuiGatewayWrapperBlockedCount: Int
    let evidenceTuiGatewayFixtureBackedCount: Int
    let evidenceProductionTransportBlockedCount: Int
    let evidenceWriteBackContractBlockedCount: Int
    let evidenceUnresolvedNativeRequirementCount: Int
    let checklistTotal: Int
    let evidenceReentryPacketCount: Int

    var isSemanticallyCovered: Bool {
        coverageStatus == "semantic_lens_covered"
    }

    var accessibilityLabel: String {
        [
            "Runtime lens validation",
            runtimeName,
            coverageStatus,
            "closure \(closureState)",
            "decision \(finalDecision)",
            finalDecisionId.map { "decision id \($0)" },
            "stage \(effectiveSupportStage)",
            "recommended \(recommended)",
            "production \(production)",
            uiParityClaim.map { "ui parity claim \($0)" },
            uiParityDisposition.map { "ui parity \($0)" },
            "checklist \(checklistTotal)",
            "reentry \(evidenceReentryPacketCount)",
            "projected domains \(projectedDomainCount)",
            "unsupported domains \(unsupportedDomainCount)",
            "product blocked but projected \(productBlockedButProjectedDomainCount)",
            "read only sync domains \(syncReadOnlyDomainCount)",
            "local overlay domains \(syncLocalOverlayDomainCount)",
            "write back allowed domains \(syncWriteBackAllowedDomainCount)",
            syncFreshnessLabel.map { "freshness \($0)" },
            "approval required \(evidenceApprovalRequiredCount)",
            "upstream contract blocked \(evidenceUpstreamContractBlockedCount)",
            "approval gate blocked \(evidenceApprovalGateBlockedCount)",
            "tui gateway blocked \(evidenceTuiGatewayBlockedCount)",
            "tui gateway wrapper blocked \(evidenceTuiGatewayWrapperBlockedCount)",
            "tui gateway fixture backed \(evidenceTuiGatewayFixtureBackedCount)",
            "production transport blocked \(evidenceProductionTransportBlockedCount)",
            "write back contract blocked \(evidenceWriteBackContractBlockedCount)",
            "unresolved native \(evidenceUnresolvedNativeRequirementCount)",
            "external \(externalPendingRequirementCount)",
            "product blocked \(productBlockedRequirementCount)",
            blockedPromotionClaims.isEmpty ? nil : "blocked claims \(blockedPromotionClaims.joined(separator: ", "))",
            finalDecisionBlockerClassesLabel.map { "final blocker classes \($0)" },
            finalDecisionProductBlockedIdsLabel.map { "final product blocked ids \($0)" },
            finalDecisionExternalPendingIdsLabel.map { "final external pending ids \($0)" },
            finalDecisionUnresolvedNativeIdsLabel.map { "final unresolved native ids \($0)" },
            finalDecisionPromotionEvidenceLabel.map { "final promotion evidence \($0)" },
            missingDomains.isEmpty ? "all domains accounted" : "missing domains \(missingDomains.joined(separator: ", "))"
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    static func make(snapshot: ClawJSRuntimeLensSnapshot) -> ClawJSRuntimeLensValidationSummary {
        let audit = snapshot.supportAudit
        let finalDecision = audit?.finalSupportClaimDecision
        let productBlockedCount = audit?.blockerSummary?.productBlockedRequirementCount ?? 0
        let externalPendingCount = finalDecision?.externalPendingRequirementIds?.count
            ?? audit?.finalPromotionReview?.externalPendingRequirementIds?.count
            ?? audit?.blockerSummary?.byBlockerClass?["external_pending"]
            ?? 0
        let checklist = audit?.closureChecklist ?? []
        let projectionSummary = audit?.projectionSummary
        let syncPolicySummary = audit?.syncPolicySummary
        let evidenceReadinessSummary = audit?.evidenceReadinessSummary
        let hasSemanticAudit = audit != nil
            && audit?.finalPromotionReview != nil
            && finalDecision != nil
            && syncPolicySummary != nil
            && projectionSummary != nil
            && evidenceReadinessSummary != nil
            && !checklist.isEmpty
            && audit?.evidenceReentryPackets?.isEmpty == false
        let hasRuntimeControls = snapshot.commands?.resourceDomains == ClawJSRuntimeLensSnapshot.canonicalDomains
            && !(snapshot.commands?.executableByClawCli ?? []).isEmpty
        let allDomainsAccounted = audit?.allDomainsAccountedFor == true
            && snapshot.missingCanonicalDomains.isEmpty
        let coverageStatus = hasSemanticAudit && hasRuntimeControls && allDomainsAccounted
            ? "semantic_lens_covered"
            : "semantic_lens_incomplete"

        return ClawJSRuntimeLensValidationSummary(
            runtimeId: snapshot.runtimeId,
            runtimeName: snapshot.runtimeName,
            coverageStatus: coverageStatus,
            missingDomains: snapshot.missingCanonicalDomains,
            closureState: audit?.closureState ?? "unknown",
            finalDecision: finalDecision?.status ?? "unknown",
            finalDecisionId: finalDecision?.decision,
            effectiveSupportStage: finalDecision?.effectiveSupportStage ?? audit?.supportStage ?? "unknown",
            recommended: finalDecision?.recommended == true,
            production: finalDecision?.production == true,
            uiParityClaim: finalDecision?.uiParityClaim,
            uiParityDisposition: finalDecision?.uiParityDisposition,
            blockedPromotionClaims: finalDecision?.blockedPromotionClaims ?? [],
            finalDecisionBlockerClassesLabel: listLabel(finalDecision?.blockerClasses, limit: 4),
            finalDecisionProductBlockedIdsLabel: listLabel(finalDecision?.productBlockedRequirementIds, limit: 4),
            finalDecisionExternalPendingIdsLabel: listLabel(finalDecision?.externalPendingRequirementIds, limit: 4),
            finalDecisionUnresolvedNativeIdsLabel: listLabel(finalDecision?.unresolvedNativeRequirementIds, limit: 4),
            finalDecisionPromotionEvidenceLabel: listLabel(finalDecision?.promotionEvidenceRequired, limit: 5),
            externalPendingRequirementCount: externalPendingCount,
            productBlockedRequirementCount: productBlockedCount,
            projectedDomainCount: projectionSummary?.projectedDomainCount ?? 0,
            unsupportedDomainCount: projectionSummary?.unsupportedDomainCount ?? 0,
            productBlockedButProjectedDomainCount: projectionSummary?.productBlockedButProjectedDomainCount ?? 0,
            syncReadOnlyDomainCount: syncPolicySummary?.readOnlyProjectionDomains?.count ?? 0,
            syncLocalOverlayDomainCount: syncPolicySummary?.localOverlayDomains?.count ?? 0,
            syncWriteBackAllowedDomainCount: syncPolicySummary?.writeBackAllowedDomains?.count ?? 0,
            syncFreshnessLabel: Self.countLabel(syncPolicySummary?.freshnessCounts),
            evidenceApprovalRequiredCount: evidenceReadinessSummary?.approvalRequiredCount ?? 0,
            evidenceUpstreamContractBlockedCount: evidenceReadinessSummary?.upstreamContractBlockedCount ?? 0,
            evidenceApprovalGateBlockedCount: evidenceReadinessSummary?.approvalGateBlockedCount ?? 0,
            evidenceTuiGatewayBlockedCount: evidenceReadinessSummary?.tuiGatewayBlockedCount ?? 0,
            evidenceTuiGatewayWrapperBlockedCount: evidenceReadinessSummary?.tuiGatewayWrapperBlockedCount ?? 0,
            evidenceTuiGatewayFixtureBackedCount: evidenceReadinessSummary?.tuiGatewayFixtureBackedCount ?? 0,
            evidenceProductionTransportBlockedCount: evidenceReadinessSummary?.productionTransportBlockedCount ?? 0,
            evidenceWriteBackContractBlockedCount: evidenceReadinessSummary?.writeBackContractBlockedCount ?? 0,
            evidenceUnresolvedNativeRequirementCount: evidenceReadinessSummary?.unresolvedNativeRequirementCount ?? 0,
            checklistTotal: checklist.count,
            evidenceReentryPacketCount: audit?.evidenceReentryPackets?.count ?? 0
        )
    }

    private static func countLabel(_ counts: [String: Int]?) -> String? {
        let pairs = counts?.sorted { $0.key < $1.key } ?? []
        guard !pairs.isEmpty else { return nil }
        return pairs.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
    }

    private static func listLabel(_ values: [String]?, limit: Int) -> String? {
        guard let values, !values.isEmpty else { return nil }
        return values.prefix(limit).joined(separator: ", ")
    }
}
