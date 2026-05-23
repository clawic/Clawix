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

    func testPrepareLogFilePreservesWorkoutMarkers() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let logURL = directory.appendingPathComponent("clawix-renders.log")
        try "[1.000] === MARK: scroll-chat-start ===\n".write(to: logURL, atomically: true, encoding: .utf8)

        RenderProbe.prepareLogFile(at: logURL.path)

        let preserved = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(preserved.contains("MARK: scroll-chat-start"))
    }
}
