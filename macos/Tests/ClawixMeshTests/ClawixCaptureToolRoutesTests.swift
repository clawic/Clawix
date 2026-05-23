import XCTest
@testable import Clawix

final class ClawixCaptureToolRoutesTests: XCTestCase {
    func testCaptureToolRoutesCentralizeScreencaptureAndFfmpegCandidates() throws {
        let routesSource = try readSource("ClawixCaptureToolRoutes.swift")
        let appSnapshotSource = try readSource("AppSnapshotCapture.swift")
        let temporaryDirectory = URL(fileURLWithPath: "/tmp", isDirectory: true)

        XCTAssertEqual(ClawixCaptureToolRoutes.screencaptureCLI, "/usr/sbin/screencapture")
        XCTAssertEqual(ClawixSystemToolRoutes.screencaptureCLI, "/usr/sbin/screencapture")
        XCTAssertEqual(ClawixCaptureToolRoutes.appSnapshotTempPrefix, "clawix-appshot")
        XCTAssertEqual(ClawixCaptureToolRoutes.pngExtension, "png")
        XCTAssertEqual(
            ClawixCaptureToolRoutes.appSnapshotURL(
                appSlug: "Example App/One",
                timestamp: 1_779_407_845,
                temporaryDirectory: temporaryDirectory
            ).path,
            "/tmp/clawix-appshot-example-app-one-1779407845.png"
        )
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
        XCTAssertTrue(routesSource.contains("ClawixTemporaryRoutes.systemTemporaryDirectory(fileManager: fileManager)"))
        XCTAssertTrue(routesSource.contains("ClawixSystemToolRoutes.optHomebrewBinTool(\"ffmpeg\")"))
        XCTAssertTrue(routesSource.contains("ClawixSystemToolRoutes.usrLocalBinTool(\"ffmpeg\")"))
        XCTAssertTrue(routesSource.contains("ClawixSystemToolRoutes.usrBinTool(\"ffmpeg\")"))
        XCTAssertTrue(appSnapshotSource.contains("ClawixCaptureToolRoutes.appSnapshotURL(appSlug: slug)"))
        XCTAssertTrue(appSnapshotSource.contains("ClawixCaptureToolRoutes.screencaptureCLI"))
        XCTAssertFalse(routesSource.contains("static let screencaptureCLI = \"/usr/sbin/screencapture\""))
        XCTAssertFalse(routesSource.contains("\"/opt/homebrew/bin/ffmpeg\""))
        XCTAssertFalse(routesSource.contains("\"/usr/local/bin/ffmpeg\""))
        XCTAssertFalse(routesSource.contains("\"/usr/bin/ffmpeg\""))
        XCTAssertFalse(appSnapshotSource.contains("FileManager.default.temporaryDirectory"))
        XCTAssertFalse(appSnapshotSource.contains("URL(fileURLWithPath: \"/usr/sbin/screencapture\")"))
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
