import XCTest
@testable import Clawix

@MainActor
final class ClawixSkillsRoutesTests: XCTestCase {
    func testDefaultExternalSkillSyncRoutesAreCentralized() throws {
        let routesSource = try readSource("Skills/ClawixSkillsRoutes.swift")
        let storeSource = try readSource("Skills/SkillsStore.swift")
        let settingsSource = try readSource("Skills/SkillsSettingsPage.swift")
        let skillsViewSource = try readSource("Skills/SkillsView.swift")
        let detailViewSource = try readSource("Skills/SkillDetailView.swift")
        let userHome = URL(fileURLWithPath: "/Users/demo", isDirectory: true)
        let targets = ClawixSkillsRoutes.defaultSyncTargets(userHomeDirectory: userHome)
        let store = SkillsStore(
            seedBuiltins: true,
            frameworkClient: Self.emptyFrameworkClient(),
            loadMode: .fullCatalog
        )

        XCTAssertEqual(
            ClawixSkillsRoutes.externalSkillsDisplayPath(rootDirectoryName: ".codex"),
            "~/.codex/skills"
        )
        XCTAssertEqual(ClawixSkillsRoutes.skillsDirectoryName, "skills")
        XCTAssertEqual(
            ClawixSkillsRoutes.defaultExternalDirectories.map(\.displayPath),
            ["~/.codex/skills", "~/.hermes/skills", "~/.openclaude/skills", "~/.cursor/skills"]
        )
        XCTAssertEqual(ClawixSkillsRoutes.defaultExternalDirectoriesSummary, "~/.codex/skills, ~/.hermes/skills, etc.")
        XCTAssertEqual(
            targets.map { "\($0.id):\($0.label):\($0.home):\($0.mode.rawValue)" },
            [
                "codex:Codex CLI:/Users/demo/.codex/skills:symlink",
                "hermes:HermesAgent:/Users/demo/.hermes/skills:symlink",
                "openclaude:OpenClaude:/Users/demo/.openclaude/skills:symlink",
                "cursor:Cursor:/Users/demo/.cursor/skills:symlink",
            ]
        )
        XCTAssertEqual(store.syncTargets.map(\.id), ["codex", "hermes", "openclaude", "cursor"])
        XCTAssertEqual(store.syncTargets.map(\.mode), [.symlink, .symlink, .symlink, .symlink])

        XCTAssertTrue(routesSource.contains("ClawixUserHomeRoutes.directory()"))
        XCTAssertTrue(routesSource.contains("ClawixPersistentSurfacePaths.userVisibleHomeChild(rootDirectoryName, skillsDirectoryName)"))
        XCTAssertTrue(routesSource.contains("ClawixPersistentSurfacePaths.expandedUserVisiblePath("))
        XCTAssertTrue(routesSource.contains("displayPath: externalSkillsDisplayPath(rootDirectoryName: \".codex\")"))
        XCTAssertFalse(routesSource.contains("displayPath: \"~/.codex/skills\""))
        XCTAssertFalse(routesSource.contains("displayPath: \"~/.hermes/skills\""))
        XCTAssertFalse(routesSource.contains("displayPath: \"~/.openclaude/skills\""))
        XCTAssertFalse(routesSource.contains("displayPath: \"~/.cursor/skills\""))
        XCTAssertFalse(routesSource.contains("displayPath.hasPrefix(\"~/\")"))
        XCTAssertFalse(routesSource.contains("displayPath.dropFirst(2)"))
        XCTAssertTrue(storeSource.contains("ClawixSkillsRoutes.defaultSyncTargets()"))
        XCTAssertTrue(settingsSource.contains("ClawixSkillsRoutes.defaultExternalDirectories.prefix(2)"))
        XCTAssertTrue(skillsViewSource.contains("ClawixSkillsRoutes.defaultExternalDirectoriesSummary"))
        XCTAssertTrue(detailViewSource.contains("ClawixSkillsRoutes.defaultExternalDirectoriesSummary"))
        for source in [storeSource, settingsSource, skillsViewSource, detailViewSource] {
            XCTAssertFalse(source.contains("~/.codex/skills"))
            XCTAssertFalse(source.contains("~/.hermes/skills"))
            XCTAssertFalse(source.contains("~/.openclaude/skills"))
            XCTAssertFalse(source.contains("~/.cursor/skills"))
        }
        XCTAssertFalse(storeSource.contains("NSString(\"~/."))
    }

    private static func emptyFrameworkClient() -> ClawJSFrameworkRecordsClient {
        ClawJSFrameworkRecordsClient(runner: .init { args in
            if args == ["skills", "list", "--json", "--kind", "clawix_skill"] {
                return Data(#"{"ok":true,"data":{"items":[]}}"#.utf8)
            }
            if args == ["skills", "get", "clawix-active-skills", "--json"] {
                return Data(#"{"ok":true,"data":null}"#.utf8)
            }
            return Data(#"{"ok":true,"data":{}}"#.utf8)
        })
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
