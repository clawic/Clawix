import SwiftUI
import AppKit

struct HelpMenuCommands: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Button(L10n.t("Send Feedback…")) {
            appState.isFeedbackOpen = true
        }

        Button("Send feedback about \(appDisplayName) to the platform vendor") {
            HelpMenuActions.sendFeedbackToApple()
        }

        Divider()

        Button("Model Context Protocol") {
            HelpMenuActions.open("https://modelcontextprotocol.io/")
        }

        Divider()

        Button("Command Palette") {
            appState.isCommandPaletteOpen = true
        }
        .keyboardShortcut("k", modifiers: [.command])

        Button("Keyboard Shortcuts") {
            appState.isKeyboardShortcutsOpen = true
        }
        // ⌘? — i.e. ⇧⌘/ on a US layout.
        .keyboardShortcut("/", modifiers: [.command, .shift])

        Button("Start Performance Trace") {
            PerfTraceController.shared.toggle()
        }
        .keyboardShortcut("s", modifiers: [.command, .shift])
    }
}

enum HelpMenuActions {
    static func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    static func sendFeedbackToApple() {
        // Platform-vendor feedback endpoint for macOS system feedback.
        open("https://www.apple.com/feedback/macos.html")
    }
}
