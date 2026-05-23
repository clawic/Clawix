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
