import ClawHostKit
import Foundation
import SwiftUI

enum MacControlSettingsFamily: String, CaseIterable, Identifiable {
    case wifi
    case window
    case shortcut

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wifi:     return "Wi-Fi"
        case .window:   return "Windows"
        case .shortcut: return "Shortcuts"
        }
    }
}

struct MacControlSettingsCapability: Identifiable, Equatable {
    let id: String
    let family: MacControlSettingsFamily
    let title: String
    let detail: String
    let canRun: Bool

    static let all: [MacControlSettingsCapability] = [
        MacControlSettingsCapability(id: "mac.wifi.status", family: .wifi, title: "Status", detail: "Read power and current network.", canRun: false),
        MacControlSettingsCapability(id: "mac.wifi.list", family: .wifi, title: "Known networks", detail: "List preferred Wi-Fi networks.", canRun: false),
        MacControlSettingsCapability(id: "mac.wifi.connect", family: .wifi, title: "Connect", detail: "Join a network using a stored secret.", canRun: true),
        MacControlSettingsCapability(id: "mac.wifi.disconnect", family: .wifi, title: "Disconnect", detail: "Drop the current Wi-Fi connection.", canRun: true),
        MacControlSettingsCapability(id: "mac.wifi.power.on", family: .wifi, title: "Turn on", detail: "Enable the Wi-Fi device.", canRun: true),
        MacControlSettingsCapability(id: "mac.wifi.power.off", family: .wifi, title: "Turn off", detail: "Disable the Wi-Fi device.", canRun: true),
        MacControlSettingsCapability(id: "mac.window.list", family: .window, title: "List", detail: "Read visible application windows.", canRun: false),
        MacControlSettingsCapability(id: "mac.window.focus", family: .window, title: "Focus", detail: "Bring a matching window forward.", canRun: true),
        MacControlSettingsCapability(id: "mac.window.move", family: .window, title: "Move", detail: "Move a matching window to x/y.", canRun: true),
        MacControlSettingsCapability(id: "mac.window.resize", family: .window, title: "Resize", detail: "Resize a matching window.", canRun: true),
        MacControlSettingsCapability(id: "mac.window.close", family: .window, title: "Close", detail: "Close the focused window.", canRun: true),
        MacControlSettingsCapability(id: "mac.window.minimize", family: .window, title: "Minimize", detail: "Minimize the focused window.", canRun: true),
        MacControlSettingsCapability(id: "mac.shortcut.list", family: .shortcut, title: "List", detail: "Read installed Shortcuts.", canRun: false),
        MacControlSettingsCapability(id: "mac.shortcut.show", family: .shortcut, title: "Show", detail: "Open a named Shortcut.", canRun: false),
        MacControlSettingsCapability(id: "mac.shortcut.run", family: .shortcut, title: "Run", detail: "Run a named Shortcut.", canRun: true),
    ]

    static func capabilities(in family: MacControlSettingsFamily) -> [MacControlSettingsCapability] {
        all.filter { $0.family == family }
    }

    static func capability(id: String) -> MacControlSettingsCapability? {
        all.first { $0.id == id }
    }
}

@MainActor
struct MacControlPermissionSnapshot: Identifiable, Equatable {
    let id: String
    let title: String
    let status: String

    static var current: [MacControlPermissionSnapshot] {
        [
            snapshot(.accessibility, title: "Accessibility"),
            snapshot(.automationAppleEvents, title: "Automation"),
            snapshot(.microphone, title: "Microphone"),
            snapshot(.speechRecognition, title: "Speech recognition"),
            snapshot(.camera, title: "Camera"),
            snapshot(.inputMonitoring, title: "Input monitoring"),
            snapshot(.contacts, title: "Contacts"),
            snapshot(.calendar, title: "Calendar"),
            snapshot(.reminders, title: "Reminders"),
        ]
    }

    private static func snapshot(_ permission: NativeMacPermissionBroker.PermissionID, title: String) -> MacControlPermissionSnapshot {
        MacControlPermissionSnapshot(id: permission.rawValue, title: title, status: statusLabel(NativeMacPermissionBroker.status(for: permission)))
    }

    private static func statusLabel(_ status: NativeMacPermissionBroker.Status) -> String {
        switch status {
        case .granted:       return "Granted"
        case .denied:        return "Denied"
        case .notDetermined: return "Not requested"
        }
    }
}

struct MacControlTimelineEntry: Identifiable, Equatable, Codable {
    enum Kind: String, Equatable, Codable {
        case plan
        case approval
        case evaluation
        case error
    }

    let id: String
    let kind: Kind
    let createdAt: Date
    let hostId: String
    let bundleId: String
    let actorId: String
    let capabilityId: String
    let risk: String
    let decision: String
    let receiptId: String?
    let detail: String
}

struct MacControlPendingApproval: Identifiable, Equatable, Codable {
    let id: String
    let requestId: String
    let capabilityId: String
    let risk: String
    let approverRoles: [String]
    let reason: String
    let createdAt: Date
    var globalApprovalRecordId: String? = nil
    var globalInboxThreadId: String? = nil
    var globalInboxMessageId: String? = nil
    var projectedAt: Date? = nil

    var isProjectedToGlobalInbox: Bool {
        globalApprovalRecordId != nil && globalInboxThreadId != nil && globalInboxMessageId != nil
    }
}

struct MacControlCenterPersistence {
    let timelineURL: URL?
    let pendingApprovalsURL: URL?

    static var live: MacControlCenterPersistence {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = base.appendingPathComponent(ClawixPersistentSurfacePaths.components.clawix, isDirectory: true)
        return MacControlCenterPersistence(
            timelineURL: directory.appendingPathComponent(ClawixPersistentSurfacePaths.components.macControlTimelineFile),
            pendingApprovalsURL: directory.appendingPathComponent(ClawixPersistentSurfacePaths.components.macControlPendingApprovalsFile)
        )
    }

    static var memoryOnly: MacControlCenterPersistence {
        MacControlCenterPersistence(timelineURL: nil, pendingApprovalsURL: nil)
    }

    func loadTimeline(limit: Int = 100) -> [MacControlTimelineEntry] {
        guard let timelineURL, let data = try? Data(contentsOf: timelineURL) else { return [] }
        let decoder = JSONDecoder()
        let entries = String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .compactMap { try? decoder.decode(MacControlTimelineEntry.self, from: Data($0.utf8)) }
        return Array(entries.suffix(limit).reversed())
    }

    func loadPendingApprovals() -> [MacControlPendingApproval] {
        guard let pendingApprovalsURL,
              let data = try? Data(contentsOf: pendingApprovalsURL),
              let approvals = try? JSONDecoder().decode([MacControlPendingApproval].self, from: data) else {
            return []
        }
        return approvals
    }

    func appendTimeline(_ entry: MacControlTimelineEntry) {
        guard let timelineURL else { return }
        do {
            try FileManager.default.createDirectory(at: timelineURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var data = try JSONEncoder().encode(entry)
            data.append(0x0A)
            if FileManager.default.fileExists(atPath: timelineURL.path),
               let handle = try? FileHandle(forWritingTo: timelineURL) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: timelineURL, options: .atomic)
            }
        } catch {
            NSLog("Clawix Mac Control timeline write failed: \(error.localizedDescription)")
        }
    }

    func savePendingApprovals(_ approvals: [MacControlPendingApproval]) {
        guard let pendingApprovalsURL else { return }
        do {
            try FileManager.default.createDirectory(at: pendingApprovalsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(approvals)
            try data.write(to: pendingApprovalsURL, options: .atomic)
        } catch {
            NSLog("Clawix Mac Control approvals write failed: \(error.localizedDescription)")
        }
    }

    func clear() {
        if let timelineURL {
            try? FileManager.default.removeItem(at: timelineURL)
        }
        if let pendingApprovalsURL {
            try? FileManager.default.removeItem(at: pendingApprovalsURL)
        }
    }
}

@MainActor
final class MacControlCenter: ObservableObject {
    @Published private(set) var lastPlan: NativeMacActionWirePlan?
    @Published private(set) var lastEvaluation: NativeMacActionWireEvaluation?
    @Published private(set) var lastError: String?
    @Published private(set) var timeline: [MacControlTimelineEntry] = []
    @Published private(set) var pendingApprovals: [MacControlPendingApproval] = []

    private let runner: NativeMacActionCommandRunning
    private let defaults: UserDefaults
    private let auditURL: URL?
    private let persistence: MacControlCenterPersistence

    init(
        runner: NativeMacActionCommandRunning = NativeMacActionProcessRunner(),
        defaults: UserDefaults = .standard,
        auditURL: URL? = nil,
        persistence: MacControlCenterPersistence = .live
    ) {
        self.runner = runner
        self.defaults = defaults
        self.auditURL = auditURL
        self.persistence = persistence
        timeline = persistence.loadTimeline()
        pendingApprovals = persistence.loadPendingApprovals()
    }

    func plan(_ capability: MacControlSettingsCapability, arguments: [String: String] = [:]) {
        do {
            lastError = nil
            lastEvaluation = nil
            let data = try requestBytes(for: capability, arguments: arguments, dryRun: true, approved: false)
            let planBytes = try NativeMacActionWire.planJSON(for: data)
            lastPlan = try JSONDecoder().decode(NativeMacActionWirePlan.self, from: planBytes)
            recordPlan(lastPlan)
        } catch {
            recordError(error.localizedDescription, capabilityId: capability.id)
        }
    }

    func execute(_ capability: MacControlSettingsCapability, arguments: [String: String] = [:], approved: Bool = true) {
        do {
            lastError = nil
            let data = try requestBytes(for: capability, arguments: arguments, dryRun: false, approved: approved)
            let evaluationData = try NativeMacActionWire.evaluateJSON(for: data, defaults: defaults, auditURL: auditURL, runner: runner)
            lastEvaluation = try JSONDecoder().decode(NativeMacActionWireEvaluation.self, from: evaluationData)
            lastPlan = nil
            recordEvaluation(lastEvaluation)
        } catch {
            recordError(error.localizedDescription, capabilityId: capability.id)
        }
    }

    func clearTimeline() {
        timeline = []
        pendingApprovals = []
        persistence.clear()
    }

    func markPendingApprovalProjected(
        id: String,
        approvalRecordId: String,
        inboxThreadId: String,
        inboxMessageId: String,
        projectedAt: Date = Date()
    ) {
        guard let index = pendingApprovals.firstIndex(where: { $0.id == id }) else { return }
        pendingApprovals[index].globalApprovalRecordId = approvalRecordId
        pendingApprovals[index].globalInboxThreadId = inboxThreadId
        pendingApprovals[index].globalInboxMessageId = inboxMessageId
        pendingApprovals[index].projectedAt = projectedAt
        persistence.savePendingApprovals(pendingApprovals)
    }

    func arguments(
        for capability: MacControlSettingsCapability,
        wifiSSID: String,
        wifiSecretRef: String,
        wifiDevice: String,
        windowApp: String,
        windowTitle: String,
        windowX: String,
        windowY: String,
        windowWidth: String,
        windowHeight: String,
        shortcutName: String
    ) -> [String: String] {
        var arguments: [String: String] = [:]

        if capability.family == .wifi {
            arguments.addTrimmed("device", wifiDevice)
            if capability.id == "mac.wifi.connect" {
                arguments.addTrimmed("ssid", wifiSSID)
                arguments.addTrimmed("secretRef", wifiSecretRef)
            }
        }

        if capability.family == .window {
            arguments.addTrimmed("app", windowApp)
            arguments.addTrimmed("title", windowTitle)
            if capability.id == "mac.window.move" {
                arguments.addTrimmed("x", windowX)
                arguments.addTrimmed("y", windowY)
            }
            if capability.id == "mac.window.resize" {
                arguments.addTrimmed("width", windowWidth)
                arguments.addTrimmed("height", windowHeight)
            }
        }

        if capability.family == .shortcut {
            if capability.id == "mac.shortcut.show" || capability.id == "mac.shortcut.run" {
                arguments.addTrimmed("name", shortcutName)
            }
        }

        return arguments
    }

    private func requestBytes(
        for capability: MacControlSettingsCapability,
        arguments: [String: String],
        dryRun: Bool,
        approved: Bool
    ) throws -> Data {
        let request = NativeMacActionWireRequest(
            requestId: "macreq_clawix_\(UUID().uuidString.lowercased())",
            capabilityId: capability.id,
            actor: NativeMacActionWireActor(kind: "user_ui", id: "clawix_settings", role: "owner"),
            host: NativeMacActionWireHost(
                hostId: ProcessInfo.processInfo.hostName,
                bundleId: Bundle.main.bundleIdentifier ?? "com.clawix.app",
                signingIdentity: nil,
                teamId: nil,
                appVariant: appVariant,
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ),
            arguments: arguments.mapValues { .string($0) },
            dryRun: dryRun,
            reason: "Mac Control Settings",
            approved: approved
        )
        return try JSONEncoder().encode(request)
    }

    private var appVariant: String {
        #if DEBUG
        return "debug"
        #else
        return "release"
        #endif
    }

    private func recordPlan(_ plan: NativeMacActionWirePlan?) {
        guard let plan else { return }
        appendTimeline(
            kind: .plan,
            hostId: plan.host.hostId,
            bundleId: plan.host.bundleId,
            actorId: plan.actor.id,
            capabilityId: plan.capabilityId,
            risk: plan.risk,
            decision: plan.blockedReasons.isEmpty ? "planned" : "blocked",
            receiptId: nil,
            detail: plan.blockedReasons.first ?? plan.rollback.level
        )

        for approval in plan.requiredApprovals {
            let item = MacControlPendingApproval(
                id: approval.requestId ?? "\(plan.requestId):\(approval.risk)",
                requestId: plan.requestId,
                capabilityId: plan.capabilityId,
                risk: approval.risk,
                approverRoles: approval.approverRoles,
                reason: approval.reason,
                createdAt: Date()
            )
            upsertPendingApproval(item)
            appendTimeline(
                kind: .approval,
                hostId: plan.host.hostId,
                bundleId: plan.host.bundleId,
                actorId: plan.actor.id,
                capabilityId: plan.capabilityId,
                risk: approval.risk,
                decision: "approval_required",
                receiptId: nil,
                detail: approval.reason
            )
        }
    }

    private func recordEvaluation(_ evaluation: NativeMacActionWireEvaluation?) {
        guard let evaluation else { return }
        if evaluation.decision == "allow" || evaluation.decision == "blocked" {
            pendingApprovals.removeAll { $0.requestId == evaluation.requestId || $0.capabilityId == evaluation.capabilityId }
            persistence.savePendingApprovals(pendingApprovals)
        }
        appendTimeline(
            kind: .evaluation,
            hostId: evaluation.host.hostId,
            bundleId: evaluation.host.bundleId,
            actorId: evaluation.actor.id,
            capabilityId: evaluation.capabilityId,
            risk: evaluation.receipt?.risk ?? "read",
            decision: evaluation.decision,
            receiptId: evaluation.receipt?.id,
            detail: evaluation.reasons.first ?? evaluation.receipt?.result ?? "ok"
        )
    }

    private func recordError(_ message: String, capabilityId: String) {
        lastError = message
        appendTimeline(
            kind: .error,
            hostId: ProcessInfo.processInfo.hostName,
            bundleId: Bundle.main.bundleIdentifier ?? "com.clawix.app",
            actorId: "clawix_settings",
            capabilityId: capabilityId,
            risk: "unknown",
            decision: "error",
            receiptId: nil,
            detail: message
        )
    }

    private func upsertPendingApproval(_ item: MacControlPendingApproval) {
        pendingApprovals.removeAll { $0.id == item.id }
        pendingApprovals.insert(item, at: 0)
        persistence.savePendingApprovals(pendingApprovals)
    }

    private func appendTimeline(
        kind: MacControlTimelineEntry.Kind,
        hostId: String,
        bundleId: String,
        actorId: String,
        capabilityId: String,
        risk: String,
        decision: String,
        receiptId: String?,
        detail: String
    ) {
        let entry = MacControlTimelineEntry(
            id: "mactl_\(UUID().uuidString.lowercased())",
            kind: kind,
            createdAt: Date(),
            hostId: hostId,
            bundleId: bundleId,
            actorId: actorId,
            capabilityId: capabilityId,
            risk: risk,
            decision: decision,
            receiptId: receiptId,
            detail: detail
        )
        timeline.insert(entry, at: 0)
        persistence.appendTimeline(entry)
    }
}

private extension Dictionary where Key == String, Value == String {
    mutating func addTrimmed(_ key: String, _ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self[key] = trimmed
    }
}
