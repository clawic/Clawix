import ClawHostKit
import CommanderCore
import Foundation
import SwiftUI

struct NetworkControlAdapter: Equatable, Identifiable {
    var id: String
    var kind: String
    var label: String
    var status: String
    var enforcement: String
    var externalPending: Bool
    var reason: String
    var reentryCondition: String?
}

struct NetworkControlRule: Equatable, Identifiable {
    var id: String
    var action: String
    var subjectKind: String
    var endpointKind: String
    var endpointValue: String
    var priority: Int
    var enabled: Bool
    var source: String
    var notes: String?
}

struct NetworkControlEvent: Equatable, Identifiable {
    var id: String
    var observedAt: String
    var subjectKind: String
    var subjectID: String
    var endpointKind: String
    var endpointValue: String
    var decision: String
    var adapterID: String
    var bytesIn: Int
    var bytesOut: Int
    var domainHidden: Bool
    var processHidden: Bool
}

struct NetworkControlStatus: Equatable {
    var detailOptIn: Bool
    var defaultRedaction: String
    var clawRuntime: String
    var gateway: String
    var nativeMac: String
    var recentEvents: Int
    var monitorPath: String
}

struct NetworkControlRouteDecision: Equatable {
    var routeID: String
    var decision: String
    var adapterID: String
    var explanation: String
    var matchedRuleIDs: [String]
    var enforcement: String
}

enum NetworkControlBridgeError: LocalizedError {
    case commandFailed(String)
    case missingData
    case invalidPayload(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message
        case .missingData:
            return "The host returned no network control data."
        case .invalidPayload(let message):
            return message
        }
    }
}

final class NetworkControlBridge {
    fileprivate static let maxCommandResponseBytes = 1_048_576
    private let execute: @Sendable (CommandRequest) async -> CommandResponse

    init(execute: @escaping @Sendable (CommandRequest) async -> CommandResponse) {
        self.execute = execute
    }

    convenience init(service: CommandService) {
        self.init { request in
            await service.execute(request)
        }
    }

    @MainActor
    static func bundledCLI() -> NetworkControlBridge {
        let runner = NetworkControlCLIRunner(
            executableURL: ClawJSRuntime.nodeBinaryURL,
            cliScriptURL: ClawJSRuntime.cliScriptURL,
            workspaceURL: ClawJSServiceManager.workspaceURL,
            environment: ClawJSServiceManager.cliEnvironment()
        )
        return NetworkControlBridge { request in
            do {
                let data = try await runner.run(request: request)
                return try commandResponse(from: data)
            } catch {
                return CommandResponse(
                    ok: false,
                    data: nil,
                    error: CommanderError.invalidCommand(error.localizedDescription).payload,
                    meta: .init(adapter: "network-control", source: .framework, durationMS: 0)
                )
            }
        }
    }

    func status(detailOptIn: Bool = false) async throws -> NetworkControlStatus {
        let response = await execute(CommandRequest(
            domain: .system,
            resource: "network",
            action: "status",
            arguments: detailOptIn ? ["detail_opt_in": "true"] : [:],
            clientContext: .current()
        ))
        return try Self.decodeStatus(response)
    }

    func adapters() async throws -> [NetworkControlAdapter] {
        let response = await execute(CommandRequest(
            domain: .system,
            resource: "network",
            action: "adapters",
            arguments: [:],
            clientContext: .current()
        ))
        return try Self.decodeAdapters(response)
    }

    func events(detailOptIn: Bool = false) async throws -> [NetworkControlEvent] {
        let response = await execute(CommandRequest(
            domain: .system,
            resource: "network",
            action: "events",
            arguments: detailOptIn ? ["detail_opt_in": "true"] : [:],
            clientContext: .current()
        ))
        return try Self.decodeEvents(response)
    }

    func rules() async throws -> [NetworkControlRule] {
        let response = await execute(CommandRequest(
            domain: .system,
            resource: "network",
            action: "rules",
            arguments: [:],
            clientContext: .current()
        ))
        return try Self.decodeRules(response)
    }

    func routeDecision(routeID: String) async throws -> NetworkControlRouteDecision {
        let response = await execute(CommandRequest(
            domain: .system,
            resource: "network",
            action: "routes",
            arguments: ["route_id": routeID],
            clientContext: .current()
        ))
        return try Self.decodeRouteDecision(response)
    }

    static func decodeStatus(_ response: CommandResponse) throws -> NetworkControlStatus {
        guard response.ok else {
            throw NetworkControlBridgeError.commandFailed(response.error?.message ?? "Network control command failed.")
        }
        guard let data = try decodedObject(from: response.data) as? [String: Any] else {
            throw NetworkControlBridgeError.missingData
        }
        let privacy = data["privacy"] as? [String: Any] ?? [:]
        let enforcement = data["enforcement"] as? [String: Any] ?? [:]
        let monitor = data["monitor"] as? [String: Any] ?? [:]
        return NetworkControlStatus(
            detailOptIn: bool(from: privacy["detailOptIn"]) ?? false,
            defaultRedaction: string(from: privacy["defaultRedaction"]) ?? "aggregate",
            clawRuntime: string(from: enforcement["clawRuntime"]) ?? "",
            gateway: string(from: enforcement["gateway"]) ?? "",
            nativeMac: string(from: enforcement["nativeMac"]) ?? "",
            recentEvents: integer(from: monitor["recentEvents"]) ?? 0,
            monitorPath: string(from: monitor["dbPath"]) ?? ""
        )
    }

    static func decodeAdapters(_ response: CommandResponse) throws -> [NetworkControlAdapter] {
        guard response.ok else {
            throw NetworkControlBridgeError.commandFailed(response.error?.message ?? "Network adapters command failed.")
        }
        guard let object = try decodedObject(from: response.data) as? [String: Any] else {
            throw NetworkControlBridgeError.missingData
        }
        let adapters = object["adapters"] as? [[String: Any]] ?? []
        return adapters.compactMap(decodeAdapter)
    }

    static func decodeEvents(_ response: CommandResponse) throws -> [NetworkControlEvent] {
        guard response.ok else {
            throw NetworkControlBridgeError.commandFailed(response.error?.message ?? "Network events command failed.")
        }
        guard let object = try decodedObject(from: response.data) as? [String: Any] else {
            throw NetworkControlBridgeError.missingData
        }
        let events = object["events"] as? [[String: Any]] ?? []
        return events.compactMap(decodeEvent)
    }

    static func decodeRules(_ response: CommandResponse) throws -> [NetworkControlRule] {
        guard response.ok else {
            throw NetworkControlBridgeError.commandFailed(response.error?.message ?? "Network rules command failed.")
        }
        guard let object = try decodedObject(from: response.data) as? [String: Any] else {
            throw NetworkControlBridgeError.missingData
        }
        let rules = object["rules"] as? [[String: Any]] ?? []
        return rules.compactMap(decodeRule)
    }

    static func decodeRouteDecision(_ response: CommandResponse) throws -> NetworkControlRouteDecision {
        guard response.ok else {
            throw NetworkControlBridgeError.commandFailed(response.error?.message ?? "Network routes command failed.")
        }
        guard let object = try decodedObject(from: response.data) as? [String: Any],
              let route = (object["routes"] as? [[String: Any]])?.first,
              let policy = route["policy"] as? [String: Any] else {
            throw NetworkControlBridgeError.missingData
        }
        return NetworkControlRouteDecision(
            routeID: string(from: route["routeId"]) ?? "",
            decision: string(from: policy["decision"]) ?? "",
            adapterID: string(from: policy["adapterId"]) ?? string(from: route["adapterId"]) ?? "",
            explanation: string(from: policy["explanation"]) ?? "",
            matchedRuleIDs: stringArray(from: policy["matchedRuleIds"]) ?? [],
            enforcement: string(from: route["enforcement"]) ?? ""
        )
    }

    private static func decodeAdapter(_ object: [String: Any]) -> NetworkControlAdapter? {
        guard let id = string(from: object["id"]) else { return nil }
        return NetworkControlAdapter(
            id: id,
            kind: string(from: object["kind"]) ?? "",
            label: string(from: object["label"]) ?? id,
            status: string(from: object["status"]) ?? "",
            enforcement: string(from: object["enforcement"]) ?? "",
            externalPending: bool(from: object["externalPending"]) ?? false,
            reason: string(from: object["reason"]) ?? "",
            reentryCondition: string(from: object["reentryCondition"])
        )
    }

    private static func decodeRule(_ object: [String: Any]) -> NetworkControlRule? {
        guard let id = string(from: object["id"]) else { return nil }
        let subject = object["subject"] as? [String: Any] ?? [:]
        let endpoint = object["endpoint"] as? [String: Any] ?? [:]
        return NetworkControlRule(
            id: id,
            action: string(from: object["action"]) ?? "",
            subjectKind: string(from: subject["kind"]) ?? "",
            endpointKind: string(from: endpoint["kind"]) ?? "",
            endpointValue: string(from: endpoint["value"]) ?? "",
            priority: integer(from: object["priority"]) ?? 0,
            enabled: bool(from: object["enabled"]) ?? true,
            source: string(from: object["source"]) ?? "",
            notes: string(from: object["notes"])
        )
    }

    private static func decodeEvent(_ object: [String: Any]) -> NetworkControlEvent? {
        guard let id = string(from: object["id"]) else { return nil }
        let subject = object["subject"] as? [String: Any] ?? [:]
        let endpoint = object["endpoint"] as? [String: Any] ?? [:]
        let redaction = object["redaction"] as? [String: Any] ?? [:]
        return NetworkControlEvent(
            id: id,
            observedAt: string(from: object["observedAt"]) ?? "",
            subjectKind: string(from: subject["kind"]) ?? "",
            subjectID: string(from: subject["id"]) ?? "",
            endpointKind: string(from: endpoint["kind"]) ?? "",
            endpointValue: string(from: endpoint["value"]) ?? "",
            decision: string(from: object["decision"]) ?? "",
            adapterID: string(from: object["adapterId"]) ?? "",
            bytesIn: integer(from: object["bytesIn"]) ?? 0,
            bytesOut: integer(from: object["bytesOut"]) ?? 0,
            domainHidden: bool(from: redaction["domainHidden"]) ?? true,
            processHidden: bool(from: redaction["processHidden"]) ?? true
        )
    }

    private static func decodedObject<Value: Encodable>(from value: Value?) throws -> Any? {
        guard let value else { return nil }
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }

    private static func commandResponse(from data: Data) throws -> CommandResponse {
        guard data.count <= Self.maxCommandResponseBytes else {
            throw NetworkControlBridgeError.invalidPayload("Network control CLI output exceeded the local size limit.")
        }
        // hot-path-ok maxBytes=1048576 reason=network control CLI returns one bounded JSON envelope
        guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkControlBridgeError.invalidPayload("Network control CLI returned invalid JSON.")
        }
        let ok = bool(from: envelope["ok"]) ?? false
        let payload = envelope["data"].map { CommanderCore.JSONValue.from(any: $0) }
        let errorMessage = ((envelope["error"] as? [String: Any])?["message"] as? String)
            ?? (ok ? nil : "Network control CLI failed.")
        return CommandResponse(
            ok: ok,
            data: payload,
            error: ok ? nil : CommanderError.invalidCommand(errorMessage ?? "Network control CLI failed.").payload,
            meta: .init(adapter: "network-control", source: .framework, durationMS: 0)
        )
    }

    private static func string(from value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func integer(from value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func bool(from value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String {
            if ["true", "1", "yes", "on"].contains(string.lowercased()) { return true }
            if ["false", "0", "no", "off"].contains(string.lowercased()) { return false }
        }
        return nil
    }

    private static func stringArray(from value: Any?) -> [String]? {
        (value as? [Any])?.compactMap { string(from: $0) }
    }
}

@MainActor
private final class NetworkControlCLIRunner {
    private let executableURL: URL
    private let cliScriptURL: URL
    private let workspaceURL: URL
    private let environment: [String: String]

    init(
        executableURL: URL,
        cliScriptURL: URL,
        workspaceURL: URL,
        environment: [String: String]
    ) {
        self.executableURL = executableURL
        self.cliScriptURL = cliScriptURL
        self.workspaceURL = workspaceURL
        self.environment = environment
    }

    func run(request: CommandRequest) async throws -> Data {
        guard ClawJSRuntime.isAvailable else {
            throw NetworkControlBridgeError.commandFailed("ClawJS bundle is not available in this build.")
        }
        let args = try arguments(for: request) + ["--json"]
        return try await Self.runProcess(
            executableURL: executableURL,
            arguments: [cliScriptURL.path] + args,
            currentDirectoryURL: workspaceURL,
            environment: environment
        )
    }

    private func arguments(for request: CommandRequest) throws -> [String] {
        guard request.resource == "network" else {
            throw NetworkControlBridgeError.invalidPayload("Unsupported network control resource: \(request.resource).")
        }
        var args: [String]
        switch request.action {
        case "status":
            args = ["network", "status"]
        case "adapters":
            args = ["network", "adapters"]
        case "events":
            args = ["network", "events", "--limit", request.arguments["limit"] ?? "20"]
        case "rules":
            args = ["network", "rules", "list"]
        case "routes":
            args = ["network", "routes"]
            if let routeID = request.arguments["route_id"], !routeID.isEmpty {
                args += ["--route-id", routeID]
            }
        default:
            throw NetworkControlBridgeError.invalidPayload("Unsupported network control action: \(request.action).")
        }
        if request.arguments["detail_opt_in"] == "true" {
            args += ["--detail-opt-in", "true"]
        }
        return args
    }

    private static func runProcess(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL,
        environment: [String: String]
    ) async throws -> Data {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectoryURL
            process.environment = environment

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            let err = stderr.fileHandleForReading.readDataToEndOfFile()
            // hot-path-ok maxBytes=1048576 reason=network control process runs on detached utility task with bounded output
            process.waitUntilExit()
            guard data.count <= NetworkControlBridge.maxCommandResponseBytes,
                  err.count <= NetworkControlBridge.maxCommandResponseBytes else {
                throw NetworkControlBridgeError.invalidPayload("Network control CLI output exceeded the local size limit.")
            }

            guard process.terminationStatus == 0 else {
                let message = String(data: err.isEmpty ? data : err, encoding: .utf8) ?? "network control CLI failed"
                throw NetworkControlBridgeError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return data
        }.value
    }
}

@MainActor
final class NetworkControlModel: ObservableObject {
    @Published private(set) var status: NetworkControlStatus?
    @Published private(set) var adapters: [NetworkControlAdapter] = []
    @Published private(set) var events: [NetworkControlEvent] = []
    @Published private(set) var rules: [NetworkControlRule] = []
    @Published private(set) var errorMessage: String?

    private let bridge: NetworkControlBridge

    init(bridge: NetworkControlBridge) {
        self.bridge = bridge
    }

    func refresh(detailOptIn: Bool = false) async {
        do {
            async let status = bridge.status(detailOptIn: detailOptIn)
            async let adapters = bridge.adapters()
            async let events = bridge.events(detailOptIn: detailOptIn)
            async let rules = bridge.rules()
            self.status = try await status
            self.adapters = try await adapters
            self.events = try await events
            self.rules = try await rules
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Network Control Center. Shows where agent traffic is enforced
/// (gateway, Mac, runtime), the routing rules in effect, and the recent
/// allow/deny decisions. Visual language follows `STYLE.md`: Manrope via
/// `BodyFont`, `Palette` tokens, Lucide glyphs, `thinScrollers`, and
/// sentence-case section labels.
struct NetworkControlCenterView: View {
    @ObservedObject var model: NetworkControlModel
    @State private var detailOptIn = false
    @State private var isRefreshing = false

    private static let visibleEventLimit = 100
    private static let okColor = Color(red: 0.34, green: 0.78, blue: 0.55)
    private static let warnColor = Color(red: 1.0, green: 0.78, blue: 0.34)
    private static let denyColor = Color(red: 0.95, green: 0.45, blue: 0.45)

    var body: some View {
        VStack(spacing: 0) {
            header
            CardDivider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: detailOptIn) { await reload() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Network")
                    .font(BodyFont.system(size: 16, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text(headerSubtitle)
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer()
            IconChipButton(symbol: "arrow.clockwise", label: "Refresh") {
                Task { await reload() }
            }
            .disabled(isRefreshing)
            .opacity(isRefreshing ? 0.5 : 1)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var headerSubtitle: String {
        let events = model.status?.recentEvents ?? model.events.count
        let ruleText = model.rules.count == 1 ? "1 rule" : "\(model.rules.count) rules"
        let eventText = events == 1 ? "1 recent decision" : "\(events) recent decisions"
        return "\(ruleText) · \(eventText)"
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let errorMessage = model.errorMessage {
                    errorCard(errorMessage)
                }

                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("Enforcement")
                    HStack(spacing: 10) {
                        scopeTile(icon: .globe, label: "Gateway", state: model.status?.gateway ?? "")
                        scopeTile(icon: .laptop, label: "Mac", state: model.status?.nativeMac ?? "")
                        scopeTile(icon: .terminal, label: "Runtime", state: model.status?.clawRuntime ?? "")
                    }
                    privacyControl
                }

                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("Adapters", count: model.adapters.isEmpty ? nil : model.adapters.count)
                    if model.adapters.isEmpty {
                        emptyRow("No enforcement adapters reported.")
                    } else {
                        ForEach(model.adapters) { adapterCard($0) }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("Rules", count: model.rules.isEmpty ? nil : model.rules.count)
                    if model.rules.isEmpty {
                        emptyRow("No routing rules defined.")
                    } else {
                        ForEach(model.rules) { ruleCard($0) }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("Recent activity", count: model.events.isEmpty ? nil : model.events.count)
                    if model.events.isEmpty {
                        emptyRow("No network decisions recorded yet.")
                    } else {
                        ForEach(model.events.prefix(Self.visibleEventLimit)) { eventCard($0) }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .thinScrollers()
    }

    // MARK: - Enforcement summary

    private func scopeTile(icon: LucideIcon.Kind, label: String, state: String) -> some View {
        let color = Self.enforcementColor(state)
        return HStack(spacing: 10) {
            LucideIcon(icon, size: 15)
                .foregroundColor(Palette.textPrimary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                HStack(spacing: 5) {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                    Text(state.isEmpty ? "Off" : state.capitalized)
                        .font(BodyFont.system(size: 12.5, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Palette.popupStroke, lineWidth: Palette.popupStrokeWidth)
                )
        )
    }

    private var privacyControl: some View {
        HStack(spacing: 12) {
            LucideIcon(detailOptIn ? .eye : .eyeOff, size: 15)
                .foregroundColor(Palette.textPrimary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("Reveal endpoint details")
                    .font(BodyFont.system(size: 13, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                Text("Domains and processes are aggregated by default.")
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Palette.textSecondary)
            }
            Spacer()
            PillToggle(isOn: $detailOptIn, accessibilityLabel: "Reveal endpoint details")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.025))
        )
    }

    // MARK: - Cards

    private func adapterCard(_ adapter: NetworkControlAdapter) -> some View {
        HStack(spacing: 12) {
            LucideIcon(Self.adapterIcon(adapter.kind), size: 14)
                .foregroundColor(Palette.textPrimary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(adapter.label)
                    .font(BodyFont.system(size: 13, wght: 600))
                    .foregroundColor(Palette.textPrimary)
                if !adapter.reason.isEmpty {
                    Text(adapter.reason)
                        .font(BodyFont.system(size: 11, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                        .lineLimit(2)
                }
                if let reentry = adapter.reentryCondition, !reentry.isEmpty {
                    Text("Re-enters when \(reentry)")
                        .font(BodyFont.system(size: 10.5, wght: 500))
                        .foregroundColor(Palette.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                statusBadge(adapter.status)
                if adapter.externalPending {
                    tag("External pending", color: Self.warnColor)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.025))
        )
    }

    private func ruleCard(_ rule: NetworkControlRule) -> some View {
        let color = decisionColor(rule.action)
        return HStack(spacing: 12) {
            decisionGlyph(rule.action, color: color)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(rule.action.isEmpty ? "Rule" : rule.action.capitalized)
                        .font(BodyFont.system(size: 13, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                    Text(endpointText(kind: rule.endpointKind, value: rule.endpointValue))
                        .font(BodyFont.system(size: 12, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack(spacing: 8) {
                    if !rule.subjectKind.isEmpty { metaText(rule.subjectKind) }
                    if !rule.source.isEmpty { metaText("via \(rule.source)") }
                    if let notes = rule.notes, !notes.isEmpty { metaText(notes) }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text("Priority \(rule.priority)")
                    .font(BodyFont.system(size: 10.5, wght: 500))
                    .foregroundColor(Palette.textTertiary)
                if !rule.enabled {
                    tag("Disabled", color: Palette.textTertiary)
                }
            }
        }
        .opacity(rule.enabled ? 1 : 0.55)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.025))
        )
    }

    private func eventCard(_ event: NetworkControlEvent) -> some View {
        let color = decisionColor(event.decision)
        return HStack(spacing: 12) {
            decisionGlyph(event.decision, color: color)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(event.decision.isEmpty ? "Decision" : event.decision.capitalized)
                        .font(BodyFont.system(size: 13, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                    Text(eventEndpoint(event))
                        .font(BodyFont.system(size: 12, wght: 500))
                        .foregroundColor(Palette.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack(spacing: 8) {
                    if !event.subjectKind.isEmpty { metaText(event.subjectKind) }
                    if !event.adapterID.isEmpty { metaText(event.adapterID) }
                    if event.bytesIn + event.bytesOut > 0 {
                        metaText("↓\(formatBytes(event.bytesIn)) ↑\(formatBytes(event.bytesOut))")
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                if !event.observedAt.isEmpty {
                    Text(relativeTime(event.observedAt))
                        .font(BodyFont.system(size: 10.5, wght: 500))
                        .foregroundColor(Palette.textTertiary)
                }
                if event.domainHidden || event.processHidden {
                    LucideIcon(.eyeOff, size: 11)
                        .foregroundColor(Palette.textTertiary)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.025))
        )
    }

    private func errorCard(_ message: String) -> some View {
        HStack(spacing: 10) {
            LucideIcon(.triangleAlert, size: 14)
                .foregroundColor(Self.denyColor)
            Text(message)
                .font(BodyFont.system(size: 12, wght: 500))
                .foregroundColor(Palette.textPrimary)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Self.denyColor.opacity(0.10))
        )
    }

    // MARK: - Small building blocks

    private func sectionHeader(_ title: String, count: Int? = nil) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(BodyFont.system(size: 12, wght: 600))
                .foregroundColor(Palette.textSecondary)
            if let count {
                Text("\(count)")
                    .font(BodyFont.system(size: 10.5, wght: 600))
                    .foregroundColor(Palette.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule(style: .continuous).fill(Color.white.opacity(0.05)))
            }
            Spacer()
        }
    }

    private func decisionGlyph(_ value: String, color: Color) -> some View {
        LucideIcon(decisionIcon(value), size: 14)
            .foregroundColor(color)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.12))
            )
    }

    private func statusBadge(_ status: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Self.enforcementColor(status))
                .frame(width: 6, height: 6)
            Text(status.isEmpty ? "Unknown" : status.capitalized)
                .font(BodyFont.system(size: 11, wght: 600))
                .foregroundColor(Palette.textPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule(style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(BodyFont.system(size: 10, wght: 600))
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule(style: .continuous).fill(color.opacity(0.14)))
    }

    private func metaText(_ value: String) -> some View {
        Text(value)
            .font(BodyFont.system(size: 10.5, wght: 500))
            .foregroundColor(Palette.textTertiary)
            .lineLimit(1)
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(BodyFont.system(size: 12, wght: 500))
            .foregroundColor(Palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.02))
            )
    }

    // MARK: - Behaviour

    private func reload() async {
        isRefreshing = true
        await model.refresh(detailOptIn: detailOptIn)
        isRefreshing = false
    }

    // MARK: - Formatting and semantics

    private func endpointText(kind: String, value: String) -> String {
        if !value.isEmpty { return value }
        if !kind.isEmpty { return kind }
        return "any endpoint"
    }

    private func eventEndpoint(_ event: NetworkControlEvent) -> String {
        if !event.endpointValue.isEmpty { return event.endpointValue }
        if event.domainHidden { return "Domain hidden" }
        if !event.endpointKind.isEmpty { return event.endpointKind }
        return "endpoint"
    }

    private func formatBytes(_ count: Int) -> String {
        if count <= 0 { return "0 B" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(count)
        var index = 0
        while value >= 1024 && index < units.count - 1 {
            value /= 1024
            index += 1
        }
        return index == 0 ? "\(Int(value)) B" : String(format: "%.1f %@", value, units[index])
    }

    private func relativeTime(_ iso: String) -> String {
        guard !iso.isEmpty else { return "" }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        guard let date = fractional.date(from: iso) ?? plain.date(from: iso) else {
            return iso
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func decisionColor(_ value: String) -> Color {
        let v = value.lowercased()
        if v.contains("allow") || v.contains("permit") || v.contains("accept") { return Self.okColor }
        if v.contains("deny") || v.contains("block") || v.contains("reject") || v.contains("drop") { return Self.denyColor }
        if v.contains("redact") || v.contains("review") || v.contains("pending") || v.contains("ask") { return Self.warnColor }
        return Palette.textSecondary
    }

    private func decisionIcon(_ value: String) -> LucideIcon.Kind {
        let v = value.lowercased()
        if v.contains("allow") || v.contains("permit") || v.contains("accept") { return .circleCheck }
        if v.contains("deny") || v.contains("block") || v.contains("reject") || v.contains("drop") { return .circleX }
        if v.contains("redact") { return .eyeOff }
        if v.contains("review") || v.contains("pending") || v.contains("ask") { return .circleAlert }
        return .circleDot
    }

    private static func enforcementColor(_ value: String) -> Color {
        let v = value.lowercased()
        if v.contains("enforc") || v.contains("active") || v.contains("enabled") || v == "on" { return okColor }
        if v.contains("monitor") || v.contains("advisory") || v.contains("pending") || v.contains("partial") || v.contains("degrad") { return warnColor }
        return Palette.textTertiary
    }

    private static func adapterIcon(_ kind: String) -> LucideIcon.Kind {
        let v = kind.lowercased()
        if v.contains("gateway") { return .globe }
        if v.contains("mac") || v.contains("native") { return .laptop }
        if v.contains("runtime") || v.contains("claw") { return .terminal }
        if v.contains("webhook") { return .webhook }
        if v.contains("proxy") || v.contains("route") { return .workflow }
        return .shieldAlert
    }
}

struct NetworkControlCenterScreen: View {
    @StateObject private var model = NetworkControlModel(bridge: .bundledCLI())

    var body: some View {
        NetworkControlCenterView(model: model)
    }
}
