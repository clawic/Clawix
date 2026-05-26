import Foundation

struct ClawJSRuntimeLensSupportAuditDomainPresentation: Equatable {
    struct Row: Equatable, Identifiable {
        var id: String { domain }
        let domain: String
        let claim: String?
        let status: String?
        let readProjectionStatus: String?
        let externalPending: Bool
        let writeBackAllowed: Bool
        let writeBackApprovalGated: Bool
        let approvalGateFixtureStatus: String?
        let authorityLabel: String?
        let policyLabel: String?
        let relationshipLabel: String?
        let implementedFacetsLabel: String?
        let blockingFacetsLabel: String?
        let blockerClassesLabel: String?
        let evidenceDispositionsLabel: String?
        let evidenceRequirementIdsLabel: String?
        let supportResolutionsLabel: String?

        var accessibilityLabel: String {
            [
                "runtime support audit domain \(domain)",
                claim.map { "claim \($0)" },
                status.map { "status \($0)" },
                readProjectionStatus.map { "read projection \($0)" },
                "external pending \(externalPending)",
                "write back allowed \(writeBackAllowed)",
                "write back approval gated \(writeBackApprovalGated)",
                approvalGateFixtureStatus.map { "approval gate fixture \($0)" },
                authorityLabel.map { "authority \($0)" },
                policyLabel.map { "policy \($0)" },
                relationshipLabel.map { "relationship \($0)" },
                implementedFacetsLabel.map { "implemented facets \($0)" },
                blockingFacetsLabel.map { "blocking facets \($0)" },
                blockerClassesLabel.map { "blocker classes \($0)" },
                evidenceDispositionsLabel.map { "evidence dispositions \($0)" },
                evidenceRequirementIdsLabel.map { "evidence ids \($0)" },
                supportResolutionsLabel.map { "support resolutions \($0)" }
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        }
    }

    let domainCount: Int
    let externalPendingCount: Int
    let writeBackAllowedCount: Int
    let approvalGatedCount: Int
    let evidenceDomainCount: Int
    let blockerDomainCount: Int
    let rows: [Row]

    var totalLabel: String {
        "audit domains \(domainCount)"
    }

    var accessibilityLabel: String {
        [
            "Runtime support audit domains",
            "domains \(domainCount)",
            "external pending \(externalPendingCount)",
            "write back allowed \(writeBackAllowedCount)",
            "approval gated \(approvalGatedCount)",
            "evidence domains \(evidenceDomainCount)",
            "blocker domains \(blockerDomainCount)",
            rows.map { "\($0.domain) \($0.status ?? "unknown")" }.joined(separator: ", ")
        ]
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }

    static func make(
        domains: [ClawJSRuntimeLensSnapshot.SupportAudit.DomainAudit],
        limit: Int = 8
    ) -> ClawJSRuntimeLensSupportAuditDomainPresentation {
        let rows = domains.prefix(max(0, limit)).map { domain in
            Row(
                domain: domain.domain,
                claim: domain.claim,
                status: domain.status,
                readProjectionStatus: domain.readProjectionStatus,
                externalPending: domain.externalPending == true,
                writeBackAllowed: domain.writeBackAllowed == true,
                writeBackApprovalGated: domain.writeBackApprovalGated == true,
                approvalGateFixtureStatus: domain.approvalGateFixtureStatus,
                authorityLabel: listLabel([domain.canonicalAuthority, domain.nativeAuthority].compactMap { $0 }, limit: 2),
                policyLabel: listLabel([domain.writeBackPolicy, domain.validation, domain.freshness].compactMap { $0 }, limit: 3),
                relationshipLabel: listLabel([domain.persistence, domain.relation, domain.lossPolicy].compactMap { $0 }, limit: 3),
                implementedFacetsLabel: listLabel(domain.implementedFacets, limit: 4),
                blockingFacetsLabel: listLabel(domain.blockingFacets, limit: 4),
                blockerClassesLabel: listLabel(domain.blockerClasses, limit: 4),
                evidenceDispositionsLabel: listLabel(domain.evidenceDispositions, limit: 4),
                evidenceRequirementIdsLabel: listLabel(domain.evidenceRequirementIds, limit: 4),
                supportResolutionsLabel: listLabel(domain.supportResolutions, limit: 4)
            )
        }

        return ClawJSRuntimeLensSupportAuditDomainPresentation(
            domainCount: domains.count,
            externalPendingCount: domains.filter { $0.externalPending == true }.count,
            writeBackAllowedCount: domains.filter { $0.writeBackAllowed == true }.count,
            approvalGatedCount: domains.filter { $0.writeBackApprovalGated == true }.count,
            evidenceDomainCount: domains.filter { !($0.evidenceRequirementIds ?? []).isEmpty }.count,
            blockerDomainCount: domains.filter { !($0.blockerClasses ?? []).isEmpty }.count,
            rows: Array(rows)
        )
    }

    private static func listLabel(_ values: [String]?, limit: Int) -> String? {
        guard let values, !values.isEmpty else { return nil }
        let visibleLimit = max(0, limit)
        var visible = Array(values.prefix(visibleLimit))
        let hiddenCount = max(0, values.count - visible.count)
        if hiddenCount > 0 {
            visible.append("+\(hiddenCount) more")
        }
        return visible.joined(separator: ", ")
    }
}
