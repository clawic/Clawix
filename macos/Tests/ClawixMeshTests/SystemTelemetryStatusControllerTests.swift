import XCTest
@testable import Clawix

final class SystemTelemetryStatusControllerTests: XCTestCase {
    @MainActor
    func testStatusControllerStartDoesNotRefreshOrScheduleTelemetry() async {
        let probe = StatusControllerProbe()
        let (controller, counter) = makeStatusController(probe: probe)

        controller.start()
        let counts = await counter.counts()

        XCTAssertEqual(probe.diagnosticsActivations, 0)
        XCTAssertEqual(probe.recordCalls, [])
        XCTAssertEqual(probe.renderCount, 0)
        XCTAssertEqual(counts.widgets, 0)
        XCTAssertEqual(counts.snapshots, 0)
    }

    @MainActor
    func testStatusControllerActivatesTelemetryOnUserSurfaceOpen() async {
        let probe = StatusControllerProbe()
        let (controller, counter) = makeStatusController(probe: probe)

        await controller.activateFromUserSurfaceAndRefresh()
        let counts = await counter.counts()

        XCTAssertEqual(probe.diagnosticsActivations, 0)
        XCTAssertEqual(probe.recordCalls, [false])
        XCTAssertEqual(probe.renderCount, 1)
        XCTAssertEqual(counts.widgets, 1)
        XCTAssertEqual(counts.snapshots, 1)
    }

    @MainActor
    func testStatusControllerDoesNotActivateWhenMaturityBlocksTelemetry() async {
        let probe = StatusControllerProbe()
        let (controller, counter) = makeStatusController(probe: probe, isCapabilityVisible: { false })

        await controller.activateFromUserSurfaceAndRefresh()
        let counts = await counter.counts()

        XCTAssertEqual(probe.diagnosticsActivations, 0)
        XCTAssertEqual(probe.recordCalls, [])
        XCTAssertEqual(probe.renderCount, 0)
        XCTAssertEqual(counts.widgets, 0)
        XCTAssertEqual(counts.snapshots, 0)
    }

    @MainActor
    func testStatusControllerActivationIsIdempotent() async {
        let probe = StatusControllerProbe()
        let (controller, counter) = makeStatusController(probe: probe)

        await controller.activateFromUserSurfaceAndRefresh()
        await controller.activateFromUserSurfaceAndRefresh()
        let counts = await counter.counts()

        XCTAssertEqual(probe.diagnosticsActivations, 0)
        XCTAssertEqual(probe.recordCalls, [false, false])
        XCTAssertEqual(probe.renderCount, 2)
        XCTAssertEqual(counts.widgets, 2)
        XCTAssertEqual(counts.snapshots, 1)
    }

    @MainActor
    func testStatusControllerDoesNotScheduleTimerAfterActivation() async {
        let probe = StatusControllerProbe()
        let (controller, counter) = makeStatusController(probe: probe)

        await controller.activateFromUserSurfaceAndRefresh()
        let counts = await counter.counts()

        XCTAssertEqual(probe.recordCalls, [false])
        XCTAssertEqual(probe.renderCount, 1)
        XCTAssertEqual(counts.widgets, 1)
        XCTAssertEqual(counts.snapshots, 1)
    }
}
