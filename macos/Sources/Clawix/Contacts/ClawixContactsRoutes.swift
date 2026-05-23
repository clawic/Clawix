import Foundation

enum ClawixContactsRoutes {
    static let placeholderDragPath = ClawixTemporaryRoutes.nullDevicePath
    static let vCardExtension = "vcf"

    static func temporaryDirectory(fileManager: FileManager = .default) -> URL {
        ClawixTemporaryRoutes.systemTemporaryDirectory(fileManager: fileManager)
    }

    static func vCardExportURL(
        fullName: String,
        temporaryDirectory: URL = temporaryDirectory()
    ) -> URL {
        temporaryDirectory.appendingPathComponent("\(fullName).\(vCardExtension)")
    }

    static func placeholderDragURL() -> URL {
        ClawixTemporaryRoutes.nullDeviceURL
    }
}
