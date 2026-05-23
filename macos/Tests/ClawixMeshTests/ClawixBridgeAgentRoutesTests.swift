import XCTest
@testable import Clawix

final class ClawixBridgeAgentRoutesTests: XCTestCase {
    func testBridgeAgentRoutesCentralizeLogsLaunchctlAndLaunchAgentPlists() throws {
        let routesSource = try readSource("Bridge/ClawixBridgeAgentRoutes.swift")
        let bridgeControlSource = try readSource("Bridge/BridgeAgentControl.swift")

        XCTAssertEqual(ClawixTemporaryRoutes.unixTemporaryDirectoryPath, "/tmp")
        XCTAssertEqual(ClawixTemporaryRoutes.unixTemporaryFileURL(fileName: "clawix-bridge.err").path, "/tmp/clawix-bridge.err")
        XCTAssertEqual(ClawixBridgeAgentRoutes.tempDirectory, "/tmp")
        XCTAssertEqual(ClawixBridgeAgentRoutes.bridgeStderrFileName, "clawix-bridge.err")
        XCTAssertEqual(ClawixBridgeAgentRoutes.tempDirectoryURL.path, "/tmp")
        XCTAssertEqual(ClawixBridgeAgentRoutes.bridgeStderrURL.path, "/tmp/clawix-bridge.err")
        XCTAssertEqual(ClawixBridgeAgentRoutes.launchctlCLI, "/bin/launchctl")
        XCTAssertEqual(ClawixSystemToolRoutes.launchctlCLI, "/bin/launchctl")
        XCTAssertFalse(ClawixBridgeAgentRoutes.userHomePath().isEmpty)
        XCTAssertFalse(ClawixUserHomeRoutes.path().isEmpty)
        XCTAssertEqual(
            ClawixBridgeAgentRoutes.launchAgentPlistPath(label: "clawix.bridge", homeDirectory: "/Users/demo"),
            "/Users/demo/Library/LaunchAgents/clawix.bridge.plist"
        )
        XCTAssertEqual(
            ClawixBridgeAgentRoutes.launchAgentPlistPath(label: "clawix.menubar", homeDirectory: "/Users/demo"),
            "/Users/demo/Library/LaunchAgents/clawix.menubar.plist"
        )
        XCTAssertTrue(routesSource.contains("static func userHomePath() -> String"))
        XCTAssertTrue(routesSource.contains("ClawixUserHomeRoutes.path()"))
        XCTAssertTrue(routesSource.contains("ClawixTemporaryRoutes.unixTemporaryDirectoryPath"))
        XCTAssertTrue(routesSource.contains("static let launchctlCLI = ClawixSystemToolRoutes.launchctlCLI"))
        XCTAssertTrue(routesSource.contains("ClawixTemporaryRoutes.unixTemporaryDirectoryURL"))
        XCTAssertTrue(routesSource.contains("ClawixTemporaryRoutes.unixTemporaryFileURL(fileName: bridgeStderrFileName)"))
        XCTAssertTrue(routesSource.contains("homeDirectory ?? userHomePath()"))
        XCTAssertFalse(routesSource.contains("static let tempDirectory = \"/tmp\""))
        XCTAssertFalse(routesSource.contains("static let launchctlCLI = \"/bin/launchctl\""))
        XCTAssertFalse(routesSource.contains("static let bridgeStderrPath = \"/tmp/clawix-bridge.err\""))
        XCTAssertFalse(routesSource.contains("URL(fileURLWithPath: tempDirectory"))
        XCTAssertFalse(routesSource.contains("URL(fileURLWithPath: bridgeStderr"))
        XCTAssertFalse(routesSource.contains("NSHomeDirectory()"))
        XCTAssertFalse(routesSource.contains("homeDirectory: String = NSHomeDirectory()"))
        XCTAssertTrue(bridgeControlSource.contains("ClawixBridgeAgentRoutes.launchAgentPlistPath(label: menubarLabel)"))
        XCTAssertTrue(bridgeControlSource.contains("ClawixBridgeAgentRoutes.launchAgentPlistPath(label: bridgeLabel)"))
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
