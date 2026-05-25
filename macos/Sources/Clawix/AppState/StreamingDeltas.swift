import Foundation

extension AppState {
    func appendAssistantDelta(chatId: UUID, delta: String) {
        if delta.isEmpty { return }
        RenderProbe.mark(
            "LiveStreamAppendEnter",
            fields: [
                "chat": chatId.uuidString,
                "kind": "content",
                "deltaChars": "\(delta.count)",
                "deltaWords": "\(Self.completeWordCount(in: delta))"
            ]
        )
        flushPendingReasoningDeltas(chatId: chatId)
        applyAssistantTextDelta(chatId: chatId, delta: delta)
    }

    /// Mark the most-recent assistant placeholder of a chat as finished.
    /// Used by the local-model (Ollama) chat path which doesn't go
    /// through the Codex turn-completion machinery.
    func markAssistantFinished(chatId: UUID, messageId: UUID) {
        flushPendingAssistantTextDeltas(chatId: chatId)
        flushPendingReasoningDeltas(chatId: chatId)
        guard let transcript = chatStore.transcript(for: chatId),
              transcript.lastMessage?.id == messageId
        else { return }
        transcript.mutateMessage(id: messageId) { message in
            flushStreamingCheckpointTails(&message)
            message.streamingFinished = true
        }
        chatStore.updateSummary(id: chatId) { summary in
            summary.hasActiveTurn = false
        }
        syncLegacyChatFromStore(chatId: chatId)
        scheduleStreamingCheckpointSettlement(chatId: chatId, messageId: messageId)
    }

    /// Replace the in-flight assistant placeholder with an error message.
    func markAssistantFailed(chatId: UUID, messageId: UUID, error: String) {
        dropPendingAssistantText(chatId: chatId)
        dropPendingReasoning(chatId: chatId)
        let failure = UserFacingFailure.classify(error)
        failure.log(surface: "chat.assistantFailed")
        guard let transcript = chatStore.transcript(for: chatId),
              let last = transcript.lastMessage,
              last.id == messageId
        else { return }
        let display = last.content.isEmpty
            ? failure.chatLine
            : "\(last.content)\n\n\(failure.chatLine)"
        transcript.mutateMessage(id: messageId) { message in
            message.content = display
            message.isError = true
            message.streamingFinished = true
            message.streamCheckpoints = StreamingFade.settledSentinel(prefixCount: display.count)
            message.streamPendingTail = ""
            settleReasoningCheckpoints(&message)
        }
        chatStore.updateSummary(id: chatId) { summary in
            summary.hasActiveTurn = false
        }
        syncLegacyChatFromStore(chatId: chatId)
        scheduleStreamingCheckpointSettlement(chatId: chatId, messageId: messageId)
    }

    /// Flush every chat's pending text. Called once per main-runloop
    /// tick by the scheduler. Safe to call directly when an external
    /// event needs the buffer drained synchronously (e.g. before
    /// finalizing a turn).
    func flushPendingAssistantTextDeltas() {
        assistantTextFlushScheduled = false
        guard !pendingAssistantTextBuffers.isEmpty else { return }
        let buffers = pendingAssistantTextBuffers
        pendingAssistantTextBuffers.removeAll(keepingCapacity: true)
        for (chatId, delta) in buffers where !delta.isEmpty {
            applyAssistantTextDelta(chatId: chatId, delta: delta)
        }
    }

    /// Drain a single chat's buffered deltas synchronously. Call this
    /// before any code path that reads or replaces
    /// `messages[last].content` on that chat (turn completion, daemon
    /// rehydrate, interrupt) so the buffer never lags behind the
    /// authoritative state.
    func flushPendingAssistantTextDeltas(chatId: UUID) {
        guard let delta = pendingAssistantTextBuffers.removeValue(forKey: chatId),
              !delta.isEmpty
        else { return }
        applyAssistantTextDelta(chatId: chatId, delta: delta)
    }

    /// Drop any pending text for a chat without applying it. Used when
    /// the daemon hands us the canonical content (`applyDaemonStreaming`,
    /// `appendDaemonMessage`) so we don't double-append after the
    /// authoritative replace.
    func dropPendingAssistantText(chatId: UUID) {
        pendingAssistantTextBuffers.removeValue(forKey: chatId)
    }

    func flushPendingReasoningDeltas() {
        reasoningFlushScheduled = false
        guard !pendingReasoningBuffers.isEmpty else { return }
        let buffers = pendingReasoningBuffers
        pendingReasoningBuffers.removeAll(keepingCapacity: true)
        for (chatId, delta) in buffers where !delta.isEmpty {
            applyReasoningDelta(chatId: chatId, delta: delta)
        }
    }

    func flushPendingReasoningDeltas(chatId: UUID) {
        guard let delta = pendingReasoningBuffers.removeValue(forKey: chatId),
              !delta.isEmpty
        else { return }
        applyReasoningDelta(chatId: chatId, delta: delta)
    }

    func dropPendingReasoning(chatId: UUID) {
        pendingReasoningBuffers.removeValue(forKey: chatId)
    }

    private func applyAssistantTextDelta(chatId: UUID, delta: String) {
        guard let transcript = chatStore.transcript(for: chatId),
              let lastMessage = transcript.lastMessage,
              lastMessage.role == .assistant
        else { return }
        let t0 = streamingPerfLogEnabled ? CFAbsoluteTimeGetCurrent() : 0
        var totalLen = 0
        var totalCps = 0
        var pendingTailCount = 0
        var checkpointDeltaCount = 0
        var queueDepth: Double = 0
        var messageId = lastMessage.id
        transcript.mutateMessage(id: lastMessage.id) { message in
            messageId = message.id
            message.content += delta
            // Mirror into the chronological timeline so message text
            // interleaves with reasoning and tool groups in arrival order
            // instead of always rendering after them as a separate block.
            let timeline = message.timeline
            if let lastEntry = timeline.last,
               case .message(let existingId, let existing) = lastEntry {
                message.timeline[timeline.count - 1] =
                    .message(id: existingId, text: existing + delta)
            } else {
                message.timeline.append(
                    .message(id: UUID(), text: delta)
                )
            }
            let cps = message.streamCheckpoints
            let lastAt = cps.last?.addedAt ?? .distantPast
            let result = StreamingFade.ingest(
                delta: delta,
                pendingTail: message.streamPendingTail,
                scheduledLength: cps.last?.prefixCount ?? 0,
                lastFadeStart: lastAt
            )
            if !result.newCheckpoints.isEmpty {
                message.streamCheckpoints.append(contentsOf: result.newCheckpoints)
            }
            message.streamCheckpoints = StreamingFade.compact(
                checkpoints: message.streamCheckpoints
            )
            message.streamPendingTail = result.pendingTail
            totalLen = message.content.count
            totalCps = message.streamCheckpoints.count
            pendingTailCount = result.pendingTail.count
            checkpointDeltaCount = result.newCheckpoints.count
            queueDepth = max(0, (message.streamCheckpoints.last?.addedAt ?? lastAt).timeIntervalSinceNow * 1000)
        }
        RenderProbe.mark(
            "LiveStreamModelAppend",
            fields: [
                "chat": chatId.uuidString,
                "message": messageId.uuidString,
                "deltaChars": "\(delta.count)",
                "deltaWords": "\(Self.completeWordCount(in: delta))",
                "totalChars": "\(totalLen)",
                "checkpoints": "\(totalCps)",
                "checkpointDelta": "\(checkpointDeltaCount)",
                "pendingTail": "\(pendingTailCount)",
                "queueAheadMs": String(format: "%.1f", queueDepth)
            ]
        )
        if streamingPerfLogEnabled {
            let t1 = CFAbsoluteTimeGetCurrent()
            let dt = lastDeltaArrivalTime > 0 ? (t0 - lastDeltaArrivalTime) * 1000 : 0
            lastDeltaArrivalTime = t0
            let line = String(
                format: "delta dt=%.1fms size=%d totalLen=%d ingest=%.2fms +cps=%d totalCps=%d pendTail=%d queueAheadMs=%.1f",
                dt, delta.count, totalLen, (t1 - t0) * 1000,
                checkpointDeltaCount, totalCps,
                pendingTailCount, queueDepth
            )
            streamingPerfLog.log("\(line, privacy: .public)")
        }
    }

    func appendReasoningDelta(chatId: UUID, delta: String) {
        guard !delta.isEmpty else { return }
        RenderProbe.mark(
            "LiveStreamAppendEnter",
            fields: [
                "chat": chatId.uuidString,
                "kind": "reasoning",
                "deltaChars": "\(delta.count)",
                "deltaWords": "\(Self.completeWordCount(in: delta))"
            ]
        )
        // Drain any pending agent-message deltas FIRST so the text the
        // model emitted before this reasoning chunk lands in the timeline
        // ahead of the new `.reasoning` entry. Without this, buffered text
        // applied a runloop tick later would appear after reasoning that
        // arrived later in the stream.
        flushPendingAssistantTextDeltas(chatId: chatId)
        applyReasoningDelta(chatId: chatId, delta: delta)
    }

    private func applyReasoningDelta(chatId: UUID, delta: String) {
        guard let transcript = chatStore.transcript(for: chatId),
              let lastMessage = transcript.lastMessage,
              lastMessage.role == .assistant
        else { return }
        var messageId = lastMessage.id
        var entryId = UUID()
        var totalChars = 0
        var checkpointCount = 0
        var checkpointDeltaCount = 0
        var pendingTailCount = 0
        var queueDepth: Double = 0
        transcript.mutateMessage(id: lastMessage.id) { message in
            messageId = message.id
            message.reasoningText += delta
            // Extend the trailing reasoning chunk in the timeline, or open a
            // new one if the last entry is a tools group (so the row order
            // becomes text -> tools -> text -> tools -> ...).
            let timeline = message.timeline
            let nextEntryId: UUID
            let newText: String
            if let lastEntry = timeline.last,
               case .reasoning(let existingId, let existing) = lastEntry {
                nextEntryId = existingId
                newText = existing + delta
                message.timeline[timeline.count - 1] =
                    .reasoning(id: nextEntryId, text: newText)
            } else {
                nextEntryId = UUID()
                newText = delta
                message.timeline.append(
                    .reasoning(id: nextEntryId, text: newText)
                )
            }
            entryId = nextEntryId
            let bucket = message.reasoningCheckpoints[entryId, default: []]
            let pending = message.reasoningPendingTails[entryId, default: ""]
            let result = StreamingFade.ingest(
                delta: delta,
                pendingTail: pending,
                scheduledLength: bucket.last?.prefixCount ?? 0,
                lastFadeStart: bucket.last?.addedAt ?? .distantPast
            )
            if !result.newCheckpoints.isEmpty {
                message.reasoningCheckpoints[entryId, default: []]
                    .append(contentsOf: result.newCheckpoints)
            }
            message.reasoningCheckpoints[entryId] = StreamingFade.compact(
                checkpoints: message.reasoningCheckpoints[entryId] ?? []
            )
            message.reasoningPendingTails[entryId] = result.pendingTail
            totalChars = message.reasoningText.count
            checkpointCount = message.reasoningCheckpoints[entryId]?.count ?? 0
            checkpointDeltaCount = result.newCheckpoints.count
            pendingTailCount = result.pendingTail.count
            queueDepth = max(
                0,
                (message.reasoningCheckpoints[entryId]?.last?.addedAt ?? .distantPast).timeIntervalSinceNow * 1000
            )
        }
        RenderProbe.mark(
            "LiveStreamReasoningModelAppend",
            fields: [
                "chat": chatId.uuidString,
                "message": messageId.uuidString,
                "entry": entryId.uuidString,
                "deltaChars": "\(delta.count)",
                "deltaWords": "\(Self.completeWordCount(in: delta))",
                "totalChars": "\(totalChars)",
                "checkpoints": "\(checkpointCount)",
                "checkpointDelta": "\(checkpointDeltaCount)",
                "pendingTail": "\(pendingTailCount)",
                "queueAheadMs": String(format: "%.1f", queueDepth)
            ]
        )
    }

    func markAssistantCompleted(chatId: UUID, finalText: String?) {
        // Drain any text deltas still buffered for this chat before we
        // fold in the canonical body / mark the turn finished.
        flushPendingAssistantTextDeltas(chatId: chatId)
        flushPendingReasoningDeltas(chatId: chatId)
        guard let transcript = chatStore.transcript(for: chatId),
              let lastMessage = transcript.lastMessage,
              lastMessage.role == .assistant
        else { return }
        // Fresh turn closed cleanly. Drop any "Interrupted" pill that
        // a previous hydration may have raised.
        transcript.mutateMessage(id: lastMessage.id) { message in
            if let text = finalText, !text.isEmpty {
                // If the canonical final body differs from what we accumulated
                // from deltas, the existing per-word checkpoints don't line up
                // with the new characters. Replaying every word as a fresh
                // fade-in would look like the answer animates twice. Instead,
                // mark the entire replacement as already settled so the user
                // sees the final body at full opacity without another ramp.
                if text != message.content {
                    message.streamCheckpoints = [
                        StreamCheckpoint(prefixCount: text.count, addedAt: .distantPast)
                    ]
                    message.streamPendingTail = ""
                }
                message.content = text
            }
            message.streamingFinished = true
            flushStreamingCheckpointTails(&message)
        }
        chatStore.updateSummary(id: chatId) { summary in
            summary.lastTurnInterrupted = false
            summary.hasActiveTurn = false
            if !isCurrentRoute(chatId: chatId) {
                summary.hasUnreadCompletion = true
            }
        }
        // If the user wasn't looking at this chat when the turn finished,
        // surface the soft-blue unread dot in the sidebar so they can spot
        // the freshly-arrived reply at a glance.
        syncLegacyChatFromStore(chatId: chatId)
        scheduleStreamingCheckpointSettlement(chatId: chatId, messageId: lastMessage.id)

        // A clean completion is the moment to release the next queued
        // follow-up (type-ahead). Hop to the next runloop tick so the
        // completion state fully settles before a new turn starts. We only
        // drain on natural completion: interrupts and errors leave the
        // queue intact so the user stays in control.
        if queuedMessages[chatId] != nil {
            Task { @MainActor [weak self] in
                self?.dispatchNextQueuedMessage(forChatId: chatId)
            }
        }
    }

    private static func completeWordCount(in text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }
}
