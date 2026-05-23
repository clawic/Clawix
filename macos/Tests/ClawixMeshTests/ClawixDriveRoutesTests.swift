import XCTest
@testable import Clawix

final class ClawixDriveRoutesTests: XCTestCase {
    func testDriveTemporaryRoutesAreCentralized() throws {
        let routesSource = try readSource("Drive/ClawixDriveRoutes.swift")
        let clientSource = try readSource("ClawJS/ClawJSDriveClient.swift")
        let toolsSource = try readSource("Drive/DriveTools.swift")
        let temporaryDirectory = URL(fileURLWithPath: "/tmp", isDirectory: true)

        XCTAssertEqual(ClawixDriveRoutes.uploadBytesSeparator, "-")
        XCTAssertEqual(
            ClawixDriveRoutes.uploadBytesTempURL(
                fileName: "report.pdf",
                id: "upload-token",
                temporaryDirectory: temporaryDirectory
            ).path,
            "/tmp/upload-token-report.pdf"
        )
        XCTAssertEqual(
            ClawixDriveRoutes.readTempURL(
                itemId: "drive-item",
                id: "read-token",
                temporaryDirectory: temporaryDirectory
            ).path,
            "/tmp/drive-item-read-token"
        )

        XCTAssertTrue(routesSource.contains("ClawixTemporaryRoutes.systemTemporaryDirectory(fileManager: fileManager)"))
        XCTAssertFalse(routesSource.contains("fileManager.temporaryDirectory"))
        XCTAssertTrue(clientSource.contains("ClawixDriveRoutes.uploadBytesTempURL(fileName: fileName)"))
        XCTAssertTrue(toolsSource.contains("ClawixDriveRoutes.readTempURL(itemId: itemId)"))
        XCTAssertFalse(clientSource.contains("FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + \"-\" + fileName)"))
        XCTAssertFalse(toolsSource.contains("FileManager.default.temporaryDirectory.appendingPathComponent(\"\\(itemId)-\\(UUID().uuidString)"))
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
