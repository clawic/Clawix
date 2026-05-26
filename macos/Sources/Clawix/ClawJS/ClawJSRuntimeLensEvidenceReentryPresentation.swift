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
        let exactCommand: String?
        let preflightCommand: String?
        let approvalScope: String?
        let evidenceSafetyPolicy: String?
        let safeDefault: String?
        let reentryCondition: String?
        let expectedEvidenceLabel: String?
        let expectedRedactedEvidenceLabel: String?
        let riskControlsLabel: String?
        let claimEffect: String?
        let claimBlockedUntil: String?
        let supportResolution: String?
        let productDecision: String?
        let userVisibleContract: String?
        let officialMethod: String?
        let officialTransportSurface: String?
        let officialTransportClassesLabel: String?
        let officialTransportSource: String?
        let productionTransportStatus: String?
        let productionTransportBlocker: String?
        let productionTransportCommandShape: String?
        let doNotRunWithoutApproval: Bool
        let expectedEvidenceCount: Int
        let expectedRedactedEvidenceCount: Int
        let riskControlCount: Int

        var accessibilityLabel: String {
            [
                requirementId,
                status,
                blockerClass.map { "blocker \($0)" },
                approvalRequired ? "approval required" : "approval not required",
                commandShape.map { "command \($0)" },
                exactCommand.map { "exact command \($0)" },
                preflightCommand.map { "preflight \($0)" },
                approvalScope.map { "approval scope \($0)" },
                evidenceSafetyPolicy.map { "evidence safety \($0)" },
                safeDefault.map { "safe default \($0)" },
                reentryCondition.map { "reentry condition \($0)" },
                expectedEvidenceLabel.map { "expected evidence \($0)" },
                expectedRedactedEvidenceLabel.map { "expected redacted evidence \($0)" },
                riskControlsLabel.map { "risk controls \($0)" },
                claimEffect.map { "claim effect \($0)" },
                claimBlockedUntil.map { "claim blocked until \($0)" },
                supportResolution.map { "support resolution \($0)" },
                productDecision.map { "product decision \($0)" },
                userVisibleContract.map { "user visible contract \($0)" },
                officialMethod.map { "official method \($0)" },
                officialTransportSurface.map { "official transport \($0)" },
                officialTransportClassesLabel.map { "official transport classes \($0)" },
                officialTransportSource.map { "official transport source \($0)" },
                productionTransportStatus.map { "production transport \($0)" },
                productionTransportBlocker.map { "production blocker \($0)" },
                productionTransportCommandShape.map { "production command \($0)" },
                doNotRunWithoutApproval ? "do not run without approval" : nil,
                "expected evidence count \(expectedEvidenceCount)",
                "expected redacted evidence count \(expectedRedactedEvidenceCount)",
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
        let highlightedPackets = Array(
            (Array(packets.prefix(3)) + packets.filter {
                $0.transportPolicyId != nil
                    || $0.officialTransportSurface != nil
                    || $0.productionTransportBlocker != nil
            })
            .uniquedBy { $0.id }
        )
        let rows = highlightedPackets.map {
            Row(
                requirementId: $0.requirementId ?? $0.id,
                status: $0.status ?? "unknown",
                blockerClass: $0.blockerClass,
                approvalRequired: $0.approvalRequired == true,
                commandShape: $0.commandShape,
                exactCommand: $0.exactCommand,
                preflightCommand: $0.preflightCommand,
                approvalScope: $0.approvalScope,
                evidenceSafetyPolicy: $0.evidenceSafetyPolicy,
                safeDefault: $0.safeDefault,
                reentryCondition: $0.reentryCondition,
                expectedEvidenceLabel: listLabel($0.expectedEvidence, limit: 3),
                expectedRedactedEvidenceLabel: listLabel($0.expectedRedactedEvidence, limit: 4),
                riskControlsLabel: listLabel($0.riskControls, limit: 3),
                claimEffect: $0.claimEffect,
                claimBlockedUntil: $0.claimBlockedUntil,
                supportResolution: $0.supportResolution,
                productDecision: $0.productDecision,
                userVisibleContract: $0.userVisibleContract,
                officialMethod: $0.officialMethod,
                officialTransportSurface: $0.officialTransportSurface,
                officialTransportClassesLabel: listLabel($0.officialTransportClasses, limit: 3),
                officialTransportSource: $0.officialTransportSource,
                productionTransportStatus: $0.productionTransportStatus,
                productionTransportBlocker: $0.productionTransportBlocker,
                productionTransportCommandShape: $0.productionTransportCommandShape,
                doNotRunWithoutApproval: $0.doNotRunWithoutApproval == true,
                expectedEvidenceCount: $0.expectedEvidence?.count ?? 0,
                expectedRedactedEvidenceCount: $0.expectedRedactedEvidence?.count ?? 0,
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

private extension Sequence {
    func uniquedBy<ID: Hashable>(_ id: (Element) -> ID) -> [Element] {
        var seen = Set<ID>()
        return filter { seen.insert(id($0)).inserted }
    }
}
