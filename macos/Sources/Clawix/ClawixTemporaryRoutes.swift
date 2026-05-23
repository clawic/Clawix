import Foundation

enum ClawixTemporaryRoutes {
    static let unixTemporaryDirectoryPath = "/tmp"
    static let nullDevicePath = "/dev/null"

    static var unixTemporaryDirectoryURL: URL {
        URL(fileURLWithPath: unixTemporaryDirectoryPath, isDirectory: true)
    }

    static var nullDeviceURL: URL {
        URL(fileURLWithPath: nullDevicePath, isDirectory: false)
    }

    static func systemTemporaryDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.temporaryDirectory
    }

    static func unixTemporaryFileURL(fileName: String) -> URL {
        unixTemporaryDirectoryURL.appendingPathComponent(fileName, isDirectory: false)
    }
}
