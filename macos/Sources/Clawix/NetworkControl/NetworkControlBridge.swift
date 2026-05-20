import ClawHostKit
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
    private let execute: @Sendable (CommandRequest) async -> CommandResponse

    init(execute: @escaping @Sendable (CommandRequest) async -> CommandResponse) {
        self.execute = execute
    }

    convenience init(service: CommandService) {
        self.init { request in
            await service.execute(request)
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

struct NetworkControlCenterView: View {
    @ObservedObject var model: NetworkControlModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Network")
                    .font(.headline)
                Spacer()
                if let status = model.status {
                    Text(status.defaultRedaction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 8) {
                statusPill("Gateway", model.status?.gateway ?? "unknown")
                statusPill("Mac", model.status?.nativeMac ?? "unknown")
                statusPill("Events", "\(model.status?.recentEvents ?? model.events.count)")
            }

            List {
                Section("Adapters") {
                    ForEach(model.adapters) { adapter in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(adapter.label)
                                Text(adapter.reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(adapter.status)
                                .font(.caption)
                        }
                    }
                }

                Section("Rules") {
                    ForEach(model.rules) { rule in
                        HStack {
                            Text(rule.action)
                            Text(rule.endpointValue.isEmpty ? rule.endpointKind : rule.endpointValue)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(rule.enabled ? "enabled" : "disabled")
                                .font(.caption)
                        }
                    }
                }

                Section("Recent") {
                    ForEach(model.events) { event in
                        HStack {
                            Text(event.decision)
                            Text(event.endpointValue)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(event.adapterID)
                                .font(.caption)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
        .padding(16)
    }

    private func statusPill(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
