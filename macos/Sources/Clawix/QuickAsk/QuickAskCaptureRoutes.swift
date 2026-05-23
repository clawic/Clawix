import Foundation

enum QuickAskCaptureRoutes {
    static let capturesDirectoryName = ClawixPersistentSurfacePaths.components.captures
    static let defaultCaptureExtension = "png"
    static let placeholderAttachmentPath = ClawixTemporaryRoutes.nullDevicePath

    static func cachesRoot(fileManager: FileManager = .default) -> URL? {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
    }

    static func capturesDirectoryURL(cachesRoot: URL) -> URL {
        cachesRoot.appendingPathComponent(capturesDirectoryName, isDirectory: true)
    }

    static func ensureCapturesDirectory(fileManager: FileManager = .default) -> URL? {
        guard let root = cachesRoot(fileManager: fileManager) else { return nil }
        let dir = capturesDirectoryURL(cachesRoot: root)
        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        } catch {
            return nil
        }
    }

    static func captureFileURL(
        prefix: String,
        fileExtension: String = defaultCaptureExtension,
        timestamp: TimeInterval = Date().timeIntervalSince1970,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let dir = ensureCapturesDirectory(fileManager: fileManager) else { return nil }
        let stamp = Int(timestamp * 1000)
        return dir.appendingPathComponent("\(prefix)-\(stamp).\(fileExtension)")
    }

    static func captureFileURLWithTemporaryFallback(
        prefix: String,
        fileExtension: String = defaultCaptureExtension,
        timestamp: TimeInterval = Date().timeIntervalSince1970,
        fileManager: FileManager = .default
    ) -> URL {
        if let url = captureFileURL(
            prefix: prefix,
            fileExtension: fileExtension,
            timestamp: timestamp,
            fileManager: fileManager
        ) {
            return url
        }
        let stamp = Int(timestamp * 1000)
        return ClawixTemporaryRoutes.systemTemporaryDirectory(fileManager: fileManager)
            .appendingPathComponent("\(prefix)-\(stamp).\(fileExtension)")
    }

    static func placeholderAttachmentURL() -> URL {
        ClawixTemporaryRoutes.nullDeviceURL
    }
}
