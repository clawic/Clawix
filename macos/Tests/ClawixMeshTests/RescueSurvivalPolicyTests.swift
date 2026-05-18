import XCTest
@testable import Clawix

final class RescueSurvivalPolicyTests: XCTestCase {
    func testMigrationOrStorageFailureKeepsLaunchChatAndRepairThroughEphemeralChat() {
        let decision = RescueSurvivalPolicy.evaluate(
            signals: [.migrationFailure, .storageUnavailable],
            availableRuntimeCount: 1
        )

        XCTAssertEqual(decision.mode, .ephemeralChat)
        XCTAssertTrue(decision.canLaunch)
        XCTAssertTrue(decision.canChat)
        XCTAssertTrue(decision.canProvideRepairContext)
        XCTAssertTrue(decision.preservedCapabilities.contains(.agentExecution))
        XCTAssertTrue(decision.preservedCapabilities.contains(.diagnosticsExport))
        XCTAssertTrue(decision.disabledCapabilities.contains(.persistentHistory))
        XCTAssertTrue(decision.disabledCapabilities.contains(.nonCriticalUI))
        XCTAssertTrue(decision.circuitBreakers.contains(.migrationFailure))
        XCTAssertTrue(decision.requiresApprovalForRiskyRepair)
    }

    func testNoRuntimeFallsBackToDiagnosticsWithoutPretendingChatCanRun() {
        let decision = RescueSurvivalPolicy.evaluate(
            signals: [.bridgeRuntimeDown],
            availableRuntimeCount: 0
        )

        XCTAssertEqual(decision.mode, .diagnosticsOnly)
        XCTAssertTrue(decision.canLaunch)
        XCTAssertFalse(decision.canChat)
        XCTAssertTrue(decision.canProvideRepairContext)
        XCTAssertTrue(decision.preservedCapabilities.contains(.diagnosticsExport))
        XCTAssertTrue(decision.disabledCapabilities.contains(.agentExecution))
        XCTAssertTrue(decision.pendingRepairSignals.contains(.noRuntimeAvailable))
        XCTAssertTrue(decision.requiresApprovalForRiskyRepair)
    }

    func testCpuAndMemoryCircuitBreakersDegradeNonCriticalUIBeforeChat() {
        let decision = RescueSurvivalPolicy.evaluate(
            signals: [.highCPU, .highMemory],
            availableRuntimeCount: 1
        )

        XCTAssertEqual(decision.mode, .degraded)
        XCTAssertTrue(decision.canLaunch)
        XCTAssertTrue(decision.canChat)
        XCTAssertTrue(decision.canProvideRepairContext)
        XCTAssertTrue(decision.disabledCapabilities.contains(.nonCriticalUI))
        XCTAssertFalse(decision.disabledCapabilities.contains(.persistentHistory))
        XCTAssertEqual(decision.circuitBreakers, [.highCPU, .highMemory])
        XCTAssertTrue(decision.requiresApprovalForRiskyRepair)
    }

    func testHealthyStartupPreservesAllCapabilities() {
        let decision = RescueSurvivalPolicy.evaluate(signals: [], availableRuntimeCount: 1)

        XCTAssertEqual(decision.mode, .normal)
        XCTAssertTrue(decision.canLaunch)
        XCTAssertTrue(decision.canChat)
        XCTAssertTrue(decision.canProvideRepairContext)
        XCTAssertEqual(Set(decision.preservedCapabilities), Set(RescueCapability.allCases))
        XCTAssertTrue(decision.disabledCapabilities.isEmpty)
        XCTAssertFalse(decision.requiresApprovalForRiskyRepair)
    }

    func testRepairStatusSummaryOnlyAppearsWhenThereIsPendingRescueWork() {
        let healthy = RescueSurvivalPolicy.evaluate(signals: [], availableRuntimeCount: 1)
        XCTAssertNil(RescueRepairStatusSummary(decision: healthy))

        let degraded = RescueSurvivalPolicy.evaluate(signals: [.highCPU, .highMemory], availableRuntimeCount: 1)
        let degradedSummary = try! XCTUnwrap(RescueRepairStatusSummary(decision: degraded))
        XCTAssertEqual(degradedSummary.title, "Repair pending")
        XCTAssertEqual(degradedSummary.detail, "2 issues")
        XCTAssertEqual(degradedSummary.actionTitle, "Diagnose")

        let noRuntime = RescueSurvivalPolicy.evaluate(signals: [.bridgeRuntimeDown], availableRuntimeCount: 0)
        let diagnosticsSummary = try! XCTUnwrap(RescueRepairStatusSummary(decision: noRuntime))
        XCTAssertEqual(diagnosticsSummary.title, "Diagnostics available")
        XCTAssertEqual(diagnosticsSummary.detail, "Chat runtime unavailable")
    }
}
