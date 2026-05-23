import AppKit
import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let rootSearch = Self(
        SearchEntrypointShortcutBroker.rootBindingId,
        default: .init(.space, modifiers: [.command, .option])
    )
}

@MainActor
enum SearchEntrypointShortcutsInstaller {
    private static var installed = false

    static func installIfNeeded() {
        guard !installed else { return }
        installed = true

        KeyboardShortcuts.onKeyDown(for: .rootSearch) {
            Task { @MainActor in
                let decision = validateRootSearchShortcut(
                    KeyboardShortcuts.getShortcut(for: .rootSearch)
                )
                guard decision.allowed else { return }
                RootSearchPanelController.shared.show()
            }
        }
    }

    nonisolated static func validateRootSearchShortcut(
        _ shortcut: KeyboardShortcuts.Shortcut?
    ) -> SearchEntrypointShortcutDecision {
        SearchEntrypointShortcutBroker.validate(
            SearchEntrypointShortcutRequest(
                entrypointId: SearchEntrypointShortcutBroker.rootEntrypointId,
                bindingId: SearchEntrypointShortcutBroker.rootBindingId,
                chord: chordDescription(for: shortcut) ?? "",
                routeTarget: SearchEntrypointShortcutBroker.rootRouteTarget
            )
        )
    }

    nonisolated static func chordDescription(for shortcut: KeyboardShortcuts.Shortcut?) -> String? {
        guard let shortcut, let key = shortcut.key else { return nil }

        var parts: [String] = []
        let modifiers = shortcut.modifiers
        if modifiers.contains(.control) { parts.append("Control") }
        if modifiers.contains(.option) { parts.append("Option") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        if modifiers.contains(.command) { parts.append("Command") }
        parts.append(keyDescription(for: key))
        return parts.joined(separator: "-")
    }

    private nonisolated static func keyDescription(for key: KeyboardShortcuts.Key) -> String {
        switch key {
        case .space: return "Space"
        case .tab: return "Tab"
        case .escape: return "Escape"
        case .return: return "Return"
        case .delete: return "Delete"
        case .g: return "G"
        default: return String(key.rawValue)
        }
    }
}
