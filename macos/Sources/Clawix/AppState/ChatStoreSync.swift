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
        // The real per-send / per-turn legacy-mirror cost. Reassigning the
        // `@Published chats` here fans `AppState.objectWillChange` out to every
        // @EnvironmentObject observer (the open-session shell + chrome) for a
        // conceptually single-row event, and walks/rebuilds the bounded `chats`
        // array O(N-chats). NOTE: the `chats` didSet's replaceActive is skipped
        // while `syncingLegacyChatsFromStore` is set, so the per-event cost is
        // this scan + the broad publish, NOT a summary rebuild. Instrumented so
        // both are countable from code; `legacy.sync.scanned` per call equals
        // the array size walked, and should drop to zero once this mirror is
        // retired on the send/turn hot path (ADR 0036 view-layer slice).
        RenderProbe.count("legacy.sync.scanned", by: chats.count, recordsActivity: false)
        RenderProbe.time("legacy.sync") {
            syncingLegacyChatsFromStore = true
            if snapshot.isArchived {
                if let idx = archivedChats.firstIndex(where: { $0.id == chatId }) {
                    if archivedChats[idx] != snapshot {
                        archivedChats[idx] = snapshot
                    }
                } else {
                    archivedChats.insert(snapshot, at: 0)
                }
                if chats.contains(where: { $0.id == chatId }) {
                    chats.removeAll { $0.id == chatId }
                }
            } else {
                var nextChats = chats
                if let idx = nextChats.firstIndex(where: { $0.id == chatId }) {
                    nextChats[idx] = snapshot
                } else {
                    nextChats.insert(snapshot, at: 0)
                }
                let boundedChats = boundedSidebarChats(nextChats, preserving: chatId)
                if chats != boundedChats {
                    chats = boundedChats
                }
                if archivedChats.contains(where: { $0.id == chatId }) {
                    archivedChats.removeAll { $0.id == chatId }
                }
            }
            syncingLegacyChatsFromStore = false
        }
    }

    func syncLegacyChatFromStoreIfRenderedSummaryChanged(chatId: UUID) {
        guard let snapshot = chatStore.summarySnapshot(id: chatId) else { return }
        guard let existing = chats.first(where: { $0.id == chatId })
            ?? archivedChats.first(where: { $0.id == chatId })
        else {
            syncLegacyChatFromStore(chatId: chatId)
            return
        }
        guard legacyRenderedSummaryDiffers(existing, snapshot) else { return }
        syncLegacyChatFromStore(chatId: chatId)
    }

    private func legacyRenderedSummaryDiffers(_ lhs: Chat, _ rhs: Chat) -> Bool {
        lhs.id != rhs.id
            || lhs.title != rhs.title
            || lhs.createdAt != rhs.createdAt
            || lhs.clawixThreadId != rhs.clawixThreadId
            || lhs.rolloutPath != rhs.rolloutPath
            || lhs.historyHydrated != rhs.historyHydrated
            || lhs.hasActiveTurn != rhs.hasActiveTurn
            || lhs.contextUsage != rhs.contextUsage
            || lhs.projectId != rhs.projectId
            || lhs.isArchived != rhs.isArchived
            || lhs.isPinned != rhs.isPinned
            || lhs.hasUnreadCompletion != rhs.hasUnreadCompletion
            || lhs.cwd != rhs.cwd
            || lhs.hasGitRepo != rhs.hasGitRepo
            || lhs.branch != rhs.branch
            || lhs.availableBranches != rhs.availableBranches
            || lhs.uncommittedFiles != rhs.uncommittedFiles
            || lhs.forkedFromChatId != rhs.forkedFromChatId
            || lhs.forkedFromTitle != rhs.forkedFromTitle
            || lhs.forkBannerAfterMessageId != rhs.forkBannerAfterMessageId
            || lhs.lastTurnInterrupted != rhs.lastTurnInterrupted
            || lhs.isQuickAskTemporary != rhs.isQuickAskTemporary
            || lhs.isSideChat != rhs.isSideChat
            || lhs.agentId != rhs.agentId
            || lhs.lastMessageAt != rhs.lastMessageAt
    }

    func replaceLegacyChatsFromStore() {
        syncingLegacyChatsFromStore = true
        let preservingId: UUID?
        if case let .chat(id) = currentRoute {
            preservingId = id
        } else {
            preservingId = nil
        }
        let nextChats = boundedSidebarChats(chatStore.activeSnapshots, preserving: preservingId)
        let nextArchived = chatStore.archivedSnapshots
        if chats != nextChats {
            chats = nextChats
        }
        if archivedChats != nextArchived {
            archivedChats = nextArchived
        }
        syncingLegacyChatsFromStore = false
    }
}
