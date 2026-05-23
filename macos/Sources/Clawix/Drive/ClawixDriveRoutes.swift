import Foundation

enum ClawixDriveRoutes {
    static let uploadBytesSeparator = "-"

    static func temporaryDirectory(fileManager: FileManager = .default) -> URL {
        ClawixTemporaryRoutes.systemTemporaryDirectory(fileManager: fileManager)
    }

    static func uploadBytesTempURL(
        fileName: String,
        id: String = UUID().uuidString,
        temporaryDirectory: URL = temporaryDirectory()
    ) -> URL {
        temporaryDirectory.appendingPathComponent("\(id)\(uploadBytesSeparator)\(fileName)")
    }

    static func readTempURL(
        itemId: String,
        id: String = UUID().uuidString,
        temporaryDirectory: URL = temporaryDirectory()
    ) -> URL {
        temporaryDirectory.appendingPathComponent("\(itemId)\(uploadBytesSeparator)\(id)")
    }
}
