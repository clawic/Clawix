import Foundation

struct ClawJSRuntimeLensSupportAuditPresentation: Equatable {
    let closureState: String
    let supportComplete: Bool
    let allDomainsAccountedFor: Bool
    let evidenceRequirementCount: Int
    let directBlockerCount: Int
    let externalPendingCount: Int
    let productBlockedRequirementCount: Int
    let supportStage: String?
    let blockerClassLabel: String?
    let directBlockerDomainsLabel: String?
    let externalPendingDomainsLabel: String?
    let blockedWriteBackDomainsLabel: String?
    let ecosystemExternalPendingDomainsLabel: String?
    let promotionGate: String?
    let provenanceSource: String?
    let provenanceRuntimeId: String?
    let provenanceLabel: String?

    var domainCoverageLabel: String {
        allDomainsAccountedFor ? "all domains" : "coverage gap"
    }

    var accessibilityLabel: String {
        [
            "Runtime support audit",
            "closure \(closureState)",
            "support complete \(supportComplete)",
            "domain coverage \(domainCoverageLabel)",
            "evidence requirements \(evidenceRequirementCount)",
            "direct blockers \(directBlockerCount)",
            "external pending \(externalPendingCount)",
            "product blocked \(productBlockedRequirementCount)",
            supportStage.map { "support stage \($0)" },
            blockerClassLabel.map { "blocker classes \($0)" },
            directBlockerDomainsLabel.map { "direct blocker domains \($0)" },
            externalPendingDomainsLabel.map { "external pending domains \($0)" },
            blockedWriteBackDomainsLabel.map { "blocked write back domains \($0)" },
            ecosystemExternalPendingDomainsLabel.map { "ecosystem external pending domains \($0)" },
            promotionGate.map { "promotion gate \($0)" },
            provenanceSource.map { "provenance source \($0)" },
            provenanceRuntimeId.map { "provenance runtime \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    static func make(
        audit: ClawJSRuntimeLensSnapshot.SupportAudit
    ) -> ClawJSRuntimeLensSupportAuditPresentation {
        ClawJSRuntimeLensSupportAuditPresentation(
            closureState: audit.closureState ?? "unknown",
            supportComplete: audit.supportComplete == true,
            allDomainsAccountedFor: audit.allDomainsAccountedFor == true,
            evidenceRequirementCount: audit.blockerSummary?.evidenceRequirementCount ?? 0,
            directBlockerCount: audit.blockerSummary?.byBlockerClass?["direct_blocker"] ?? 0,
            externalPendingCount: audit.blockerSummary?.byBlockerClass?["external_pending"] ?? 0,
            productBlockedRequirementCount: audit.blockerSummary?.productBlockedRequirementCount ?? 0,
            supportStage: audit.supportStage,
            blockerClassLabel: countLabel(audit.blockerSummary?.byBlockerClass),
            directBlockerDomainsLabel: listLabel(audit.blockerSummary?.directBlockerDomains, limit: 5),
            externalPendingDomainsLabel: listLabel(audit.blockerSummary?.externalPendingDomains, limit: 5),
            blockedWriteBackDomainsLabel: listLabel(audit.blockerSummary?.blockedWriteBackDomains, limit: 5),
            ecosystemExternalPendingDomainsLabel: listLabel(
                audit.blockerSummary?.ecosystemExternalPendingDomains,
                limit: 5
            ),
            promotionGate: audit.promotionGate,
            provenanceSource: normalized(audit.provenance?.source),
            provenanceRuntimeId: normalized(audit.provenance?.runtimeId),
            provenanceLabel: provenanceLabel(audit.provenance)
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

    private static func provenanceLabel(
        _ provenance: ClawJSRuntimeLensSnapshot.SupportAudit.Provenance?
    ) -> String? {
        let parts = [
            normalized(provenance?.source),
            normalized(provenance?.runtimeId).map { "runtime \($0)" }
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return nil
        }
        return value
    }
}
