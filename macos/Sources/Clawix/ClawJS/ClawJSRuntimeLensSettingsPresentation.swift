import Foundation

struct ClawJSRuntimeLensSettingsPresentation: Equatable {
    struct Pill: Equatable, Identifiable {
        let id: String
        let label: String
        let tone: ClawJSRuntimeLensStatusTone
    }

    struct Row: Equatable, Identifiable {
        let id: String
        let label: String
        let value: String?
        let pills: [Pill]
        let detailLines: [String]
        let accessibilityLabel: String
    }

    struct Section: Equatable, Identifiable {
        let id: String
        let title: String
        let rows: [Row]
        let accessibilityLabel: String
    }

    let runtimeId: String
    let runtimeLabel: String
    let hasSnapshot: Bool
    let viewState: ClawJSRuntimeLensViewStatePresentation
    let validationAccessibilityLabel: String
    let sections: [Section]
    private let runtimeSummaryBySectionId: [String: ClawJSRuntimeLensRuntimeSummaryPresentation]
    private let domainPresentationBySectionId: [String: ClawJSRuntimeLensDomainPresentation]

    var sectionCount: Int { sections.count }
    var rowCount: Int { sections.reduce(0) { $0 + $1.rows.count } }

    var runtimeSummary: ClawJSRuntimeLensRuntimeSummaryPresentation? {
        guard let section = sections.first(where: { $0.id == "runtime" }) else { return nil }
        return runtimeSummaryBySectionId[section.id]
    }

    var domainPresentation: ClawJSRuntimeLensDomainPresentation? {
        guard let section = sections.first(where: { $0.id == "domains" }) else { return nil }
        return domainPresentationBySectionId[section.id]
    }

    static func make(
        runtime: ClawJSRuntimeLensID,
        isRefreshing: Bool,
        loadError: String?,
        actionError: String?,
        snapshot: ClawJSRuntimeLensSnapshot?
    ) -> ClawJSRuntimeLensSettingsPresentation {
        let viewState = ClawJSRuntimeLensViewStatePresentation.make(
            runtime: runtime,
            isRefreshing: isRefreshing,
            loadError: loadError,
            actionError: actionError,
            hasSnapshot: snapshot != nil
        )
        var sections: [Section] = []
        var runtimeSummaries: [String: ClawJSRuntimeLensRuntimeSummaryPresentation] = [:]
        var domainPresentations: [String: ClawJSRuntimeLensDomainPresentation] = [:]

        if viewState.hasRows {
            sections.append(viewStateSection(viewState))
        }

        if let snapshot {
            let snapshotPresentation = makeSnapshotPresentation(snapshot: snapshot)
            sections.append(contentsOf: snapshotPresentation.sections)
            runtimeSummaries = snapshotPresentation.runtimeSummaries
            domainPresentations = snapshotPresentation.domainPresentations
        }

        let validationAccessibilityLabel = snapshot.map {
            ClawJSRuntimeLensValidationSummary.make(snapshot: $0).accessibilityLabel
        } ?? viewState.accessibilityLabel

        return ClawJSRuntimeLensSettingsPresentation(
            runtimeId: runtime.rawValue,
            runtimeLabel: runtime.label,
            hasSnapshot: snapshot != nil,
            viewState: viewState,
            validationAccessibilityLabel: validationAccessibilityLabel,
            sections: sections,
            runtimeSummaryBySectionId: runtimeSummaries,
            domainPresentationBySectionId: domainPresentations
        )
    }

    private struct SnapshotPresentation {
        let sections: [Section]
        let runtimeSummaries: [String: ClawJSRuntimeLensRuntimeSummaryPresentation]
        let domainPresentations: [String: ClawJSRuntimeLensDomainPresentation]
    }

    private static func makeSnapshotPresentation(snapshot: ClawJSRuntimeLensSnapshot) -> SnapshotPresentation {
        let runtimeSummary = ClawJSRuntimeLensRuntimeSummaryPresentation.make(snapshot: snapshot)
        let domains = ClawJSRuntimeLensDomainPresentation.make(domains: snapshot.domains)

        return SnapshotPresentation(
            sections: [
                [runtimeSection(runtimeSummary)],
                supportSections(snapshot: snapshot),
                supportAuditSections(audit: snapshot.supportAudit),
                sessionSections(snapshot: snapshot),
                commandSections(commands: snapshot.commands),
                missingDomainSections(domains: snapshot.domains),
                [domainSection(domains)],
                supportContractSections(snapshot: snapshot),
                inventorySections(snapshot: snapshot)
            ].flatMap { $0 },
            runtimeSummaries: ["runtime": runtimeSummary],
            domainPresentations: ["domains": domains]
        )
    }

    private static func supportSections(snapshot: ClawJSRuntimeLensSnapshot) -> [Section] {
        guard let support = snapshot.support else { return [] }
        return [
            supportSection(
                ClawJSRuntimeLensSupportOverviewPresentation.make(
                    support: support,
                    officialSnapshot: snapshot.officialSnapshot
                )
            )
        ]
    }

    private static func supportAuditSections(audit: ClawJSRuntimeLensSnapshot.SupportAudit?) -> [Section] {
        guard let audit else { return [] }

        var sections = [
            supportAuditSection(ClawJSRuntimeLensSupportAuditPresentation.make(audit: audit))
        ]
        if let domains = audit.domains, !domains.isEmpty {
            sections.append(supportAuditDomainsSection(ClawJSRuntimeLensSupportAuditDomainPresentation.make(domains: domains)))
        }
        if let sync = audit.syncPolicySummary {
            sections.append(syncSummarySection(ClawJSRuntimeLensSupportSummaryPresentation.make(sync: sync)))
        }
        if let projection = audit.projectionSummary {
            sections.append(projectionSummarySection(ClawJSRuntimeLensSupportSummaryPresentation.make(projection: projection)))
        }
        if let readiness = audit.evidenceReadinessSummary {
            sections.append(evidenceReadinessSummarySection(ClawJSRuntimeLensSupportSummaryPresentation.make(evidenceReadiness: readiness)))
        }
        if let requirements = audit.evidenceRequirements, !requirements.isEmpty {
            sections.append(evidenceRequirementsSection(ClawJSRuntimeLensEvidenceRequirementPresentation.make(requirements: requirements, limit: 8)))
        }
        if let checklist = audit.closureChecklist, !checklist.isEmpty {
            sections.append(closureSection(ClawJSRuntimeLensClosureChecklistPresentation.make(checklist: checklist, summary: audit.closureChecklistSummary)))
        }
        if let review = audit.finalPromotionReview {
            sections.append(promotionReviewSection(ClawJSRuntimeLensSupportDecisionPresentation.make(review: review)))
        }
        if let decision = audit.finalSupportClaimDecision {
            sections.append(finalDecisionSection(ClawJSRuntimeLensSupportDecisionPresentation.make(decision: decision)))
        }
        if let packets = audit.evidenceReentryPackets, !packets.isEmpty {
            sections.append(reentrySection(ClawJSRuntimeLensEvidenceReentryPresentation.make(packets: packets)))
        }
        return sections
    }

    private static func sessionSections(snapshot: ClawJSRuntimeLensSnapshot) -> [Section] {
        guard let sessions = snapshot.domainData?.sessions else {
            guard let session = snapshot.session else { return [] }
            return [sessionSection(ClawJSRuntimeLensSessionDescriptorPresentation.make(session: session))]
        }

        var sections = [
            sessionInventorySection(ClawJSRuntimeLensSessionInventoryPresentation.make(bucket: sessions))
        ]
        if let session = sessions.session ?? snapshot.session {
            sections.append(sessionSection(ClawJSRuntimeLensSessionDescriptorPresentation.make(session: session)))
        }
        if let actions = sessions.actionPolicy, !actions.isEmpty {
            sections.append(sessionActionsSection(ClawJSRuntimeLensSessionActionPresentation.make(actions: actions)))
        }
        if let contracts = sessions.actionContracts, !contracts.isEmpty {
            sections.append(sessionActionContractsSection(ClawJSRuntimeLensSessionActionContractPresentation.make(contracts: contracts, materializedPolicy: sessions.actionPolicy ?? [])))
        }
        if let overlay = sessions.overlayState {
            sections.append(sessionOverlaySection(ClawJSRuntimeLensSessionOverlayPresentation.make(state: overlay)))
        }
        return sections
    }

    private static func commandSections(commands: ClawJSRuntimeLensSnapshot.CommandMatrix?) -> [Section] {
        guard let commands, !(commands.executableByClawCli ?? []).isEmpty else { return [] }
        return [commandSection(ClawJSRuntimeLensCommandMatrixPresentation.make(commands: commands))]
    }

    private static func missingDomainSections(domains: [ClawJSRuntimeLensSnapshot.Domain]) -> [Section] {
        let missing = ClawJSRuntimeLensMissingDomainPresentation.make(domains: domains)
        guard missing.hasMissingDomains else { return [] }
        return [missingDomainSection(missing)]
    }

    private static func supportContractSections(snapshot: ClawJSRuntimeLensSnapshot) -> [Section] {
        let contracts = ClawJSRuntimeLensSupportContractPresentation.make(snapshot: snapshot)
        guard contracts.contractDomainCount > 0 else { return [] }
        return [supportContractSection(contracts)]
    }

    private static func inventorySections(snapshot: ClawJSRuntimeLensSnapshot) -> [Section] {
        let inventory = ClawJSRuntimeLensInventoryPresentation.make(snapshot: snapshot)
        guard inventory.hasInventory else { return [] }
        return [inventorySection(inventory)]
    }

    private static func viewStateSection(_ presentation: ClawJSRuntimeLensViewStatePresentation) -> Section {
        Section(
            id: "view-state",
            title: "Runtime lens state",
            rows: presentation.rows.map {
                Row(
                    id: $0.id,
                    label: $0.kind,
                    value: $0.message,
                    pills: [$0.severity == "warning" ? Pill(id: "warning", label: "warning", tone: .warning) : Pill(id: "state", label: $0.kind, tone: .info)],
                    detailLines: [],
                    accessibilityLabel: $0.accessibilityLabel
                )
            },
            accessibilityLabel: presentation.accessibilityLabel
        )
    }

    private static func runtimeSection(_ presentation: ClawJSRuntimeLensRuntimeSummaryPresentation) -> Section {
        Section(
            id: "runtime",
            title: "Runtime",
            rows: [
                Row(
                    id: "runtime",
                    label: "Runtime",
                    value: presentation.runtimeName,
                    pills: [
                        Pill(id: "installed", label: presentation.installedLabel, tone: presentation.installed ? .success : .warning),
                        Pill(id: "cli", label: presentation.cliLabel, tone: presentation.cliAvailable ? .success : .warning),
                        Pill(id: "gateway", label: presentation.gatewayLabel, tone: presentation.gatewayAvailable ? .success : .warning)
                    ] + optionalPills([
                        presentation.adapter.map { Pill(id: "adapter", label: $0, tone: .muted) },
                        presentation.version.map { Pill(id: "version", label: "v\($0)", tone: .muted) }
                    ]),
                    detailLines: optionalLines([
                        presentation.workspaceFilesLabel,
                        presentation.runtimeResourcesLabel,
                        presentation.capabilityStatusLabel,
                        presentation.lastError
                    ]),
                    accessibilityLabel: presentation.accessibilityLabel
                )
            ],
            accessibilityLabel: presentation.accessibilityLabel
        )
    }

    private static func supportSection(_ presentation: ClawJSRuntimeLensSupportOverviewPresentation) -> Section {
        Section(
            id: "support",
            title: "Support",
            rows: [
                Row(
                    id: "support",
                    label: "Support",
                    value: presentation.summary,
                    pills: optionalPills([
                        presentation.adapterSupportLevel.map { Pill(id: "adapter", label: "adapter \($0)", tone: $0 == "production" ? .success : .info) },
                        presentation.ecosystemSupportStage.map { Pill(id: "ecosystem", label: "ecosystem \($0)", tone: ClawJSRuntimeLensStatusTone.ecosystemStage($0)) },
                        presentation.notPromoted ? Pill(id: "not-promoted", label: "not promoted", tone: .warning) : nil
                    ]),
                    detailLines: optionalLines([
                        presentation.blockingReasonsLabel,
                        presentation.sourceLabel,
                        presentation.officialSnapshotLabel.map { "Official snapshot: \($0)" },
                        presentation.officialSnapshotDriftPolicy.map { "Drift policy: \($0)" }
                    ]),
                    accessibilityLabel: presentation.accessibilityLabel
                )
            ],
            accessibilityLabel: presentation.accessibilityLabel
        )
    }

    private static func supportAuditSection(_ presentation: ClawJSRuntimeLensSupportAuditPresentation) -> Section {
        Section(
            id: "support-audit",
            title: "Support audit",
            rows: [
                Row(
                    id: "closure",
                    label: "Closure",
                    value: presentation.promotionGate,
                    pills: [
                        Pill(id: "closure", label: presentation.closureState, tone: presentation.supportComplete ? .success : .warning),
                        Pill(id: "coverage", label: presentation.domainCoverageLabel, tone: presentation.allDomainsAccountedFor ? .info : .warning),
                        Pill(id: "evidence", label: "evidence \(presentation.evidenceRequirementCount)", tone: presentation.evidenceRequirementCount == 0 ? .success : .warning)
                    ],
                    detailLines: optionalLines([
                        presentation.blockerClassLabel,
                        presentation.directBlockerDomainsLabel,
                        presentation.externalPendingDomainsLabel,
                        presentation.blockedWriteBackDomainsLabel,
                        presentation.ecosystemExternalPendingDomainsLabel,
                        presentation.provenanceLabel
                    ]),
                    accessibilityLabel: presentation.accessibilityLabel
                )
            ],
            accessibilityLabel: presentation.accessibilityLabel
        )
    }

    private static func syncSummarySection(_ presentation: ClawJSRuntimeLensSupportSummaryPresentation.SyncPolicySummary) -> Section {
        Section(
            id: "sync-policy",
            title: "Sync policy",
            rows: [
                Row(
                    id: "sync",
                    label: "Sync policy",
                    value: presentation.defaultSyncMode,
                    pills: [
                        Pill(id: "domains", label: "sync domains \(presentation.domainCount)", tone: .info),
                        Pill(id: "read-only", label: "read-only \(presentation.readOnlyDomainCount)", tone: .info),
                        Pill(id: "overlay", label: "local overlay \(presentation.localOverlayDomainCount)", tone: presentation.localOverlayDomainCount > 0 ? .warning : .muted)
                    ],
                    detailLines: optionalLines([
                        presentation.blockedWriteBackLabel,
                        presentation.canonicalAuthorityLabel,
                        presentation.writeBackPolicyLabel,
                        presentation.persistenceLabel,
                        presentation.relationLabel,
                        presentation.lossPolicyLabel,
                        presentation.freshnessLabel,
                        presentation.safeDefault
                    ]),
                    accessibilityLabel: presentation.accessibilityLabel
                )
            ],
            accessibilityLabel: presentation.accessibilityLabel
        )
    }

    private static func supportAuditDomainsSection(_ presentation: ClawJSRuntimeLensSupportAuditDomainPresentation) -> Section {
        Section(
            id: "support-audit-domains",
            title: "Support audit domains",
            rows: [
                Row(id: "summary", label: "Support audit domains", value: presentation.totalLabel, pills: [
                    Pill(id: "domains", label: "domains \(presentation.domainCount)", tone: .info),
                    Pill(id: "evidence", label: "evidence \(presentation.evidenceDomainCount)", tone: presentation.evidenceDomainCount > 0 ? .warning : .success),
                    Pill(id: "blockers", label: "blockers \(presentation.blockerDomainCount)", tone: presentation.blockerDomainCount > 0 ? .warning : .muted)
                ], detailLines: [], accessibilityLabel: presentation.accessibilityLabel)
            ] + presentation.rows.map {
                Row(
                    id: $0.domain,
                    label: $0.domain,
                    value: $0.status,
                    pills: optionalPills([
                        $0.claim.map { Pill(id: "claim", label: $0, tone: ClawJSRuntimeLensStatusTone.supportClaim($0)) },
                        Pill(id: "write", label: $0.writeBackAllowed ? "write-back" : "no write-back", tone: $0.writeBackAllowed ? .success : .warning),
                        $0.externalPending ? Pill(id: "external", label: "external", tone: .warning) : nil
                    ]),
                    detailLines: optionalLines([
                        $0.readProjectionStatus.map { "read projection \($0)" },
                        $0.authorityLabel.map { "authority \($0)" },
                        $0.policyLabel.map { "policy \($0)" },
                        $0.relationshipLabel.map { "relationship \($0)" },
                        $0.approvalGateFixtureStatus.map { "approval gate fixture \($0)" },
                        $0.implementedFacetsLabel.map { "implemented facets \($0)" },
                        $0.blockingFacetsLabel.map { "blocking facets \($0)" },
                        $0.blockerClassesLabel.map { "blocker classes \($0)" },
                        $0.evidenceDispositionsLabel.map { "evidence dispositions \($0)" },
                        $0.evidenceRequirementIdsLabel.map { "evidence \($0)" },
                        $0.supportResolutionsLabel.map { "support resolutions \($0)" }
                    ]),
                    accessibilityLabel: $0.accessibilityLabel
                )
            },
            accessibilityLabel: presentation.accessibilityLabel
        )
    }

    private static func projectionSummarySection(_ presentation: ClawJSRuntimeLensSupportSummaryPresentation.ProjectionSummary) -> Section {
        Section(
            id: "projection",
            title: "Projection",
            rows: [
                Row(
                    id: "projection",
                    label: "Projection",
                    value: presentation.readStatusLabel,
                    pills: [
                        Pill(id: "projected", label: "read projected \(presentation.projectedDomainCount)", tone: presentation.projectedDomainCount > 0 ? .info : .warning),
                        Pill(id: "unsupported", label: "unsupported \(presentation.unsupportedDomainCount)", tone: presentation.unsupportedDomainCount > 0 ? .warning : .muted),
                        Pill(id: "blocked", label: "blocked+read \(presentation.productBlockedButProjectedDomainCount)", tone: presentation.productBlockedButProjectedDomainCount > 0 ? .warning : .muted)
                    ],
                    detailLines: optionalLines([
                        presentation.implementedFacetLabel,
                        presentation.blockingFacetLabel
                    ]),
                    accessibilityLabel: presentation.accessibilityLabel
                )
            ],
            accessibilityLabel: presentation.accessibilityLabel
        )
    }

    private static func evidenceReadinessSummarySection(_ presentation: ClawJSRuntimeLensSupportSummaryPresentation.EvidenceReadinessSummary) -> Section {
        Section(
            id: "evidence-readiness",
            title: "Evidence readiness",
            rows: [
                Row(
                    id: "evidence-readiness",
                    label: "Evidence readiness",
                    value: presentation.nextRequiredActionsLabel,
                    pills: [
                        Pill(id: "requirements", label: "requirements \(presentation.totalRequirementCount)", tone: presentation.totalRequirementCount == 0 ? .success : .warning),
                        Pill(id: "approval", label: "approval \(presentation.approvalRequiredCount)", tone: presentation.approvalRequiredCount > 0 ? .warning : .muted),
                        Pill(id: "upstream", label: "upstream \(presentation.upstreamContractBlockedCount)", tone: presentation.upstreamContractBlockedCount > 0 ? .warning : .muted),
                        Pill(id: "approval-gate", label: "approval gate \(presentation.approvalGateBlockedCount)", tone: presentation.approvalGateBlockedCount > 0 ? .warning : .muted),
                        Pill(id: "tui-gateway", label: "tui gateway \(presentation.tuiGatewayBlockedCount)", tone: presentation.tuiGatewayBlockedCount > 0 ? .warning : .muted),
                        Pill(id: "tui-wrapper", label: "wrapper \(presentation.tuiGatewayWrapperBlockedCount)", tone: presentation.tuiGatewayWrapperBlockedCount > 0 ? .warning : .muted),
                        Pill(id: "tui-fixture", label: "fixture \(presentation.tuiGatewayFixtureBackedCount)", tone: presentation.tuiGatewayFixtureBackedCount > 0 ? .success : .muted),
                        Pill(id: "transport", label: "transport \(presentation.productionTransportBlockedCount)", tone: presentation.productionTransportBlockedCount > 0 ? .warning : .muted),
                        Pill(id: "write-back", label: "write back \(presentation.writeBackContractBlockedCount)", tone: presentation.writeBackContractBlockedCount > 0 ? .warning : .muted)
                    ],
                    detailLines: optionalLines([
                        presentation.blockerClassLabel,
                        presentation.safeDefaultLabel,
                        presentation.approvalRequiredIdsLabel,
                        presentation.externalPendingIdsLabel,
                        presentation.upstreamContractIdsLabel,
                        presentation.approvalGateIdsLabel,
                        presentation.tuiGatewayIdsLabel,
                        presentation.tuiGatewayWrapperIdsLabel,
                        presentation.tuiGatewayFixtureBackedIdsLabel,
                        presentation.productionTransportIdsLabel,
                        presentation.writeBackContractIdsLabel,
                        presentation.productBlockedIdsLabel,
                        presentation.unresolvedNativeIdsLabel,
                        presentation.safeDefault
                    ]),
                    accessibilityLabel: presentation.accessibilityLabel
                )
            ],
            accessibilityLabel: presentation.accessibilityLabel
        )
    }

    private static func evidenceRequirementsSection(_ presentation: ClawJSRuntimeLensEvidenceRequirementPresentation) -> Section {
        Section(
            id: "evidence-requirements",
            title: "Evidence requirements",
            rows: [
                Row(id: "summary", label: "Evidence requirements", value: presentation.blockerClassLabel, pills: [
                    Pill(id: "total", label: "requirements \(presentation.totalRequirementCount)", tone: presentation.totalRequirementCount > 0 ? .warning : .success),
                    Pill(id: "approval", label: "approval \(presentation.approvalRequiredCount)", tone: presentation.approvalRequiredCount > 0 ? .warning : .muted),
                    Pill(id: "direct", label: "direct \(presentation.directBlockerCount)", tone: presentation.directBlockerCount > 0 ? .warning : .muted),
                    Pill(id: "external", label: "external \(presentation.externalPendingCount)", tone: presentation.externalPendingCount > 0 ? .warning : .muted)
                ], detailLines: [], accessibilityLabel: presentation.accessibilityLabel)
            ] + presentation.rows.map {
                Row(
                    id: $0.id,
                    label: $0.id,
                    value: $0.detailLabel,
                    pills: optionalPills([
                        $0.blockerClass.map { Pill(id: "blocker", label: $0, tone: .warning) },
                        $0.approvalRequired ? Pill(id: "approval", label: "approval", tone: .warning) : nil,
                        $0.expectedEvidenceCount > 0 ? Pill(id: "expected", label: "expected \($0.expectedEvidenceCount)", tone: .info) : nil,
                        $0.riskControlCount > 0 ? Pill(id: "risk", label: "risk \($0.riskControlCount)", tone: .muted) : nil
                    ]),
                    detailLines: $0.detailLines,
                    accessibilityLabel: $0.accessibilityLabel
                )
            },
            accessibilityLabel: presentation.accessibilityLabel
        )
    }

    private static func closureSection(_ presentation: ClawJSRuntimeLensClosureChecklistPresentation) -> Section {
        Section(
            id: "closure-checklist",
            title: "Closure checklist",
            rows: [
                Row(id: "summary", label: "Closure checklist", value: presentation.totalLabel, pills: presentation.statusPills.map { Pill(id: $0.status, label: $0.label, tone: ClawJSRuntimeLensStatusTone.closureStatus($0.status)) }, detailLines: [], accessibilityLabel: presentation.accessibilityLabel)
            ] + presentation.rows.map {
                Row(
                    id: $0.domain,
                    label: $0.domain,
                    value: $0.claim,
                    pills: [Pill(id: "status", label: $0.closureStatus, tone: ClawJSRuntimeLensStatusTone.closureStatus($0.closureStatus))],
                    detailLines: optionalLines([
                        $0.projectionDisposition,
                        $0.runtimeStatus,
                        $0.writeBackPolicy,
                        $0.validation,
                        $0.blockerClassesLabel,
                        $0.evidenceRequirementIdsLabel,
                        $0.implementedFacetsLabel.map { "implemented facets \($0)" },
                        $0.blockingFacetsLabel.map { "blocking facets \($0)" },
                        $0.supportResolutionsLabel,
                        $0.safeDefault,
                        $0.nextAction
                    ]),
                    accessibilityLabel: $0.accessibilityLabel
                )
            },
            accessibilityLabel: presentation.accessibilityLabel
        )
    }

    private static func promotionReviewSection(_ presentation: ClawJSRuntimeLensSupportDecisionPresentation.PromotionReview) -> Section {
        Section(
            id: "final-promotion-review",
            title: "Final promotion review",
            rows: [
                Row(
                    id: "final-promotion-review",
                    label: "Final promotion review",
                    value: presentation.requiredForPromotionLabel,
                    pills: [
                        Pill(id: "status", label: presentation.status, tone: presentation.finalPromotionAllowed ? .success : .warning),
                        Pill(id: "claim", label: presentation.claimDisposition, tone: presentation.finalPromotionAllowed ? .success : .warning)
                    ] + optionalPills([
                        presentation.commandCoverageLabel.map { Pill(id: "commands", label: "commands \($0)", tone: .info) },
                        presentation.commandCoveragePromotionSignal == false ? Pill(id: "command-promotion", label: "no command promotion", tone: .muted) : nil
                    ]),
                    detailLines: optionalLines([
                        presentation.commandCoverageSafeDefault,
                        presentation.productBlockedIdsLabel,
                        presentation.externalPendingIdsLabel,
                        presentation.unresolvedNativeIdsLabel,
                        presentation.userVisibleStatus
                    ]),
                    accessibilityLabel: presentation.accessibilityLabel
                )
            ],
            accessibilityLabel: presentation.accessibilityLabel
        )
    }

    private static func finalDecisionSection(_ presentation: ClawJSRuntimeLensSupportDecisionPresentation.FinalDecision) -> Section {
        Section(
            id: "final-support-claim-decision",
            title: "Final support claim",
            rows: [
                Row(
                    id: "final-support-claim-decision",
                    label: "Final support claim",
                    value: presentation.decision,
                    pills: [
                        Pill(id: "status", label: presentation.status, tone: presentation.status == "promoted" ? .success : .warning),
                        Pill(id: "claim", label: "claim \(presentation.effectiveSupportStage)", tone: ClawJSRuntimeLensStatusTone.supportClaim(presentation.effectiveSupportStage)),
                        Pill(id: "disposition", label: presentation.claimDisposition, tone: presentation.claimDisposition == "all_claims_supported_by_current_evidence" ? .success : .warning)
                    ] + optionalPills([
                        presentation.commandCoverageLabel.map { Pill(id: "commands", label: "commands \($0)", tone: .info) },
                        presentation.commandCoveragePromotionSignal == false ? Pill(id: "command-promotion", label: "no command promotion", tone: .muted) : nil
                    ]),
                    detailLines: optionalLines([
                        presentation.commandCoverageSafeDefault,
                        presentation.uiParityClaim,
                        presentation.claimDisposition,
                        presentation.blockedPromotionClaimsLabel,
                        presentation.blockerClassesLabel,
                        presentation.productBlockedIdsLabel,
                        presentation.externalPendingIdsLabel,
                        presentation.unresolvedNativeIdsLabel,
                        presentation.promotionEvidenceRequiredLabel,
                        presentation.reentryPolicy,
                        presentation.safeDefault
                    ]),
                    accessibilityLabel: presentation.accessibilityLabel
                )
            ],
            accessibilityLabel: presentation.accessibilityLabel
        )
    }

    private static func reentrySection(_ presentation: ClawJSRuntimeLensEvidenceReentryPresentation) -> Section {
        Section(
            id: "evidence-reentry",
            title: "Evidence reentry",
            rows: [
                Row(id: "summary", label: "Evidence reentry", value: presentation.totalLabel, pills: presentation.statusPills.map { Pill(id: $0.status, label: $0.label, tone: ClawJSRuntimeLensStatusTone.evidenceReentryStatus($0.status)) }, detailLines: [], accessibilityLabel: presentation.accessibilityLabel)
            ] + presentation.rows.map {
                Row(id: $0.requirementId, label: $0.requirementId, value: $0.exactCommand ?? $0.commandShape, pills: $0.approvalRequired ? [Pill(id: "approval", label: "approval", tone: .warning)] : [], detailLines: optionalLines([$0.commandShape, $0.preflightCommand, $0.approvalScope, $0.evidenceSafetyPolicy, $0.safeDefault, $0.reentryCondition, $0.expectedEvidenceLabel, $0.expectedRedactedEvidenceLabel, $0.riskControlsLabel, $0.claimEffect, $0.claimBlockedUntil, $0.supportResolution, $0.productDecision, $0.userVisibleContract, $0.officialMethod, $0.officialTransportSurface.map { "official transport \($0)" }, $0.officialTransportClassesLabel.map { "official transport classes \($0)" }, $0.officialTransportSource.map { "official transport source \($0)" }, $0.productionTransportStatus, $0.productionTransportBlocker.map { "production blocker \($0)" }, $0.productionTransportCommandShape]), accessibilityLabel: $0.accessibilityLabel)
            },
            accessibilityLabel: presentation.accessibilityLabel
        )
    }

    private static func sessionInventorySection(_ presentation: ClawJSRuntimeLensSessionInventoryPresentation) -> Section {
        Section(
            id: "session-inventory",
            title: "Session inventory",
            rows: [
                Row(id: "session-inventory", label: "Session inventory", value: presentation.detailLabel, pills: [
                    Pill(id: "status", label: presentation.statusLabel, tone: presentation.hasInventoryError ? .warning : .success),
                    Pill(id: "projected", label: "projected \(presentation.projectedCount)", tone: .info),
                    Pill(id: "visible", label: "visible \(presentation.visibleCount)", tone: .muted)
                ], detailLines: [], accessibilityLabel: presentation.accessibilityLabel)
            ],
            accessibilityLabel: presentation.accessibilityLabel
        )
    }

    private static func sessionSection(_ presentation: ClawJSRuntimeLensSessionDescriptorPresentation) -> Section {
        Section(
            id: "session",
            title: "Session",
            rows: [
                Row(id: "session", label: "Session", value: presentation.sessionPath, pills: presentation.transportPills.map { Pill(id: $0, label: $0, tone: $0 == presentation.streamingLabel ? .success : .info) }, detailLines: optionalLines([presentation.fallbackTransport]) + presentation.storageDetailLines, accessibilityLabel: presentation.accessibilityLabel)
            ],
            accessibilityLabel: presentation.accessibilityLabel
        )
    }

    private static func sessionActionsSection(_ presentation: ClawJSRuntimeLensSessionActionPresentation) -> Section {
        Section(id: "session-actions", title: "Session actions", rows: presentation.rows.map {
            Row(id: $0.id, label: $0.action, value: $0.detailLabel, pills: optionalPills([
                $0.status.map { Pill(id: "status", label: $0, tone: ClawJSRuntimeLensStatusTone.sessionActionStatus($0)) },
                Pill(id: "write", label: $0.writeDisposition, tone: ClawJSRuntimeLensStatusTone.sessionActionDisposition($0.writeDisposition)),
                $0.requiredEvidenceCount > 0 ? Pill(id: "evidence", label: "evidence \($0.requiredEvidenceCount)", tone: .warning) : nil
            ]), detailLines: sessionActionDetailLines($0), accessibilityLabel: $0.accessibilityLabel)
        }, accessibilityLabel: presentation.accessibilityLabel)
    }

    private static func sessionActionDetailLines(_ row: ClawJSRuntimeLensSessionActionPresentation.Row) -> [String] {
        optionalLines([
            row.officialTransportSurface.map { "official transport \($0)" },
            row.productionTransportBlocker.map { "production blocker \($0)" },
            row.requiredEvidenceLabel,
            row.userVisibleContract.map { "user visible contract \($0)" },
            row.claimEffect.map { "claim effect \($0)" }
        ])
    }

    private static func sessionActionContractsSection(_ presentation: ClawJSRuntimeLensSessionActionContractPresentation) -> Section {
        Section(id: "session-action-contracts", title: "Action contract", rows: [
            Row(id: "summary", label: "Action contract", value: presentation.statusChangedActionsLabel, pills: [
                Pill(id: "contracts", label: "contracts \(presentation.contractCount)", tone: .info),
                Pill(id: "materialized", label: "materialized \(presentation.materializedCount)", tone: .info)
            ], detailLines: [], accessibilityLabel: presentation.accessibilityLabel)
        ] + presentation.rows.map {
            Row(id: $0.id, label: $0.action, value: $0.detailLabel, pills: optionalPills([
                $0.contractStatus.map { Pill(id: "contract", label: "contract \($0)", tone: ClawJSRuntimeLensStatusTone.sessionActionStatus($0)) },
                $0.materializedStatus.map { Pill(id: "materialized", label: "now \($0)", tone: ClawJSRuntimeLensStatusTone.sessionActionStatus($0)) },
                Pill(id: "write", label: $0.materializedWriteDisposition, tone: ClawJSRuntimeLensStatusTone.sessionActionDisposition($0.materializedWriteDisposition))
            ]), detailLines: sessionActionContractDetailLines($0), accessibilityLabel: $0.accessibilityLabel)
        }, accessibilityLabel: presentation.accessibilityLabel)
    }

    private static func sessionActionContractDetailLines(_ row: ClawJSRuntimeLensSessionActionContractPresentation.Row) -> [String] {
        optionalLines([
            row.authority,
            row.delegatesTo,
            row.guardName.map { "guard \($0)" },
            row.officialProtocol.map { "official protocol \($0)" },
            row.officialMethod.map { "official method \($0)" },
            row.officialContractSource.map { "official contract source \($0)" },
            row.transportPolicyId.map { "transport policy \($0)" },
            row.officialTransportSurface.map { "official transport \($0)" },
            row.productionTransportBlocker.map { "production blocker \($0)" },
            row.productionTransportStatus.map { "production transport \($0)" },
            row.lifecycleStatus.map { "lifecycle \($0)" },
            row.nativeWriteBackStatus.map { "native write-back \($0)" },
            row.nativeWriteBackSafeDefault.map { "safe default \($0)" },
            row.evidenceRequirementId.map { "evidence \($0)" },
            row.userVisibleContract.map { "user visible contract \($0)" },
            row.claimEffect.map { "claim effect \($0)" },
            row.requiredEvidenceCount > 0 ? "evidence \(row.requiredEvidenceCount)" : nil,
            row.statusChanged ? "materialized status differs" : nil
        ])
    }

    private static func sessionOverlaySection(_ presentation: ClawJSRuntimeLensSessionOverlayPresentation) -> Section {
        Section(id: "session-overlays", title: "Overlays", rows: [
            Row(id: "summary", label: "Overlays", value: presentation.detailLabel, pills: [
                Pill(id: "total", label: "\(presentation.totalOverlays)", tone: .info),
                Pill(id: "write", label: presentation.writesRuntime ? "writes runtime" : "no write", tone: presentation.writesRuntime ? .warning : .muted)
            ], detailLines: presentation.detailLines + optionalLines([
                presentation.conflictStatusLabel.map { "conflict statuses \($0)" }
            ]), accessibilityLabel: presentation.accessibilityLabel)
        ] + presentation.rows.map {
            Row(id: $0.id, label: $0.sessionLabel, value: nil, pills: optionalPills([$0.conflictStatus.map { Pill(id: "conflict", label: $0, tone: ClawJSRuntimeLensStatusTone.overlayConflictStatus($0)) }]), detailLines: $0.detailLines, accessibilityLabel: $0.accessibilityLabel)
        }, accessibilityLabel: presentation.accessibilityLabel)
    }

    private static func commandSection(_ presentation: ClawJSRuntimeLensCommandMatrixPresentation) -> Section {
        Section(id: "commands", title: "Commands", rows: [
            Row(id: "summary", label: "Commands", value: presentation.mutationPolicy, pills: [
                Pill(id: "count", label: "\(presentation.executableCount)", tone: .info)
            ] + optionalPills([presentation.authority.map { Pill(id: "authority", label: $0, tone: .muted) }]), detailLines: [], accessibilityLabel: presentation.accessibilityLabel)
        ] + presentation.rows.map {
            Row(id: $0.id, label: $0.command, value: $0.argsLabel, pills: [
                Pill(id: "write", label: $0.writeDisposition, tone: ClawJSRuntimeLensStatusTone.commandDisposition($0.writeDisposition))
            ] + ($0.argumentCount > 0 ? [Pill(id: "args", label: "args \($0.argumentCount)", tone: .muted)] : []), detailLines: commandDetailLines($0), accessibilityLabel: $0.accessibilityLabel)
        }, accessibilityLabel: presentation.accessibilityLabel)
    }

    private static func commandDetailLines(_ row: ClawJSRuntimeLensCommandMatrixPresentation.Row) -> [String] {
        optionalLines([
            row.delegatesTo,
            row.blockerClass.map { "blocker \($0)" },
            row.nativeWriteBackStatus.map { "native write-back \($0)" },
            row.nativeWriteBackBlockerClass.map { "native blocker \($0)" },
            row.nativeWriteBackFixtureRequired.map { "fixture required \($0)" },
            row.nativeWriteBackSafeDefault.map { "native safe default \($0)" },
            row.safeDefault.map { "safe default \($0)" },
            row.userVisibleContract.map { "user visible contract \($0)" },
            row.claimEffect.map { "claim effect \($0)" },
            row.supportResolution.map { "support resolution \($0)" },
            row.evidenceRequirementId.map { "evidence \($0)" },
            row.requiredEvidenceLabel.map { "required evidence \($0)" },
            row.transportPolicyId.map { "transport policy \($0)" },
            row.officialTransportSurface.map { "official transport \($0)" },
            row.productionTransportBlocker.map { "production blocker \($0)" },
            row.productionTransportStatus.map { "production transport \($0)" },
            row.lifecycleStatus.map { "lifecycle \($0)" },
            row.productionTransportCommandShape.map { "production command \($0)" },
            row.doNotRunWithoutApproval ? "do not run without approval" : nil,
            row.claimBlockedUntil.map { "claim blocked until \($0)" },
            row.requiredEndpoint.map { "required endpoint \($0)" },
            row.configuredEndpointClass.map { "endpoint class \($0)" }
        ])
    }

    private static func missingDomainSection(_ presentation: ClawJSRuntimeLensMissingDomainPresentation) -> Section {
        Section(id: "missing-domains", title: "Missing domains", rows: presentation.rows.map {
            Row(id: $0.id, label: $0.displayLabel, value: $0.domain, pills: [Pill(id: "missing", label: "missing", tone: .warning)], detailLines: [], accessibilityLabel: $0.accessibilityLabel)
        }, accessibilityLabel: presentation.accessibilityLabel)
    }

    private static func domainSection(_ presentation: ClawJSRuntimeLensDomainPresentation) -> Section {
        Section(id: "domains", title: "Domains", rows: presentation.rows.map {
            Row(id: $0.id, label: $0.displayLabel, value: $0.detailLabel, pills: optionalPills([
                Pill(id: "status", label: $0.status, tone: ClawJSRuntimeLensStatusTone.runtimeDomainStatus(status: $0.status, supported: $0.supported)),
                $0.claim.map { Pill(id: "claim", label: $0, tone: ClawJSRuntimeLensStatusTone.supportClaim($0)) },
                $0.strategy.map { Pill(id: "strategy", label: $0, tone: .muted) },
                $0.count.map { Pill(id: "count", label: "\($0)", tone: .muted) }
            ]), detailLines: optionalLines([
                $0.policyLabel,
                $0.officialCommandsLabel.map { "official commands \($0)" },
                $0.evidenceRequirementsLabel.map { "evidence \($0)" },
                $0.limitationsLabel,
                $0.provenanceLabel
            ]), accessibilityLabel: $0.accessibilityLabel)
        }, accessibilityLabel: presentation.accessibilityLabel)
    }

    private static func supportContractSection(_ presentation: ClawJSRuntimeLensSupportContractPresentation) -> Section {
        Section(id: "support-contracts", title: "Support contracts", rows: [
            Row(id: "summary", label: "Support contracts", value: presentation.validationLabel, pills: [
                Pill(id: "contracts", label: "contracts \(presentation.contractDomainCount)", tone: .info),
                Pill(id: "blocked", label: "blocked \(presentation.blockedWriteBackCount)", tone: presentation.blockedWriteBackCount > 0 ? .warning : .success)
            ], detailLines: [], accessibilityLabel: presentation.accessibilityLabel)
        ] + presentation.rows.map {
            Row(id: $0.id, label: $0.displayLabel, value: $0.policyLabel, pills: optionalPills([
                $0.writeBackPolicy.map { Pill(id: "write", label: $0, tone: .warning) },
                $0.validation.map { Pill(id: "validation", label: $0, tone: .muted) }
            ]), detailLines: optionalLines([
                $0.provenanceLabel,
                $0.relationshipLabel,
                $0.authorityLabel,
                $0.officialCommandsLabel.map { "official commands \($0)" },
                $0.evidenceRequirementsLabel.map { "evidence \($0)" },
                $0.approvalGateFixtureLabel
            ]), accessibilityLabel: $0.accessibilityLabel)
        }, accessibilityLabel: presentation.accessibilityLabel)
    }

    private static func inventorySection(_ presentation: ClawJSRuntimeLensInventoryPresentation) -> Section {
        let domainRows = presentation.sections.map {
            Row(id: $0.id, label: $0.displayLabel, value: $0.statusLabel, pills: [
                Pill(id: "resources", label: "\($0.totalResourceCount)", tone: .info)
            ], detailLines: [], accessibilityLabel: $0.accessibilityLabel)
        }
        let resourceRows = presentation.sections.flatMap { section in
            section.rows.map { row in
                Row(
                    id: "\(section.id)::\(row.id)",
                    label: "\(section.displayLabel): \(row.displayLabel)",
                    value: row.statusLabel ?? row.kind,
                    pills: optionalPills([
                        row.statusLabel.map {
                            Pill(id: "status", label: $0, tone: ClawJSRuntimeLensStatusTone.runtimeDomainStatus(status: $0, supported: true))
                        },
                        row.kind.map { Pill(id: "kind", label: $0, tone: .muted) }
                    ]),
                    detailLines: inventoryResourceDetailLines(row),
                    accessibilityLabel: row.accessibilityLabel
                )
            }
        }

        return Section(id: "inventory", title: "Inventory", rows: [
            Row(id: "summary", label: "Inventory", value: presentation.domainLabel, pills: [
                Pill(id: "domains", label: "domains \(presentation.sectionCount)", tone: .info),
                Pill(id: "resources", label: "resources \(presentation.visibleResourceCount)", tone: .info)
            ], detailLines: [], accessibilityLabel: presentation.accessibilityLabel)
        ] + domainRows + resourceRows, accessibilityLabel: presentation.accessibilityLabel)
    }

    private static func inventoryResourceDetailLines(_ row: ClawJSRuntimeLensInventoryPresentation.Row) -> [String] {
        optionalLines([
            row.path.map { "path \($0)" },
            row.summaryLabel.map { "summary \($0)" },
            row.enabledLabel,
            row.sizeLabel.map { "size \($0)" },
            row.nativeIdentifierLabel,
            row.provenanceLabel.map { "provenance \($0)" },
            row.limitationsLabel.map { "limitations \($0)" },
            row.attributesLabel.map { "attributes \($0)" }
        ])
    }

    private static func optionalPills(_ values: [Pill?]) -> [Pill] {
        values.compactMap { $0 }
    }

    private static func optionalLines(_ values: [String?]) -> [String] {
        values.compactMap { value in
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty
            else {
                return nil
            }
            return value
        }
    }
}
