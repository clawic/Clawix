import XCTest
@testable import Clawix

final class BackgroundBridgeRecoveryPolicyTests: XCTestCase {
    func testRecoveryBootstrapBacksOffAfterRepeatedFailures() {
        XCTAssertEqual(
            BackgroundBridgeService.recoveryRetryDelaySeconds(afterConsecutiveFailures: 0),
            5
        )
        XCTAssertEqual(
            BackgroundBridgeService.recoveryRetryDelaySeconds(afterConsecutiveFailures: 1),
            10
        )
        XCTAssertEqual(
            BackgroundBridgeService.recoveryRetryDelaySeconds(afterConsecutiveFailures: 2),
            20
        )
        XCTAssertEqual(
            BackgroundBridgeService.recoveryRetryDelaySeconds(afterConsecutiveFailures: 3),
            40
        )
        XCTAssertEqual(
            BackgroundBridgeService.recoveryRetryDelaySeconds(afterConsecutiveFailures: 4),
            60
        )
        XCTAssertEqual(
            BackgroundBridgeService.recoveryRetryDelaySeconds(afterConsecutiveFailures: 12),
            60
        )
    }

    func testRecoveryOnlyStopsBackingOffWhenDaemonIsReachable() {
        XCTAssertTrue(BackgroundBridgeService.shouldBackOffRecovery(isEnabled: true, daemonReachable: false))
        XCTAssertFalse(BackgroundBridgeService.shouldBackOffRecovery(isEnabled: true, daemonReachable: true))
        XCTAssertFalse(BackgroundBridgeService.shouldBackOffRecovery(isEnabled: false, daemonReachable: false))
    }

    func testCriticalUIActivityDefersBackgroundWorkOnlyInsideGraceWindow() {
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertFalse(CriticalUIActivity.shouldDeferBackgroundWork(
            now: now,
            lastMarkedAt: nil,
            graceSeconds: 2
        ))
        XCTAssertTrue(CriticalUIActivity.shouldDeferBackgroundWork(
            now: now,
            lastMarkedAt: now.addingTimeInterval(-1),
            graceSeconds: 2
        ))
        XCTAssertFalse(CriticalUIActivity.shouldDeferBackgroundWork(
            now: now,
            lastMarkedAt: now.addingTimeInterval(-3),
            graceSeconds: 2
        ))
    }
}
