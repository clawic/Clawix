import Foundation

enum ClawixHostActionRoutes {
    static func temporaryDirectory(fileManager: FileManager = .default) -> URL {
        ClawixTemporaryRoutes.systemTemporaryDirectory(fileManager: fileManager)
    }

    static func applicationSupportDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? temporaryDirectory(fileManager: fileManager)
    }

    static func clawixSupportDirectory(
        applicationSupportDirectory: URL = applicationSupportDirectory()
    ) -> URL {
        applicationSupportDirectory.appendingPathComponent(
            ClawixPersistentSurfacePaths.components.clawix,
            isDirectory: true
        )
    }

    static func hostActionAuditURL(
        applicationSupportDirectory: URL = applicationSupportDirectory()
    ) -> URL {
        clawixSupportDirectory(applicationSupportDirectory: applicationSupportDirectory)
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.hostActionAuditFile)
    }

    static func macControlTimelineURL(
        applicationSupportDirectory: URL = applicationSupportDirectory()
    ) -> URL {
        clawixSupportDirectory(applicationSupportDirectory: applicationSupportDirectory)
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.macControlTimelineFile)
    }

    static func macControlPendingApprovalsURL(
        applicationSupportDirectory: URL = applicationSupportDirectory()
    ) -> URL {
        clawixSupportDirectory(applicationSupportDirectory: applicationSupportDirectory)
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.macControlPendingApprovalsFile)
    }
}
