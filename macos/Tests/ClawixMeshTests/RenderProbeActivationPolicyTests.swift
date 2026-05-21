import XCTest
import ClawixCore
@testable import Clawix

final class RenderProbeActivationPolicyTests: XCTestCase {
    func testDebugBuildEnablesRenderProbeByDefault() {
        XCTAssertTrue(RenderProbe.isEnabled(environment: [:], isDebugBuild: true))
    }

    func testReleaseBuildDisablesRenderProbeByDefault() {
        XCTAssertFalse(RenderProbe.isEnabled(environment: [:], isDebugBuild: false))
    }

    func testReleaseBuildEnablesRenderProbeWithEnvironmentOptIn() {
        XCTAssertTrue(RenderProbe.isEnabled(
            environment: [ClawixEnv.renderProbe: "1"],
            isDebugBuild: false
        ))
    }
}
