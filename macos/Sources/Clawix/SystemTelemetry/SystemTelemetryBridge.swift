import ClawHostKit
import Combine
import Foundation

struct SystemTelemetrySample: Equatable, Identifiable {
    var id: String { metricKey }
    var metricKey: String
    var value: Double
    var stringValue: String?
    var unit: String
    var capturedAt: String
    var source: String
    var confidence: String
}

struct SystemTelemetryHistoryPoint: Equatable, Identifiable {
    var id: String { "\(timestampMS)-\(sourceID)-\(value)" }
    var timestampMS: Double
    var value: Double
    var sourceID: String
    var count: Int?
}

struct SystemTelemetryHistoryChart: Equatable {
    var kind: String
    var metricKey: String
    var unit: String
    var source: String
    var points: [SystemTelemetryHistoryPoint]
    var empty: Bool
}

struct SystemTelemetryHistory: Equatable {
    var metricKey: String
    var rangeMS: Int
    var retentionStatus: String
    var chart: SystemTelemetryHistoryChart
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

struct SystemTelemetryControlAction: Equatable, Identifiable {
    var id: String
    var family: String
    var label: String
    var targetMetricKeys: [String]
    var requiresSignedHostBroker: Bool
    var requiresConfirmation: Bool
    var requiredGrants: [String]
    var riskTier: String
    var availability: String
    var auditEvent: String
    var description: String
}

struct SystemTelemetryControlPlanStep: Equatable, Identifiable {
    var id: String
    var status: String
    var owner: String
    var reason: String?
}

struct SystemTelemetryPlanAuditRedaction: Equatable {
    var credentialRefRedacted: Bool
    var preciseLocationRedacted: Bool
    var targetRedacted: Bool
    var valueRedacted: Bool
    var sensitiveDetailRedacted: Bool
}

struct SystemTelemetryPlanAuditProjection: Equatable {
    var status: String
    var durable: Bool
    var event: String
    var outcome: String
    var receiptStatus: String
    var note: String
    var redaction: SystemTelemetryPlanAuditRedaction
}

struct SystemTelemetryControlPlan: Equatable, Identifiable {
    var id: String
    var status: String
    var willExecute: Bool
    var externalPending: Bool
    var action: SystemTelemetryControlAction
    var target: String?
    var value: String?
    var reason: String
    var brokerStatus: String
    var failClosed: Bool
    var requiredGrants: [String]
    var riskTier: String
    var receiptStatus: String
    var auditEvent: String
    var auditPlan: SystemTelemetryPlanAuditProjection?
    var steps: [SystemTelemetryControlPlanStep]
}

struct SystemTelemetryProvider: Equatable, Identifiable {
    var id: String
    var kind: String
    var label: String
    var mode: String
    var status: String
    var metricKeys: [String]
    var widgetIds: [String]
    var capabilities: [String]
    var defaultEnabled: Bool
    var privacyTier: String
    var requiresGrant: String?
    var credentialRefRequired: Bool
    var freshnessMS: Int
    var description: String
}

struct SystemTelemetryProviderPlanStep: Equatable, Identifiable {
    var id: String
    var status: String
    var owner: String
}

struct SystemTelemetryProviderPlan: Equatable, Identifiable {
    var id: String
    var status: String
    var willConnect: Bool
    var externalPending: Bool
    var provider: SystemTelemetryProvider
    var credentialRef: String?
    var reason: String
    var brokerStatus: String
    var failClosed: Bool
    var requiredGrants: [String]
    var credentialRefRequired: Bool
    var privacyTier: String
    var networkAccess: String
    var receiptStatus: String
    var auditEvent: String
    var auditPlan: SystemTelemetryPlanAuditProjection?
    var steps: [SystemTelemetryProviderPlanStep]
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

struct SystemTelemetryMenuBarConfiguration: Equatable {
    static let storageKey = "SystemTelemetry.MenuBar.EnabledWidgetIDs"
    static let `default` = SystemTelemetryMenuBarConfiguration(enabledWidgetIDs: nil)

    var enabledWidgetIDs: Set<String>?

    func isEnabled(_ widget: SystemTelemetryWidget) -> Bool {
        guard let enabledWidgetIDs else {
            return widget.agentVisible
        }
        return enabledWidgetIDs.contains(widget.id)
    }

    func enabledWidgetIDs(for widgets: [SystemTelemetryWidget]) -> Set<String> {
        guard let enabledWidgetIDs else {
            return Set(widgets.filter(\.agentVisible).map(\.id))
        }
        return enabledWidgetIDs
    }

    func toggling(widgetID: String, widgets: [SystemTelemetryWidget]) -> SystemTelemetryMenuBarConfiguration {
        var nextIDs = enabledWidgetIDs(for: widgets)
        if nextIDs.contains(widgetID) {
            nextIDs.remove(widgetID)
        } else {
            nextIDs.insert(widgetID)
        }
        return SystemTelemetryMenuBarConfiguration(enabledWidgetIDs: nextIDs)
    }

    static func load(defaults: UserDefaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard) -> SystemTelemetryMenuBarConfiguration {
        guard defaults.object(forKey: storageKey) != nil else {
            return .default
        }
        return SystemTelemetryMenuBarConfiguration(enabledWidgetIDs: Set(defaults.stringArray(forKey: storageKey) ?? []))
    }

    func save(defaults: UserDefaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard) {
        if let enabledWidgetIDs {
            defaults.set(Array(enabledWidgetIDs).sorted(), forKey: Self.storageKey)
        } else {
            defaults.removeObject(forKey: Self.storageKey)
        }
    }
}

enum SystemTelemetryMenuBarSeverity: Equatable {
    case normal
    case warning
    case critical
    case unavailable
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

    func controls() async throws -> [SystemTelemetryControlAction] {
        let response = await execute(CommandRequest(
            domain: .system,
            resource: "controls",
            action: "list",
            arguments: [:],
            clientContext: .current()
        ))
        return try Self.decodeControls(response)
    }

    func providers() async throws -> [SystemTelemetryProvider] {
        let response = await execute(CommandRequest(
            domain: .system,
            resource: "providers",
            action: "list",
            arguments: [:],
            clientContext: .current()
        ))
        return try Self.decodeProviders(response)
    }

    func history(metricKey: String, range: String = "1h") async throws -> SystemTelemetryHistory {
        let response = await execute(CommandRequest(
            domain: .system,
            resource: "history",
            action: "get",
            arguments: [
                "metric_key": metricKey,
                "range": range,
            ],
            clientContext: .current()
        ))
        return try Self.decodeHistory(response, fallbackMetricKey: metricKey)
    }

    func controlPlan(
        controlID: String,
        target: String? = nil,
        value: String? = nil,
        reason: String? = nil
    ) async throws -> SystemTelemetryControlPlan {
        var arguments = ["control_id": controlID]
        if let target { arguments["target"] = target }
        if let value { arguments["value"] = value }
        if let reason { arguments["reason"] = reason }

        let response = await execute(CommandRequest(
            domain: .system,
            resource: "controls",
            action: "plan",
            arguments: arguments,
            clientContext: .current()
        ))
        return try Self.decodeControlPlan(response)
    }

    func providerPlan(
        providerID: String,
        credentialRef: String? = nil,
        reason: String? = nil
    ) async throws -> SystemTelemetryProviderPlan {
        var arguments = ["provider_id": providerID]
        if let credentialRef { arguments["credential_ref"] = credentialRef }
        if let reason { arguments["reason"] = reason }

        let response = await execute(CommandRequest(
            domain: .system,
            resource: "providers",
            action: "plan",
            arguments: arguments,
            clientContext: .current()
        ))
        return try Self.decodeProviderPlan(response)
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

    static func decodeControls(_ response: CommandResponse) throws -> [SystemTelemetryControlAction] {
        guard response.ok else {
            throw SystemTelemetryBridgeError.commandFailed(response.error?.message ?? "Telemetry controls command failed.")
        }
        guard let decoded = try decodedObject(from: response.data) else {
            throw SystemTelemetryBridgeError.missingData
        }
        let values: [[String: Any]]
        if let array = decoded as? [[String: Any]] {
            values = array
        } else if let object = decoded as? [String: Any],
                  let controls = object["controls"] as? [[String: Any]] {
            values = controls
        } else {
            throw SystemTelemetryBridgeError.missingData
        }
        return values.compactMap(decodeControlAction)
    }

    static func decodeProviders(_ response: CommandResponse) throws -> [SystemTelemetryProvider] {
        guard response.ok else {
            throw SystemTelemetryBridgeError.commandFailed(response.error?.message ?? "Telemetry providers command failed.")
        }
        guard let decoded = try decodedObject(from: response.data) else {
            throw SystemTelemetryBridgeError.missingData
        }
        let values: [[String: Any]]
        if let array = decoded as? [[String: Any]] {
            values = array
        } else if let object = decoded as? [String: Any],
                  let providers = object["providers"] as? [[String: Any]] {
            values = providers
        } else {
            throw SystemTelemetryBridgeError.missingData
        }
        return values.compactMap(decodeProvider)
    }

    static func decodeHistory(_ response: CommandResponse, fallbackMetricKey: String = "") throws -> SystemTelemetryHistory {
        guard response.ok else {
            throw SystemTelemetryBridgeError.commandFailed(response.error?.message ?? "Telemetry history command failed.")
        }
        guard let object = try decodedObject(from: response.data) as? [String: Any] else {
            throw SystemTelemetryBridgeError.missingData
        }
        let metricObject = object["metric"] as? [String: Any] ?? [:]
        let chartObject = object["chart"] as? [String: Any] ?? [:]
        let retentionObject = object["retention"] as? [String: Any] ?? [:]
        let metricKey = string(from: metricObject["key"])
            ?? string(from: chartObject["metricKey"])
            ?? string(from: chartObject["metric_key"])
            ?? fallbackMetricKey
        let chart = decodeHistoryChart(chartObject, fallbackMetricKey: metricKey)
        return SystemTelemetryHistory(
            metricKey: metricKey,
            rangeMS: integer(from: object["rangeMs"]) ?? integer(from: object["range_ms"]) ?? 0,
            retentionStatus: string(from: retentionObject["status"]) ?? "empty",
            chart: chart
        )
    }

    static func decodeControlPlan(_ response: CommandResponse) throws -> SystemTelemetryControlPlan {
        guard response.ok else {
            throw SystemTelemetryBridgeError.commandFailed(response.error?.message ?? "Telemetry control plan command failed.")
        }
        guard let object = try decodedObject(from: response.data) as? [String: Any] else {
            throw SystemTelemetryBridgeError.missingData
        }
        if let error = string(from: object["error"]) {
            throw SystemTelemetryBridgeError.invalidPayload(error)
        }
        guard let actionObject = object["action"] as? [String: Any],
              let action = decodeControlAction(actionObject) else {
            throw SystemTelemetryBridgeError.invalidPayload("Telemetry control plan is missing an action.")
        }

        let request = object["request"] as? [String: Any] ?? [:]
        let broker = object["broker"] as? [String: Any] ?? [:]
        let policy = object["policy"] as? [String: Any] ?? [:]
        let receipt = object["receipt"] as? [String: Any] ?? [:]
        let stepObjects = object["steps"] as? [[String: Any]] ?? []

        return SystemTelemetryControlPlan(
            id: string(from: object["id"]) ?? "",
            status: string(from: object["status"]) ?? "planned",
            willExecute: bool(from: object["will_execute"]) ?? bool(from: object["willExecute"]) ?? false,
            externalPending: bool(from: object["external_pending"]) ?? bool(from: object["externalPending"]) ?? true,
            action: action,
            target: string(from: request["target"]),
            value: string(from: request["value"]),
            reason: string(from: request["reason"]) ?? "not_provided",
            brokerStatus: string(from: broker["status"]) ?? "external_pending",
            failClosed: bool(from: broker["fail_closed"]) ?? bool(from: broker["failClosed"]) ?? true,
            requiredGrants: stringArray(from: policy["required_grants"]) ?? stringArray(from: policy["requiredGrants"]) ?? [],
            riskTier: string(from: policy["risk_tier"]) ?? string(from: policy["riskTier"]) ?? action.riskTier,
            receiptStatus: string(from: receipt["status"]) ?? "not_issued",
            auditEvent: string(from: receipt["audit_event"]) ?? string(from: receipt["auditEvent"]) ?? action.auditEvent,
            auditPlan: decodeAuditPlan(object["audit_plan"] as? [String: Any] ?? object["auditPlan"] as? [String: Any]),
            steps: stepObjects.compactMap(decodeControlPlanStep)
        )
    }

    static func decodeProviderPlan(_ response: CommandResponse) throws -> SystemTelemetryProviderPlan {
        guard response.ok else {
            throw SystemTelemetryBridgeError.commandFailed(response.error?.message ?? "Telemetry provider plan command failed.")
        }
        guard let object = try decodedObject(from: response.data) as? [String: Any] else {
            throw SystemTelemetryBridgeError.missingData
        }
        if let error = string(from: object["error"]) {
            throw SystemTelemetryBridgeError.invalidPayload(error)
        }
        guard let providerObject = object["provider"] as? [String: Any],
              let provider = decodeProvider(providerObject) else {
            throw SystemTelemetryBridgeError.invalidPayload("Telemetry provider plan is missing a provider.")
        }

        let request = object["request"] as? [String: Any] ?? [:]
        let broker = object["broker"] as? [String: Any] ?? [:]
        let policy = object["policy"] as? [String: Any] ?? [:]
        let receipt = object["receipt"] as? [String: Any] ?? [:]
        let stepObjects = object["steps"] as? [[String: Any]] ?? []

        return SystemTelemetryProviderPlan(
            id: string(from: object["id"]) ?? "",
            status: string(from: object["status"]) ?? "planned",
            willConnect: bool(from: object["will_connect"]) ?? bool(from: object["willConnect"]) ?? false,
            externalPending: bool(from: object["external_pending"]) ?? bool(from: object["externalPending"]) ?? true,
            provider: provider,
            credentialRef: redactedCredentialRef(from: request),
            reason: string(from: request["reason"]) ?? "not_provided",
            brokerStatus: string(from: broker["status"]) ?? "external_pending",
            failClosed: bool(from: broker["fail_closed"]) ?? bool(from: broker["failClosed"]) ?? true,
            requiredGrants: stringArray(from: policy["required_grants"]) ?? stringArray(from: policy["requiredGrants"]) ?? [],
            credentialRefRequired: bool(from: policy["credential_ref_required"]) ?? bool(from: policy["credentialRefRequired"]) ?? provider.credentialRefRequired,
            privacyTier: string(from: policy["privacy_tier"]) ?? string(from: policy["privacyTier"]) ?? provider.privacyTier,
            networkAccess: string(from: policy["network_access"]) ?? string(from: policy["networkAccess"]) ?? "",
            receiptStatus: string(from: receipt["status"]) ?? "not_issued",
            auditEvent: string(from: receipt["audit_event"]) ?? string(from: receipt["auditEvent"]) ?? "",
            auditPlan: decodeAuditPlan(object["audit_plan"] as? [String: Any] ?? object["auditPlan"] as? [String: Any]),
            steps: stepObjects.compactMap(decodeProviderPlanStep)
        )
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
            stringValue: number(from: object["value"]) == nil ? stringLiteral(from: object["value"]) : nil,
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

    private static func decodeControlAction(_ object: [String: Any]) -> SystemTelemetryControlAction? {
        guard let id = string(from: object["id"]) else {
            return nil
        }
        return SystemTelemetryControlAction(
            id: id,
            family: string(from: object["family"]) ?? "",
            label: string(from: object["label"]) ?? id,
            targetMetricKeys: stringArray(from: object["target_metric_keys"]) ?? stringArray(from: object["targetMetricKeys"]) ?? [],
            requiresSignedHostBroker: bool(from: object["requires_signed_host_broker"]) ?? bool(from: object["requiresSignedHostBroker"]) ?? true,
            requiresConfirmation: bool(from: object["requires_confirmation"]) ?? bool(from: object["requiresConfirmation"]) ?? true,
            requiredGrants: stringArray(from: object["required_grants"]) ?? stringArray(from: object["requiredGrants"]) ?? [],
            riskTier: string(from: object["risk_tier"]) ?? string(from: object["riskTier"]) ?? "",
            availability: string(from: object["availability"]) ?? "",
            auditEvent: string(from: object["audit_event"]) ?? string(from: object["auditEvent"]) ?? "",
            description: string(from: object["description"]) ?? ""
        )
    }

    private static func decodeProvider(_ object: [String: Any]) -> SystemTelemetryProvider? {
        guard let id = string(from: object["id"]) else {
            return nil
        }
        return SystemTelemetryProvider(
            id: id,
            kind: string(from: object["kind"]) ?? "",
            label: string(from: object["label"]) ?? id,
            mode: string(from: object["mode"]) ?? "",
            status: string(from: object["status"]) ?? "",
            metricKeys: stringArray(from: object["metric_keys"]) ?? stringArray(from: object["metricKeys"]) ?? stringArray(from: object["metrics"]) ?? [],
            widgetIds: stringArray(from: object["widget_ids"]) ?? stringArray(from: object["widgetIds"]) ?? [],
            capabilities: stringArray(from: object["capabilities"]) ?? [],
            defaultEnabled: bool(from: object["default_enabled"]) ?? bool(from: object["defaultEnabled"]) ?? false,
            privacyTier: string(from: object["privacy_tier"]) ?? string(from: object["privacyTier"]) ?? "",
            requiresGrant: string(from: object["requires_grant"]) ?? string(from: object["requiresGrant"]),
            credentialRefRequired: bool(from: object["credential_ref_required"]) ?? bool(from: object["credentialRefRequired"]) ?? false,
            freshnessMS: integer(from: object["freshness_ms"]) ?? integer(from: object["freshnessMs"]) ?? 0,
            description: string(from: object["description"]) ?? ""
        )
    }

    private static func decodeHistoryChart(_ object: [String: Any], fallbackMetricKey: String) -> SystemTelemetryHistoryChart {
        let points = (object["points"] as? [[String: Any]] ?? []).compactMap(decodeHistoryPoint)
        return SystemTelemetryHistoryChart(
            kind: string(from: object["kind"]) ?? "line",
            metricKey: string(from: object["metricKey"]) ?? string(from: object["metric_key"]) ?? fallbackMetricKey,
            unit: string(from: object["unit"]) ?? "",
            source: string(from: object["source"]) ?? "empty",
            points: points,
            empty: bool(from: object["empty"]) ?? points.isEmpty
        )
    }

    private static func decodeHistoryPoint(_ object: [String: Any]) -> SystemTelemetryHistoryPoint? {
        guard let timestamp = number(from: object["t"]) ?? number(from: object["timestampMS"]) ?? number(from: object["timestamp_ms"]),
              let value = number(from: object["value"]) else {
            return nil
        }
        return SystemTelemetryHistoryPoint(
            timestampMS: timestamp,
            value: value,
            sourceID: string(from: object["sourceId"]) ?? string(from: object["source_id"]) ?? "",
            count: integer(from: object["count"])
        )
    }

    private static func decodeControlPlanStep(_ object: [String: Any]) -> SystemTelemetryControlPlanStep? {
        guard let id = string(from: object["id"]) else {
            return nil
        }
        return SystemTelemetryControlPlanStep(
            id: id,
            status: string(from: object["status"]) ?? "pending",
            owner: string(from: object["owner"]) ?? "signed_host_broker",
            reason: string(from: object["reason"])
        )
    }

    private static func decodeProviderPlanStep(_ object: [String: Any]) -> SystemTelemetryProviderPlanStep? {
        guard let id = string(from: object["id"]) else {
            return nil
        }
        return SystemTelemetryProviderPlanStep(
            id: id,
            status: string(from: object["status"]) ?? "pending",
            owner: string(from: object["owner"]) ?? "provider_broker"
        )
    }

    private static func redactedCredentialRef(from request: [String: Any]) -> String? {
        guard let credentialRef = string(from: request["credential_ref"]) ?? string(from: request["credentialRef"]),
              !credentialRef.isEmpty else {
            return nil
        }
        return "provided_redacted"
    }

    private static func decodeAuditPlan(_ object: [String: Any]?) -> SystemTelemetryPlanAuditProjection? {
        guard let object else {
            return nil
        }
        let redaction = object["redaction"] as? [String: Any] ?? [:]
        return SystemTelemetryPlanAuditProjection(
            status: string(from: object["status"]) ?? "planned",
            durable: bool(from: object["durable"]) ?? false,
            event: string(from: object["event"]) ?? "",
            outcome: string(from: object["outcome"]) ?? "blocked",
            receiptStatus: string(from: object["receipt_status"]) ?? string(from: object["receiptStatus"]) ?? "not_issued",
            note: string(from: object["note"]) ?? "",
            redaction: SystemTelemetryPlanAuditRedaction(
                credentialRefRedacted: bool(from: redaction["credential_ref_redacted"]) ?? bool(from: redaction["credentialRefRedacted"]) ?? false,
                preciseLocationRedacted: bool(from: redaction["precise_location_redacted"]) ?? bool(from: redaction["preciseLocationRedacted"]) ?? false,
                targetRedacted: bool(from: redaction["target_redacted"]) ?? bool(from: redaction["targetRedacted"]) ?? false,
                valueRedacted: bool(from: redaction["value_redacted"]) ?? bool(from: redaction["valueRedacted"]) ?? false,
                sensitiveDetailRedacted: bool(from: redaction["sensitive_detail_redacted"]) ?? bool(from: redaction["sensitiveDetailRedacted"]) ?? false
            )
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
    @Published private(set) var allWidgets: [SystemTelemetryWidget] = []
    @Published private(set) var widgets: [SystemTelemetryWidget] = []
    @Published private(set) var panelWidgets: [SystemTelemetryWidget] = []
    @Published private(set) var providers: [SystemTelemetryProvider] = []
    @Published private(set) var snapshot: SystemTelemetrySnapshotState?
    @Published private(set) var histories: [String: SystemTelemetryHistory] = [:]
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRefreshing = false

    private let bridge: SystemTelemetryBridge
    private let configuration: () -> SystemTelemetryMenuBarConfiguration

    init(
        bridge: SystemTelemetryBridge,
        configuration: @escaping () -> SystemTelemetryMenuBarConfiguration = { .default }
    ) {
        self.bridge = bridge
        self.configuration = configuration
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            async let nextWidgets = bridge.widgets()
            async let nextSnapshot = bridge.snapshot()
            async let nextProviders = loadProviders()
            let currentConfiguration = configuration()
            let widgetCatalog = try await nextWidgets
            let enabledWidgets = widgetCatalog.filter {
                currentConfiguration.isEnabled($0)
            }
            async let nextHistories = loadHistories(for: enabledWidgets)
            allWidgets = widgetCatalog
            widgets = enabledWidgets.filter {
                $0.placement == "menu_bar" || $0.placement == "both"
            }
            panelWidgets = enabledWidgets.filter {
                $0.placement == "panel" || $0.placement == "both"
            }
            providers = await nextProviders
            snapshot = try await nextSnapshot
            histories = await nextHistories
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadHistories(for widgets: [SystemTelemetryWidget]) async -> [String: SystemTelemetryHistory] {
        let metricKeys = Set(widgets.filter { Self.supportsHistoryGraph($0) }.flatMap(\.metricKeys))
        guard !metricKeys.isEmpty else { return [:] }

        var next: [String: SystemTelemetryHistory] = [:]
        for metricKey in metricKeys.sorted() {
            do {
                let history = try await bridge.history(metricKey: metricKey)
                if !history.chart.points.isEmpty {
                    next[metricKey] = history
                }
            } catch {
                continue
            }
        }
        return next
    }

    func providerStatusRows(limit: Int = 5) -> [String] {
        providers.prefix(limit).map { provider in
            let status = Self.statusTitle(provider.status)
            if let grant = provider.requiresGrant, !grant.isEmpty {
                return "\(provider.label): \(status) - \(grant)"
            }
            return "\(provider.label): \(status)"
        }
    }

    var shouldShowCombinedPanel: Bool {
        !panelWidgets.isEmpty
    }

    func combinedPanelTitle() -> String {
        switch combinedPanelSeverity() {
        case .normal:
            return "System OK"
        case .warning:
            return "System WARN"
        case .critical:
            return "System HIGH"
        case .unavailable:
            return "System --"
        }
    }

    func combinedPanelRows(limit: Int = 8) -> [String] {
        panelWidgets.prefix(limit).map { title(for: $0) }
    }

    func combinedPanelSeverity() -> SystemTelemetryMenuBarSeverity {
        let severities = panelWidgets.map { severity(for: $0) }
        if severities.contains(.critical) { return .critical }
        if severities.contains(.warning) { return .warning }
        if severities.contains(.normal) { return .normal }
        return .unavailable
    }

    private func loadProviders() async -> [SystemTelemetryProvider] {
        do {
            return try await bridge.providers()
        } catch {
            return []
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
        guard !rendered.isEmpty else {
            return widget.title
        }

        let joined = rendered.joined(separator: " ")
        switch widget.renderMode {
        case "icon":
            return "\(widget.title) \(Self.iconToken(for: widget, snapshot: snapshot))"
        case "sparkline":
            if let metricKey = widget.metricKeys.first,
               let sparkline = sparkline(for: metricKey) {
                return "\(widget.title) \(sparkline)"
            }
            return "\(widget.title) \(joined)"
        case "gauge":
            return "\(widget.title) \(joined)"
        case "threshold":
            return "\(widget.title) \(Self.thresholdToken(for: widget, snapshot: snapshot)) \(joined)"
        case "dropdown":
            return widget.title
        default:
            return joined
        }
    }

    func sparkline(for metricKey: String, width: Int = 8) -> String? {
        guard let history = histories[metricKey] else { return nil }
        return Self.sparkline(points: history.chart.points.map(\.value), width: width)
    }

    func historyGraph(for widget: SystemTelemetryWidget) -> SystemTelemetryHistory? {
        guard Self.supportsHistoryGraph(widget),
              let metricKey = widget.metricKeys.first,
              let history = histories[metricKey],
              history.chart.points.count >= 2 else {
            return nil
        }
        return history
    }

    func hasHistoryGraph(for widget: SystemTelemetryWidget) -> Bool {
        historyGraph(for: widget) != nil
    }

    func severity(for widget: SystemTelemetryWidget) -> SystemTelemetryMenuBarSeverity {
        guard let snapshot else {
            return .unavailable
        }
        guard let sample = widget.metricKeys.compactMap({ snapshot.sample(for: $0) }).first else {
            return .unavailable
        }
        switch sample.unit {
        case "percent":
            if sample.value >= 90 { return .critical }
            if sample.value >= 75 || sample.value <= 10 { return .warning }
            return .normal
        case "state":
            if sample.value >= 2 { return .critical }
            if sample.value >= 1 { return .warning }
            return .normal
        case "bytes":
            return sample.value < 10 * 1024 * 1024 * 1024 ? .warning : .normal
        case "string":
            return sample.stringValue?.isEmpty == false ? .normal : .unavailable
        default:
            return sample.value > 0 ? .normal : .unavailable
        }
    }

    private static func statusTitle(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { word in String(word.prefix(1)).uppercased() + word.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private static func compactValue(_ sample: SystemTelemetrySample) -> String {
        if let stringValue = sample.stringValue {
            return truncate(stringValue, limit: 24)
        }
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

    private static func truncate(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        let end = value.index(value.startIndex, offsetBy: limit)
        return String(value[..<end])
    }

    private static func sparkline(points: [Double], width: Int) -> String? {
        guard points.count >= 2, width > 0 else { return nil }
        let sampled = downsample(points: points, width: width)
        guard let minValue = sampled.min(),
              let maxValue = sampled.max() else {
            return nil
        }
        let span = max(maxValue - minValue, 0.0001)
        let ticks = Array("▁▂▃▄▅▆▇█")
        return String(sampled.map { value in
            let normalized = (value - minValue) / span
            let index = min(ticks.count - 1, max(0, Int((normalized * Double(ticks.count - 1)).rounded())))
            return ticks[index]
        })
    }

    private static func supportsHistoryGraph(_ widget: SystemTelemetryWidget) -> Bool {
        widget.renderMode == "sparkline" || widget.renderMode == "chart"
    }

    private static func downsample(points: [Double], width: Int) -> [Double] {
        guard points.count > width else { return points }
        return (0..<width).map { index in
            let sourceIndex = Int((Double(index) / Double(max(width - 1, 1))) * Double(points.count - 1))
            return points[sourceIndex]
        }
    }

    private static func iconToken(for widget: SystemTelemetryWidget, snapshot: SystemTelemetrySnapshotState) -> String {
        guard let sample = widget.metricKeys.compactMap({ snapshot.sample(for: $0) }).first else {
            return "--"
        }
        switch sample.unit {
        case "boolean":
            return sample.value > 0 ? "ON" : "OFF"
        case "state":
            return sample.value > 0 ? "!" : "OK"
        default:
            return sample.value > 0 ? "OK" : "--"
        }
    }

    private static func thresholdToken(for widget: SystemTelemetryWidget, snapshot: SystemTelemetrySnapshotState) -> String {
        guard let sample = widget.metricKeys.compactMap({ snapshot.sample(for: $0) }).first else {
            return "--"
        }
        switch sample.unit {
        case "percent":
            if sample.value >= 90 { return "HIGH" }
            if sample.value >= 75 { return "WARN" }
            if sample.value <= 10 { return "LOW" }
            return "OK"
        case "state":
            if sample.value >= 2 { return "HIGH" }
            if sample.value >= 1 { return "WARN" }
            return "OK"
        case "bytes":
            return sample.value < 10 * 1024 * 1024 * 1024 ? "LOW" : "OK"
        default:
            return sample.value > 0 ? "OK" : "LOW"
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

private func stringLiteral(from value: Any?) -> String? {
    guard let value = value as? String else {
        return nil
    }
    return value.isEmpty ? nil : value
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
