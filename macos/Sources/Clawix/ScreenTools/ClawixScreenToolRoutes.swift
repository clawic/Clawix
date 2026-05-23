import Foundation

enum ClawixScreenToolRoutes {
    static let scrollingCapturePrefix = "clawix-scrolling"
    static let scrollingCaptureExtension = "png"
    static let processedRecordingSuffix = "processed"
    static let recordingExtension = "mov"

    static func temporaryDirectory(fileManager: FileManager = .default) -> URL {
        ClawixTemporaryRoutes.systemTemporaryDirectory(fileManager: fileManager)
    }

    static func scrollingCaptureFrameURL(
        index: Int,
        id: String = UUID().uuidString,
        temporaryDirectory: URL = temporaryDirectory()
    ) -> URL {
        temporaryDirectory.appendingPathComponent(
            "\(scrollingCapturePrefix)-\(id)-\(index).\(scrollingCaptureExtension)"
        )
    }

    static func processedRecordingURL(
        for url: URL,
        id: String = UUID().uuidString
    ) -> URL {
        url.deletingLastPathComponent()
            .appendingPathComponent(
                ".\(url.deletingPathExtension().lastPathComponent)-\(processedRecordingSuffix)-\(id).\(recordingExtension)"
            )
    }
}
