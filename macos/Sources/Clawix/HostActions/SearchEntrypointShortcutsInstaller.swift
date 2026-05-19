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
                let decision = SearchEntrypointShortcutBroker.validate(
                    SearchEntrypointShortcutRequest(
                        entrypointId: SearchEntrypointShortcutBroker.rootEntrypointId,
                        bindingId: SearchEntrypointShortcutBroker.rootBindingId,
                        chord: SearchEntrypointShortcutBroker.rootDefaultChord,
                        routeTarget: SearchEntrypointShortcutBroker.rootRouteTarget
                    )
                )
                guard decision.allowed else { return }
                RootSearchPanelController.shared.show()
            }
        }
    }
}
