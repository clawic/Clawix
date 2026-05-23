import XCTest
@testable import Clawix

final class ClawixAppResourceRoutesTests: XCTestCase {
    func testAppResourceRegistryRoutesAreCentralized() throws {
        let storeSource = try readSource("Apps/AppResourceRegistryStore.swift")
        let routesSource = try readSource("Apps/ClawixAppResourceRoutes.swift")
        let home = URL(fileURLWithPath: "/Users/demo", isDirectory: true)
        let configuredDirectory = ClawixAppResourceRoutes.defaultDirectory(
            environment: [ClawixAppResourceRoutes.resourcesDirectoryEnvName: "~/CustomResources"],
            homeDirectory: home
        )
        let frameworkHomeDirectory = ClawixAppResourceRoutes.defaultDirectory(
            environment: [ClawixAppResourceRoutes.frameworkHomeEnvName: "~/FrameworkHome"],
            homeDirectory: home
        )
        let defaultDirectory = ClawixAppResourceRoutes.defaultDirectory(
            environment: [:],
            homeDirectory: home
        )

        XCTAssertEqual(ClawixAppResourceRoutes.resourcesDirectoryEnvName, "CLAW_RESOURCES_DIR")
        XCTAssertEqual(ClawixAppResourceRoutes.frameworkHomeEnvName, "CLAW_HOME")
        XCTAssertEqual(ClawixAppResourceRoutes.frameworkHomeDirectoryName, ".claw")
        XCTAssertEqual(ClawixAppResourceRoutes.resourcesDirectoryName, "resources")
        XCTAssertEqual(ClawixAppResourceRoutes.stateFileName, "resources.json")
        XCTAssertFalse(ClawixAppResourceRoutes.userHomeDirectory().path.isEmpty)
        XCTAssertEqual(configuredDirectory.path, "/Users/demo/CustomResources")
        XCTAssertEqual(frameworkHomeDirectory.path, "/Users/demo/FrameworkHome/resources")
        XCTAssertEqual(defaultDirectory.path, "/Users/demo/.claw/resources")
        XCTAssertEqual(
            ClawixAppResourceRoutes.stateFileURL(directory: defaultDirectory).path,
            "/Users/demo/.claw/resources/resources.json"
        )
        XCTAssertEqual(
            ClawixAppResourceRoutes.expandHome("~/ReadableResource.txt", homeDirectory: home).path,
            "/Users/demo/ReadableResource.txt"
        )
        XCTAssertEqual(
            ClawixAppResourceRoutes.expandHome("~", homeDirectory: home).path,
            "/Users/demo"
        )

        XCTAssertTrue(storeSource.contains("ClawixAppResourceRoutes.defaultDirectory(environment: environment)"))
        XCTAssertTrue(storeSource.contains("ClawixAppResourceRoutes.expandHome(value)"))
        XCTAssertTrue(storeSource.contains("ClawixAppResourceRoutes.stateFileURL(directory: directory)"))
        XCTAssertTrue(routesSource.contains("static func userHomeDirectory() -> URL"))
        XCTAssertTrue(routesSource.contains("ClawixUserHomeRoutes.directory()"))
        XCTAssertTrue(routesSource.contains("homeDirectory ?? userHomeDirectory()"))
        XCTAssertTrue(routesSource.contains("ClawixPersistentSurfacePaths.expandedUserVisiblePath("))
        XCTAssertFalse(routesSource.contains("value.hasPrefix(\"~/\")"))
        XCTAssertFalse(routesSource.contains("value.dropFirst(2)"))
        XCTAssertFalse(routesSource.contains("FileManager.default.homeDirectoryForCurrentUser"))
        XCTAssertFalse(routesSource.contains("homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser"))
        XCTAssertFalse(routesSource.contains("expandHome(_ value: String, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser)"))
        XCTAssertFalse(storeSource.contains("\"CLAW_RESOURCES_DIR\""))
        XCTAssertFalse(storeSource.contains("\"CLAW_HOME\""))
        XCTAssertFalse(storeSource.contains("FileManager.default.homeDirectoryForCurrentUser"))
        XCTAssertFalse(storeSource.contains("ClawixPersistentSurfacePaths.components.clawHome"))
        XCTAssertFalse(storeSource.contains("ClawixPersistentSurfacePaths.components.resources"))
        XCTAssertFalse(storeSource.contains("appendingPathComponent(\"resources\""))
        XCTAssertFalse(storeSource.contains("appendingPathComponent(Self.stateFileName"))
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
