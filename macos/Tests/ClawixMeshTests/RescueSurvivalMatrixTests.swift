import XCTest
@testable import Clawix

final class RescueSurvivalMatrixTests: XCTestCase {
    func testBaseCriticalSurvivalMatrixPreservesLaunchChatOrDiagnostics() {
        let scenarios: [Scenario] = [
            Scenario(
                id: "failed_migration",
                decision: RescueSurvivalPolicy.evaluate(signals: [.migrationFailure], availableRuntimeCount: 1),
                expectedMode: .ephemeralChat,
                expectedCanChat: true,
                expectedPending: [.migrationFailure],
                expectedDisabled: [.persistentHistory],
                expectedCircuitBreakers: [.migrationFailure]
            ),
            Scenario(
                id: "partial_storage",
                decision: RescueSurvivalPolicy.evaluate(signals: [.storageUnavailable, .historyUnavailable], availableRuntimeCount: 1),
                expectedMode: .ephemeralChat,
                expectedCanChat: true,
                expectedPending: [.storageUnavailable, .historyUnavailable],
                expectedDisabled: [.persistentHistory, .nonCriticalUI],
                expectedCircuitBreakers: []
            ),
            Scenario(
                id: "bridge_runtime_down_with_alternate_runtime",
                decision: RescueRuntimeSignalMapper.decision(
                    backendStatus: .error("bridge failed"),
                    runtimeHealth: RescueRuntimeHealthSnapshot(
                        bridgeReachable: false,
                        runtimeCount: 1
                    )
                ),
                expectedMode: .ephemeralChat,
                expectedCanChat: true,
                expectedPending: [.bridgeRuntimeDown],
                expectedDisabled: [.persistentHistory, .nonCriticalUI],
                expectedCircuitBreakers: [.bridgeRuntimeDown]
            ),
            Scenario(
                id: "startup_cpu_hang_circuit_breaker",
                decision: RescueRuntimeSignalMapper.decision(
                    backendStatus: .ready,
                    runtimeHealth: RescueRuntimeHealthSnapshot(
                        processCpuPercent: 95,
                        residentBytes: 256_000_000,
                        footprintBytes: 512_000_000,
                        bridgeReachable: true,
                        runtimeCount: 1,
                        startupElapsedSeconds: 90,
                        mainThreadStallMs: 5_000,
                        recentCrashCount: 0
                    ),
                    thresholds: RescueRuntimeHealthThresholds(
                        highCPUPercent: 80,
                        highResidentBytes: 1_000_000_000,
                        highFootprintBytes: 1_000_000_000,
                        startupHangSeconds: 30,
                        mainThreadStallMs: 1_000,
                        crashLoopCount: 2
                    )
                ),
                expectedMode: .degraded,
                expectedCanChat: true,
                expectedPending: [.highCPU, .startupHang],
                expectedDisabled: [.nonCriticalUI],
                expectedCircuitBreakers: [.highCPU, .startupHang]
            )
        ]

        for scenario in scenarios {
            assertSurvivalScenario(scenario)
        }
    }

    func testNoRuntimeMatrixFallsBackToLocalDiagnosticsWithoutBlockingLaunch() {
        let decision = RescueRuntimeSignalMapper.decision(
            backendStatus: .error("runtime unavailable"),
            runtimeHealth: RescueRuntimeHealthSnapshot(
                bridgeReachable: false,
                runtimeCount: 0
            )
        )

        XCTAssertEqual(decision.mode, .diagnosticsOnly)
        XCTAssertTrue(decision.canLaunch)
        XCTAssertFalse(decision.canChat)
        XCTAssertTrue(decision.canProvideRepairContext)
        XCTAssertTrue(decision.preservedCapabilities.contains(.diagnosticsExport))
        XCTAssertTrue(decision.pendingRepairSignals.contains(.bridgeRuntimeDown))
        XCTAssertTrue(decision.pendingRepairSignals.contains(.noRuntimeAvailable))
        XCTAssertTrue(decision.disabledCapabilities.contains(.agentExecution))
        XCTAssertTrue(decision.requiresApprovalForRiskyRepair)
    }

    private func assertSurvivalScenario(_ scenario: Scenario, file: StaticString = #filePath, line: UInt = #line) {
        let decision = scenario.decision
        XCTAssertEqual(decision.mode, scenario.expectedMode, scenario.id, file: file, line: line)
        XCTAssertTrue(decision.canLaunch, scenario.id, file: file, line: line)
        XCTAssertEqual(decision.canChat, scenario.expectedCanChat, scenario.id, file: file, line: line)
        XCTAssertTrue(decision.canProvideRepairContext, scenario.id, file: file, line: line)
        XCTAssertTrue(decision.requiresApprovalForRiskyRepair, scenario.id, file: file, line: line)
        for signal in scenario.expectedPending {
            XCTAssertTrue(decision.pendingRepairSignals.contains(signal), "\(scenario.id) missing pending \(signal.rawValue)", file: file, line: line)
        }
        for capability in scenario.expectedDisabled {
            XCTAssertTrue(decision.disabledCapabilities.contains(capability), "\(scenario.id) missing disabled \(capability.rawValue)", file: file, line: line)
        }
        for signal in scenario.expectedCircuitBreakers {
            XCTAssertTrue(decision.circuitBreakers.contains(signal), "\(scenario.id) missing circuit breaker \(signal.rawValue)", file: file, line: line)
        }
    }

    private struct Scenario {
        var id: String
        var decision: RescueSurvivalDecision
        var expectedMode: RescueMode
        var expectedCanChat: Bool
        var expectedPending: [RescueFailureSignal]
        var expectedDisabled: [RescueCapability]
        var expectedCircuitBreakers: [RescueFailureSignal]
    }
}
