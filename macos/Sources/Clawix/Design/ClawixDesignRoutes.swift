import Foundation

enum ClawixDesignRoutes {
    static let droppedImagePrefix = "clawix-drop"
    static let pngExtension = "png"

    static func temporaryDirectory(fileManager: FileManager = .default) -> URL {
        ClawixTemporaryRoutes.systemTemporaryDirectory(fileManager: fileManager)
    }

    static func droppedImageURL(
        id: String = UUID().uuidString,
        temporaryDirectory: URL = temporaryDirectory()
    ) -> URL {
        temporaryDirectory.appendingPathComponent("\(droppedImagePrefix)-\(id).\(pngExtension)")
    }
}
