import XCTest
@testable import Clawix

final class ClawixKnownAppRoutesTests: XCTestCase {
    func testKnownAppRoutesCentralizeEditorFallbackPaths() throws {
        let routesSource = try readSource("ClawixKnownAppRoutes.swift")

        XCTAssertEqual(ClawixKnownAppRoutes.applicationsDirectory, "/Applications")
        XCTAssertEqual(ClawixKnownAppRoutes.systemApplicationsDirectory, "/System/Applications")
        XCTAssertEqual(ClawixKnownAppRoutes.systemUtilitiesDirectory, "/System/Applications/Utilities")
        XCTAssertEqual(ClawixKnownAppRoutes.systemCoreServicesDirectory, "/System/Library/CoreServices")
        XCTAssertEqual(ClawixKnownAppRoutes.applicationsApp("Xcode"), "/Applications/Xcode.app")
        XCTAssertEqual(ClawixKnownAppRoutes.systemApplicationsApp("Shortcuts"), "/System/Applications/Shortcuts.app")
        XCTAssertEqual(ClawixKnownAppRoutes.systemUtilitiesApp("Terminal"), "/System/Applications/Utilities/Terminal.app")
        XCTAssertEqual(ClawixKnownAppRoutes.systemCoreServicesApp("Finder"), "/System/Library/CoreServices/Finder.app")
        XCTAssertEqual(
            ClawixKnownAppRoutes.appBundleResourcesDirectory(appPath: "/Applications/Codex.app"),
            "/Applications/Codex.app/Contents/Resources"
        )
        XCTAssertEqual(
            ClawixKnownAppRoutes.applicationResourcesDirectory(appName: "Codex"),
            "/Applications/Codex.app/Contents/Resources"
        )
        XCTAssertEqual(ClawixKnownAppRoutes.finder.bundleId, "com.apple.finder")
        XCTAssertEqual(ClawixKnownAppRoutes.finder.fallbackPath, "/System/Library/CoreServices/Finder.app")
        XCTAssertEqual(ClawixKnownAppRoutes.terminal.fallbackPath, "/System/Applications/Utilities/Terminal.app")
        XCTAssertEqual(ClawixKnownAppRoutes.vsCode.fallbackPath, "/Applications/Visual Studio Code.app")
        XCTAssertEqual(ClawixKnownAppRoutes.cursor.fallbackPath, "/Applications/Cursor.app")
        XCTAssertEqual(ClawixKnownAppRoutes.ghostty.fallbackPath, "/Applications/Ghostty.app")
        XCTAssertEqual(ClawixKnownAppRoutes.xcode.fallbackPath, "/Applications/Xcode.app")
        XCTAssertEqual(ClawixKnownAppRoutes.androidStudio.fallbackPath, "/Applications/Android Studio.app")
        XCTAssertEqual(ClawixKnownAppRoutes.shortcuts.fallbackPath, "/System/Applications/Shortcuts.app")
        XCTAssertEqual(ClawixKnownAppRoutes.passwords.fallbackPath, "/System/Applications/Passwords.app")
        XCTAssertTrue(routesSource.contains("fallbackPath: applicationsApp(\"Xcode\")"))
        XCTAssertTrue(routesSource.contains("fallbackPath: systemApplicationsApp(\"Shortcuts\")"))
        XCTAssertTrue(routesSource.contains("fallbackPath: systemApplicationsApp(\"Passwords\")"))
        XCTAssertTrue(routesSource.contains("fallbackPath: systemUtilitiesApp(\"Terminal\")"))
        XCTAssertTrue(routesSource.contains("fallbackPath: systemCoreServicesApp(\"Finder\")"))
        XCTAssertFalse(routesSource.contains("fallbackPath: \"/Applications/Xcode.app\""))
        XCTAssertFalse(routesSource.contains("fallbackPath: \"/System/Applications/Shortcuts.app\""))
        XCTAssertFalse(routesSource.contains("fallbackPath: \"/System/Applications/Passwords.app\""))
        XCTAssertFalse(routesSource.contains("fallbackPath: \"/System/Applications/Utilities/Terminal.app\""))
        XCTAssertFalse(routesSource.contains("fallbackPath: \"/System/Library/CoreServices/Finder.app\""))
    }

    func testKnownAppRouteCollectionsPreserveMenuOrder() {
        XCTAssertEqual(
            ClawixKnownAppRoutes.editorPickerOptions.map(\.name),
            ["VS Code", "Cursor", "Finder", "Terminal", "Ghostty", "Xcode", "Android Studio"]
        )
        XCTAssertEqual(
            ClawixKnownAppRoutes.changedFileEditorOptions.map(\.name),
            ["VS Code", "Cursor", "Terminal", "Ghostty", "Xcode", "Android Studio"]
        )
        XCTAssertEqual(ClawixKnownAppRoutes.route(named: "Finder")?.fallbackPath, ClawixKnownAppRoutes.finder.fallbackPath)
        XCTAssertNil(ClawixKnownAppRoutes.route(named: "Unknown"))
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
