import Foundation

enum ClawixTemporaryRoutes {
    static let audioPlaybackCacheDirectoryName = "clawix-audio"
    static let voiceRecordingPrefix = "clawix_voice"
    static let m4aExtension = "m4a"

    static func temporaryDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.temporaryDirectory
    }

    static func cachesDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? temporaryDirectory(fileManager: fileManager)
    }

    static func audioPlaybackCacheDirectory(fileManager: FileManager = .default) -> URL {
        cachesDirectory(fileManager: fileManager)
            .appendingPathComponent(audioPlaybackCacheDirectoryName, isDirectory: true)
    }

    static func audioPlaybackCacheURL(audioId: String, fileExtension: String, fileManager: FileManager = .default) -> URL {
        audioPlaybackCacheDirectory(fileManager: fileManager)
            .appendingPathComponent("\(safePathComponent(audioId)).\(safePathComponent(fileExtension))", isDirectory: false)
    }

    static func voiceRecordingURL(timestamp: TimeInterval = Date().timeIntervalSince1970) -> URL {
        temporaryDirectory()
            .appendingPathComponent("\(voiceRecordingPrefix)_\(Int(timestamp)).\(m4aExtension)", isDirectory: false)
    }

    static func designExportURL(fileExtension: String, suggestedName: String, id: String = String(UUID().uuidString.prefix(6))) -> URL {
        let base = suggestedName.isEmpty ? "Untitled" : suggestedName
        return temporaryDirectory()
            .appendingPathComponent("\(safePathComponent(base))-\(safePathComponent(id))", isDirectory: false)
            .appendingPathExtension(safePathComponent(fileExtension))
    }

    private static func safePathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? $0 : UnicodeScalar("-")! }
        let component = String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
            .lowercased()
        return component.isEmpty ? "item" : component
    }
}
