import Foundation

extension AppState {
    func syncChatStoreFromLegacySnapshots() {
        chatStore.replaceActive(with: chats)
        chatStore.replaceArchived(with: archivedChats)
        stripLegacyTranscriptPayloadsIfNeeded()
    }

    func stripLegacyTranscriptPayloadsIfNeeded() {
        guard !syncingLegacyChatsFromStore else { return }
        let activeNeedsStrip = chats.contains { !$0.messages.isEmpty }
        let archivedNeedsStrip = archivedChats.contains { !$0.messages.isEmpty }
        guard activeNeedsStrip || archivedNeedsStrip else { return }
        syncingLegacyChatsFromStore = true
        if activeNeedsStrip {
            chats = chats.map(\.summarySnapshot)
        }
        if archivedNeedsStrip {
            archivedChats = archivedChats.map(\.summarySnapshot)
        }
        syncingLegacyChatsFromStore = false
    }

    func syncLegacyChatFromStore(chatId: UUID) {
        guard let snapshot = chatStore.summarySnapshot(id: chatId) else { return }
        syncingLegacyChatsFromStore = true
        if snapshot.isArchived {
            if let idx = archivedChats.firstIndex(where: { $0.id == chatId }) {
                archivedChats[idx] = snapshot
            } else {
                archivedChats.insert(snapshot, at: 0)
            }
            chats.removeAll { $0.id == chatId }
        } else {
            var nextChats = chats
            if let idx = nextChats.firstIndex(where: { $0.id == chatId }) {
                nextChats[idx] = snapshot
            } else {
                nextChats.insert(snapshot, at: 0)
            }
            chats = boundedSidebarChats(nextChats, preserving: chatId)
            archivedChats.removeAll { $0.id == chatId }
        }
        syncingLegacyChatsFromStore = false
    }

    func replaceLegacyChatsFromStore() {
        syncingLegacyChatsFromStore = true
        let preservingId: UUID?
        if case let .chat(id) = currentRoute {
            preservingId = id
        } else {
            preservingId = nil
        }
        chats = boundedSidebarChats(chatStore.activeSnapshots, preserving: preservingId)
        archivedChats = chatStore.archivedSnapshots
        syncingLegacyChatsFromStore = false
    }
}
