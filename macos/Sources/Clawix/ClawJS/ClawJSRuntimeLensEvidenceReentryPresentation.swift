import Foundation

struct ClawJSRuntimeLensEvidenceReentryPresentation: Equatable {
    struct StatusPill: Equatable, Identifiable {
        var id: String { status }
        let status: String
        let count: Int

        var label: String {
            "\(status) \(count)"
        }
    }

    struct Row: Equatable, Identifiable {
        var id: String { requirementId }
        let requirementId: String
        let status: String
        let blockerClass: String?
        let approvalRequired: Bool
        let commandShape: String?
        let safeDefault: String?
        let reentryCondition: String?
        let expectedEvidenceLabel: String?
        let riskControlsLabel: String?
        let claimEffect: String?
        let supportResolution: String?
        let productDecision: String?
        let userVisibleContract: String?
        let expectedEvidenceCount: Int
        let riskControlCount: Int

        var accessibilityLabel: String {
            [
                requirementId,
                status,
                blockerClass.map { "blocker \($0)" },
                approvalRequired ? "approval required" : "approval not required",
                commandShape.map { "command \($0)" },
                safeDefault.map { "safe default \($0)" },
                reentryCondition.map { "reentry condition \($0)" },
                expectedEvidenceLabel.map { "expected evidence \($0)" },
                riskControlsLabel.map { "risk controls \($0)" },
                claimEffect.map { "claim effect \($0)" },
                supportResolution.map { "support resolution \($0)" },
                productDecision.map { "product decision \($0)" },
                userVisibleContract.map { "user visible contract \($0)" },
                "expected evidence count \(expectedEvidenceCount)",
                "risk controls \(riskControlCount)"
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        }
    }

    let totalLabel: String
    let statusPills: [StatusPill]
    let rows: [Row]
    let approvalRequiredCount: Int

    var accessibilityLabel: String {
        let statuses = statusPills.map(\.label).joined(separator: ", ")
        let requirements = rows.map { "\($0.requirementId) \($0.status)" }.joined(separator: ", ")
        return [
            "Runtime evidence reentry packets",
            totalLabel,
            "approval required \(approvalRequiredCount)",
            statuses,
            requirements
        ]
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }

    static func make(
        packets: [ClawJSRuntimeLensSnapshot.SupportAudit.EvidenceReentryPacket]
    ) -> ClawJSRuntimeLensEvidenceReentryPresentation {
        let statusCounts = Dictionary(grouping: packets, by: { $0.status ?? "unknown" })
            .mapValues(\.count)
        let statusPills = statusCounts.keys.sorted().prefix(3).map {
            StatusPill(status: $0, count: statusCounts[$0] ?? 0)
        }
        let rows = packets.prefix(3).map {
            Row(
                requirementId: $0.requirementId ?? $0.id,
                status: $0.status ?? "unknown",
                blockerClass: $0.blockerClass,
                approvalRequired: $0.approvalRequired == true,
                commandShape: $0.commandShape,
                safeDefault: $0.safeDefault,
                reentryCondition: $0.reentryCondition,
                expectedEvidenceLabel: listLabel($0.expectedEvidence, limit: 3),
                riskControlsLabel: listLabel($0.riskControls, limit: 3),
                claimEffect: $0.claimEffect,
                supportResolution: $0.supportResolution,
                productDecision: $0.productDecision,
                userVisibleContract: $0.userVisibleContract,
                expectedEvidenceCount: $0.expectedEvidence?.count ?? 0,
                riskControlCount: $0.riskControls?.count ?? 0
            )
        }

        return ClawJSRuntimeLensEvidenceReentryPresentation(
            totalLabel: "reentry \(packets.count)",
            statusPills: Array(statusPills),
            rows: Array(rows),
            approvalRequiredCount: packets.filter { $0.approvalRequired == true }.count
        )
    }

    private static func listLabel(_ values: [String]?, limit: Int) -> String? {
        guard let values, !values.isEmpty else { return nil }
        return values.prefix(limit).joined(separator: ", ")
    }
}
