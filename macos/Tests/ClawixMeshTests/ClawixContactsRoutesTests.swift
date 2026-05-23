import XCTest
@testable import Clawix

final class ClawixContactsRoutesTests: XCTestCase {
    func testContactVCardTemporaryRoutesAreCentralized() throws {
        let routesSource = try readSource("Contacts/ClawixContactsRoutes.swift")
        let toolbarSource = try readSource("Contacts/Views/ContactsToolbar.swift")
        let detailSource = try readSource("Contacts/Views/ContactDetail.swift")
        let temporaryDirectory = URL(fileURLWithPath: "/tmp", isDirectory: true)

        XCTAssertEqual(ClawixContactsRoutes.vCardExtension, "vcf")
        XCTAssertEqual(ClawixTemporaryRoutes.nullDevicePath, "/dev/null")
        XCTAssertEqual(ClawixContactsRoutes.placeholderDragPath, ClawixTemporaryRoutes.nullDevicePath)
        XCTAssertEqual(ClawixContactsRoutes.placeholderDragURL().path, "/dev/null")
        XCTAssertEqual(
            ClawixContactsRoutes.vCardExportURL(
                fullName: "Ada Lovelace",
                temporaryDirectory: temporaryDirectory
            ).path,
            "/tmp/Ada Lovelace.vcf"
        )

        XCTAssertTrue(routesSource.contains("ClawixTemporaryRoutes.systemTemporaryDirectory(fileManager: fileManager)"))
        XCTAssertTrue(routesSource.contains("static let placeholderDragPath = ClawixTemporaryRoutes.nullDevicePath"))
        XCTAssertTrue(routesSource.contains("ClawixTemporaryRoutes.nullDeviceURL"))
        XCTAssertFalse(routesSource.contains("fileManager.temporaryDirectory"))
        XCTAssertFalse(routesSource.contains("static let placeholderDragPath = \"/dev/null\""))
        XCTAssertTrue(toolbarSource.contains("ClawixContactsRoutes.vCardExportURL(fullName: c.fullName)"))
        XCTAssertTrue(detailSource.contains("ClawixContactsRoutes.vCardExportURL(fullName: contact.fullName)"))
        XCTAssertTrue(detailSource.contains("ClawixContactsRoutes.placeholderDragURL()"))
        XCTAssertFalse(toolbarSource.contains("FileManager.default.temporaryDirectory"))
        XCTAssertFalse(detailSource.contains("FileManager.default.temporaryDirectory"))
        XCTAssertFalse(detailSource.contains("URL(fileURLWithPath: \"/dev/null\")"))
        XCTAssertFalse(toolbarSource.contains(".appendingPathComponent(\"\\(c.fullName).vcf\")"))
        XCTAssertFalse(detailSource.contains(".appendingPathComponent(\"\\(contact.fullName).vcf\")"))
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
