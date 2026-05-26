import Foundation

struct ClawJSRuntimeLensSessionActionContractPresentation: Equatable {
    struct Row: Equatable, Identifiable {
        let id: String
        let action: String
        let contractStatus: String?
        let materializedStatus: String?
        let statusChanged: Bool
        let contractWriteDisposition: String
        let materializedWriteDisposition: String
        let authority: String?
        let delegatesTo: String?
        let guardName: String?
        let officialProtocol: String?
        let officialMethod: String?
        let officialContractSource: String?
        let transportPolicyId: String?
        let productionTransportStatus: String?
        let lifecycleStatus: String?
        let nativeWriteBackStatus: String?
        let nativeWriteBackSafeDefault: String?
        let evidenceRequirementId: String?
        let requiredEvidenceCount: Int

        var detailLabel: String? {
            let values = [
                authority,
                delegatesTo,
                guardName,
                officialProtocol,
                officialMethod,
                officialContractSource,
                transportPolicyId.map { "transport policy \($0)" },
                productionTransportStatus.map { "production transport \($0)" },
                lifecycleStatus.map { "lifecycle \($0)" },
                nativeWriteBackStatus.map { "native write-back \($0)" },
                nativeWriteBackSafeDefault.map { "safe default \($0)" },
                evidenceRequirementId.map { "evidence \($0)" },
                requiredEvidenceCount > 0 ? "evidence \(requiredEvidenceCount)" : nil,
                statusChanged ? "materialized" : nil
            ].compactMap { $0 }
            guard !values.isEmpty else { return nil }
            return values.joined(separator: ", ")
        }

        var accessibilityLabel: String {
            [
                "session action contract \(action)",
                contractStatus.map { "contract status \($0)" },
                materializedStatus.map { "materialized status \($0)" },
                "status changed \(statusChanged)",
                "contract disposition \(contractWriteDisposition)",
                "materialized disposition \(materializedWriteDisposition)",
                authority.map { "authority \($0)" },
                delegatesTo.map { "delegates to \($0)" },
                guardName.map { "guard \($0)" },
                officialProtocol.map { "official protocol \($0)" },
                officialMethod.map { "official method \($0)" },
                officialContractSource.map { "official contract source \($0)" },
                transportPolicyId.map { "transport policy \($0)" },
                productionTransportStatus.map { "production transport \($0)" },
                lifecycleStatus.map { "lifecycle \($0)" },
                nativeWriteBackStatus.map { "native write-back \($0)" },
                nativeWriteBackSafeDefault.map { "safe default \($0)" },
                evidenceRequirementId.map { "evidence \($0)" },
                "required evidence \(requiredEvidenceCount)"
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        }
    }

    let contractCount: Int
    let materializedCount: Int
    let statusChangedCount: Int
    let contractOnlyCount: Int
    let materializedOnlyCount: Int
    let runtimeWriteContractCount: Int
    let wouldWriteRuntimeCount: Int
    let localOverlayContractCount: Int
    let nativeWriteBackBlockedCount: Int
    let requiredEvidenceCount: Int
    let statusChangedActionsLabel: String?
    let contractOnlyActionsLabel: String?
    let materializedOnlyActionsLabel: String?
    let rows: [Row]

    var hasRows: Bool {
        !rows.isEmpty
    }

    var accessibilityLabel: String {
        [
            "Runtime session action contracts",
            "contracts \(contractCount)",
            "materialized \(materializedCount)",
            "status changed \(statusChangedCount)",
            "contract only \(contractOnlyCount)",
            "materialized only \(materializedOnlyCount)",
            "runtime write contracts \(runtimeWriteContractCount)",
            "would write runtime \(wouldWriteRuntimeCount)",
            "local overlay contracts \(localOverlayContractCount)",
            "native write-back blocked \(nativeWriteBackBlockedCount)",
            "required evidence \(requiredEvidenceCount)",
            statusChangedActionsLabel.map { "changed actions \($0)" },
            contractOnlyActionsLabel.map { "contract only actions \($0)" },
            materializedOnlyActionsLabel.map { "materialized only actions \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    static func make(
        contracts: [ClawJSRuntimeLensSnapshot.SessionActionPolicy],
        materializedPolicy: [ClawJSRuntimeLensSnapshot.SessionActionPolicy] = []
    ) -> ClawJSRuntimeLensSessionActionContractPresentation {
        let contractByAction = Dictionary(uniqueKeysWithValues: contracts.map { ($0.action, $0) })
        let materializedByAction = Dictionary(uniqueKeysWithValues: materializedPolicy.map { ($0.action, $0) })
        let actions = Array(Set(contractByAction.keys).union(materializedByAction.keys)).sorted()

        let rows = actions.map { action -> Row in
            let contract = contractByAction[action]
            let materialized = materializedByAction[action]
            let statusChanged = contract?.status != nil
                && materialized?.status != nil
                && contract?.status != materialized?.status
            return Row(
                id: action,
                action: action,
                contractStatus: contract?.status,
                materializedStatus: materialized?.status,
                statusChanged: statusChanged,
                contractWriteDisposition: writeDisposition(for: contract),
                materializedWriteDisposition: writeDisposition(for: materialized),
                authority: materialized?.authority ?? contract?.authority,
                delegatesTo: materialized?.delegatesTo ?? contract?.delegatesTo,
                guardName: materialized?.guardName ?? contract?.guardName,
                officialProtocol: materialized?.officialProtocol ?? contract?.officialProtocol,
                officialMethod: materialized?.officialMethod ?? contract?.officialMethod,
                officialContractSource: materialized?.officialContractSource ?? contract?.officialContractSource,
                transportPolicyId: materialized?.transportPolicy?.id ?? contract?.transportPolicy?.id,
                productionTransportStatus: materialized?.productionTransportStatus
                    ?? materialized?.transportPolicy?.productionTransportStatus
                    ?? contract?.productionTransportStatus
                    ?? contract?.transportPolicy?.productionTransportStatus,
                lifecycleStatus: materialized?.lifecycleStatus
                    ?? materialized?.transportPolicy?.lifecycleStatus
                    ?? contract?.lifecycleStatus
                    ?? contract?.transportPolicy?.lifecycleStatus,
                nativeWriteBackStatus: materialized?.nativeWriteBackStatus ?? contract?.nativeWriteBackStatus,
                nativeWriteBackSafeDefault: materialized?.nativeWriteBackSafeDefault ?? contract?.nativeWriteBackSafeDefault,
                evidenceRequirementId: materialized?.evidenceRequirementId ?? contract?.evidenceRequirementId,
                requiredEvidenceCount: materialized?.requiredEvidence?.count ?? contract?.requiredEvidence?.count ?? 0
            )
        }

        // Session actions are bounded by the runtime snapshot action catalog.
        let changedActions = rows.filter(\.statusChanged).map(\.action)
        let contractOnlyActions = actions.filter { materializedByAction[$0] == nil }
        let materializedOnlyActions = actions.filter { contractByAction[$0] == nil }

        return ClawJSRuntimeLensSessionActionContractPresentation(
            contractCount: contracts.count,
            materializedCount: materializedPolicy.count,
            statusChangedCount: changedActions.count,
            contractOnlyCount: contractOnlyActions.count,
            materializedOnlyCount: materializedOnlyActions.count,
            runtimeWriteContractCount: contracts.filter { $0.writesRuntime == true }.count,
            wouldWriteRuntimeCount: contracts.filter { $0.wouldWriteRuntime == true }.count,
            localOverlayContractCount: contracts.filter { $0.status == "local_overlay_only" }.count,
            nativeWriteBackBlockedCount: contracts.filter { $0.nativeWriteBackStatus != nil }.count,
            requiredEvidenceCount: contracts.reduce(0) { count, action in
                count + (action.requiredEvidence?.count ?? 0)
            },
            statusChangedActionsLabel: listLabel(changedActions, limit: 5),
            contractOnlyActionsLabel: listLabel(contractOnlyActions, limit: 5),
            materializedOnlyActionsLabel: listLabel(materializedOnlyActions, limit: 5),
            rows: rows
        )
    }

    private static func writeDisposition(
        for action: ClawJSRuntimeLensSnapshot.SessionActionPolicy?
    ) -> String {
        guard let action else { return "missing" }
        if action.wouldWriteRuntime == true {
            return "would write"
        }
        if action.writesRuntime == true {
            return "writes runtime"
        }
        if action.writesRuntime == false {
            return "no write"
        }
        return "unknown"
    }

    private static func listLabel(_ values: [String], limit: Int) -> String? {
        guard !values.isEmpty else { return nil }
        return values.prefix(limit).joined(separator: ", ")
    }
}
