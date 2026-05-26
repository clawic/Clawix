import Foundation

enum ClawJSRuntimeLensSupportDecisionPresentation {
    struct PromotionReview: Equatable {
        let status: String
        let claimDisposition: String
        let finalPromotionAllowed: Bool
        let supportCompletionMode: String?
        let productBlockedCount: Int
        let externalPendingCount: Int
        let unresolvedNativeRequirementCount: Int
        let commandCoverageLabel: String?
        let commandCoveragePromotionSignal: Bool?
        let commandCoverageSafeDefault: String?
        let productBlockedIdsLabel: String?
        let externalPendingIdsLabel: String?
        let unresolvedNativeIdsLabel: String?
        let requiredForPromotionLabel: String?
        let userVisibleStatus: String?

        var accessibilityLabel: String {
            [
                "Runtime final promotion review",
                "status \(status)",
                "disposition \(claimDisposition)",
                "allowed \(finalPromotionAllowed)",
                supportCompletionMode.map { "completion mode \($0)" },
                "product blocked \(productBlockedCount)",
                "external pending \(externalPendingCount)",
                "unresolved native \(unresolvedNativeRequirementCount)",
                commandCoverageLabel.map { "command coverage \($0)" },
                commandCoveragePromotionSignal.map { "command coverage promotion \($0)" },
                commandCoverageSafeDefault.map { "command coverage safe default \($0)" },
                productBlockedIdsLabel.map { "product blocked ids \($0)" },
                externalPendingIdsLabel.map { "external pending ids \($0)" },
                unresolvedNativeIdsLabel.map { "unresolved native ids \($0)" },
                requiredForPromotionLabel.map { "promotion needs \($0)" },
                userVisibleStatus.map { "user visible status \($0)" }
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        }
    }

    struct FinalDecision: Equatable {
        let status: String
        let decision: String?
        let effectiveSupportStage: String
        let recommended: Bool
        let production: Bool
        let uiParityClaim: String?
        let uiParityDisposition: String?
        let claimDisposition: String
        let supportCompletionMode: String?
        let commandCoverageLabel: String?
        let commandCoveragePromotionSignal: Bool?
        let commandCoverageSafeDefault: String?
        let blockedPromotionClaims: [String]
        let blockerClassesLabel: String?
        let productBlockedIdsLabel: String?
        let externalPendingIdsLabel: String?
        let unresolvedNativeIdsLabel: String?
        let promotionEvidenceRequiredLabel: String?
        let reentryPolicy: String?
        let safeDefault: String?
        let userVisibleStatus: String?

        var blockedPromotionClaimsLabel: String? {
            guard !blockedPromotionClaims.isEmpty else { return nil }
            return blockedPromotionClaims.joined(separator: ", ")
        }

        var accessibilityLabel: String {
            [
                "Runtime final support claim decision",
                "status \(status)",
                decision.map { "decision \($0)" },
                "stage \(effectiveSupportStage)",
                "recommended \(recommended)",
                "production \(production)",
                uiParityClaim.map { "ui parity claim \($0)" },
                uiParityDisposition.map { "ui parity \($0)" },
                "disposition \(claimDisposition)",
                supportCompletionMode.map { "completion mode \($0)" },
                commandCoverageLabel.map { "command coverage \($0)" },
                commandCoveragePromotionSignal.map { "command coverage promotion \($0)" },
                commandCoverageSafeDefault.map { "command coverage safe default \($0)" },
                blockedPromotionClaimsLabel.map { "blocked claims \($0)" },
                blockerClassesLabel.map { "blocker classes \($0)" },
                productBlockedIdsLabel.map { "product blocked ids \($0)" },
                externalPendingIdsLabel.map { "external pending ids \($0)" },
                unresolvedNativeIdsLabel.map { "unresolved native ids \($0)" },
                promotionEvidenceRequiredLabel.map { "promotion evidence \($0)" },
                reentryPolicy.map { "reentry policy \($0)" },
                safeDefault.map { "safe default \($0)" },
                userVisibleStatus.map { "user visible status \($0)" }
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        }
    }

    static func make(
        review: ClawJSRuntimeLensSnapshot.SupportAudit.FinalPromotionReview
    ) -> PromotionReview {
        PromotionReview(
            status: review.status ?? "unknown",
            claimDisposition: review.claimDisposition ?? "unknown",
            finalPromotionAllowed: review.finalPromotionAllowed == true,
            supportCompletionMode: review.supportCompletionMode,
            productBlockedCount: review.productBlockedByDecisionCount ?? review.productBlockedRequirementIds?.count ?? 0,
            externalPendingCount: review.externalPendingCount ?? review.externalPendingRequirementIds?.count ?? 0,
            unresolvedNativeRequirementCount: review.unresolvedNativeRequirementCount ?? review.unresolvedNativeRequirementIds?.count ?? 0,
            commandCoverageLabel: commandCoverageLabel(review.commandCoverageSummary),
            commandCoveragePromotionSignal: review.commandCoverageSummary?.promotionSignal,
            commandCoverageSafeDefault: review.commandCoverageSummary?.safeDefault,
            productBlockedIdsLabel: listLabel(review.productBlockedRequirementIds, limit: 4),
            externalPendingIdsLabel: listLabel(review.externalPendingRequirementIds, limit: 4),
            unresolvedNativeIdsLabel: listLabel(review.unresolvedNativeRequirementIds, limit: 4),
            requiredForPromotionLabel: review.requiredForPromotion?.prefix(5).joined(separator: ", "),
            userVisibleStatus: review.userVisibleStatus
        )
    }

    static func make(
        decision: ClawJSRuntimeLensSnapshot.SupportAudit.FinalSupportClaimDecision
    ) -> FinalDecision {
        FinalDecision(
            status: decision.status ?? "unknown",
            decision: decision.decision,
            effectiveSupportStage: decision.effectiveSupportStage ?? "unknown",
            recommended: decision.recommended == true,
            production: decision.production == true,
            uiParityClaim: decision.uiParityClaim,
            uiParityDisposition: decision.uiParityDisposition,
            claimDisposition: decision.claimDisposition ?? "unknown",
            supportCompletionMode: decision.supportCompletionMode,
            commandCoverageLabel: commandCoverageLabel(decision.commandCoverageSummary),
            commandCoveragePromotionSignal: decision.commandCoverageSummary?.promotionSignal,
            commandCoverageSafeDefault: decision.commandCoverageSummary?.safeDefault,
            blockedPromotionClaims: decision.blockedPromotionClaims ?? [],
            blockerClassesLabel: listLabel(decision.blockerClasses, limit: 4),
            productBlockedIdsLabel: listLabel(decision.productBlockedRequirementIds, limit: 4),
            externalPendingIdsLabel: listLabel(decision.externalPendingRequirementIds, limit: 4),
            unresolvedNativeIdsLabel: listLabel(decision.unresolvedNativeRequirementIds, limit: 4),
            promotionEvidenceRequiredLabel: listLabel(decision.promotionEvidenceRequired, limit: 5),
            reentryPolicy: decision.reentryPolicy,
            safeDefault: decision.safeDefault,
            userVisibleStatus: decision.userVisibleStatus
        )
    }

    private static func listLabel(_ values: [String]?, limit: Int) -> String? {
        guard let values, !values.isEmpty else { return nil }
        return values.prefix(limit).joined(separator: ", ")
    }

    static func isPositiveDisposition(_ disposition: String) -> Bool {
        disposition == "all_claims_supported_by_current_evidence"
            || disposition == "operable_non_default_complete"
    }

    static func isPositiveStatus(_ status: String) -> Bool {
        status == "promoted" || status == "operable_non_default_complete"
    }

    private static func commandCoverageLabel(
        _ summary: ClawJSRuntimeLensSnapshot.SupportAudit.CommandCoverageSummary?
    ) -> String? {
        guard let summary, let count = summary.totalCommandCount else { return nil }
        let status = summary.status ?? "unknown"
        return "\(status) \(count)"
    }
}
