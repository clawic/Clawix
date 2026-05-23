import Foundation

enum ClawixAudioRoutes {
    static let replayPrefix = "clawix-replay"
    static let attachmentsDirectoryName = "clawix-attachments"
    static let dictationDirectoryName = "dictation"
    static let appSupportDirectoryName = ClawixPersistentSurfacePaths.components.clawix
    static let dictationSoundsDirectoryName = ClawixPersistentSurfacePaths.components.dictationSounds

    static func temporaryDirectory(fileManager: FileManager = .default) -> URL {
        ClawixTemporaryRoutes.systemTemporaryDirectory(fileManager: fileManager)
    }

    static func applicationSupportRoot(fileManager: FileManager = .default) throws -> URL {
        try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
    }

    static func replayFileURL(
        audioId: String,
        fileExtension: String,
        temporaryDirectory: URL = temporaryDirectory()
    ) -> URL {
        temporaryDirectory.appendingPathComponent("\(replayPrefix)-\(audioId).\(fileExtension)")
    }

    static func dictationSpoolDirectoryURL(
        temporaryDirectory: URL = temporaryDirectory()
    ) -> URL {
        temporaryDirectory
            .appendingPathComponent(attachmentsDirectoryName, isDirectory: true)
            .appendingPathComponent(dictationDirectoryName, isDirectory: true)
    }

    static func dictationSpoolFileURL(
        requestId: String,
        fileExtension: String,
        temporaryDirectory: URL = temporaryDirectory()
    ) -> URL {
        dictationSpoolDirectoryURL(temporaryDirectory: temporaryDirectory)
            .appendingPathComponent("\(requestId).\(fileExtension)")
    }

    static func dictationSoundsDirectoryURL(applicationSupportRoot: URL) -> URL {
        applicationSupportRoot
            .appendingPathComponent(appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent(dictationSoundsDirectoryName, isDirectory: true)
    }
}
