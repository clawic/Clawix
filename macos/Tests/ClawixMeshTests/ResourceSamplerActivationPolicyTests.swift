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

final class HangDetectorActivationPolicyTests: XCTestCase {
    func testDefaultEnvironmentDoesNotStartHangDetector() {
        XCTAssertFalse(HangDetector.shouldStartFromEnvironment(environment: [:]))
    }

    func testDiagnosticsSamplerEnvironmentStartsHangDetector() {
        XCTAssertTrue(HangDetector.shouldStartFromEnvironment(
            environment: [ClawixEnv.forceDiagnosticsSamplers: "1"]
        ))
    }

    func testHangDetectorEnvironmentStartsHangDetector() {
        XCTAssertTrue(HangDetector.shouldStartFromEnvironment(
            environment: [ClawixEnv.forceHangDetector: "1"]
        ))
    }

    func testDebugBuildDoesNotStartHangDetectorWithoutOptIn() {
        XCTAssertFalse(HangDetector.shouldStartFromEnvironment(environment: [:]))
    }
}
