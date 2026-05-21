import Foundation

extension AppState {
    func syncChatStoreFromLegacySnapshots() {
        chatStore.replaceActive(with: chats)
        chatStore.replaceArchived(with: archivedChats)
    }

    func syncLegacyChatFromStore(chatId: UUID) {
        guard let snapshot = chatStore.snapshot(id: chatId) else { return }
        syncingLegacyChatsFromStore = true
        if snapshot.isArchived {
            if let idx = archivedChats.firstIndex(where: { $0.id == chatId }) {
                archivedChats[idx] = snapshot
            } else {
                archivedChats.insert(snapshot, at: 0)
            }
            chats.removeAll { $0.id == chatId }
        } else {
            if let idx = chats.firstIndex(where: { $0.id == chatId }) {
                chats[idx] = snapshot
            } else {
                chats.insert(snapshot, at: 0)
            }
            archivedChats.removeAll { $0.id == chatId }
        }
        syncingLegacyChatsFromStore = false
    }

    func replaceLegacyChatsFromStore() {
        syncingLegacyChatsFromStore = true
        chats = chatStore.activeSnapshots
        archivedChats = chatStore.archivedSnapshots
        syncingLegacyChatsFromStore = false
    }
}
