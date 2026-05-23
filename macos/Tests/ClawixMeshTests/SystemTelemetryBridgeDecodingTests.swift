import ClawHostKit
import XCTest
@testable import Clawix

final class SystemTelemetryBridgeDecodingTests: XCTestCase {
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
                    .object([
                        "key": .string("system.peripheral.bluetooth_count"),
                        "value": .number(2),
                        "unit": .string("count"),
                        "capturedAt": .string("2026-05-18T12:00:00Z"),
                        "source": .object([
                            "adapter": .string("signed_host"),
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
        XCTAssertEqual(snapshot.sample(for: "system.peripheral.bluetooth_count")?.value, 2)
        XCTAssertEqual(snapshot.sample(for: "system.peripheral.bluetooth_count")?.source, "signed_host")
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
        let controlsResponse = SystemTelemetryBridgeResponses.controlCatalog()

        let controls = try SystemTelemetryBridge.decodeControls(controlsResponse)

        XCTAssertEqual(controls.map(\.id), ["system.display.set_brightness"])
        XCTAssertEqual(controls[0].targetMetricKeys, ["system.display.brightness"])
        XCTAssertEqual(controls[0].requiresSignedHostBroker, true)
        XCTAssertEqual(controls[0].requiredGrants, ["system.display.control"])

        let planResponse = SystemTelemetryBridgeResponses.controlPlan()

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
        XCTAssertEqual(plan.auditPlan?.status, "planned")
        XCTAssertEqual(plan.auditPlan?.durable, false)
        XCTAssertEqual(plan.auditPlan?.event, "system.telemetry.control.audio.set_output_volume")
        XCTAssertEqual(plan.auditPlan?.outcome, "blocked")
        XCTAssertEqual(plan.auditPlan?.receiptStatus, "not_issued")
        XCTAssertEqual(plan.auditPlan?.redaction.targetRedacted, true)
        XCTAssertEqual(plan.auditPlan?.redaction.valueRedacted, true)
        XCTAssertEqual(plan.auditPlan?.redaction.sensitiveDetailRedacted, true)
        XCTAssertEqual(plan.steps.first?.status, "blocked")
    }

    func testDecodesProviderCatalogAndPlanPayloads() throws {
        let providersResponse = SystemTelemetryBridgeResponses.providerCatalog()

        let providers = try SystemTelemetryBridge.decodeProviders(providersResponse)

        XCTAssertEqual(providers.map(\.id), ["context.weather.live", "system.sensors.signed"])
        XCTAssertEqual(providers[0].metricKeys, ["context.weather.temperature"])
        XCTAssertEqual(providers[0].requiresGrant, "weather.location.read")
        XCTAssertEqual(providers[0].credentialRefRequired, true)
        XCTAssertEqual(providers[0].adapterContract?.providerID, "context.weather.live")
        XCTAssertEqual(providers[0].adapterContract?.input.credentialRef, "required_redacted")
        XCTAssertEqual(providers[0].adapterContract?.input.requiredGrants, ["weather.location.read"])
        XCTAssertEqual(providers[0].adapterContract?.input.networkAccess, "blocked_until_granted")
        XCTAssertEqual(providers[0].adapterContract?.output.metrics, ["context.weather.temperature"])
        XCTAssertEqual(providers[0].adapterContract?.output.sampleShape, "system_telemetry_metric_sample")
        XCTAssertEqual(providers[0].adapterContract?.output.monitorWriteRequired, true)
        XCTAssertEqual(providers[0].adapterContract?.audit.durableReceiptSource, "provider_broker_or_signed_host")
        XCTAssertEqual(providers[0].adapterContract?.audit.redaction.credentialRefRedacted, true)
        XCTAssertEqual(providers[0].adapterContract?.audit.redaction.preciseLocationRedacted, true)
        XCTAssertEqual(providers[0].adapterContract?.executionPolicy.failClosed, true)
        XCTAssertEqual(providers[0].adapterContract?.executionPolicy.externalPendingUntilReceipt, true)
        XCTAssertEqual(providers[1].kind, "hardware_sensor")
        XCTAssertEqual(providers[1].metricKeys, ["system.sensor.temperature", "system.sensor.fan_speed"])
        XCTAssertEqual(providers[1].requiresGrant, "system.sensor.read")

        let planResponse = SystemTelemetryBridgeResponses.providerPlan()

        let plan = try SystemTelemetryBridge.decodeProviderPlan(planResponse)

        XCTAssertEqual(plan.provider.id, "system.sensors.signed")
        XCTAssertEqual(plan.willConnect, false)
        XCTAssertEqual(plan.externalPending, true)
        XCTAssertEqual(plan.credentialRef, "provided_redacted")
        XCTAssertEqual(plan.reason, "test")
        XCTAssertEqual(plan.brokerStatus, "external_pending")
        XCTAssertEqual(plan.failClosed, true)
        XCTAssertEqual(plan.requiredGrants, ["system.sensor.read"])
        XCTAssertEqual(plan.credentialRefRequired, false)
        XCTAssertEqual(plan.networkAccess, "blocked_until_granted")
        XCTAssertEqual(plan.receiptStatus, "not_issued")
        XCTAssertEqual(plan.auditEvent, "system.telemetry.provider.hardware_sensor.live")
        XCTAssertEqual(plan.auditPlan?.status, "planned")
        XCTAssertEqual(plan.auditPlan?.durable, false)
        XCTAssertEqual(plan.auditPlan?.event, "system.telemetry.provider.hardware_sensor.live")
        XCTAssertEqual(plan.auditPlan?.outcome, "blocked")
        XCTAssertEqual(plan.auditPlan?.receiptStatus, "not_issued")
        XCTAssertEqual(plan.auditPlan?.redaction.credentialRefRedacted, true)
        XCTAssertEqual(plan.auditPlan?.redaction.preciseLocationRedacted, true)
        XCTAssertEqual(plan.steps.map(\.status), ["skipped", "blocked"])
    }
}
