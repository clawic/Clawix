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
                        statusPill(text: adapter, color: Color.overlay(0.35))
                    }
                    if let version = presentation.version {
                        statusPill(text: "v\(version)", color: Color.overlay(0.35))
                    }
                    statusPill(
                        text: presentation.installedLabel,
                        color: presentation.installed ? .green : .orange
                    )
                    Spacer()
                }
            }
            if let support = snapshot.support {
                Divider().background(Color.overlay(0.07))
                runtimeLensSupport(support)
            }
            if let supportAudit = snapshot.supportAudit {
                Divider().background(Color.overlay(0.07))
                runtimeLensSupportAudit(supportAudit)
            }
            Divider().background(Color.overlay(0.07))
            row(label: "CLI") {
                statusPill(
                    text: presentation.cliLabel,
                    color: presentation.cliAvailable ? .green : .orange
                )
            }
            Divider().background(Color.overlay(0.07))
            row(label: "Gateway") {
                statusPill(
                    text: presentation.gatewayLabel,
                    color: presentation.gatewayAvailable ? .green : .orange
                )
            }
            if presentation.workspaceCanonicalPathCount > 0 || presentation.workspaceManagedFileCount > 0 {
                Divider().background(Color.overlay(0.07))
                row(label: "Workspace files") {
                    HStack(spacing: 8) {
                        if presentation.workspaceCanonicalPathCount > 0 {
                            statusPill(text: "canonical \(presentation.workspaceCanonicalPathCount)", color: .blue)
                        }
                        if presentation.workspaceManagedFileCount > 0 {
                            statusPill(text: "managed \(presentation.workspaceManagedFileCount)", color: Color.overlay(0.35))
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
                Divider().background(Color.overlay(0.07))
                row(label: "Runtime resources") {
                    HStack(spacing: 8) {
                        statusPill(text: "\(presentation.runtimeResourceCount)", color: .blue)
                        statusPill(
                            text: "groups \(presentation.runtimeResourceAggregateDomainCount)",
                            color: Color.overlay(0.35)
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
                Divider().background(Color.overlay(0.07))
                row(label: "Capabilities") {
                    HStack(spacing: 8) {
                        if presentation.capabilityCount > 0 {
                            statusPill(text: "\(presentation.capabilityCount)", color: .blue)
                        }
                        if presentation.rawCapabilityCount > 0 {
                            statusPill(
                                text: "enabled \(presentation.rawCapabilityEnabledCount)/\(presentation.rawCapabilityCount)",
                                color: Color.overlay(0.35)
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
                                statusPill(text: strategy, color: Color.overlay(0.28))
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
                Divider().background(Color.overlay(0.07))
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
                Divider().background(Color.overlay(0.07))
                Text(error)
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("runtime-lens-runtime-summary")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

}
