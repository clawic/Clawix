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
    @State private var actionInFlight: Set<UUID> = []
    @State private var appsError: String?

    private var totalSizeBytes: Int {
        appsStore.apps.reduce(0) { partial, record in
            partial + appSizeOnDisk(record)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            SectionLabel(title: "General")
            SettingsCard {
                ToggleRow(
                    title: "Enable Apps",
                    detail: "Show the Apps section in the sidebar and let the agent create new ones.",
                    isOn: $appsFeatureEnabled
                )
            }

            SectionLabel(title: "Installed")
            SettingsCard {
                tableHeader
                CardDivider()
                if let appsError {
                    InfoBanner(text: appsError, kind: .error)
                        .padding(12)
                }
                if appsStore.apps.isEmpty {
                    emptyTable
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(appsStore.sortedApps) { record in
                            AppsSettingsRow(
                                record: record,
                                variantDefault: variantDefaultPresentation(for: record),
                                isBusy: actionInFlight.contains(record.id),
                                onOpen: { appState.navigate(to: .app(record.id)) },
                                onTogglePin: { togglePinned(record) },
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
                            if record.id != appsStore.sortedApps.last?.id {
                                CardDivider()
                            }
                        }
                    }
                }
            }

            SectionLabel(title: "Defaults for new apps")
            SettingsCard {
                ToggleRow(
                    title: "Internet access",
                    detail: nil,
                    isOn: $defaultInternetAllowed
                )
                CardDivider()
                ToggleRow(
                    title: "Allow apps to send messages to the agent",
                    detail: nil,
                    isOn: $defaultCallAgent
                )
            }

            HStack {
                Text("Storage used: \(formatBytes(totalSizeBytes))")
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                Spacer()
                IconChipButton(symbol: "folder", label: "Open Apps folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([AppsStore.defaultRootURL()])
                }
            }
            .padding(.top, 18)
        }
        .alert(item: $pendingDelete) { record in
            Alert(
                title: Text("Delete \"\(record.name)\"?"),
                message: Text("The app folder will be removed from disk. This cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    delete(record)
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
                    .font(BodyFont.system(size: 22, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                Text(String(
                    format: L10n.t("Mini web apps your agent has built. They live under %@; Settings only opens and edits the local managed folder."),
                    locale: AppLocale.current,
                    AppsStore.defaultRootURL().path
                ))
                    .font(BodyFont.system(size: 12.5))
                    .foregroundColor(Palette.textSecondary)
            }

            Spacer()

            HStack(spacing: 8) {
                IconChipButton(symbol: "badge.check", action: showAllTrustAudit)
                    .help("Trust audit")
                IconChipButton(symbol: "exclamationmark.shield", action: showAllHighRiskAudit)
                    .help("High-risk action audit")
            }
        }
        .padding(.bottom, 26)
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
        .foregroundColor(Palette.textSecondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var emptyTable: some View {
        HStack {
            Spacer()
            Text("No apps yet")
                .font(BodyFont.system(size: 13, wght: 500))
                .foregroundColor(Palette.textSecondary)
            Spacer()
        }
        .padding(.vertical, 32)
    }

    private func toggleInternet(_ record: AppRecord) {
        var updated = record
        if !updated.permissions.internet {
            AppPermissionPrompt.shared.requestInternetApproval(appName: record.name) { allowed in
                guard allowed else { return }
                Task { @MainActor in
                    var copy = record
                    copy.permissions.internet = true
                    runAppMutation(record) {
                        try appsStore.update(copy)
                    }
                }
            }
            return
        }
        updated.permissions.internet = false
        runAppMutation(record) {
            try appsStore.update(updated)
        }
    }

    private func togglePinned(_ record: AppRecord) {
        var updated = record
        updated.pinned.toggle()
        runAppMutation(record) {
            try appsStore.update(updated)
        }
    }

    private func delete(_ record: AppRecord) {
        runAppMutation(record) {
            try appsStore.delete(record)
        }
    }

    private func runAppMutation(_ record: AppRecord, operation: @escaping @MainActor () throws -> Void) {
        appsError = nil
        actionInFlight.insert(record.id)
        Task { @MainActor in
            await Task.yield()
            do {
                try operation()
            } catch {
                appsError = SettingsUtilities.failureMessage(for: error, surface: "settings.apps.mutation")
            }
            actionInFlight.remove(record.id)
        }
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
            ToastCenter.shared.show(SettingsUtilities.failureMessage(for: error, surface: "settings.apps.variantDefault"), icon: .error)
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
            ToastCenter.shared.show(SettingsUtilities.failureMessage(for: error, surface: "settings.apps.trustAudit"), icon: .error)
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
            ToastCenter.shared.show(SettingsUtilities.failureMessage(for: error, surface: "settings.apps.trustAuditAll"), icon: .error)
        }
    }

    private func showHighRiskAudit(_ record: AppRecord) {
        do {
            let receipts = try AppHighRiskActionAudit.read(from: appsStore.highRiskActionAuditURL(for: record))
            highRiskAuditSheet = AppsSettingsHighRiskAuditSheetModel(record: record, receipts: receipts)
        } catch {
            ToastCenter.shared.show(SettingsUtilities.failureMessage(for: error, surface: "settings.apps.highRiskAudit"), icon: .error)
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
            ToastCenter.shared.show(SettingsUtilities.failureMessage(for: error, surface: "settings.apps.highRiskAuditAll"), icon: .error)
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
    let isBusy: Bool
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
                        .foregroundColor(Palette.textPrimary)
                        .lineLimit(1)
                    Text(record.slug)
                        .font(BodyFont.system(size: 11.5, wght: 500))
                        .foregroundColor(Palette.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(projectName)
                .font(BodyFont.system(size: 12.5, wght: 500))
                .foregroundColor(Palette.textSecondary)
                .frame(width: 130, alignment: .leading)
                .lineLimit(1)

            Text(lastOpenedText)
                .font(BodyFont.system(size: 12.5, wght: 500))
                .foregroundColor(Palette.textSecondary)
                .frame(width: 130, alignment: .leading)

            Text(formatBytes(sizeOnDisk))
                .font(BodyFont.system(size: 12.5, wght: 500))
                .foregroundColor(Palette.textSecondary)
                .frame(width: 80, alignment: .trailing)

            Button(action: onToggleInternet) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    IconImage("globe", size: 13)
                        .foregroundColor(record.permissions.internet ? Self.internetOnColor : Palette.textTertiary)
                }
            }
            .buttonStyle(.plain)
            .frame(width: 50, alignment: .center)
            .disabled(isBusy)
            .help(record.permissions.internet ? "Internet access enabled. Click to revoke." : "Offline. Click to allow internet.")

            trustControl
                .frame(width: 90, alignment: .center)

            variantDefaultControl
                .frame(width: 86, alignment: .center)

            HStack(spacing: 6) {
                Button(action: onOpen) {
                    IconImage("arrow.up.right.square", size: 13)
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .help("Open")

                Button(action: onTogglePin) {
                    IconImage(record.pinned ? "pin.fill" : "pin", size: 13)
                        .foregroundColor(record.pinned ? Palette.textPrimary : Palette.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .help(record.pinned ? "Unpin" : "Pin")

                Button(action: onShowTrustAudit) {
                    IconImage("badge.check", size: 13)
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .help("Trust audit")

                Button(action: onShowHighRiskAudit) {
                    IconImage("exclamationmark.shield", size: 13)
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .help("High-risk action audit")

                Button(action: onDelete) {
                    IconImage("trash", size: 13)
                        .foregroundColor(Self.destructiveColor)
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .help("Delete")
            }
            .foregroundColor(Palette.textSecondary)
            .frame(width: 140, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private static let internetOnColor = Color(red: 0.45, green: 0.78, blue: 0.55)
    private static let destructiveColor = Color.red.opacity(0.8)

    @ViewBuilder
    private var trustControl: some View {
        let trust = AppsSettingsTrustPresentation(record: record)
        HStack(spacing: 5) {
            IconImage(trust.symbolName, size: 12)
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
                    IconImage(variantDefault.symbolName, size: 12)
                    Text(variantDefault.statusLabel)
                        .font(BodyFont.system(size: 11.5, wght: 600))
                        .lineLimit(1)
                }
                .foregroundColor(variantDefault.canManageDefaults ? Palette.textSecondary : Palette.textTertiary)
            }
            .buttonStyle(.plain)
            .help(variantDefault.helpText)
        } else {
            Text("—")
                .font(BodyFont.system(size: 12.5, wght: 500))
                .foregroundColor(Palette.textTertiary)
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
        if let keyId = event.signatureKeyId, !keyId.isEmpty {
            parts.append("Signature key: \(keyId)")
        }
        if let trustSource = event.signatureTrustSource, !trustSource.isEmpty {
            parts.append("Trust source: \(trustSource)")
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
                    .foregroundColor(Palette.textSecondary)
            }

            if model.rows.isEmpty {
                Text(model.emptyMessage)
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.rows) { row in
                            AppsAuditRow(symbolName: row.symbolName,
                                         title: row.title,
                                         subtitle: row.subtitle,
                                         detail: row.detail)
                        }
                    }
                }
                .frame(minHeight: 160, maxHeight: 360)
                .thinScrollers()
            }
        }
        .padding(22)
        .frame(width: 560)
        .background(Palette.background)
    }
}

/// Shared row for the trust / high-risk audit sheets.
private struct AppsAuditRow: View {
    let symbolName: String
    let title: String
    let subtitle: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            IconImage(symbolName, size: 13)
                .foregroundColor(Palette.textSecondary)
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(BodyFont.system(size: 13.5, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                    Spacer()
                    Text(subtitle)
                        .font(BodyFont.system(size: 11.5, wght: 500))
                        .foregroundColor(Palette.textTertiary)
                }
                Text(detail)
                    .font(BodyFont.system(size: 12, wght: 400))
                    .foregroundColor(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
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
                    .foregroundColor(Palette.textSecondary)
            }

            if model.rows.isEmpty {
                Text(model.emptyMessage)
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.rows) { row in
                            AppsAuditRow(symbolName: row.symbolName,
                                         title: row.title,
                                         subtitle: row.subtitle,
                                         detail: row.detail)
                        }
                    }
                }
                .frame(minHeight: 160, maxHeight: 360)
                .thinScrollers()
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
            return Palette.textSecondary
        case .warning:
            return Color(red: 0.95, green: 0.62, blue: 0.30)
        case .muted:
            return Palette.textTertiary
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
            if let keyId = provenance.signatureKeyId, !keyId.isEmpty {
                parts.append("Signature key: \(keyId)")
            }
            if let trustSource = provenance.signatureTrustSource, !trustSource.isEmpty {
                parts.append("Trust source: \(trustSource)")
            }
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
