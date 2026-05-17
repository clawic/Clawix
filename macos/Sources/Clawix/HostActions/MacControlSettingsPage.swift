import SwiftUI

struct MacControlSettingsPage: View {
    @EnvironmentObject private var databaseManager: DatabaseManager
    @StateObject private var center = MacControlCenter()
    @State private var family: MacControlSettingsFamily = .wifi
    @State private var timelineFilter: MacControlTimelineFilter = .all
    @State private var pendingCapability: MacControlSettingsCapability?
    @State private var globalProjectionError: String?
    @State private var wifiSSID = ""
    @State private var wifiSecretRef = ""
    @State private var wifiDevice = "en0"
    @State private var windowApp = ""
    @State private var windowTitle = ""
    @State private var windowX = "0"
    @State private var windowY = "0"
    @State private var windowWidth = "1200"
    @State private var windowHeight = "800"
    @State private var shortcutName = ""

    private let familyOptions: [(MacControlSettingsFamily, String)] = MacControlSettingsFamily.allCases.map { ($0, $0.title) }
    private let timelineOptions: [(MacControlTimelineFilter, String)] = MacControlTimelineFilter.allCases.map { ($0, $0.title) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                title: "Mac Control",
                subtitle: "Plan and run governed Mac actions through the signed host broker."
            )

            SectionLabel(title: "Surface")
            SettingsCard {
                SegmentedRow(
                    title: "Capability group",
                    detail: "Choose the part of macOS you want to inspect or control.",
                    options: familyOptions,
                    selection: $family,
                    width: 270
                )
            }

            targetSection
            capabilitiesSection
            permissionsSection
            resultSection
            approvalsSection
            timelineSection
        }
        .alert(
            pendingCapability?.title ?? "Run Mac Action",
            isPresented: Binding(
                get: { pendingCapability != nil },
                set: { if !$0 { pendingCapability = nil } }
            ),
            presenting: pendingCapability
        ) { capability in
            Button("Run", role: .destructive) {
                center.execute(capability, arguments: arguments(for: capability), approved: true)
                pendingCapability = nil
            }
            Button("Cancel", role: .cancel) {
                pendingCapability = nil
            }
        } message: { capability in
            Text("Run \(capability.id) through Mac Control now?")
        }
        .task {
            await projectPendingApprovalsToGlobalInbox()
        }
        .onChange(of: center.pendingApprovals) { _, _ in
            Task { await projectPendingApprovalsToGlobalInbox() }
        }
        .onChange(of: databaseManager.state) { _, _ in
            Task { await projectPendingApprovalsToGlobalInbox() }
        }
    }

    private var approvalsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title: "Approvals")
            SettingsCard {
                if center.pendingApprovals.isEmpty {
                    SettingsRow {
                        RowLabel(title: "No pending approvals", detail: "Medium and high risk actions appear here after planning.")
                    } trailing: {
                        EmptyView()
                    }
                } else {
                    let approvals = center.pendingApprovals
                    if let globalProjectionError {
                        SettingsRow {
                            RowLabel(title: "Inbox projection paused", detail: LocalizedStringKey(globalProjectionError))
                        } trailing: {
                            EmptyView()
                        }
                        CardDivider()
                    }
                    ForEach(approvals, id: \.id) { (approval: MacControlPendingApproval) in
                        SettingsRow {
                            RowLabel(title: LocalizedStringKey(approval.capabilityId), detail: LocalizedStringKey(approval.reason))
                        } trailing: {
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(approval.risk)
                                    .font(BodyFont.system(size: 12, wght: 600))
                                    .foregroundColor(Palette.textPrimary)
                                Text(approval.approverRoles.joined(separator: ", "))
                                    .font(BodyFont.system(size: 11))
                                    .foregroundColor(Palette.textSecondary)
                                if approval.isProjectedToGlobalInbox {
                                    Text("Inbox")
                                        .font(BodyFont.system(size: 11, wght: 600))
                                        .foregroundColor(Color.accentColor)
                                }
                            }
                        }
                        if approval.id != approvals.last?.id {
                            CardDivider()
                        }
                    }
                }
            }
        }
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title: "Timeline")
            SettingsCard {
                SegmentedRow(
                    title: "Filter",
                    detail: "Review recent plans, approvals, runs, and blocked decisions.",
                    options: timelineOptions,
                    selection: $timelineFilter,
                    width: 300
                )
                CardDivider()
                let entries = filteredTimeline
                if entries.isEmpty {
                    SettingsRow {
                        RowLabel(title: "No events", detail: "Plan or run a capability to populate this timeline.")
                    } trailing: {
                        EmptyView()
                    }
                } else {
                    ForEach(Array(entries.prefix(8).enumerated()), id: \.element.id) { index, entry in
                        MacControlTimelineRow(entry: entry)
                        if index < min(entries.count, 8) - 1 {
                            CardDivider()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var targetSection: some View {
        SectionLabel(title: "Target")
        SettingsCard {
            switch family {
            case .wifi:
                MacControlTextRow(title: "SSID", detail: "Required for Connect.", placeholder: "Network name", text: $wifiSSID)
                CardDivider()
                MacControlTextRow(title: "Secret ref", detail: "Optional stored credential reference.", placeholder: "sec_wifi_home", text: $wifiSecretRef)
                CardDivider()
                MacControlTextRow(title: "Device", detail: "Default Wi-Fi interface.", placeholder: "en0", text: $wifiDevice)
            case .window:
                MacControlTextRow(title: "App", detail: "Optional application selector.", placeholder: "Safari", text: $windowApp)
                CardDivider()
                MacControlTextRow(title: "Title", detail: "Optional title selector.", placeholder: "Window title", text: $windowTitle)
                CardDivider()
                HStack(spacing: 8) {
                    MacControlCompactTextField(placeholder: "x", text: $windowX)
                    MacControlCompactTextField(placeholder: "y", text: $windowY)
                    MacControlCompactTextField(placeholder: "width", text: $windowWidth)
                    MacControlCompactTextField(placeholder: "height", text: $windowHeight)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            case .shortcut:
                MacControlTextRow(title: "Shortcut", detail: "Required for Show and Run.", placeholder: "Daily Plan", text: $shortcutName)
            }
        }
    }

    private var capabilitiesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title: "Capabilities")
            SettingsCard {
                let capabilities = MacControlSettingsCapability.capabilities(in: family)
                ForEach(Array(capabilities.enumerated()), id: \.element.id) { index, capability in
                    MacControlCapabilityRow(
                        capability: capability,
                        onPlan: { center.plan(capability, arguments: arguments(for: capability)) },
                        onRun: { pendingCapability = capability }
                    )
                    if index < capabilities.count - 1 {
                        CardDivider()
                    }
                }
            }
        }
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title: "Permissions")
            SettingsCard {
                let permissions = MacControlPermissionSnapshot.current
                ForEach(Array(permissions.enumerated()), id: \.element.id) { index, permission in
                    SettingsRow {
                        RowLabel(title: LocalizedStringKey(permission.title), detail: nil)
                    } trailing: {
                        Text(permission.status)
                            .font(BodyFont.system(size: 12, wght: 600))
                            .foregroundColor(Palette.textSecondary)
                    }
                    if index < permissions.count - 1 {
                        CardDivider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if center.lastError != nil || center.lastPlan != nil || center.lastEvaluation != nil {
            SectionLabel(title: "Latest")
            VStack(alignment: .leading, spacing: 10) {
                if let error = center.lastError {
                    InfoBanner(text: error, kind: .error)
                }
                if let plan = center.lastPlan {
                    MacControlResultCard(
                        title: "Plan",
                        rows: [
                            ("Capability", plan.capabilityId),
                            ("Risk", plan.risk),
                            ("Coverage", plan.coverageState),
                            ("Decision", plan.blockedReasons.isEmpty ? "Executable" : "Blocked"),
                            ("Rollback", rollbackText(plan.rollback)),
                        ] + plan.blockedReasons.map { ("Blocked", $0) }
                    )
                }
                if let evaluation = center.lastEvaluation {
                    MacControlResultCard(
                        title: "Evaluation",
                        rows: [
                            ("Capability", evaluation.capabilityId),
                            ("Decision", evaluation.decision),
                            ("Plan", evaluation.planId),
                            ("Receipt", evaluation.receipt?.id ?? "None"),
                        ] + evaluation.reasons.map { ("Reason", $0) }
                    )
                }
            }
        }
    }

    private func arguments(for capability: MacControlSettingsCapability) -> [String: String] {
        center.arguments(
            for: capability,
            wifiSSID: wifiSSID,
            wifiSecretRef: wifiSecretRef,
            wifiDevice: wifiDevice,
            windowApp: windowApp,
            windowTitle: windowTitle,
            windowX: windowX,
            windowY: windowY,
            windowWidth: windowWidth,
            windowHeight: windowHeight,
            shortcutName: shortcutName
        )
    }

    private func rollbackText(_ rollback: NativeMacActionWireRollbackPlan) -> String {
        if let seconds = rollback.timerSeconds {
            return "\(rollback.level), \(seconds)s"
        }
        return rollback.level
    }

    private var filteredTimeline: [MacControlTimelineEntry] {
        center.timeline.filter { timelineFilter.includes($0) }
    }

    @MainActor
    private func projectPendingApprovalsToGlobalInbox() async {
        guard case .ready = databaseManager.state else { return }
        for approval in center.pendingApprovals where !approval.isProjectedToGlobalInbox {
            do {
                let projection = try await MacControlGlobalInboxProjector.project(approval, using: databaseManager)
                center.markPendingApprovalProjected(
                    id: approval.id,
                    approvalRecordId: projection.approvalRecordId,
                    inboxThreadId: projection.inboxThreadId,
                    inboxMessageId: projection.inboxMessageId
                )
                globalProjectionError = nil
            } catch {
                globalProjectionError = error.localizedDescription
            }
        }
    }
}

private struct MacControlGlobalInboxProjection {
    let approvalRecordId: String
    let inboxThreadId: String
    let inboxMessageId: String
}

@MainActor
private enum MacControlGlobalInboxProjector {
    static func project(
        _ approval: MacControlPendingApproval,
        using manager: DatabaseManager
    ) async throws -> MacControlGlobalInboxProjection {
        let title = "Mac Control approval: \(approval.capabilityId)"
        let content = """
        Approval required for \(approval.capabilityId)
        Risk: \(approval.risk)
        Roles: \(approval.approverRoles.joined(separator: ", "))
        Reason: \(approval.reason)
        Request: \(approval.requestId)
        """
        let createdAt = ISO8601DateFormatter().string(from: approval.createdAt)
        let evidence: DBJSON = .array([
            .string(approval.id),
            .string(approval.requestId),
            .string(approval.capabilityId),
        ])

        let approvalRecord = try await manager.createRecord(collection: "approvals", data: [
            "title": .string(title),
            "status": .string("pending"),
            "kind": .string("policy_gate"),
            "requestedByAgentId": .string("clawix_settings"),
            "policyReason": .string(approval.reason),
            "evidenceIds": evidence,
            "confidence": .number(1.0),
        ])

        do {
            let thread = try await manager.createRecord(collection: "inbox_threads", data: [
                "channel": .string("mac_control"),
                "status": .string("unread"),
                "subject": .string(title),
                "externalThreadId": .string(approval.id),
                "latestMessageAt": .string(createdAt),
                "preview": .string(approval.reason),
            ])

            do {
                let message = try await manager.createRecord(collection: "inbox_messages", data: [
                    "threadId": .string(thread.id),
                    "channel": .string("mac_control"),
                    "externalThreadId": .string(approval.id),
                    "externalMessageId": .string(approval.requestId),
                    "direction": .string("system"),
                    "status": .string("unread"),
                    "attachments": .object([
                        "approvalRecordId": .string(approvalRecord.id),
                        "capabilityId": .string(approval.capabilityId),
                    ]),
                    "content": .string(content),
                ])
                return MacControlGlobalInboxProjection(
                    approvalRecordId: approvalRecord.id,
                    inboxThreadId: thread.id,
                    inboxMessageId: message.id
                )
            } catch {
                try? await manager.deleteRecord(collection: "inbox_threads", id: thread.id)
                try? await manager.deleteRecord(collection: "approvals", id: approvalRecord.id)
                throw error
            }
        } catch {
            try? await manager.deleteRecord(collection: "approvals", id: approvalRecord.id)
            throw error
        }
    }
}

private enum MacControlTimelineFilter: String, CaseIterable, Identifiable {
    case all
    case approvals
    case runs
    case blocked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:       return "All"
        case .approvals: return "Approvals"
        case .runs:      return "Runs"
        case .blocked:   return "Blocked"
        }
    }

    func includes(_ entry: MacControlTimelineEntry) -> Bool {
        switch self {
        case .all:
            return true
        case .approvals:
            return entry.kind == .approval
        case .runs:
            return entry.kind == .evaluation
        case .blocked:
            return entry.decision == "blocked" || entry.kind == .error
        }
    }
}

private struct MacControlCapabilityRow: View {
    let capability: MacControlSettingsCapability
    let onPlan: () -> Void
    let onRun: () -> Void

    var body: some View {
        SettingsRow {
            RowLabel(title: LocalizedStringKey(capability.title), detail: LocalizedStringKey(capability.detail))
        } trailing: {
            HStack(spacing: 7) {
                Button("Plan", action: onPlan)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                if capability.canRun {
                    Button("Run", action: onRun)
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
            }
        }
    }
}

private struct MacControlTextRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?
    let placeholder: String
    @Binding var text: String

    var body: some View {
        SettingsRow {
            RowLabel(title: title, detail: detail)
        } trailing: {
            MacControlCompactTextField(placeholder: placeholder, text: $text)
                .frame(width: 210)
        }
    }
}

private struct MacControlCompactTextField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Palette.textTertiary))
            .textFieldStyle(.plain)
            .font(BodyFont.system(size: 12))
            .foregroundColor(Palette.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.black.opacity(0.24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
            )
    }
}

private struct MacControlResultCard: View {
    let title: String
    let rows: [(String, String)]

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(BodyFont.system(size: 12.5, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .top, spacing: 10) {
                        Text(row.0)
                            .font(BodyFont.system(size: 11, wght: 600))
                            .foregroundColor(Palette.textSecondary)
                            .frame(width: 80, alignment: .leading)
                        Text(row.1)
                            .font(BodyFont.system(size: 11))
                            .foregroundColor(Palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
        }
    }
}

private struct MacControlTimelineRow: View {
    let entry: MacControlTimelineEntry

    var body: some View {
        SettingsRow {
            RowLabel(title: LocalizedStringKey(entry.capabilityId), detail: LocalizedStringKey(entry.detail))
        } trailing: {
            VStack(alignment: .trailing, spacing: 3) {
                Text(entry.decision)
                    .font(BodyFont.system(size: 12, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text([entry.risk, entry.receiptId].compactMap { $0 }.joined(separator: " · "))
                    .font(BodyFont.system(size: 11))
                    .foregroundColor(Palette.textSecondary)
                    .lineLimit(1)
            }
        }
    }
}
