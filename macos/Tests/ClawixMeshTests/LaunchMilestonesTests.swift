import XCTest
@testable import Clawix

final class LaunchMilestonesTests: XCTestCase {
    override func tearDown() {
        LaunchMilestones.resetForTests()
        super.tearDown()
    }

    func testMilestoneNamesAreStable() {
        XCTAssertEqual(LaunchMilestones.names, [
            "process_start",
            "app_init_start",
            "app_init_end",
            "first_window",
            "first_sidebar_paint",
            "first_chat_interactive",
            "core_ready",
        ])
    }

    func testMilestonesEmitOncePerProcess() {
        var emitted: [String] = []
        LaunchMilestones.testEmitter = { emitted.append($0.rawValue) }

        LaunchMilestones.mark(.processStart)
        LaunchMilestones.mark(.processStart)
        LaunchMilestones.mark(.firstWindow)
        LaunchMilestones.mark(.firstWindow)

        XCTAssertEqual(emitted, ["process_start", "first_window"])
    }
}
