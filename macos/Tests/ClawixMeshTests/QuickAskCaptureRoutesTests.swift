import XCTest
@testable import Clawix

final class QuickAskCaptureRoutesTests: XCTestCase {
    func testQuickAskCaptureCacheRoutesAreCentralized() throws {
        let routesSource = try readSource("QuickAsk/QuickAskCaptureRoutes.swift")
        let actionsSource = try readSource("QuickAsk/QuickAskActions.swift")
        let cameraSource = try readSource("QuickAsk/QuickAskCameraSheet.swift")
        let clipboardSource = try readSource("QuickAsk/QuickAskClipboardSniffer.swift")
        let controllerSource = try readSource("QuickAsk/QuickAskController.swift")
        let viewSource = try readSource("QuickAsk/QuickAskView.swift")
        let cachesRoot = URL(fileURLWithPath: "/Users/demo/Library/Caches", isDirectory: true)

        XCTAssertEqual(QuickAskCaptureRoutes.capturesDirectoryName, "Clawix-Captures")
        XCTAssertEqual(QuickAskCaptureRoutes.defaultCaptureExtension, "png")
        XCTAssertEqual(QuickAskCaptureRoutes.placeholderAttachmentPath, ClawixTemporaryRoutes.nullDevicePath)
        XCTAssertEqual(QuickAskCaptureRoutes.placeholderAttachmentURL().path, "/dev/null")
        XCTAssertEqual(
            QuickAskCaptureRoutes.capturesDirectoryURL(cachesRoot: cachesRoot).path,
            "/Users/demo/Library/Caches/Clawix-Captures"
        )
        XCTAssertEqual(
            QuickAskCaptureRoutes.captureFileURL(
                prefix: "drop",
                timestamp: 1_779_407_845,
                fileManager: FileManager.default
            )?.lastPathComponent,
            "drop-1779407845000.png"
        )
        XCTAssertEqual(
            QuickAskCaptureRoutes.captureFileURLWithTemporaryFallback(
                prefix: "selection",
                timestamp: 1_779_407_845
            ).lastPathComponent,
            "selection-1779407845000.png"
        )

        XCTAssertTrue(routesSource.contains("ClawixTemporaryRoutes.systemTemporaryDirectory(fileManager: fileManager)"))
        XCTAssertTrue(routesSource.contains("static let placeholderAttachmentPath = ClawixTemporaryRoutes.nullDevicePath"))
        XCTAssertTrue(routesSource.contains("ClawixTemporaryRoutes.nullDeviceURL"))
        XCTAssertFalse(routesSource.contains("fileManager.temporaryDirectory"))
        XCTAssertFalse(routesSource.contains("static let placeholderAttachmentPath = \"/dev/null\""))
        for source in [actionsSource, cameraSource, clipboardSource, controllerSource, viewSource] {
            XCTAssertTrue(source.contains("QuickAskCaptureRoutes.captureFileURL"))
            XCTAssertFalse(source.contains("appendingPathComponent(ClawixPersistentSurfacePaths.components.captures"))
            XCTAssertFalse(source.contains(".urls(for: .cachesDirectory, in: .userDomainMask)"))
        }
        XCTAssertTrue(actionsSource.contains("QuickAskCaptureRoutes.captureFileURLWithTemporaryFallback(prefix: prefix)"))
        XCTAssertTrue(controllerSource.contains("QuickAskCaptureRoutes.placeholderAttachmentURL()"))
        XCTAssertTrue(viewSource.contains("QuickAskCaptureRoutes.placeholderAttachmentURL()"))
        XCTAssertFalse(actionsSource.contains("FileManager.default.temporaryDirectory"))
        XCTAssertFalse(controllerSource.contains("URL(fileURLWithPath: \"/dev/null\")"))
        XCTAssertFalse(viewSource.contains("URL(fileURLWithPath: \"/dev/null\")"))
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
