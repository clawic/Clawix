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
                        "metric_key": .string("system.cpu.load_1m"),
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
        XCTAssertEqual(snapshot.sample(for: "system.cpu.load_1m")?.value, 1.25)
        XCTAssertEqual(snapshot.unavailableMetricKeys, ["system.sensor.temperature"])
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
                        .string("system.cpu.load_1m"),
                        .string("system.memory.used_bytes"),
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
        XCTAssertEqual(widgets.first?.metricKeys, ["system.cpu.load_1m", "system.memory.used_bytes"])
        XCTAssertEqual(widgets.first?.refreshIntervalMS, 2000)
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
                                .string("system.cpu.load_1m"),
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
                                "metric_key": .string("system.cpu.load_1m"),
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
}
