import Foundation

struct ClawJSRuntimeLensEvidenceRequirementPresentation: Equatable {
    struct Row: Equatable, Identifiable {
        let id: String
        let blockerClass: String?
        let approvalRequired: Bool
        let commandShape: String?
        let evidenceDisposition: String?
        let currentBehavior: String?
        let supportResolution: String?
        let productDecision: String?
        let promotionGate: String?
        let expectedEvidenceCount: Int
        let riskControlCount: Int

        var detailLabel: String? {
            let values = [commandShape, evidenceDisposition, currentBehavior].compactMap { $0 }
            guard !values.isEmpty else { return nil }
            return values.joined(separator: ", ")
        }

        var resolutionLabel: String? {
            let values = [supportResolution, productDecision].compactMap { $0 }
            guard !values.isEmpty else { return nil }
            return values.joined(separator: ", ")
        }

        var accessibilityLabel: String {
            [
                "evidence requirement \(id)",
                blockerClass.map { "blocker \($0)" },
                "approval required \(approvalRequired)",
                commandShape.map { "command \($0)" },
                evidenceDisposition.map { "disposition \($0)" },
                currentBehavior.map { "current behavior \($0)" },
                supportResolution.map { "support resolution \($0)" },
                productDecision.map { "product decision \($0)" },
                promotionGate.map { "promotion gate \($0)" },
                "expected evidence \(expectedEvidenceCount)",
                "risk controls \(riskControlCount)"
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
                evidenceDisposition: requirement.evidenceDisposition,
                currentBehavior: requirement.currentBehavior,
                supportResolution: requirement.supportResolution,
                productDecision: requirement.productDecision,
                promotionGate: requirement.promotionGate,
                expectedEvidenceCount: requirement.expectedEvidence?.count ?? 0,
                riskControlCount: requirement.riskControls?.count ?? 0
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
}
