import AppKit
import ClawHostKit
import XCTest
@testable import Clawix

final class SystemTelemetryBridgeTests: XCTestCase {
    private actor TelemetryRequestCounter {
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
    private final class StatusControllerProbe {
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

    @MainActor
    private func makeStatusController(
        probe: StatusControllerProbe,
        counter: TelemetryRequestCounter = TelemetryRequestCounter(),
        isCapabilityVisible: @escaping @MainActor () -> Bool = { true }
    ) -> (SystemTelemetryStatusItemController, TelemetryRequestCounter) {
        let bridge = SystemTelemetryBridge { request in
            switch (request.resource, request.action) {
            case ("widgets", "list"):
                await counter.incrementWidgets()
                return CommandResponse(
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
            case ("providers", "list"):
                return CommandResponse(
                    ok: true,
                    data: .object(["providers": .array([])]),
                    error: nil,
                    meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
                )
            default:
                await counter.incrementSnapshots()
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
                            ]),
                        ]),
                        "unavailableMetrics": .array([]),
                        "policy": .object(["defaultAgentAccess": .string("safe_read")]),
                    ]),
                    error: nil,
                    meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
                )
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

    @MainActor
    func testStatusControllerStartDoesNotRefreshOrScheduleTelemetry() async {
        let probe = StatusControllerProbe()
        let (controller, counter) = makeStatusController(probe: probe)

        controller.start()
        let counts = await counter.counts()

        XCTAssertEqual(probe.diagnosticsActivations, 0)
        XCTAssertEqual(probe.recordCalls, [])
        XCTAssertEqual(probe.renderCount, 0)
        XCTAssertEqual(counts.widgets, 0)
        XCTAssertEqual(counts.snapshots, 0)
    }

    @MainActor
    func testStatusControllerActivatesTelemetryOnUserSurfaceOpen() async {
        let probe = StatusControllerProbe()
        let (controller, counter) = makeStatusController(probe: probe)

        await controller.activateFromUserSurfaceAndRefresh()
        let counts = await counter.counts()

        XCTAssertEqual(probe.diagnosticsActivations, 0)
        XCTAssertEqual(probe.recordCalls, [false])
        XCTAssertEqual(probe.renderCount, 1)
        XCTAssertEqual(counts.widgets, 1)
        XCTAssertEqual(counts.snapshots, 1)
    }

    @MainActor
    func testStatusControllerDoesNotActivateWhenMaturityBlocksTelemetry() async {
        let probe = StatusControllerProbe()
        let (controller, counter) = makeStatusController(probe: probe, isCapabilityVisible: { false })

        await controller.activateFromUserSurfaceAndRefresh()
        let counts = await counter.counts()

        XCTAssertEqual(probe.diagnosticsActivations, 0)
        XCTAssertEqual(probe.recordCalls, [])
        XCTAssertEqual(probe.renderCount, 0)
        XCTAssertEqual(counts.widgets, 0)
        XCTAssertEqual(counts.snapshots, 0)
    }

    @MainActor
    func testStatusControllerActivationIsIdempotent() async {
        let probe = StatusControllerProbe()
        let (controller, counter) = makeStatusController(probe: probe)

        await controller.activateFromUserSurfaceAndRefresh()
        await controller.activateFromUserSurfaceAndRefresh()
        let counts = await counter.counts()

        XCTAssertEqual(probe.diagnosticsActivations, 0)
        XCTAssertEqual(probe.recordCalls, [false, false])
        XCTAssertEqual(probe.renderCount, 2)
        XCTAssertEqual(counts.widgets, 2)
        XCTAssertEqual(counts.snapshots, 1)
    }

    @MainActor
    func testStatusControllerDoesNotScheduleTimerAfterActivation() async {
        let probe = StatusControllerProbe()
        let (controller, counter) = makeStatusController(probe: probe)

        await controller.activateFromUserSurfaceAndRefresh()
        let counts = await counter.counts()

        XCTAssertEqual(probe.recordCalls, [false])
        XCTAssertEqual(probe.renderCount, 1)
        XCTAssertEqual(counts.widgets, 1)
        XCTAssertEqual(counts.snapshots, 1)
    }

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
                        "adapter_contract": .object([
                            "provider_id": .string("context.weather.live"),
                            "adapter_kind": .string("weather"),
                            "mode": .string("live"),
                            "input": .object([
                                "credential_ref": .string("required_redacted"),
                                "required_grants": .array([
                                    .string("weather.location.read"),
                                ]),
                                "network_access": .string("blocked_until_granted"),
                            ]),
                            "output": .object([
                                "metrics": .array([
                                    .string("context.weather.temperature"),
                                ]),
                                "sample_shape": .string("system_telemetry_metric_sample"),
                                "monitor_write_required": .bool(true),
                            ]),
                            "audit": .object([
                                "event": .string("system.telemetry.provider.weather.live"),
                                "receipt_required": .bool(true),
                                "durable_receipt_source": .string("provider_broker_or_signed_host"),
                                "redaction": .object([
                                    "credential_ref_redacted": .bool(true),
                                    "precise_location_redacted": .bool(true),
                                ]),
                            ]),
                            "execution_policy": .object([
                                "fail_closed": .bool(true),
                                "external_pending_until_receipt": .bool(true),
                            ]),
                        ]),
                    ]),
                    "request": .object([
                        "credential_ref": .string("provided_redacted"),
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
        XCTAssertEqual(plan.provider.adapterContract?.providerID, "context.weather.live")
        XCTAssertEqual(plan.provider.adapterContract?.output.metrics, ["context.weather.temperature"])
        XCTAssertEqual(plan.provider.adapterContract?.audit.receiptRequired, true)
        XCTAssertEqual(plan.provider.adapterContract?.executionPolicy.externalPendingUntilReceipt, true)
        XCTAssertEqual(plan.credentialRef, "provided_redacted")
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
    func testMenuBarModelDoesNotOverlapRefreshes() async {
        let counter = TelemetryRequestCounter()
        let bridge = SystemTelemetryBridge { request in
            switch (request.resource, request.action) {
            case ("widgets", "list"):
                await counter.incrementWidgets()
                try? await Task.sleep(nanoseconds: 200_000_000)
                return CommandResponse(
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
                            ]),
                        ]),
                        "unavailableMetrics": .array([]),
                        "policy": .object(["defaultAgentAccess": .string("safe_read")]),
                    ]),
                    error: nil,
                    meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
                )
            }
        }
        let model = SystemTelemetryMenuBarModel(bridge: bridge)

        let first = Task { await model.refresh() }
        try? await Task.sleep(nanoseconds: 50_000_000)
        let second = Task { await model.refresh() }
        await first.value
        await second.value

        let counts = await counter.counts()
        XCTAssertEqual(counts.widgets, 1)
    }

    @MainActor
    func testMenuBarModelThrottlesHistoryRefreshes() async {
        let counter = TelemetryRequestCounter()
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
                await counter.incrementHistories()
                return CommandResponse(
                    ok: true,
                    data: .object([
                        "metric": .object(["key": .string("system.cpu.load1")]),
                        "rangeMs": .integer(3600000),
                        "retention": .object(["status": .string("recorded")]),
                        "chart": .object([
                            "kind": .string("line"),
                            "metricKey": .string("system.cpu.load1"),
                            "unit": .string("count"),
                            "source": .string("metric_samples"),
                            "empty": .bool(false),
                            "points": .array([
                                .object(["t": .integer(1), "value": .number(1), "sourceId": .string("system.telemetry.local")]),
                                .object(["t": .integer(2), "value": .number(2), "sourceId": .string("system.telemetry.local")]),
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
                            ]),
                        ]),
                        "unavailableMetrics": .array([]),
                        "policy": .object(["defaultAgentAccess": .string("safe_read")]),
                    ]),
                    error: nil,
                    meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
                )
            }
        }
        let model = SystemTelemetryMenuBarModel(bridge: bridge)

        await model.refresh(now: Date(timeIntervalSince1970: 100))
        await model.refresh(now: Date(timeIntervalSince1970: 120))
        var counts = await counter.counts()
        XCTAssertEqual(counts.histories, 1)

        await model.refresh(forceHistory: true, now: Date(timeIntervalSince1970: 121))
        counts = await counter.counts()
        XCTAssertEqual(counts.histories, 2)

        await model.refresh(now: Date(timeIntervalSince1970: 182))
        counts = await counter.counts()
        XCTAssertEqual(counts.histories, 3)
    }

    @MainActor
    func testMenuBarModelThrottlesSnapshotRefreshes() async {
        let counter = TelemetryRequestCounter()
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
                                "presentation": .string("text"),
                            ]),
                        ]),
                    ]),
                    error: nil,
                    meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
                )
            case ("providers", "list"):
                return CommandResponse(
                    ok: true,
                    data: .object(["providers": .array([])]),
                    error: nil,
                    meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
                )
            default:
                await counter.incrementSnapshots()
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
                            ]),
                        ]),
                        "unavailableMetrics": .array([]),
                        "policy": .object(["defaultAgentAccess": .string("safe_read")]),
                    ]),
                    error: nil,
                    meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
                )
            }
        }
        let model = SystemTelemetryMenuBarModel(bridge: bridge)

        await model.refresh(now: Date(timeIntervalSince1970: 100))
        await model.refresh(now: Date(timeIntervalSince1970: 110))
        var counts = await counter.counts()
        XCTAssertEqual(counts.snapshots, 1)

        await model.refresh(forceHistory: true, now: Date(timeIntervalSince1970: 111))
        counts = await counter.counts()
        XCTAssertEqual(counts.snapshots, 2)

        await model.refresh(now: Date(timeIntervalSince1970: 127))
        counts = await counter.counts()
        XCTAssertEqual(counts.snapshots, 3)
    }

    @MainActor
    func testMenuBarModelLimitsAutomaticHistoryRefreshes() async {
        let counter = TelemetryRequestCounter()
        let bridge = SystemTelemetryBridge { request in
            switch (request.resource, request.action) {
            case ("widgets", "list"):
                return CommandResponse(
                    ok: true,
                    data: .object([
                        "widgets": .array((1...5).map { index in
                            .object([
                                "id": .string("metric-\(index)"),
                                "title": .string("Metric \(index)"),
                                "placement": .string("menubar"),
                                "metricKey": .string("system.metric.\(index)"),
                                "presentation": .string("sparkline"),
                            ])
                        }),
                    ]),
                    error: nil,
                    meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
                )
            case ("history", "get"):
                await counter.incrementHistories()
                let metricKey = request.arguments["metric_key"] ?? "system.metric.unknown"
                return CommandResponse(
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
                            "points": .array([
                                .object(["t": .integer(1), "value": .number(1), "sourceId": .string("system.telemetry.local")]),
                                .object(["t": .integer(2), "value": .number(2), "sourceId": .string("system.telemetry.local")]),
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
                        "samples": .array([]),
                        "unavailableMetrics": .array([]),
                        "policy": .object(["defaultAgentAccess": .string("safe_read")]),
                    ]),
                    error: nil,
                    meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
                )
            }
        }
        let model = SystemTelemetryMenuBarModel(bridge: bridge)

        await model.refresh(now: Date(timeIntervalSince1970: 100))
        var counts = await counter.counts()
        XCTAssertEqual(counts.histories, 3)

        await model.refresh(forceHistory: true, now: Date(timeIntervalSince1970: 200))
        counts = await counter.counts()
        XCTAssertEqual(counts.histories, 8)
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

}
