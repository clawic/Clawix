import XCTest
@testable import Clawix

final class ClawixTerminalRoutesTests: XCTestCase {
    func testTerminalRoutesCentralizeDefaultShellAndHomeResolution() throws {
        let routesSource = try readSource("Terminal/ClawixTerminalRoutes.swift")
        let sessionSource = try readSource("Terminal/TerminalSession.swift")
        let storeSource = try readSource("Terminal/TerminalSessionStore.swift")
        let panelSource = try readSource("Terminal/TerminalPanel.swift")
        let tabSource = try readSource("Terminal/TerminalTab.swift")
        let tabBarSource = try readSource("Terminal/TerminalTabBar.swift")
        let shortcutsSource = try readSource("Terminal/TerminalShortcutsInstaller.swift")
        let viewMenuCommandsSource = try readSource("ViewMenuCommands.swift")

        XCTAssertEqual(ClawixTerminalRoutes.defaultShell, "/bin/zsh")
        XCTAssertEqual(ClawixSystemToolRoutes.zshCLI, "/bin/zsh")
        XCTAssertEqual(ClawixTerminalRoutes.resolvedShell(environment: [:]), "/bin/zsh")
        XCTAssertEqual(
            ClawixTerminalRoutes.resolvedShell(environment: ["SHELL": "/usr/local/bin/fish"]),
            "/usr/local/bin/fish"
        )
        XCTAssertFalse(ClawixTerminalRoutes.userHomePath().isEmpty)
        XCTAssertFalse(ClawixUserHomeRoutes.path().isEmpty)
        XCTAssertTrue(routesSource.contains("static let defaultShell = ClawixSystemToolRoutes.zshCLI"))
        XCTAssertTrue(routesSource.contains("ClawixUserHomeRoutes.path()"))
        XCTAssertFalse(routesSource.contains("static let defaultShell = \"/bin/zsh\""))
        XCTAssertFalse(routesSource.contains("NSHomeDirectory()"))

        for source in [sessionSource, storeSource, panelSource, tabSource, tabBarSource, shortcutsSource, viewMenuCommandsSource] {
            XCTAssertTrue(source.contains("ClawixTerminalRoutes.userHomePath()"))
            XCTAssertFalse(source.contains("NSHomeDirectory()"))
        }
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
