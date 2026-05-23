import XCTest
@testable import Clawix

final class ClawixFrameworkResourceRoutesTests: XCTestCase {
    func testFrameworkResourceStoreRootsAreCentralized() throws {
        let appsStoreSource = try readSource("Apps/AppsStore.swift")
        let designStoreSource = try readSource("Design/DesignStore.swift")
        let editorStoreSource = try readSource("Design/EditorStore.swift")
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let appsRoot = ClawixFrameworkResourceRoutes.appsRootURL()
        let designRoot = ClawixFrameworkResourceRoutes.designRootURL()
        let documentsRoot = ClawixFrameworkResourceRoutes.editorDocumentsRootURL(designRootURL: designRoot)

        XCTAssertEqual(ClawixFrameworkResourceRoutes.appsDirectoryName, "apps")
        XCTAssertEqual(ClawixFrameworkResourceRoutes.designDirectoryName, "design")
        XCTAssertEqual(ClawixFrameworkResourceRoutes.documentsDirectoryName, "documents")
        XCTAssertEqual(ClawixFrameworkResourceRoutes.stylesDirectoryName, "styles")
        XCTAssertEqual(ClawixFrameworkResourceRoutes.templatesDirectoryName, "templates")
        XCTAssertEqual(ClawixFrameworkResourceRoutes.referencesDirectoryName, "references")
        XCTAssertEqual(ClawixFrameworkResourceRoutes.appManifestFileName, "manifest.json")
        XCTAssertEqual(ClawixFrameworkResourceRoutes.editorDocumentFileName, "document.json")
        XCTAssertEqual(
            appsRoot.standardizedFileURL.path,
            home.appendingPathComponent(".claw/apps", isDirectory: true).standardizedFileURL.path
        )
        XCTAssertEqual(
            designRoot.standardizedFileURL.path,
            home.appendingPathComponent(".claw/design", isDirectory: true).standardizedFileURL.path
        )
        XCTAssertEqual(
            documentsRoot.standardizedFileURL.path,
            home.appendingPathComponent(".claw/design/documents", isDirectory: true).standardizedFileURL.path
        )
        XCTAssertEqual(
            ClawixFrameworkResourceRoutes.stylesRootURL(designRootURL: designRoot).lastPathComponent,
            "styles"
        )
        XCTAssertEqual(
            ClawixFrameworkResourceRoutes.templatesRootURL(designRootURL: designRoot).lastPathComponent,
            "templates"
        )
        XCTAssertEqual(
            ClawixFrameworkResourceRoutes.referencesRootURL(designRootURL: designRoot).lastPathComponent,
            "references"
        )
        XCTAssertEqual(
            ClawixFrameworkResourceRoutes.editorDocumentManifestURL(
                documentDirectory: ClawixFrameworkResourceRoutes.editorDocumentDirectory(
                    documentId: "doc-1",
                    documentsRootURL: documentsRoot
                )
            ).lastPathComponent,
            "document.json"
        )

        XCTAssertTrue(appsStoreSource.contains("ClawixFrameworkResourceRoutes.appManifestFileName"))
        XCTAssertTrue(appsStoreSource.contains("ClawixFrameworkResourceRoutes.appsRootURL()"))
        XCTAssertTrue(designStoreSource.contains("ClawixFrameworkResourceRoutes.designRootURL()"))
        XCTAssertTrue(designStoreSource.contains("ClawixFrameworkResourceRoutes.stylesRootURL(designRootURL: rootURL)"))
        XCTAssertTrue(designStoreSource.contains("ClawixFrameworkResourceRoutes.templatesRootURL(designRootURL: rootURL)"))
        XCTAssertTrue(designStoreSource.contains("ClawixFrameworkResourceRoutes.referencesRootURL(designRootURL: rootURL)"))
        XCTAssertTrue(editorStoreSource.contains("ClawixFrameworkResourceRoutes.editorDocumentFileName"))
        XCTAssertTrue(editorStoreSource.contains("ClawixFrameworkResourceRoutes.editorDocumentsRootURL()"))
        XCTAssertTrue(editorStoreSource.contains("ClawixFrameworkResourceRoutes.editorDocumentDirectory("))
        XCTAssertTrue(editorStoreSource.contains("ClawixFrameworkResourceRoutes.editorDocumentManifestURL("))
        for source in [appsStoreSource, designStoreSource, editorStoreSource] {
            XCTAssertFalse(source.contains("frameworkGlobalChild(\"apps\""))
            XCTAssertFalse(source.contains("frameworkGlobalChild(\"design\""))
            XCTAssertFalse(source.contains("appendingPathComponent(\"documents\""))
            XCTAssertFalse(source.contains("manifestName = \"manifest.json\""))
            XCTAssertFalse(source.contains("manifestName = \"document.json\""))
        }
        XCTAssertFalse(designStoreSource.contains("appendingPathComponent(\"styles\""))
        XCTAssertFalse(designStoreSource.contains("appendingPathComponent(\"templates\""))
        XCTAssertFalse(designStoreSource.contains("appendingPathComponent(\"references\""))
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
