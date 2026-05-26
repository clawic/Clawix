import Foundation

struct ClawJSRuntimeLensDomainPresentation: Equatable {
    struct Row: Equatable, Identifiable {
        let id: String
        let domain: String
        let displayLabel: String
        let status: String
        let runtimeCapabilityStatus: String?
        let runtimeCapabilitySupported: Bool?
        let runtimeCapabilityStrategy: String?
        let readProjectionStatus: String?
        let supported: Bool
        let strategy: String?
        let claim: String?
        let count: Int?
        let authority: String?
        let nativeAuthority: String?
        let persistence: String?
        let relation: String?
        let lossPolicy: String?
        let freshness: String?
        let writeBackPolicy: String?
        let writeBackAllowed: Bool?
        let validation: String?
        let externalPending: Bool
        let officialCommands: [String]
        let evidenceRequirements: [ClawJSRuntimeLensSnapshot.EvidenceRequirement]
        let limitations: [String]
        let provenanceSource: String?
        let provenanceRuntimeId: String?
        let provenanceDomain: String?

        var detailLabel: String? {
            let values = [
                strategy,
                readProjectionStatus.map { "read \($0)" },
                authority,
                freshness,
                writeBackPolicy
            ].compactMap { $0 }
            guard !values.isEmpty else { return nil }
            return values.joined(separator: ", ")
        }

        var policyLabel: String? {
            let values = [
                nativeAuthority.map { "native \($0)" },
                persistence.map { "persistence \($0)" },
                relation.map { "relation \($0)" },
                lossPolicy.map { "loss \($0)" },
                validation.map { "validation \($0)" },
                writeBackAllowed.map { $0 ? "runtime write-back allowed" : "no runtime write-back" }
            ]
            .compactMap { $0 }
            guard !values.isEmpty else { return nil }
            return values.joined(separator: ", ")
        }

        var hasPolicy: Bool {
            policyLabel != nil
        }

        var provenanceLabel: String? {
            let values = [
                provenanceSource,
                provenanceRuntimeId.map { "runtime \($0)" },
                provenanceDomain.map { "domain \($0)" }
            ]
            .compactMap { $0 }
            guard !values.isEmpty else { return nil }
            return values.joined(separator: ", ")
        }

        var commandCount: Int {
            officialCommands.count
        }

        var officialCommandsLabel: String? {
            ClawJSRuntimeLensDomainPresentation.listLabel(officialCommands, limit: 4)
        }

        var evidenceRequirementCount: Int {
            evidenceRequirements.count
        }

        var evidenceRequirementsLabel: String? {
            ClawJSRuntimeLensDomainPresentation.listLabel(evidenceRequirements.map(\.id), limit: 4)
        }

        var limitationCount: Int {
            limitations.count
        }

        var limitationsLabel: String? {
            ClawJSRuntimeLensDomainPresentation.listLabel(limitations, limit: 5)
        }

        var accessibilityLabel: String {
            [
                "runtime domain \(domain)",
                "label \(displayLabel)",
                "status \(status)",
                runtimeCapabilityStatus.map { "runtime capability status \($0)" },
                runtimeCapabilitySupported.map { "runtime capability supported \($0)" },
                runtimeCapabilityStrategy.map { "runtime capability strategy \($0)" },
                readProjectionStatus.map { "read projection \($0)" },
                "supported \(supported)",
                strategy.map { "strategy \($0)" },
                claim.map { "claim \($0)" },
                count.map { "count \($0)" },
                authority.map { "authority \($0)" },
                nativeAuthority.map { "native authority \($0)" },
                persistence.map { "persistence \($0)" },
                relation.map { "relation \($0)" },
                lossPolicy.map { "loss policy \($0)" },
                freshness.map { "freshness \($0)" },
                writeBackPolicy.map { "write back \($0)" },
                writeBackAllowed.map { "write back allowed \($0)" },
                validation.map { "validation \($0)" },
                "external pending \(externalPending)",
                "commands \(commandCount)",
                officialCommandsLabel.map { "official commands \($0)" },
                "evidence \(evidenceRequirementCount)",
                evidenceRequirementsLabel.map { "evidence ids \($0)" },
                "limitations \(limitationCount)",
                limitationsLabel.map { "limitations \($0)" },
                provenanceSource.map { "provenance source \($0)" },
                provenanceRuntimeId.map { "provenance runtime \($0)" },
                provenanceDomain.map { "provenance domain \($0)" }
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        }
    }

    let domainCount: Int
    let supportedCount: Int
    let unsupportedCount: Int
    let externalPendingCount: Int
    let evidenceRequirementCount: Int
    let nativeCommandDomainCount: Int
    let limitationDomainCount: Int
    let limitationCount: Int
    let policyDomainCount: Int
    let writeBackAllowedCount: Int
    let provenanceDomainCount: Int
    let strategyLabel: String?
    let persistenceLabel: String?
    let validationLabel: String?
    let provenanceSourceLabel: String?
    let statusLabel: String?
    let externalPendingDomainsLabel: String?
    let limitationDomainsLabel: String?
    let rows: [Row]

    var accessibilityLabel: String {
        [
            "Runtime domains",
            "domains \(domainCount)",
            "supported \(supportedCount)",
            "unsupported \(unsupportedCount)",
            "external pending \(externalPendingCount)",
            "evidence \(evidenceRequirementCount)",
            "native command domains \(nativeCommandDomainCount)",
            "limitation domains \(limitationDomainCount)",
            "limitations \(limitationCount)",
            "policy domains \(policyDomainCount)",
            "write back allowed \(writeBackAllowedCount)",
            "provenance domains \(provenanceDomainCount)",
            strategyLabel.map { "strategies \($0)" },
            persistenceLabel.map { "persistence \($0)" },
            validationLabel.map { "validation \($0)" },
            provenanceSourceLabel.map { "provenance sources \($0)" },
            statusLabel.map { "statuses \($0)" },
            externalPendingDomainsLabel.map { "external pending domains \($0)" },
            limitationDomainsLabel.map { "limitation domains \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    static func make(
        domains: [ClawJSRuntimeLensSnapshot.Domain]
    ) -> ClawJSRuntimeLensDomainPresentation {
        let rows = domains.map { domain in
            Row(
                id: domain.domain,
                domain: domain.domain,
                displayLabel: domain.displayLabel,
                status: domain.status ?? (domain.supported == false ? "unsupported" : "unknown"),
                runtimeCapabilityStatus: domain.runtimeCapabilityStatus,
                runtimeCapabilitySupported: domain.runtimeCapabilitySupported,
                runtimeCapabilityStrategy: domain.runtimeCapabilityStrategy,
                readProjectionStatus: domain.readProjectionStatus,
                supported: domain.supported != false,
                strategy: domain.strategy,
                claim: domain.claim,
                count: domain.count,
                authority: domain.canonicalAuthority ?? domain.authority,
                nativeAuthority: domain.nativeAuthority,
                persistence: domain.persistence,
                relation: domain.relation,
                lossPolicy: domain.lossPolicy,
                freshness: domain.freshness,
                writeBackPolicy: domain.writeBackPolicy,
                writeBackAllowed: domain.writeBackAllowed,
                validation: domain.validation,
                externalPending: domain.externalPending == true,
                officialCommands: domain.officialCommands ?? [],
                evidenceRequirements: domain.evidenceRequirements ?? [],
                limitations: domain.limitations ?? [],
                provenanceSource: domain.provenance?.source,
                provenanceRuntimeId: domain.provenance?.runtimeId,
                provenanceDomain: domain.provenance?.domain
            )
        }

        // Runtime lens domains are bounded by the runtime snapshot domain catalog.
        return ClawJSRuntimeLensDomainPresentation(
            domainCount: rows.count,
            supportedCount: rows.filter(\.supported).count,
            unsupportedCount: rows.filter { !$0.supported }.count,
            externalPendingCount: rows.filter(\.externalPending).count,
            evidenceRequirementCount: rows.reduce(0) { $0 + $1.evidenceRequirementCount },
            nativeCommandDomainCount: rows.filter { !$0.officialCommands.isEmpty }.count,
            limitationDomainCount: rows.filter { !$0.limitations.isEmpty }.count,
            limitationCount: rows.reduce(0) { $0 + $1.limitationCount },
            // Bounded snapshot catalog summary; no unbounded user history is read here.
            policyDomainCount: rows.filter(\.hasPolicy).count,
            writeBackAllowedCount: rows.filter { $0.writeBackAllowed == true }.count,
            provenanceDomainCount: rows.filter { $0.provenanceLabel != nil }.count,
            strategyLabel: countLabel(rows.compactMap(\.strategy)),
            persistenceLabel: countLabel(rows.compactMap(\.persistence)),
            validationLabel: countLabel(rows.compactMap(\.validation)),
            provenanceSourceLabel: countLabel(rows.compactMap(\.provenanceSource)),
            statusLabel: countLabel(rows.map(\.status)),
            externalPendingDomainsLabel: listLabel(rows.filter(\.externalPending).map(\.domain), limit: 5),
            limitationDomainsLabel: listLabel(rows.filter { !$0.limitations.isEmpty }.map(\.domain), limit: 5),
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

    private static func listLabel(_ values: [String], limit: Int) -> String? {
        guard !values.isEmpty else { return nil }
        return values.prefix(limit).joined(separator: ", ")
    }
}
