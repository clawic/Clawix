import Foundation

enum ClawixMCPRoutes {
    static let suggestedCodeWorkspaceDirectoryName = "code"

    static var suggestedWorkingDirectoryDisplayPath: String {
        ClawixPersistentSurfacePaths.userVisibleHomeChild(suggestedCodeWorkspaceDirectoryName)
    }
}
