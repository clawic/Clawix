import XCTest
@testable import Clawix

final class ClawixAgentStoreRoutesTests: XCTestCase {
    func testAgentStoreFrameworkRoutesAreCentralized() throws {
        let routesSource = try readSource("Agents/ClawixAgentStoreRoutes.swift")
        let agentStoreSource = try readSource("Agents/AgentStore.swift")
        let userHome = URL(fileURLWithPath: "/Users/demo", isDirectory: true)
        let defaultHome = ClawixAgentStoreRoutes.frameworkHome(environment: [:], userHomeDirectory: userHome)
        let overrideHome = ClawixAgentStoreRoutes.frameworkHome(
            environment: [ClawixAgentStoreRoutes.frameworkHomeEnvName: "~/ClawOverride"],
            userHomeDirectory: userHome
        )
        let serviceWorkspace = URL(
            fileURLWithPath: "/Users/demo/Library/Application Support/Clawix/clawjs/workspace",
            isDirectory: true
        )
        let serviceFrameworkHome = ClawixAgentStoreRoutes.frameworkHome(workspaceURL: serviceWorkspace)
        let agentsDirectory = ClawixAgentStoreRoutes.agentsDirectory(frameworkHome: defaultHome)
        let personalitiesDirectory = ClawixAgentStoreRoutes.personalitiesDirectory(frameworkHome: defaultHome)
        let collectionsDirectory = ClawixAgentStoreRoutes.skillCollectionsDirectory(frameworkHome: defaultHome)
        let connectionsDirectory = ClawixAgentStoreRoutes.connectionsDirectory(frameworkHome: defaultHome)

        XCTAssertEqual(ClawixAgentStoreRoutes.frameworkHomeEnvName, "CLAW_HOME")
        XCTAssertEqual(ClawixAgentStoreRoutes.frameworkHomeDirectoryName, ".claw")
        XCTAssertEqual(ClawixAgentStoreRoutes.agentsDirectoryName, "agents")
        XCTAssertEqual(ClawixAgentStoreRoutes.personalitiesDirectoryName, "personalities")
        XCTAssertEqual(ClawixAgentStoreRoutes.skillCollectionsDirectoryName, "skill-collections")
        XCTAssertEqual(ClawixAgentStoreRoutes.connectionsDirectoryName, "connections")
        XCTAssertEqual(ClawixAgentStoreRoutes.presetsDirectoryName, "presets")
        XCTAssertEqual(ClawixAgentStoreRoutes.publicMemoryDirectoryName, "memory")
        XCTAssertEqual(ClawixAgentStoreRoutes.auditLogFileName, "audit.log")
        XCTAssertFalse(ClawixAgentStoreRoutes.userHomeDirectory().path.isEmpty)
        XCTAssertEqual(defaultHome.path, "/Users/demo/.claw")
        XCTAssertTrue(overrideHome.path.hasSuffix("/ClawOverride"))
        XCTAssertEqual(
            serviceFrameworkHome.path,
            "/Users/demo/Library/Application Support/Clawix/clawjs/workspace/.claw"
        )
        XCTAssertEqual(agentsDirectory.path, "/Users/demo/.claw/agents")
        XCTAssertEqual(personalitiesDirectory.path, "/Users/demo/.claw/personalities")
        XCTAssertEqual(collectionsDirectory.path, "/Users/demo/.claw/skill-collections")
        XCTAssertEqual(connectionsDirectory.path, "/Users/demo/.claw/connections")
        XCTAssertEqual(
            ClawixAgentStoreRoutes.presetsDirectory(frameworkHome: defaultHome).path,
            "/Users/demo/.claw/presets"
        )
        XCTAssertEqual(
            ClawixAgentStoreRoutes.publicMemoryDirectory(frameworkHome: defaultHome).path,
            "/Users/demo/.claw/memory"
        )
        XCTAssertEqual(
            ClawixAgentStoreRoutes.agentDirectory(agentId: "agent-1", agentsDirectory: agentsDirectory).path,
            "/Users/demo/.claw/agents/agent-1"
        )
        XCTAssertEqual(
            ClawixAgentStoreRoutes.personalityDirectory(
                personalityId: "personality-1",
                personalitiesDirectory: personalitiesDirectory
            ).path,
            "/Users/demo/.claw/personalities/personality-1"
        )
        XCTAssertEqual(
            ClawixAgentStoreRoutes.collectionDirectory(
                collectionId: "collection-1",
                collectionsDirectory: collectionsDirectory
            ).path,
            "/Users/demo/.claw/skill-collections/collection-1"
        )
        XCTAssertEqual(
            ClawixAgentStoreRoutes.connectionDirectory(
                connectionId: "connection-1",
                connectionsDirectory: connectionsDirectory
            ).path,
            "/Users/demo/.claw/connections/connection-1"
        )
        XCTAssertEqual(
            ClawixAgentStoreRoutes.auditLogFile(agentDirectory: agentsDirectory).path,
            "/Users/demo/.claw/agents/audit.log"
        )

        XCTAssertTrue(agentStoreSource.contains("ClawixAgentStoreRoutes.frameworkHome()"))
        XCTAssertTrue(routesSource.contains("static func userHomeDirectory() -> URL"))
        XCTAssertTrue(routesSource.contains("ClawixUserHomeRoutes.directory()"))
        XCTAssertTrue(routesSource.contains("explicitUserHomeDirectory ?? Self.userHomeDirectory()"))
        XCTAssertFalse(routesSource.contains("FileManager.default.homeDirectoryForCurrentUser"))
        XCTAssertFalse(routesSource.contains("userHomeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser"))
        XCTAssertTrue(agentStoreSource.contains("ClawixAgentStoreRoutes.agentsDirectory(frameworkHome: home)"))
        XCTAssertTrue(agentStoreSource.contains("ClawixAgentStoreRoutes.personalitiesDirectory(frameworkHome: home)"))
        XCTAssertTrue(agentStoreSource.contains("ClawixAgentStoreRoutes.skillCollectionsDirectory(frameworkHome: home)"))
        XCTAssertTrue(agentStoreSource.contains("ClawixAgentStoreRoutes.connectionsDirectory(frameworkHome: home)"))
        XCTAssertTrue(agentStoreSource.contains("ClawixAgentStoreRoutes.presetsDirectory(frameworkHome: home)"))
        XCTAssertTrue(agentStoreSource.contains("ClawixAgentStoreRoutes.publicMemoryDirectory(frameworkHome: home)"))
        XCTAssertTrue(agentStoreSource.contains("ClawixAgentStoreRoutes.auditLogFile(agentDirectory: folder)"))
        XCTAssertFalse(agentStoreSource.contains("ProcessInfo.processInfo.environment[ClawEnv.home]"))
        XCTAssertFalse(agentStoreSource.contains("FileManager.default.homeDirectoryForCurrentUser"))
        XCTAssertFalse(agentStoreSource.contains("ClawixPersistentSurfacePaths.components.clawWorkspace"))
        XCTAssertFalse(agentStoreSource.contains("appendingPathComponent(\"agents\""))
        XCTAssertFalse(agentStoreSource.contains("appendingPathComponent(\"personalities\""))
        XCTAssertFalse(agentStoreSource.contains("appendingPathComponent(\"skill-collections\""))
        XCTAssertFalse(agentStoreSource.contains("appendingPathComponent(\"connections\""))
        XCTAssertFalse(agentStoreSource.contains("appendingPathComponent(\"presets\""))
        XCTAssertFalse(agentStoreSource.contains("appendingPathComponent(\"memory\""))
        XCTAssertFalse(agentStoreSource.contains("appendingPathComponent(\"audit.log\""))
    }

    func testMemorySettingsUsesCentralFrameworkMemoryRoute() throws {
        let memorySettingsSource = try readSource("Memory/MemorySettingsView.swift")
        let serviceWorkspace = URL(
            fileURLWithPath: "/Users/demo/Library/Application Support/Clawix/clawjs/workspace",
            isDirectory: true
        )
        let frameworkHome = ClawixAgentStoreRoutes.frameworkHome(workspaceURL: serviceWorkspace)

        XCTAssertEqual(
            ClawixAgentStoreRoutes.publicMemoryDirectory(frameworkHome: frameworkHome).path,
            "/Users/demo/Library/Application Support/Clawix/clawjs/workspace/.claw/memory"
        )
        XCTAssertTrue(
            memorySettingsSource.contains("ClawixAgentStoreRoutes.frameworkHome(workspaceURL: ClawJSServiceManager.workspaceURL)")
        )
        XCTAssertTrue(
            memorySettingsSource.contains("ClawixAgentStoreRoutes.publicMemoryDirectory(frameworkHome: frameworkHome)")
        )
        XCTAssertFalse(memorySettingsSource.contains("ClawixPersistentSurfacePaths.components.clawWorkspace"))
        XCTAssertFalse(memorySettingsSource.contains("appendingPathComponent(\"memory\""))
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
