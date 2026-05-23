import Foundation

/// A follow-up message the user composed while the agent was still working
/// on a previous turn. Queued messages dispatch automatically, oldest
/// first, as each turn for the chat completes cleanly.
struct QueuedMessage: Identifiable, Equatable {
    let id: UUID
    var text: String
    var attachments: [ComposerAttachment]

    init(id: UUID = UUID(), text: String, attachments: [ComposerAttachment]) {
        self.id = id
        self.text = text
        self.attachments = attachments
    }

    /// One-line label for the queued chip. Falls back to the first
    /// attachment's name when the message is attachments-only, matching
    /// the title-seed convention used elsewhere when sending.
    var preview: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if let first = attachments.first {
            return first.displayName
        }
        return ""
    }
}

extension AppState {
    /// Upper bound on queued follow-ups per chat. Keeps a stuck or
    /// runaway loop from accumulating an unbounded backlog.
    private var maxQueuedMessagesPerChat: Int { 20 }

    /// Stage a follow-up to send once the chat's active turn finishes.
    func enqueueMessage(text: String, attachments: [ComposerAttachment], forChatId chatId: UUID) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }
        var queue = queuedMessages[chatId] ?? []
        guard queue.count < maxQueuedMessagesPerChat else { return }
        queue.append(QueuedMessage(text: trimmed, attachments: attachments))
        queuedMessages[chatId] = queue
    }

    func removeQueuedMessage(id: UUID, forChatId chatId: UUID) {
        guard var queue = queuedMessages[chatId] else { return }
        queue.removeAll { $0.id == id }
        if queue.isEmpty {
            queuedMessages.removeValue(forKey: chatId)
        } else {
            queuedMessages[chatId] = queue
        }
    }

    func clearQueuedMessages(forChatId chatId: UUID) {
        guard queuedMessages[chatId] != nil else { return }
        queuedMessages.removeValue(forKey: chatId)
    }

    /// Pop the oldest queued follow-up for `chatId` and send it through the
    /// same path side chats use, starting a fresh turn. Called when the
    /// previous turn completes cleanly; a no-op when nothing is queued or
    /// a turn is somehow still in flight.
    func dispatchNextQueuedMessage(forChatId chatId: UUID) {
        guard var queue = queuedMessages[chatId], !queue.isEmpty else { return }
        // The chat must exist and be idle before we start the next turn.
        guard let summary = chatStore.summary(id: chatId), !summary.hasActiveTurn else { return }

        let next = queue.removeFirst()
        if queue.isEmpty {
            queuedMessages.removeValue(forKey: chatId)
        } else {
            queuedMessages[chatId] = queue
        }

        let synthetic = ComposerState()
        synthetic.text = next.text
        synthetic.attachments = next.attachments
        sendMessage(forChatId: chatId, composer: synthetic)
    }
}
