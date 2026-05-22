import SwiftUI

extension ClawJSRuntimeLensSection {
    func runtimeLensSummary(_ snapshot: ClawJSRuntimeLensSnapshot) -> some View {
        let presentation = ClawJSRuntimeLensRuntimeSummaryPresentation.make(snapshot: snapshot)
        let capabilityPageKey = ClawJSRuntimeLensPageKey("runtime-capabilities-\(snapshot.runtimeId)")
        let capabilitySlice = page(presentation.capabilityRows, key: capabilityPageKey)
        let locationPageKey = ClawJSRuntimeLensPageKey("runtime-locations-\(snapshot.runtimeId)")
        let locationSlice = page(presentation.locationRows, key: locationPageKey)

        return VStack(alignment: .leading, spacing: 10) {
            row(label: "Runtime") {
                HStack(spacing: 8) {
                    Text(presentation.runtimeName)
                        .font(BodyFont.system(size: 12.5, weight: .medium))
                        .foregroundColor(Palette.textPrimary)
                    if let adapter = presentation.adapter {
                        statusPill(text: adapter, color: Color.white.opacity(0.35))
                    }
                    if let version = presentation.version {
                        statusPill(text: "v\(version)", color: Color.white.opacity(0.35))
                    }
                    statusPill(
                        text: presentation.installedLabel,
                        color: presentation.installed ? .green : .orange
                    )
                    Spacer()
                }
            }
            if let support = snapshot.support {
                Divider().background(Color.white.opacity(0.07))
                runtimeLensSupport(support)
            }
            if let supportAudit = snapshot.supportAudit {
                Divider().background(Color.white.opacity(0.07))
                runtimeLensSupportAudit(supportAudit)
            }
            Divider().background(Color.white.opacity(0.07))
            row(label: "CLI") {
                statusPill(
                    text: presentation.cliLabel,
                    color: presentation.cliAvailable ? .green : .orange
                )
            }
            Divider().background(Color.white.opacity(0.07))
            row(label: "Gateway") {
                statusPill(
                    text: presentation.gatewayLabel,
                    color: presentation.gatewayAvailable ? .green : .orange
                )
            }
            if presentation.workspaceCanonicalPathCount > 0 || presentation.workspaceManagedFileCount > 0 {
                Divider().background(Color.white.opacity(0.07))
                row(label: "Workspace files") {
                    HStack(spacing: 8) {
                        if presentation.workspaceCanonicalPathCount > 0 {
                            statusPill(text: "canonical \(presentation.workspaceCanonicalPathCount)", color: .blue)
                        }
                        if presentation.workspaceManagedFileCount > 0 {
                            statusPill(text: "managed \(presentation.workspaceManagedFileCount)", color: Color.white.opacity(0.35))
                        }
                        Spacer()
                    }
                }
                if let files = presentation.workspaceFilesLabel {
                    Text(files)
                        .font(BodyFont.system(size: 10.5))
                        .foregroundColor(Palette.textSecondary.opacity(0.72))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            if presentation.runtimeResourceCount > 0 {
                Divider().background(Color.white.opacity(0.07))
                row(label: "Runtime resources") {
                    HStack(spacing: 8) {
                        statusPill(text: "\(presentation.runtimeResourceCount)", color: .blue)
                        statusPill(
                            text: "groups \(presentation.runtimeResourceAggregateDomainCount)",
                            color: Color.white.opacity(0.35)
                        )
                        Spacer()
                    }
                }
                if let resources = presentation.runtimeResourcesLabel {
                    Text(resources)
                        .font(BodyFont.system(size: 10.5))
                        .foregroundColor(Palette.textSecondary.opacity(0.72))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            if presentation.capabilityCount > 0 || presentation.rawCapabilityCount > 0 {
                Divider().background(Color.white.opacity(0.07))
                row(label: "Capabilities") {
                    HStack(spacing: 8) {
                        if presentation.capabilityCount > 0 {
                            statusPill(text: "\(presentation.capabilityCount)", color: .blue)
                        }
                        if presentation.rawCapabilityCount > 0 {
                            statusPill(
                                text: "enabled \(presentation.rawCapabilityEnabledCount)/\(presentation.rawCapabilityCount)",
                                color: Color.white.opacity(0.35)
                            )
                        }
                        if presentation.degradedCapabilityCount > 0 {
                            statusPill(text: "degraded \(presentation.degradedCapabilityCount)", color: .orange)
                        }
                        if presentation.errorCapabilityCount > 0 {
                            statusPill(text: "error \(presentation.errorCapabilityCount)", color: .red)
                        }
                        if presentation.unsupportedCapabilityCount > 0 {
                            statusPill(text: "unsupported \(presentation.unsupportedCapabilityCount)", color: .orange)
                        }
                        Spacer()
                    }
                }
                ForEach(capabilitySlice.rows) { capability in
                    row(label: capability.label) {
                        HStack(spacing: 8) {
                            statusPill(
                                text: capability.status,
                                color: runtimeLensColor(ClawJSRuntimeLensStatusTone.resourceStatus(capability.status))
                            )
                            if let strategy = capability.strategy {
                                statusPill(text: strategy, color: Color.white.opacity(0.28))
                            }
                            if let limitations = capability.limitationsLabel {
                                Text(limitations)
                                    .font(BodyFont.system(size: 10.5))
                                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                        }
                    }
                    .accessibilityIdentifier("runtime-lens-runtime-capability-\(capability.id)")
                    .accessibilityLabel(Text(capability.accessibilityLabel))
                }
                pager(capabilitySlice, key: capabilityPageKey)
            }
            if !presentation.locationRows.isEmpty {
                Divider().background(Color.white.opacity(0.07))
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(locationSlice.rows) { location in
                        row(label: location.label) {
                            Text(location.value)
                                .font(BodyFont.system(size: 11.5))
                                .foregroundColor(Palette.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .accessibilityIdentifier("runtime-lens-runtime-location-\(location.id)")
                        .accessibilityLabel(Text(location.accessibilityLabel))
                    }
                    pager(locationSlice, key: locationPageKey)
                }
            }
            if let error = presentation.lastError {
                Divider().background(Color.white.opacity(0.07))
                Text(error)
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("runtime-lens-runtime-summary")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    func runtimeLensSupportAudit(_ audit: ClawJSRuntimeLensSnapshot.SupportAudit) -> some View {
        let presentation = ClawJSRuntimeLensSupportAuditPresentation.make(audit: audit)

        return VStack(alignment: .leading, spacing: 6) {
            row(label: "Closure") {
                HStack(spacing: 8) {
                    statusPill(
                        text: presentation.closureState,
                        color: presentation.supportComplete ? .green : .orange
                    )
                    if presentation.allDomainsAccountedFor {
                        statusPill(text: "all domains", color: .blue)
                    } else {
                        statusPill(text: "coverage gap", color: .orange)
                    }
                    statusPill(
                        text: "evidence \(presentation.evidenceRequirementCount)",
                        color: presentation.evidenceRequirementCount == 0 ? .green : .orange
                    )
                    Spacer()
                }
            }
            HStack(spacing: 8) {
                if presentation.directBlockerCount > 0 {
                    statusPill(text: "direct \(presentation.directBlockerCount)", color: .red)
                }
                if presentation.externalPendingCount > 0 {
                    statusPill(text: "external \(presentation.externalPendingCount)", color: .orange)
                }
                if presentation.productBlockedRequirementCount > 0 {
                    statusPill(text: "product \(presentation.productBlockedRequirementCount)", color: .orange)
                }
                if let stage = presentation.supportStage {
                    statusPill(text: stage, color: runtimeEcosystemStageColor(stage))
                }
                Spacer()
            }
            if let blockerClasses = presentation.blockerClassLabel {
                Text("Blocker classes: \(blockerClasses)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let directDomains = presentation.directBlockerDomainsLabel {
                Text("Direct blockers: \(directDomains)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(.orange)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let externalDomains = presentation.externalPendingDomainsLabel {
                Text("External evidence: \(externalDomains)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(.orange)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let blockedWriteBackDomains = presentation.blockedWriteBackDomainsLabel {
                Text("Blocked write-back: \(blockedWriteBackDomains)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(.orange)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let ecosystemExternalDomains = presentation.ecosystemExternalPendingDomainsLabel {
                Text("Ecosystem external: \(ecosystemExternalDomains)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let gate = presentation.promotionGate {
                Text(gate)
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.78))
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            if let provenance = presentation.provenanceLabel {
                Text("Audit source: \(provenance)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let syncSummary = audit.syncPolicySummary {
                runtimeLensSyncPolicySummary(syncSummary)
            }
            if let projectionSummary = audit.projectionSummary {
                runtimeLensProjectionSummary(projectionSummary)
            }
            if let readinessSummary = audit.evidenceReadinessSummary {
                runtimeLensEvidenceReadinessSummary(readinessSummary)
            }
            if let checklist = audit.closureChecklist, !checklist.isEmpty {
                runtimeLensClosureChecklist(checklist, summary: audit.closureChecklistSummary)
            }
            if let review = audit.finalPromotionReview {
                runtimeLensFinalPromotionReview(review)
            }
            if let decision = audit.finalSupportClaimDecision {
                runtimeLensFinalSupportClaimDecision(decision)
            }
            if let packets = audit.evidenceReentryPackets, !packets.isEmpty {
                runtimeLensEvidenceReentryPackets(packets)
            }
        }
        .accessibilityIdentifier("runtime-lens-support-audit")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    func runtimeLensProjectionSummary(
        _ summary: ClawJSRuntimeLensSnapshot.SupportAudit.ProjectionSummary
    ) -> some View {
        let presentation = ClawJSRuntimeLensSupportSummaryPresentation.make(projection: summary)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                statusPill(
                    text: "read projected \(presentation.projectedDomainCount)",
                    color: presentation.projectedDomainCount > 0 ? .blue : .orange
                )
                if presentation.unsupportedDomainCount > 0 {
                    statusPill(text: "unsupported \(presentation.unsupportedDomainCount)", color: .orange)
                }
                if presentation.productBlockedButProjectedDomainCount > 0 {
                    statusPill(text: "blocked+read \(presentation.productBlockedButProjectedDomainCount)", color: .orange)
                }
                Spacer()
            }
            if let readStatusLabel = presentation.readStatusLabel {
                Text(readStatusLabel)
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let implementedFacets = presentation.implementedFacetLabel {
                Text("Implemented: \(implementedFacets)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let blockingFacets = presentation.blockingFacetLabel {
                Text("Blocked: \(blockingFacets)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(.orange)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .accessibilityIdentifier("runtime-lens-projection-summary")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    func runtimeLensSyncPolicySummary(
        _ summary: ClawJSRuntimeLensSnapshot.SupportAudit.SyncPolicySummary
    ) -> some View {
        let presentation = ClawJSRuntimeLensSupportSummaryPresentation.make(sync: summary)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                statusPill(text: "sync domains \(presentation.domainCount)", color: .blue)
                if presentation.readOnlyDomainCount > 0 {
                    statusPill(text: "read-only \(presentation.readOnlyDomainCount)", color: .blue)
                }
                if presentation.localOverlayDomainCount > 0 {
                    statusPill(text: "local overlay \(presentation.localOverlayDomainCount)", color: .orange)
                }
                if presentation.writeBackAllowedDomainCount > 0 {
                    statusPill(text: "write-back \(presentation.writeBackAllowedDomainCount)", color: .orange)
                }
                Spacer()
            }
            if let mode = presentation.defaultSyncMode {
                Text(mode)
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.78))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let blocked = presentation.blockedWriteBackLabel {
                Text("Blocked write-back: \(blocked)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(.orange)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let canonicalAuthority = presentation.canonicalAuthorityLabel {
                Text("Canonical authority: \(canonicalAuthority)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let writeBackPolicy = presentation.writeBackPolicyLabel {
                Text("Write-back policy: \(writeBackPolicy)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let persistence = presentation.persistenceLabel {
                Text("Persistence: \(persistence)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let relation = presentation.relationLabel {
                Text("Relation: \(relation)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let lossPolicy = presentation.lossPolicyLabel {
                Text("Loss policy: \(lossPolicy)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let freshness = presentation.freshnessLabel {
                Text("Freshness: \(freshness)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let safeDefault = presentation.safeDefault {
                Text(safeDefault)
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .accessibilityIdentifier("runtime-lens-sync-policy-summary")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    func runtimeLensEvidenceReadinessSummary(
        _ summary: ClawJSRuntimeLensSnapshot.SupportAudit.EvidenceReadinessSummary
    ) -> some View {
        let presentation = ClawJSRuntimeLensSupportSummaryPresentation.make(evidenceReadiness: summary)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                statusPill(
                    text: "requirements \(presentation.totalRequirementCount)",
                    color: presentation.totalRequirementCount == 0 ? .green : .orange
                )
                if presentation.approvalRequiredCount > 0 {
                    statusPill(text: "approval \(presentation.approvalRequiredCount)", color: .orange)
                }
                if presentation.upstreamContractBlockedCount > 0 {
                    statusPill(text: "upstream \(presentation.upstreamContractBlockedCount)", color: .orange)
                }
                if presentation.unresolvedNativeRequirementCount > 0 {
                    statusPill(text: "unresolved \(presentation.unresolvedNativeRequirementCount)", color: .red)
                }
                Spacer()
            }
            if let actions = presentation.nextRequiredActionsLabel {
                Text("Next: \(actions)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.78))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let blockerClasses = presentation.blockerClassLabel {
                Text("Blockers: \(blockerClasses)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let safeDefaults = presentation.safeDefaultLabel {
                Text("Safe defaults: \(safeDefaults)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let approvalIds = presentation.approvalRequiredIdsLabel {
                Text("Approval ids: \(approvalIds)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let externalIds = presentation.externalPendingIdsLabel {
                Text("External ids: \(externalIds)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let upstreamIds = presentation.upstreamContractIdsLabel {
                Text("Upstream ids: \(upstreamIds)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let productIds = presentation.productBlockedIdsLabel {
                Text("Product ids: \(productIds)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let unresolvedIds = presentation.unresolvedNativeIdsLabel {
                Text("Unresolved ids: \(unresolvedIds)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let safeDefault = presentation.safeDefault {
                Text(safeDefault)
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .accessibilityIdentifier("runtime-lens-evidence-readiness-summary")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    func runtimeLensClosureChecklist(
        _ checklist: [ClawJSRuntimeLensSnapshot.SupportAudit.ClosureChecklistItem],
        summary: [String: Int]?
    ) -> some View {
        let presentation = ClawJSRuntimeLensClosureChecklistPresentation.make(
            checklist: checklist,
            summary: summary
        )
        let pageKey = ClawJSRuntimeLensPageKey("closure-checklist")
        let slice = page(presentation.rows, key: pageKey)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                statusPill(text: presentation.totalLabel, color: .blue)
                ForEach(presentation.statusPills) { pill in
                    statusPill(text: pill.label, color: runtimeLensClosureStatusColor(pill.status))
                }
                Spacer()
            }
            ForEach(slice.rows) { item in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.domain)
                            .font(BodyFont.system(size: 10.5, weight: .medium))
                            .foregroundColor(Palette.textPrimary)
                        statusPill(text: item.closureStatus, color: runtimeLensClosureStatusColor(item.closureStatus))
                        if let readProjectionStatus = item.readProjectionStatus {
                            statusPill(text: "read \(readProjectionStatus)", color: .blue)
                        }
                        if item.evidenceCount > 0 {
                            statusPill(text: "evidence \(item.evidenceCount)", color: .orange)
                        }
                        if item.blockingFacetCount > 0 {
                            statusPill(text: "blocked \(item.blockingFacetCount)", color: .red)
                        }
                        Spacer()
                    }
                    if let projectionDisposition = item.projectionDisposition {
                        Text(projectionDisposition)
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let claim = item.claim {
                        Text("Claim: \(claim)")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let runtimeStatus = item.runtimeStatus {
                        Text("Runtime status: \(runtimeStatus)")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let writeBackPolicy = item.writeBackPolicy {
                        Text("Write-back: \(writeBackPolicy)")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let validation = item.validation {
                        Text("Validation: \(validation)")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let blockerClasses = item.blockerClassesLabel {
                        Text("Blockers: \(blockerClasses)")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let evidenceIds = item.evidenceRequirementIdsLabel {
                        Text("Evidence ids: \(evidenceIds)")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let supportResolutions = item.supportResolutionsLabel {
                        Text("Resolution: \(supportResolutions)")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let safeDefault = item.safeDefault {
                        Text(safeDefault)
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let next = item.nextAction {
                        Text(next)
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .accessibilityIdentifier("runtime-lens-closure-checklist-row-\(item.domain)")
                .accessibilityLabel(Text(item.accessibilityLabel))
            }
            pager(slice, key: pageKey)
        }
        .accessibilityIdentifier("runtime-lens-closure-checklist")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    func runtimeLensClosureStatusColor(_ status: String) -> Color {
        runtimeLensColor(ClawJSRuntimeLensStatusTone.closureStatus(status))
    }

    func runtimeLensFinalPromotionReview(
        _ review: ClawJSRuntimeLensSnapshot.SupportAudit.FinalPromotionReview
    ) -> some View {
        let presentation = ClawJSRuntimeLensSupportDecisionPresentation.make(review: review)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                statusPill(text: presentation.status, color: presentation.finalPromotionAllowed ? .green : .orange)
                statusPill(
                    text: presentation.claimDisposition,
                    color: presentation.claimDisposition == "all_claims_supported_by_current_evidence" ? .green : .orange
                )
                Spacer()
            }
            HStack(spacing: 8) {
                if presentation.productBlockedCount > 0 {
                    statusPill(text: "product-blocked \(presentation.productBlockedCount)", color: .orange)
                }
                if presentation.externalPendingCount > 0 {
                    statusPill(text: "external \(presentation.externalPendingCount)", color: .orange)
                }
                if presentation.unresolvedNativeRequirementCount > 0 {
                    statusPill(text: "unresolved \(presentation.unresolvedNativeRequirementCount)", color: .red)
                }
                Spacer()
            }
            if let required = presentation.requiredForPromotionLabel, !required.isEmpty {
                Text("Promotion needs: \(required)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.78))
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            if let productIds = presentation.productBlockedIdsLabel {
                Text("Product ids: \(productIds)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let externalIds = presentation.externalPendingIdsLabel {
                Text("External ids: \(externalIds)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let unresolvedIds = presentation.unresolvedNativeIdsLabel {
                Text("Unresolved ids: \(unresolvedIds)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let status = presentation.userVisibleStatus {
                Text(status)
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .accessibilityIdentifier("runtime-lens-final-promotion-review")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    func runtimeLensFinalSupportClaimDecision(
        _ decision: ClawJSRuntimeLensSnapshot.SupportAudit.FinalSupportClaimDecision
    ) -> some View {
        let presentation = ClawJSRuntimeLensSupportDecisionPresentation.make(decision: decision)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                statusPill(text: presentation.status, color: presentation.status == "promoted" ? .green : .orange)
                statusPill(text: "claim \(presentation.effectiveSupportStage)", color: claimColor(presentation.effectiveSupportStage))
                if let parity = presentation.uiParityDisposition {
                    statusPill(text: parity, color: parity == "ui_parity_promoted" ? .green : .orange)
                }
                Spacer()
            }
            if let decision = presentation.decision {
                Text("Decision: \(decision)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.78))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let claim = presentation.uiParityClaim {
                Text("UI parity claim: \(claim)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text("Recommended: \(presentation.recommended ? "yes" : "no") · Production: \(presentation.production ? "yes" : "no")")
                .font(BodyFont.system(size: 10.5))
                .foregroundColor(Palette.textSecondary.opacity(0.72))
                .lineLimit(1)
                .truncationMode(.middle)
            if let blocked = presentation.blockedPromotionClaimsLabel {
                Text("Blocked claims: \(blocked)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(.orange)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let classes = presentation.blockerClassesLabel {
                Text("Blocker classes: \(classes)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let productIds = presentation.productBlockedIdsLabel {
                Text("Product ids: \(productIds)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let externalIds = presentation.externalPendingIdsLabel {
                Text("External ids: \(externalIds)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let unresolvedIds = presentation.unresolvedNativeIdsLabel {
                Text("Unresolved ids: \(unresolvedIds)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let evidence = presentation.promotionEvidenceRequiredLabel {
                Text("Evidence: \(evidence)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            if let policy = presentation.reentryPolicy {
                Text(policy)
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.78))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let safeDefault = presentation.safeDefault {
                Text(safeDefault)
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .accessibilityIdentifier("runtime-lens-final-support-claim-decision")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    func runtimeLensEvidenceReentryPackets(
        _ packets: [ClawJSRuntimeLensSnapshot.SupportAudit.EvidenceReentryPacket]
    ) -> some View {
        let presentation = ClawJSRuntimeLensEvidenceReentryPresentation.make(packets: packets)
        let pageKey = ClawJSRuntimeLensPageKey("evidence-reentry-packets")
        let slice = page(presentation.rows, key: pageKey)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                statusPill(text: presentation.totalLabel, color: .orange)
                ForEach(presentation.statusPills) { pill in
                    statusPill(text: pill.label, color: runtimeLensEvidenceReentryStatusColor(pill.status))
                }
                Spacer()
            }
            ForEach(slice.rows) { row in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(row.requirementId)
                            .font(BodyFont.system(size: 10.5, weight: .medium))
                            .foregroundColor(Palette.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if row.approvalRequired {
                            statusPill(text: "approval", color: .orange)
                        }
                        Spacer()
                    }
                    if let command = row.commandShape {
                        Text(command)
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.78))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let safeDefault = row.safeDefault {
                        Text(safeDefault)
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let condition = row.reentryCondition {
                        Text(condition)
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let evidence = row.expectedEvidenceLabel {
                        Text("Evidence: \(evidence)")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let controls = row.riskControlsLabel {
                        Text("Risk controls: \(controls)")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let effect = row.claimEffect {
                        Text("Claim: \(effect)")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let resolution = row.supportResolution {
                        Text("Resolution: \(resolution)")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let decision = row.productDecision {
                        Text("Product: \(decision)")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let contract = row.userVisibleContract {
                        Text("Contract: \(contract)")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.72))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .accessibilityIdentifier("runtime-lens-evidence-reentry-row-\(row.requirementId)")
                .accessibilityLabel(Text(row.accessibilityLabel))
            }
            pager(slice, key: pageKey)
        }
        .accessibilityIdentifier("runtime-lens-evidence-reentry-packets")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    func runtimeLensEvidenceReentryStatusColor(_ status: String) -> Color {
        runtimeLensColor(ClawJSRuntimeLensStatusTone.evidenceReentryStatus(status))
    }

    func runtimeLensSupport(_ support: ClawJSRuntimeLensSnapshot.Support) -> some View {
        let presentation = ClawJSRuntimeLensSupportOverviewPresentation.make(support: support)

        return VStack(alignment: .leading, spacing: 6) {
            row(label: "Support") {
                HStack(spacing: 8) {
                    if let adapterLevel = presentation.adapterSupportLevel {
                        statusPill(text: "adapter \(adapterLevel)", color: adapterLevel == "production" ? .green : .blue)
                    }
                    if let stage = presentation.ecosystemSupportStage {
                        statusPill(text: "ecosystem \(stage)", color: runtimeEcosystemStageColor(stage))
                    }
                    if presentation.notPromoted {
                        statusPill(text: "not promoted", color: .orange)
                    }
                    Spacer()
                }
            }
            if let summary = presentation.summary {
                Text(summary)
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let blockers = presentation.blockingReasonsLabel {
                Text("Blocked: \(blockers)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(.orange)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let source = presentation.sourceLabel {
                Text("Source: \(source)")
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let evidence = support.ecosystem?.evidenceRequirements, !evidence.isEmpty {
                runtimeLensEvidenceRequirements(evidence, limit: 3)
            }
        }
        .accessibilityIdentifier("runtime-lens-support-overview")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    func runtimeEcosystemStageColor(_ stage: String) -> Color {
        runtimeLensColor(ClawJSRuntimeLensStatusTone.ecosystemStage(stage))
    }

}
