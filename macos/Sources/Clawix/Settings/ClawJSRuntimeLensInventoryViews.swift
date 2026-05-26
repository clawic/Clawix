import SwiftUI

extension ClawJSRuntimeLensSection {
    func runtimeLensInventory(
        _ snapshot: ClawJSRuntimeLensSnapshot,
        presentation: ClawJSRuntimeLensInventoryPresentation
    ) -> some View {
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(presentation.sections) { section in
                let pageKey = ClawJSRuntimeLensPageKey("inventory-\(section.domain)")
                let slice = page(section.rows, key: pageKey)
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.displayLabel)
                        .font(BodyFont.system(size: 12, weight: .semibold))
                        .foregroundColor(Palette.textPrimary)
                    ForEach(slice.rows) { row in
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
                    pager(slice, key: pageKey)
                }
                .accessibilityIdentifier("runtime-lens-inventory-domain-\(section.domain)")
                .accessibilityLabel(Text(section.accessibilityLabel))
            }
        }
        .accessibilityIdentifier("runtime-lens-inventory")
        .accessibilityLabel(Text(presentation.accessibilityLabel))
    }

    func runtimeSessionOverlayButton(
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

    func resourceStatusColor(_ status: String) -> Color {
        runtimeLensColor(ClawJSRuntimeLensStatusTone.resourceStatus(status))
    }

    @MainActor
    func setRuntimeSessionPinned(
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
            runtimeLensActionResult = runtimeLensSessionOverlayActionResultLabel(result)
            runtimeLensActionResultDetails = runtimeLensSessionOverlayActionResultDetails(result)
            await refreshRuntimeLens(runtime)
        } catch {
            runtimeLensActionError = SettingsUtilities.failureMessage(for: error, surface: "settings.runtimeLens.action")
        }
    }

}
