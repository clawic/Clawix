import Foundation
import ClawixCore

enum ClawJSServiceSupervisorRoutes {
    static let envCLI = ClawixSystemToolRoutes.envCLI
    static let workspaceDirectoryName = "workspace"
    static let homeDirectoryName = "home"
    static let secretsDirectoryName = "secrets"
    static let secretsProxyRelativePath = "bin/secrets-proxy"
    static let runtimeDatabaseFileName = "runtime.sqlite"
    static let adminTokenFileName = ".admin-token"
    static let devPointersDirectoryName = "dev-pointers"
    static let iotPointerFileName = "iot.dir"

    static var envURL: URL {
        ClawixSystemToolRoutes.envURL
    }

    static func applicationSupportRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        if environment[ClawixEnv.dummyMode] == "1",
           let root = environment[ClawixEnv.backendHome],
           !root.isEmpty {
            return URL(fileURLWithPath: root, isDirectory: true)
        }
        return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.clawix, isDirectory: true)
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.clawjs, isDirectory: true)
    }

    static func workspaceURL(applicationSupportRoot: URL) -> URL {
        applicationSupportRoot.appendingPathComponent(workspaceDirectoryName, isDirectory: true)
    }

    static func mainDatabaseURL(mainDataDirectoryURL: URL) -> URL {
        mainDataDirectoryURL.appendingPathComponent(ClawixPersistentSurfacePaths.components.sqlite, isDirectory: false)
    }

    static func mainFilesDirectoryURL(mainDataDirectoryURL: URL) -> URL {
        mainDataDirectoryURL.appendingPathComponent(ClawixPersistentSurfacePaths.components.files, isDirectory: true)
    }

    static func userHomeDirectory() -> URL {
        ClawixUserHomeRoutes.directory()
    }

    static func frameworkGlobalRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL? = nil
    ) -> URL {
        if let override = environment[ClawEnv.home], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        let homeDirectory = homeDirectory ?? userHomeDirectory()
        return homeDirectory.appendingPathComponent(ClawixPersistentSurfacePaths.components.clawWorkspace, isDirectory: true)
    }

    static func frameworkSecretsDirectory(frameworkGlobalRoot: URL) -> URL {
        frameworkGlobalRoot.appendingPathComponent(secretsDirectoryName, isDirectory: true)
    }

    static func logFileURL(
        service: ClawJSService,
        fileManager: FileManager = .default
    ) -> URL {
        let logs = fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.logs, isDirectory: true)
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.clawix, isDirectory: true)
        return logs.appendingPathComponent("clawjs-\(service.rawValue).log", isDirectory: false)
    }

    static func statusFileURL(service: ClawJSService, applicationSupportRoot: URL) -> URL {
        applicationSupportRoot
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.status, isDirectory: true)
            .appendingPathComponent("\(service.rawValue).json", isDirectory: false)
    }

    static func homeURL(applicationSupportRoot: URL) -> URL {
        applicationSupportRoot.appendingPathComponent(homeDirectoryName, isDirectory: true)
    }

    static func secretsProxyURL(homeDirectory: URL? = nil) -> URL {
        let homeDirectory = homeDirectory ?? userHomeDirectory()
        return homeDirectory.appendingPathComponent(secretsProxyRelativePath, isDirectory: false)
    }

    static func runtimeDatabaseURL(runtimeDataDirectoryURL: URL) -> URL {
        runtimeDataDirectoryURL.appendingPathComponent(runtimeDatabaseFileName, isDirectory: false)
    }

    static func sessionsDatabaseURL(dataDirectoryURL: URL) -> URL {
        dataDirectoryURL.appendingPathComponent(ClawixPersistentSurfacePaths.components.sessionsDatabase, isDirectory: false)
    }

    static func secretsDatabaseURL(dataDirectoryURL: URL) -> URL {
        dataDirectoryURL.appendingPathComponent(ClawixPersistentSurfacePaths.components.secretsDatabase, isDirectory: false)
    }

    static func serviceDataDirectoryURL(
        service: ClawJSService,
        workspaceURL: URL,
        mainDataDirectoryURL: URL,
        frameworkSecretsDirectoryURL: URL
    ) -> URL {
        if service == .database {
            return mainDataDirectoryURL
        }
        if service == .secrets {
            return frameworkSecretsDirectoryURL
        }
        return workspaceURL
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.clawWorkspace, isDirectory: true)
            .appendingPathComponent(service.rawValue, isDirectory: true)
    }

    static func adminTokenURL(dataDirectoryURL: URL) -> URL {
        dataDirectoryURL.appendingPathComponent(adminTokenFileName, isDirectory: false)
    }

    static func iotPointerURL(applicationSupportRoot: URL) -> URL {
        applicationSupportRoot
            .appendingPathComponent(devPointersDirectoryName, isDirectory: true)
            .appendingPathComponent(iotPointerFileName, isDirectory: false)
    }
}
