import XCTest
import ClawixCore
@testable import Clawix

final class ResourceSamplerActivationPolicyTests: XCTestCase {
    func testDefaultEnvironmentDoesNotStartPeriodicSampler() {
        XCTAssertFalse(ResourceSampler.shouldStartPeriodicSampler(environment: [:]))
    }

    func testDiagnosticsEnvironmentStartsPeriodicSampler() {
        XCTAssertTrue(ResourceSampler.shouldStartPeriodicSampler(
            environment: [ClawixEnv.forceDiagnosticsSamplers: "1"]
        ))
    }

    func testDebugBuildDoesNotStartPeriodicSamplerWithoutOptIn() {
        XCTAssertFalse(ResourceSampler.shouldStartPeriodicSampler(environment: [:]))
    }
}
