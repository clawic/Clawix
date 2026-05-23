import Foundation

enum ClawJSServiceDirectoryResolver {
    static var workspaceURL: URL {
        ClawJSServiceSupervisorRoutes.workspaceURL(applicationSupportRoot: applicationSupportRoot)
    }

    static var applicationSupportRoot: URL {
        ClawJSServiceSupervisorRoutes.applicationSupportRoot()
    }

    static func workingDirectoryURL(for service: ClawJSService) -> URL {
        if service == .runtime {
            return ClawJSRuntime.bundleRootURL
        }
        return workspaceURL
    }

    static var mainDataDirectoryURL: URL {
        applicationSupportRoot
    }

    static var mainDatabaseURL: URL {
        ClawJSServiceSupervisorRoutes.mainDatabaseURL(mainDataDirectoryURL: mainDataDirectoryURL)
    }

    static var mainFilesDirectoryURL: URL {
        ClawJSServiceSupervisorRoutes.mainFilesDirectoryURL(mainDataDirectoryURL: mainDataDirectoryURL)
    }

    static var frameworkGlobalRootURL: URL {
        ClawJSServiceSupervisorRoutes.frameworkGlobalRoot()
    }

    static var frameworkSecretsDirectoryURL: URL {
        ClawJSServiceSupervisorRoutes.frameworkSecretsDirectory(frameworkGlobalRoot: frameworkGlobalRootURL)
    }

    static func logFileURL(for service: ClawJSService) -> URL {
        ClawJSServiceSupervisorRoutes.logFileURL(service: service)
    }

    static func statusFileURL(for service: ClawJSService) -> URL {
        ClawJSServiceSupervisorRoutes.statusFileURL(service: service, applicationSupportRoot: applicationSupportRoot)
    }

    static func dataDirectoryURL(for service: ClawJSService) -> URL {
        if service == .database {
            return mainDataDirectoryURL
        }
        if service == .secrets {
            return frameworkSecretsDirectoryURL
        }
        return ClawJSServiceSupervisorRoutes.serviceDataDirectoryURL(
            service: service,
            workspaceURL: workspaceURL,
            mainDataDirectoryURL: mainDataDirectoryURL,
            frameworkSecretsDirectoryURL: frameworkSecretsDirectoryURL
        )
    }

    static func staleAdminTokenURLs(for service: ClawJSService) -> [URL] {
        [
            dataDirectoryURL(for: service),
            ClawJSServiceSupervisorRoutes.serviceDataDirectoryURL(
                service: service,
                workspaceURL: workspaceURL,
                mainDataDirectoryURL: mainDataDirectoryURL,
                frameworkSecretsDirectoryURL: frameworkSecretsDirectoryURL
            ),
        ].map { ClawJSServiceSupervisorRoutes.adminTokenURL(dataDirectoryURL: $0) }
    }

    static func prepareDirectories(for service: ClawJSService, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: logFileURL(for: service).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: statusFileURL(for: service).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let dataURL = dataDirectoryURL(for: service)
        try fileManager.createDirectory(
            at: dataURL,
            withIntermediateDirectories: true
        )
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dataURL.path)
        if ClawJSServiceSupervisorPolicy.requiresSessionAdminToken(service) {
            for tokenURL in staleAdminTokenURLs(for: service) {
                try? fileManager.removeItem(at: tokenURL)
            }
        }
        try fileManager.createDirectory(
            at: mainFilesDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    static func adminTokenFromTokenFile(for service: ClawJSService) throws -> String {
        if ClawJSServiceSupervisorPolicy.requiresSessionAdminToken(service) {
            throw NSError(domain: "ClawJSServiceManager", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "\(service.displayName) admin token is host-session only and is never read from disk."
            ])
        }
        let url = ClawJSServiceSupervisorRoutes.adminTokenURL(dataDirectoryURL: dataDirectoryURL(for: service))
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        if let mode = attrs[.posixPermissions] as? NSNumber,
           mode.intValue & 0o077 != 0 {
            throw NSError(domain: "ClawJSServiceManager", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Admin token at \(url.path) must be readable only by the current user."
            ])
        }
        let raw = try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.count >= 32 else {
            throw NSError(domain: "ClawJSServiceManager", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Admin token at \(url.path) is too short."
            ])
        }
        return raw
    }
}
