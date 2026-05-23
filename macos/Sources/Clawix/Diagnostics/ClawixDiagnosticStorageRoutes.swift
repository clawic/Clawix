import Foundation

enum ClawixDiagnosticStorageRoutes {
    static let fallbackBundleIdentifier = "clawix.desktop"
    static let diagnosticsDirectoryName = "Diagnostics"

    static func bundleIdentifier(from bundle: Bundle = .main) -> String {
        bundle.bundleIdentifier ?? fallbackBundleIdentifier
    }

    static func applicationSupportRoot(fileManager: FileManager = .default) -> URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }

    static func diagnosticsDirectoryURL(
        applicationSupportRoot: URL,
        bundleIdentifier: String
    ) -> URL {
        applicationSupportRoot
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent(diagnosticsDirectoryName, isDirectory: true)
    }

    static func diagnosticsFileURL(
        named name: String,
        applicationSupportRoot: URL,
        bundleIdentifier: String
    ) -> URL {
        diagnosticsDirectoryURL(
            applicationSupportRoot: applicationSupportRoot,
            bundleIdentifier: bundleIdentifier
        )
        .appendingPathComponent(name, isDirectory: false)
    }
}
