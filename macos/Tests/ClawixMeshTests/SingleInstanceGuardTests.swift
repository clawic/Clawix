import XCTest
@testable import Clawix

final class SingleInstanceGuardTests: XCTestCase {
    func testSingleInstanceGuardIgnoresAgentSnapshotBundlePaths() {
        let currentBundle = URL(fileURLWithPath: "/Applications/Clawix.app")
        let agentBundle = URL(fileURLWithPath: "/Users/test/Library/Caches/Clawix-Agents/snapshots/1/Clawix.app")

        XCTAssertFalse(ClawixSingleInstanceGuard.isExistingMainInstanceCandidate(
            bundleURL: agentBundle,
            processIdentifier: 10,
            isTerminated: false,
            currentPID: 20,
            currentBundleURL: currentBundle
        ))
    }

    func testSingleInstanceGuardKeepsOlderCanonicalBundleCandidate() {
        let currentBundle = URL(fileURLWithPath: "/Applications/Clawix.app")

        XCTAssertTrue(ClawixSingleInstanceGuard.isExistingMainInstanceCandidate(
            bundleURL: currentBundle,
            processIdentifier: 10,
            isTerminated: false,
            currentPID: 20,
            currentBundleURL: currentBundle
        ))
    }
}
