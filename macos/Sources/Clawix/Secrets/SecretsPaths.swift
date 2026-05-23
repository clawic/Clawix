import Foundation

enum SecretsPaths {
    static let deviceIdKey = "clawix.secrets.deviceId"

    /// Secrets directory. Honors the override route so dummy mode and tests can
    /// sandbox Secrets away from the user's real Application Support folder.
    /// Without it the real production location is used.
    static var directory: URL {
        ClawixSecretsRoutes.directoryURL()
    }

    static var databaseFile: URL {
        ClawixSecretsRoutes.databaseFileURL(directory: directory)
    }

    static var proxySocketFile: URL {
        ClawixSecretsRoutes.proxySocketFileURL(directory: directory)
    }

    static func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func vaultExists() -> Bool {
        FileManager.default.fileExists(atPath: databaseFile.path)
    }

    static func deviceId() -> String {
        let key = deviceIdKey
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: key)
        return new
    }
}
