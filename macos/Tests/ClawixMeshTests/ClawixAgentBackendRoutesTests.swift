import XCTest
@testable import Clawix

final class ClawixAgentBackendRoutesTests: XCTestCase {
    func testAgentBackendRoutesCentralizeExecutableLookupPaths() throws {
        let routesSource = try readSource("AgentBackend/ClawixAgentBackendRoutes.swift")
        let titleGeneratorSource = try readSource("AgentBackend/TitleGenerator.swift")
        let serviceSource = try readSource("AgentBackend/ClawixService.swift")
        let rolloutReaderSource = try readSource("AgentBackend/RolloutReader.swift")
        let rolloutLocatorSource = try readSource("AgentBackend/CodexRolloutLocator.swift")
        let backendAuthReaderSource = try readSource("AgentBackend/BackendAuthReader.swift")
        let backendAuthCoordinatorSource = try readSource("AgentBackend/BackendAuthCoordinator.swift")
        let chatHydrationSource = try readSource("AppState/ChatHydration.swift")
        let temporaryDirectory = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let home = URL(fileURLWithPath: "/Users/demo", isDirectory: true)
        let codexDirectory = ClawixAgentBackendRoutes.codexDirectory(homeDirectory: home)

        XCTAssertEqual(ClawixAgentBackendRoutes.codexAppResourcesDir, "/Applications/Codex.app/Contents/Resources")
        XCTAssertEqual(ClawixAgentBackendRoutes.homebrewBinDir, "/opt/homebrew/bin")
        XCTAssertEqual(ClawixAgentBackendRoutes.usrLocalBinDir, "/usr/local/bin")
        XCTAssertEqual(ClawixAgentBackendRoutes.usrBinDir, "/usr/bin")
        XCTAssertEqual(ClawixAgentBackendRoutes.binDir, "/bin")
        XCTAssertEqual(ClawixAgentBackendRoutes.usrSbinDir, "/usr/sbin")
        XCTAssertEqual(ClawixAgentBackendRoutes.sbinDir, "/sbin")
        XCTAssertEqual(ClawixAgentBackendRoutes.envCLI, "/usr/bin/env")
        XCTAssertEqual(ClawixSystemToolRoutes.envCLI, "/usr/bin/env")
        XCTAssertEqual(ClawixAgentBackendRoutes.nvmNodeVersionsRelativePath, ".nvm/versions/node")
        XCTAssertEqual(ClawixAgentBackendRoutes.generatedTitlePrefix, "clawix-title")
        XCTAssertEqual(ClawixAgentBackendRoutes.codexDirectoryName, ".codex")
        XCTAssertEqual(ClawixAgentBackendRoutes.codexSessionsDirectoryName, "sessions")
        XCTAssertEqual(ClawixAgentBackendRoutes.codexGeneratedImagesDirectoryName, "generated_images")
        XCTAssertEqual(ClawixAgentBackendRoutes.codexAuthFileName, "auth.json")
        XCTAssertEqual(ClawixAgentBackendRoutes.pngExtension, "png")
        XCTAssertFalse(ClawixAgentBackendRoutes.userHomeDirectory().path.isEmpty)

        XCTAssertEqual(
            ClawixAgentBackendRoutes.codexAppBackendURL(executableName: "codex").path,
            "/Applications/Codex.app/Contents/Resources/codex"
        )
        XCTAssertEqual(ClawixAgentBackendRoutes.defaultThreadCwd(homeDirectory: home), "/Users/demo")
        XCTAssertEqual(
            ClawixAgentBackendRoutes.nvmNodeVersionsRoot(homeDirectory: home).path,
            "/Users/demo/.nvm/versions/node"
        )
        XCTAssertEqual(codexDirectory.path, "/Users/demo/.codex")
        XCTAssertEqual(
            ClawixAgentBackendRoutes.codexSessionsDirectory(codexDirectory: codexDirectory).path,
            codexDirectory.appendingPathComponent(ClawixAgentBackendRoutes.codexSessionsDirectoryName).path
        )
        XCTAssertEqual(
            ClawixAgentBackendRoutes.codexAuthFileURL(codexDirectory: codexDirectory).path,
            "/Users/demo/.codex/auth.json"
        )
        XCTAssertEqual(
            ClawixAgentBackendRoutes.codexGeneratedImagesDirectory(
                sessionId: "session-fixture",
                codexDirectory: codexDirectory
            ).path,
            "/Users/demo/.codex/generated_images/session-fixture"
        )
        XCTAssertEqual(
            ClawixAgentBackendRoutes.codexGeneratedImageURL(
                sessionId: "session-fixture",
                callId: "call-fixture",
                codexDirectory: codexDirectory
            ).path,
            "/Users/demo/.codex/generated_images/session-fixture/call-fixture.png"
        )
        XCTAssertEqual(ClawixAgentBackendRoutes.homebrewBackendURL(executableName: "codex").path, "/opt/homebrew/bin/codex")
        XCTAssertEqual(ClawixAgentBackendRoutes.usrLocalBackendURL(executableName: "codex").path, "/usr/local/bin/codex")
        XCTAssertEqual(ClawixAgentBackendRoutes.usrBinBackendURL(executableName: "codex").path, "/usr/bin/codex")
        XCTAssertEqual(
            ClawixAgentBackendRoutes.generatedTitleOutputURL(
                id: "title-token",
                temporaryDirectory: temporaryDirectory
            ).path,
            "/tmp/clawix-title-title-token.txt"
        )

        XCTAssertTrue(titleGeneratorSource.contains("ClawixAgentBackendRoutes.generatedTitleOutputURL()"))
        XCTAssertTrue(routesSource.contains("static func userHomeDirectory() -> URL"))
        XCTAssertTrue(
            routesSource.contains(
                "static let codexAppResourcesDir = ClawixKnownAppRoutes.applicationResourcesDirectory(appName: \"Codex\")"
            )
        )
        XCTAssertTrue(routesSource.contains("static let envCLI = ClawixSystemToolRoutes.envCLI"))
        XCTAssertTrue(routesSource.contains("static let usrBinDir = ClawixSystemToolRoutes.usrBinDirectory"))
        XCTAssertTrue(routesSource.contains("ClawixUserHomeRoutes.directory()"))
        XCTAssertTrue(routesSource.contains("explicitHomeDirectory ?? userHomeDirectory()"))
        XCTAssertTrue(routesSource.contains("ClawixTemporaryRoutes.systemTemporaryDirectory(fileManager: fileManager)"))
        XCTAssertFalse(routesSource.contains("FileManager.default.homeDirectoryForCurrentUser"))
        XCTAssertFalse(routesSource.contains("homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser"))
        XCTAssertFalse(routesSource.contains("fileManager.temporaryDirectory"))
        XCTAssertFalse(routesSource.contains("static let codexAppResourcesDir = \"/Applications/Codex.app/Contents/Resources\""))
        XCTAssertFalse(routesSource.contains("static let envCLI = \"\\(usrBinDir)/env\""))
        XCTAssertTrue(serviceSource.contains("ClawixAgentBackendRoutes.codexGeneratedImageURL("))
        XCTAssertTrue(rolloutReaderSource.contains("ClawixAgentBackendRoutes.codexGeneratedImageURL("))
        XCTAssertTrue(rolloutLocatorSource.contains("ClawixAgentBackendRoutes.codexSessionsDirectory()"))
        XCTAssertTrue(backendAuthReaderSource.contains("ClawixAgentBackendRoutes.codexAuthFileURL()"))
        XCTAssertTrue(backendAuthCoordinatorSource.contains("proc.arguments = [\"logout\"]"))
        XCTAssertFalse(backendAuthCoordinatorSource.contains("removeItem(at: BackendAuthReader.authURL)"))
        XCTAssertFalse(backendAuthCoordinatorSource.contains("FileManager.default.removeItem"))
        XCTAssertTrue(serviceSource.contains("ClawixAgentBackendRoutes.defaultThreadCwd()"))
        XCTAssertTrue(chatHydrationSource.contains("ClawixAgentBackendRoutes.defaultThreadCwd()"))
        XCTAssertFalse(titleGeneratorSource.contains("FileManager.default.temporaryDirectory"))
        XCTAssertFalse(titleGeneratorSource.contains("clawix-title-\\(UUID().uuidString).txt"))
        for source in [serviceSource, rolloutReaderSource, rolloutLocatorSource, backendAuthReaderSource] {
            XCTAssertFalse(source.contains("appendingPathComponent(\".codex\""))
            XCTAssertFalse(source.contains("appendingPathComponent(\"generated_images\""))
            XCTAssertFalse(source.contains("appendingPathComponent(\"sessions\""))
            XCTAssertFalse(source.contains("appendingPathComponent(\".codex/auth.json\""))
            XCTAssertFalse(source.contains("backendDirectoryName"))
            XCTAssertFalse(source.contains("auth.json") && !source.contains("codexAuthFileURL"))
            XCTAssertFalse(source.contains("appendingPathComponent(\"\\(callId).png\""))
            XCTAssertFalse(source.contains("appendingPathComponent(\"\\(payload.item.id).png\""))
        }
        for source in [serviceSource, chatHydrationSource] {
            XCTAssertFalse(source.contains("FileManager.default.homeDirectoryForCurrentUser.path"))
        }
    }

    func testLoginSystemPathAddsMacSystemToolsOnce() {
        XCTAssertEqual(
            ClawixAgentBackendRoutes.ensureLoginSystemPath(in: "/custom/bin"),
            "/custom/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        )
        XCTAssertEqual(
            ClawixAgentBackendRoutes.ensureLoginSystemPath(in: "/custom/bin:/usr/bin"),
            "/custom/bin:/usr/bin"
        )
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
