import XCTest
@testable import Clawix

final class ClawixHostBootstrapRoutesTests: XCTestCase {
    func testClawHostBootstrapRegistryRoutesAreCentralized() throws {
        let bootstrapSource = try readSource("ClawHost/ClawixHostBootstrap.swift")
        let routesSource = try readSource("ClawHost/ClawixHostBootstrapRoutes.swift")
        let home = URL(fileURLWithPath: "/Users/demo", isDirectory: true)

        XCTAssertEqual(ClawixHostBootstrapRoutes.libraryDirectoryName, "Library")
        XCTAssertEqual(ClawixHostBootstrapRoutes.applicationSupportDirectoryName, "Application Support")
        XCTAssertEqual(ClawixHostBootstrapRoutes.clawDirectoryName, "Claw")
        XCTAssertEqual(ClawixHostBootstrapRoutes.hostsDirectoryName, "hosts")
        XCTAssertEqual(ClawixHostBootstrapRoutes.registryFileName, "registry.json")
        XCTAssertFalse(ClawixHostBootstrapRoutes.userHomeDirectory().path.isEmpty)
        XCTAssertEqual(
            ClawixHostBootstrapRoutes.applicationSupportDirectory(homeDirectory: home).path,
            "/Users/demo/Library/Application Support"
        )
        XCTAssertEqual(
            ClawixHostBootstrapRoutes.hostsDirectory(homeDirectory: home).path,
            "/Users/demo/Library/Application Support/Claw/hosts"
        )
        XCTAssertEqual(
            ClawixHostBootstrapRoutes.registryFileURL(homeDirectory: home).path,
            "/Users/demo/Library/Application Support/Claw/hosts/registry.json"
        )

        XCTAssertTrue(bootstrapSource.contains("ClawixHostBootstrapRoutes.registryFileURL()"))
        XCTAssertTrue(routesSource.contains("static func userHomeDirectory() -> URL"))
        XCTAssertTrue(routesSource.contains("ClawixUserHomeRoutes.directory()"))
        XCTAssertTrue(routesSource.contains("explicitHomeDirectory ?? userHomeDirectory()"))
        XCTAssertFalse(routesSource.contains("FileManager.default.homeDirectoryForCurrentUser"))
        XCTAssertFalse(routesSource.contains("homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser"))
        XCTAssertFalse(bootstrapSource.contains(".appendingPathComponent(\"Application Support\""))
        XCTAssertFalse(bootstrapSource.contains(".appendingPathComponent(\"Claw\""))
        XCTAssertFalse(bootstrapSource.contains(".appendingPathComponent(\"hosts\""))
        XCTAssertFalse(bootstrapSource.contains(".appendingPathComponent(\"registry.json\""))
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
