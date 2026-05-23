import Foundation

enum ClawixTerminalRoutes {
    static let defaultShell = ClawixSystemToolRoutes.zshCLI

    static func resolvedShell(environment: [String: String]) -> String {
        environment["SHELL"] ?? defaultShell
    }

    static func userHomePath() -> String {
        ClawixUserHomeRoutes.path()
    }
}
