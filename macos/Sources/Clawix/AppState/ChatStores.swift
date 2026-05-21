import Combine
import Foundation

struct ChatSummary: Identifiable, Equatable {
    let id: UUID
    var title: String
    var createdAt: Date
    var clawixThreadId: String?
    var rolloutPath: URL?
    var historyHydrated: Bool
    var hasActiveTurn: Bool
    var contextUsage: ContextUsage?
    var projectId: UUID?
    var isArchived: Bool
    var isPinned: Bool
    var hasUnreadCompletion: Bool
    var cwd: String?
    var hasGitRepo: Bool
    var branch: String?
    var availableBranches: [String]
    var uncommittedFiles: Int?
    var forkedFromChatId: UUID?
    var forkedFromTitle: String?
    var forkBannerAfterMessageId: UUID?
    var lastTurnInterrupted: Bool
    var isQuickAskTemporary: Bool
    var isSideChat: Bool
    var agentId: String
    var lastMessageAt: Date?

    init(chat: Chat) {
        id = chat.id
        title = chat.title
        createdAt = chat.createdAt
        clawixThreadId = chat.clawixThreadId
        rolloutPath = chat.rolloutPath
        historyHydrated = chat.historyHydrated
        hasActiveTurn = chat.hasActiveTurn
        contextUsage = chat.contextUsage
        projectId = chat.projectId
        isArchived = chat.isArchived
        isPinned = chat.isPinned
        hasUnreadCompletion = chat.hasUnreadCompletion
        cwd = chat.cwd
        hasGitRepo = chat.hasGitRepo
        branch = chat.branch
        availableBranches = chat.availableBranches
        uncommittedFiles = chat.uncommittedFiles
        forkedFromChatId = chat.forkedFromChatId
        forkedFromTitle = chat.forkedFromTitle
        forkBannerAfterMessageId = chat.forkBannerAfterMessageId
        lastTurnInterrupted = chat.lastTurnInterrupted
        isQuickAskTemporary = chat.isQuickAskTemporary
        isSideChat = chat.isSideChat
        agentId = chat.agentId
        lastMessageAt = chat.lastMessageAt
    }

    func snapshot(messages: [ChatMessage]) -> Chat {
        var chat = Chat(
            id: id,
            title: title,
            messages: messages,
            createdAt: createdAt,
            clawixThreadId: clawixThreadId,
            rolloutPath: rolloutPath,
            historyHydrated: historyHydrated,
            hasActiveTurn: hasActiveTurn,
            projectId: projectId,
            isArchived: isArchived,
            isPinned: isPinned,
            hasUnreadCompletion: hasUnreadCompletion,
            cwd: cwd,
            hasGitRepo: hasGitRepo,
            branch: branch,
            availableBranches: availableBranches,
            uncommittedFiles: uncommittedFiles,
            forkedFromChatId: forkedFromChatId,
            forkedFromTitle: forkedFromTitle,
            forkBannerAfterMessageId: forkBannerAfterMessageId,
            lastTurnInterrupted: lastTurnInterrupted,
            isQuickAskTemporary: isQuickAskTemporary,
            isSideChat: isSideChat,
            agentId: agentId,
            lastMessageAt: lastMessageAt
        )
        chat.contextUsage = contextUsage
        return chat
    }

    func summarySnapshot() -> Chat {
        snapshot(messages: [])
    }
}

extension Chat {
    var summarySnapshot: Chat {
        var copy = self
        copy.messages = []
        return copy
    }
}

@MainActor
final class ChatMessageStore: ObservableObject, Identifiable {
    let id: UUID
    @Published var message: ChatMessage {
        didSet {
            RenderProbe.tick("ChatMessageStore.message")
            onChange()
        }
    }
    private let onChange: () -> Void

    init(_ message: ChatMessage, onChange: @escaping () -> Void = {}) {
        id = message.id
        self.message = message
        self.onChange = onChange
    }
}

@MainActor
final class ChatTranscriptStore: ObservableObject, Identifiable {
    let id: UUID
    @Published private(set) var messageIds: [UUID] = [] {
        didSet {
            RenderProbe.tick("ChatTranscriptStore.messageIds")
            onChange()
        }
    }
    private var messagesById: [UUID: ChatMessageStore] = [:]
    private let onChange: () -> Void

    init(chatId: UUID, messages: [ChatMessage] = [], onChange: @escaping () -> Void = {}) {
        id = chatId
        self.onChange = onChange
        replaceMessages(messages)
    }

    var messageStores: [ChatMessageStore] {
        messageIds.compactMap { messagesById[$0] }
    }

    var messages: [ChatMessage] {
        messageStores.map(\.message)
    }

    var lastMessage: ChatMessage? {
        guard let id = messageIds.last else { return nil }
        return messagesById[id]?.message
    }

    func messageStore(id: UUID) -> ChatMessageStore? {
        messagesById[id]
    }

    func replaceMessages(_ messages: [ChatMessage]) {
        var nextById: [UUID: ChatMessageStore] = [:]
        nextById.reserveCapacity(messages.count)
        for message in messages {
            if let existing = messagesById[message.id] {
                existing.message = message
                nextById[message.id] = existing
            } else {
                nextById[message.id] = ChatMessageStore(message, onChange: onChange)
            }
        }
        messagesById = nextById
        messageIds = messages.map(\.id)
    }

    func replaceWithTail(_ messages: [ChatMessage], limit: Int, keeping keepIds: Set<UUID> = []) {
        let boundedLimit = max(0, limit)
        let keepMessages = messages.filter { keepIds.contains($0.id) }
        let tail = Array(messages.suffix(boundedLimit))
        let tailIds = Set(tail.map(\.id))
        let missingKeep = keepMessages.filter { !tailIds.contains($0.id) }
        replaceMessages(missingKeep + tail)
    }

    func append(_ message: ChatMessage) {
        messagesById[message.id] = ChatMessageStore(message, onChange: onChange)
        messageIds.append(message.id)
    }

    func prepend(_ messages: [ChatMessage]) {
        guard !messages.isEmpty else { return }
        for message in messages {
            messagesById[message.id] = ChatMessageStore(message, onChange: onChange)
        }
        messageIds = messages.map(\.id) + messageIds
    }

    func trimToRecentWindow(maxMessages: Int, keeping keepIds: Set<UUID> = []) {
        guard maxMessages >= 0, messageIds.count > maxMessages else { return }
        let tailIds = Set(messageIds.suffix(maxMessages))
        let retain = Set(messageIds.filter { keepIds.contains($0) }).union(tailIds)
        for id in Array(messagesById.keys) where !retain.contains(id) {
            messagesById[id] = nil
        }
        messageIds = messageIds.filter { retain.contains($0) }
    }

    func removeAll(from index: Int) {
        guard messageIds.indices.contains(index) else { return }
        let removed = messageIds[index...]
        for id in removed {
            messagesById[id] = nil
        }
        messageIds.removeSubrange(index...)
    }

    func remove(id: UUID) {
        messagesById[id] = nil
        messageIds.removeAll { $0 == id }
    }

    func replace(id: UUID, with message: ChatMessage) {
        let replacementStore: ChatMessageStore
        if let store = messagesById[id] {
            store.message = message
            replacementStore = store
        } else {
            replacementStore = ChatMessageStore(message, onChange: onChange)
        }
        if message.id != id {
            messagesById[id] = nil
            messagesById[message.id] = replacementStore
            if let idx = messageIds.firstIndex(of: id) {
                messageIds[idx] = message.id
            } else {
                messageIds.append(message.id)
            }
        } else {
            messagesById[id] = replacementStore
            if !messageIds.contains(id) {
                messageIds.append(id)
            }
        }
    }

    func mutateMessage(id: UUID, _ body: (inout ChatMessage) -> Void) {
        guard let store = messagesById[id] else { return }
        var message = store.message
        body(&message)
        store.message = message
    }

    func mutateLastMessage(_ body: (inout ChatMessage) -> Void) {
        guard let id = messageIds.last else { return }
        mutateMessage(id: id, body)
    }

    func firstIndex(where predicate: (ChatMessage) -> Bool) -> Int? {
        messages.firstIndex(where: predicate)
    }
}

@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var summaries: [ChatSummary] = [] {
        didSet { RenderProbe.tick("ChatStore.summaries") }
    }
    @Published private(set) var archivedSummaries: [ChatSummary] = [] {
        didSet { RenderProbe.tick("ChatStore.archivedSummaries") }
    }

    private var transcripts: [UUID: ChatTranscriptStore] = [:]

    var activeSnapshots: [Chat] {
        summaries.map { $0.summarySnapshot() }
    }

    var archivedSnapshots: [Chat] {
        archivedSummaries.map { $0.summarySnapshot() }
    }

    func replaceActive(with chats: [Chat]) {
        summaries = chats.map(ChatSummary.init(chat:))
        reconcileTranscripts(with: chats)
    }

    func replaceArchived(with chats: [Chat]) {
        archivedSummaries = chats.map(ChatSummary.init(chat:))
        reconcileTranscripts(with: chats)
    }

    func upsert(_ chat: Chat, archived: Bool? = nil, at index: Int? = nil) {
        let isArchived = archived ?? chat.isArchived
        let summary = ChatSummary(chat: chat)
        if isArchived {
            archivedSummaries = upserted(summary, in: archivedSummaries, at: index)
            summaries.removeAll { $0.id == chat.id }
        } else {
            summaries = upserted(summary, in: summaries, at: index)
            archivedSummaries.removeAll { $0.id == chat.id }
        }
        if !chat.messages.isEmpty {
            transcript(forCreating: chat.id).replaceMessages(chat.messages)
        } else if transcripts[chat.id] == nil {
            transcripts[chat.id] = ChatTranscriptStore(chatId: chat.id)
        }
    }

    func remove(chatId: UUID) {
        summaries.removeAll { $0.id == chatId }
        archivedSummaries.removeAll { $0.id == chatId }
        transcripts[chatId] = nil
    }

    func summary(id: UUID) -> ChatSummary? {
        summaries.first(where: { $0.id == id }) ?? archivedSummaries.first(where: { $0.id == id })
    }

    func updateSummary(id: UUID, _ body: (inout ChatSummary) -> Void) {
        if let idx = summaries.firstIndex(where: { $0.id == id }) {
            body(&summaries[idx])
        } else if let idx = archivedSummaries.firstIndex(where: { $0.id == id }) {
            body(&archivedSummaries[idx])
        }
    }

    func transcript(for id: UUID) -> ChatTranscriptStore? {
        transcripts[id]
    }

    func transcript(forCreating id: UUID) -> ChatTranscriptStore {
        if let transcript = transcripts[id] { return transcript }
        let transcript = ChatTranscriptStore(chatId: id, onChange: { [weak self] in
            self?.objectWillChange.send()
        })
        transcripts[id] = transcript
        return transcript
    }

    func snapshot(id: UUID) -> Chat? {
        guard let summary = summary(id: id) else { return nil }
        return summary.snapshot(messages: transcripts[id]?.messages ?? [])
    }

    func summarySnapshot(id: UUID) -> Chat? {
        summary(id: id)?.summarySnapshot()
    }

    func appendMessage(chatId: UUID, _ message: ChatMessage) {
        transcript(forCreating: chatId).append(message)
        updateSummary(id: chatId) { summary in
            summary.lastMessageAt = message.timestamp
            summary.lastTurnInterrupted = false
        }
    }

    func replaceMessages(chatId: UUID, _ messages: [ChatMessage]) {
        transcript(forCreating: chatId).replaceMessages(messages)
    }

    func replaceMessageTail(chatId: UUID, _ messages: [ChatMessage], limit: Int, keeping keepIds: Set<UUID> = []) {
        transcript(forCreating: chatId).replaceWithTail(messages, limit: limit, keeping: keepIds)
    }

    func mutateMessage(chatId: UUID, messageId: UUID, _ body: (inout ChatMessage) -> Void) {
        transcript(for: chatId)?.mutateMessage(id: messageId, body)
    }

    private func snapshot(for summary: ChatSummary) -> Chat {
        summary.snapshot(messages: transcripts[summary.id]?.messages ?? [])
    }

    private func reconcileTranscripts(with chats: [Chat]) {
        let ids = Set(chats.map(\.id))
        for chat in chats {
            if !chat.messages.isEmpty {
                transcript(forCreating: chat.id).replaceMessages(chat.messages)
            } else if transcripts[chat.id] == nil {
                transcripts[chat.id] = ChatTranscriptStore(chatId: chat.id)
            }
        }
        let knownSummaryIds = Set(summaries.map(\.id)).union(archivedSummaries.map(\.id))
        for id in Array(transcripts.keys) where !ids.contains(id) && !knownSummaryIds.contains(id) {
            transcripts[id] = nil
        }
    }

    private func upserted(_ summary: ChatSummary, in list: [ChatSummary], at index: Int?) -> [ChatSummary] {
        var list = list
        if let existing = list.firstIndex(where: { $0.id == summary.id }) {
            list[existing] = summary
            return list
        }
        if let index {
            list.insert(summary, at: max(0, min(index, list.count)))
        } else {
            list.append(summary)
        }
        return list
    }
}
