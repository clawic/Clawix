import SwiftUI
import AppKit

/// The "Chat" menu in the menu bar. Surfaces the per-chat actions that also
/// live in the chat ellipsis / right-click menu (pin, rename, archive, copy)
/// plus keyboard navigation between chats, so every documented shortcut has a
/// discoverable home and a working accelerator. Items that need an active chat
/// disable themselves when the current route isn't a chat.
struct ChatMenuCommands: View {
    @ObservedObject var appState: AppState

    private var currentChat: Chat? {
        guard let id = appState.currentChatId else { return nil }
        return appState.chat(byId: id)
    }

    private var canComposeHere: Bool {
        switch appState.currentRoute {
        case .chat, .home: return true
        default:           return false
        }
    }

    var body: some View {
        Button(currentChat?.isPinned == true ? "Unpin Chat" : "Pin Chat") {
            if let chat = currentChat { appState.togglePin(chatId: chat.id) }
        }
        .keyboardShortcut("p", modifiers: [.command, .option])
        .disabled(currentChat == nil || currentChat?.isArchived == true)

        Button("Rename Chat…") {
            appState.pendingRenameChat = currentChat
        }
        .keyboardShortcut("r", modifiers: [.command, .option])
        .disabled(currentChat?.clawixThreadId == nil)

        Button("Archive Chat") {
            if let chat = currentChat { appState.archiveChat(chatId: chat.id) }
        }
        .keyboardShortcut("a", modifiers: [.command, .shift])
        .disabled(currentChat == nil)

        Divider()

        Button("Copy Working Directory") {
            if let cwd = currentChat?.cwd, !cwd.isEmpty {
                ChatMenuCommands.copyToPasteboard(cwd)
            }
        }
        .keyboardShortcut("c", modifiers: [.command, .shift])
        .disabled((currentChat?.cwd ?? "").isEmpty)

        Button("Copy Session ID") {
            if let id = currentChat?.clawixThreadId {
                ChatMenuCommands.copyToPasteboard(id)
            }
        }
        .keyboardShortcut("c", modifiers: [.command, .option])
        .disabled(currentChat?.clawixThreadId == nil)

        Button("Copy Deeplink") {
            if let id = currentChat?.clawixThreadId {
                ChatMenuCommands.copyToPasteboard("clawix://session/\(id)")
            }
        }
        .keyboardShortcut("l", modifiers: [.command, .option])
        .disabled(currentChat?.clawixThreadId == nil)

        Divider()

        Menu("Go to Chat") {
            ForEach(1...9, id: \.self) { slot in
                Button("Chat \(slot)") {
                    appState.goToChatSlot(slot)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(slot)")), modifiers: .command)
            }
        }

        Button("Next Recently Viewed") {
            appState.cycleRecentlyViewedChat(forward: true)
        }
        .keyboardShortcut(.tab, modifiers: .control)
        .disabled(appState.recentlyViewedChatIds.count < 2)

        Button("Previous Recently Viewed") {
            appState.cycleRecentlyViewedChat(forward: false)
        }
        .keyboardShortcut(.tab, modifiers: [.control, .shift])
        .disabled(appState.recentlyViewedChatIds.count < 2)

        Divider()

        Button("Open Model Picker") {
            appState.requestModelPickerSignal = UUID()
        }
        .keyboardShortcut("m", modifiers: [.control, .shift])
        .disabled(!canComposeHere)

        Button("Start Dictation") {
            appState.requestStartDictationSignal = UUID()
        }
        .keyboardShortcut("d", modifiers: [.control, .shift])
        .disabled(!canComposeHere)
    }

    static func copyToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
}
