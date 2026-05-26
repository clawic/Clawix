import Foundation

enum ClawJSRuntimeLensSupportSummaryPresentation {
    struct ProjectionSummary: Equatable {
        let projectedDomainCount: Int
        let unsupportedDomainCount: Int
        let productBlockedButProjectedDomainCount: Int
        let readStatusLabel: String?
        let implementedFacetLabel: String?
        let blockingFacetLabel: String?

        var accessibilityLabel: String {
            [
                "Runtime projection summary",
                "projected domains \(projectedDomainCount)",
                "unsupported domains \(unsupportedDomainCount)",
                "product blocked but projected \(productBlockedButProjectedDomainCount)",
                readStatusLabel.map { "read statuses \($0)" },
                implementedFacetLabel.map { "implemented facets \($0)" },
                blockingFacetLabel.map { "blocking facets \($0)" }
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        }
    }

    struct SyncPolicySummary: Equatable {
        let domainCount: Int
        let readOnlyDomainCount: Int
        let localOverlayDomainCount: Int
        let writeBackAllowedDomainCount: Int
        let blockedWriteBackDomainCount: Int
        let externalPendingDomainCount: Int
        let blockedWriteBackLabel: String?
        let canonicalAuthorityLabel: String?
        let nativeAuthorityLabel: String?
        let persistenceLabel: String?
        let relationLabel: String?
        let writeBackPolicyLabel: String?
        let lossPolicyLabel: String?
        let freshnessLabel: String?
        let noSilentOverwrite: Bool?
        let defaultSyncMode: String?
        let safeDefault: String?

        var accessibilityLabel: String {
            [
                "Runtime sync policy summary",
                "domains \(domainCount)",
                "read only domains \(readOnlyDomainCount)",
                "local overlay domains \(localOverlayDomainCount)",
                "write back allowed domains \(writeBackAllowedDomainCount)",
                "blocked write back domains \(blockedWriteBackDomainCount)",
                "external pending domains \(externalPendingDomainCount)",
                canonicalAuthorityLabel.map { "canonical authority \($0)" },
                nativeAuthorityLabel.map { "native authority \($0)" },
                persistenceLabel.map { "persistence \($0)" },
                relationLabel.map { "relation \($0)" },
                writeBackPolicyLabel.map { "write back policy \($0)" },
                lossPolicyLabel.map { "loss policy \($0)" },
                freshnessLabel.map { "freshness \($0)" },
                noSilentOverwrite.map { "no silent overwrite \($0)" },
                defaultSyncMode.map { "default sync mode \($0)" },
                safeDefault.map { "safe default \($0)" }
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        }
    }

    struct EvidenceReadinessSummary: Equatable {
        let totalRequirementCount: Int
        let approvalRequiredCount: Int
        let externalPendingCount: Int
        let upstreamContractBlockedCount: Int
        let approvalGateBlockedCount: Int
        let tuiGatewayBlockedCount: Int
        let productionTransportBlockedCount: Int
        let productBlockedCount: Int
        let unresolvedNativeRequirementCount: Int
        let statusLabel: String?
        let blockerClassLabel: String?
        let safeDefaultLabel: String?
        let approvalRequiredIdsLabel: String?
        let externalPendingIdsLabel: String?
        let upstreamContractIdsLabel: String?
        let approvalGateIdsLabel: String?
        let tuiGatewayIdsLabel: String?
        let productionTransportIdsLabel: String?
        let productBlockedIdsLabel: String?
        let unresolvedNativeIdsLabel: String?
        let nextRequiredActionsLabel: String?
        let reentryPolicy: String?
        let safeDefault: String?

        var accessibilityLabel: String {
            [
                "Runtime evidence readiness summary",
                "requirements \(totalRequirementCount)",
                "approval required \(approvalRequiredCount)",
                "external pending \(externalPendingCount)",
                "upstream contract blocked \(upstreamContractBlockedCount)",
                "approval gate blocked \(approvalGateBlockedCount)",
                "tui gateway blocked \(tuiGatewayBlockedCount)",
                "production transport blocked \(productionTransportBlockedCount)",
                "product blocked \(productBlockedCount)",
                "unresolved native \(unresolvedNativeRequirementCount)",
                statusLabel.map { "statuses \($0)" },
                blockerClassLabel.map { "blocker classes \($0)" },
                safeDefaultLabel.map { "safe defaults \($0)" },
                approvalRequiredIdsLabel.map { "approval required ids \($0)" },
                externalPendingIdsLabel.map { "external pending ids \($0)" },
                upstreamContractIdsLabel.map { "upstream contract ids \($0)" },
                approvalGateIdsLabel.map { "approval gate ids \($0)" },
                tuiGatewayIdsLabel.map { "tui gateway ids \($0)" },
                productionTransportIdsLabel.map { "production transport ids \($0)" },
                productBlockedIdsLabel.map { "product blocked ids \($0)" },
                unresolvedNativeIdsLabel.map { "unresolved native ids \($0)" },
                reentryPolicy.map { "reentry policy \($0)" },
                safeDefault.map { "safe default \($0)" }
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        }
    }

    static func make(
        projection summary: ClawJSRuntimeLensSnapshot.SupportAudit.ProjectionSummary
    ) -> ProjectionSummary {
        ProjectionSummary(
            projectedDomainCount: summary.projectedDomainCount ?? 0,
            unsupportedDomainCount: summary.unsupportedDomainCount ?? 0,
            productBlockedButProjectedDomainCount: summary.productBlockedButProjectedDomainCount ?? 0,
            readStatusLabel: countLabel(summary.byReadProjectionStatus),
            implementedFacetLabel: countLabel(summary.implementedFacetCounts),
            blockingFacetLabel: countLabel(summary.blockingFacetCounts)
        )
    }

    static func make(
        sync summary: ClawJSRuntimeLensSnapshot.SupportAudit.SyncPolicySummary
    ) -> SyncPolicySummary {
        SyncPolicySummary(
            domainCount: summary.domainCount ?? 0,
            readOnlyDomainCount: summary.readOnlyProjectionDomains?.count ?? 0,
            localOverlayDomainCount: summary.localOverlayDomains?.count ?? 0,
            writeBackAllowedDomainCount: summary.writeBackAllowedDomains?.count ?? 0,
            blockedWriteBackDomainCount: summary.blockedWriteBackDomains?.count ?? 0,
            externalPendingDomainCount: summary.externalPendingDomains?.count ?? 0,
            blockedWriteBackLabel: listLabel(summary.blockedWriteBackDomains, limit: 5),
            canonicalAuthorityLabel: countLabel(summary.canonicalAuthorityCounts),
            nativeAuthorityLabel: countLabel(summary.nativeAuthorityCounts),
            persistenceLabel: countLabel(summary.persistenceCounts),
            relationLabel: countLabel(summary.relationCounts),
            writeBackPolicyLabel: countLabel(summary.writeBackPolicyCounts),
            lossPolicyLabel: countLabel(summary.lossPolicyCounts),
            freshnessLabel: countLabel(summary.freshnessCounts),
            noSilentOverwrite: summary.noSilentOverwrite,
            defaultSyncMode: summary.defaultSyncMode,
            safeDefault: summary.safeDefault
        )
    }

    static func make(
        evidenceReadiness summary: ClawJSRuntimeLensSnapshot.SupportAudit.EvidenceReadinessSummary
    ) -> EvidenceReadinessSummary {
        EvidenceReadinessSummary(
            totalRequirementCount: summary.totalRequirementCount ?? 0,
            approvalRequiredCount: summary.approvalRequiredCount ?? 0,
            externalPendingCount: summary.externalPendingCount ?? 0,
            upstreamContractBlockedCount: summary.upstreamContractBlockedCount ?? 0,
            approvalGateBlockedCount: summary.approvalGateBlockedCount ?? 0,
            tuiGatewayBlockedCount: summary.tuiGatewayBlockedCount ?? 0,
            productionTransportBlockedCount: summary.productionTransportBlockedCount ?? 0,
            productBlockedCount: summary.productBlockedCount ?? 0,
            unresolvedNativeRequirementCount: summary.unresolvedNativeRequirementCount ?? 0,
            statusLabel: countLabel(summary.statusCounts),
            blockerClassLabel: countLabel(summary.blockerClassCounts),
            safeDefaultLabel: countLabel(summary.safeDefaultCounts),
            approvalRequiredIdsLabel: listLabel(summary.approvalRequiredRequirementIds, limit: 3),
            externalPendingIdsLabel: listLabel(summary.externalPendingRequirementIds, limit: 3),
            upstreamContractIdsLabel: listLabel(summary.upstreamContractRequirementIds, limit: 3),
            approvalGateIdsLabel: listLabel(summary.approvalGateRequirementIds, limit: 3),
            tuiGatewayIdsLabel: listLabel(summary.tuiGatewayRequirementIds, limit: 3),
            productionTransportIdsLabel: listLabel(summary.productionTransportRequirementIds, limit: 3),
            productBlockedIdsLabel: listLabel(summary.productBlockedRequirementIds, limit: 3),
            unresolvedNativeIdsLabel: listLabel(summary.unresolvedNativeRequirementIds, limit: 3),
            nextRequiredActionsLabel: listLabel(summary.nextRequiredActions, limit: 5),
            reentryPolicy: summary.reentryPolicy,
            safeDefault: summary.safeDefault
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
