import AppKit
import SwiftUI

/// Settings page for the Apps surface. Mirrors the master/detail look
/// of the other settings pages: master toggle on top, then an inline
/// table listing every installed app with size + permissions and
/// per-row actions (open, pin, delete, toggle internet access).
struct AppsSettingsPage: View {
    @ObservedObject private var appsStore: AppsStore = .shared
    @ObservedObject private var variantDefaults: AppVariantDefaultsStore = .shared
    @EnvironmentObject var appState: AppState

    @AppStorage(ClawixPersistentSurfaceKeys.appsFeatureEnabled, store: SidebarPrefs.store)
    private var appsFeatureEnabled: Bool = true
    @AppStorage(ClawixPersistentSurfaceKeys.appsDefaultInternetAllowed, store: SidebarPrefs.store)
    private var defaultInternetAllowed: Bool = false
    @AppStorage(ClawixPersistentSurfaceKeys.appsDefaultCallAgent, store: SidebarPrefs.store)
    private var defaultCallAgent: Bool = true

    @State private var pendingDelete: AppRecord?
    @State private var trustAuditSheet: AppsSettingsTrustAuditSheetModel?
    @State private var highRiskAuditSheet: AppsSettingsHighRiskAuditSheetModel?

    private var totalSizeBytes: Int {
        appsStore.apps.reduce(0) { partial, record in
            partial + appSizeOnDisk(record)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            header

            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $appsFeatureEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Apps")
                            .font(BodyFont.system(size: 14, wght: 600))
                        Text("Show the Apps section in the sidebar and let the agent create new ones.")
                            .font(BodyFont.system(size: 12.5, wght: 400))
                            .foregroundColor(Color(white: 0.6))
                    }
                }
                .toggleStyle(.switch)
            }
            .padding(16)
            .background(cardBackground)

            VStack(alignment: .leading, spacing: 0) {
                tableHeader
                Divider().opacity(0.18)
                if appsStore.apps.isEmpty {
                    emptyTable
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(appsStore.sortedApps) { record in
                            AppsSettingsRow(
                                record: record,
                                variantDefault: variantDefaultPresentation(for: record),
                                onOpen: { appState.currentRoute = .app(record.id) },
                                onTogglePin: { appsStore.togglePinned(record) },
                                onToggleInternet: { toggleInternet(record) },
                                onSetUserDefault: { setVariantDefault(record, scope: .user) },
                                onSetWorkspaceDefault: { setVariantDefault(record, scope: .workspace) },
                                onClearUserDefault: { clearVariantDefault(record, scope: .user) },
                                onClearWorkspaceDefault: { clearVariantDefault(record, scope: .workspace) },
                                onShowTrustAudit: { showTrustAudit(record) },
                                onShowHighRiskAudit: { showHighRiskAudit(record) },
                                onDelete: { pendingDelete = record },
                                sizeOnDisk: appSizeOnDisk(record)
                            )
                            Divider().opacity(0.10)
                        }
                    }
                }
            }
            .background(cardBackground)

            VStack(alignment: .leading, spacing: 12) {
                Text("Defaults for new apps")
                    .font(BodyFont.system(size: 13, wght: 600))
                    .foregroundColor(Color(white: 0.85))
                Toggle(isOn: $defaultInternetAllowed) {
                    Text("Internet access")
                        .font(BodyFont.system(size: 13, wght: 500))
                }
                .toggleStyle(.switch)
                Toggle(isOn: $defaultCallAgent) {
                    Text("Allow apps to send messages to the agent")
                        .font(BodyFont.system(size: 13, wght: 500))
                }
                .toggleStyle(.switch)
            }
            .padding(16)
            .background(cardBackground)

            HStack {
                Text("Storage used: \(formatBytes(totalSizeBytes))")
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Color(white: 0.55))
                Spacer()
                Button("Open Apps folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([AppsStore.defaultRootURL()])
                }
                .buttonStyle(.link)
            }
        }
        .alert(item: $pendingDelete) { record in
            Alert(
                title: Text("Delete \"\(record.name)\"?"),
                message: Text("The app folder will be removed from disk. This cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    try? appsStore.delete(record)
                },
                secondaryButton: .cancel()
            )
        }
        .sheet(item: $trustAuditSheet) { model in
            AppsTrustAuditSheet(model: model)
        }
        .sheet(item: $highRiskAuditSheet) { model in
            AppsHighRiskAuditSheet(model: model)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Apps")
                    .font(BodyFont.system(size: 20, wght: 700))
                    .foregroundColor(Palette.textPrimary)
                Text("Mini web apps your agent has built. They live under \(AppsStore.defaultRootURL().path) and you can sync that folder with anything that knows about file paths.")
                    .font(BodyFont.system(size: 13, wght: 400))
                    .foregroundColor(Color(white: 0.62))
            }

            Spacer()

            HStack(spacing: 10) {
                Button(action: showAllTrustAudit) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundColor(Color(white: 0.72))
                .help("Trust audit")

                Button(action: showAllHighRiskAudit) {
                    Image(systemName: "exclamationmark.shield")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundColor(Color(white: 0.72))
                .help("High-risk action audit")
            }
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 0) {
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Project")
                .frame(width: 130, alignment: .leading)
            Text("Last opened")
                .frame(width: 130, alignment: .leading)
            Text("Size")
                .frame(width: 80, alignment: .trailing)
            Text("Net")
                .frame(width: 50, alignment: .center)
            Text("Trust")
                .frame(width: 90, alignment: .center)
            Text("Variant")
                .frame(width: 86, alignment: .center)
            Text("")
                .frame(width: 140)
        }
        .font(BodyFont.system(size: 11.5, wght: 600))
        .foregroundColor(Color(white: 0.5))
        .textCase(.uppercase)
        .tracking(0.4)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var emptyTable: some View {
        HStack {
            Spacer()
            Text("No apps yet")
                .font(BodyFont.system(size: 13, wght: 500))
                .foregroundColor(Color(white: 0.55))
            Spacer()
        }
        .padding(.vertical, 32)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(0.025))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 0.7)
            )
    }

    private func toggleInternet(_ record: AppRecord) {
        var updated = record
        if !updated.permissions.internet {
            // Going from offline → online: ask the user explicitly. We
            // already gate by file path so a JSON edit on disk would
            // not trigger this dialog, but the Settings UI funnel
            // should always pause.
            AppPermissionPrompt.shared.requestInternetApproval(appName: record.name) { allowed in
                guard allowed else { return }
                var copy = record
                copy.permissions.internet = true
                try? appsStore.update(copy)
            }
            return
        }
        updated.permissions.internet = false
        try? appsStore.update(updated)
    }

    private func variantDefaultPresentation(for record: AppRecord) -> AppsSettingsVariantDefaultPresentation {
        let workspaceId = appState.selectedProject?.id
        return AppsSettingsVariantDefaultPresentation(
            record: record,
            workspaceId: workspaceId,
            userDefaultActive: variantDefaults.isDefault(app: record, scope: .user),
            workspaceDefaultActive: workspaceId.map { workspaceId in
                variantDefaults.isDefault(app: record, scope: .workspace, workspaceId: workspaceId)
            } ?? false
        )
    }

    private func setVariantDefault(_ record: AppRecord, scope: AppVariantDefaultScope) {
        do {
            try variantDefaults.setDefault(
                app: record,
                scope: scope,
                workspaceId: scope == .workspace ? appState.selectedProject?.id : nil
            )
            ToastCenter.shared.show(scope == .workspace ? "Workspace variant default set" : "User variant default set")
        } catch {
            ToastCenter.shared.show(error.localizedDescription, icon: .error)
        }
    }

    private func clearVariantDefault(_ record: AppRecord, scope: AppVariantDefaultScope) {
        guard let routeTarget = record.routeTarget else { return }
        variantDefaults.clearDefault(
            routeTarget: routeTarget,
            scope: scope,
            workspaceId: scope == .workspace ? appState.selectedProject?.id : nil
        )
        ToastCenter.shared.show(scope == .workspace ? "Workspace variant default cleared" : "User variant default cleared")
    }

    private func showTrustAudit(_ record: AppRecord) {
        do {
            let events = try AppTrustAudit.read(from: appsStore.trustAuditURL(for: record))
            trustAuditSheet = AppsSettingsTrustAuditSheetModel(record: record, events: events)
        } catch {
            ToastCenter.shared.show(error.localizedDescription, icon: .error)
        }
    }

    private func showAllTrustAudit() {
        do {
            let entries = try appsStore.sortedApps.map { record in
                let events = try AppTrustAudit.read(from: appsStore.trustAuditURL(for: record))
                return AppsSettingsTrustAuditEntry(record: record, events: events)
            }
            trustAuditSheet = AppsSettingsTrustAuditSheetModel(entries: entries)
        } catch {
            ToastCenter.shared.show(error.localizedDescription, icon: .error)
        }
    }

    private func showHighRiskAudit(_ record: AppRecord) {
        do {
            let receipts = try AppHighRiskActionAudit.read(from: appsStore.highRiskActionAuditURL(for: record))
            highRiskAuditSheet = AppsSettingsHighRiskAuditSheetModel(record: record, receipts: receipts)
        } catch {
            ToastCenter.shared.show(error.localizedDescription, icon: .error)
        }
    }

    private func showAllHighRiskAudit() {
        do {
            let entries = try appsStore.sortedApps.map { record in
                let receipts = try AppHighRiskActionAudit.read(from: appsStore.highRiskActionAuditURL(for: record))
                return AppsSettingsHighRiskAuditEntry(record: record, receipts: receipts)
            }
            highRiskAuditSheet = AppsSettingsHighRiskAuditSheetModel(entries: entries)
        } catch {
            ToastCenter.shared.show(error.localizedDescription, icon: .error)
        }
    }

    private func appSizeOnDisk(_ record: AppRecord) -> Int {
        let dir = appsStore.directory(forSlug: record.slug)
        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total = 0
        for case let url as URL in enumerator {
            if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                total += size
            }
        }
        return total
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

private struct AppsSettingsRow: View {
    let record: AppRecord
    let variantDefault: AppsSettingsVariantDefaultPresentation
    let onOpen: () -> Void
    let onTogglePin: () -> Void
    let onToggleInternet: () -> Void
    let onSetUserDefault: () -> Void
    let onSetWorkspaceDefault: () -> Void
    let onClearUserDefault: () -> Void
    let onClearWorkspaceDefault: () -> Void
    let onShowTrustAudit: () -> Void
    let onShowHighRiskAudit: () -> Void
    let onDelete: () -> Void
    let sizeOnDisk: Int

    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(record.icon.isEmpty ? "🪟" : record.icon)
                    .font(.system(size: 16))
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.name)
                        .font(BodyFont.system(size: 13.5, wght: 600))
                        .foregroundColor(Color(white: 0.92))
                        .lineLimit(1)
                    Text(record.slug)
                        .font(BodyFont.system(size: 11.5, wght: 500))
                        .foregroundColor(Color(white: 0.45))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(projectName)
                .font(BodyFont.system(size: 12.5, wght: 500))
                .foregroundColor(Color(white: 0.62))
                .frame(width: 130, alignment: .leading)
                .lineLimit(1)

            Text(lastOpenedText)
                .font(BodyFont.system(size: 12.5, wght: 500))
                .foregroundColor(Color(white: 0.62))
                .frame(width: 130, alignment: .leading)

            Text(formatBytes(sizeOnDisk))
                .font(BodyFont.system(size: 12.5, wght: 500))
                .foregroundColor(Color(white: 0.62))
                .frame(width: 80, alignment: .trailing)

            Button(action: onToggleInternet) {
                Image(systemName: record.permissions.internet ? "globe" : "globe.badge.chevron.backward")
                    .foregroundColor(record.permissions.internet ? .green.opacity(0.8) : Color(white: 0.4))
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.plain)
            .frame(width: 50, alignment: .center)
            .help(record.permissions.internet ? "Internet access enabled. Click to revoke." : "Offline. Click to allow internet.")

            trustControl
                .frame(width: 90, alignment: .center)

            variantDefaultControl
                .frame(width: 86, alignment: .center)

            HStack(spacing: 4) {
                Button(action: onOpen) {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
                .help("Open")

                Button(action: onTogglePin) {
                    Image(systemName: record.pinned ? "pin.fill" : "pin")
                }
                .buttonStyle(.plain)
                .help(record.pinned ? "Unpin" : "Pin")

                Button(action: onShowTrustAudit) {
                    Image(systemName: "shield.lefthalf.filled")
                }
                .buttonStyle(.plain)
                .help("Trust audit")

                Button(action: onShowHighRiskAudit) {
                    Image(systemName: "exclamationmark.shield")
                }
                .buttonStyle(.plain)
                .help("High-risk action audit")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Delete")
                .foregroundColor(.red.opacity(0.8))
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Color(white: 0.7))
            .frame(width: 140, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var trustControl: some View {
        let trust = AppsSettingsTrustPresentation(record: record)
        HStack(spacing: 5) {
            Image(systemName: trust.symbolName)
                .font(.system(size: 12, weight: .semibold))
            Text(trust.statusLabel)
                .font(BodyFont.system(size: 11.5, wght: 600))
                .lineLimit(1)
        }
        .foregroundColor(trust.tint)
        .help(trust.helpText)
    }

    @ViewBuilder
    private var variantDefaultControl: some View {
        if variantDefault.isVariant {
            Menu {
                Button("Set as user default", action: onSetUserDefault)
                    .disabled(!variantDefault.canManageDefaults)
                Button("Set as workspace default", action: onSetWorkspaceDefault)
                    .disabled(!variantDefault.canSetWorkspaceDefault)
                Divider()
                Button("Clear user default", action: onClearUserDefault)
                    .disabled(!variantDefault.isUserDefault)
                Button("Clear workspace default", action: onClearWorkspaceDefault)
                    .disabled(!variantDefault.isWorkspaceDefault)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: variantDefault.symbolName)
                        .font(.system(size: 12, weight: .semibold))
                    Text(variantDefault.statusLabel)
                        .font(BodyFont.system(size: 11.5, wght: 600))
                        .lineLimit(1)
                }
                .foregroundColor(variantDefault.canManageDefaults ? Color(white: 0.78) : Color(white: 0.42))
            }
            .buttonStyle(.plain)
            .help(variantDefault.helpText)
        } else {
            Text("—")
                .font(BodyFont.system(size: 12.5, wght: 500))
                .foregroundColor(Color(white: 0.34))
        }
    }

    private var projectName: String {
        guard let pid = record.projectId,
              let project = appState.projects.first(where: { $0.id == pid }) else {
            return "—"
        }
        return project.name
    }

    private var lastOpenedText: String {
        guard let date = record.lastOpenedAt else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

struct AppsSettingsTrustAuditEntry: Equatable {
    let record: AppRecord
    let events: [AppTrustAuditEvent]
}

struct AppsSettingsTrustAuditSheetModel: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let emptyMessage: String
    let rows: [AppsSettingsTrustAuditRowPresentation]

    init(record: AppRecord, events: [AppTrustAuditEvent]) {
        self.id = record.id.uuidString
        self.title = "Trust audit"
        self.subtitle = "\(record.name) · \(record.slug)"
        self.emptyMessage = "No trust events recorded for this app."
        self.rows = events
            .sorted { $0.createdAt > $1.createdAt }
            .map { AppsSettingsTrustAuditRowPresentation(event: $0) }
    }

    init(entries: [AppsSettingsTrustAuditEntry]) {
        self.id = "all-apps"
        self.title = "Trust audit"
        self.subtitle = "All apps"
        self.emptyMessage = "No trust events recorded for installed apps."
        self.rows = entries
            .flatMap { entry in
                entry.events.map { event in
                    AppsSettingsTrustAuditRowPresentation(event: event, includeAppName: true)
                }
            }
            .sorted { $0.createdAt > $1.createdAt }
    }
}

struct AppsSettingsTrustAuditRowPresentation: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let detail: String
    let symbolName: String
    let createdAt: Date

    init(event: AppTrustAuditEvent, includeAppName: Bool = false) {
        id = event.id
        createdAt = event.createdAt
        let eventTitle: String
        switch event.eventType {
        case .packageImported:
            eventTitle = "Package imported"
            symbolName = "tray.and.arrow.down"
        case .activationApproved:
            eventTitle = "Activation approved"
            symbolName = "checkmark.seal"
        }
        title = includeAppName ? "\(event.appName) · \(eventTitle)" : eventTitle

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        subtitle = formatter.localizedString(for: event.createdAt, relativeTo: Date())

        var parts = [
            "Origin: \(event.originClass.rawValue)",
            "Actor: \(event.actor)"
        ]
        if let signature = event.signatureStatus {
            parts.append("Signature: \(signature.displayLabel)")
        }
        if let digest = event.packageDigestSHA256, !digest.isEmpty {
            parts.append("Package SHA-256: \(digest)")
        }
        if let sourceSlug = event.sourceSlug, !sourceSlug.isEmpty {
            parts.append("Source slug: \(sourceSlug)")
        }
        if let sourcePath = event.sourcePath, !sourcePath.isEmpty {
            parts.append("Source path: \(sourcePath)")
        }
        if let riskMapSource = event.riskMapSource {
            parts.append("Risk map: \(riskMapSource)")
        }
        if !event.ordinaryAccess.isEmpty {
            parts.append("Ordinary: \(event.ordinaryAccess.joined(separator: ", "))")
        }
        if !event.approvalRequired.isEmpty {
            parts.append("Approval: \(event.approvalRequired.joined(separator: ", "))")
        }
        if !event.highRisk.isEmpty {
            parts.append("High risk: \(event.highRisk.joined(separator: ", "))")
        }
        parts.append(event.reason)
        detail = parts.joined(separator: "\n")
    }
}

private struct AppsTrustAuditSheet: View {
    let model: AppsSettingsTrustAuditSheetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.title)
                    .font(BodyFont.system(size: 18, wght: 700))
                    .foregroundColor(Palette.textPrimary)
                Text(model.subtitle)
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Color(white: 0.58))
            }

            if model.rows.isEmpty {
                Text(model.emptyMessage)
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Color(white: 0.58))
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.rows) { row in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: row.symbolName)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Color(white: 0.75))
                                    .frame(width: 20, height: 20)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(row.title)
                                            .font(BodyFont.system(size: 13.5, wght: 650))
                                            .foregroundColor(Color(white: 0.90))
                                        Spacer()
                                        Text(row.subtitle)
                                            .font(BodyFont.system(size: 11.5, wght: 500))
                                            .foregroundColor(Color(white: 0.48))
                                    }
                                    Text(row.detail)
                                        .font(BodyFont.system(size: 12, wght: 400))
                                        .foregroundColor(Color(white: 0.62))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.035))
                            )
                        }
                    }
                }
                .frame(minHeight: 160, maxHeight: 360)
            }
        }
        .padding(22)
        .frame(width: 560)
        .background(Palette.background)
    }
}

struct AppsSettingsHighRiskAuditEntry: Equatable {
    let record: AppRecord
    let receipts: [AppHighRiskActionReceipt]
}

struct AppsSettingsHighRiskAuditSheetModel: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let emptyMessage: String
    let rows: [AppsSettingsHighRiskAuditRowPresentation]

    init(record: AppRecord, receipts: [AppHighRiskActionReceipt]) {
        self.id = "high-risk-\(record.id.uuidString)"
        self.title = "High-risk action audit"
        self.subtitle = "\(record.name) · \(record.slug)"
        self.emptyMessage = "No high-risk action receipts recorded for this app."
        self.rows = receipts
            .sorted { $0.createdAt > $1.createdAt }
            .map { AppsSettingsHighRiskAuditRowPresentation(receipt: $0) }
    }

    init(entries: [AppsSettingsHighRiskAuditEntry]) {
        self.id = "all-high-risk-actions"
        self.title = "High-risk action audit"
        self.subtitle = "All apps"
        self.emptyMessage = "No high-risk action receipts recorded for installed apps."
        self.rows = entries
            .flatMap { entry in
                entry.receipts.map { AppsSettingsHighRiskAuditRowPresentation(receipt: $0, includeAppName: true) }
            }
            .sorted { $0.createdAt > $1.createdAt }
    }
}

struct AppsSettingsHighRiskAuditRowPresentation: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let detail: String
    let symbolName: String
    let createdAt: Date

    init(receipt: AppHighRiskActionReceipt, includeAppName: Bool = false) {
        id = receipt.id
        createdAt = receipt.createdAt
        title = includeAppName ? "\(receipt.appName) · \(receipt.action)" : receipt.action
        symbolName = receipt.outcome == .denied ? "xmark.octagon" : "exclamationmark.shield"

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        subtitle = formatter.localizedString(for: receipt.createdAt, relativeTo: Date())

        detail = [
            "Capability: \(receipt.capabilityId)",
            "Decision: \(receipt.decision.rawValue)",
            "Outcome: \(receipt.outcome.rawValue)",
            "Risk tier: \(receipt.riskTier.rawValue)",
            "Interruptive: \(receipt.interruptiveApproval ? "yes" : "no")",
            receipt.reason
        ].joined(separator: "\n")
    }
}

private struct AppsHighRiskAuditSheet: View {
    let model: AppsSettingsHighRiskAuditSheetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.title)
                    .font(BodyFont.system(size: 18, wght: 700))
                    .foregroundColor(Palette.textPrimary)
                Text(model.subtitle)
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Color(white: 0.58))
            }

            if model.rows.isEmpty {
                Text(model.emptyMessage)
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Color(white: 0.58))
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.rows) { row in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: row.symbolName)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Color(white: 0.75))
                                    .frame(width: 20, height: 20)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(row.title)
                                            .font(BodyFont.system(size: 13.5, wght: 650))
                                            .foregroundColor(Color(white: 0.90))
                                        Spacer()
                                        Text(row.subtitle)
                                            .font(BodyFont.system(size: 11.5, wght: 500))
                                            .foregroundColor(Color(white: 0.48))
                                    }
                                    Text(row.detail)
                                        .font(BodyFont.system(size: 12, wght: 400))
                                        .foregroundColor(Color(white: 0.62))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.035))
                            )
                        }
                    }
                }
                .frame(minHeight: 160, maxHeight: 360)
            }
        }
        .padding(22)
        .frame(width: 560)
        .background(Palette.background)
    }
}

struct AppsSettingsTrustPresentation: Equatable {
    let statusLabel: String
    let symbolName: String
    let helpText: String
    let tone: Tone

    enum Tone: Equatable {
        case normal
        case warning
        case muted
    }

    var tint: Color {
        switch tone {
        case .normal:
            return Color(white: 0.72)
        case .warning:
            return Color(red: 0.95, green: 0.62, blue: 0.30)
        case .muted:
            return Color(white: 0.50)
        }
    }

    init(record: AppRecord) {
        let origin = record.effectiveOriginClass
        let provenance = record.packageProvenance

        switch origin {
        case .localUserAuthored:
            statusLabel = "Local"
            symbolName = "person.crop.square"
            tone = .normal
        case .imported:
            statusLabel = "Imported"
            symbolName = "tray.and.arrow.down"
            tone = provenance?.signatureStatus == .verified ? .normal : .warning
        case .marketplace:
            statusLabel = "Market"
            symbolName = "shippingbox"
            tone = provenance?.signatureStatus == .verified ? .normal : .warning
        case .system:
            statusLabel = "System"
            symbolName = "checkmark.seal"
            tone = .normal
        }

        if let provenance {
            var parts = [
                "Origin: \(origin.rawValue)",
                "Signature: \(provenance.signatureStatus.displayLabel)",
                "Package: \(provenance.packageKind)"
            ]
            if let digest = provenance.packageDigestSHA256, !digest.isEmpty {
                parts.append("Package SHA-256: \(digest)")
            }
            if let sourceSlug = provenance.sourceSlug, !sourceSlug.isEmpty {
                parts.append("Source slug: \(sourceSlug)")
            }
            if let sourcePath = provenance.sourcePath, !sourcePath.isEmpty {
                parts.append("Source path: \(sourcePath)")
            }
            helpText = parts.joined(separator: "\n")
        } else {
            helpText = "Origin: \(origin.rawValue)"
        }
    }
}

struct AppsSettingsVariantDefaultPresentation: Equatable {
    let isVariant: Bool
    let canManageDefaults: Bool
    let hasWorkspace: Bool
    let isUserDefault: Bool
    let isWorkspaceDefault: Bool
    let statusLabel: String
    let symbolName: String
    let helpText: String

    var canSetWorkspaceDefault: Bool {
        canManageDefaults && hasWorkspace
    }

    init(
        record: AppRecord,
        workspaceId: UUID?,
        userDefaultActive: Bool,
        workspaceDefaultActive: Bool
    ) {
        let normalizedTarget = AppVariantDefaultsStore.normalizedRouteTarget(record.routeTarget ?? "")
        let normalizedOriginal = AppVariantDefaultsStore.normalizedRouteTarget(record.variant?.originalRoute ?? "")
        let hasValidVariantTarget = !normalizedTarget.isEmpty && normalizedTarget == normalizedOriginal
        let isAllowed: Bool
        if case .allowed = AppCapabilityCatalog.activationGate(for: record) {
            isAllowed = true
        } else {
            isAllowed = false
        }
        let hasProtectedViolations = !AppCapabilityCatalog.protectedRouteViolations(for: record).isEmpty

        let isVariant = record.variant != nil
        let canManageDefaults = hasValidVariantTarget && isAllowed && !hasProtectedViolations
        let statusLabel: String
        let symbolName: String
        let helpText: String

        if !isVariant {
            statusLabel = ""
            symbolName = "square.grid.2x2"
            helpText = ""
        } else if !canManageDefaults {
            statusLabel = "Blocked"
            symbolName = "exclamationmark.triangle"
            helpText = "This variant cannot be used as a default"
        } else if workspaceDefaultActive {
            statusLabel = "Workspace"
            symbolName = "building.2"
            helpText = "Workspace default variant for \(normalizedTarget)"
        } else if userDefaultActive {
            statusLabel = "User"
            symbolName = "person"
            helpText = "User default variant for \(normalizedTarget)"
        } else {
            statusLabel = "Set"
            symbolName = "square.grid.2x2"
            helpText = "Set this app as a route variant default"
        }

        self.isVariant = isVariant
        self.canManageDefaults = canManageDefaults
        self.hasWorkspace = workspaceId != nil
        self.isUserDefault = userDefaultActive
        self.isWorkspaceDefault = workspaceDefaultActive
        self.statusLabel = statusLabel
        self.symbolName = symbolName
        self.helpText = helpText
    }
}
