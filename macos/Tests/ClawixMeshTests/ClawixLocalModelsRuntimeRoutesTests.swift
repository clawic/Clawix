import XCTest
@testable import Clawix

final class ClawixLocalModelsRuntimeRoutesTests: XCTestCase {
    func testLocalModelsRuntimeExtractionToolPathIsCentralized() throws {
        let installerSource = try readSource("LocalModels/LocalModelsRuntimeInstaller.swift")
        let routesSource = try readSource("LocalModels/ClawixLocalModelsRuntimeRoutes.swift")
        let appSupportDirectory = URL(fileURLWithPath: "/Users/demo/Library/Application Support", isDirectory: true)
        let supportRoot = ClawixLocalModelsRuntimeRoutes.applicationSupportRoot(
            applicationSupportDirectory: appSupportDirectory
        )
        let runtimeRoot = ClawixLocalModelsRuntimeRoutes.runtimeRoot(applicationSupportRoot: supportRoot)

        XCTAssertEqual(ClawixLocalModelsRuntimeRoutes.tarCLI, "/usr/bin/tar")
        XCTAssertEqual(ClawixSystemToolRoutes.tarCLI, "/usr/bin/tar")
        XCTAssertEqual(ClawixLocalModelsRuntimeRoutes.appSupportDirectoryName, "Clawix")
        XCTAssertEqual(ClawixLocalModelsRuntimeRoutes.localModelsDirectoryName, "local-models")
        XCTAssertEqual(ClawixLocalModelsRuntimeRoutes.runtimeDirectoryName, "runtime")
        XCTAssertEqual(ClawixLocalModelsRuntimeRoutes.versionFileName, "version")
        XCTAssertEqual(ClawixLocalModelsRuntimeRoutes.binaryFileName, "ollama")
        XCTAssertEqual(ClawixLocalModelsRuntimeRoutes.tarURL.path, "/usr/bin/tar")
        XCTAssertEqual(ClawixLocalModelsRuntimeRoutes.logsDirectoryName, "Logs")
        XCTAssertEqual(supportRoot.path, "/Users/demo/Library/Application Support/Clawix/local-models")
        XCTAssertEqual(runtimeRoot.path, "/Users/demo/Library/Application Support/Clawix/local-models/runtime")
        XCTAssertEqual(
            ClawixLocalModelsRuntimeRoutes.versionFileURL(runtimeRoot: runtimeRoot).path,
            "/Users/demo/Library/Application Support/Clawix/local-models/runtime/version"
        )
        XCTAssertEqual(
            ClawixLocalModelsRuntimeRoutes.binaryURL(runtimeRoot: runtimeRoot).path,
            "/Users/demo/Library/Application Support/Clawix/local-models/runtime/ollama"
        )
        XCTAssertTrue(installerSource.contains("ClawixLocalModelsRuntimeRoutes.tarURL"))
        XCTAssertTrue(installerSource.contains("ClawixLocalModelsRuntimeRoutes.applicationSupportRoot()"))
        XCTAssertTrue(installerSource.contains("ClawixLocalModelsRuntimeRoutes.runtimeRoot(applicationSupportRoot: applicationSupportRoot)"))
        XCTAssertTrue(installerSource.contains("ClawixLocalModelsRuntimeRoutes.versionFileURL(runtimeRoot: runtimeRoot)"))
        XCTAssertTrue(installerSource.contains("ClawixLocalModelsRuntimeRoutes.binaryURL(runtimeRoot: runtimeRoot)"))
        XCTAssertTrue(routesSource.contains("static let tarCLI = ClawixSystemToolRoutes.tarCLI"))
        XCTAssertFalse(routesSource.contains("static let tarCLI = \"/usr/bin/tar\""))
        XCTAssertFalse(installerSource.contains("URL(fileURLWithPath: \"/usr/bin/tar\")"))
        XCTAssertFalse(installerSource.contains("for: .applicationSupportDirectory"))
        XCTAssertFalse(installerSource.contains("ClawixPersistentSurfacePaths.components.localModels"))
        XCTAssertFalse(installerSource.contains("appendingPathComponent(\"runtime\""))
        XCTAssertFalse(installerSource.contains("appendingPathComponent(\"version\""))
        XCTAssertFalse(installerSource.contains("appendingPathComponent(\"ollama\""))
    }

    func testLocalModelsRuntimeDaemonPathsAreCentralized() throws {
        let daemonSource = try readSource("LocalModels/LocalModelsDaemon.swift")
        let routesSource = try readSource("LocalModels/ClawixLocalModelsRuntimeRoutes.swift")
        let supportRoot = URL(fileURLWithPath: "/Users/demo/Library/Application Support/Clawix/local-models")
        let libraryRoot = URL(fileURLWithPath: "/Users/demo/Library", isDirectory: true)

        XCTAssertEqual(ClawixLocalModelsRuntimeRoutes.logFileName, "local-models.log")
        XCTAssertEqual(ClawixLocalModelsRuntimeRoutes.modelsDirectoryName, "models")
        XCTAssertEqual(ClawixLocalModelsRuntimeRoutes.fakeHomeDirectoryName, "home")
        XCTAssertEqual(ClawixLocalModelsRuntimeRoutes.userVisibleLogPath, "~/Library/Logs/Clawix/local-models.log")
        XCTAssertEqual(
            ClawixLocalModelsRuntimeRoutes.logsDirectory(
                fileManager: StubFileManager(libraryRoot: libraryRoot)
            ).path,
            "/Users/demo/Library/Logs/Clawix"
        )
        XCTAssertEqual(
            ClawixLocalModelsRuntimeRoutes.modelsDirectory(applicationSupportRoot: supportRoot).path,
            "/Users/demo/Library/Application Support/Clawix/local-models/models"
        )
        XCTAssertEqual(
            ClawixLocalModelsRuntimeRoutes.fakeHomeDirectory(applicationSupportRoot: supportRoot).path,
            "/Users/demo/Library/Application Support/Clawix/local-models/home"
        )
        XCTAssertTrue(daemonSource.contains("ClawixLocalModelsRuntimeRoutes.logFileURL"))
        XCTAssertTrue(daemonSource.contains("ClawixLocalModelsRuntimeRoutes.modelsDirectory("))
        XCTAssertTrue(daemonSource.contains("ClawixLocalModelsRuntimeRoutes.fakeHomeDirectory("))
        XCTAssertTrue(daemonSource.contains("ClawixLocalModelsRuntimeRoutes.userVisibleLogPath"))
        XCTAssertTrue(routesSource.contains("static var userVisibleLogPath: String"))
        XCTAssertTrue(routesSource.contains("ClawixPersistentSurfacePaths.userVisibleLibraryChild("))
        XCTAssertTrue(routesSource.contains("logsDirectoryName,"))
        XCTAssertTrue(routesSource.contains("appSupportDirectoryName,"))
        XCTAssertTrue(routesSource.contains("logFileName"))
        XCTAssertFalse(routesSource.contains("\"~/Library/\\(logsDirectoryName)/\\(appSupportDirectoryName)/\\(logFileName)\""))
        XCTAssertFalse(routesSource.contains("static let userVisibleLogPath = \"~/Library/Logs/Clawix/local-models.log\""))
        XCTAssertFalse(daemonSource.contains("appendingPathComponent(\"local-models.log\""))
        XCTAssertFalse(daemonSource.contains("appendingPathComponent(\"models\""))
        XCTAssertFalse(daemonSource.contains("appendingPathComponent(\"home\""))
        XCTAssertFalse(daemonSource.contains("\"~/Library/Logs/Clawix/local-models.log\""))
    }

    func testLocalModelsLaunchAgentPlistNameIsCentralized() throws {
        let launchAgentSource = try readSource("LocalModels/LocalModelsLaunchAgent.swift")

        XCTAssertEqual(ClawixLocalModelsRuntimeRoutes.launchAgentPlistSuffix, ".local-models.plist")
        XCTAssertEqual(
            ClawixLocalModelsRuntimeRoutes.launchAgentPlistName(parentBundleId: "com.example.Clawix"),
            "com.example.Clawix.local-models.plist"
        )
        XCTAssertTrue(launchAgentSource.contains("ClawixLocalModelsRuntimeRoutes.launchAgentPlistName"))
        XCTAssertFalse(launchAgentSource.contains("\\(parentBundleId).local-models.plist"))
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

private final class StubFileManager: FileManager {
    private let libraryRoot: URL

    init(libraryRoot: URL) {
        self.libraryRoot = libraryRoot
        super.init()
    }

    override func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL] {
        guard directory == .libraryDirectory else {
            return super.urls(for: directory, in: domainMask)
        }
        return [libraryRoot]
    }
}
