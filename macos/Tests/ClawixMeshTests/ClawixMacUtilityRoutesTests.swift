import XCTest
@testable import Clawix

final class ClawixMacUtilityRoutesTests: XCTestCase {
    func testMacUtilityRoutesCentralizeSystemToolsAndAppleApps() throws {
        let routesSource = try readSource("MacUtilities/ClawixMacUtilityRoutes.swift")

        XCTAssertEqual(ClawixMacUtilityRoutes.pmsetCLI, "/usr/bin/pmset")
        XCTAssertEqual(ClawixMacUtilityRoutes.defaultsCLI, "/usr/bin/defaults")
        XCTAssertEqual(ClawixMacUtilityRoutes.killallCLI, "/usr/bin/killall")
        XCTAssertEqual(ClawixSystemToolRoutes.pmsetCLI, "/usr/bin/pmset")
        XCTAssertEqual(ClawixSystemToolRoutes.defaultsCLI, "/usr/bin/defaults")
        XCTAssertEqual(ClawixSystemToolRoutes.killallCLI, "/usr/bin/killall")
        XCTAssertEqual(ClawixMacUtilityRoutes.finderApp, ClawixKnownAppRoutes.finder.fallbackPath)
        XCTAssertEqual(ClawixMacUtilityRoutes.terminalApp, ClawixKnownAppRoutes.terminal.fallbackPath)
        XCTAssertEqual(ClawixMacUtilityRoutes.shortcutsApp, ClawixKnownAppRoutes.shortcuts.fallbackPath)
        XCTAssertEqual(ClawixMacUtilityRoutes.passwordsApp, ClawixKnownAppRoutes.passwords.fallbackPath)
        XCTAssertEqual(ClawixMacUtilityRoutes.shortcutsApp, "/System/Applications/Shortcuts.app")
        XCTAssertEqual(ClawixMacUtilityRoutes.passwordsApp, "/System/Applications/Passwords.app")
        XCTAssertTrue(routesSource.contains("static let pmsetCLI = ClawixSystemToolRoutes.pmsetCLI"))
        XCTAssertTrue(routesSource.contains("static let defaultsCLI = ClawixSystemToolRoutes.defaultsCLI"))
        XCTAssertTrue(routesSource.contains("static let killallCLI = ClawixSystemToolRoutes.killallCLI"))
        XCTAssertTrue(routesSource.contains("static let shortcutsApp = ClawixKnownAppRoutes.shortcuts.fallbackPath"))
        XCTAssertTrue(routesSource.contains("static let passwordsApp = ClawixKnownAppRoutes.passwords.fallbackPath"))
        XCTAssertFalse(routesSource.contains("static let pmsetCLI = \"/usr/bin/pmset\""))
        XCTAssertFalse(routesSource.contains("static let defaultsCLI = \"/usr/bin/defaults\""))
        XCTAssertFalse(routesSource.contains("static let killallCLI = \"/usr/bin/killall\""))
        XCTAssertFalse(routesSource.contains("static let shortcutsApp = \"/System/Applications/Shortcuts.app\""))
        XCTAssertFalse(routesSource.contains("static let passwordsApp = \"/System/Applications/Passwords.app\""))
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
