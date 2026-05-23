import Foundation

enum ClawixAgentBackendRoutes {
    static let codexAppResourcesDir = ClawixKnownAppRoutes.applicationResourcesDirectory(appName: "Codex")
    static let homebrewBinDir = ClawixSystemToolRoutes.optHomebrewBinDirectory
    static let usrLocalBinDir = ClawixSystemToolRoutes.usrLocalBinDirectory
    static let usrBinDir = ClawixSystemToolRoutes.usrBinDirectory
    static let binDir = ClawixSystemToolRoutes.binDirectory
    static let usrSbinDir = ClawixSystemToolRoutes.usrSbinDirectory
    static let sbinDir = ClawixSystemToolRoutes.sbinDirectory
    static let generatedTitlePrefix = "clawix-title"
    static let textExtension = "txt"
    static let codexDirectoryName = ".codex"
    static let codexSessionsDirectoryName = "sessions"
    static let codexGeneratedImagesDirectoryName = "generated_images"
    static let codexAuthFileName = "auth.json"
    static let pngExtension = "png"

    static let envCLI = ClawixSystemToolRoutes.envCLI
    static let nvmNodeVersionsRelativePath = ".nvm/versions/node"

    static let loginSystemPathComponents = [
        usrBinDir,
        binDir,
        usrSbinDir,
        sbinDir,
    ]

    static func codexAppBackendURL(executableName: String) -> URL {
        URL(fileURLWithPath: codexAppResourcesDir).appendingPathComponent(executableName)
    }

    static func userHomeDirectory() -> URL {
        ClawixUserHomeRoutes.directory()
    }

    static func defaultThreadCwd(homeDirectory explicitHomeDirectory: URL? = nil) -> String {
        let homeDirectory = explicitHomeDirectory ?? userHomeDirectory()
        return homeDirectory.path
    }

    static func nvmNodeVersionsRoot(homeDirectory explicitHomeDirectory: URL? = nil) -> URL {
        let homeDirectory = explicitHomeDirectory ?? userHomeDirectory()
        return homeDirectory.appendingPathComponent(nvmNodeVersionsRelativePath, isDirectory: true)
    }

    static func codexDirectory(homeDirectory explicitHomeDirectory: URL? = nil) -> URL {
        let homeDirectory = explicitHomeDirectory ?? userHomeDirectory()
        return homeDirectory.appendingPathComponent(codexDirectoryName, isDirectory: true)
    }

    static func codexSessionsDirectory(codexDirectory: URL = codexDirectory()) -> URL {
        codexDirectory.appendingPathComponent(codexSessionsDirectoryName, isDirectory: true)
    }

    static func codexAuthFileURL(codexDirectory: URL = codexDirectory()) -> URL {
        codexDirectory.appendingPathComponent(codexAuthFileName, isDirectory: false)
    }

    static func codexGeneratedImagesDirectory(
        sessionId: String,
        codexDirectory: URL = codexDirectory()
    ) -> URL {
        codexDirectory
            .appendingPathComponent(codexGeneratedImagesDirectoryName, isDirectory: true)
            .appendingPathComponent(sessionId, isDirectory: true)
    }

    static func codexGeneratedImageURL(
        sessionId: String,
        callId: String,
        codexDirectory: URL = codexDirectory()
    ) -> URL {
        codexGeneratedImagesDirectory(sessionId: sessionId, codexDirectory: codexDirectory)
            .appendingPathComponent("\(callId).\(pngExtension)", isDirectory: false)
    }

    static func homebrewBackendURL(executableName: String) -> URL {
        URL(fileURLWithPath: homebrewBinDir).appendingPathComponent(executableName)
    }

    static func usrLocalBackendURL(executableName: String) -> URL {
        URL(fileURLWithPath: usrLocalBinDir).appendingPathComponent(executableName)
    }

    static func usrBinBackendURL(executableName: String) -> URL {
        URL(fileURLWithPath: usrBinDir).appendingPathComponent(executableName)
    }

    static func temporaryDirectory(fileManager: FileManager = .default) -> URL {
        ClawixTemporaryRoutes.systemTemporaryDirectory(fileManager: fileManager)
    }

    static func generatedTitleOutputURL(
        id: String = UUID().uuidString,
        temporaryDirectory: URL = temporaryDirectory()
    ) -> URL {
        temporaryDirectory.appendingPathComponent("\(generatedTitlePrefix)-\(id).\(textExtension)")
    }

    static func ensureLoginSystemPath(in path: String) -> String {
        guard !path.contains(usrBinDir) else { return path }
        return path + ":" + loginSystemPathComponents.joined(separator: ":")
    }
}
