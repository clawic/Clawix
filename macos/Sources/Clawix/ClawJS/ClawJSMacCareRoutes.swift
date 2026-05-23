import Foundation

enum ClawJSMacCareRoutes {
    static let finalizerDirectoryName = "clawix-mac-care-finalizer"
    static let jsonExtension = "json"

    static func temporaryDirectory(fileManager: FileManager = .default) -> URL {
        ClawixTemporaryRoutes.systemTemporaryDirectory(fileManager: fileManager)
    }

    static func finalizerActionPlanDirectory(
        temporaryDirectory: URL = temporaryDirectory()
    ) -> URL {
        temporaryDirectory.appendingPathComponent(finalizerDirectoryName, isDirectory: true)
    }

    static func finalizerActionPlanURL(
        id: String = UUID().uuidString,
        temporaryDirectory: URL = temporaryDirectory()
    ) -> URL {
        finalizerActionPlanDirectory(temporaryDirectory: temporaryDirectory)
            .appendingPathComponent("\(id).\(jsonExtension)")
    }
}
