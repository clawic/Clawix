import Foundation

enum ClawixCaptureToolRoutes {
    static let screencaptureCLI = ClawixSystemToolRoutes.screencaptureCLI
    static let appSnapshotTempPrefix = "clawix-appshot"
    static let pngExtension = "png"

    static let ffmpegCandidatePaths = [
        ClawixSystemToolRoutes.optHomebrewBinTool("ffmpeg"),
        ClawixSystemToolRoutes.usrLocalBinTool("ffmpeg"),
        ClawixSystemToolRoutes.usrBinTool("ffmpeg"),
    ]

    static func temporaryDirectory(fileManager: FileManager = .default) -> URL {
        ClawixTemporaryRoutes.systemTemporaryDirectory(fileManager: fileManager)
    }

    static func appSnapshotURL(
        appSlug: String,
        timestamp: TimeInterval = Date().timeIntervalSince1970,
        temporaryDirectory: URL = temporaryDirectory()
    ) -> URL {
        temporaryDirectory.appendingPathComponent(
            "\(appSnapshotTempPrefix)-\(safePathComponent(appSlug))-\(Int(timestamp)).\(pngExtension)",
            isDirectory: false
        )
    }

    static func ffmpegCandidateURLs() -> [URL] {
        ffmpegCandidatePaths.map { URL(fileURLWithPath: $0) }
    }

    private static func safePathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? $0 : UnicodeScalar("-") }
        let component = String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
            .lowercased()
        return component.isEmpty ? "app" : component
    }
}
