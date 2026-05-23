import Foundation

enum ClawixAppResourceRoutes {
    static let resourcesDirectoryEnvName = "CLAW_RESOURCES_DIR"
    static let frameworkHomeEnvName = "CLAW_HOME"
    static let frameworkHomeDirectoryName = ClawixPersistentSurfacePaths.components.clawHome
    static let resourcesDirectoryName = ClawixPersistentSurfacePaths.components.resources
    static let stateFileName = ClawixPersistentSurfacePaths.components.resourcesStateFile

    static func userHomeDirectory() -> URL {
        ClawixUserHomeRoutes.directory()
    }

    static func defaultDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL? = nil
    ) -> URL {
        let homeDirectory = homeDirectory ?? userHomeDirectory()
        if let configured = environment[resourcesDirectoryEnvName]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty {
            return expandHome(configured, homeDirectory: homeDirectory)
        }
        if let frameworkHome = environment[frameworkHomeEnvName]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !frameworkHome.isEmpty {
            return expandHome(frameworkHome, homeDirectory: homeDirectory)
                .appendingPathComponent(resourcesDirectoryName, isDirectory: true)
        }
        return homeDirectory
            .appendingPathComponent(frameworkHomeDirectoryName, isDirectory: true)
            .appendingPathComponent(resourcesDirectoryName, isDirectory: true)
    }

    static func expandHome(_ value: String, homeDirectory: URL? = nil) -> URL {
        ClawixPersistentSurfacePaths.expandedUserVisiblePath(
            value,
            userHomeDirectory: homeDirectory ?? userHomeDirectory()
        )
    }

    static func stateFileURL(directory: URL) -> URL {
        directory.appendingPathComponent(stateFileName, isDirectory: false)
    }
}
