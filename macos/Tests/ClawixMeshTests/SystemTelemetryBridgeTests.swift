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
        XCTAssertEqual(model.title(for: model.widgets[0]), "1.25")
    }
}
