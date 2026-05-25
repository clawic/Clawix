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
}
