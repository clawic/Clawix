import Foundation

extension AppState {
    func scheduleStreamingCheckpointSettlement(chatId: UUID, messageId: UUID) {
        streamingSettlementTasks[messageId]?.cancel()

        guard let message = chatStore.transcript(for: chatId)?.messageStore(id: messageId)?.message else {
            streamingSettlementTasks[messageId] = nil
            return
        }
        let delay = streamingSettlementDelay(for: message)
        guard delay > 0 else {
            settleStreamingCheckpoints(chatId: chatId, messageId: messageId)
            return
        }

        streamingSettlementTasks[messageId] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.settleStreamingCheckpoints(chatId: chatId, messageId: messageId)
        }
    }

    private func streamingSettlementDelay(for message: ChatMessage) -> Double {
        let textDelay = StreamingFade.settlementDelay(checkpoints: message.streamCheckpoints)
        let reasoningDelay = message.reasoningCheckpoints.values
            .map { StreamingFade.settlementDelay(checkpoints: $0) }
            .max() ?? 0
        return max(textDelay, reasoningDelay)
    }

    func settleStreamingCheckpoints(chatId: UUID, messageId: UUID) {
        guard let transcript = chatStore.transcript(for: chatId),
              transcript.messageStore(id: messageId) != nil
        else {
            streamingSettlementTasks[messageId] = nil
            return
        }

        var beforeCount = 0
        var afterCount = 0
        var changed = false
        transcript.mutateMessage(id: messageId) { message in
            beforeCount = streamingCheckpointCount(message)
            let beforePending = !message.streamPendingTail.isEmpty || !message.reasoningPendingTails.isEmpty
            message.streamCheckpoints = StreamingFade.settled(checkpoints: message.streamCheckpoints)
            message.streamPendingTail = ""
            settleReasoningCheckpoints(&message)
            afterCount = streamingCheckpointCount(message)
            changed = beforeCount != afterCount || beforePending
        }
        streamingSettlementTasks[messageId] = nil

        PerfSignpost.renderStreaming.event("settle.checkpoints.before", beforeCount)
        PerfSignpost.renderStreaming.event("settle.checkpoints.after", afterCount)

        _ = changed
        // No legacy mirror sync on the streaming hot path. Transcript
        // content lives in ChatTranscriptStore/ChatMessageStore; the sidebar
        // and chrome read the named summary projection, not AppState.chats.
    }

    func flushStreamingCheckpointTails(_ message: inout ChatMessage) {
        if !message.streamPendingTail.isEmpty {
            let flushed = StreamingFade.ingest(
                delta: "",
                pendingTail: message.streamPendingTail,
                scheduledLength: message.streamCheckpoints.last?.prefixCount ?? 0,
                lastFadeStart: message.streamCheckpoints.last?.addedAt ?? .distantPast,
                flush: true
            )
            message.streamCheckpoints.append(contentsOf: flushed.newCheckpoints)
            message.streamCheckpoints = StreamingFade.compact(checkpoints: message.streamCheckpoints)
            message.streamPendingTail = flushed.pendingTail
        }

        for entry in message.timeline {
            guard case .reasoning(let entryId, _) = entry else { continue }
            let pending = message.reasoningPendingTails[entryId] ?? ""
            guard !pending.isEmpty else { continue }
            let checkpoints = message.reasoningCheckpoints[entryId] ?? []
            let flushed = StreamingFade.ingest(
                delta: "",
                pendingTail: pending,
                scheduledLength: checkpoints.last?.prefixCount ?? 0,
                lastFadeStart: checkpoints.last?.addedAt ?? .distantPast,
                flush: true
            )
            message.reasoningCheckpoints[entryId, default: []].append(contentsOf: flushed.newCheckpoints)
            message.reasoningCheckpoints[entryId] = StreamingFade.compact(
                checkpoints: message.reasoningCheckpoints[entryId] ?? []
            )
            message.reasoningPendingTails[entryId] = flushed.pendingTail
        }
    }

    func settleReasoningCheckpoints(_ message: inout ChatMessage) {
        var settled: [UUID: [StreamCheckpoint]] = [:]
        var validIds = Set<UUID>()
        for entry in message.timeline {
            guard case .reasoning(let entryId, _) = entry else { continue }
            validIds.insert(entryId)
            let checkpoints = StreamingFade.settled(
                checkpoints: message.reasoningCheckpoints[entryId] ?? []
            )
            if !checkpoints.isEmpty {
                settled[entryId] = checkpoints
            }
        }
        message.reasoningCheckpoints = settled
        message.reasoningPendingTails = message.reasoningPendingTails.filter { validIds.contains($0.key) }
        if message.streamingFinished || message.isError {
            message.reasoningPendingTails.removeAll(keepingCapacity: false)
        }
    }

    private func streamingCheckpointCount(_ message: ChatMessage) -> Int {
        message.streamCheckpoints.count + message.reasoningCheckpoints.values.reduce(0) { $0 + $1.count }
    }

    func isCurrentRoute(chatId: UUID) -> Bool {
        if case let .chat(id) = currentRoute, id == chatId { return true }
        return false
    }

    func clearUnreadIfChatRoute() {
        guard case let .chat(id) = currentRoute,
              chatStore.summary(id: id)?.hasUnreadCompletion == true
        else { return }
        // Named single-row event only: the sidebar row reacts to the
        // `chatStore.$summaries` publish. No broad AppState.chats sync.
        chatStore.updateSummary(id: id) { summary in
            summary.hasUnreadCompletion = false
        }
    }

    func markChat(chatId: UUID, hasActiveTurn: Bool) {
        guard chatStore.summary(id: chatId) != nil else { return }
        // Turn-boundary spinner flip is a single-row event. Routing it through
        // the named summary update keeps the broad AppState.objectWillChange
        // fan-out and the O(N-chats) legacy scan off the hot path.
        chatStore.updateSummary(id: chatId) { summary in
            summary.hasActiveTurn = hasActiveTurn
        }
    }

    /// Flip the sidebar's blue "unread" dot on the row, regardless of
    /// whether the user is currently looking at the chat. Used by the
    /// row's right-click "Mark as unread" / "Mark as read" actions.
    func toggleChatUnread(chatId: UUID) {
        guard chatStore.summary(id: chatId) != nil else { return }
        chatStore.updateSummary(id: chatId) { summary in
            summary.hasUnreadCompletion.toggle()
        }
    }

}
