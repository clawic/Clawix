import Foundation

enum ClawixDiagnosticLogRoutes {
    static let tempDirectory = ClawixTemporaryRoutes.unixTemporaryDirectoryPath
    static let renderProbeBaseName = "clawix-renders"
    static let quickAskLogName = "clawix-quickask.log"
    static let hotkeyDebugLogName = "clawix-hotkey.log"

    static var quickAskLogURL: URL {
        tempLogURL(fileName: quickAskLogName)
    }

    static var hotkeyDebugLogURL: URL {
        tempLogURL(fileName: hotkeyDebugLogName)
    }

    static func renderProbeLogPath(role: String?) -> String {
        guard let role, !role.isEmpty else {
            return tempLogPath(fileName: "\(renderProbeBaseName).log")
        }
        let suffix = role
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .replacingOccurrences(of: ".", with: "-")
        return tempLogPath(fileName: "\(renderProbeBaseName)-\(suffix.isEmpty ? "aux" : suffix).log")
    }

    private static func tempLogPath(fileName: String) -> String {
        tempLogURL(fileName: fileName).path
    }

    private static func tempLogURL(fileName: String) -> URL {
        ClawixTemporaryRoutes.unixTemporaryFileURL(fileName: fileName)
    }
}
