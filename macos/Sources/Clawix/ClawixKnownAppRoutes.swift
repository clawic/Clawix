import Foundation

struct ClawixKnownAppRoute: Hashable {
    let bundleId: String
    let name: String
    let fallbackPath: String

    var editorOption: EditorOption {
        EditorOption(bundleId: bundleId, name: name, fallbackPath: fallbackPath)
    }
}

enum ClawixKnownAppRoutes {
    static let applicationsDirectory = "/Applications"
    static let systemApplicationsDirectory = "/System/Applications"
    static let systemUtilitiesDirectory = "\(systemApplicationsDirectory)/Utilities"
    static let systemCoreServicesDirectory = "/System/Library/CoreServices"

    static func applicationsApp(_ appName: String) -> String {
        "\(applicationsDirectory)/\(appName).app"
    }

    static func systemApplicationsApp(_ appName: String) -> String {
        "\(systemApplicationsDirectory)/\(appName).app"
    }

    static func systemUtilitiesApp(_ appName: String) -> String {
        "\(systemUtilitiesDirectory)/\(appName).app"
    }

    static func systemCoreServicesApp(_ appName: String) -> String {
        "\(systemCoreServicesDirectory)/\(appName).app"
    }

    static func appBundleResourcesDirectory(appPath: String) -> String {
        "\(appPath)/Contents/Resources"
    }

    static func applicationResourcesDirectory(appName: String) -> String {
        appBundleResourcesDirectory(appPath: applicationsApp(appName))
    }

    static let vsCode = ClawixKnownAppRoute(
        bundleId: "com.microsoft.VSCode",
        name: "VS Code",
        fallbackPath: applicationsApp("Visual Studio Code")
    )
    static let cursor = ClawixKnownAppRoute(
        bundleId: "com.todesktop.230313mzl4w4u92",
        name: "Cursor",
        fallbackPath: applicationsApp("Cursor")
    )
    static let finder = ClawixKnownAppRoute(
        bundleId: "com.apple.finder",
        name: "Finder",
        fallbackPath: systemCoreServicesApp("Finder")
    )
    static let terminal = ClawixKnownAppRoute(
        bundleId: "com.apple.Terminal",
        name: "Terminal",
        fallbackPath: systemUtilitiesApp("Terminal")
    )
    static let ghostty = ClawixKnownAppRoute(
        bundleId: "com.mitchellh.ghostty",
        name: "Ghostty",
        fallbackPath: applicationsApp("Ghostty")
    )
    static let xcode = ClawixKnownAppRoute(
        bundleId: "com.apple.dt.Xcode",
        name: "Xcode",
        fallbackPath: applicationsApp("Xcode")
    )
    static let androidStudio = ClawixKnownAppRoute(
        bundleId: "com.google.android.studio",
        name: "Android Studio",
        fallbackPath: applicationsApp("Android Studio")
    )
    static let shortcuts = ClawixKnownAppRoute(
        bundleId: "com.apple.shortcuts",
        name: "Shortcuts",
        fallbackPath: systemApplicationsApp("Shortcuts")
    )
    static let passwords = ClawixKnownAppRoute(
        bundleId: "com.apple.Passwords",
        name: "Passwords",
        fallbackPath: systemApplicationsApp("Passwords")
    )

    static let editorPickerOptions: [EditorOption] = [
        vsCode.editorOption,
        cursor.editorOption,
        finder.editorOption,
        terminal.editorOption,
        ghostty.editorOption,
        xcode.editorOption,
        androidStudio.editorOption,
    ]

    static let fileLinkEditorOptions: [EditorOption] = [
        vsCode.editorOption,
        cursor.editorOption,
        terminal.editorOption,
        ghostty.editorOption,
        xcode.editorOption,
        androidStudio.editorOption,
    ]

    static func route(named name: String) -> ClawixKnownAppRoute? {
        [
            vsCode,
            cursor,
            finder,
            terminal,
            ghostty,
            xcode,
            androidStudio,
        ].first { $0.name == name }
    }
}
