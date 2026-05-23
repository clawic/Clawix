import Foundation

enum ClawixLocalModelsRuntimeRoutes {
    static let tarCLI = ClawixSystemToolRoutes.tarCLI
    static let appSupportDirectoryName = ClawixPersistentSurfacePaths.components.clawix
    static let localModelsDirectoryName = ClawixPersistentSurfacePaths.components.localModels
    static let logsDirectoryName = ClawixPersistentSurfacePaths.components.logs
    static let runtimeDirectoryName = "runtime"
    static let versionFileName = "version"
    static let binaryFileName = "ollama"
    static let logFileName = "local-models.log"
    static let modelsDirectoryName = "models"
    static let fakeHomeDirectoryName = "home"
    static let launchAgentPlistSuffix = ".local-models.plist"

    static var userVisibleLogPath: String {
        ClawixPersistentSurfacePaths.userVisibleLibraryChild(
            logsDirectoryName,
            appSupportDirectoryName,
            logFileName
        )
    }

    static var tarURL: URL {
        URL(fileURLWithPath: tarCLI)
    }

    static func applicationSupportDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static func applicationSupportRoot(
        applicationSupportDirectory: URL = applicationSupportDirectory()
    ) -> URL {
        applicationSupportDirectory
            .appendingPathComponent(appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent(localModelsDirectoryName, isDirectory: true)
    }

    static func runtimeRoot(applicationSupportRoot: URL) -> URL {
        applicationSupportRoot.appendingPathComponent(runtimeDirectoryName, isDirectory: true)
    }

    static func versionFileURL(runtimeRoot: URL) -> URL {
        runtimeRoot.appendingPathComponent(versionFileName, isDirectory: false)
    }

    static func binaryURL(runtimeRoot: URL) -> URL {
        runtimeRoot.appendingPathComponent(binaryFileName, isDirectory: false)
    }

    static var logFileURL: URL {
        logsDirectory()
            .appendingPathComponent(logFileName, isDirectory: false)
    }

    static func logsDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent(logsDirectoryName, isDirectory: true)
        .appendingPathComponent(appSupportDirectoryName, isDirectory: true)
    }

    static func modelsDirectory(applicationSupportRoot: URL) -> URL {
        applicationSupportRoot.appendingPathComponent(modelsDirectoryName, isDirectory: true)
    }

    static func fakeHomeDirectory(applicationSupportRoot: URL) -> URL {
        applicationSupportRoot.appendingPathComponent(fakeHomeDirectoryName, isDirectory: true)
    }

    static func launchAgentPlistName(parentBundleId: String) -> String {
        "\(parentBundleId)\(launchAgentPlistSuffix)"
    }
}
