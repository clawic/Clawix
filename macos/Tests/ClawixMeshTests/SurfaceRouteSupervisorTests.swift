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

        XCTAssertEqual(
            state,
            .loading(
                surfaceID: "database:tasks",
                timeoutSeconds: 5,
                message: nil,
                progress: nil
            )
        )
        XCTAssertFalse(state.isTerminal)
    }

    func testImmediateReadinessMarksSurfaceReadyAfterFirstRender() {
        let descriptor = SidebarRoute.databaseCollection("tasks").surfaceDescriptor
        let loading = SurfaceRouteSupervisor.start(descriptor: descriptor)

        let ready = SurfaceRouteSupervisor.afterFirstRender(
            state: loading,
            descriptor: descriptor,
            readinessMode: .immediateAfterFirstRender
        )

        XCTAssertEqual(ready, .ready(surfaceID: "database:tasks"))
    }

    func testChildReportedReadinessStaysLoadingAfterFirstRender() {
        let descriptor = SidebarRoute.app(UUID(uuidString: "00000000-0000-0000-0000-000000000002")!).surfaceDescriptor
        let loading = SurfaceRouteSupervisor.start(descriptor: descriptor)

        let stillLoading = SurfaceRouteSupervisor.afterFirstRender(
            state: loading,
            descriptor: descriptor,
            readinessMode: .childReported
        )

        XCTAssertEqual(stillLoading, loading)
    }

    func testSurfaceReportsCanUpdateProgressPartialAndReady() {
        let descriptor = SidebarRoute.databaseCollection("tasks").surfaceDescriptor
        let loading = SurfaceRouteSupervisor.start(descriptor: descriptor)

        let progress = SurfaceRouteSupervisor.apply(
            report: .loading(message: "Loading rows", progress: 1.2),
            state: loading,
            descriptor: descriptor
        )
        XCTAssertEqual(
            progress,
            .loading(
                surfaceID: "database:tasks",
                timeoutSeconds: 5,
                message: "Loading rows",
                progress: 1
            )
        )

        let partial = SurfaceRouteSupervisor.apply(
            report: .partial(message: "Showing cached rows"),
            state: progress,
            descriptor: descriptor
        )
        XCTAssertEqual(partial, .partial(surfaceID: "database:tasks", message: "Showing cached rows"))
        XCTAssertFalse(partial.isTerminal)

        XCTAssertEqual(
            SurfaceRouteSupervisor.apply(report: .ready, state: partial, descriptor: descriptor),
            .ready(surfaceID: "database:tasks")
        )
    }

    func testSurfaceReportsCanMarkErrorAndUnavailable() {
        let descriptor = SidebarRoute.app(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!).surfaceDescriptor
        let loading = SurfaceRouteSupervisor.start(descriptor: descriptor)

        XCTAssertEqual(
            SurfaceRouteSupervisor.apply(
                report: .error(message: "Bridge failed"),
                state: loading,
                descriptor: descriptor
            ),
            .error(surfaceID: descriptor.id, message: "Bridge failed")
        )
        XCTAssertEqual(
            SurfaceRouteSupervisor.apply(
                report: .unavailable(reason: "App record is unavailable."),
                state: loading,
                descriptor: descriptor
            ),
            .unavailable(surfaceID: descriptor.id, reason: "App record is unavailable.")
        )
    }

    func testCoreRoutesIgnoreLoadingReports() {
        let descriptor = SidebarRoute.rescue.surfaceDescriptor
        let ready = SurfaceRouteSupervisor.start(descriptor: descriptor)

        XCTAssertEqual(
            SurfaceRouteSupervisor.apply(
                report: .loading(message: "Ignored", progress: 0.5),
                state: ready,
                descriptor: descriptor
            ),
            .ready(surfaceID: "rescue")
        )
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
        let stale = SurfaceRouteSupervisionState.loading(
            surfaceID: "calendar",
            timeoutSeconds: 5,
            message: nil,
            progress: nil
        )

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
