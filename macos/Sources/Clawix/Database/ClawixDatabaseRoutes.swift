import Foundation

enum ClawixDatabaseRoutes {
    static let multipartUploadPrefix = "clawix-database-upload"
    static let uploadSourcePrefix = "clawix-database-upload-source"
    static let restoreSuffix = "restore"
    static let temporaryExtension = "tmp"
    static let previewSuffix = "preview"

    static func temporaryDirectory(fileManager: FileManager = .default) -> URL {
        ClawixTemporaryRoutes.systemTemporaryDirectory(fileManager: fileManager)
    }

    static func multipartUploadBodyURL(
        id: String = UUID().uuidString,
        temporaryDirectory: URL = temporaryDirectory()
    ) -> URL {
        temporaryDirectory.appendingPathComponent("\(multipartUploadPrefix)-\(id)", isDirectory: false)
    }

    static func uploadSourceURL(
        id: String = UUID().uuidString,
        temporaryDirectory: URL = temporaryDirectory()
    ) -> URL {
        temporaryDirectory.appendingPathComponent("\(uploadSourcePrefix)-\(id)", isDirectory: false)
    }

    static func restoreReplacementURL(
        for targetURL: URL,
        id: String = UUID().uuidString
    ) -> URL {
        targetURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(targetURL.lastPathComponent).\(restoreSuffix)-\(id).\(temporaryExtension)")
    }

    static func downloadedFilePreviewURL(
        fileId: String,
        temporaryDirectory: URL = temporaryDirectory()
    ) -> URL {
        temporaryDirectory.appendingPathComponent("\(fileId)-\(previewSuffix)")
    }
}
