import Foundation

struct ClawJSRuntimeLensSessionActionPresentation: Equatable {
    struct Row: Equatable, Identifiable {
        let id: String
        let action: String
        let status: String?
        let authority: String?
        let persistence: String?
        let delegatesTo: String?
        let guardName: String?
        let officialProtocol: String?
        let officialMethod: String?
        let officialContractSource: String?
        let transportPolicyId: String?
        let productionTransportStatus: String?
        let lifecycleStatus: String?
        let requiredEvidenceCount: Int
        let requiredEvidenceLabel: String?
        let userVisibleContract: String?
        let claimEffect: String?
        let writeDisposition: String

        var detailLabel: String? {
            let transportValues = [
                transportPolicyId.map { "transport policy \($0)" },
                productionTransportStatus.map { "production transport \($0)" },
                lifecycleStatus.map { "lifecycle \($0)" }
            ].compactMap { $0 }
            let actionValues = [
                authority,
                persistence,
                delegatesTo,
                guardName,
                officialProtocol,
                officialMethod,
                officialContractSource,
                requiredEvidenceLabel,
                userVisibleContract.map { "user visible contract \($0)" },
                claimEffect.map { "claim effect \($0)" }
            ].compactMap { $0 }
            let values = transportValues + actionValues
            guard !values.isEmpty else { return nil }
            return values.joined(separator: ", ")
        }

        var accessibilityLabel: String {
            [
                "session action \(action)",
                status.map { "status \($0)" },
                "disposition \(writeDisposition)",
                authority.map { "authority \($0)" },
                persistence.map { "persistence \($0)" },
                delegatesTo.map { "delegates to \($0)" },
                guardName.map { "guard \($0)" },
                officialProtocol.map { "official protocol \($0)" },
                officialMethod.map { "official method \($0)" },
                officialContractSource.map { "official contract source \($0)" },
                transportPolicyId.map { "transport policy \($0)" },
                productionTransportStatus.map { "production transport \($0)" },
                lifecycleStatus.map { "lifecycle \($0)" },
                "required evidence count \(requiredEvidenceCount)",
                requiredEvidenceLabel.map { "required evidence \($0)" },
                userVisibleContract.map { "user visible contract \($0)" },
                claimEffect.map { "claim effect \($0)" }
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        }
    }

    let actionCount: Int
    let implementedCount: Int
    let blockedCount: Int
    let localOverlayCount: Int
    let noWriteCount: Int
    let wouldWriteRuntimeCount: Int
    let requiredEvidenceCount: Int
    let statusLabel: String?
    let localOverlayActionsLabel: String?
    let blockedActionsLabel: String?
    let rows: [Row]

    var accessibilityLabel: String {
        [
            "Runtime session actions",
            "actions \(actionCount)",
            "implemented \(implementedCount)",
            "blocked \(blockedCount)",
            "local overlay \(localOverlayCount)",
            "no write \(noWriteCount)",
            "would write runtime \(wouldWriteRuntimeCount)",
            "required evidence \(requiredEvidenceCount)",
            statusLabel.map { "statuses \($0)" },
            localOverlayActionsLabel.map { "local overlay actions \($0)" },
            blockedActionsLabel.map { "blocked actions \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    static func make(
        actions: [ClawJSRuntimeLensSnapshot.SessionActionPolicy]
    ) -> ClawJSRuntimeLensSessionActionPresentation {
        let rows = actions.map { action in
            Row(
                id: action.action,
                action: action.action,
                status: action.status,
                authority: action.authority,
                persistence: action.persistence,
                delegatesTo: action.delegatesTo,
                guardName: action.guardName,
                officialProtocol: action.officialProtocol,
                officialMethod: action.officialMethod,
                officialContractSource: action.officialContractSource,
                transportPolicyId: action.transportPolicy?.id,
                productionTransportStatus: action.productionTransportStatus ?? action.transportPolicy?.productionTransportStatus,
                lifecycleStatus: action.lifecycleStatus ?? action.transportPolicy?.lifecycleStatus,
                requiredEvidenceCount: action.requiredEvidence?.count ?? 0,
                requiredEvidenceLabel: listLabel(action.requiredEvidence ?? [], limit: 5),
                userVisibleContract: action.userVisibleContract,
                claimEffect: action.claimEffect,
                writeDisposition: writeDisposition(for: action)
            )
        }

        return ClawJSRuntimeLensSessionActionPresentation(
            actionCount: actions.count,
            implementedCount: actions.filter { $0.status == "implemented" }.count,
            blockedCount: actions.filter { $0.status == "blocked" }.count,
            localOverlayCount: actions.filter { $0.status == "local_overlay_only" }.count,
            noWriteCount: actions.filter { $0.writesRuntime == false }.count,
            wouldWriteRuntimeCount: actions.filter { $0.wouldWriteRuntime == true }.count,
            requiredEvidenceCount: actions.reduce(0) { count, action in
                count + (action.requiredEvidence?.count ?? 0)
            },
            statusLabel: countLabel(actions.compactMap(\.status)),
            localOverlayActionsLabel: listLabel(
                actions.filter { $0.status == "local_overlay_only" }.map(\.action),
                limit: 5
            ),
            blockedActionsLabel: listLabel(
                actions.filter { $0.status == "blocked" }.map(\.action),
                limit: 5
            ),
            rows: rows
        )
    }

    private static func writeDisposition(
        for action: ClawJSRuntimeLensSnapshot.SessionActionPolicy
    ) -> String {
        if action.wouldWriteRuntime == true {
            return "would write"
        }
        if action.writesRuntime == false {
            return "no write"
        }
        if action.writesRuntime == true {
            return "writes runtime"
        }
        return "unknown"
    }

    private static func countLabel(_ values: [String]) -> String? {
        let counts = values.reduce(into: [String: Int]()) { result, value in
            result[value, default: 0] += 1
        }
        let pairs = counts.sorted { $0.key < $1.key }
        guard !pairs.isEmpty else { return nil }
        return pairs.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
    }

    private static func listLabel(_ values: [String], limit: Int) -> String? {
        guard !values.isEmpty else { return nil }
        return values.prefix(limit).joined(separator: ", ")
    }
}
