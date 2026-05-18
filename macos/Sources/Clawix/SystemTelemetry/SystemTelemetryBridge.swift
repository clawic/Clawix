import ClawHostKit
import Combine
import Foundation

struct SystemTelemetrySample: Equatable, Identifiable {
    var id: String { metricKey }
    var metricKey: String
    var value: Double
    var unit: String
    var capturedAt: String
    var source: String
    var confidence: String
}

struct SystemTelemetryWidget: Equatable, Identifiable {
    var id: String
    var title: String
    var placement: String
    var metricKeys: [String]
    var renderMode: String
    var refreshIntervalMS: Int
    var agentVisible: Bool
}

struct SystemTelemetrySnapshotState: Equatable {
    var capturedAt: String
    var samples: [SystemTelemetrySample]
    var unavailableMetricKeys: [String]
    var defaultAgentAccess: String
    var retentionOwner: String

    func sample(for key: String) -> SystemTelemetrySample? {
        samples.first { $0.metricKey == key }
    }
}

enum SystemTelemetryBridgeError: Error, Equatable, LocalizedError {
    case commandFailed(String)
    case missingData
    case invalidPayload(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message
        case .missingData:
            return "The host returned no telemetry data."
        case .invalidPayload(let message):
            return message
        }
    }
}

final class SystemTelemetryBridge {
    private let execute: @Sendable (CommandRequest) async -> CommandResponse

    init(execute: @escaping @Sendable (CommandRequest) async -> CommandResponse) {
        self.execute = execute
    }

    convenience init(service: CommandService) {
        self.init { request in
            await service.execute(request)
        }
    }

    func snapshot() async throws -> SystemTelemetrySnapshotState {
        let response = await execute(CommandRequest(
            domain: .system,
            resource: "telemetry",
            action: "snapshot",
            arguments: [:],
            clientContext: .current()
        ))
        return try Self.decodeSnapshot(response)
    }

    func widgets() async throws -> [SystemTelemetryWidget] {
        let response = await execute(CommandRequest(
            domain: .system,
            resource: "widgets",
            action: "list",
            arguments: [:],
            clientContext: .current()
        ))
        return try Self.decodeWidgets(response)
    }

    static func decodeSnapshot(_ response: CommandResponse) throws -> SystemTelemetrySnapshotState {
        guard response.ok else {
            throw SystemTelemetryBridgeError.commandFailed(response.error?.message ?? "Telemetry command failed.")
        }
        guard let data = try decodedObject(from: response.data) as? [String: Any] else {
            throw SystemTelemetryBridgeError.missingData
        }

        let samples = (data["samples"] as? [[String: Any]] ?? []).compactMap(decodeSample)
        let unavailable = decodeUnavailableMetricKeys(from: data)
        let policy = data["policy"] as? [String: Any] ?? [:]

        return SystemTelemetrySnapshotState(
            capturedAt: string(from: data["captured_at"]) ?? string(from: data["capturedAt"]) ?? string(from: data["generatedAt"]) ?? "",
            samples: samples,
            unavailableMetricKeys: unavailable,
            defaultAgentAccess: string(from: policy["default_agent_access"]) ?? string(from: policy["defaultAgentAccess"]) ?? "safe_read",
            retentionOwner: string(from: policy["retention_owner"]) ?? string(from: policy["retentionOwner"]) ?? "monitor"
        )
    }

    static func decodeWidgets(_ response: CommandResponse) throws -> [SystemTelemetryWidget] {
        guard response.ok else {
            throw SystemTelemetryBridgeError.commandFailed(response.error?.message ?? "Telemetry widget command failed.")
        }
        guard let decoded = try decodedObject(from: response.data) else {
            throw SystemTelemetryBridgeError.missingData
        }
        let values: [[String: Any]]
        if let array = decoded as? [[String: Any]] {
            values = array
        } else if let object = decoded as? [String: Any],
                  let widgets = object["widgets"] as? [[String: Any]] {
            values = widgets
        } else {
            throw SystemTelemetryBridgeError.missingData
        }
        return values.compactMap(decodeWidget)
    }

    private static func decodedObject<Value: Encodable>(from value: Value?) throws -> Any? {
        guard let value else { return nil }
        let data = try JSONEncoder().encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }

    private static func decodeSample(_ object: [String: Any]) -> SystemTelemetrySample? {
        guard let metricKey = string(from: object["metric_key"]) ?? string(from: object["key"]) else {
            return nil
        }
        let source = object["source"]
        let sourceObject = source as? [String: Any]
        return SystemTelemetrySample(
            metricKey: metricKey,
            value: number(from: object["value"]) ?? 0,
            unit: string(from: object["unit"]) ?? "",
            capturedAt: string(from: object["captured_at"]) ?? string(from: object["capturedAt"]) ?? "",
            source: string(from: sourceObject?["adapter"]) ?? string(from: source) ?? "",
            confidence: string(from: object["confidence"]) ?? string(from: sourceObject?["confidence"]) ?? ""
        )
    }

    private static func decodeWidget(_ object: [String: Any]) -> SystemTelemetryWidget? {
        guard let id = string(from: object["id"]) else {
            return nil
        }
        let metricKeys = stringArray(from: object["metric_keys"])
            ?? stringArray(from: object["metricKeys"])
            ?? [string(from: object["metric_key"]) ?? string(from: object["metricKey"])]
                .compactMap { $0 }
        return SystemTelemetryWidget(
            id: id,
            title: string(from: object["title"]) ?? id,
            placement: normalizePlacement(string(from: object["placement"]) ?? "menu_bar"),
            metricKeys: metricKeys,
            renderMode: string(from: object["render_mode"]) ?? string(from: object["presentation"]) ?? "compact",
            refreshIntervalMS: integer(from: object["refresh_interval_ms"]) ?? integer(from: object["refreshIntervalMS"]) ?? 5000,
            agentVisible: bool(from: object["agent_visible"]) ?? bool(from: object["enabledByDefault"]) ?? true
        )
    }

    private static func decodeUnavailableMetricKeys(from data: [String: Any]) -> [String] {
        if let objects = data["unavailable_metrics"] as? [[String: Any]] {
            return objects.compactMap { string(from: $0["metric_key"]) ?? string(from: $0["key"]) }
        }
        if let strings = stringArray(from: data["unavailableMetrics"]) {
            return strings
        }
        if let objects = data["unavailableMetrics"] as? [[String: Any]] {
            return objects.compactMap { string(from: $0["metricKey"]) ?? string(from: $0["metric_key"]) ?? string(from: $0["key"]) }
        }
        return []
    }

    private static func normalizePlacement(_ value: String) -> String {
        switch value {
        case "menubar":
            return "menu_bar"
        case "combined_panel":
            return "panel"
        default:
            return value
        }
    }
}

@MainActor
final class SystemTelemetryMenuBarModel: ObservableObject {
    @Published private(set) var widgets: [SystemTelemetryWidget] = []
    @Published private(set) var snapshot: SystemTelemetrySnapshotState?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRefreshing = false

    private let bridge: SystemTelemetryBridge

    init(bridge: SystemTelemetryBridge) {
        self.bridge = bridge
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            async let nextWidgets = bridge.widgets()
            async let nextSnapshot = bridge.snapshot()
            widgets = try await nextWidgets.filter { $0.agentVisible && ($0.placement == "menu_bar" || $0.placement == "both") }
            snapshot = try await nextSnapshot
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func title(for widget: SystemTelemetryWidget) -> String {
        guard let snapshot else {
            return widget.title
        }
        let rendered = widget.metricKeys.compactMap { key -> String? in
            guard let sample = snapshot.sample(for: key) else {
                return nil
            }
            return Self.compactValue(sample)
        }
        return rendered.isEmpty ? widget.title : rendered.joined(separator: " ")
    }

    private static func compactValue(_ sample: SystemTelemetrySample) -> String {
        switch sample.unit {
        case "bytes":
            return ByteCountFormatter.string(fromByteCount: Int64(sample.value), countStyle: .memory)
        case "percent":
            return "\(Int(sample.value.rounded()))%"
        case "seconds":
            let hours = Int(sample.value / 3600)
            return "\(hours)h"
        case "load":
            return String(format: "%.2f", sample.value)
        default:
            return String(format: "%.0f", sample.value)
        }
    }
}

private func number(from value: Any?) -> Double? {
    switch value {
    case let value as Double:
        return value
    case let value as Int:
        return Double(value)
    case let value as NSNumber:
        return value.doubleValue
    default:
        return nil
    }
}

private func integer(from value: Any?) -> Int? {
    switch value {
    case let value as Int:
        return value
    case let value as Double:
        return Int(value)
    case let value as NSNumber:
        return value.intValue
    default:
        return nil
    }
}

private func bool(from value: Any?) -> Bool? {
    switch value {
    case let value as Bool:
        return value
    case let value as NSNumber:
        return value.boolValue
    default:
        return nil
    }
}

private func string(from value: Any?) -> String? {
    switch value {
    case let value as String:
        return value
    case let value as CustomStringConvertible:
        return value.description
    default:
        return nil
    }
}

private func stringArray(from value: Any?) -> [String]? {
    if let value = value as? [String] {
        return value
    }
    if let values = value as? [Any] {
        return values.compactMap(string)
    }
    return nil
}
