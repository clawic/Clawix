import Foundation

// User-facing toggles that control whether app actions are mirrored to
// the underlying runtime (Codex CLI today). The local SQLite store is
// always the canonical source of truth for what the app shows; these
// flags only gate the side-effect of also writing to the runtime.
//
// Stored in UserDefaults under the standard app prefs suite, mirroring
// the convention used by PreferredLanguage and the sidebar toggles.
enum SyncSettings {
    static var store: UserDefaults { UserDefaults(suiteName: appPrefsSuite) ?? .standard }
    static let archiveKey = "SyncArchiveWithCodex"
    static let renamesKey = "SyncRenamesWithCodex"
    static let autoReloadKey = "AutoReloadOnFocus"

    static var syncArchiveWithCodex: Bool {
        get { store.object(forKey: archiveKey) as? Bool ?? true }
        set { store.set(newValue, forKey: archiveKey) }
    }

    static var syncRenamesWithCodex: Bool {
        get { store.object(forKey: renamesKey) as? Bool ?? true }
        set { store.set(newValue, forKey: renamesKey) }
    }

    static var autoReloadOnFocus: Bool {
        get { store.object(forKey: autoReloadKey) as? Bool ?? false }
        set { store.set(newValue, forKey: autoReloadKey) }
    }
}
