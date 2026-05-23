import Foundation

enum DictationExportRoutes {
    static let transcriptsPrefix = "clawix-transcripts"
    static let settingsPrefix = "clawix-dictation-settings"
    static let csvExtension = "csv"
    static let jsonExtension = "json"

    static func temporaryDirectory(fileManager: FileManager = .default) -> URL {
        ClawixTemporaryRoutes.systemTemporaryDirectory(fileManager: fileManager)
    }

    static func transcriptsExportURL(
        timestamp: TimeInterval = Date().timeIntervalSince1970,
        temporaryDirectory: URL = temporaryDirectory()
    ) -> URL {
        temporaryDirectory.appendingPathComponent("\(transcriptsPrefix)-\(timestamp).\(csvExtension)")
    }

    static func settingsExportURL(
        timestamp: TimeInterval = Date().timeIntervalSince1970,
        temporaryDirectory: URL = temporaryDirectory()
    ) -> URL {
        temporaryDirectory.appendingPathComponent("\(settingsPrefix)-\(timestamp).\(jsonExtension)")
    }
}
