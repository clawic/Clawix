import XCTest
@testable import Clawix

final class ClawixDiagnosticLogRoutesTests: XCTestCase {
    func testDiagnosticTempLogRoutesCentralizeDebugLogPaths() throws {
        let routesSource = try readSource("Diagnostics/ClawixDiagnosticLogRoutes.swift")

        XCTAssertEqual(ClawixDiagnosticLogRoutes.tempDirectory, "/tmp")
        XCTAssertEqual(ClawixDiagnosticLogRoutes.renderProbeLogPath(role: nil), "/tmp/clawix-renders.log")
        XCTAssertEqual(ClawixDiagnosticLogRoutes.renderProbeLogPath(role: ""), "/tmp/clawix-renders.log")
        XCTAssertEqual(
            ClawixDiagnosticLogRoutes.renderProbeLogPath(role: "com.clawix.preview"),
            "/tmp/clawix-renders-com-clawix-preview.log"
        )
        XCTAssertEqual(ClawixDiagnosticLogRoutes.renderProbeLogPath(role: "."), "/tmp/clawix-renders-aux.log")
        XCTAssertEqual(ClawixDiagnosticLogRoutes.quickAskLogURL.path, "/tmp/clawix-quickask.log")
        XCTAssertEqual(ClawixDiagnosticLogRoutes.hotkeyDebugLogURL.path, "/tmp/clawix-hotkey.log")
        XCTAssertTrue(routesSource.contains("ClawixTemporaryRoutes.unixTemporaryDirectoryPath"))
        XCTAssertTrue(routesSource.contains("ClawixTemporaryRoutes.unixTemporaryFileURL(fileName: fileName)"))
        XCTAssertFalse(routesSource.contains("static let tempDirectory = \"/tmp\""))
        XCTAssertFalse(routesSource.contains("URL(fileURLWithPath: tempDirectory"))
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
