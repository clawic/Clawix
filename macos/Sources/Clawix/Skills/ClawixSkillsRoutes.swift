import Foundation

enum ClawixSkillsRoutes {
    struct ExternalDirectory: Identifiable, Equatable {
        let id: String
        let label: String
        let displayPath: String
    }

    static let skillsDirectoryName = "skills"

    static let defaultExternalDirectories: [ExternalDirectory] = [
        ExternalDirectory(id: "codex", label: "Codex CLI", displayPath: externalSkillsDisplayPath(rootDirectoryName: ".codex")),
        ExternalDirectory(id: "hermes", label: "HermesAgent", displayPath: externalSkillsDisplayPath(rootDirectoryName: ".hermes")),
        ExternalDirectory(id: "openclaude", label: "OpenClaude", displayPath: externalSkillsDisplayPath(rootDirectoryName: ".openclaude")),
        ExternalDirectory(id: "cursor", label: "Cursor", displayPath: externalSkillsDisplayPath(rootDirectoryName: ".cursor")),
    ]

    static var defaultExternalDirectoriesSummary: String {
        let visibleExamples = defaultExternalDirectories.prefix(2).map(\.displayPath).joined(separator: ", ")
        return "\(visibleExamples), etc."
    }

    static func externalSkillsDisplayPath(rootDirectoryName: String) -> String {
        ClawixPersistentSurfacePaths.userVisibleHomeChild(rootDirectoryName, skillsDirectoryName)
    }

    static func expandedPath(
        displayPath: String,
        userHomeDirectory: URL = ClawixUserHomeRoutes.directory()
    ) -> String {
        ClawixPersistentSurfacePaths.expandedUserVisiblePath(
            displayPath,
            userHomeDirectory: userHomeDirectory
        ).path
    }

    static func defaultSyncTargets(
        userHomeDirectory: URL = ClawixUserHomeRoutes.directory()
    ) -> [SkillSyncTarget] {
        defaultExternalDirectories.map { directory in
            SkillSyncTarget(
                id: directory.id,
                label: directory.label,
                home: expandedPath(displayPath: directory.displayPath, userHomeDirectory: userHomeDirectory),
                mode: .symlink,
                lastSyncedAt: nil,
                lastError: nil
            )
        }
    }
}
