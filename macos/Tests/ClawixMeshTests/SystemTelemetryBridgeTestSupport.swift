import ClawHostKit
@testable import Clawix

actor TelemetryRequestCounter {
    private var widgets = 0
    private var snapshots = 0
    private var histories = 0

    func incrementWidgets() {
        widgets += 1
    }

    func incrementSnapshots() {
        snapshots += 1
    }

    func incrementHistories() {
        histories += 1
    }

    func counts() -> (widgets: Int, snapshots: Int, histories: Int) {
        (widgets, snapshots, histories)
    }
}

actor StringRecorder {
    private var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }

    func recorded() -> [String] {
        values
    }
}

@MainActor
final class StatusControllerProbe {
    var diagnosticsActivations = 0
    var recordCalls: [Bool] = []
    var renderCount = 0

    func record(forceHistory: Bool) async -> SystemTelemetryMonitorRecordResult {
        recordCalls.append(forceHistory)
        return SystemTelemetryMonitorRecordResult(
            status: .skipped,
            sampleCount: 0,
            rollupCount: 0,
            incidentCount: 0,
            dbPath: nil,
            reason: "test"
        )
    }
}

enum SystemTelemetryBridgeResponses {
    static func emptyProviders() -> CommandResponse {
        CommandResponse(
            ok: true,
            data: .object(["providers": .array([])]),
            error: nil,
            meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
        )
    }

    static func cpuTextWidget() -> CommandResponse {
        CommandResponse(
            ok: true,
            data: .object([
                "widgets": .array([
                    .object([
                        "id": .string("cpu-load"),
                        "title": .string("CPU"),
                        "placement": .string("menubar"),
                        "metricKey": .string("system.cpu.load1"),
                        "presentation": .string("text"),
                    ]),
                ]),
            ]),
            error: nil,
            meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
        )
    }

    static func cpuSnapshot(
        value: Double = 1.25,
        generatedAt: String = "2026-05-18T12:00:00Z"
    ) -> CommandResponse {
        CommandResponse(
            ok: true,
            data: .object([
                "generatedAt": .string(generatedAt),
                "samples": .array([
                    .object([
                        "key": .string("system.cpu.load1"),
                        "value": .number(value),
                        "unit": .string("load"),
                        "capturedAt": .string(generatedAt),
                    ]),
                ]),
                "unavailableMetrics": .array([]),
                "policy": .object(["defaultAgentAccess": .string("safe_read")]),
            ]),
            error: nil,
            meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
        )
    }

    static func history(metricKey: String = "system.cpu.load1", values: [Double] = [1, 2]) -> CommandResponse {
        CommandResponse(
            ok: true,
            data: .object([
                "metric": .object(["key": .string(metricKey)]),
                "rangeMs": .integer(3600000),
                "retention": .object(["status": .string("recorded")]),
                "chart": .object([
                    "kind": .string("line"),
                    "metricKey": .string(metricKey),
                    "unit": .string("count"),
                    "source": .string("metric_samples"),
                    "empty": .bool(false),
                    "points": .array(values.enumerated().map { index, value in
                        .object([
                            "t": .integer(index + 1),
                            "value": .number(value),
                            "sourceId": .string("system.telemetry.local"),
                        ])
                    }),
                ]),
            ]),
            error: nil,
            meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
        )
    }

    static func emptySnapshot() -> CommandResponse {
        CommandResponse(
            ok: true,
            data: .object([
                "generatedAt": .string("2026-05-18T12:00:00Z"),
                "samples": .array([]),
                "unavailableMetrics": .array([]),
                "policy": .object(["defaultAgentAccess": .string("safe_read")]),
            ]),
            error: nil,
            meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
        )
    }

    static func controlCatalog() -> CommandResponse {
        CommandResponse(
            ok: true,
            data: .object([
                "controls": .array([
                    .object([
                        "id": .string("system.display.set_brightness"),
                        "family": .string("display"),
                        "label": .string("Set display brightness"),
                        "targetMetricKeys": .array([
                            .string("system.display.brightness"),
                        ]),
                        "requiresSignedHostBroker": .bool(true),
                        "requiresConfirmation": .bool(false),
                        "requiredGrants": .array([
                            .string("system.display.control"),
                        ]),
                        "riskTier": .string("disruptive"),
                        "availability": .string("host_required"),
                        "auditEvent": .string("system.telemetry.control.display.set_brightness"),
                        "description": .string("Plan-only display control."),
                    ]),
                ]),
                "mutatesHardware": .bool(false),
            ]),
            error: nil,
            meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
        )
    }

    static func controlPlan() -> CommandResponse {
        CommandResponse(
            ok: true,
            data: .object([
                "schema_version": .integer(1),
                "id": .string("system-control-plan-system-audio-set_output_volume-1"),
                "status": .string("planned"),
                "will_execute": .bool(false),
                "external_pending": .bool(true),
                "action": .object([
                    "id": .string("system.audio.set_output_volume"),
                    "family": .string("audio"),
                    "label": .string("Set output volume"),
                    "target_metric_keys": .array([
                        .string("system.audio.output_volume"),
                    ]),
                    "requires_signed_host_broker": .bool(true),
                    "requires_confirmation": .bool(false),
                    "required_grants": .array([
                        .string("system.audio.control"),
                    ]),
                    "risk_tier": .string("low"),
                    "availability": .string("external_pending"),
                    "audit_event": .string("system.telemetry.control.audio.set_output_volume"),
                    "description": .string("Plan-only audio control."),
                ]),
                "request": .object([
                    "target": .string("default"),
                    "value": .string("35"),
                    "reason": .string("test"),
                ]),
                "broker": .object([
                    "status": .string("external_pending"),
                    "fail_closed": .bool(true),
                ]),
                "policy": .object([
                    "required_grants": .array([
                        .string("system.audio.control"),
                    ]),
                    "risk_tier": .string("low"),
                ]),
                "steps": .array([
                    .object([
                        "id": .string("execute_native_action"),
                        "owner": .string("signed_host_broker"),
                        "status": .string("blocked"),
                        "reason": .string("Native mutation is not available from this plan-only surface."),
                    ]),
                ]),
                "receipt": .object([
                    "status": .string("not_issued"),
                    "audit_event": .string("system.telemetry.control.audio.set_output_volume"),
                ]),
                "auditPlan": .object([
                    "status": .string("planned"),
                    "durable": .bool(false),
                    "event": .string("system.telemetry.control.audio.set_output_volume"),
                    "outcome": .string("blocked"),
                    "receiptStatus": .string("not_issued"),
                    "note": .string("Portable audit projection; local CLI or signed host records durable JSONL evidence."),
                    "redaction": .object([
                        "targetRedacted": .bool(true),
                        "valueRedacted": .bool(true),
                        "sensitiveDetailRedacted": .bool(true),
                    ]),
                ]),
            ]),
            error: nil,
            meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
        )
    }

    static func providerCatalog() -> CommandResponse {
        CommandResponse(
            ok: true,
            data: .object([
                "providers": .array([
                    .object([
                        "id": .string("context.weather.live"),
                        "kind": .string("weather"),
                        "label": .string("Live weather context"),
                        "mode": .string("live"),
                        "status": .string("external_pending"),
                        "metricKeys": .array([
                            .string("context.weather.temperature"),
                        ]),
                        "widgetIds": .array([
                            .string("weather-temperature"),
                        ]),
                        "capabilities": .array([
                            .string("snapshot"),
                            .string("history"),
                        ]),
                        "defaultEnabled": .bool(false),
                        "privacyTier": .string("precise_location"),
                        "requiresGrant": .string("weather.location.read"),
                        "credentialRefRequired": .bool(true),
                        "freshnessMs": .integer(900000),
                        "description": .string("Live provider slot."),
                        "adapterContract": .object([
                            "providerId": .string("context.weather.live"),
                            "adapterKind": .string("weather"),
                            "mode": .string("live"),
                            "input": .object([
                                "credentialRef": .string("required_redacted"),
                                "requiredGrants": .array([
                                    .string("weather.location.read"),
                                ]),
                                "networkAccess": .string("blocked_until_granted"),
                            ]),
                            "output": .object([
                                "metrics": .array([
                                    .string("context.weather.temperature"),
                                ]),
                                "sampleShape": .string("system_telemetry_metric_sample"),
                                "monitorWriteRequired": .bool(true),
                            ]),
                            "audit": .object([
                                "event": .string("system.telemetry.provider.weather.live"),
                                "receiptRequired": .bool(true),
                                "durableReceiptSource": .string("provider_broker_or_signed_host"),
                                "redaction": .object([
                                    "credentialRefRedacted": .bool(true),
                                    "preciseLocationRedacted": .bool(true),
                                ]),
                            ]),
                            "executionPolicy": .object([
                                "failClosed": .bool(true),
                                "externalPendingUntilReceipt": .bool(true),
                            ]),
                        ]),
                    ]),
                    .object([
                        "id": .string("system.sensors.signed"),
                        "kind": .string("hardware_sensor"),
                        "label": .string("Signed hardware sensor provider"),
                        "mode": .string("live"),
                        "status": .string("external_pending"),
                        "metrics": .array([
                            .string("system.sensor.temperature"),
                            .string("system.sensor.fan_speed"),
                        ]),
                        "widgetIds": .array([]),
                        "capabilities": .array([
                            .string("snapshot"),
                            .string("history"),
                        ]),
                        "defaultEnabled": .bool(false),
                        "privacyTier": .string("safe_aggregate"),
                        "requiresGrant": .string("system.sensor.read"),
                        "credentialRefRequired": .bool(false),
                        "freshnessMs": .integer(5000),
                        "description": .string("Signed sensor slot."),
                    ]),
                ]),
            ]),
            error: nil,
            meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
        )
    }

    static func providerPlan() -> CommandResponse {
        CommandResponse(
            ok: true,
            data: .object([
                "schemaVersion": .integer(1),
                "id": .string("system-provider-plan-system-sensors-signed-1"),
                "status": .string("planned"),
                "willConnect": .bool(false),
                "externalPending": .bool(true),
                "provider": .object([
                    "id": .string("system.sensors.signed"),
                    "kind": .string("hardware_sensor"),
                    "label": .string("Signed hardware sensor provider"),
                    "mode": .string("live"),
                    "status": .string("external_pending"),
                    "metricKeys": .string("[REDACTED]"),
                    "metrics": .array([
                        .string("system.sensor.temperature"),
                        .string("system.sensor.fan_speed"),
                    ]),
                    "widgetIds": .array([]),
                    "capabilities": .array([
                        .string("snapshot"),
                        .string("history"),
                    ]),
                    "defaultEnabled": .bool(false),
                    "privacyTier": .string("safe_aggregate"),
                    "requiresGrant": .string("system.sensor.read"),
                    "credentialRefRequired": .bool(false),
                    "freshnessMs": .integer(5000),
                    "description": .string("Signed sensor slot."),
                ]),
                "request": .object([
                    "credentialRef": .string("provided_redacted"),
                    "reason": .string("test"),
                ]),
                "broker": .object([
                    "status": .string("external_pending"),
                    "failClosed": .bool(true),
                ]),
                "policy": .object([
                    "requiredGrants": .array([
                        .string("system.sensor.read"),
                    ]),
                    "credentialRefRequired": .bool(false),
                    "privacyTier": .string("safe_aggregate"),
                    "networkAccess": .string("blocked_until_granted"),
                ]),
                "steps": .array([
                    .object([
                        "id": .string("resolve_credential_ref"),
                        "owner": .string("provider_broker"),
                        "status": .string("skipped"),
                    ]),
                    .object([
                        "id": .string("connect_provider"),
                        "owner": .string("provider_broker"),
                        "status": .string("blocked"),
                    ]),
                ]),
                "receipt": .object([
                    "status": .string("not_issued"),
                    "auditEvent": .string("system.telemetry.provider.hardware_sensor.live"),
                ]),
                "auditPlan": .object([
                    "status": .string("planned"),
                    "durable": .bool(false),
                    "event": .string("system.telemetry.provider.hardware_sensor.live"),
                    "outcome": .string("blocked"),
                    "receiptStatus": .string("not_issued"),
                    "note": .string("Portable audit projection; local CLI or signed host records durable JSONL evidence."),
                    "redaction": .object([
                        "credentialRefRedacted": .bool(true),
                        "preciseLocationRedacted": .bool(true),
                    ]),
                ]),
            ]),
            error: nil,
            meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
        )
    }
}

@MainActor
func makeStatusController(
    probe: StatusControllerProbe,
    counter: TelemetryRequestCounter = TelemetryRequestCounter(),
    isCapabilityVisible: @escaping @MainActor () -> Bool = { true }
) -> (SystemTelemetryStatusItemController, TelemetryRequestCounter) {
    let bridge = SystemTelemetryBridge { request in
        switch (request.resource, request.action) {
        case ("widgets", "list"):
            await counter.incrementWidgets()
            return SystemTelemetryBridgeResponses.cpuTextWidget()
        case ("providers", "list"):
            return SystemTelemetryBridgeResponses.emptyProviders()
        default:
            await counter.incrementSnapshots()
            return SystemTelemetryBridgeResponses.cpuSnapshot()
        }
    }
    let controller = SystemTelemetryStatusItemController(dependencies: .init(
        makeModel: { SystemTelemetryMenuBarModel(bridge: bridge) },
        recordIfDue: { forceHistory in await probe.record(forceHistory: forceHistory) },
        renderModel: { _ in probe.renderCount += 1 },
        isCapabilityVisible: isCapabilityVisible
    ))
    return (controller, counter)
}
