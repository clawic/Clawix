import Foundation
import ClawixCore

enum ClawixAgentStoreRoutes {
    static let frameworkHomeEnvName = ClawEnv.home
    static let frameworkHomeDirectoryName = ClawixPersistentSurfacePaths.components.clawWorkspace
    static let agentsDirectoryName = "agents"
    static let personalitiesDirectoryName = "personalities"
    static let skillCollectionsDirectoryName = "skill-collections"
    static let connectionsDirectoryName = "connections"
    static let presetsDirectoryName = "presets"
    static let publicMemoryDirectoryName = "memory"
    static let auditLogFileName = "audit.log"

    static func userHomeDirectory() -> URL {
        ClawixUserHomeRoutes.directory()
    }

    static func frameworkHome(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        userHomeDirectory explicitUserHomeDirectory: URL? = nil
    ) -> URL {
        let userHomeDirectory = explicitUserHomeDirectory ?? Self.userHomeDirectory()
        if let override = environment[frameworkHomeEnvName], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return userHomeDirectory.appendingPathComponent(frameworkHomeDirectoryName, isDirectory: true)
    }

    static func frameworkHome(workspaceURL: URL) -> URL {
        workspaceURL.appendingPathComponent(frameworkHomeDirectoryName, isDirectory: true)
    }

    static func agentsDirectory(frameworkHome: URL) -> URL {
        frameworkHome.appendingPathComponent(agentsDirectoryName, isDirectory: true)
    }

    static func personalitiesDirectory(frameworkHome: URL) -> URL {
        frameworkHome.appendingPathComponent(personalitiesDirectoryName, isDirectory: true)
    }

    static func skillCollectionsDirectory(frameworkHome: URL) -> URL {
        frameworkHome.appendingPathComponent(skillCollectionsDirectoryName, isDirectory: true)
    }

    static func connectionsDirectory(frameworkHome: URL) -> URL {
        frameworkHome.appendingPathComponent(connectionsDirectoryName, isDirectory: true)
    }

    static func presetsDirectory(frameworkHome: URL) -> URL {
        frameworkHome.appendingPathComponent(presetsDirectoryName, isDirectory: true)
    }

    static func publicMemoryDirectory(frameworkHome: URL) -> URL {
        frameworkHome.appendingPathComponent(publicMemoryDirectoryName, isDirectory: true)
    }

    static func agentDirectory(agentId: String, agentsDirectory: URL) -> URL {
        agentsDirectory.appendingPathComponent(agentId, isDirectory: true)
    }

    static func personalityDirectory(personalityId: String, personalitiesDirectory: URL) -> URL {
        personalitiesDirectory.appendingPathComponent(personalityId, isDirectory: true)
    }

    static func collectionDirectory(collectionId: String, collectionsDirectory: URL) -> URL {
        collectionsDirectory.appendingPathComponent(collectionId, isDirectory: true)
    }

    static func connectionDirectory(connectionId: String, connectionsDirectory: URL) -> URL {
        connectionsDirectory.appendingPathComponent(connectionId, isDirectory: true)
    }

    static func auditLogFile(agentDirectory: URL) -> URL {
        agentDirectory.appendingPathComponent(auditLogFileName, isDirectory: false)
    }
}
