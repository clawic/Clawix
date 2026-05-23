import XCTest
@testable import Clawix

final class ClawixCaptureToolRoutesTests: XCTestCase {
    func testCaptureToolRoutesCentralizeScreencaptureAndFfmpegCandidates() throws {
        let routesSource = try readSource("ClawixCaptureToolRoutes.swift")

        XCTAssertEqual(ClawixCaptureToolRoutes.screencaptureCLI, "/usr/sbin/screencapture")
        XCTAssertEqual(ClawixSystemToolRoutes.screencaptureCLI, "/usr/sbin/screencapture")
        XCTAssertEqual(
            ClawixCaptureToolRoutes.ffmpegCandidatePaths,
            [
                "/opt/homebrew/bin/ffmpeg",
                "/usr/local/bin/ffmpeg",
                "/usr/bin/ffmpeg",
            ]
        )
        XCTAssertEqual(
            ClawixCaptureToolRoutes.ffmpegCandidateURLs().map(\.path),
            ClawixCaptureToolRoutes.ffmpegCandidatePaths
        )
        XCTAssertTrue(routesSource.contains("static let screencaptureCLI = ClawixSystemToolRoutes.screencaptureCLI"))
        XCTAssertTrue(routesSource.contains("ClawixSystemToolRoutes.optHomebrewBinTool(\"ffmpeg\")"))
        XCTAssertTrue(routesSource.contains("ClawixSystemToolRoutes.usrLocalBinTool(\"ffmpeg\")"))
        XCTAssertTrue(routesSource.contains("ClawixSystemToolRoutes.usrBinTool(\"ffmpeg\")"))
        XCTAssertFalse(routesSource.contains("static let screencaptureCLI = \"/usr/sbin/screencapture\""))
        XCTAssertFalse(routesSource.contains("\"/opt/homebrew/bin/ffmpeg\""))
        XCTAssertFalse(routesSource.contains("\"/usr/local/bin/ffmpeg\""))
        XCTAssertFalse(routesSource.contains("\"/usr/bin/ffmpeg\""))
    }

    private func readSource(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.sources, isDirectory: true)
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.clawix, isDirectory: true)
        return try String(
            contentsOf: root.appendingPathComponent(relativePath, isDirectory: false),
            encoding: .utf8
        )
    }
}
