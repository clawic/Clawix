import XCTest
@testable import Clawix

final class ClawixMCPRoutesTests: XCTestCase {
    func testSuggestedWorkingDirectoryDisplayPathIsCentralized() throws {
        let routesSource = try readSource("MCP/ClawixMCPRoutes.swift")
        let editorSource = try readSource("MCP/MCPEditorSheet.swift")
        let localizableSource = try readSource("Resources/Localizable.xcstrings")

        XCTAssertEqual(ClawixMCPRoutes.suggestedWorkingDirectoryDisplayPath, "~/code")
        XCTAssertTrue(routesSource.contains("ClawixPersistentSurfacePaths.userVisibleHomeChild(suggestedCodeWorkspaceDirectoryName)"))
        XCTAssertTrue(editorSource.contains("ClawixMCPRoutes.suggestedWorkingDirectoryDisplayPath"))
        XCTAssertFalse(editorSource.contains("placeholder: \"~/code\""))
        XCTAssertFalse(localizableSource.contains(#""~/code""#))
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
