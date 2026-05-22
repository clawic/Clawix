import AppKit
import SwiftUI

/// Settings page that surfaces the state of the ClawJS sidecar services.
/// The manager owns launch/probe state; this page renders every ready,
/// blocked, crashed, and daemon-owned service state directly.
struct ClawJSSettingsPage: View {

    @StateObject private var manager = ClawJSServiceManager.shared
    @State private var advancedExpanded = false
    @State private var databaseProbe: DatabaseProbeResult?
    @State private var databaseProbeInFlight = false
    @State private var manualServiceLeases: [ClawJSService: ServiceDemandLease] = [:]
    @State private var runtimeLensSelection: ClawJSRuntimeLensID = .openclaw
    @State private var runtimeLensSnapshots: [ClawJSRuntimeLensID: ClawJSRuntimeLensSnapshot] = [:]
    @State private var runtimeLensLoading = false
    @State private var runtimeLensError: String?
    @State private var runtimeLensActionError: String?
    @State private var runtimeLensSessionActionsInFlight: Set<String> = []

    private let runtimeLensClient = ClawJSRuntimeLensClient()

    private enum DatabaseProbeResult: Equatable {
        case success(service: String, host: String, port: Int)
        case failure(message: String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            bundleSection
                .padding(.top, 18)

            ClawJSRuntimeLensSection()
                .padding(.top, 18)

            ForEach(visibleClawJSServices) { service in
                serviceSection(for: service)
                    .padding(.top, 18)
            }

            advancedSection
                .padding(.top, 22)
                .padding(.bottom, 8)
        }
        .onDisappear {
            Task { await releaseManualServiceLeases() }
        }
        .task {
            await refreshRuntimeLens(runtimeLensSelection)
        }
        .onChange(of: runtimeLensSelection) { _, selectedRuntime in
            Task { await refreshRuntimeLens(selectedRuntime) }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ClawJS")
                .font(BodyFont.system(size: 22, weight: .semibold))
                .foregroundColor(Palette.textPrimary)
            Text("Sidecar services backing framework-owned storage, integrations, and domain APIs.")
                .font(BodyFont.system(size: 12.5))
                .foregroundColor(Palette.textSecondary)
        }
    }

    // MARK: - Bundle card

    private var bundleSection: some View {
        SectionCard(title: "Bundle") {
            VStack(alignment: .leading, spacing: 12) {
                row(label: "Pinned version") {
                    Text(ClawJSRuntime.expectedVersion)
                        .font(BodyFont.system(size: 12.5, weight: .medium))
                        .foregroundColor(Palette.textPrimary)
                }
                Divider().background(Color.white.opacity(0.07))
                row(label: "Bundle available") {
                    if BackgroundBridgeService.shared.isDaemonReachable && !ClawJSRuntime.isAvailable {
                        statusPill(text: "Not required in daemon mode", color: .blue)
                    } else if ClawJSRuntime.isAvailable {
                        statusPill(text: "Yes", color: .green)
                    } else {
                        statusPill(text: "Missing", color: .orange)
                    }
                }
            }
        }
    }

    // MARK: - Runtime lenses

    private var runtimeLensSection: some View {
        SectionCard(title: "Runtime lenses") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("", selection: $runtimeLensSelection) {
                    ForEach(ClawJSRuntimeLensID.allCases) { runtime in
                        Text(runtime.label).tag(runtime)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                let viewState = runtimeLensViewStatePresentation
                if viewState.hasRows {
                    runtimeLensViewState(viewState)
                }

                if let snapshot = runtimeLensSnapshots[runtimeLensSelection] {
                    runtimeLensSummary(snapshot)
                    if let sessions = snapshot.domainData?.sessions {
                        Divider().background(Color.white.opacity(0.07))
                        runtimeLensSessionInventory(sessions)
                    }
                    if let session = snapshot.domainData?.sessions?.session ?? snapshot.session {
                        Divider().background(Color.white.opacity(0.07))
                        runtimeLensSession(session)
                    }
                    if let actions = snapshot.domainData?.sessions?.actionPolicy, !actions.isEmpty {
                        Divider().background(Color.white.opacity(0.07))
                        runtimeLensSessionActions(actions)
                    }
                    if let contracts = snapshot.domainData?.sessions?.actionContracts, !contracts.isEmpty {
                        Divider().background(Color.white.opacity(0.07))
                        runtimeLensSessionActionContracts(
                            contracts,
                            materializedPolicy: snapshot.domainData?.sessions?.actionPolicy ?? []
                        )
                    }
                    if let commands = snapshot.commands, !(commands.executableByClawCli ?? []).isEmpty {
                        Divider().background(Color.white.opacity(0.07))
                        runtimeLensCommands(commands)
                    }
                    if let overlayState = snapshot.domainData?.sessions?.overlayState {
                        Divider().background(Color.white.opacity(0.07))
                        runtimeLensSessionOverlayState(overlayState)
                    }
                    if runtimeLensHasMissingDomains(snapshot) {
                        Divider().background(Color.white.opacity(0.07))
                        runtimeLensMissingDomains(snapshot)
                    }
                    Divider().background(Color.white.opacity(0.07))
                    runtimeLensDomains(snapshot)
                    if runtimeLensHasSupportContracts(snapshot) {
                        Divider().background(Color.white.opacity(0.07))
                        runtimeLensSupportContracts(snapshot)
                    }
                    if runtimeLensHasInventory(snapshot) {
                        Divider().background(Color.white.opacity(0.07))
                        runtimeLensInventory(snapshot)
                    }
                }

                HStack {
                    Button("Refresh") {
                        Task { await refreshRuntimeLens(runtimeLensSelection) }
                    }
                    .buttonStyle(.borderless)
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                    .disabled(runtimeLensLoading)
                    Spacer()
                }
            }
            .accessibilityIdentifier("runtime-lens-section-\(runtimeLensSelection.rawValue)")
            .accessibilityLabel(Text(runtimeLensValidationAccessibilityLabel))
        }
    }

    private var runtimeLensValidationAccessibilityLabel: String {
        if let snapshot = runtimeLensSnapshots[runtimeLensSelection] {
            return ClawJSRuntimeLensValidationSummary.make(snapshot: snapshot).accessibilityLabel
        }
        return runtimeLensViewStatePresentation.accessibilityLabel
    }

    private var runtimeLensViewStatePresentation: ClawJSRuntimeLensViewStatePresentation {
        ClawJSRuntimeLensViewStatePresentation.make(
            runtime: runtimeLensSelection,
            isRefreshing: runtimeLensLoading,
            loadError: runtimeLensError,
            actionError: runtimeLensActionError,
            hasSnapshot: runtimeLensSnapshots[runtimeLensSelection] != nil
        )
    }

    private func runtimeLensViewState(_ presentation: ClawJSRuntimeLensViewStatePresentation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(presentation.rows.prefix(100))) { row in
                HStack(spacing: 8) {
                    if row.kind == "refreshing" {
                        ProgressView().controlSize(.small)
                    }
                    Text(row.message)
                        .font(BodyFont.system(size: 11.5))
                        .foregroundColor(row.severity == "warning" ? .orange : Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .accessibilityIdentifier("runtime-lens-view-state-\(row.id)-\(presentation.runtimeId)")
                .accessibilityLabel(Text(row.accessibilityLabel))
            }
        }
        .accessibilityIdentifier("runtime-lens-view-state-\(presentation.runtimeId)")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    private func runtimeLensSessionInventory(
        _ sessions: ClawJSRuntimeLensSnapshot.DomainData.SessionBucket
    ) -> some View {
        let presentation = ClawJSRuntimeLensSessionInventoryPresentation.make(bucket: sessions)

        return VStack(alignment: .leading, spacing: 8) {
            row(label: "Session inventory") {
                HStack(spacing: 8) {
                    statusPill(text: presentation.statusLabel, color: presentation.hasInventoryError ? .orange : .green)
                    statusPill(text: "projected \(presentation.projectedCount)", color: .blue)
                    statusPill(text: "visible \(presentation.visibleCount)", color: Color.white.opacity(0.35))
                    Spacer()
                }
            }
            if let detail = presentation.detailLabel {
                Text(detail)
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.82))
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
        .accessibilityIdentifier("runtime-lens-session-inventory")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    private func runtimeLensSession(_ session: ClawJSRuntimeLensSnapshot.SessionDescriptor) -> some View {
        let presentation = ClawJSRuntimeLensSessionDescriptorPresentation.make(session: session)

        return VStack(alignment: .leading, spacing: 8) {
            row(label: "Session") {
                HStack(spacing: 8) {
                    ForEach(presentation.transportPills, id: \.self) { pill in
                        statusPill(
                            text: pill,
                            color: pill == presentation.streamingLabel ? .green : .blue
                        )
                    }
                }
            }
            if let fallback = presentation.fallbackTransport {
                Divider().background(Color.white.opacity(0.07))
                row(label: "Fallback") {
                    Text(fallback)
                        .font(BodyFont.system(size: 11.5))
                        .foregroundColor(Palette.textSecondary)
                }
            }
            if let path = presentation.sessionPath {
                Divider().background(Color.white.opacity(0.07))
                row(label: "Path") {
                    Text(path)
                        .font(BodyFont.system(size: 11.5))
                        .foregroundColor(Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .accessibilityIdentifier("runtime-lens-session-descriptor")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    private func runtimeLensSessionActions(_ actions: [ClawJSRuntimeLensSnapshot.SessionActionPolicy]) -> some View {
        let presentation = ClawJSRuntimeLensSessionActionPresentation.make(actions: actions)

        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(presentation.rows.prefix(100))) { action in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(action.action)
                            .font(BodyFont.system(size: 11.5, weight: .medium))
                            .foregroundColor(Palette.textPrimary)
                            .frame(width: 58, alignment: .leading)
                        if let status = action.status {
                            statusPill(text: status, color: sessionActionColor(status))
                        }
                        statusPill(text: action.writeDisposition, color: sessionActionDispositionColor(action.writeDisposition))
                        if action.requiredEvidenceCount > 0 {
                            statusPill(text: "evidence \(action.requiredEvidenceCount)", color: .orange)
                        }
                        Spacer()
                    }
                    if let detailLabel = action.detailLabel {
                        Text(detailLabel)
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.8))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let evidence = action.requiredEvidenceLabel {
                        Text("Evidence: \(evidence)")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.78))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .accessibilityLabel(Text(action.accessibilityLabel))
            }
        }
        .accessibilityIdentifier("runtime-lens-session-actions")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    private func runtimeLensSessionActionContracts(
        _ contracts: [ClawJSRuntimeLensSnapshot.SessionActionPolicy],
        materializedPolicy: [ClawJSRuntimeLensSnapshot.SessionActionPolicy]
    ) -> some View {
        let presentation = ClawJSRuntimeLensSessionActionContractPresentation.make(
            contracts: contracts,
            materializedPolicy: materializedPolicy
        )

        return VStack(alignment: .leading, spacing: 8) {
            row(label: "Action contract") {
                HStack(spacing: 8) {
                    statusPill(text: "contracts \(presentation.contractCount)", color: .blue)
                    statusPill(text: "materialized \(presentation.materializedCount)", color: .blue)
                    if presentation.statusChangedCount > 0 {
                        statusPill(text: "changed \(presentation.statusChangedCount)", color: .orange)
                    }
                    if presentation.wouldWriteRuntimeCount > 0 {
                        statusPill(text: "would write \(presentation.wouldWriteRuntimeCount)", color: .orange)
                    }
                    if presentation.localOverlayContractCount > 0 {
                        statusPill(text: "local \(presentation.localOverlayContractCount)", color: .blue)
                    }
                    Spacer()
                }
            }
            ForEach(Array(presentation.rows.prefix(100))) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(row.action)
                            .font(BodyFont.system(size: 11.5, weight: .medium))
                            .foregroundColor(Palette.textPrimary)
                            .frame(width: 58, alignment: .leading)
                        if let contractStatus = row.contractStatus {
                            statusPill(text: "contract \(contractStatus)", color: sessionActionColor(contractStatus))
                        }
                        if let materializedStatus = row.materializedStatus, row.statusChanged {
                            statusPill(text: "now \(materializedStatus)", color: sessionActionColor(materializedStatus))
                        }
                        statusPill(
                            text: row.materializedWriteDisposition,
                            color: sessionActionDispositionColor(row.materializedWriteDisposition)
                        )
                        Spacer()
                    }
                    if let detailLabel = row.detailLabel {
                        Text(detailLabel)
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.8))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .accessibilityIdentifier("runtime-lens-session-action-contract-\(row.id)")
                .accessibilityLabel(Text(row.accessibilityLabel))
            }
        }
        .accessibilityIdentifier("runtime-lens-session-action-contracts")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    private func runtimeLensCommands(_ commands: ClawJSRuntimeLensSnapshot.CommandMatrix) -> some View {
        let presentation = ClawJSRuntimeLensCommandMatrixPresentation.make(commands: commands)

        return VStack(alignment: .leading, spacing: 8) {
            row(label: "Commands") {
                HStack(spacing: 8) {
                    statusPill(text: "\(presentation.executableCount)", color: .blue)
                    if let authority = presentation.authority {
                        statusPill(text: authority, color: Color.white.opacity(0.35))
                    }
                    Spacer()
                }
            }
            if let mutationPolicy = presentation.mutationPolicy, !mutationPolicy.isEmpty {
                Text(mutationPolicy)
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(presentation.rows.prefix(100))) { command in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(command.command)
                            .font(BodyFont.system(size: 10.5, weight: .medium))
                            .foregroundColor(Palette.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        statusPill(text: command.writeDisposition, color: commandDispositionColor(command.writeDisposition))
                        if command.argumentCount > 0 {
                            statusPill(text: "args \(command.argumentCount)", color: Color.white.opacity(0.28))
                        }
                        Spacer()
                    }
                    if let args = command.argsLabel {
                        Text("Args: \(args)")
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.78))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let delegatesTo = command.delegatesTo {
                        Text(delegatesTo)
                            .font(BodyFont.system(size: 10.5))
                            .foregroundColor(Palette.textSecondary.opacity(0.78))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .accessibilityLabel(Text(command.accessibilityLabel))
            }
        }
        .accessibilityIdentifier("runtime-lens-command-matrix")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    private func commandDispositionColor(_ disposition: String) -> Color {
        runtimeLensColor(ClawJSRuntimeLensStatusTone.commandDisposition(disposition))
    }

    private func sessionActionColor(_ status: String) -> Color {
        runtimeLensColor(ClawJSRuntimeLensStatusTone.sessionActionStatus(status))
    }

    private func sessionActionDispositionColor(_ disposition: String) -> Color {
        runtimeLensColor(ClawJSRuntimeLensStatusTone.sessionActionDisposition(disposition))
    }

    private func runtimeLensSessionOverlayState(_ state: ClawJSRuntimeLensSnapshot.SessionOverlayState) -> some View {
        let presentation = ClawJSRuntimeLensSessionOverlayPresentation.make(state: state)

        return VStack(alignment: .leading, spacing: 8) {
            row(label: "Overlays") {
                HStack(spacing: 8) {
                    statusPill(text: "\(presentation.totalOverlays)", color: .blue)
                    if presentation.totalConflicts > 0 {
                        let conflicts = presentation.totalConflicts
                        statusPill(text: "\(conflicts) conflict", color: .orange)
                    }
                    if !presentation.writesRuntime {
                        statusPill(text: "no write", color: Color.white.opacity(0.35))
                    }
                    Spacer()
                }
            }
            if let detailLabel = presentation.detailLabel {
                Text(detailLabel)
                    .font(BodyFont.system(size: 10.5))
                    .foregroundColor(Palette.textSecondary.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            ForEach(Array(presentation.rows.prefix(100))) { overlay in
                HStack(spacing: 8) {
                    Text(overlay.sessionLabel)
                        .font(BodyFont.system(size: 10.5))
                        .foregroundColor(Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let conflictStatus = overlay.conflictStatus {
                        statusPill(text: conflictStatus, color: overlayConflictColor(conflictStatus))
                    }
                    Spacer()
                }
                .accessibilityLabel(Text(overlay.accessibilityLabel))
            }
        }
        .accessibilityIdentifier("runtime-lens-session-overlays")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    private func overlayConflictColor(_ status: String) -> Color {
        runtimeLensColor(ClawJSRuntimeLensStatusTone.overlayConflictStatus(status))
    }

    private func runtimeLensSummary(_ snapshot: ClawJSRuntimeLensSnapshot) -> some View {
        let presentation = ClawJSRuntimeLensRuntimeSummaryPresentation.make(snapshot: snapshot)

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
                ForEach(presentation.capabilityRows.prefix(8)) { capability in
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
            }
            if !presentation.locationRows.isEmpty {
                Divider().background(Color.white.opacity(0.07))
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(presentation.locationRows) { location in
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

    private func runtimeLensSupportAudit(_ audit: ClawJSRuntimeLensSnapshot.SupportAudit) -> some View {
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

    private func runtimeLensProjectionSummary(
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

    private func runtimeLensSyncPolicySummary(
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

    private func runtimeLensEvidenceReadinessSummary(
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

    private func runtimeLensClosureChecklist(
        _ checklist: [ClawJSRuntimeLensSnapshot.SupportAudit.ClosureChecklistItem],
        summary: [String: Int]?
    ) -> some View {
        let presentation = ClawJSRuntimeLensClosureChecklistPresentation.make(
            checklist: checklist,
            summary: summary
        )

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                statusPill(text: presentation.totalLabel, color: .blue)
                ForEach(presentation.statusPills) { pill in
                    statusPill(text: pill.label, color: runtimeLensClosureStatusColor(pill.status))
                }
                Spacer()
            }
            ForEach(Array(presentation.rows.prefix(100))) { item in
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
        }
        .accessibilityIdentifier("runtime-lens-closure-checklist")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    private func runtimeLensClosureStatusColor(_ status: String) -> Color {
        runtimeLensColor(ClawJSRuntimeLensStatusTone.closureStatus(status))
    }

    private func runtimeLensFinalPromotionReview(
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

    private func runtimeLensFinalSupportClaimDecision(
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

    private func runtimeLensEvidenceReentryPackets(
        _ packets: [ClawJSRuntimeLensSnapshot.SupportAudit.EvidenceReentryPacket]
    ) -> some View {
        let presentation = ClawJSRuntimeLensEvidenceReentryPresentation.make(packets: packets)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                statusPill(text: presentation.totalLabel, color: .orange)
                ForEach(presentation.statusPills) { pill in
                    statusPill(text: pill.label, color: runtimeLensEvidenceReentryStatusColor(pill.status))
                }
                Spacer()
            }
            ForEach(Array(presentation.rows.prefix(100))) { row in
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
        }
        .accessibilityIdentifier("runtime-lens-evidence-reentry-packets")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    private func runtimeLensEvidenceReentryStatusColor(_ status: String) -> Color {
        runtimeLensColor(ClawJSRuntimeLensStatusTone.evidenceReentryStatus(status))
    }

    private func runtimeLensSupport(_ support: ClawJSRuntimeLensSnapshot.Support) -> some View {
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

    private func runtimeEcosystemStageColor(_ stage: String) -> Color {
        runtimeLensColor(ClawJSRuntimeLensStatusTone.ecosystemStage(stage))
    }

    private func runtimeLensDomains(_ snapshot: ClawJSRuntimeLensSnapshot) -> some View {
        let presentation = ClawJSRuntimeLensDomainPresentation.make(domains: snapshot.domains)

        return VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(presentation.rows.prefix(100)), id: \.id) { domain in
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
        }
        .accessibilityIdentifier("runtime-lens-domains")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    private func runtimeLensEvidenceRequirements(
        _ requirements: [ClawJSRuntimeLensSnapshot.EvidenceRequirement],
        limit: Int
    ) -> some View {
        let presentation = ClawJSRuntimeLensEvidenceRequirementPresentation.make(
            requirements: requirements,
            limit: limit
        )

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                statusPill(text: "evidence \(presentation.totalRequirementCount)", color: .orange)
                ForEach(presentation.blockerClassLabel?.components(separatedBy: ", ") ?? [], id: \.self) { blockerLabel in
                    let blockerClass = blockerLabel.components(separatedBy: " ").first ?? blockerLabel
                    statusPill(text: blockerClass, color: evidenceBlockerColor(blockerClass))
                }
                Spacer()
            }
            ForEach(Array(presentation.rows.prefix(100))) { requirement in
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
        }
        .accessibilityIdentifier("runtime-lens-evidence-requirements")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    private func evidenceBlockerColor(_ blockerClass: String) -> Color {
        runtimeLensColor(ClawJSRuntimeLensStatusTone.evidenceBlockerClass(blockerClass))
    }

    private func runtimeLensDomainCommands(domain: String, commands: [String]) -> some View {
        let presentation = ClawJSRuntimeLensDomainCommandPresentation.make(
            domain: domain,
            commands: commands
        )

        return Group {
            if presentation.hasCommands {
                HStack(spacing: 6) {
                    ForEach(Array(presentation.rows.prefix(100))) { command in
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
                .accessibilityIdentifier("runtime-lens-domain-commands-\(domain)")
                .accessibilityLabel(Text(presentation.accessibilityLabel))
            }
        }
    }

    private func runtimeDomainColor(status: String, supported: Bool) -> Color {
        runtimeLensColor(ClawJSRuntimeLensStatusTone.runtimeDomainStatus(status: status, supported: supported))
    }

    private func claimColor(_ claim: String) -> Color {
        runtimeLensColor(ClawJSRuntimeLensStatusTone.supportClaim(claim))
    }

    private func runtimeLensHasMissingDomains(_ snapshot: ClawJSRuntimeLensSnapshot) -> Bool {
        ClawJSRuntimeLensMissingDomainPresentation.make(domains: snapshot.domains).hasMissingDomains
    }

    private func runtimeLensMissingDomains(_ snapshot: ClawJSRuntimeLensSnapshot) -> some View {
        let presentation = ClawJSRuntimeLensMissingDomainPresentation.make(domains: snapshot.domains)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                statusPill(text: "missing \(presentation.missingDomainCount)", color: .orange)
                statusPill(text: "present \(presentation.presentDomainCount)", color: .blue)
                Spacer()
            }
            ForEach(Array(presentation.rows.prefix(100))) { row in
                Text(row.displayLabel)
                    .font(BodyFont.system(size: 11.5, weight: .medium))
                    .foregroundColor(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(row.domain)
                    .accessibilityIdentifier("runtime-lens-missing-domain-\(row.domain)")
                    .accessibilityLabel(Text(row.accessibilityLabel))
            }
        }
        .accessibilityIdentifier("runtime-lens-missing-domains")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    private func runtimeLensHasSupportContracts(_ snapshot: ClawJSRuntimeLensSnapshot) -> Bool {
        ClawJSRuntimeLensSupportContractPresentation.make(snapshot: snapshot).hasContracts
    }

    private func runtimeLensSupportContracts(_ snapshot: ClawJSRuntimeLensSnapshot) -> some View {
        let presentation = ClawJSRuntimeLensSupportContractPresentation.make(snapshot: snapshot)

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
            ForEach(Array(presentation.rows.prefix(100)), id: \.id) { contract in
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
        }
        .accessibilityIdentifier("runtime-lens-support-contracts")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    private func runtimeLensHasInventory(_ snapshot: ClawJSRuntimeLensSnapshot) -> Bool {
        ClawJSRuntimeLensInventoryPresentation.make(snapshot: snapshot).hasInventory
    }

    private func runtimeLensInventory(_ snapshot: ClawJSRuntimeLensSnapshot) -> some View {
        let presentation = ClawJSRuntimeLensInventoryPresentation.make(snapshot: snapshot)

        return VStack(alignment: .leading, spacing: 10) {
            ForEach(presentation.sections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.displayLabel)
                        .font(BodyFont.system(size: 12, weight: .semibold))
                        .foregroundColor(Palette.textPrimary)
                    ForEach(Array(section.rows.prefix(100))) { row in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(row.displayLabel)
                                    .font(BodyFont.system(size: 11.5))
                                    .foregroundColor(Palette.textSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if let status = row.statusLabel {
                                    statusPill(text: status, color: resourceStatusColor(status))
                                }
                                if section.domain == "sessions" {
                                    runtimeSessionOverlayButton(snapshot: snapshot, resource: row.resource)
                                }
                                Spacer()
                            }
                            if let path = row.path {
                                Text(path)
                                    .font(BodyFont.system(size: 10.5))
                                    .foregroundColor(Palette.textSecondary.opacity(0.75))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            if let kind = row.kindLabel {
                                Text(kind)
                                    .font(BodyFont.system(size: 10.5))
                                    .foregroundColor(Palette.textSecondary.opacity(0.72))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            if let summary = row.summaryLabel {
                                Text(summary)
                                    .font(BodyFont.system(size: 10.5))
                                    .foregroundColor(Palette.textSecondary.opacity(0.7))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            if row.enabledLabel != nil || row.sizeLabel != nil {
                                HStack(spacing: 6) {
                                    if let enabled = row.enabledLabel {
                                        Text(enabled)
                                            .font(BodyFont.system(size: 10.5))
                                            .foregroundColor(Palette.textSecondary.opacity(0.68))
                                            .lineLimit(1)
                                    }
                                    if let size = row.sizeLabel {
                                        Text(size)
                                            .font(BodyFont.system(size: 10.5))
                                            .foregroundColor(Palette.textSecondary.opacity(0.68))
                                            .lineLimit(1)
                                    }
                                }
                            }
                            if let nativeIdentifier = row.nativeIdentifierLabel {
                                Text(nativeIdentifier)
                                    .font(BodyFont.system(size: 10.5))
                                    .foregroundColor(Palette.textSecondary.opacity(0.7))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            if let provenance = row.provenanceLabel {
                                Text(provenance)
                                    .font(BodyFont.system(size: 10.5))
                                    .foregroundColor(Palette.textSecondary.opacity(0.65))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            if let limitations = row.limitationsLabel {
                                Text("Limitations: \(limitations)")
                                    .font(BodyFont.system(size: 10.5))
                                    .foregroundColor(Palette.textSecondary.opacity(0.65))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            if let attributes = row.attributesLabel {
                                Text("Attributes: \(attributes)")
                                    .font(BodyFont.system(size: 10.5))
                                    .foregroundColor(Palette.textSecondary.opacity(0.65))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            if let updatedAt = row.updatedAt {
                                Text(updatedAt)
                                    .font(BodyFont.system(size: 10.5))
                                    .foregroundColor(Palette.textSecondary.opacity(0.65))
                                    .lineLimit(1)
                            }
                        }
                        .accessibilityIdentifier("runtime-lens-inventory-resource-\(section.domain)-\(row.id)")
                        .accessibilityLabel(Text(row.accessibilityLabel))
                    }
                }
                .accessibilityIdentifier("runtime-lens-inventory-domain-\(section.domain)")
                .accessibilityLabel(Text(section.accessibilityLabel))
            }
        }
        .accessibilityIdentifier("runtime-lens-inventory")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    private func runtimeSessionOverlayButton(
        snapshot: ClawJSRuntimeLensSnapshot,
        resource: ClawJSRuntimeLensSnapshot.RuntimeResource
    ) -> some View {
        let presentation = ClawJSRuntimeLensSessionOverlayActionPresentation.make(
            snapshot: snapshot,
            resource: resource,
            inFlightKeys: runtimeLensSessionActionsInFlight
        )
        return Button {
            Task {
                await setRuntimeSessionPinned(
                    snapshot: snapshot,
                    resource: resource,
                    pinned: presentation.targetPinned
                )
            }
        } label: {
            Image(systemName: presentation.systemImage)
                .font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.plain)
        .foregroundColor(presentation.currentPinned ? Palette.textPrimary : Palette.textSecondary)
        .help(presentation.helpText)
        .disabled(presentation.disabled)
        .accessibilityIdentifier(presentation.accessibilityIdentifier)
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    private func resourceStatusColor(_ status: String) -> Color {
        runtimeLensColor(ClawJSRuntimeLensStatusTone.resourceStatus(status))
    }

    private func runtimeLensColor(_ tone: ClawJSRuntimeLensStatusTone) -> Color {
        switch tone {
        case .success: return .green
        case .info: return .blue
        case .warning: return .orange
        case .danger: return .red
        case .muted: return Color.white.opacity(0.35)
        }
    }

    @MainActor
    private func setRuntimeSessionPinned(
        snapshot: ClawJSRuntimeLensSnapshot,
        resource: ClawJSRuntimeLensSnapshot.RuntimeResource,
        pinned: Bool
    ) async {
        guard let runtime = ClawJSRuntimeLensID(rawValue: snapshot.runtimeId) else { return }
        let key = ClawJSRuntimeLensSessionOverlayActionPresentation.actionKey(
            runtimeId: snapshot.runtimeId,
            sessionId: resource.id
        )
        runtimeLensActionError = nil
        runtimeLensSessionActionsInFlight.insert(key)
        defer { runtimeLensSessionActionsInFlight.remove(key) }
        do {
            let result = try await runtimeLensClient.setSessionPinned(
                runtime: runtime,
                sessionId: resource.id,
                pinned: pinned
            )
            guard result.writesRuntime == false else {
                runtimeLensActionError = "Runtime session overlay unexpectedly reported a runtime write."
                return
            }
            await refreshRuntimeLens(runtime)
        } catch {
            runtimeLensActionError = error.localizedDescription
        }
    }

    @MainActor
    private func refreshRuntimeLens(_ runtime: ClawJSRuntimeLensID) async {
        runtimeLensLoading = true
        runtimeLensError = nil
        defer { runtimeLensLoading = false }

        let plan = ClawJSRuntimeLensRefreshPlan.scoped(to: runtime)
        for target in plan.runtimes {
            do {
                runtimeLensSnapshots[target] = try await runtimeLensClient.load(runtime: target)
            } catch {
                if target == runtimeLensSelection {
                    runtimeLensError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Per-service card

    private func serviceSection(for service: ClawJSService) -> some View {
        let snapshot = manager.snapshots[service]
        let state = snapshot?.state ?? .idle
        return SectionCard(title: service.displayName) {
            VStack(alignment: .leading, spacing: 12) {
                row(label: "Status") {
                    statusPill(text: stateLabel(state), color: stateColor(state))
                }
                if case .blocked(let reason) = state {
                    blockedReason(reason)
                }
                if case .crashed(let reason) = state {
                    blockedReason(reason)
                }
                if case .daemonUnavailable(let reason) = state {
                    blockedReason(reason)
                }
                if case .availableOnDemand(let trigger) = state {
                    blockedReason("Available when \(trigger).")
                }
                Divider().background(Color.white.opacity(0.07))
                row(label: "Port") {
                    Text(verbatim: "127.0.0.1:\(service.port)")
                        .font(BodyFont.system(size: 12.5, weight: .medium))
                        .foregroundColor(Palette.textPrimary)
                        .monospacedDigit()
                }
                Divider().background(Color.white.opacity(0.07))
                HStack(spacing: 12) {
                    serviceActionButton(service: service, state: state)

                    Button("Open admin console") {
                        if let url = URL(string: "http://127.0.0.1:\(service.port)") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(state.isReady ? Palette.textPrimary : Palette.textSecondary)
                    .disabled(!state.isReady)

                    Button("Reveal log") {
                        let url = ClawJSServiceManager.logFileURL(for: service)
                        if FileManager.default.fileExists(atPath: url.path) {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                }

                if service == .database, state.isReady {
                    Divider().background(Color.white.opacity(0.07))
                    databaseProbeRow
                    Divider().background(Color.white.opacity(0.07))
                    DatabaseManagerStatusRow()
                }
            }
        }
    }

    /// Smoke-test row for the database service: hits `/v1/health`
    /// (unauthenticated) and renders the response or the error inline.
    @ViewBuilder
    private var databaseProbeRow: some View {
        HStack(spacing: 12) {
            Button("Probe /v1/health") {
                Task { await probeDatabase() }
            }
            .buttonStyle(.borderless)
            .font(BodyFont.system(size: 11.5, wght: 500))
            .foregroundColor(Palette.textPrimary)
            .disabled(databaseProbeInFlight)

            if databaseProbeInFlight {
                ProgressView().controlSize(.small)
            }
            Spacer()
        }
        if let result = databaseProbe {
            switch result {
            case .success(let service, let host, let port):
                Text("\(service) reports \(host):\(port)")
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(Palette.textSecondary)
            case .failure(let message):
                Text(message)
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func probeDatabase() async {
        databaseProbeInFlight = true
        defer { databaseProbeInFlight = false }
        do {
            let response = try await ClawJSDatabaseClient().probeHealth()
            databaseProbe = .success(
                service: response.service,
                host: response.host,
                port: response.port
            )
        } catch {
            databaseProbe = .failure(message: error.localizedDescription)
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        DisclosureGroup(isExpanded: $advancedExpanded) {
            SectionCard(title: "Advanced") {
                VStack(alignment: .leading, spacing: 12) {
                    row(label: "Workspace") {
                        Text(ClawJSServiceManager.workspaceURL.path)
                            .font(BodyFont.system(size: 11.5))
                            .foregroundColor(Palette.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Divider().background(Color.white.opacity(0.07))
                    ForEach(visibleClawJSServices) { service in
                        let state = manager.snapshots[service]?.state ?? .idle
                        HStack(spacing: 12) {
                            Text(service.displayName)
                                .font(BodyFont.system(size: 12.5))
                                .foregroundColor(Palette.textPrimary)
                                .frame(width: 90, alignment: .leading)
                            serviceActionButton(service: service, state: state)
                            Button("Status JSON") {
                                if let json = statusJSON(for: service) {
                                    let pasteboard = NSPasteboard.general
                                    pasteboard.clearContents()
                                    pasteboard.setString(json, forType: .string)
                                }
                            }
                            .buttonStyle(.borderless)
                            .font(BodyFont.system(size: 11.5, wght: 500))
                            .foregroundColor(Palette.textSecondary)
                            Spacer()
                        }
                    }
                }
            }
        } label: {
            Text("Advanced")
                .font(BodyFont.system(size: 12, wght: 600))
                .foregroundColor(Palette.textSecondary)
        }
    }

    private var visibleClawJSServices: [ClawJSService] {
        ClawJSServiceDemandPolicy.visibleServices(
            Set(ClawJSService.allCases),
            isVisible: FeatureFlags.shared.isVisible
        ).sorted { $0.displayName < $1.displayName }
    }

    private func serviceActionButton(service: ClawJSService, state: ClawJSServiceState) -> some View {
        Button(serviceActionTitle(service: service, state: state)) {
            Task {
                if let lease = manualServiceLeases[service] {
                    await manager.release(lease)
                    manualServiceLeases[service] = nil
                } else if state.isReady {
                    await manager.restart(service)
                } else {
                    let services = ClawJSServiceDemandPolicy.visibleServices(
                        [service],
                        isVisible: FeatureFlags.shared.isVisible
                    )
                    manualServiceLeases[service] = await manager.acquire(
                        services: services,
                        reason: .manual(service.displayName),
                        consumer: "settings.manual.\(service.rawValue)"
                    )
                }
            }
        }
        .buttonStyle(.borderless)
        .font(BodyFont.system(size: 11.5, wght: 500))
        .foregroundColor(Palette.textSecondary)
        .disabled(isServiceActionDisabled(service, state: state))
    }

    private func serviceActionTitle(service: ClawJSService, state: ClawJSServiceState) -> String {
        if manualServiceLeases[service] != nil { return "Stop" }
        return state.isReady ? "Restart" : "Start"
    }

    @MainActor
    private func releaseManualServiceLeases() async {
        let leases = manualServiceLeases
        manualServiceLeases.removeAll()
        for lease in leases.values {
            await manager.release(lease)
        }
    }

    private func isServiceActionDisabled(_ service: ClawJSService, state: ClawJSServiceState) -> Bool {
        guard ClawJSServiceDemandPolicy.isServiceVisible(service, isVisible: FeatureFlags.shared.isVisible) else {
            return true
        }
        if case .starting = state { return true }
        return false
    }

    // MARK: - Row + pill helpers

    private func row<Trailing: View>(
        label: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack {
            Text(label)
                .font(BodyFont.system(size: 12.5))
                .foregroundColor(Palette.textSecondary)
            Spacer()
            trailing()
        }
    }

    private func statusPill(text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(BodyFont.system(size: 11.5, wght: 500))
                .foregroundColor(Palette.textPrimary)
        }
    }

    private func blockedReason(_ reason: String) -> some View {
        Text(reason)
            .font(BodyFont.system(size: 11.5))
            .foregroundColor(Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func stateLabel(_ state: ClawJSServiceState) -> String {
        switch state {
        case .idle:                return "Idle"
        case .availableOnDemand:   return "Available on demand"
        case .blocked:             return "Blocked"
        case .starting:            return "Starting"
        case .ready:               return "Running"
        case .readyFromDaemon:     return "Running from daemon"
        case .crashed:             return "Crashed"
        case .daemonUnavailable:   return "Unavailable from daemon"
        }
    }

    private func stateColor(_ state: ClawJSServiceState) -> Color {
        switch state {
        case .idle:                return Color.white.opacity(0.4)
        case .availableOnDemand:   return .blue
        case .blocked:             return .orange
        case .starting:            return .yellow
        case .ready:               return .green
        case .readyFromDaemon:     return .green
        case .crashed:             return .red
        case .daemonUnavailable:   return .red
        }
    }

    private func statusJSON(for service: ClawJSService) -> String? {
        guard let snapshot = manager.snapshots[service] else { return nil }
        var dict: [String: Any] = [
            "service": service.rawValue,
            "port": Int(service.port),
            "restartCount": snapshot.restartCount,
        ]
        switch snapshot.state {
        case .idle:                dict["state"] = "idle"
        case .availableOnDemand(let trigger):
            dict["state"] = "availableOnDemand"
            dict["trigger"] = trigger
        case .blocked(let reason):
            dict["state"] = "blocked"
            dict["reason"] = reason
        case .starting:            dict["state"] = "starting"
        case .ready(let pid, let port):
            dict["state"] = "ready"
            dict["pid"] = Int(pid)
            dict["readyPort"] = Int(port)
        case .readyFromDaemon(let port):
            dict["state"] = "readyFromDaemon"
            dict["readyPort"] = Int(port)
        case .crashed(let reason):
            dict["state"] = "crashed"
            dict["reason"] = reason
        case .daemonUnavailable(let reason):
            dict["state"] = "daemonUnavailable"
            dict["reason"] = reason
        }
        if let lastError = snapshot.lastError { dict["lastError"] = lastError }
        guard let data = try? JSONSerialization.data(
            withJSONObject: dict,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
