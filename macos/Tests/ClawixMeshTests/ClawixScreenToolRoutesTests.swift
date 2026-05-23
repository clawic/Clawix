import XCTest
@testable import Clawix

final class ClawixScreenToolRoutesTests: XCTestCase {
    func testScreenToolTemporaryRoutesAreCentralized() throws {
        let routesSource = try readSource("ScreenTools/ClawixScreenToolRoutes.swift")
        let serviceSource = try readSource("ScreenTools/ScreenToolService.swift")
        let temporaryDirectory = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let recordingURL = URL(fileURLWithPath: "/Users/demo/Movies/capture.mov", isDirectory: false)

        XCTAssertEqual(ClawixScreenToolRoutes.scrollingCapturePrefix, "clawix-scrolling")
        XCTAssertEqual(ClawixScreenToolRoutes.scrollingCaptureExtension, "png")
        XCTAssertEqual(ClawixScreenToolRoutes.processedRecordingSuffix, "processed")
        XCTAssertEqual(ClawixScreenToolRoutes.recordingExtension, "mov")
        XCTAssertEqual(
            ClawixScreenToolRoutes.scrollingCaptureFrameURL(
                index: 2,
                id: "frame-token",
                temporaryDirectory: temporaryDirectory
            ).path,
            "/tmp/clawix-scrolling-frame-token-2.png"
        )
        XCTAssertEqual(
            ClawixScreenToolRoutes.processedRecordingURL(for: recordingURL, id: "recording-token").path,
            "/Users/demo/Movies/.capture-processed-recording-token.mov"
        )

        XCTAssertTrue(routesSource.contains("ClawixTemporaryRoutes.systemTemporaryDirectory(fileManager: fileManager)"))
        XCTAssertFalse(routesSource.contains("fileManager.temporaryDirectory"))
        XCTAssertTrue(serviceSource.contains("ClawixScreenToolRoutes.scrollingCaptureFrameURL(index: index)"))
        XCTAssertTrue(serviceSource.contains("ClawixScreenToolRoutes.processedRecordingURL(for: url)"))
        XCTAssertFalse(serviceSource.contains("clawix-scrolling-\\(UUID().uuidString)-\\(index).png"))
        XCTAssertFalse(serviceSource.contains("-processed-\\(UUID().uuidString).mov"))
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
