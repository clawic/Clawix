import XCTest
@testable import Clawix

final class ClawixDatabaseRoutesTests: XCTestCase {
    func testDatabaseTemporaryRoutesAreCentralized() throws {
        let routesSource = try readSource("Database/ClawixDatabaseRoutes.swift")
        let clientSource = try readSource("Database/DatabaseClient.swift")
        let operationsSource = try readSource("Database/DatabaseWorkbenchOperations.swift")
        let rendererSource = try readSource("Database/Renderers/FieldRenderers.swift")
        let temporaryDirectory = URL(fileURLWithPath: "/tmp", isDirectory: true)

        XCTAssertEqual(
            ClawixDatabaseRoutes.multipartUploadBodyURL(id: "body", temporaryDirectory: temporaryDirectory).path,
            "/tmp/clawix-database-upload-body"
        )
        XCTAssertEqual(
            ClawixDatabaseRoutes.uploadSourceURL(id: "source", temporaryDirectory: temporaryDirectory).path,
            "/tmp/clawix-database-upload-source-source"
        )
        XCTAssertEqual(
            ClawixDatabaseRoutes.restoreReplacementURL(
                for: URL(fileURLWithPath: "/Users/example/data.sqlite"),
                id: "restore"
            ).path,
            "/Users/example/data.sqlite.restore-restore.tmp"
        )
        XCTAssertEqual(
            ClawixDatabaseRoutes.downloadedFilePreviewURL(
                fileId: "file-123",
                temporaryDirectory: temporaryDirectory
            ).path,
            "/tmp/file-123-preview"
        )

        XCTAssertTrue(routesSource.contains("ClawixTemporaryRoutes.systemTemporaryDirectory(fileManager: fileManager)"))
        XCTAssertFalse(routesSource.contains("fileManager.temporaryDirectory"))
        XCTAssertTrue(clientSource.contains("ClawixDatabaseRoutes.multipartUploadBodyURL()"))
        XCTAssertTrue(clientSource.contains("ClawixDatabaseRoutes.uploadSourceURL()"))
        XCTAssertTrue(operationsSource.contains("ClawixDatabaseRoutes.restoreReplacementURL(for: targetURL)"))
        XCTAssertTrue(rendererSource.contains("ClawixDatabaseRoutes.downloadedFilePreviewURL(fileId: id)"))
        XCTAssertFalse(clientSource.contains("FileManager.default.temporaryDirectory"))
        XCTAssertFalse(clientSource.contains("clawix-database-upload-\\(UUID().uuidString)"))
        XCTAssertFalse(operationsSource.contains(".restore-\\(UUID().uuidString).tmp"))
        XCTAssertFalse(rendererSource.contains("NSTemporaryDirectory()"))
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
