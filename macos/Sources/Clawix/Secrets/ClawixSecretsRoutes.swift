import Foundation

enum ClawixSecretsRoutes {
    static let overrideDirectoryEnvName = "CLAWIX_SECRETS_DIR"
    static let appSupportDirectoryName = ClawixPersistentSurfacePaths.components.clawix
    static let secretsDirectoryName = ClawixPersistentSurfacePaths.components.secrets
    static let databaseFileName = ClawixPersistentSurfacePaths.components.secretsDatabase
    static let proxySocketFileName = "proxy.sock"
    static let shellBinDirectoryName = "bin"
    static let clawCLISymlinkFileName = "claw"

    static func applicationSupportRoot(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }

    static func directoryURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        applicationSupportRoot: URL = applicationSupportRoot()
    ) -> URL {
        if let override = environment[overrideDirectoryEnvName], !override.isEmpty {
            let expanded = (override as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
        return applicationSupportRoot
            .appendingPathComponent(appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent(secretsDirectoryName, isDirectory: true)
    }

    static func databaseFileURL(directory: URL) -> URL {
        directory.appendingPathComponent(databaseFileName)
    }

    static func proxySocketFileURL(directory: URL) -> URL {
        directory.appendingPathComponent(proxySocketFileName)
    }

    static func userHomeDirectory() -> URL {
        ClawixUserHomeRoutes.directory()
    }

    static func shellBinDirectory(userHomeDirectory explicitUserHomeDirectory: URL? = nil) -> URL {
        let userHomeDirectory = explicitUserHomeDirectory ?? Self.userHomeDirectory()
        return userHomeDirectory.appendingPathComponent(shellBinDirectoryName, isDirectory: true)
    }

    static func clawCLISymlinkURL(binDirectory: URL = shellBinDirectory()) -> URL {
        binDirectory.appendingPathComponent(clawCLISymlinkFileName, isDirectory: false)
    }
}
