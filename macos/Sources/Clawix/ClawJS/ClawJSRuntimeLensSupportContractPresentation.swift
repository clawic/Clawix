import Foundation

struct ClawJSRuntimeLensSupportContractPresentation: Equatable {
    struct Row: Equatable, Identifiable {
        let id: String
        let domain: String
        let displayLabel: String
        let claim: String?
        let contractAuthority: String?
        let canonicalAuthority: String?
        let nativeAuthority: String?
        let persistence: String?
        let relation: String?
        let lossPolicy: String?
        let writeBackPolicy: String?
        let writeBackAllowed: Bool
        let validation: String?
        let externalPending: Bool
        let freshness: String?
        let officialCommands: [String]
        let evidenceRequirements: [ClawJSRuntimeLensSnapshot.EvidenceRequirement]
        let provenanceSource: String?
        let provenanceRuntimeId: String?
        let provenanceDomain: String?

        var authorityLabel: String? {
            let values = [canonicalAuthority, nativeAuthority].compactMap { $0 }
            guard !values.isEmpty else { return nil }
            return values.joined(separator: " -> ")
        }

        var policyLabel: String? {
            let values = [writeBackPolicy, validation, freshness].compactMap { $0 }
            guard !values.isEmpty else { return nil }
            return values.joined(separator: ", ")
        }

        var relationshipLabel: String? {
            let values = [persistence, relation, lossPolicy].compactMap { $0 }
            guard !values.isEmpty else { return nil }
            return values.joined(separator: ", ")
        }

        var contractAuthorityLabel: String? {
            guard let contractAuthority else { return nil }
            return "contract authority: \(contractAuthority)"
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

        var officialCommandCount: Int {
            officialCommands.count
        }

        var evidenceRequirementCount: Int {
            evidenceRequirements.count
        }

        var accessibilityLabel: String {
            [
                "runtime support contract \(domain)",
                "label \(displayLabel)",
                claim.map { "claim \($0)" },
                contractAuthority.map { "contract authority \($0)" },
                canonicalAuthority.map { "canonical authority \($0)" },
                nativeAuthority.map { "native authority \($0)" },
                persistence.map { "persistence \($0)" },
                relation.map { "relation \($0)" },
                lossPolicy.map { "loss policy \($0)" },
                writeBackPolicy.map { "write back \($0)" },
                "write back allowed \(writeBackAllowed)",
                validation.map { "validation \($0)" },
                "external pending \(externalPending)",
                freshness.map { "freshness \($0)" },
                "commands \(officialCommandCount)",
                "evidence \(evidenceRequirementCount)",
                provenanceSource.map { "provenance source \($0)" },
                provenanceRuntimeId.map { "provenance runtime \($0)" },
                provenanceDomain.map { "provenance domain \($0)" }
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        }
    }

    let contractDomainCount: Int
    let writeBackAllowedCount: Int
    let blockedWriteBackCount: Int
    let externalPendingCount: Int
    let evidenceRequirementCount: Int
    let nativeCommandDomainCount: Int
    let contractAuthorityDomainCount: Int
    let provenanceDomainCount: Int
    let validationLabel: String?
    let writeBackPolicyLabel: String?
    let contractAuthorityLabel: String?
    let provenanceSourceLabel: String?
    let externalPendingDomainsLabel: String?
    let rows: [Row]

    var hasContracts: Bool {
        !rows.isEmpty
    }

    var accessibilityLabel: String {
        [
            "Runtime support contracts",
            "domains \(contractDomainCount)",
            "write back allowed \(writeBackAllowedCount)",
            "blocked write back \(blockedWriteBackCount)",
            "external pending \(externalPendingCount)",
            "evidence \(evidenceRequirementCount)",
            "native command domains \(nativeCommandDomainCount)",
            "contract authority domains \(contractAuthorityDomainCount)",
            "provenance domains \(provenanceDomainCount)",
            validationLabel.map { "validation \($0)" },
            writeBackPolicyLabel.map { "write back policies \($0)" },
            contractAuthorityLabel.map { "contract authorities \($0)" },
            provenanceSourceLabel.map { "provenance sources \($0)" },
            externalPendingDomainsLabel.map { "external pending domains \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    static func make(snapshot: ClawJSRuntimeLensSnapshot) -> ClawJSRuntimeLensSupportContractPresentation {
        let rows = ClawJSRuntimeLensSnapshot.canonicalDomains.compactMap { domain -> Row? in
            guard let contract = snapshot.supportContract(for: domain) else { return nil }
            return Row(
                id: domain,
                domain: domain,
                displayLabel: ClawJSRuntimeLensSnapshot.displayLabel(for: domain),
                claim: contract.claim,
                contractAuthority: contract.authority,
                canonicalAuthority: contract.canonicalAuthority,
                nativeAuthority: contract.nativeAuthority,
                persistence: contract.persistence,
                relation: contract.relation,
                lossPolicy: contract.lossPolicy,
                writeBackPolicy: contract.writeBackPolicy,
                writeBackAllowed: contract.writeBackAllowed == true,
                validation: contract.validation,
                externalPending: contract.externalPending == true,
                freshness: contract.freshness,
                officialCommands: contract.officialCommands ?? [],
                evidenceRequirements: contract.evidenceRequirements ?? [],
                provenanceSource: contract.provenance?.source,
                provenanceRuntimeId: contract.provenance?.runtimeId,
                provenanceDomain: contract.provenance?.domain
            )
        }

        return ClawJSRuntimeLensSupportContractPresentation(
            contractDomainCount: rows.count,
            writeBackAllowedCount: rows.filter(\.writeBackAllowed).count,
            blockedWriteBackCount: rows.filter { row in
                row.writeBackPolicy?.contains("blocked") == true
            }.count,
            externalPendingCount: rows.filter(\.externalPending).count,
            evidenceRequirementCount: rows.reduce(0) { $0 + $1.evidenceRequirementCount },
            nativeCommandDomainCount: rows.filter { !$0.officialCommands.isEmpty }.count,
            contractAuthorityDomainCount: rows.filter { $0.contractAuthority != nil }.count,
            provenanceDomainCount: rows.filter { $0.provenanceLabel != nil }.count,
            validationLabel: countLabel(rows.compactMap(\.validation)),
            writeBackPolicyLabel: countLabel(rows.compactMap(\.writeBackPolicy)),
            contractAuthorityLabel: countLabel(rows.compactMap(\.contractAuthority)),
            provenanceSourceLabel: countLabel(rows.compactMap(\.provenanceSource)),
            externalPendingDomainsLabel: listLabel(rows.filter(\.externalPending).map(\.domain), limit: 5),
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

private extension ClawJSRuntimeLensSnapshot {
    func supportContract(for domain: String) -> ClawJSRuntimeLensSnapshot.SupportContract? {
        switch domain {
        case "sessions": return domainData?.sessions?.supportContract
        case "skills": return domainData?.skills?.supportContract
        case "memory": return domainData?.memory?.supportContract
        case "channels": return domainData?.channels?.supportContract
        case "providers": return domainData?.providers?.supportContract
        case "auth": return domainData?.auth?.supportContract
        case "models": return domainData?.models?.supportContract
        case "scheduler": return domainData?.scheduler?.supportContract
        case "plugins": return domainData?.plugins?.supportContract
        case "gateway": return domainData?.gateway?.supportContract
        case "doctorCompat": return domainData?.doctorCompat?.supportContract
        case "sandboxPermissions": return domainData?.sandboxPermissions?.supportContract
        case "configuration": return domainData?.configuration?.supportContract
        default: return nil
        }
    }
}
