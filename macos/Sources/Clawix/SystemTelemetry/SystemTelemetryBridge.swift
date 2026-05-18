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
        let unavailable = (data["unavailable_metrics"] as? [[String: Any]] ?? []).compactMap {
            $0["metric_key"] as? String
        }
        let policy = data["policy"] as? [String: Any] ?? [:]

        return SystemTelemetrySnapshotState(
            capturedAt: data["captured_at"] as? String ?? "",
            samples: samples,
            unavailableMetricKeys: unavailable,
            defaultAgentAccess: policy["default_agent_access"] as? String ?? "safe_read",
            retentionOwner: policy["retention_owner"] as? String ?? "monitor"
        )
    }

    static func decodeWidgets(_ response: CommandResponse) throws -> [SystemTelemetryWidget] {
        guard response.ok else {
            throw SystemTelemetryBridgeError.commandFailed(response.error?.message ?? "Telemetry widget command failed.")
        }
        guard let values = try decodedObject(from: response.data) as? [[String: Any]] else {
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
        guard let metricKey = object["metric_key"] as? String else {
            return nil
        }
        return SystemTelemetrySample(
            metricKey: metricKey,
            value: number(from: object["value"]) ?? 0,
            unit: object["unit"] as? String ?? "",
            capturedAt: object["captured_at"] as? String ?? "",
            source: object["source"] as? String ?? "",
            confidence: object["confidence"] as? String ?? ""
        )
    }

    private static func decodeWidget(_ object: [String: Any]) -> SystemTelemetryWidget? {
        guard let id = object["id"] as? String else {
            return nil
        }
        return SystemTelemetryWidget(
            id: id,
            title: object["title"] as? String ?? id,
            placement: object["placement"] as? String ?? "menu_bar",
            metricKeys: object["metric_keys"] as? [String] ?? [],
            renderMode: object["render_mode"] as? String ?? "compact",
            refreshIntervalMS: object["refresh_interval_ms"] as? Int ?? 5000,
            agentVisible: object["agent_visible"] as? Bool ?? true
        )
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
            widgets = try await nextWidgets.filter { $0.placement == "menu_bar" }
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
