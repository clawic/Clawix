import SwiftUI

extension ClawJSRuntimeLensSection {
    func runtimeLensDomains(_ snapshot: ClawJSRuntimeLensSnapshot) -> some View {
        let presentation = ClawJSRuntimeLensDomainPresentation.make(domains: snapshot.domains)
        let pageKey = ClawJSRuntimeLensPageKey("domains-\(snapshot.runtimeId)")
        let slice = page(presentation.rows, key: pageKey)

        return VStack(alignment: .leading, spacing: 8) {
            ForEach(slice.rows, id: \.id) { domain in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text(domain.displayLabel)
                            .font(BodyFont.system(size: 12.5, weight: .medium))
                            .foregroundColor(Palette.textPrimary)
                            .frame(width: 92, alignment: .leading)
                            .help(domain.domain)
                        statusPill(
                            text: domain.status,
                            color: runtimeDomainColor(status: domain.status, supported: domain.supported)
                        )
                        if let claim = domain.claim {
                            statusPill(text: claim, color: claimColor(claim))
                        }
                        if let strategy = domain.strategy {
                            statusPill(text: strategy, color: Color.white.opacity(0.28))
                        }
                        if let count = domain.count {
                            Text("\(count)")
                                .font(BodyFont.system(size: 11.5, weight: .medium))
                                .foregroundColor(Palette.textSecondary)
                                .monospacedDigit()
                        }
                        Spacer()
                    }
                    if let detailLabel = domain.detailLabel {
                        Text(detailLabel)
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.8))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let policyLabel = domain.policyLabel {
                        Text("Policy: \(policyLabel)")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.78))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let limitations = domain.limitationsLabel {
                        Text("Limitations: \(limitations)")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.78))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let provenance = domain.provenanceLabel {
                        Text("Provenance: \(provenance)")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    runtimeLensDomainCommands(domain: domain.domain, commands: domain.officialCommands)
                    let evidence = domain.evidenceRequirements
                    if !evidence.isEmpty {
                        runtimeLensEvidenceRequirements(evidence, limit: 2)
                    }
                    if domain.externalPending {
                        Text("External evidence required before this claim can be promoted.")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityIdentifier("runtime-lens-domain-\(domain.domain)")
                .accessibilityLabel(Text(domain.accessibilityLabel))
            }
            pager(slice, key: pageKey)
        }
        .accessibilityIdentifier("runtime-lens-domains")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    func runtimeLensEvidenceRequirements(
        _ requirements: [ClawJSRuntimeLensSnapshot.EvidenceRequirement],
        limit: Int
    ) -> some View {
        let presentation = ClawJSRuntimeLensEvidenceRequirementPresentation.make(
            requirements: requirements,
            limit: limit
        )
        let pageKey = ClawJSRuntimeLensPageKey(
            "evidence-requirements-\(presentation.rows.first?.id ?? "empty")-\(presentation.totalRequirementCount)"
        )
        let slice = page(presentation.rows, key: pageKey)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                statusPill(text: "evidence \(presentation.totalRequirementCount)", color: .orange)
                ForEach(presentation.blockerClassLabel?.components(separatedBy: ", ") ?? [], id: \.self) { blockerLabel in
                    let blockerClass = blockerLabel.components(separatedBy: " ").first ?? blockerLabel
                    statusPill(text: blockerClass, color: evidenceBlockerColor(blockerClass))
                }
                Spacer()
            }
            ForEach(slice.rows) { requirement in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(requirement.id)
                            .font(BodyFont.system(size: 10.5, weight: .medium))
                            .foregroundColor(Palette.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if requirement.approvalRequired {
                            statusPill(text: "approval", color: .orange)
                        }
                        Spacer()
                    }
                    if let commandShape = requirement.commandShape {
                        Text(commandShape)
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.78))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let disposition = requirement.evidenceDisposition {
                        Text(disposition)
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.78))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let behavior = requirement.currentBehavior {
                        Text(behavior)
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let resolution = requirement.resolutionLabel {
                        Text(resolution)
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .accessibilityIdentifier("runtime-lens-evidence-requirement-\(requirement.id)")
                .accessibilityLabel(Text(requirement.accessibilityLabel))
            }
            pager(slice, key: pageKey)
        }
        .accessibilityIdentifier("runtime-lens-evidence-requirements")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    func evidenceBlockerColor(_ blockerClass: String) -> Color {
        runtimeLensColor(ClawJSRuntimeLensStatusTone.evidenceBlockerClass(blockerClass))
    }

    func runtimeLensDomainCommands(domain: String, commands: [String]) -> some View {
        let presentation = ClawJSRuntimeLensDomainCommandPresentation.make(
            domain: domain,
            commands: commands
        )
        let pageKey = ClawJSRuntimeLensPageKey("domain-commands-\(domain)")
        let slice = page(presentation.rows, key: pageKey)

        return Group {
            if presentation.hasCommands {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        ForEach(slice.rows) { command in
                            statusPill(text: command.command, color: Color.white.opacity(0.24))
                                .help(command.command)
                                .accessibilityIdentifier("runtime-lens-domain-command-\(domain)-\(command.id)")
                                .accessibilityLabel(Text(command.accessibilityLabel))
                        }
                        if presentation.hiddenCommandCount > 0 {
                            statusPill(text: "+\(presentation.hiddenCommandCount)", color: Color.white.opacity(0.2))
                        }
                        Spacer()
                    }
                    pager(slice, key: pageKey)
                }
                .accessibilityIdentifier("runtime-lens-domain-commands-\(domain)")
                .accessibilityLabel(Text(presentation.accessibilityLabel))
            }
        }
    }

    func runtimeDomainColor(status: String, supported: Bool) -> Color {
        runtimeLensColor(ClawJSRuntimeLensStatusTone.runtimeDomainStatus(status: status, supported: supported))
    }

    func claimColor(_ claim: String) -> Color {
        runtimeLensColor(ClawJSRuntimeLensStatusTone.supportClaim(claim))
    }

    func runtimeLensMissingDomains(_ presentation: ClawJSRuntimeLensMissingDomainPresentation) -> some View {
        let pageKey = ClawJSRuntimeLensPageKey("missing-domains")
        let slice = page(presentation.rows, key: pageKey)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                statusPill(text: "missing \(presentation.missingDomainCount)", color: .orange)
                statusPill(text: "present \(presentation.presentDomainCount)", color: .blue)
                Spacer()
            }
            ForEach(slice.rows) { row in
                Text(row.displayLabel)
                    .font(BodyFont.system(size: 11.5, weight: .medium))
                    .foregroundColor(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(row.domain)
                    .accessibilityIdentifier("runtime-lens-missing-domain-\(row.domain)")
                    .accessibilityLabel(Text(row.accessibilityLabel))
            }
            pager(slice, key: pageKey)
        }
        .accessibilityIdentifier("runtime-lens-missing-domains")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    func runtimeLensSupportContracts(_ presentation: ClawJSRuntimeLensSupportContractPresentation) -> some View {
        let pageKey = ClawJSRuntimeLensPageKey("support-contracts")
        let slice = page(presentation.rows, key: pageKey)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                statusPill(text: "contracts \(presentation.contractDomainCount)", color: .blue)
                if presentation.blockedWriteBackCount > 0 {
                    statusPill(text: "blocked write \(presentation.blockedWriteBackCount)", color: .orange)
                }
                if presentation.externalPendingCount > 0 {
                    statusPill(text: "external \(presentation.externalPendingCount)", color: .orange)
                }
                if presentation.evidenceRequirementCount > 0 {
                    statusPill(text: "evidence \(presentation.evidenceRequirementCount)", color: .orange)
                }
                Spacer()
            }
            ForEach(slice.rows, id: \.id) { contract in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text(contract.displayLabel)
                            .font(BodyFont.system(size: 12, weight: .medium))
                            .foregroundColor(Palette.textPrimary)
                            .frame(width: 92, alignment: .leading)
                            .help(contract.domain)
                        if let claim = contract.claim {
                            statusPill(text: claim, color: claimColor(claim))
                        }
                        statusPill(
                            text: contract.writeBackAllowed ? "write-back" : "no write-back",
                            color: contract.writeBackAllowed ? .green : .orange
                        )
                        if contract.externalPending {
                            statusPill(text: "external", color: .orange)
                        }
                        Spacer()
                    }
                    if let authority = contract.authorityLabel {
                        Text(authority)
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.78))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let contractAuthority = contract.contractAuthorityLabel {
                        Text(contractAuthority)
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.78))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let policy = contract.policyLabel {
                        Text(policy)
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.78))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let relationship = contract.relationshipLabel {
                        Text(relationship)
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let provenance = contract.provenanceLabel {
                        Text("Provenance: \(provenance)")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    runtimeLensDomainCommands(domain: contract.domain, commands: contract.officialCommands)
                    if !contract.evidenceRequirements.isEmpty {
                        runtimeLensEvidenceRequirements(contract.evidenceRequirements, limit: 2)
                    }
                }
                .accessibilityIdentifier("runtime-lens-support-contract-\(contract.domain)")
                .accessibilityLabel(Text(contract.accessibilityLabel))
            }
            pager(slice, key: pageKey)
        }
        .accessibilityIdentifier("runtime-lens-support-contracts")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

}
