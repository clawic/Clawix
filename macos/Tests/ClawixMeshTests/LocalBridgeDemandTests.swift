import XCTest
import ClawixEngine
@testable import Clawix

@MainActor
final class LocalBridgeDemandTests: XCTestCase {
    override func setUp() {
        super.setUp()
        setenv("CLAWIX_DISABLE_BACKEND", "1", 1)
        unsetenv("CLAWIX_BRIDGE_DISABLE")
        unsetenv("CLAWIX_DUMMY_MODE")
    }

    override func tearDown() {
        unsetenv("CLAWIX_DISABLE_BACKEND")
        unsetenv("CLAWIX_BRIDGE_DISABLE")
        unsetenv("CLAWIX_DUMMY_MODE")
        super.tearDown()
    }

    func testAppStateDoesNotStartBridgeWithoutDemand() {
        let launcher = FakeLocalBridgeLauncher()
        _ = makeState(launcher: launcher)

        XCTAssertEqual(launcher.startCount, 0)
        XCTAssertEqual(launcher.stopCount, 0)
        XCTAssertFalse(launcher.isRunning)
    }

    func testPairingDemandStartsTemporaryBridgeUntilReleased() {
        let launcher = FakeLocalBridgeLauncher()
        let state = makeState(launcher: launcher)

        let lease = state.acquireLocalBridge(reason: .pairing)

        XCTAssertEqual(launcher.startCount, 1)
        XCTAssertTrue(launcher.isRunning)
        XCTAssertEqual(state.activeLocalBridgeDemandReasonsForTests, [.pairing])

        lease.release()

        XCTAssertEqual(launcher.stopCount, 1)
        XCTAssertFalse(launcher.isRunning)
        XCTAssertTrue(state.activeLocalBridgeDemandReasonsForTests.isEmpty)
    }

    func testMultipleLeasesKeepTemporaryBridgeRunningUntilLastRelease() {
        let launcher = FakeLocalBridgeLauncher()
        let state = makeState(launcher: launcher)

        let pairing = state.acquireLocalBridge(reason: .pairing)
        let remote = state.acquireLocalBridge(reason: .remoteTools)

        XCTAssertEqual(launcher.startCount, 1)
        XCTAssertTrue(launcher.isRunning)

        pairing.release()

        XCTAssertEqual(launcher.stopCount, 0)
        XCTAssertTrue(launcher.isRunning)

        remote.release()

        XCTAssertEqual(launcher.stopCount, 1)
        XCTAssertFalse(launcher.isRunning)
    }

    func testReachableDaemonOwnsBridgeInsteadOfTemporaryHelper() {
        let launcher = FakeLocalBridgeLauncher()
        var daemonIsActive = false
        var daemonConnectCount = 0
        let state = makeState(
            launcher: launcher,
            backgroundActive: { daemonIsActive },
            makeDaemonBridgeClient: { _, _ in
                daemonConnectCount += 1
                return nil
            }
        )

        daemonIsActive = true
        let lease = state.acquireLocalBridge(reason: .pairing)

        XCTAssertEqual(launcher.startCount, 0)
        XCTAssertGreaterThanOrEqual(daemonConnectCount, 1)
        XCTAssertFalse(state.isTemporaryLocalBridgeRunningForTests)

        lease.release()
    }

    func testBridgeDisableBlocksDemandStartup() {
        setenv("CLAWIX_BRIDGE_DISABLE", "1", 1)
        let launcher = FakeLocalBridgeLauncher()
        let state = makeState(launcher: launcher)

        let lease = state.acquireLocalBridge(reason: .pairing)

        XCTAssertEqual(launcher.startCount, 0)
        XCTAssertFalse(launcher.isRunning)
        XCTAssertEqual(state.activeLocalBridgeDemandReasonsForTests, [.pairing])

        lease.release()
    }

    private func makeState(
        launcher: FakeLocalBridgeLauncher,
        backgroundActive: @escaping @MainActor () -> Bool = { false },
        backgroundEnabled: @escaping @MainActor () -> Bool = { false },
        makeDaemonBridgeClient: @escaping @MainActor (AppState, PairingService) -> DaemonBridgeClient? = { _, _ in nil }
    ) -> AppState {
        AppState(
            localBridgeLauncher: launcher,
            backgroundBridgeIsActive: backgroundActive,
            backgroundBridgeIsEnabled: backgroundEnabled,
            makeDaemonBridgeClient: makeDaemonBridgeClient
        )
    }
}

@MainActor
private final class FakeLocalBridgeLauncher: LocalBridgeHelperLaunching {
    private(set) var isRunning = false
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() -> Bool {
        if !isRunning {
            isRunning = true
            startCount += 1
        }
        return true
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        stopCount += 1
    }
}
