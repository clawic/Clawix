import AppKit
import ClawHostKit
import XCTest
@testable import Clawix

extension SystemTelemetryBridgeTests {
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
        let forced = await recorder.recordIfDue(now: Date(timeIntervalSince1970: 121), force: true)
        let third = await recorder.recordIfDue(now: Date(timeIntervalSince1970: 190))

        XCTAssertEqual(first.status, .recorded)
        XCTAssertEqual(first.sampleCount, 3)
        XCTAssertEqual(first.rollupCount, 3)
        XCTAssertEqual(first.incidentCount, 1)
        XCTAssertEqual(first.dbPath, "/tmp/monitor.sqlite")
        XCTAssertEqual(second.status, .skipped)
        XCTAssertEqual(second.reason, "minimum_interval")
        XCTAssertEqual(forced.status, .recorded)
        XCTAssertEqual(third.status, .recorded)
        let calls = await capture.calls
        XCTAssertEqual(calls.count, 3)
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

    @MainActor
    func testMenuBarModelLoadsHistoryGraphForChartWidgets() async {
        let bridge = SystemTelemetryBridge { request in
            switch (request.resource, request.action) {
            case ("widgets", "list"):
                return CommandResponse(
                    ok: true,
                    data: .object([
                        "widgets": .array([
                            .object([
                                "id": .string("hardware-overview"),
                                "title": .string("Hardware Overview"),
                                "placement": .string("panel"),
                                "metric_keys": .array([
                                    .string("system.cpu.load1"),
                                ]),
                                "render_mode": .string("chart"),
                            ]),
                        ]),
                    ]),
                    error: nil,
                    meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
                )
            case ("history", "get"):
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
                                .object(["t": .integer(2), "value": .number(3), "sourceId": .string("system.telemetry.local")]),
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

        await model.refresh()

        XCTAssertEqual(model.panelWidgets.map(\.id), ["hardware-overview"])
        XCTAssertEqual(model.historyGraph(for: model.panelWidgets[0])?.chart.points.count, 2)
        XCTAssertTrue(model.hasHistoryGraph(for: model.panelWidgets[0]))
    }

    @MainActor
    func testMenuBarModelPrioritizesWidgetMetricOrderForHistoryGraphs() async {
        let requestedHistoryKeys = StringRecorder()
        let bridge = SystemTelemetryBridge { request in
            switch (request.resource, request.action) {
            case ("widgets", "list"):
                return CommandResponse(
                    ok: true,
                    data: .object([
                        "widgets": .array([
                            .object([
                                "id": .string("hardware-overview"),
                                "title": .string("Hardware Overview"),
                                "placement": .string("panel"),
                                "metric_keys": .array([
                                    .string("system.cpu.load1"),
                                    .string("context.agent.active_runs"),
                                    .string("context.build.status"),
                                    .string("system.memory.used"),
                                ]),
                                "render_mode": .string("chart"),
                            ]),
                        ]),
                    ]),
                    error: nil,
                    meta: .init(adapter: "system-telemetry", source: .framework, durationMS: 0)
                )
            case ("history", "get"):
                await requestedHistoryKeys.append(request.arguments["metric_key"] ?? "")
                return CommandResponse(
                    ok: true,
                    data: .object([
                        "metric": .object(["key": .string(request.arguments["metric_key"] ?? "")]),
                        "rangeMs": .integer(3600000),
                        "retention": .object(["status": .string("recorded")]),
                        "chart": .object([
                            "kind": .string("line"),
                            "metricKey": .string(request.arguments["metric_key"] ?? ""),
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

        await model.refresh()

        let recordedKeys = await requestedHistoryKeys.recorded()
        XCTAssertEqual(Array(recordedKeys.prefix(3)), [
            "system.cpu.load1",
            "context.agent.active_runs",
            "context.build.status",
        ])
        XCTAssertEqual(model.historyGraph(for: model.panelWidgets[0])?.metricKey, "system.cpu.load1")
    }

    @MainActor
    func testHistoryGraphViewRendersNativeBitmap() throws {
        let history = SystemTelemetryHistory(
            metricKey: "system.cpu.load1",
            rangeMS: 3_600_000,
            retentionStatus: "recorded",
            chart: SystemTelemetryHistoryChart(
                kind: "line",
                metricKey: "system.cpu.load1",
                unit: "count",
                source: "metric_samples",
                points: [
                    SystemTelemetryHistoryPoint(timestampMS: 1, value: 1, sourceID: "system.telemetry.local", count: nil),
                    SystemTelemetryHistoryPoint(timestampMS: 2, value: 4, sourceID: "system.telemetry.local", count: nil),
                    SystemTelemetryHistoryPoint(timestampMS: 3, value: 2, sourceID: "system.telemetry.local", count: nil),
                    SystemTelemetryHistoryPoint(timestampMS: 4, value: 5, sourceID: "system.telemetry.local", count: nil),
                ],
                empty: false
            )
        )
        let view = SystemTelemetryHistoryGraphView(history: history, title: "CPU")
        let size = SystemTelemetryHistoryGraphView.preferredSize
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        rep.size = size

        view.cacheDisplay(in: view.bounds, to: rep)

        var nonTransparentPixels = 0
        var graphTintPixels = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.alphaComponent > 0.01 {
                    nonTransparentPixels += 1
                }
                if color.blueComponent > 0.35,
                   color.blueComponent > color.redComponent + 0.08,
                   color.blueComponent > color.greenComponent + 0.02 {
                    graphTintPixels += 1
                }
            }
        }

        XCTAssertGreaterThan(nonTransparentPixels, rep.pixelsWide * rep.pixelsHigh / 2)
        XCTAssertGreaterThan(graphTintPixels, 20)
    }}
