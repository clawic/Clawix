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
        let approvalGateFixtureLabel: String?
        let liveEvidenceFixtureLabel: String?
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

        var officialCommandsLabel: String? {
            ClawJSRuntimeLensSupportContractPresentation.listLabel(officialCommands, limit: 4)
        }

        var evidenceRequirementCount: Int {
            evidenceRequirements.count
        }

        var evidenceRequirementsLabel: String? {
            ClawJSRuntimeLensSupportContractPresentation.listLabel(evidenceRequirements.map(\.id), limit: 4)
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
                approvalGateFixtureLabel.map { "approval gate receipt \($0)" },
                liveEvidenceFixtureLabel.map { "live evidence receipt \($0)" },
                validation.map { "validation \($0)" },
                "external pending \(externalPending)",
                freshness.map { "freshness \($0)" },
                "commands \(officialCommandCount)",
                officialCommandsLabel.map { "official commands \($0)" },
                "evidence \(evidenceRequirementCount)",
                evidenceRequirementsLabel.map { "evidence ids \($0)" },
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
        withUnsafePointer(to: snapshot) { snapshotPointer in
            presentation(rows: supportContractRows(snapshot: snapshotPointer))
        }
    }

    @inline(never)
    private static func supportContractRows(snapshot: UnsafePointer<ClawJSRuntimeLensSnapshot>) -> [Row] {
        var rows: [Row] = []
        rows.reserveCapacity(ClawJSRuntimeLensSnapshot.canonicalDomains.count)
        appendRow(domain: "sessions", contract: snapshot.pointee.domainData?.sessions?.supportContract, domains: snapshot.pointee.domains, to: &rows)
        appendRow(domain: "skills", contract: snapshot.pointee.domainData?.skills?.supportContract, domains: snapshot.pointee.domains, to: &rows)
        appendRow(domain: "memory", contract: snapshot.pointee.domainData?.memory?.supportContract, domains: snapshot.pointee.domains, to: &rows)
        appendRow(domain: "channels", contract: snapshot.pointee.domainData?.channels?.supportContract, domains: snapshot.pointee.domains, to: &rows)
        appendRow(domain: "providers", contract: snapshot.pointee.domainData?.providers?.supportContract, domains: snapshot.pointee.domains, to: &rows)
        appendRow(domain: "auth", contract: snapshot.pointee.domainData?.auth?.supportContract, domains: snapshot.pointee.domains, to: &rows)
        appendRow(domain: "models", contract: snapshot.pointee.domainData?.models?.supportContract, domains: snapshot.pointee.domains, to: &rows)
        appendRow(domain: "scheduler", contract: snapshot.pointee.domainData?.scheduler?.supportContract, domains: snapshot.pointee.domains, to: &rows)
        appendRow(domain: "plugins", contract: snapshot.pointee.domainData?.plugins?.supportContract, domains: snapshot.pointee.domains, to: &rows)
        appendRow(domain: "gateway", contract: snapshot.pointee.domainData?.gateway?.supportContract, domains: snapshot.pointee.domains, to: &rows)
        appendRow(domain: "doctorCompat", contract: snapshot.pointee.domainData?.doctorCompat?.supportContract, domains: snapshot.pointee.domains, to: &rows)
        appendRow(domain: "sandboxPermissions", contract: snapshot.pointee.domainData?.sandboxPermissions?.supportContract, domains: snapshot.pointee.domains, to: &rows)
        appendRow(domain: "configuration", contract: snapshot.pointee.domainData?.configuration?.supportContract, domains: snapshot.pointee.domains, to: &rows)
        return rows
    }

    @inline(never)
    private static func presentation(rows: [Row]) -> ClawJSRuntimeLensSupportContractPresentation {
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

    private static func appendRow(
        domain: String,
        contract: ClawJSRuntimeLensSnapshot.SupportContract?,
        domains: [ClawJSRuntimeLensSnapshot.Domain],
        to rows: inout [Row]
    ) {
        guard let contract else { return }
        let metadata = fixtureMetadata(for: domain, domains: domains)
        rows.append(Row(
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
            approvalGateFixtureLabel: approvalGateFixtureLabel(
                status: metadata.approvalGateStatus,
                receipt: metadata.approvalGateReceipt
            ),
            liveEvidenceFixtureLabel: liveEvidenceFixtureLabel(
                status: metadata.liveEvidenceStatus,
                receipt: metadata.liveEvidenceReceipt
            ),
            validation: contract.validation,
            externalPending: contract.externalPending == true,
            freshness: contract.freshness,
            officialCommands: contract.officialCommands ?? [],
            evidenceRequirements: contract.evidenceRequirements ?? [],
            provenanceSource: contract.provenance?.source,
            provenanceRuntimeId: contract.provenance?.runtimeId,
            provenanceDomain: contract.provenance?.domain
        ))
    }

    private static func fixtureMetadata(
        for domain: String,
        domains: [ClawJSRuntimeLensSnapshot.Domain]
    ) -> (
        writeBackApprovalGated: Bool,
        approvalGateStatus: String?,
        approvalGateReceipt: ClawJSRuntimeLensSnapshot.ApprovalGateFixtureReceipt?,
        liveEvidenceStatus: String?,
        liveEvidenceReceipt: ClawJSRuntimeLensSnapshot.LiveEvidenceFixtureReceipt?
    ) {
        guard let metadata = domains.first(where: { $0.domain == domain }) else {
            return (false, nil, nil, nil, nil)
        }
        return (
            metadata.writeBackApprovalGated == true,
            metadata.approvalGateFixtureStatus,
            metadata.approvalGateFixtureReceipt,
            metadata.liveEvidenceFixtureStatus,
            metadata.liveEvidenceFixtureReceipt
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
        let visibleLimit = max(0, limit)
        var visible = Array(values.prefix(visibleLimit))
        let hiddenCount = max(0, values.count - visible.count)
        if hiddenCount > 0 {
            visible.append("+\(hiddenCount) more")
        }
        return visible.joined(separator: ", ")
    }

    private static func approvalGateFixtureLabel(
        status: String?,
        receipt: ClawJSRuntimeLensSnapshot.ApprovalGateFixtureReceipt?
    ) -> String? {
        guard let status else { return nil }
        let values = [
            status,
            receipt?.receiptId.map { "receipt \($0)" },
            receipt?.status.map { "status \($0)" },
            receipt?.redacted.map { "redacted \($0)" }
        ]
        .compactMap { $0 }
        return values.joined(separator: ", ")
    }

    private static func liveEvidenceFixtureLabel(
        status: String?,
        receipt: ClawJSRuntimeLensSnapshot.LiveEvidenceFixtureReceipt?
    ) -> String? {
        guard let status else { return nil }
        let values = [
            status,
            receipt?.receiptId.map { "receipt \($0)" },
            receipt?.status.map { "status \($0)" },
            receipt?.redacted.map { "redacted \($0)" },
            receipt?.readOnly.map { "read only \($0)" }
        ]
        .compactMap { $0 }
        return values.joined(separator: ", ")
    }
}

private extension ClawJSRuntimeLensSnapshot {
    enum SupportContractDomain: String {
        case sessions
        case skills
        case memory
        case channels
        case providers
        case auth
        case models
        case scheduler
        case plugins
        case gateway
        case doctorCompat
        case sandboxPermissions
        case configuration
    }

    func supportContract(for domain: String) -> SupportContractDomain? {
        SupportContractDomain(rawValue: domain)
    }
}
