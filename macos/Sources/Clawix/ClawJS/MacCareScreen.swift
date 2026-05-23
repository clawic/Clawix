import SwiftUI

struct MacCareScreen: View {
    @StateObject private var store: ClawJSMacCareStore

    @MainActor
    init() {
        _store = StateObject(wrappedValue: .shared)
    }

    @MainActor
    init(store: ClawJSMacCareStore) {
        _store = StateObject(wrappedValue: store)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let error = store.errorMessage {
                    MacCareStatusBanner(message: error)
                }
                summaryGrid
                scanHistorySection
                selectedScanSection
                finalizerPreviewSection
                routeAtlasSection
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.background)
        .task {
            await store.refresh()
            if store.selectedScan == nil, let latestScanId = store.latestScanId {
                await store.selectScan(id: latestScanId)
            }
        }
        .onDisappear {
            store.cancelSurfaceWork()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Mac Care")
                    .font(BodyFont.system(size: 22, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                Text("Read-only reports from the framework atlas and persisted scan history.")
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(BodyFont.system(size: 13, wght: 600))
            }
            .buttonStyle(.borderless)
            .disabled(store.isLoading)
            .help("Refresh")
        }
    }

    private var summaryGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 170), spacing: 12),
                GridItem(.flexible(minimum: 170), spacing: 12),
                GridItem(.flexible(minimum: 170), spacing: 12),
                GridItem(.flexible(minimum: 170), spacing: 12)
            ],
            alignment: .leading,
            spacing: 12
        ) {
            MacCareMetricTile(
                title: "Routes",
                value: "\(store.report?.routes.count ?? 0)",
                detail: store.report?.sidecar.filename ?? "mac_care.sqlite"
            )
            MacCareMetricTile(
                title: "Scans",
                value: "\(store.scanList?.scans.count ?? 0)",
                detail: store.latestScan?.completedAt.map(Self.shortDate) ?? "No completed scan"
            )
            MacCareMetricTile(
                title: "Candidates",
                value: "\(store.totalPersistedCandidates)",
                detail: Self.bytes(store.totalPersistedSizeBytes)
            )
            MacCareMetricTile(
                title: "Authority",
                value: store.hasDestructiveActionPlan ? "Review" : "Read-only",
                detail: store.report?.executionPolicy.destructiveExecutionAuthority ?? "agent_plan_only"
            )
        }
    }

    private var scanHistorySection: some View {
        SectionCard(title: "Scan history") {
            VStack(alignment: .leading, spacing: 0) {
                if store.isRefreshing && store.scanList == nil {
                    MacCareLoadingRow(title: "Loading scan history")
                } else if let scans = store.scanList?.scans, !scans.isEmpty {
                    ForEach(Array(scans.enumerated()), id: \.element.id) { index, scan in
                        if index > 0 {
                            Divider().background(Color.white.opacity(0.07))
                        }
                        MacCareScanRow(
                            scan: scan,
                            selected: store.selectedScan?.scan.id == scan.id
                        ) {
                            Task { await store.selectScan(id: scan.id) }
                        }
                    }
                } else {
                    MacCareEmptyRow(title: "No persisted scans", detail: "No scan history has been recorded yet.")
                }
            }
        }
    }

    @ViewBuilder
    private var selectedScanSection: some View {
        if let selectedScan = store.selectedScan {
            SectionCard(title: "Selected scan") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        MacCareInlineMetric(title: "Status", value: selectedScan.scan.status)
                        MacCareInlineMetric(title: "Candidates", value: "\(selectedScan.candidates.count)")
                        MacCareInlineMetric(title: "Size", value: Self.bytes(selectedScan.scan.summary.totalSizeBytes ?? 0))
                        MacCareInlineMetric(title: "Safety", value: selectedScan.safety?.requiredAuthority ?? "none")
                    }
                    Divider().background(Color.white.opacity(0.07))
                    if selectedScan.candidates.isEmpty {
                        MacCareEmptyRow(title: "No candidates", detail: "The selected scan has no persisted findings.")
                    } else {
                        ForEach(Array(selectedScan.candidates.prefix(12).enumerated()), id: \.element.id) { index, candidate in
                            if index > 0 {
                                Divider().background(Color.white.opacity(0.07))
                            }
                            MacCareCandidateRow(candidate: candidate)
                        }
                    }
                }
            }
        } else if store.isLoadingScan {
            SectionCard(title: "Selected scan") {
                MacCareLoadingRow(title: "Loading scan detail")
            }
        }
    }

    @ViewBuilder
    private var finalizerPreviewSection: some View {
        if shouldShowFinalizerPreviewSection {
            SectionCard(title: "Finalizer preview") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        MacCareInlineMetric(title: "Authority", value: store.finalizerPreview?.executionAuthority ?? selectedScanAuthority)
                        MacCareInlineMetric(title: "Execution", value: store.finalizerPreview?.willExecute == true ? "Yes" : "No")
                        MacCareInlineMetric(title: "Receipts", value: "\(store.finalizerPreview?.summary.receiptsIssued ?? 0)")
                        Spacer(minLength: 8)
                        Button {
                            Task { await store.previewFinalizerForSelectedScan() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "shield.lefthalf.filled")
                                    .font(BodyFont.system(size: 12, wght: 600))
                                Text("Preview")
                                    .font(BodyFont.system(size: 12, wght: 600))
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(store.isLoadingFinalizerPreview || store.selectedScan?.actionPlan == nil)
                        .help("Prepare finalizer preview")
                    }
                    if store.isLoadingFinalizerPreview {
                        MacCareLoadingRow(title: "Preparing finalizer preview")
                    } else if let preview = store.finalizerPreview {
                        Divider().background(Color.white.opacity(0.07))
                        if preview.actions.isEmpty {
                            MacCareEmptyRow(title: "No final actions", detail: "The selected action plan has no destructive candidates.")
                        } else {
                            ForEach(Array(preview.actions.prefix(8).enumerated()), id: \.element.id) { index, action in
                                if index > 0 {
                                    Divider().background(Color.white.opacity(0.07))
                                }
                                MacCareFinalizerActionRow(action: action)
                            }
                        }
                    } else {
                        MacCareEmptyRow(title: "Preview not prepared", detail: "The selected scan requires signed-host review before final actions.")
                    }
                }
            }
        }
    }

    private var shouldShowFinalizerPreviewSection: Bool {
        store.finalizerPreview != nil || store.isLoadingFinalizerPreview || selectedScanNeedsSignedHost
    }

    private var selectedScanNeedsSignedHost: Bool {
        store.selectedScan?.safety?.requiredAuthority == "signed_host_human_confirmed"
    }

    private var selectedScanAuthority: String {
        store.selectedScan?.safety?.requiredAuthority ?? "none"
    }

    @ViewBuilder
    private var routeAtlasSection: some View {
        if let report = store.report {
            SectionCard(title: "Route atlas") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(report.routes.prefix(10).enumerated()), id: \.element.id) { index, route in
                        if index > 0 {
                            Divider().background(Color.white.opacity(0.07))
                        }
                        MacCareRouteRow(route: route)
                    }
                }
            }
        }
    }

    private static func bytes(_ value: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }

    private static func shortDate(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value) else { return value }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct MacCareMetricTile: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(BodyFont.system(size: 11.5, wght: 600))
                .foregroundColor(Palette.textSecondary)
            Text(value)
                .font(BodyFont.system(size: 20, wght: 650))
                .foregroundColor(Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(detail)
                .font(BodyFont.system(size: 11))
                .foregroundColor(Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(14)
        .frame(minHeight: 96, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(white: 0.085))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.6)
        )
    }
}

private struct MacCareStatusBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(BodyFont.system(size: 12, wght: 600))
                .foregroundColor(Color(red: 0.95, green: 0.62, blue: 0.30))
            Text(message)
                .font(BodyFont.system(size: 12))
                .foregroundColor(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.18, green: 0.12, blue: 0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.orange.opacity(0.25), lineWidth: 0.7)
        )
    }
}

private struct MacCareScanRow: View {
    let scan: ClawJSMacCareClient.ScanSummary
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(BodyFont.system(size: 13, wght: 600))
                    .foregroundColor(selected ? Color(red: 0.50, green: 0.78, blue: 0.55) : Palette.textSecondary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 4) {
                    Text(scan.id)
                        .font(BodyFont.system(size: 12.5, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(scan.metadata.modules?.joined(separator: ", ") ?? scan.moduleId)
                        .font(BodyFont.system(size: 11))
                        .foregroundColor(Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 10)
                MacCareInlineMetric(title: "Candidates", value: "\(scan.candidateCount)")
                MacCareInlineMetric(title: "Size", value: ByteCountFormatter.string(fromByteCount: Int64(scan.summary.totalSizeBytes ?? 0), countStyle: .file))
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct MacCareCandidateRow: View {
    let candidate: ClawJSMacCareClient.PersistedCandidate

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(BodyFont.system(size: 12, wght: 600))
                .foregroundColor(Palette.textSecondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.metadata.displayName ?? candidate.id)
                    .font(BodyFont.system(size: 12.5, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(candidate.path)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 10)
            MacCareInlineMetric(title: candidate.action, value: candidate.selection)
            MacCareInlineMetric(
                title: "Size",
                value: ByteCountFormatter.string(fromByteCount: Int64(candidate.sizeBytes ?? 0), countStyle: .file)
            )
        }
        .padding(.vertical, 10)
    }
}

private struct MacCareRouteRow: View {
    let route: ClawJSMacCareClient.Route

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "folder")
                .font(BodyFont.system(size: 12, wght: 600))
                .foregroundColor(Palette.textSecondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(route.label)
                    .font(BodyFont.system(size: 12.5, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                    .lineLimit(1)
                Text(route.pathPattern)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 10)
            MacCareInlineMetric(title: route.sensitivity, value: route.mutability)
        }
        .padding(.vertical, 10)
    }
}

private struct MacCareFinalizerActionRow: View {
    let action: ClawJSMacCareClient.FinalizerActionPreview

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shield")
                .font(BodyFont.system(size: 12, wght: 600))
                .foregroundColor(Color(red: 0.95, green: 0.62, blue: 0.30))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 4) {
                Text(action.displayName)
                    .font(BodyFont.system(size: 12.5, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(action.path)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(action.rollback.notes)
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            MacCareInlineMetric(title: action.action, value: action.selection)
            MacCareInlineMetric(title: "Rollback", value: action.rollback.level)
            MacCareInlineMetric(title: "Receipt", value: action.audit.receiptStatus)
        }
        .padding(.vertical, 10)
    }
}

private struct MacCareInlineMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(BodyFont.system(size: 10.5, wght: 600))
                .foregroundColor(Palette.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(value)
                .font(BodyFont.system(size: 11.5, wght: 600))
                .foregroundColor(Palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(minWidth: 72, alignment: .leading)
    }
}

private struct MacCareLoadingRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .font(BodyFont.system(size: 12))
                .foregroundColor(Palette.textSecondary)
        }
        .padding(.vertical, 8)
    }
}

private struct MacCareEmptyRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(BodyFont.system(size: 12.5, wght: 600))
                .foregroundColor(Palette.textPrimary)
            Text(detail)
                .font(BodyFont.system(size: 11.5))
                .foregroundColor(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }
}
