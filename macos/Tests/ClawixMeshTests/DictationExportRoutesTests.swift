import XCTest
@testable import Clawix

final class DictationExportRoutesTests: XCTestCase {
    func testDictationExportTemporaryRoutesAreCentralized() throws {
        let routesSource = try readSource("Dictation/DictationExportRoutes.swift")
        let exportSource = try readSource("Dictation/ExportService.swift")
        let temporaryDirectory = URL(fileURLWithPath: "/tmp", isDirectory: true)

        XCTAssertEqual(DictationExportRoutes.transcriptsPrefix, "clawix-transcripts")
        XCTAssertEqual(DictationExportRoutes.settingsPrefix, "clawix-dictation-settings")
        XCTAssertEqual(DictationExportRoutes.csvExtension, "csv")
        XCTAssertEqual(DictationExportRoutes.jsonExtension, "json")
        XCTAssertEqual(
            DictationExportRoutes.transcriptsExportURL(
                timestamp: 1_779_408_600.25,
                temporaryDirectory: temporaryDirectory
            ).path,
            "/tmp/clawix-transcripts-1779408600.25.csv"
        )
        XCTAssertEqual(
            DictationExportRoutes.settingsExportURL(
                timestamp: 1_779_408_600.25,
                temporaryDirectory: temporaryDirectory
            ).path,
            "/tmp/clawix-dictation-settings-1779408600.25.json"
        )

        XCTAssertTrue(routesSource.contains("ClawixTemporaryRoutes.systemTemporaryDirectory(fileManager: fileManager)"))
        XCTAssertFalse(routesSource.contains("fileManager.temporaryDirectory"))
        XCTAssertTrue(exportSource.contains("DictationExportRoutes.transcriptsExportURL()"))
        XCTAssertTrue(exportSource.contains("DictationExportRoutes.settingsExportURL()"))
        XCTAssertFalse(exportSource.contains("NSTemporaryDirectory()"))
        XCTAssertFalse(exportSource.contains("clawix-transcripts-\\("))
        XCTAssertFalse(exportSource.contains("clawix-dictation-settings-\\("))
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
