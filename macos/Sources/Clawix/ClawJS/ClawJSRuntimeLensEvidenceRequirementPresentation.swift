import Foundation

struct ClawJSRuntimeLensEvidenceRequirementPresentation: Equatable {
    struct Row: Equatable, Identifiable {
        let id: String
        let blockerClass: String?
        let approvalRequired: Bool
        let commandShape: String?
        let exactCommand: String?
        let preflightCommand: String?
        let approvalScope: String?
        let evidenceSafetyPolicy: String?
        let evidenceDisposition: String?
        let currentBehavior: String?
        let fallbackPolicy: String?
        let safeDefault: String?
        let claimEffect: String?
        let claimBlockedUntil: String?
        let reentryCondition: String?
        let supportResolution: String?
        let productDecision: String?
        let userVisibleContract: String?
        let promotionGate: String?
        let officialProtocol: String?
        let officialMethod: String?
        let officialContractSource: String?
        let expectedEvidenceCount: Int
        let expectedEvidenceLabel: String?
        let expectedRedactedEvidenceCount: Int
        let expectedRedactedEvidenceLabel: String?
        let riskControlCount: Int
        let riskControlsLabel: String?
        let doNotRunWithoutApproval: Bool?

        var detailLabel: String? {
            let values = [exactCommand ?? commandShape, evidenceDisposition, currentBehavior].compactMap { $0 }
            guard !values.isEmpty else { return nil }
            return values.joined(separator: ", ")
        }

        var resolutionLabel: String? {
            let values = [supportResolution, productDecision, claimEffect].compactMap { $0 }
            guard !values.isEmpty else { return nil }
            return values.joined(separator: ", ")
        }

        var detailLines: [String] {
            [
                commandShape.map { "command shape \($0)" },
                exactCommand.map { "exact command \($0)" },
                preflightCommand.map { "preflight \($0)" },
                approvalScope.map { "approval scope \($0)" },
                evidenceSafetyPolicy.map { "safety \($0)" },
                evidenceDisposition.map { "disposition \($0)" },
                currentBehavior.map { "current behavior \($0)" },
                fallbackPolicy.map { "fallback \($0)" },
                safeDefault.map { "safe default \($0)" },
                reentryCondition.map { "reentry \($0)" },
                expectedEvidenceLabel.map { "expected evidence \($0)" },
                expectedRedactedEvidenceLabel.map { "redacted evidence \($0)" },
                riskControlsLabel.map { "risk controls \($0)" },
                userVisibleContract.map { "user visible contract \($0)" },
                claimEffect.map { "claim effect \($0)" },
                claimBlockedUntil.map { "claim blocked until \($0)" },
                supportResolution.map { "support resolution \($0)" },
                productDecision.map { "product decision \($0)" },
                promotionGate.map { "promotion gate \($0)" },
                officialProtocol.map { "official protocol \($0)" },
                officialMethod.map { "official method \($0)" },
                officialContractSource.map { "official contract source \($0)" },
                doNotRunWithoutApproval.map { "do not run without approval \($0)" }
            ]
            .compactMap { $0 }
        }

        var accessibilityLabel: String {
            [
                "evidence requirement \(id)",
                blockerClass.map { "blocker \($0)" },
                "approval required \(approvalRequired)",
                commandShape.map { "command \($0)" },
                exactCommand.map { "exact command \($0)" },
                preflightCommand.map { "preflight \($0)" },
                approvalScope.map { "approval scope \($0)" },
                evidenceSafetyPolicy.map { "safety \($0)" },
                evidenceDisposition.map { "disposition \($0)" },
                currentBehavior.map { "current behavior \($0)" },
                fallbackPolicy.map { "fallback \($0)" },
                safeDefault.map { "safe default \($0)" },
                reentryCondition.map { "reentry \($0)" },
                supportResolution.map { "support resolution \($0)" },
                productDecision.map { "product decision \($0)" },
                userVisibleContract.map { "user visible contract \($0)" },
                claimEffect.map { "claim effect \($0)" },
                claimBlockedUntil.map { "claim blocked until \($0)" },
                promotionGate.map { "promotion gate \($0)" },
                officialProtocol.map { "official protocol \($0)" },
                officialMethod.map { "official method \($0)" },
                officialContractSource.map { "official contract source \($0)" },
                "expected evidence \(expectedEvidenceCount)",
                expectedEvidenceLabel.map { "expected evidence list \($0)" },
                "redacted evidence \(expectedRedactedEvidenceCount)",
                expectedRedactedEvidenceLabel.map { "redacted evidence list \($0)" },
                "risk controls \(riskControlCount)",
                riskControlsLabel.map { "risk controls list \($0)" },
                doNotRunWithoutApproval.map { "do not run without approval \($0)" }
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        }
    }

    let totalRequirementCount: Int
    let approvalRequiredCount: Int
    let directBlockerCount: Int
    let externalPendingCount: Int
    let productBlockedCount: Int
    let commandShapeCount: Int
    let blockerClassLabel: String?
    let rows: [Row]

    var accessibilityLabel: String {
        [
            "Runtime evidence requirements",
            "requirements \(totalRequirementCount)",
            "approval required \(approvalRequiredCount)",
            "direct blockers \(directBlockerCount)",
            "external pending \(externalPendingCount)",
            "product blocked \(productBlockedCount)",
            "command shapes \(commandShapeCount)",
            blockerClassLabel.map { "blockers \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    static func make(
        requirements: [ClawJSRuntimeLensSnapshot.EvidenceRequirement],
        limit: Int
    ) -> ClawJSRuntimeLensEvidenceRequirementPresentation {
        let rows = requirements.prefix(limit).map { requirement in
            Row(
                id: requirement.id,
                blockerClass: requirement.blockerClass,
                approvalRequired: requirement.approvalRequired == true,
                commandShape: requirement.commandShape,
                exactCommand: requirement.exactCommand,
                preflightCommand: requirement.preflightCommand,
                approvalScope: requirement.approvalScope,
                evidenceSafetyPolicy: requirement.evidenceSafetyPolicy,
                evidenceDisposition: requirement.evidenceDisposition,
                currentBehavior: requirement.currentBehavior,
                fallbackPolicy: requirement.fallbackPolicy,
                safeDefault: requirement.safeDefault,
                claimEffect: requirement.claimEffect,
                claimBlockedUntil: requirement.claimBlockedUntil,
                reentryCondition: requirement.reentryCondition,
                supportResolution: requirement.supportResolution,
                productDecision: requirement.productDecision,
                userVisibleContract: requirement.userVisibleContract,
                promotionGate: requirement.promotionGate,
                officialProtocol: requirement.officialProtocol,
                officialMethod: requirement.officialMethod,
                officialContractSource: requirement.officialContractSource,
                expectedEvidenceCount: requirement.expectedEvidence?.count ?? 0,
                expectedEvidenceLabel: listLabel(requirement.expectedEvidence, limit: 4),
                expectedRedactedEvidenceCount: requirement.expectedRedactedEvidence?.count ?? 0,
                expectedRedactedEvidenceLabel: listLabel(requirement.expectedRedactedEvidence, limit: 4),
                riskControlCount: requirement.riskControls?.count ?? 0,
                riskControlsLabel: listLabel(requirement.riskControls, limit: 4),
                doNotRunWithoutApproval: requirement.doNotRunWithoutApproval
            )
        }

        return ClawJSRuntimeLensEvidenceRequirementPresentation(
            totalRequirementCount: requirements.count,
            approvalRequiredCount: requirements.filter { $0.approvalRequired == true }.count,
            directBlockerCount: requirements.filter { $0.blockerClass == "direct_blocker" }.count,
            externalPendingCount: requirements.filter { $0.blockerClass == "external_pending" }.count,
            productBlockedCount: requirements.filter {
                $0.supportResolution == "explicitly_product_blocked_not_a_silent_gap"
                    || $0.productDecision != nil
            }.count,
            commandShapeCount: requirements.filter { $0.commandShape != nil }.count,
            blockerClassLabel: countLabel(requirements.compactMap(\.blockerClass)),
            rows: rows
        )
    }

    private static func countLabel(_ values: [String]) -> String? {
        let counts = values.reduce(into: [String: Int]()) { result, value in
            result[value, default: 0] += 1
        }
        let pairs = counts.sorted { $0.key < $1.key }
        guard !pairs.isEmpty else { return nil }
        return pairs.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
    }

    private static func listLabel(_ values: [String]?, limit: Int) -> String? {
        guard let values, !values.isEmpty else { return nil }
        let visible = values.prefix(limit).joined(separator: ", ")
        let remaining = values.count - min(values.count, limit)
        guard remaining > 0 else { return visible }
        return "\(visible), +\(remaining) more"
    }
}
