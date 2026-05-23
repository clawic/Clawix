import XCTest
@testable import Clawix

final class WorktreesPanelBoundaryTests: XCTestCase {
    func testWorktreesPanelUsesCentralGitToolRouteAndRemainsReadOnly() throws {
        let source = try readSource("WorktreesPanel.swift")

        XCTAssertEqual(ClawixSystemToolRoutes.gitCLI, "/usr/bin/git")
        XCTAssertTrue(source.contains("ClawixSystemToolRoutes.gitCLI"))
        XCTAssertTrue(source.contains("\"worktree\", \"list\", \"--porcelain\""))
        XCTAssertFalse(source.contains("URL(fileURLWithPath: \"/usr/bin/git\")"))
        XCTAssertFalse(source.contains("\"worktree\", \"add\""))
        XCTAssertFalse(source.contains("\"worktree\", \"remove\""))
        XCTAssertFalse(source.contains("\"worktree\", \"prune\""))
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
