import Foundation

enum ClawixHostBootstrapRoutes {
    static let libraryDirectoryName = "Library"
    static let applicationSupportDirectoryName = "Application Support"
    static let clawDirectoryName = "Claw"
    static let hostsDirectoryName = "hosts"
    static let registryFileName = "registry.json"

    static func userHomeDirectory() -> URL {
        ClawixUserHomeRoutes.directory()
    }

    static func applicationSupportDirectory(homeDirectory explicitHomeDirectory: URL? = nil) -> URL {
        let homeDirectory = explicitHomeDirectory ?? userHomeDirectory()
        return homeDirectory
            .appendingPathComponent(libraryDirectoryName, isDirectory: true)
            .appendingPathComponent(applicationSupportDirectoryName, isDirectory: true)
    }

    static func hostsDirectory(homeDirectory explicitHomeDirectory: URL? = nil) -> URL {
        let homeDirectory = explicitHomeDirectory ?? userHomeDirectory()
        return applicationSupportDirectory(homeDirectory: homeDirectory)
            .appendingPathComponent(clawDirectoryName, isDirectory: true)
            .appendingPathComponent(hostsDirectoryName, isDirectory: true)
    }

    static func registryFileURL(homeDirectory explicitHomeDirectory: URL? = nil) -> URL {
        let homeDirectory = explicitHomeDirectory ?? userHomeDirectory()
        return hostsDirectory(homeDirectory: homeDirectory)
            .appendingPathComponent(registryFileName, isDirectory: false)
    }
}
