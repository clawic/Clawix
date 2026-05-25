import SwiftUI

extension ClawJSRuntimeLensSection {
    func runtimeLensViewState(_ presentation: ClawJSRuntimeLensViewStatePresentation) -> some View {
        let pageKey = ClawJSRuntimeLensPageKey("view-state-\(presentation.runtimeId)")
        let slice = page(presentation.rows, key: pageKey)

        return VStack(alignment: .leading, spacing: 6) {
            ForEach(slice.rows) { row in
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
            pager(slice, key: pageKey)
        }
        .accessibilityIdentifier("runtime-lens-view-state-\(presentation.runtimeId)")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    func runtimeLensSessionInventory(
        _ sessions: ClawJSRuntimeLensSnapshot.DomainData.SessionBucket
    ) -> some View {
        let presentation = ClawJSRuntimeLensSessionInventoryPresentation.make(bucket: sessions)

        return VStack(alignment: .leading, spacing: 8) {
            row(label: "Session inventory") {
                HStack(spacing: 8) {
                    statusPill(text: presentation.statusLabel, color: presentation.hasInventoryError ? .orange : .green)
                    statusPill(text: "projected \(presentation.projectedCount)", color: .blue)
                    statusPill(text: "visible \(presentation.visibleCount)", color: Color.overlay(0.35))
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

    func runtimeLensSession(_ session: ClawJSRuntimeLensSnapshot.SessionDescriptor) -> some View {
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
                Divider().background(Color.overlay(0.07))
                row(label: "Fallback") {
                    Text(fallback)
                        .font(BodyFont.system(size: 11.5))
                        .foregroundColor(Palette.textSecondary)
                }
            }
            if let path = presentation.sessionPath {
                Divider().background(Color.overlay(0.07))
                row(label: "Path") {
                    Text(path)
                        .font(BodyFont.system(size: 11.5))
                        .foregroundColor(Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            if let storage = presentation.sessionStorageContract {
                Divider().background(Color.overlay(0.07))
                row(label: "Storage") {
                    Text(storage)
                        .font(BodyFont.system(size: 11.5))
                        .foregroundColor(Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            if let database = presentation.sessionDatabasePath {
                Divider().background(Color.overlay(0.07))
                row(label: "Database") {
                    Text(database)
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

    func runtimeLensSessionActions(_ actions: [ClawJSRuntimeLensSnapshot.SessionActionPolicy]) -> some View {
        let presentation = ClawJSRuntimeLensSessionActionPresentation.make(actions: actions)
        let pageKey = ClawJSRuntimeLensPageKey("session-actions")
        let slice = page(presentation.rows, key: pageKey)

        return VStack(alignment: .leading, spacing: 8) {
            ForEach(slice.rows) { action in
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
            pager(slice, key: pageKey)
        }
        .accessibilityIdentifier("runtime-lens-session-actions")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    func runtimeLensSessionActionContracts(
        _ contracts: [ClawJSRuntimeLensSnapshot.SessionActionPolicy],
        materializedPolicy: [ClawJSRuntimeLensSnapshot.SessionActionPolicy]
    ) -> some View {
        let presentation = ClawJSRuntimeLensSessionActionContractPresentation.make(
            contracts: contracts,
            materializedPolicy: materializedPolicy
        )
        let pageKey = ClawJSRuntimeLensPageKey("session-action-contracts")
        let slice = page(presentation.rows, key: pageKey)

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
            ForEach(slice.rows) { row in
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
            pager(slice, key: pageKey)
        }
        .accessibilityIdentifier("runtime-lens-session-action-contracts")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    func runtimeLensCommands(_ commands: ClawJSRuntimeLensSnapshot.CommandMatrix) -> some View {
        let presentation = ClawJSRuntimeLensCommandMatrixPresentation.make(commands: commands)
        let pageKey = ClawJSRuntimeLensPageKey("command-matrix")
        let slice = page(presentation.rows, key: pageKey)

        return VStack(alignment: .leading, spacing: 8) {
            row(label: "Commands") {
                HStack(spacing: 8) {
                    statusPill(text: "\(presentation.executableCount)", color: .blue)
                    if let authority = presentation.authority {
                        statusPill(text: authority, color: Color.overlay(0.35))
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
            ForEach(slice.rows) { command in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(command.command)
                            .font(BodyFont.system(size: 10.5, weight: .medium))
                            .foregroundColor(Palette.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        statusPill(text: command.writeDisposition, color: commandDispositionColor(command.writeDisposition))
                        if command.argumentCount > 0 {
                            statusPill(text: "args \(command.argumentCount)", color: Color.overlay(0.28))
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
            pager(slice, key: pageKey)
        }
        .accessibilityIdentifier("runtime-lens-command-matrix")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    func commandDispositionColor(_ disposition: String) -> Color {
        runtimeLensColor(ClawJSRuntimeLensStatusTone.commandDisposition(disposition))
    }

    func sessionActionColor(_ status: String) -> Color {
        runtimeLensColor(ClawJSRuntimeLensStatusTone.sessionActionStatus(status))
    }

    func sessionActionDispositionColor(_ disposition: String) -> Color {
        runtimeLensColor(ClawJSRuntimeLensStatusTone.sessionActionDisposition(disposition))
    }

    func runtimeLensSessionOverlayState(_ state: ClawJSRuntimeLensSnapshot.SessionOverlayState) -> some View {
        let presentation = ClawJSRuntimeLensSessionOverlayPresentation.make(state: state)
        let pageKey = ClawJSRuntimeLensPageKey("session-overlays")
        let slice = page(presentation.rows, key: pageKey)

        return VStack(alignment: .leading, spacing: 8) {
            row(label: "Overlays") {
                HStack(spacing: 8) {
                    statusPill(text: "\(presentation.totalOverlays)", color: .blue)
                    if presentation.totalConflicts > 0 {
                        let conflicts = presentation.totalConflicts
                        statusPill(text: "\(conflicts) conflict", color: .orange)
                    }
                    if !presentation.writesRuntime {
                        statusPill(text: "no write", color: Color.overlay(0.35))
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
            ForEach(slice.rows) { overlay in
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
            pager(slice, key: pageKey)
        }
        .accessibilityIdentifier("runtime-lens-session-overlays")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    func overlayConflictColor(_ status: String) -> Color {
        runtimeLensColor(ClawJSRuntimeLensStatusTone.overlayConflictStatus(status))
    }

}
