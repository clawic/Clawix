import Foundation

enum ClawixBridgeAgentRoutes {
    static let tempDirectory = ClawixTemporaryRoutes.unixTemporaryDirectoryPath
    static let bridgeStderrFileName = "clawix-bridge.err"
    static let launchctlCLI = ClawixSystemToolRoutes.launchctlCLI
    static let userLaunchAgentsRelativePath = "Library/LaunchAgents"

    static var tempDirectoryURL: URL {
        ClawixTemporaryRoutes.unixTemporaryDirectoryURL
    }

    static var bridgeStderrURL: URL {
        ClawixTemporaryRoutes.unixTemporaryFileURL(fileName: bridgeStderrFileName)
    }

    static func userHomePath() -> String {
        ClawixUserHomeRoutes.path()
    }

    static func launchAgentPlistPath(label: String, homeDirectory: String? = nil) -> String {
        let homeDirectory = homeDirectory ?? userHomePath()
        return URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent(userLaunchAgentsRelativePath, isDirectory: true)
            .appendingPathComponent("\(label).plist", isDirectory: false)
            .path
    }
}
