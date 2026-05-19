import XCTest
@testable import Clawix

final class SurfaceRouteSupervisorTests: XCTestCase {
    func testCoreRoutesStartReadyWithoutTimeout() {
        let descriptor = SidebarRoute.rescue.surfaceDescriptor

        let state = SurfaceRouteSupervisor.start(descriptor: descriptor)

        XCTAssertEqual(state, .ready(surfaceID: "rescue"))
        XCTAssertTrue(state.isTerminal)
    }

    func testExtensionRoutesStartLoadingWithDescriptorTimeout() {
        let descriptor = SidebarRoute.databaseCollection("tasks").surfaceDescriptor

        let state = SurfaceRouteSupervisor.start(descriptor: descriptor)

        XCTAssertEqual(state, .loading(surfaceID: "database:tasks", timeoutSeconds: 5))
        XCTAssertFalse(state.isTerminal)
    }

    func testTimeoutOnlyDegradesCurrentLoadingSurface() {
        let descriptor = SidebarRoute.iotHome.surfaceDescriptor
        let loading = SurfaceRouteSupervisor.start(descriptor: descriptor)

        let degraded = SurfaceRouteSupervisor.timeout(state: loading, descriptor: descriptor)

        XCTAssertEqual(
            degraded,
            .degraded(surfaceID: "iot", reason: "Surface did not become ready within 5 seconds.")
        )
        XCTAssertEqual(
            SurfaceRouteSupervisor.timeout(state: .ready(surfaceID: "iot"), descriptor: descriptor),
            .ready(surfaceID: "iot")
        )
    }

    func testCancelIgnoresStaleSurfaceState() {
        let descriptor = SidebarRoute.driveAdmin.surfaceDescriptor
        let stale = SurfaceRouteSupervisionState.loading(surfaceID: "calendar", timeoutSeconds: 5)

        XCTAssertEqual(
            SurfaceRouteSupervisor.cancel(state: stale, descriptor: descriptor),
            stale
        )
        XCTAssertEqual(
            SurfaceRouteSupervisor.cancel(
                state: SurfaceRouteSupervisor.start(descriptor: descriptor),
                descriptor: descriptor
            ),
            .cancelled(surfaceID: "drive")
        )
    }
}
