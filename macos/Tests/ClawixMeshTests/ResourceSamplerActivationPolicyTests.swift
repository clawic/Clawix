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

    func testExplicitDiagnosticSampleIncludesDerivedResourceMetrics() {
        let first = ResourceSampler.diagnosticSampleNow()
        Thread.sleep(forTimeInterval: 0.06)
        let second = ResourceSampler.diagnosticSampleNow()

        XCTAssertGreaterThan(second.sample.timestamp, first.sample.timestamp)
        XCTAssertGreaterThanOrEqual(second.sample.residentBytes, UInt64(0))
        XCTAssertGreaterThanOrEqual(second.sample.footprintBytes, UInt64(0))
        XCTAssertTrue(second.sample.processCpuPercent.isFinite)
        if let memorySlope = second.memorySlopeMBPerMin {
            XCTAssertTrue(memorySlope.isFinite)
        }
        if let timerWakeups = second.timerWakeups {
            XCTAssertGreaterThanOrEqual(timerWakeups, UInt64(0))
        }
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
