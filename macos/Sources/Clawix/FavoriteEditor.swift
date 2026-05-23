import Foundation
import AppKit
import KeyboardShortcuts

/// Launches a folder in an external editor (or Finder/Terminal). Shared by the
/// "Open with" chrome dropdown and the global "open favorite editor" shortcut so
/// both paths use identical launch semantics.
enum EditorLauncher {
    static func open(folderPath: String, with editor: EditorOption) {
        let folderURL = URL(fileURLWithPath: folderPath, isDirectory: true)
        let appURL: URL? =
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: editor.bundleId)
            ?? (FileManager.default.fileExists(atPath: editor.fallbackPath)
                ? URL(fileURLWithPath: editor.fallbackPath)
                : nil)

        guard let appURL else {
            NSWorkspace.shared.open(folderURL)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [folderURL],
            withApplicationAt: appURL,
            configuration: configuration,
            completionHandler: nil
        )
    }
}

/// Remembers the editor the user most recently opened a folder with, so the
/// chrome dropdown trigger reflects it and the "open favorite editor" shortcut
/// can launch it without going through the menu. Falls back to Finder (then the
/// first known option) when nothing has been picked yet or the stored bundle id
/// is no longer in the catalog.
enum FavoriteEditorStore {
    private static var store: UserDefaults { SidebarPrefs.store }

    static func record(_ editor: EditorOption) {
        store.set(editor.bundleId, forKey: ClawixPersistentSurfaceKeys.favoriteEditorBundleId)
    }

    static var favorite: EditorOption {
        let options = ClawixKnownAppRoutes.editorPickerOptions
        if let bundleId = store.string(forKey: ClawixPersistentSurfaceKeys.favoriteEditorBundleId),
           let match = options.first(where: { $0.bundleId == bundleId }) {
            return match
        }
        return options.first { $0.name == "Finder" } ?? options[0]
    }
}

extension KeyboardShortcuts.Name {
    /// Open the current project folder in the last-used external editor. ⌥⌘O by
    /// default to stay clear of ⌘O (File ▸ Open Folder). Customizable from
    /// Settings ▸ Keyboard Shortcuts.
    static let openFavoriteEditor = Self(
        "editor.openFavorite",
        default: .init(.o, modifiers: [.command, .option])
    )
}

/// Wires the global "open favorite editor" shortcut to the launcher. Registered
/// once from `App.init`. Mirrors `TerminalShortcutsInstaller`: the resolver pulls
/// the active project folder from `AppState`, so the shortcut targets whatever
/// chat/project the user is viewing (and does nothing when there is no folder).
@MainActor
enum FavoriteEditorShortcutInstaller {
    private static var installed = false

    static func installIfNeeded(resolveFolderPath: @escaping () -> String?) {
        if installed { return }
        installed = true

        KeyboardShortcuts.onKeyDown(for: .openFavoriteEditor) {
            guard let path = resolveFolderPath() else { return }
            EditorLauncher.open(folderPath: path, with: FavoriteEditorStore.favorite)
        }
    }
}

extension AppState {
    /// Absolute path of the folder the active chat or selected project maps to,
    /// or nil when there is no real folder context. Single source of truth for
    /// the "Open with" chrome dropdown and the open-favorite-editor shortcut, so
    /// both always target the same folder.
    var currentProjectFolderPath: String? {
        if case .chat(let id) = currentRoute,
           let chat = chat(byId: id),
           let pid = chat.projectId,
           let project = projects.first(where: { $0.id == pid }) {
            let expanded = (project.path as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) { return expanded }
        }
        if let project = selectedProject {
            let expanded = (project.path as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) { return expanded }
        }
        return nil
    }
}
