import Foundation

enum ClawixCaptureToolRoutes {
    static let screencaptureCLI = ClawixSystemToolRoutes.screencaptureCLI

    static let ffmpegCandidatePaths = [
        ClawixSystemToolRoutes.optHomebrewBinTool("ffmpeg"),
        ClawixSystemToolRoutes.usrLocalBinTool("ffmpeg"),
        ClawixSystemToolRoutes.usrBinTool("ffmpeg"),
    ]

    static func ffmpegCandidateURLs() -> [URL] {
        ffmpegCandidatePaths.map { URL(fileURLWithPath: $0) }
    }
}
