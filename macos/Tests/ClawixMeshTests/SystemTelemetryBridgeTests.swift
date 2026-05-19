import ClawHostKit
import XCTest
@testable import Clawix

final class SystemTelemetryBridgeTests: XCTestCase {
    func testDecodesSnapshotPolicySamplesAndUnavailableMetrics() throws {
        let response = CommandResponse(
            ok: true,
            data: .object([
                "captured_at": .string("2026-05-18T12:00:00Z"),
                "samples": .array([
                    .object([
                        "metric_key": .string("system.cpu.load1"),
                        "value": .number(1.25),
                        "unit": .string("load"),
                        "captured_at": .string("2026-05-18T12:00:00Z"),
                        "source": .string("macos_host"),
                        "confidence": .string("observed"),
                    ]),
                ]),
                "unavailable_metrics": .array([
                    .object([
                        "metric_key": .string("system.sensor.temperature"),
                        "availability": .string("host_required"),
                    ]),
                ]),
                "policy": .object([
                    "default_agent_access": .string("safe_read"),
                    "retention_owner": .string("monitor"),
                ]),
            ]),
            error: nil,
            meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
        )

        let snapshot = try SystemTelemetryBridge.decodeSnapshot(response)

        XCTAssertEqual(snapshot.capturedAt, "2026-05-18T12:00:00Z")
        XCTAssertEqual(snapshot.defaultAgentAccess, "safe_read")
        XCTAssertEqual(snapshot.retentionOwner, "monitor")
        XCTAssertEqual(snapshot.sample(for: "system.cpu.load1")?.value, 1.25)
        XCTAssertEqual(snapshot.unavailableMetricKeys, ["system.sensor.temperature"])
    }

    func testDecodesPortableCliSnapshotPayload() throws {
        let response = CommandResponse(
            ok: true,
            data: .object([
                "generatedAt": .string("2026-05-18T12:00:00Z"),
                "samples": .array([
                    .object([
                        "key": .string("system.memory.used"),
                        "value": .number(1024),
                        "unit": .string("bytes"),
                        "capturedAt": .string("2026-05-18T12:00:00Z"),
                        "source": .object([
                            "adapter": .string("node"),
                            "confidence": .string("official"),
                        ]),
                    ]),
                ]),
                "unavailableMetrics": .array([
                    .string("context.weather.temperature"),
                ]),
                "policy": .object([
                    "defaultAgentAccess": .string("safe_read"),
                ]),
            ]),
            error: nil,
            meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
        )

        let snapshot = try SystemTelemetryBridge.decodeSnapshot(response)

        XCTAssertEqual(snapshot.capturedAt, "2026-05-18T12:00:00Z")
        XCTAssertEqual(snapshot.sample(for: "system.memory.used")?.source, "node")
        XCTAssertEqual(snapshot.sample(for: "system.memory.used")?.confidence, "official")
        XCTAssertEqual(snapshot.unavailableMetricKeys, ["context.weather.temperature"])
    }

    func testDecodesMenuBarWidgets() throws {
        let response = CommandResponse(
            ok: true,
            data: .array([
                .object([
                    "id": .string("menu.cpu-memory"),
                    "title": .string("CPU + Memory"),
                    "placement": .string("menu_bar"),
                    "metric_keys": .array([
                        .string("system.cpu.load1"),
                        .string("system.memory.used"),
                    ]),
                    "render_mode": .string("compact"),
                    "refresh_interval_ms": .integer(2000),
                    "agent_visible": .bool(true),
                ]),
            ]),
            error: nil,
            meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
        )

        let widgets = try SystemTelemetryBridge.decodeWidgets(response)

        XCTAssertEqual(widgets.count, 1)
        XCTAssertEqual(widgets.first?.id, "menu.cpu-memory")
        XCTAssertEqual(widgets.first?.metricKeys, ["system.cpu.load1", "system.memory.used"])
        XCTAssertEqual(widgets.first?.refreshIntervalMS, 2000)
    }

    func testDecodesPortableCliWidgetListPayload() throws {
        let response = CommandResponse(
            ok: true,
            data: .object([
                "widgets": .array([
                    .object([
                        "id": .string("cpu-load"),
                        "title": .string("CPU"),
                        "placement": .string("both"),
                        "metricKey": .string("system.cpu.load1"),
                        "presentation": .string("sparkline"),
                        "enabledByDefault": .bool(true),
                    ]),
                    .object([
                        "id": .string("memory-used"),
                        "title": .string("Memory"),
                        "placement": .string("combined_panel"),
                        "metricKey": .string("system.memory.used"),
                        "presentation": .string("gauge"),
                    ]),
                ]),
            ]),
            error: nil,
            meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
        )

        let widgets = try SystemTelemetryBridge.decodeWidgets(response)

        XCTAssertEqual(widgets.count, 2)
        XCTAssertEqual(widgets[0].placement, "both")
        XCTAssertEqual(widgets[0].metricKeys, ["system.cpu.load1"])
        XCTAssertEqual(widgets[0].renderMode, "sparkline")
        XCTAssertEqual(widgets[1].placement, "panel")
    }

    func testDecodesHistoryChartPayload() throws {
        let response = CommandResponse(
            ok: true,
            data: .object([
                "metric": .object([
                    "key": .string("system.cpu.load1"),
                    "unit": .string("count"),
                ]),
                "rangeMs": .integer(3600000),
                "retention": .object([
                    "status": .string("recorded"),
                ]),
                "chart": .object([
                    "kind": .string("line"),
                    "metricKey": .string("system.cpu.load1"),
                    "unit": .string("count"),
                    "source": .string("metric_samples"),
                    "empty": .bool(false),
                    "points": .array([
                        .object([
                            "t": .integer(1),
                            "value": .number(1.0),
                            "sourceId": .string("system.telemetry.local"),
                        ]),
                        .object([
                            "t": .integer(2),
                            "value": .number(3.0),
                            "sourceId": .string("system.telemetry.local"),
                            "count": .integer(2),
                        ]),
                    ]),
                ]),
            ]),
            error: nil,
            meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
        )

        let history = try SystemTelemetryBridge.decodeHistory(response)

        XCTAssertEqual(history.metricKey, "system.cpu.load1")
        XCTAssertEqual(history.rangeMS, 3600000)
        XCTAssertEqual(history.retentionStatus, "recorded")
        XCTAssertEqual(history.chart.kind, "line")
        XCTAssertEqual(history.chart.source, "metric_samples")
        XCTAssertEqual(history.chart.points.map(\.value), [1.0, 3.0])
        XCTAssertEqual(history.chart.points[1].count, 2)
    }

    @MainActor
    func testHistoryReaderRunsClawSystemHistoryCommand() async throws {
        actor Capture {
            var calls: [[String]] = []

            func append(_ args: [String]) {
                calls.append(args)
            }
        }

        let capture = Capture()
        let reader = SystemTelemetryHistoryReader(
            runner: .init { args in
                await capture.append(args)
                return Data("""
                {
                  "ok": true,
                  "data": {
                    "metric": { "key": "system.cpu.load1", "unit": "count" },
                    "rangeMs": 3600000,
                    "retention": { "status": "recorded" },
                    "chart": {
                      "kind": "line",
                      "metricKey": "system.cpu.load1",
                      "unit": "count",
                      "source": "metric_samples",
                      "empty": false,
                      "points": [
                        { "t": 1, "value": 1, "sourceId": "system.telemetry.local" },
                        { "t": 2, "value": 3, "sourceId": "system.telemetry.local" }
                      ]
                    }
                  }
                }
                """.utf8)
            }
        )

        let payload = try await reader.historyPayload(metricKey: "system.cpu.load1", range: "24h")
        let history = try SystemTelemetryBridge.decodeHistory(CommandResponse(
            ok: true,
            data: payload,
            error: nil,
            meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
        ))

        XCTAssertEqual(history.chart.points.map(\.value), [1, 3])
        let calls = await capture.calls
        XCTAssertEqual(calls, [[
            "system",
            "history",
            "system.cpu.load1",
            "--range",
            "24h",
            "--json",
        ]])
    }

    func testDecodesControlCatalogAndPlanPayloads() throws {
        let controlsResponse = CommandResponse(
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

        let controls = try SystemTelemetryBridge.decodeControls(controlsResponse)

        XCTAssertEqual(controls.map(\.id), ["system.display.set_brightness"])
        XCTAssertEqual(controls[0].targetMetricKeys, ["system.display.brightness"])
        XCTAssertEqual(controls[0].requiresSignedHostBroker, true)
        XCTAssertEqual(controls[0].requiredGrants, ["system.display.control"])

        let planResponse = CommandResponse(
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
            ]),
            error: nil,
            meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
        )

        let plan = try SystemTelemetryBridge.decodeControlPlan(planResponse)

        XCTAssertEqual(plan.action.id, "system.audio.set_output_volume")
        XCTAssertEqual(plan.willExecute, false)
        XCTAssertEqual(plan.externalPending, true)
        XCTAssertEqual(plan.target, "default")
        XCTAssertEqual(plan.value, "35")
        XCTAssertEqual(plan.brokerStatus, "external_pending")
        XCTAssertEqual(plan.failClosed, true)
        XCTAssertEqual(plan.requiredGrants, ["system.audio.control"])
        XCTAssertEqual(plan.receiptStatus, "not_issued")
        XCTAssertEqual(plan.auditEvent, "system.telemetry.control.audio.set_output_volume")
        XCTAssertEqual(plan.steps.first?.status, "blocked")
    }

    func testDecodesProviderCatalogAndPlanPayloads() throws {
        let providersResponse = CommandResponse(
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

        let providers = try SystemTelemetryBridge.decodeProviders(providersResponse)

        XCTAssertEqual(providers.map(\.id), ["context.weather.live", "system.sensors.signed"])
        XCTAssertEqual(providers[0].metricKeys, ["context.weather.temperature"])
        XCTAssertEqual(providers[0].requiresGrant, "weather.location.read")
        XCTAssertEqual(providers[0].credentialRefRequired, true)
        XCTAssertEqual(providers[1].kind, "hardware_sensor")
        XCTAssertEqual(providers[1].metricKeys, ["system.sensor.temperature", "system.sensor.fan_speed"])
        XCTAssertEqual(providers[1].requiresGrant, "system.sensor.read")

        let planResponse = CommandResponse(
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
                    "credentialRef": .string("secret://sensor/local"),
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
            ]),
            error: nil,
            meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
        )

        let plan = try SystemTelemetryBridge.decodeProviderPlan(planResponse)

        XCTAssertEqual(plan.provider.id, "system.sensors.signed")
        XCTAssertEqual(plan.willConnect, false)
        XCTAssertEqual(plan.externalPending, true)
        XCTAssertEqual(plan.credentialRef, "secret://sensor/local")
        XCTAssertEqual(plan.reason, "test")
        XCTAssertEqual(plan.brokerStatus, "external_pending")
        XCTAssertEqual(plan.failClosed, true)
        XCTAssertEqual(plan.requiredGrants, ["system.sensor.read"])
        XCTAssertEqual(plan.credentialRefRequired, false)
        XCTAssertEqual(plan.networkAccess, "blocked_until_granted")
        XCTAssertEqual(plan.receiptStatus, "not_issued")
        XCTAssertEqual(plan.auditEvent, "system.telemetry.provider.hardware_sensor.live")
        XCTAssertEqual(plan.steps.map(\.status), ["skipped", "blocked"])
    }

    func testControlPlanBridgeSendsPlanOnlyRequestArguments() async throws {
        let bridge = SystemTelemetryBridge { request in
            XCTAssertEqual(request.resource, "controls")
            XCTAssertEqual(request.action, "plan")
            XCTAssertEqual(request.arguments["control_id"], "system.audio.set_output_volume")
            XCTAssertEqual(request.arguments["target"], "default")
            XCTAssertEqual(request.arguments["value"], "35")
            XCTAssertEqual(request.arguments["reason"], "test")

            return CommandResponse(
                ok: true,
                data: .object([
                    "schemaVersion": .integer(1),
                    "id": .string("system-control-plan-system-audio-set_output_volume-1"),
                    "status": .string("planned"),
                    "willExecute": .bool(false),
                    "externalPending": .bool(true),
                    "action": .object([
                        "id": .string("system.audio.set_output_volume"),
                        "family": .string("audio"),
                        "label": .string("Set output volume"),
                        "targetMetricKeys": .array([
                            .string("system.audio.output_volume"),
                        ]),
                        "requiresSignedHostBroker": .bool(true),
                        "requiresConfirmation": .bool(false),
                        "requiredGrants": .array([
                            .string("system.audio.control"),
                        ]),
                        "riskTier": .string("safe"),
                        "availability": .string("host_required"),
                        "auditEvent": .string("system.telemetry.control.audio.set_output_volume"),
                        "description": .string("Plan-only audio control."),
                    ]),
                    "request": .object([
                        "target": .string("default"),
                        "value": .string("35"),
                        "reason": .string("test"),
                    ]),
                    "broker": .object([
                        "status": .string("external_pending"),
                        "failClosed": .bool(true),
                    ]),
                    "policy": .object([
                        "requiredGrants": .array([
                            .string("system.audio.control"),
                        ]),
                        "riskTier": .string("safe"),
                    ]),
                    "steps": .array([]),
                    "receipt": .object([
                        "status": .string("not_issued"),
                        "auditEvent": .string("system.telemetry.control.audio.set_output_volume"),
                    ]),
                ]),
                error: nil,
                meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
            )
        }

        let plan = try await bridge.controlPlan(
            controlID: "system.audio.set_output_volume",
            target: "default",
            value: "35",
            reason: "test"
        )

        XCTAssertEqual(plan.action.id, "system.audio.set_output_volume")
        XCTAssertEqual(plan.willExecute, false)
        XCTAssertEqual(plan.failClosed, true)
    }

    func testProviderPlanBridgeSendsPlanOnlyRequestArguments() async throws {
        let bridge = SystemTelemetryBridge { request in
            XCTAssertEqual(request.resource, "providers")
            XCTAssertEqual(request.action, "plan")
            XCTAssertEqual(request.arguments["provider_id"], "context.weather.live")
            XCTAssertEqual(request.arguments["credential_ref"], "secret://weather/local")
            XCTAssertEqual(request.arguments["reason"], "test")

            return CommandResponse(
                ok: true,
                data: .object([
                    "schema_version": .integer(1),
                    "id": .string("system-provider-plan-context-weather-live-1"),
                    "status": .string("planned"),
                    "will_connect": .bool(false),
                    "external_pending": .bool(true),
                    "provider": .object([
                        "id": .string("context.weather.live"),
                        "kind": .string("weather"),
                        "label": .string("Live weather context"),
                        "mode": .string("live"),
                        "status": .string("external_pending"),
                        "metric_keys": .array([
                            .string("context.weather.temperature"),
                        ]),
                        "widget_ids": .array([
                            .string("weather-temperature"),
                        ]),
                        "capabilities": .array([
                            .string("snapshot"),
                            .string("history"),
                        ]),
                        "default_enabled": .bool(false),
                        "privacy_tier": .string("precise_location"),
                        "requires_grant": .string("weather.location.read"),
                        "credential_ref_required": .bool(true),
                        "freshness_ms": .integer(900000),
                        "description": .string("Live provider slot."),
                    ]),
                    "request": .object([
                        "credential_ref": .string("secret://weather/local"),
                        "reason": .string("test"),
                    ]),
                    "broker": .object([
                        "status": .string("external_pending"),
                        "fail_closed": .bool(true),
                    ]),
                    "policy": .object([
                        "required_grants": .array([
                            .string("weather.location.read"),
                        ]),
                        "credential_ref_required": .bool(true),
                        "privacy_tier": .string("precise_location"),
                        "network_access": .string("blocked_until_granted"),
                    ]),
                    "steps": .array([
                        .object([
                            "id": .string("connect_provider"),
                            "owner": .string("provider_broker"),
                            "status": .string("blocked"),
                        ]),
                    ]),
                    "receipt": .object([
                        "status": .string("not_issued"),
                        "audit_event": .string("system.telemetry.provider.weather.live"),
                    ]),
                ]),
                error: nil,
                meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
            )
        }

        let plan = try await bridge.providerPlan(
            providerID: "context.weather.live",
            credentialRef: "secret://weather/local",
            reason: "test"
        )

        XCTAssertEqual(plan.provider.id, "context.weather.live")
        XCTAssertEqual(plan.requiredGrants, ["weather.location.read"])
        XCTAssertEqual(plan.credentialRefRequired, true)
        XCTAssertEqual(plan.steps.first?.status, "blocked")
    }

    @MainActor
    func testMenuBarModelRendersCompactValues() async {
        let bridge = SystemTelemetryBridge { request in
            switch (request.resource, request.action) {
            case ("widgets", "list"):
                return CommandResponse(
                    ok: true,
                    data: .array([
                        .object([
                            "id": .string("menu.cpu-memory"),
                            "title": .string("CPU + Memory"),
                            "placement": .string("menu_bar"),
                            "metric_keys": .array([
                                .string("system.cpu.load1"),
                            ]),
                            "render_mode": .string("compact"),
                            "refresh_interval_ms": .integer(2000),
                            "agent_visible": .bool(true),
                        ]),
                    ]),
                    error: nil,
                    meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
                )
            default:
                return CommandResponse(
                    ok: true,
                    data: .object([
                        "captured_at": .string("2026-05-18T12:00:00Z"),
                        "samples": .array([
                            .object([
                                "metric_key": .string("system.cpu.load1"),
                                "value": .number(1.25),
                                "unit": .string("load"),
                                "captured_at": .string("2026-05-18T12:00:00Z"),
                                "source": .string("macos_host"),
                                "confidence": .string("observed"),
                            ]),
                        ]),
                        "unavailable_metrics": .array([]),
                        "policy": .object([
                            "default_agent_access": .string("safe_read"),
                            "retention_owner": .string("monitor"),
                        ]),
                    ]),
                    error: nil,
                    meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
                )
            }
        }
        let model = SystemTelemetryMenuBarModel(bridge: bridge)

        await model.refresh()

        XCTAssertEqual(model.widgets.count, 1)
        XCTAssertEqual(model.title(for: model.widgets[0]), "1.25")
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testMenuBarModelRendersSparklineFromHistoryChart() async throws {
        let bridge = SystemTelemetryBridge { request in
            switch (request.resource, request.action) {
            case ("widgets", "list"):
                return CommandResponse(
                    ok: true,
                    data: .object([
                        "widgets": .array([
                            .object([
                                "id": .string("cpu-load"),
                                "title": .string("CPU"),
                                "placement": .string("both"),
                                "metricKey": .string("system.cpu.load1"),
                                "presentation": .string("sparkline"),
                            ]),
                        ]),
                    ]),
                    error: nil,
                    meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
                )
            case ("history", "get"):
                XCTAssertEqual(request.arguments["metric_key"], "system.cpu.load1")
                XCTAssertEqual(request.arguments["range"], "1h")
                return CommandResponse(
                    ok: true,
                    data: .object([
                        "metric": .object([
                            "key": .string("system.cpu.load1"),
                        ]),
                        "rangeMs": .integer(3600000),
                        "retention": .object([
                            "status": .string("recorded"),
                        ]),
                        "chart": .object([
                            "kind": .string("line"),
                            "metricKey": .string("system.cpu.load1"),
                            "unit": .string("count"),
                            "source": .string("metric_samples"),
                            "empty": .bool(false),
                            "points": .array([
                                .object(["t": .integer(1), "value": .number(1), "sourceId": .string("system.telemetry.local")]),
                                .object(["t": .integer(2), "value": .number(2), "sourceId": .string("system.telemetry.local")]),
                                .object(["t": .integer(3), "value": .number(3), "sourceId": .string("system.telemetry.local")]),
                                .object(["t": .integer(4), "value": .number(4), "sourceId": .string("system.telemetry.local")]),
                            ]),
                        ]),
                    ]),
                    error: nil,
                    meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
                )
            default:
                return CommandResponse(
                    ok: true,
                    data: .object([
                        "generatedAt": .string("2026-05-18T12:00:00Z"),
                        "samples": .array([
                            .object([
                                "key": .string("system.cpu.load1"),
                                "value": .number(1.25),
                                "unit": .string("load"),
                                "capturedAt": .string("2026-05-18T12:00:00Z"),
                                "source": .object([
                                    "adapter": .string("node"),
                                    "confidence": .string("official"),
                                ]),
                            ]),
                        ]),
                        "unavailableMetrics": .array([]),
                        "policy": .object([
                            "defaultAgentAccess": .string("safe_read"),
                        ]),
                    ]),
                    error: nil,
                    meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
                )
            }
        }
        let model = SystemTelemetryMenuBarModel(bridge: bridge)

        await model.refresh()

        XCTAssertEqual(model.histories["system.cpu.load1"]?.chart.source, "metric_samples")
        XCTAssertEqual(model.sparkline(for: "system.cpu.load1", width: 4), "▁▃▆█")
        XCTAssertEqual(model.title(for: model.widgets[0]), "CPU ▁▃▆█")
        let graphHistory = model.historyGraph(for: model.widgets[0])
        XCTAssertEqual(graphHistory?.chart.points.count, 4)
        XCTAssertTrue(model.hasHistoryGraph(for: model.widgets[0]))
        let graph = SystemTelemetryHistoryGraphView(history: try XCTUnwrap(graphHistory), title: "CPU")
        XCTAssertEqual(graph.pointCount, 4)
        XCTAssertEqual(graph.accessibilityLabel(), "CPU history graph")
    }

    @MainActor
    func testMenuBarModelIncludesPortableBothPlacement() async {
        let bridge = SystemTelemetryBridge { request in
            switch (request.resource, request.action) {
            case ("widgets", "list"):
                return CommandResponse(
                    ok: true,
                    data: .object([
                        "widgets": .array([
                            .object([
                                "id": .string("cpu-load"),
                                "title": .string("CPU"),
                                "placement": .string("both"),
                                "metricKey": .string("system.cpu.load1"),
                                "presentation": .string("sparkline"),
                            ]),
                            .object([
                                "id": .string("power-uptime"),
                                "title": .string("Uptime"),
                                "placement": .string("combined_panel"),
                                "metricKey": .string("system.power.uptime"),
                                "presentation": .string("text"),
                            ]),
                            .object([
                                "id": .string("weather-temperature"),
                                "title": .string("Weather"),
                                "placement": .string("menubar"),
                                "metricKey": .string("context.weather.temperature"),
                                "presentation": .string("text"),
                                "enabledByDefault": .bool(false),
                            ]),
                        ]),
                    ]),
                    error: nil,
                    meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
                )
            default:
                return CommandResponse(
                    ok: true,
                    data: .object([
                        "generatedAt": .string("2026-05-18T12:00:00Z"),
                        "samples": .array([
                            .object([
                                "key": .string("system.cpu.load1"),
                                "value": .number(1.25),
                                "unit": .string("load"),
                                "capturedAt": .string("2026-05-18T12:00:00Z"),
                                "source": .object([
                                    "adapter": .string("node"),
                                    "confidence": .string("official"),
                                ]),
                            ]),
                        ]),
                        "unavailableMetrics": .array([]),
                        "policy": .object([
                            "defaultAgentAccess": .string("safe_read"),
                        ]),
                    ]),
                    error: nil,
                    meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
                )
            }
        }
        let model = SystemTelemetryMenuBarModel(bridge: bridge)

        await model.refresh()

        XCTAssertEqual(model.widgets.map(\.id), ["cpu-load"])
        XCTAssertEqual(model.panelWidgets.map(\.id), ["cpu-load", "power-uptime"])
        XCTAssertEqual(model.title(for: model.widgets[0]), "CPU 1.25")
        XCTAssertEqual(model.title(for: model.panelWidgets[1]), "Uptime")
        XCTAssertTrue(model.shouldShowCombinedPanel)
        XCTAssertEqual(model.combinedPanelTitle(), "System OK")
        XCTAssertEqual(model.combinedPanelRows(), ["CPU 1.25", "Uptime"])
    }

    @MainActor
    func testMenuBarModelUsesHostSpecificWidgetConfiguration() async {
        let bridge = SystemTelemetryBridge { request in
            switch (request.resource, request.action) {
            case ("widgets", "list"):
                return CommandResponse(
                    ok: true,
                    data: .object([
                        "widgets": .array([
                            .object([
                                "id": .string("cpu-load"),
                                "title": .string("CPU"),
                                "placement": .string("both"),
                                "metricKey": .string("system.cpu.load1"),
                                "presentation": .string("sparkline"),
                            ]),
                            .object([
                                "id": .string("weather-temperature"),
                                "title": .string("Weather"),
                                "placement": .string("menubar"),
                                "metricKey": .string("context.weather.temperature"),
                                "presentation": .string("text"),
                                "enabledByDefault": .bool(false),
                            ]),
                        ]),
                    ]),
                    error: nil,
                    meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
                )
            default:
                return CommandResponse(
                    ok: true,
                    data: .object([
                        "generatedAt": .string("2026-05-18T12:00:00Z"),
                        "samples": .array([
                            .object([
                                "key": .string("context.weather.temperature"),
                                "value": .number(22),
                                "unit": .string("celsius"),
                                "capturedAt": .string("2026-05-18T12:00:00Z"),
                                "source": .object([
                                    "adapter": .string("provider"),
                                    "confidence": .string("provider"),
                                ]),
                            ]),
                        ]),
                        "unavailableMetrics": .array([]),
                        "policy": .object([
                            "defaultAgentAccess": .string("safe_read"),
                        ]),
                    ]),
                    error: nil,
                    meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
                )
            }
        }
        let model = SystemTelemetryMenuBarModel(
            bridge: bridge,
            configuration: { SystemTelemetryMenuBarConfiguration(enabledWidgetIDs: ["weather-temperature"]) }
        )

        await model.refresh()

        XCTAssertEqual(model.widgets.map(\.id), ["weather-temperature"])
        XCTAssertEqual(model.title(for: model.widgets[0]), "22")
    }

    @MainActor
    func testMenuBarModelRendersStringSamplesForTextWidgets() async {
        let bridge = SystemTelemetryBridge { request in
            switch (request.resource, request.action) {
            case ("widgets", "list"):
                return CommandResponse(
                    ok: true,
                    data: .object([
                        "widgets": .array([
                            .object([
                                "id": .string("focus-mode"),
                                "title": .string("Focus"),
                                "placement": .string("menubar"),
                                "metricKey": .string("system.focus.mode"),
                                "presentation": .string("text"),
                                "enabledByDefault": .bool(false),
                            ]),
                        ]),
                    ]),
                    error: nil,
                    meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
                )
            default:
                return CommandResponse(
                    ok: true,
                    data: .object([
                        "generatedAt": .string("2026-05-19T12:00:00Z"),
                        "samples": .array([
                            .object([
                                "key": .string("system.focus.mode"),
                                "value": .string("work"),
                                "unit": .string("string"),
                                "capturedAt": .string("2026-05-19T12:00:00Z"),
                                "source": .object([
                                    "adapter": .string("provider"),
                                    "confidence": .string("provider"),
                                ]),
                            ]),
                        ]),
                        "unavailableMetrics": .array([]),
                        "policy": .object([
                            "defaultAgentAccess": .string("safe_read"),
                        ]),
                    ]),
                    error: nil,
                    meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
                )
            }
        }
        let model = SystemTelemetryMenuBarModel(
            bridge: bridge,
            configuration: { SystemTelemetryMenuBarConfiguration(enabledWidgetIDs: ["focus-mode"]) }
        )

        await model.refresh()

        XCTAssertEqual(model.widgets.map(\.id), ["focus-mode"])
        XCTAssertEqual(model.snapshot?.sample(for: "system.focus.mode")?.stringValue, "work")
        XCTAssertEqual(model.title(for: model.widgets[0]), "work")
        XCTAssertEqual(model.severity(for: model.widgets[0]), .normal)
    }

    func testMenuBarConfigurationPersistsHostSpecificWidgetIDs() {
        let suiteName = "SystemTelemetryBridgeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let empty = SystemTelemetryMenuBarConfiguration.load(defaults: defaults)
        XCTAssertNil(empty.enabledWidgetIDs)

        SystemTelemetryMenuBarConfiguration(enabledWidgetIDs: ["cpu-load", "agent-runs-active"]).save(defaults: defaults)

        let loaded = SystemTelemetryMenuBarConfiguration.load(defaults: defaults)
        XCTAssertEqual(loaded.enabledWidgetIDs, Set(["agent-runs-active", "cpu-load"]))
    }

    func testMenuBarConfigurationTogglesFromDefaultWidgetCatalog() {
        let widgets = [
            SystemTelemetryWidget(
                id: "cpu-load",
                title: "CPU",
                placement: "menu_bar",
                metricKeys: ["system.cpu.load1"],
                renderMode: "sparkline",
                refreshIntervalMS: 5000,
                agentVisible: true
            ),
            SystemTelemetryWidget(
                id: "weather-temperature",
                title: "Weather",
                placement: "menu_bar",
                metricKeys: ["context.weather.temperature"],
                renderMode: "text",
                refreshIntervalMS: 5000,
                agentVisible: false
            ),
        ]

        let enabled = SystemTelemetryMenuBarConfiguration.default.toggling(
            widgetID: "weather-temperature",
            widgets: widgets
        )
        XCTAssertEqual(enabled.enabledWidgetIDs, Set(["cpu-load", "weather-temperature"]))

        let disabled = enabled.toggling(widgetID: "cpu-load", widgets: widgets)
        XCTAssertEqual(disabled.enabledWidgetIDs, Set(["weather-temperature"]))
    }

    @MainActor
    func testMenuBarModelLoadsProviderStatusRows() async {
        let bridge = SystemTelemetryBridge { request in
            switch (request.resource, request.action) {
            case ("widgets", "list"):
                return CommandResponse(
                    ok: true,
                    data: .object([
                        "widgets": .array([
                            .object([
                                "id": .string("cpu-load"),
                                "title": .string("CPU"),
                                "placement": .string("menubar"),
                                "metricKey": .string("system.cpu.load1"),
                                "presentation": .string("sparkline"),
                            ]),
                        ]),
                    ]),
                    error: nil,
                    meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
                )
            case ("providers", "list"):
                return CommandResponse(
                    ok: true,
                    data: .object([
                        "providers": .array([
                            .object([
                                "id": .string("context.weather.live"),
                                "kind": .string("weather"),
                                "label": .string("Live weather context"),
                                "mode": .string("live"),
                                "status": .string("external_pending"),
                                "metric_keys": .array([
                                    .string("context.weather.temperature"),
                                ]),
                                "widget_ids": .array([
                                    .string("weather-temperature"),
                                ]),
                                "capabilities": .array([
                                    .string("snapshot"),
                                    .string("history"),
                                ]),
                                "default_enabled": .bool(false),
                                "privacy_tier": .string("precise_location"),
                                "requires_grant": .string("weather.location.read"),
                                "credential_ref_required": .bool(true),
                                "freshness_ms": .integer(900000),
                                "description": .string("Live provider slot."),
                            ]),
                            .object([
                                "id": .string("system.sensors.signed"),
                                "kind": .string("hardware_sensor"),
                                "label": .string("Signed hardware sensor provider"),
                                "mode": .string("live"),
                                "status": .string("external_pending"),
                                "metric_keys": .array([
                                    .string("system.sensor.temperature"),
                                    .string("system.sensor.fan_speed"),
                                ]),
                                "capabilities": .array([
                                    .string("snapshot"),
                                    .string("history"),
                                ]),
                                "default_enabled": .bool(false),
                                "privacy_tier": .string("safe_aggregate"),
                                "requires_grant": .string("system.sensor.read"),
                                "credential_ref_required": .bool(false),
                                "freshness_ms": .integer(5000),
                                "description": .string("Signed sensor provider slot."),
                            ]),
                        ]),
                    ]),
                    error: nil,
                    meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
                )
            default:
                return CommandResponse(
                    ok: true,
                    data: .object([
                        "generatedAt": .string("2026-05-19T12:00:00Z"),
                        "samples": .array([
                            .object([
                                "key": .string("system.cpu.load1"),
                                "value": .number(1.25),
                                "unit": .string("load"),
                                "capturedAt": .string("2026-05-19T12:00:00Z"),
                            ]),
                        ]),
                        "unavailableMetrics": .array([]),
                        "policy": .object([
                            "defaultAgentAccess": .string("safe_read"),
                        ]),
                    ]),
                    error: nil,
                    meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
                )
            }
        }
        let model = SystemTelemetryMenuBarModel(bridge: bridge)

        await model.refresh()

        XCTAssertEqual(model.providers.map(\.id), ["context.weather.live", "system.sensors.signed"])
        XCTAssertEqual(model.providerStatusRows(), [
            "Live weather context: External Pending - weather.location.read",
            "Signed hardware sensor provider: External Pending - system.sensor.read",
        ])
    }

    @MainActor
    func testMonitorRecorderRecordsHostSnapshotThroughClawCLI() async throws {
        actor Capture {
            var calls: [[String]] = []

            func append(_ args: [String]) {
                calls.append(args)
            }
        }

        let capture = Capture()
        let recorder = SystemTelemetryMonitorRecorder(
            runner: .init { args in
                await capture.append(args)
                return Data("""
                {
                  "ok": true,
                  "data": {
                    "recorded": {
                      "store": "monitor.sqlite",
                      "dbPath": "/tmp/monitor.sqlite",
                      "sourceId": "system.telemetry.local",
                      "sampleCount": 3,
                      "rollupCount": 3,
                      "incidentCount": 1
                    }
                  }
                }
                """.utf8)
            },
            hostCommandProvider: { "/tmp/claw-host" },
            minimumInterval: 60
        )

        let first = await recorder.recordIfDue(now: Date(timeIntervalSince1970: 100))
        let second = await recorder.recordIfDue(now: Date(timeIntervalSince1970: 120))
        let third = await recorder.recordIfDue(now: Date(timeIntervalSince1970: 170))

        XCTAssertEqual(first.status, .recorded)
        XCTAssertEqual(first.sampleCount, 3)
        XCTAssertEqual(first.rollupCount, 3)
        XCTAssertEqual(first.incidentCount, 1)
        XCTAssertEqual(first.dbPath, "/tmp/monitor.sqlite")
        XCTAssertEqual(second.status, .skipped)
        XCTAssertEqual(second.reason, "minimum_interval")
        XCTAssertEqual(third.status, .recorded)
        let calls = await capture.calls
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0], [
            "system",
            "snapshot",
            "--source",
            "host",
            "--host-command",
            "/tmp/claw-host",
            "--record",
            "true",
            "--json",
        ])
    }

    @MainActor
    func testMonitorRecorderReportsUnavailableWithoutHostCommand() async {
        let recorder = SystemTelemetryMonitorRecorder(
            runner: .init { _ in Data() },
            hostCommandProvider: { nil },
            minimumInterval: 60
        )

        let result = await recorder.recordIfDue(now: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(result.status, .unavailable)
        XCTAssertEqual(result.reason, "host_command_unavailable")
    }

    @MainActor
    func testMenuBarModelRendersPresentationModes() async {
        let bridge = SystemTelemetryBridge { request in
            switch (request.resource, request.action) {
            case ("widgets", "list"):
                return CommandResponse(
                    ok: true,
                    data: .object([
                        "widgets": .array([
                            .object([
                                "id": .string("memory-used"),
                                "title": .string("Memory"),
                                "placement": .string("menubar"),
                                "metricKey": .string("system.memory.used"),
                                "presentation": .string("gauge"),
                            ]),
                            .object([
                                "id": .string("disk-free"),
                                "title": .string("Disk"),
                                "placement": .string("menubar"),
                                "metricKey": .string("system.disk.free"),
                                "presentation": .string("threshold"),
                            ]),
                            .object([
                                "id": .string("build-status"),
                                "title": .string("Build"),
                                "placement": .string("menubar"),
                                "metricKey": .string("context.build.status"),
                                "presentation": .string("icon"),
                            ]),
                        ]),
                    ]),
                    error: nil,
                    meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
                )
            default:
                return CommandResponse(
                    ok: true,
                    data: .object([
                        "generatedAt": .string("2026-05-18T12:00:00Z"),
                        "samples": .array([
                            .object([
                                "key": .string("system.memory.used"),
                                "value": .number(1024),
                                "unit": .string("bytes"),
                                "capturedAt": .string("2026-05-18T12:00:00Z"),
                            ]),
                            .object([
                                "key": .string("system.disk.free"),
                                "value": .number(20 * 1024 * 1024 * 1024),
                                "unit": .string("bytes"),
                                "capturedAt": .string("2026-05-18T12:00:00Z"),
                            ]),
                            .object([
                                "key": .string("context.build.status"),
                                "value": .number(1),
                                "unit": .string("state"),
                                "capturedAt": .string("2026-05-18T12:00:00Z"),
                            ]),
                        ]),
                        "unavailableMetrics": .array([]),
                        "policy": .object([
                            "defaultAgentAccess": .string("safe_read"),
                        ]),
                    ]),
                    error: nil,
                    meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
                )
            }
        }
        let model = SystemTelemetryMenuBarModel(bridge: bridge)

        await model.refresh()

        XCTAssertEqual(model.widgets.map(\.id), ["memory-used", "disk-free", "build-status"])
        XCTAssertTrue(model.title(for: model.widgets[0]).hasPrefix("Memory "))
        XCTAssertEqual(model.severity(for: model.widgets[0]), .warning)
        XCTAssertTrue(model.title(for: model.widgets[1]).hasPrefix("Disk OK "))
        XCTAssertEqual(model.severity(for: model.widgets[1]), .normal)
        XCTAssertEqual(model.title(for: model.widgets[2]), "Build !")
        XCTAssertEqual(model.severity(for: model.widgets[2]), .warning)
    }
}
