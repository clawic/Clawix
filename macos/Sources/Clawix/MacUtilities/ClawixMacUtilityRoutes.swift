import Foundation

enum ClawixMacUtilityRoutes {
    static let pmsetCLI = ClawixSystemToolRoutes.pmsetCLI
    static let defaultsCLI = ClawixSystemToolRoutes.defaultsCLI
    static let killallCLI = ClawixSystemToolRoutes.killallCLI

    static let finderApp = ClawixKnownAppRoutes.finder.fallbackPath
    static let terminalApp = ClawixKnownAppRoutes.terminal.fallbackPath
    static let shortcutsApp = ClawixKnownAppRoutes.shortcuts.fallbackPath
    static let passwordsApp = ClawixKnownAppRoutes.passwords.fallbackPath
}
