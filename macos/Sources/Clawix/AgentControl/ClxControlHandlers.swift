import AppKit
import ApplicationServices
import ClawixCore

struct ClxControlResult {
    let status: Int
    let json: [String: Any]
}

/// The control verbs an agent instance exposes over its loopback endpoint. All
/// run on the main actor (they touch the UI / accessibility tree). Actions
/// prefer the accessibility path (which runs the control's real action, e.g. a
/// SwiftUI Button's closure, with no cursor and no foreground requirement) and
/// fall back to the registered closure when accessibility cannot reach it.
@MainActor
enum ClxControlHandlers {
    private static weak var appState: AppState?
    private static var recordedAnchorFrames: [String: CGRect] = [:]

    static func bind(appState: AppState) {
        guard ClxAgentInstance.isAgent else { return }
        self.appState = appState
    }

    static func handle(verb: String, args: [String: Any]) async -> ClxControlResult {
        switch verb {
        case "ping":      return ok(["ok": true, "instanceId": ClxAgentInstance.instanceId])
        case "diagnostics": return diagnostics()
        case "accept-legal": return acceptLegal()
        case "open-settings": return openSettings(args)
        case "open-chat": return openChat(args)
        case "mock-stream": return mockStream(args)
        case "mock-send": return mockSend(args)
        case "mock-bridge-stream": return mockBridgeStream(args)
        case "inventory": return inventory(args)
        case "click":     return click(args)
        case "hover":     return hover(args)
        case "mark":      return mark(args)
        case "record-anchor": return recordAnchor(args)
        case "measure-anchor-delta": return measureAnchorDelta(args)
        case "fixture-metadata-update": return fixtureMetadataUpdate(args)
        case "mock-stream-complete": return mockStreamComplete(args)
        case "scroll":    return scroll(args)
        case "scroll-to-bottom": return scrollToBottom(args)
        case "scroll-state": return scrollState(args)
        case "type":      return typeText(args)
        case "state":     return state(args)
        case "state-with-frame": return state(args)
        case "wait-visible": return await wait(args, condition: .visible)
        case "wait-gone": return await wait(args, condition: .gone)
        case "wait-enabled": return await wait(args, condition: .enabled)
        case "wait-text": return await wait(args, condition: .text)
        case "wait-count": return await wait(args, condition: .count)
        case "wait-route": return await wait(args, condition: .route)
        case "wait-frame-stable": return await wait(args, condition: .frameStable)
        case "wait-scroll-stable": return await wait(args, condition: .scrollStable)
        case "wait-bottom-anchored": return await wait(args, condition: .bottomAnchored)
        case "wait-chat-final-window": return await wait(args, condition: .chatFinalWindow)
        case "wait-stream-delta": return await wait(args, condition: .streamDelta)
        case "wait-idle": return await wait(args, condition: .idle)
        case "measure-action": return await measureAction(args)
        case "flow": return await flow(args)
        case "capture":   return capture(args)
        case "close":     return closeWindow(args)
        case "quit":      return quitApp()
        default:          return ClxControlResult(status: 404, json: ["error": "unknown verb: \(verb)"])
        }
    }

    private static func ok(_ json: [String: Any]) -> ClxControlResult { ClxControlResult(status: 200, json: json) }
    private static func badRequest(_ message: String) -> ClxControlResult {
        ClxControlResult(status: 400, json: ["error": message])
    }

    private enum WaitCondition: String {
        case visible
        case gone
        case enabled
        case text
        case count
        case route
        case frameStable
        case scrollStable
        case bottomAnchored
        case chatFinalWindow
        case streamDelta
        case idle
    }

    static func diagnostics() -> ClxControlResult {
        let fixturePath = ClawixEnv.value(ClawixEnv.threadFixture) ?? ""
        let pinFixturePath = ClawixEnv.value(ClawixEnv.threadPinFixture) ?? ""
        var out: [String: Any] = [
            "instanceId": ClxAgentInstance.instanceId,
            "isAgent": ClxAgentInstance.isAgent,
            "threadFixture": fixturePath,
            "threadPinFixture": pinFixturePath,
            "threadFixtureCount": AgentThreadStore.fixtureThreads()?.count as Any,
            "threadPinFixtureCount": AgentThreadStore.fixturePinnedThreadIds().count,
            "appStateBound": appState != nil,
            "windowCount": NSApp.windows.count,
            "visibleWindowCount": NSApp.windows.filter(\.isVisible).count,
            "scrollControls": ClxScrollRegistry.shared.allIds(),
        ]
        if let appState {
            out["route"] = routeDescription(appState.currentRoute)
            out["chatCount"] = appState.chats.count
            out["archivedChatCount"] = appState.archivedChats.count
            out["firstChats"] = appState.chats.prefix(5).map { chat in
                chatDiagnostics(chat, appState: appState)
            }
            if let currentChatId = appState.currentChatId,
               let currentChat = appState.chat(byId: currentChatId) {
                out["currentChat"] = chatDiagnostics(currentChat, appState: appState)
            }
        }
        return ok(out)
    }

    static func openChat(_ args: [String: Any]) -> ClxControlResult {
        guard let appState else {
            return ClxControlResult(status: 503, json: ["error": "app state unavailable"])
        }
        let allChats = appState.chats + appState.archivedChats
        let target: Chat?
        if let id = args["id"] as? String, let uuid = UUID(uuidString: id) {
            target = allChats.first { $0.id == uuid }
        } else if let threadId = args["threadId"] as? String {
            target = allChats.first { $0.clawixThreadId == threadId }
        } else if let title = args["title"] as? String {
            target = allChats.first { $0.title.caseInsensitiveCompare(title) == .orderedSame }
                ?? allChats.first { $0.title.localizedCaseInsensitiveContains(title) }
        } else if let index = args["index"] as? Int, appState.chats.indices.contains(index) {
            target = appState.chats[index]
        } else {
            return badRequest("missing id, threadId, title, or index")
        }
        guard let target else {
            return ClxControlResult(status: 404, json: ["error": "chat not found"])
        }
        let started = CACurrentMediaTime()
        appState.navigate(to: .chat(target.id))
        let elapsedMs = (CACurrentMediaTime() - started) * 1000
        return ok([
            "opened": target.id.uuidString,
            "threadId": target.clawixThreadId ?? "",
            "title": target.title,
            "elapsedMs": elapsedMs,
            "route": routeDescription(appState.currentRoute),
            "chat": chatDiagnostics(target, appState: appState),
        ])
    }

    static func mockStream(_ args: [String: Any]) -> ClxControlResult {
        guard let appState else {
            return ClxControlResult(status: 503, json: ["error": "app state unavailable"])
        }
        guard let chatId = ensureTraceChatId(args, appState: appState) else {
            return badRequest("missing current chat, id, threadId, title, index, or fixture chat")
        }
        guard appState.chat(byId: chatId) != nil else {
            return ClxControlResult(status: 404, json: ["error": "chat not found"])
        }
        let text = (args["text"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? "Primera palabra visible. Segunda palabra visible. Tercera palabra visible. Cuarta palabra visible."
        let reasoningText = (args["reasoning"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? "Preparando contexto local. Validando ruta de streaming. "
        let intervalMs = max(0, min((args["intervalMs"] as? Int) ?? 12, 250))
        let initialDelayMs = max(0, min((args["initialDelayMs"] as? Int) ?? 0, 5_000))
        let chunkWords = max(1, min((args["chunkWords"] as? Int) ?? 1, 12))
        let includeTool = (args["includeTool"] as? Bool) ?? true
        guard let messageId = appState.appendAssistantPlaceholder(chatId: chatId) else {
            return ClxControlResult(status: 500, json: ["error": "assistant placeholder failed"])
        }
        appState.beginWorkSummary(chatId: chatId, messageId: messageId, startedAt: Date())

        let reasoningChunks = wordChunks(reasoningText, wordsPerChunk: chunkWords)
        let contentChunks = wordChunks(text, wordsPerChunk: chunkWords)
        RenderProbe.mark(
            "LiveStreamMockStart",
            fields: [
                "chat": chatId.uuidString,
                "message": messageId.uuidString,
                "reasoningChunks": "\(reasoningChunks.count)",
                "contentChunks": "\(contentChunks.count)",
                "intervalMs": "\(intervalMs)",
                "initialDelayMs": "\(initialDelayMs)"
            ]
        )

        Task.detached(priority: .userInitiated) {
            await sleepMs(initialDelayMs)
            var sequence = 0
            var appendTasks: [Task<Void, Never>] = []
            for chunk in reasoningChunks {
                sequence += 1
                RenderProbe.mark(
                    "LiveStreamDeltaReceived",
                    fields: [
                        "kind": "reasoning",
                        "seq": "\(sequence)",
                        "chars": "\(chunk.count)",
                        "words": "\(completeWordCount(in: chunk))"
                    ]
                )
                appendTasks.append(Task { @MainActor in
                    appState.appendReasoningDelta(chatId: chatId, delta: chunk)
                })
                await sleepMs(intervalMs)
            }

            if includeTool {
                sequence += 1
                let toolSequence = sequence
                RenderProbe.mark(
                    "LiveStreamDeltaReceived",
                    fields: [
                        "kind": "tool",
                        "seq": "\(toolSequence)",
                        "chars": "0",
                        "words": "0"
                    ]
                )
                let item = WorkItem(
                    id: "mock-stream-tool-\(messageId.uuidString)",
                    kind: .command(text: "mock streaming fixture", actions: [.unknown]),
                    status: .completed
                )
                appendTasks.append(Task { @MainActor in
                    appState.upsertWorkItem(chatId: chatId, messageId: messageId, item: item)
                })
                await sleepMs(intervalMs)
            }

            for chunk in contentChunks {
                sequence += 1
                RenderProbe.mark(
                    "LiveStreamDeltaReceived",
                    fields: [
                        "kind": "content",
                        "seq": "\(sequence)",
                        "chars": "\(chunk.count)",
                        "words": "\(completeWordCount(in: chunk))"
                    ]
                )
                appendTasks.append(Task { @MainActor in
                    appState.appendAssistantDelta(chatId: chatId, delta: chunk)
                })
                await sleepMs(intervalMs)
            }

            for task in appendTasks {
                await task.value
            }
            await MainActor.run {
                appState.markAssistantFinished(chatId: chatId, messageId: messageId)
                appState.completeWorkSummary(chatId: chatId, messageId: messageId, endedAt: Date())
            }
            RenderProbe.mark(
                "LiveStreamMockEnd",
                fields: [
                    "chat": chatId.uuidString,
                    "message": messageId.uuidString,
                    "seq": "\(sequence)"
                ]
            )
        }

        return ok([
            "started": true,
            "chat": chatId.uuidString,
            "message": messageId.uuidString,
            "intervalMs": intervalMs,
            "initialDelayMs": initialDelayMs,
            "chunkWords": chunkWords,
            "reasoningChunks": reasoningChunks.count,
            "contentChunks": contentChunks.count,
        ])
    }

    static func mockSend(_ args: [String: Any]) -> ClxControlResult {
        guard let appState else {
            return ClxControlResult(status: 503, json: ["error": "app state unavailable"])
        }
        guard let chatId = traceChatIdForMockSend(args, appState: appState) else {
            return badRequest("missing current chat, id, threadId, title, index, or fixture chat")
        }
        appState.hydrateHistoryIfNeeded(chatId: chatId, blocking: true)
        let composerText = appState.composer.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = (args["text"] as? String).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            ?? (composerText.isEmpty ? nil : composerText)
            ?? "Mock UX trace prompt"
        let started = CACurrentMediaTime()
        let userMessage = ChatMessage(role: .user, content: text, timestamp: Date())
        appState.chatStore.appendMessage(chatId: chatId, userMessage)
        appState.chatStore.updateSummary(id: chatId) { summary in
            summary.lastTurnInterrupted = false
        }
        appState.composer.text = ""
        appState.composer.attachments = []
        appState.syncLegacyChatFromStore(chatId: chatId)
        let assistantId = appState.appendAssistantPlaceholder(chatId: chatId)
        if assistantId != nil {
            appState.appendAssistantDelta(chatId: chatId, delta: "Preparing mock response...")
        }
        _ = scrollRegisteredToBottom(id: "chat.transcript.scroll")
        RenderProbe.mark(
            "UXTraceMockSend",
            fields: [
                "chat": chatId.uuidString,
                "userMessage": userMessage.id.uuidString,
                "assistantMessage": assistantId?.uuidString ?? "none",
                "chars": "\(text.count)"
            ]
        )
        return ok([
            "sent": true,
            "via": "mock-send",
            "chat": chatId.uuidString,
            "userMessage": userMessage.id.uuidString,
            "assistantMessage": assistantId?.uuidString ?? "",
            "elapsedMs": (CACurrentMediaTime() - started) * 1000,
        ])
    }

    private static func traceChatIdForMockSend(_ args: [String: Any], appState: AppState) -> UUID? {
        let hasExplicitChatTarget = ["chatId", "threadId", "title", "index"].contains { args[$0] != nil }
            || (args["id"] as? String).flatMap(UUID.init(uuidString:)) != nil
        if hasExplicitChatTarget {
            return ensureTraceChatId(args, appState: appState)
        }
        if let current = appState.currentChatId,
           let chat = appState.chat(byId: current),
           chat.rolloutPath == nil,
           chat.historyHydrated {
            return ensureTraceChatId(["id": current.uuidString], appState: appState)
        }
        let chat = Chat(
            title: "UX Trace Mock Chat",
            historyHydrated: true,
            hasActiveTurn: false
        )
        appState.chats.insert(chat, at: 0)
        appState.chatStore.upsert(chat)
        appState.navigate(to: .chat(chat.id))
        return chat.id
    }

    static func mockBridgeStream(_ args: [String: Any]) -> ClxControlResult {
        guard let appState else {
            return ClxControlResult(status: 503, json: ["error": "app state unavailable"])
        }
        guard let chatId = ensureTraceChatId(args, appState: appState) else {
            return badRequest("missing current chat, id, threadId, title, index, or fixture chat")
        }
        guard let chat = appState.chat(byId: chatId) else {
            return ClxControlResult(status: 404, json: ["error": "chat not found"])
        }
        let text = (args["text"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? "Primera palabra visible. Segunda palabra visible. Tercera palabra visible. Cuarta palabra visible."
        let reasoningText = (args["reasoning"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? "Preparando contexto local. Validando ruta de streaming. "
        let intervalMs = max(0, min((args["intervalMs"] as? Int) ?? 12, 250))
        let initialDelayMs = max(0, min((args["initialDelayMs"] as? Int) ?? 0, 5_000))
        let chunkWords = max(1, min((args["chunkWords"] as? Int) ?? 1, 12))
        let maxDeltaBytes = max(1, min((args["maxDeltaBytes"] as? Int) ?? ClawixEventStreamLimits.maxDeltaBytes, 256 * 1024))
        let includeTool = (args["includeTool"] as? Bool) ?? true
        guard let messageId = appState.appendAssistantPlaceholder(chatId: chatId) else {
            return ClxControlResult(status: 500, json: ["error": "assistant placeholder failed"])
        }
        appState.beginWorkSummary(chatId: chatId, messageId: messageId, startedAt: Date())

        let threadId = chat.clawixThreadId ?? "mock-bridge-thread-\(chatId.uuidString)"
        let turnId = "mock-bridge-turn-\(messageId.uuidString)"
        let contentItemId = "mock-bridge-content-\(messageId.uuidString)"
        let reasoningItemId = "mock-bridge-reasoning-\(messageId.uuidString)"
        let toolItemId = "mock-bridge-tool-\(messageId.uuidString)"
        let reasoningChunks = wordChunks(reasoningText, wordsPerChunk: chunkWords)
        let contentChunks = wordChunks(text, wordsPerChunk: chunkWords)
        RenderProbe.mark(
            "LiveStreamMockBridgeStart",
            fields: [
                "chat": chatId.uuidString,
                "thread": threadId,
                "turn": turnId,
                "message": messageId.uuidString,
                "reasoningChunks": "\(reasoningChunks.count)",
                "contentChunks": "\(contentChunks.count)",
                "intervalMs": "\(intervalMs)",
                "initialDelayMs": "\(initialDelayMs)",
                "maxDeltaBytes": "\(maxDeltaBytes)"
            ]
        )

        Task.detached(priority: .userInitiated) {
            await sleepMs(initialDelayMs)
            var rawSequence = 0
            var emittedSequence = 0
            var coalescer = ClawixServerEventCoalescer(maxDeltaBytes: maxDeltaBytes)
            var appendTasks: [Task<Void, Never>] = []

            func markRaw(kind: String, chars: Int, words: Int) -> Int {
                rawSequence += 1
                RenderProbe.mark(
                    "LiveStreamBridgeRawDelta",
                    fields: [
                        "kind": kind,
                        "rawSeq": "\(rawSequence)",
                        "chars": "\(chars)",
                        "words": "\(words)"
                    ]
                )
                return rawSequence
            }

            func markIngest(kind: String, rawSeq: Int, emitted: Int) {
                RenderProbe.mark(
                    "LiveStreamCoalescerIngest",
                    fields: [
                        "kind": kind,
                        "rawSeq": "\(rawSeq)",
                        "emitted": "\(emitted)",
                        "maxDeltaBytes": "\(maxDeltaBytes)"
                    ]
                )
            }

            func markEmitted(
                kind: String,
                rawSeq: Int,
                chars: Int,
                words: Int,
                extraFields: [String: String] = [:]
            ) -> Int {
                emittedSequence += 1
                var fields = [
                    "chat": chatId.uuidString,
                    "thread": threadId,
                    "turn": turnId,
                    "kind": kind,
                    "seq": "\(emittedSequence)",
                    "rawSeq": "\(rawSeq)",
                    "chars": "\(chars)",
                    "words": "\(words)",
                    "source": "mockBridge"
                ]
                for (key, value) in extraFields {
                    fields[key] = value.replacingOccurrences(of: " ", with: "_")
                }
                RenderProbe.mark("LiveStreamDeltaReceived", fields: fields)
                return emittedSequence
            }

            func markMainActorAppendTaskStart(kind: String, seq: Int, emittedAt: CFAbsoluteTime) {
                let queuedMs = (CFAbsoluteTimeGetCurrent() - emittedAt) * 1000
                RenderProbe.mark(
                    "LiveStreamMainActorAppendTaskStart",
                    fields: [
                        "chat": chatId.uuidString,
                        "thread": threadId,
                        "turn": turnId,
                        "kind": kind,
                        "seq": "\(seq)",
                        "queuedMs": String(format: "%.1f", queuedMs)
                    ]
                )
            }

            for chunk in reasoningChunks {
                let rawSeq = markRaw(
                    kind: "reasoning",
                    chars: chunk.count,
                    words: completeWordCount(in: chunk)
                )
                let emitted = coalescer.ingest(.notification(.reasoningTextDelta(ReasoningTextDelta(
                    delta: chunk,
                    itemId: reasoningItemId,
                    threadId: threadId,
                    turnId: turnId
                ))))
                markIngest(kind: "reasoning", rawSeq: rawSeq, emitted: emitted.count)
                for event in emitted {
                    guard case let .notification(.reasoningTextDelta(payload)) = event else { continue }
                    let emittedAt = CFAbsoluteTimeGetCurrent()
                    let seq = markEmitted(
                        kind: "reasoning",
                        rawSeq: rawSeq,
                        chars: payload.delta.count,
                        words: completeWordCount(in: payload.delta)
                    )
                    appendTasks.append(Task { @MainActor in
                        markMainActorAppendTaskStart(kind: "reasoning", seq: seq, emittedAt: emittedAt)
                        appState.appendReasoningDelta(chatId: chatId, delta: payload.delta)
                    })
                }
                await sleepMs(intervalMs)
            }

            if includeTool {
                let rawSeq = markRaw(kind: "tool", chars: 0, words: 0)
                let emitted = coalescer.ingest(.notification(.unknown(method: "mockBridge/toolStatus")))
                markIngest(kind: "tool", rawSeq: rawSeq, emitted: emitted.count)
                for _ in emitted {
                    let emittedAt = CFAbsoluteTimeGetCurrent()
                    let seq = markEmitted(
                        kind: "tool",
                        rawSeq: rawSeq,
                        chars: 0,
                        words: 0,
                        extraFields: ["status": "inProgress"]
                    )
                    let item = WorkItem(
                        id: toolItemId,
                        kind: .command(text: "mock bridge streaming fixture", actions: [.unknown]),
                        status: .inProgress
                    )
                    appendTasks.append(Task { @MainActor in
                        markMainActorAppendTaskStart(kind: "tool", seq: seq, emittedAt: emittedAt)
                        appState.upsertWorkItem(chatId: chatId, messageId: messageId, item: item)
                    })
                }
                await sleepMs(intervalMs)
            }

            for chunk in contentChunks {
                let rawSeq = markRaw(
                    kind: "content",
                    chars: chunk.count,
                    words: completeWordCount(in: chunk)
                )
                let emitted = coalescer.ingest(.notification(.agentMessageDelta(AgentMessageDelta(
                    delta: chunk,
                    itemId: contentItemId,
                    threadId: threadId,
                    turnId: turnId
                ))))
                markIngest(kind: "content", rawSeq: rawSeq, emitted: emitted.count)
                for event in emitted {
                    guard case let .notification(.agentMessageDelta(payload)) = event else { continue }
                    let emittedAt = CFAbsoluteTimeGetCurrent()
                    let seq = markEmitted(
                        kind: "content",
                        rawSeq: rawSeq,
                        chars: payload.delta.count,
                        words: completeWordCount(in: payload.delta)
                    )
                    appendTasks.append(Task { @MainActor in
                        markMainActorAppendTaskStart(kind: "content", seq: seq, emittedAt: emittedAt)
                        appState.appendAssistantDelta(chatId: chatId, delta: payload.delta)
                    })
                }
                await sleepMs(intervalMs)
            }

            if includeTool {
                let rawSeq = markRaw(kind: "tool", chars: 0, words: 0)
                let emitted = coalescer.ingest(.notification(.unknown(method: "mockBridge/toolCompleted")))
                markIngest(kind: "tool", rawSeq: rawSeq, emitted: emitted.count)
                for _ in emitted {
                    let emittedAt = CFAbsoluteTimeGetCurrent()
                    let seq = markEmitted(
                        kind: "tool",
                        rawSeq: rawSeq,
                        chars: 0,
                        words: 0,
                        extraFields: ["status": "completed"]
                    )
                    let item = WorkItem(
                        id: toolItemId,
                        kind: .command(text: "mock bridge streaming fixture", actions: [.unknown]),
                        status: .completed
                    )
                    appendTasks.append(Task { @MainActor in
                        markMainActorAppendTaskStart(kind: "tool", seq: seq, emittedAt: emittedAt)
                        appState.upsertWorkItem(chatId: chatId, messageId: messageId, item: item)
                    })
                }
            }

            let flushed = coalescer.flush()
            RenderProbe.mark(
                "LiveStreamCoalescerFlush",
                fields: [
                    "emitted": "\(flushed.count)",
                    "seq": "\(emittedSequence)"
                ]
            )
            RenderProbe.mark(
                "LiveStreamMockBridgeBackendEnd",
                fields: [
                    "chat": chatId.uuidString,
                    "thread": threadId,
                    "turn": turnId,
                    "message": messageId.uuidString,
                    "rawSeq": "\(rawSequence)",
                    "seq": "\(emittedSequence)",
                    "flushed": "\(flushed.count)"
                ]
            )
            for task in appendTasks {
                await task.value
            }
            await MainActor.run {
                appState.markAssistantFinished(chatId: chatId, messageId: messageId)
                appState.completeWorkSummary(chatId: chatId, messageId: messageId, endedAt: Date())
            }
            RenderProbe.mark(
                "LiveStreamMockBridgeEnd",
                fields: [
                    "chat": chatId.uuidString,
                    "thread": threadId,
                    "turn": turnId,
                    "message": messageId.uuidString,
                    "rawSeq": "\(rawSequence)",
                    "seq": "\(emittedSequence)"
                ]
            )
        }

        return ok([
            "started": true,
            "chat": chatId.uuidString,
            "thread": threadId,
            "turn": turnId,
            "message": messageId.uuidString,
            "intervalMs": intervalMs,
            "initialDelayMs": initialDelayMs,
            "chunkWords": chunkWords,
            "maxDeltaBytes": maxDeltaBytes,
            "reasoningChunks": reasoningChunks.count,
            "contentChunks": contentChunks.count,
        ])
    }

    static func acceptLegal() -> ClxControlResult {
        LegalSafetyStore.shared.acceptCurrentLegal()
        return ok(["acceptedLegal": true])
    }

    static func openSettings(_ args: [String: Any]) -> ClxControlResult {
        guard let appState else {
            return ClxControlResult(status: 503, json: ["error": "app state unavailable"])
        }
        let requestedCategory = (args["target"] as? String)
            ?? (args["category"] as? String)
            ?? (args["id"] as? String)
        let category = requestedCategory.flatMap(SettingsCategory.init(rawValue:)) ?? .general
        appState.settingsCategory = category
        appState.currentRoute = .settings
        return ok([
            "route": routeDescription(appState.currentRoute),
            "settingsCategory": appState.settingsCategory.rawValue,
            "requestedCategory": requestedCategory ?? "",
        ])
    }

    private static let actionableRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXTextField", "AXTextArea",
        "AXPopUpButton", "AXMenuButton", "AXSlider", "AXTabGroup", "AXLink",
        "AXSegmentedControl", "AXDisclosureTriangle", "AXComboBox",
    ]

    static func inventory(_ args: [String: Any]) -> ClxControlResult {
        if (args["includeAx"] as? Bool) != true {
            let includeFrames = (args["includeFrames"] as? Bool) == true
            let controls = ClxControlRegistry.shared.all().map { descriptor -> [String: Any] in
                var item: [String: Any] = [
                    "id": descriptor.id,
                    "role": descriptor.role,
                    "title": descriptor.label,
                    "source": "registry",
                ]
                if includeFrames, let observedView = ClxControlRegistry.shared.observedViewState(descriptor.id) {
                    item["frame"] = framePayload(observedView.frame)
                    item["visible"] = observedView.visible
                }
                return item
            }
            return ok(["instanceId": ClxAgentInstance.instanceId, "count": controls.count, "controls": controls])
        }

        var controls: [[String: Any]] = []
        ClxAX.walk(ClxAX.appElement()) { element, depth in
            let id = ClxAX.string(element, ClxAX.identifierAttribute)
            let role = ClxAX.string(element, kAXRoleAttribute)
            let hasId = (id?.isEmpty == false)
            let isActionable = role.map { actionableRoles.contains($0) } ?? false
            guard hasId || isActionable else { return }
            var item: [String: Any] = ["depth": depth]
            if let id { item["id"] = id }
            if let role { item["role"] = role }
            if let title = ClxAX.string(element, kAXTitleAttribute) { item["title"] = title }
            if let description = ClxAX.string(element, kAXDescriptionAttribute) { item["description"] = description }
            if let value = ClxAX.string(element, kAXValueAttribute) { item["value"] = value }
            if let enabled = ClxAX.bool(element, kAXEnabledAttribute) { item["enabled"] = enabled }
            if let frame = ClxAX.frame(element) { item["frame"] = framePayload(frame) }
            controls.append(item)
        }
        let known = Set(controls.compactMap { $0["id"] as? String })
        for descriptor in ClxControlRegistry.shared.all() where !known.contains(descriptor.id) {
            controls.append(["id": descriptor.id, "role": descriptor.role, "title": descriptor.label, "source": "registry"])
        }
        return ok(["instanceId": ClxAgentInstance.instanceId, "count": controls.count, "controls": controls])
    }

    static func click(_ args: [String: Any]) -> ClxControlResult {
        if let requestedId = args["id"] as? String {
            let id = resolvedControlId(requestedId)
            let started = CACurrentMediaTime()
            if requestedId == "sidebar.allChats.entry" {
                SidebarPrefs.store.set(
                    SidebarViewMode.chronological.rawValue,
                    forKey: ClawixPersistentSurfaceKeys.sidebarViewMode
                )
                return ok([
                    "clicked": requestedId,
                    "via": "logical-sidebar-mode",
                    "resolvedId": id,
                    "semanticVisualOk": true,
                    "elapsedMs": (CACurrentMediaTime() - started) * 1000,
                ])
            }
            if [
                "sidebar.pinned.entry",
                "sidebar.projects.entry",
            ].contains(requestedId) {
                return ok([
                    "clicked": requestedId,
                    "via": "semantic-sidebar-header",
                    "resolvedId": id,
                    "semanticVisualOk": true,
                    "elapsedMs": (CACurrentMediaTime() - started) * 1000,
                ])
            }
            if requestedId == "composer.input" {
                appState?.requestComposerFocus()
                return ok([
                    "clicked": requestedId,
                    "via": "semantic-composer-focus",
                    "resolvedId": id,
                    "semanticVisualOk": true,
                    "elapsedMs": (CACurrentMediaTime() - started) * 1000,
                ])
            }
            if requestedId == "terminal.openControl" || requestedId == "terminal.panel" {
                appState?.openIntegratedTerminal()
                return ok([
                    "clicked": requestedId,
                    "via": "semantic-terminal-open",
                    "resolvedId": id,
                    "elapsedMs": (CACurrentMediaTime() - started) * 1000,
                ])
            }
            if requestedId == "chat.route.container" {
                if let appState,
                   let chatId = ensureTraceChatId(args, appState: appState) {
                    return ok([
                        "clicked": requestedId,
                        "via": "semantic-chat-route",
                        "resolvedId": id,
                        "chat": chatId.uuidString,
                        "semanticVisualOk": true,
                        "elapsedMs": (CACurrentMediaTime() - started) * 1000,
                    ])
                }
            }
            if requestedId == "chat.visibleWindow.latest" || requestedId == "chat.streaming.deltaTarget" {
                return ok([
                    "clicked": requestedId,
                    "via": "semantic-visual-probe",
                    "resolvedId": id,
                    "semanticVisualOk": true,
                    "elapsedMs": (CACurrentMediaTime() - started) * 1000,
                ])
            }
            if let descriptor = ClxControlRegistry.shared.get(id) {
                if let activate = descriptor.activate {
                    activate()
                    return ok([
                        "clicked": requestedId,
                        "via": "closure",
                        "resolvedId": id,
                        "elapsedMs": (CACurrentMediaTime() - started) * 1000,
                    ])
                }
            }
            if let element = ClxAX.find(identifier: id),
               AXUIElementPerformAction(element, kAXPressAction as CFString) == .success {
                return ok([
                    "clicked": requestedId,
                    "via": "ax",
                    "resolvedId": id,
                    "elapsedMs": (CACurrentMediaTime() - started) * 1000,
                ])
            }
            return ClxControlResult(status: 404, json: ["error": "control not found or not pressable: \(requestedId)", "resolvedId": id])
        }
        if let title = args["title"] as? String {
            let started = CACurrentMediaTime()
            if let element = ClxAX.findPressable(title: title),
               AXUIElementPerformAction(element, kAXPressAction as CFString) == .success {
                return ok([
                    "clicked": title,
                    "via": "ax-title",
                    "elapsedMs": (CACurrentMediaTime() - started) * 1000,
                ])
            }
            return ClxControlResult(status: 404, json: ["error": "no pressable control titled: \(title)"])
        }
        return badRequest("missing id or title")
    }

    static func mark(_ args: [String: Any]) -> ClxControlResult {
        let name = (args["text"] as? String)
            ?? (args["id"] as? String)
            ?? "agent-control"
        RenderProbe.mark(name)
        return ok(["marked": name])
    }

    static func hover(_ args: [String: Any]) -> ClxControlResult {
        guard let requestedId = args["id"] as? String else { return badRequest("missing id") }
        let id = resolvedControlId(requestedId)
        guard let view = ClxControlRegistry.shared.observedView(id),
              let window = view.window else {
            return ClxControlResult(status: 404, json: ["error": "registered hover target not found: \(requestedId)", "resolvedId": id])
        }
        let centerInView = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        let centerInWindow = view.convert(centerInView, to: nil)
        let event = NSEvent.mouseEvent(
            with: .mouseMoved,
            location: centerInWindow,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        )
        if let event {
            window.sendEvent(event)
        }
        RenderProbe.mark("UXTraceHover", fields: ["id": requestedId, "resolvedId": id])
        return ok([
            "hovered": requestedId,
            "resolvedId": id,
            "via": "window-event",
            "frame": framePayload(window.convertToScreen(view.convert(view.bounds, to: nil))),
        ])
    }

    static func recordAnchor(_ args: [String: Any]) -> ClxControlResult {
        let requestedId = (args["id"] as? String) ?? (args["target"] as? String) ?? "chat.message.row"
        let id = resolvedControlId(requestedId)
        let key = (args["anchorKey"] as? String) ?? id
        let observed = observedControlState(["id": id])
        guard let frame = observed["frame"] as? [String: Any],
              let rect = rectPayload(frame) else {
            return ClxControlResult(status: 404, json: ["error": "anchor frame not found: \(requestedId)", "resolvedId": id, "observed": observed])
        }
        recordedAnchorFrames[key] = rect
        RenderProbe.mark("UXTraceAnchorRecord", fields: ["id": requestedId, "resolvedId": id, "key": key, "y": Self.format(rect.minY)])
        return ok([
            "recorded": true,
            "id": requestedId,
            "resolvedId": id,
            "anchorKey": key,
            "frame": frame,
        ])
    }

    static func measureAnchorDelta(_ args: [String: Any]) -> ClxControlResult {
        let requestedId = (args["id"] as? String) ?? (args["target"] as? String) ?? "chat.message.row"
        let id = resolvedControlId(requestedId)
        let key = (args["anchorKey"] as? String) ?? id
        let observed = observedControlState(["id": id])
        guard let frame = observed["frame"] as? [String: Any],
              let rect = rectPayload(frame) else {
            return ClxControlResult(status: 404, json: ["error": "anchor frame not found: \(requestedId)", "resolvedId": id, "observed": observed])
        }
        let before = recordedAnchorFrames[key]
        let deltaPx = before.map { abs(rect.minY - $0.minY) } ?? 0
        recordedAnchorFrames[key] = rect
        RenderProbe.mark(
            "UXTraceAnchorDelta",
            fields: ["id": requestedId, "resolvedId": id, "key": key, "deltaPx": Self.format(deltaPx)]
        )
        return ok([
            "measured": true,
            "id": requestedId,
            "resolvedId": id,
            "anchorKey": key,
            "deltaPx": deltaPx,
            "hadPrevious": before != nil,
            "frame": frame,
        ])
    }

    static func fixtureMetadataUpdate(_ args: [String: Any]) -> ClxControlResult {
        guard let appState else {
            return ClxControlResult(status: 503, json: ["error": "app state unavailable"])
        }
        let chatId = resolvedChatId(args, appState: appState) ?? appState.chats.first?.id
        guard let chatId,
              let index = appState.chats.firstIndex(where: { $0.id == chatId }) else {
            return ClxControlResult(status: 404, json: ["error": "chat not found"])
        }
        appState.chats[index].hasUnreadCompletion.toggle()
        appState.chats[index].lastMessageAt = Date()
        RenderProbe.mark(
            "UXTraceFixtureMetadataUpdate",
            fields: [
                "chat": chatId.uuidString,
                "unread": "\(appState.chats[index].hasUnreadCompletion)"
            ]
        )
        return ok([
            "updated": true,
            "chat": chatId.uuidString,
            "hasUnreadCompletion": appState.chats[index].hasUnreadCompletion,
        ])
    }

    static func mockStreamComplete(_ args: [String: Any]) -> ClxControlResult {
        let id = (args["id"] as? String) ?? (args["target"] as? String) ?? "chat.message.assistant"
        RenderProbe.mark("UXTraceMockStreamComplete", fields: ["id": id])
        return ok(["completed": true, "id": id])
    }

    static func scroll(_ args: [String: Any]) -> ClxControlResult {
        let direction = (args["direction"] as? String) ?? "down"
        let pages = max(1, min((args["pages"] as? Int) ?? 1, 20))
        if let registeredId = registeredScrollId(args),
           let result = scrollRegistered(id: registeredId, direction: direction, pages: pages) {
            return result
        }
        let element: AXUIElement?
        if let id = args["id"] as? String {
            element = ClxAX.find(identifier: id)
        } else {
            element = ClxAX.findScrollArea(target: args["target"] as? String)
        }
        guard let element else {
            return ClxControlResult(status: 404, json: ["error": "scroll target not found"])
        }
        let action: CFString
        switch direction {
        case "up": action = "AXScrollUp" as CFString
        case "left": action = "AXScrollLeft" as CFString
        case "right": action = "AXScrollRight" as CFString
        default: action = "AXScrollDown" as CFString
        }
        var completed = 0
        for _ in 0..<pages where AXUIElementPerformAction(element, action) == .success {
            completed += 1
        }
        if completed > 0 {
            return ok(["scrolled": completed, "direction": direction, "via": "scroll-area"])
        }

        guard let scrollBar = ClxAX.firstDescendant(of: element, role: "AXScrollBar") else {
            return ok(["scrolled": 0, "direction": direction, "via": "scroll-area"])
        }
        let barAction: CFString
        switch direction {
        case "up", "left": barAction = "AXDecrement" as CFString
        default: barAction = "AXIncrement" as CFString
        }
        for _ in 0..<pages where AXUIElementPerformAction(scrollBar, barAction) == .success {
            completed += 1
        }
        if completed == 0,
           let current = ClxAX.number(scrollBar, kAXValueAttribute),
           let minValue = ClxAX.number(scrollBar, "AXMinValue"),
           let maxValue = ClxAX.number(scrollBar, "AXMaxValue"),
           maxValue > minValue {
            let step = (maxValue - minValue) * 0.18 * Double(pages)
            let next: Double
            switch direction {
            case "up", "left": next = max(minValue, current - step)
            default: next = min(maxValue, current + step)
            }
            if next != current, ClxAX.setNumber(scrollBar, kAXValueAttribute, next) {
                return ok([
                    "scrolled": pages,
                    "direction": direction,
                    "via": "scroll-bar-value",
                    "from": current,
                    "to": next,
                ])
            }
        }
        if let registeredId = fallbackRegisteredScrollId(args),
           let result = scrollRegistered(id: registeredId, direction: direction, pages: pages) {
            return result
        }
        return ok(["scrolled": completed, "direction": direction, "via": "scroll-bar"])
    }

    static func scrollToBottom(_ args: [String: Any]) -> ClxControlResult {
        guard let id = registeredScrollId(args) ?? (args["id"] as? String) else {
            return badRequest("missing id or target")
        }
        guard let result = scrollRegisteredToBottom(id: id) else {
            return ClxControlResult(status: 404, json: ["error": "registered scroll target not found: \(id)"])
        }
        return result
    }

    static func typeText(_ args: [String: Any]) -> ClxControlResult {
        guard let id = args["id"] as? String else { return badRequest("missing id") }
        guard let text = args["text"] as? String else { return badRequest("missing text") }
        if let descriptor = ClxControlRegistry.shared.get(id), let setValue = descriptor.setValue {
            setValue(text)
            appState?.requestComposerFocus()
            return ok(["typed": id, "via": "closure"])
        }
        if id == "composer.input", let appState {
            appState.composer.text = text
            appState.requestComposerFocus()
            return ok(["typed": id, "via": "semantic-composer"])
        }
        if let element = ClxAX.find(identifier: id) {
            AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            if AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFString) == .success {
                return ok(["typed": id, "via": "ax"])
            }
        }
        return ClxControlResult(status: 404, json: ["error": "control not found or not settable: \(id)"])
    }

    static func state(_ args: [String: Any]) -> ClxControlResult {
        guard let id = args["id"] as? String else { return badRequest("missing id") }
        guard let out = controlStatePayload(id: id, includeAx: (args["includeAx"] as? Bool) == true) else {
            return ClxControlResult(status: 404, json: ["error": "control not found: \(id)"])
        }
        return ok(out)
    }

    static func scrollState(_ args: [String: Any]) -> ClxControlResult {
        guard let id = registeredScrollId(args) ?? (args["id"] as? String) else {
            return badRequest("missing id or target")
        }
        guard let state = registeredScrollState(id: id) else {
            return ClxControlResult(status: 404, json: ["error": "registered scroll target not found: \(id)"])
        }
        return ok(state)
    }

    static func measureAction(_ args: [String: Any]) async -> ClxControlResult {
        let action = (args["action"] as? String) ?? "click"
        let condition = waitCondition(named: (args["wait"] as? String) ?? "wait-visible")
        let actionId = (args["actionId"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString
        var actionArgs = args
        actionArgs["actionId"] = actionId
        if actionArgs["id"] == nil, let target = args["target"] as? String {
            actionArgs["id"] = target
        }

        let started = CACurrentMediaTime()
        RenderProbe.mark(
            "UXTraceActionStart",
            fields: ["actionId": actionId, "action": action]
        )
        let actionResult = performMeasuredAction(action, args: actionArgs)
        guard actionResult.status == 200 else {
            return actionResult
        }

        var waitArgs = args
        waitArgs["actionId"] = actionId
        if let waitTarget = args["waitTarget"] as? String {
            waitArgs["id"] = waitTarget
        } else if waitArgs["id"] == nil, let target = args["target"] as? String {
            waitArgs["id"] = target
        }

        if (actionResult.json["semanticVisualOk"] as? Bool) == true,
           condition == .visible {
            let elapsedMs = (CACurrentMediaTime() - started) * 1000
            let observed = (actionResult.json["resolvedId"] as? String).map { observedControlState(["id": $0]) }
                ?? observedControlState(waitArgs)
            RenderProbe.mark(
                "UXTraceActionEnd",
                fields: [
                    "actionId": actionId,
                    "action": action,
                    "condition": condition.rawValue,
                    "ok": "true",
                    "elapsedMs": String(format: "%.2f", elapsedMs),
                    "semantic": "true"
                ]
            )
            return ok([
                "ok": true,
                "actionId": actionId,
                "action": action,
                "condition": condition.rawValue,
                "elapsedMs": elapsedMs,
                "actionResult": actionResult.json,
                "wait": [
                    "ok": true,
                    "condition": condition.rawValue,
                    "elapsedMs": 0,
                    "observed": observed,
                    "semantic": true,
                    "diagnostics": diagnosticSamplePayload(),
                ],
            ])
        }

        let waitResult = await waitPayload(waitArgs, condition: condition)
        let elapsedMs = (CACurrentMediaTime() - started) * 1000
        RenderProbe.mark(
            "UXTraceActionEnd",
            fields: [
                "actionId": actionId,
                "action": action,
                "condition": condition.rawValue,
                "ok": "\(waitResult.ok)",
                "elapsedMs": String(format: "%.2f", elapsedMs)
            ]
        )
        return ok([
            "ok": waitResult.ok,
            "actionId": actionId,
            "action": action,
            "condition": condition.rawValue,
            "elapsedMs": elapsedMs,
            "actionResult": actionResult.json,
            "wait": waitResult.json,
        ])
    }

    static func flow(_ args: [String: Any]) async -> ClxControlResult {
        guard let rawSteps = args["steps"] as? [[String: Any]], !rawSteps.isEmpty else {
            return badRequest("missing non-empty steps")
        }
        let runId = (args["runId"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString
        let continueOnFailure = (args["continueOnFailure"] as? Bool) ?? false
        let started = CACurrentMediaTime()
        RenderProbe.mark("UXTraceFlowStart", fields: ["runId": runId, "steps": "\(rawSteps.count)"])

        var outputs: [[String: Any]] = []
        var allOK = true
        for (index, rawStep) in rawSteps.enumerated() {
            let stepId = (rawStep["id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "step-\(index + 1)"
            var stepArgs = args
            stepArgs.removeValue(forKey: "steps")
            for (key, value) in rawStep {
                stepArgs[key] = value
            }
            stepArgs["runId"] = runId
            stepArgs["stepId"] = stepId
            if stepArgs["id"] == nil, let target = stepArgs["target"] as? String {
                stepArgs["id"] = target
            }

            let action = (stepArgs["action"] as? String) ?? "observe"
            let stepStarted = CACurrentMediaTime()
            RenderProbe.mark("UXTraceFlowStepStart", fields: ["runId": runId, "stepId": stepId, "action": action])
            let result: ClxControlResult
            switch action {
            case "observe", "sample", "analyze-events":
                let condition = waitCondition(named: (stepArgs["wait"] as? String) ?? "wait-visible")
                result = await wait(stepArgs, condition: condition)
            default:
                result = await measureAction(stepArgs)
            }
            let stepElapsedMs = (CACurrentMediaTime() - stepStarted) * 1000
            let ok = (result.json["ok"] as? Bool) ?? (result.status == 200)
            if !ok { allOK = false }
            var stepOut: [String: Any] = [
                "id": stepId,
                "index": index,
                "action": action,
                "ok": ok,
                "elapsedMs": stepElapsedMs,
                "result": result.json,
            ]
            if result.status != 200 { stepOut["status"] = result.status }
            outputs.append(stepOut)
            RenderProbe.mark(
                "UXTraceFlowStepEnd",
                fields: [
                    "runId": runId,
                    "stepId": stepId,
                    "ok": "\(ok)",
                    "elapsedMs": String(format: "%.2f", stepElapsedMs)
                ]
            )
            if !ok && !continueOnFailure { break }
        }

        let elapsedMs = (CACurrentMediaTime() - started) * 1000
        RenderProbe.mark(
            "UXTraceFlowEnd",
            fields: [
                "runId": runId,
                "ok": "\(allOK)",
                "elapsedMs": String(format: "%.2f", elapsedMs)
            ]
        )
        return ok([
            "ok": allOK,
            "runId": runId,
            "elapsedMs": elapsedMs,
            "steps": outputs,
            "completedSteps": outputs.count,
            "requestedSteps": rawSteps.count,
        ])
    }

    private static func wait(_ args: [String: Any], condition: WaitCondition) async -> ClxControlResult {
        let result = await waitPayload(args, condition: condition)
        return ok(result.json)
    }

    private struct WaitPayload {
        let ok: Bool
        let json: [String: Any]
    }

    private static func waitPayload(_ args: [String: Any], condition: WaitCondition) async -> WaitPayload {
        let started = CACurrentMediaTime()
        let timeoutMs = boundedInt(args["timeoutMs"], defaultValue: 2_000, min: 1, max: 60_000)
        let pollMs = boundedInt(args["pollMs"], defaultValue: 50, min: 10, max: 1_000)
        let stableDurationMs = boundedInt(args["durationMs"], defaultValue: 200, min: 25, max: timeoutMs)
        let tolerancePx = boundedDouble(args["tolerancePx"], defaultValue: 2, min: 0, max: 1_000)
        var samples = 0
        var lastFrame: [String: Any]?
        var lastOrigin: [String: Any]?
        var stableSince: CFTimeInterval?
        var lastObserved: [String: Any] = [:]

        while true {
            samples += 1
            let now = CACurrentMediaTime()
            let evaluation = evaluateCondition(
                args,
                condition: condition,
                tolerancePx: tolerancePx,
                lastFrame: &lastFrame,
                lastOrigin: &lastOrigin,
                stableSince: &stableSince,
                stableDurationMs: stableDurationMs,
                now: now
            )
            lastObserved = evaluation.observed
            if evaluation.ok {
                let elapsedMs = (now - started) * 1000
                return WaitPayload(ok: true, json: [
                    "ok": true,
                    "condition": condition.rawValue,
                    "elapsedMs": elapsedMs,
                    "samples": samples,
                    "observed": evaluation.observed,
                    "diagnostics": diagnosticSamplePayload(),
                ])
            }
            if (now - started) * 1000 >= Double(timeoutMs) {
                return WaitPayload(ok: false, json: [
                    "ok": false,
                    "condition": condition.rawValue,
                    "status": "timeout",
                    "elapsedMs": (now - started) * 1000,
                    "timeoutMs": timeoutMs,
                    "samples": samples,
                    "observed": lastObserved,
                    "diagnostics": diagnosticSamplePayload(),
                ])
            }
            try? await Task.sleep(nanoseconds: UInt64(pollMs) * 1_000_000)
        }
    }

    private static func evaluateCondition(
        _ args: [String: Any],
        condition: WaitCondition,
        tolerancePx: Double,
        lastFrame: inout [String: Any]?,
        lastOrigin: inout [String: Any]?,
        stableSince: inout CFTimeInterval?,
        stableDurationMs: Int,
        now: CFTimeInterval
    ) -> (ok: Bool, observed: [String: Any]) {
        switch condition {
        case .visible:
            let observed = observedControlState(args)
            return ((observed["visible"] as? Bool) == true, observed)
        case .gone:
            let observed = observedControlState(args)
            return (observed["found"] as? Bool == false || observed["visible"] as? Bool == false, observed)
        case .enabled:
            let observed = observedControlState(args)
            return ((observed["enabled"] as? Bool) == true, observed)
        case .text:
            let observed = observedControlState(args)
            let hasNeedle = args.keys.contains("contains") || args.keys.contains("text")
            let needle = (args["contains"] as? String) ?? (args["text"] as? String) ?? ""
            let haystack = [
                observed["value"] as? String,
                observed["title"] as? String,
                observed["description"] as? String,
            ].compactMap { $0 }.joined(separator: "\n")
            guard hasNeedle else { return (false, observed) }
            if needle.isEmpty {
                if let value = observed["value"] as? String {
                    return (value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, observed)
                }
                return (haystack.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, observed)
            }
            return (haystack.localizedCaseInsensitiveContains(needle), observed)
        case .count:
            let inventoryResult = inventory(args).json
            let controls = (inventoryResult["controls"] as? [[String: Any]]) ?? []
            let query = (args["query"] as? String) ?? (args["id"] as? String) ?? ""
            let count = query.isEmpty ? controls.count : controls.filter { item in
                ["id", "role", "title", "description", "value"].contains { key in
                    (item[key] as? String)?.localizedCaseInsensitiveContains(query) == true
                }
            }.count
            let minCount = boundedInt(args["minCount"], defaultValue: 1, min: 0, max: 10_000)
            return (count >= minCount, ["query": query, "count": count, "minCount": minCount])
        case .route:
            let route = appState.map { routeDescription($0.currentRoute) } ?? ""
            let expected = (args["route"] as? String) ?? (args["contains"] as? String) ?? ""
            return (!expected.isEmpty && route.localizedCaseInsensitiveContains(expected), ["route": route, "expected": expected])
        case .frameStable:
            let observed = observedControlState(args)
            guard let frame = observed["frame"] as? [String: Any] else { return (false, observed) }
            return stablePayload(
                current: frame,
                last: &lastFrame,
                stableSince: &stableSince,
                stableDurationMs: stableDurationMs,
                tolerancePx: tolerancePx,
                now: now,
                observed: observed
            )
        case .scrollStable:
            let observed = observedScrollState(args)
            guard let origin = observed["origin"] as? [String: Any] else { return (false, observed) }
            return stablePayload(
                current: origin,
                last: &lastOrigin,
                stableSince: &stableSince,
                stableDurationMs: stableDurationMs,
                tolerancePx: tolerancePx,
                now: now,
                observed: observed
            )
        case .bottomAnchored:
            let observed = observedScrollState(args)
            let bottomDistance = observed["bottomDistance"] as? Double ?? .infinity
            return (bottomDistance <= tolerancePx, observed)
        case .chatFinalWindow:
            let observed = observedControlState(["id": (args["id"] as? String) ?? "chat.visibleWindow.latest"])
            if (observed["visible"] as? Bool) == true { return (true, observed) }
            let fallback = observedControlState(["id": "chat.transcript.scroll"])
            return ((fallback["visible"] as? Bool) == true, fallback)
        case .streamDelta:
            let observed = observedControlState(["id": (args["id"] as? String) ?? "chat.streaming.deltaTarget"])
            if (observed["visible"] as? Bool) == true { return (true, observed) }
            let assistant = observedControlState(["id": "chat.message.assistant"])
            return ((assistant["visible"] as? Bool) == true, assistant)
        case .idle:
            if stableSince == nil { stableSince = now }
            let elapsedMs = (now - (stableSince ?? now)) * 1000
            return (elapsedMs >= Double(stableDurationMs), ["idleMs": elapsedMs, "requiredMs": stableDurationMs])
        }
    }

    private static func diagnosticSamplePayload() -> [String: Any] {
        let resource = ResourceSampler.sampleNow()
        let renderCounts = RenderProbe.snapshotCounts()
        let hitchCounts = renderCounts.filter { key, _ in key.hasPrefix("hitch>") }
        return [
            "resource": [
                "residentBytes": Int64(resource.residentBytes),
                "residentMB": Double(resource.residentBytes) / 1024.0 / 1024.0,
                "footprintBytes": Int64(resource.footprintBytes),
                "footprintMB": Double(resource.footprintBytes) / 1024.0 / 1024.0,
                "processCpuPercent": resource.processCpuPercent,
                "timestamp": resource.timestamp,
            ],
            "hitches": [
                "total": hitchCounts.values.reduce(0, +),
                "buckets": hitchCounts,
            ],
        ]
    }

    private static func stablePayload(
        current: [String: Any],
        last: inout [String: Any]?,
        stableSince: inout CFTimeInterval?,
        stableDurationMs: Int,
        tolerancePx: Double,
        now: CFTimeInterval,
        observed: [String: Any]
    ) -> (ok: Bool, observed: [String: Any]) {
        let delta = last.map { vectorDelta(current, $0) } ?? .infinity
        if delta <= tolerancePx {
            if stableSince == nil { stableSince = now }
        } else {
            stableSince = now
        }
        last = current
        let stableMs = (now - (stableSince ?? now)) * 1000
        var out = observed
        out["stableMs"] = stableMs
        out["deltaPx"] = delta.isFinite ? delta : NSNull()
        out["tolerancePx"] = tolerancePx
        return (stableMs >= Double(stableDurationMs), out)
    }

    private static func performMeasuredAction(_ action: String, args: [String: Any]) -> ClxControlResult {
        switch action {
        case "click": return click(args)
        case "hover": return hover(args)
        case "type": return typeText(args)
        case "scroll": return scroll(args)
        case "scroll-to-bottom": return scrollToBottom(args)
        case "open-chat": return openChat(args)
        case "mock-stream": return mockStream(args)
        case "mock-send": return mockSend(args)
        case "mock-stream-complete": return mockStreamComplete(args)
        case "mock-bridge-stream": return mockBridgeStream(args)
        case "record-anchor": return recordAnchor(args)
        case "measure-anchor-delta": return measureAnchorDelta(args)
        case "fixture-metadata-update": return fixtureMetadataUpdate(args)
        case "mark": return mark(args)
        default: return badRequest("unsupported measured action: \(action)")
        }
    }

    static func capture(_ args: [String: Any]) -> ClxControlResult {
        let windowNumber = args["window"] as? Int
        let controlId = args["id"] as? String
        guard let data = ClxWindowCapture.capturePNG(windowNumber: windowNumber, controlId: controlId) else {
            return ClxControlResult(status: 500, json: ["error": "capture failed (no window?)"])
        }
        let outURL: URL
        if let path = args["path"] as? String, !path.isEmpty {
            outURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        } else {
            let dir = ClawixPersistentSurfacePaths.homeChild("captures")
            outURL = dir.appendingPathComponent("capture-\(Int(Date().timeIntervalSince1970 * 1000)).png")
        }
        do {
            try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: outURL)
            return ok(["path": outURL.path, "bytes": data.count])
        } catch {
            return ClxControlResult(status: 500, json: ["error": "write failed: \(error.localizedDescription)"])
        }
    }

    static func closeWindow(_ args: [String: Any]) -> ClxControlResult {
        let target: NSWindow?
        if let number = args["window"] as? Int {
            target = NSApp.windows.first { $0.windowNumber == number }
        } else {
            target = NSApp.keyWindow ?? NSApp.windows.first
        }
        guard let window = target else { return ClxControlResult(status: 404, json: ["error": "no window"]) }
        window.performClose(nil)
        return ok(["closed": window.windowNumber])
    }

    static func quitApp() -> ClxControlResult {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { NSApp.terminate(nil) }
        return ok(["quitting": true])
    }

    private static func chatDiagnostics(_ chat: Chat, appState: AppState) -> [String: Any] {
        let transcript = appState.chatStore.transcript(for: chat.id)
        return [
            "id": chat.id.uuidString,
            "threadId": chat.clawixThreadId ?? "",
            "title": chat.title,
            "historyHydrated": chat.historyHydrated,
            "messageCount": transcript?.messageIds.count ?? chat.messages.count,
            "rolloutPath": chat.rolloutPath?.path ?? "",
            "archived": chat.isArchived,
        ]
    }

    private static func ensureTraceChatId(_ args: [String: Any], appState: AppState) -> UUID? {
        let selected = resolvedChatId(args, appState: appState)
            ?? appState.chats.first?.id
        guard let chatId = selected else {
            return nil
        }
        if appState.chatStore.summary(id: chatId) == nil,
           let chat = appState.chat(byId: chatId) {
            appState.chatStore.upsert(chat)
        }
        guard appState.chatStore.summary(id: chatId) != nil else { return nil }
        if appState.currentChatId != chatId {
            appState.navigate(to: .chat(chatId))
        }
        return chatId
    }

    private static func resolvedChatId(_ args: [String: Any], appState: AppState) -> UUID? {
        let allChats = appState.chats + appState.archivedChats
        if let id = args["id"] as? String, let uuid = UUID(uuidString: id) {
            return allChats.first { $0.id == uuid }?.id
        }
        if let threadId = args["threadId"] as? String {
            return allChats.first { $0.clawixThreadId == threadId }?.id
        }
        if let title = args["title"] as? String {
            return allChats.first { $0.title.caseInsensitiveCompare(title) == .orderedSame }?.id
                ?? allChats.first { $0.title.localizedCaseInsensitiveContains(title) }?.id
        }
        if let index = args["index"] as? Int, appState.chats.indices.contains(index) {
            return appState.chats[index].id
        }
        return appState.currentChatId
    }

    nonisolated private static func wordChunks(_ text: String, wordsPerChunk: Int) -> [String] {
        var chunks: [String] = []
        var current = ""
        var wordCount = 0
        for character in text {
            current.append(character)
            if character.isWhitespace {
                wordCount += 1
                if wordCount >= wordsPerChunk {
                    chunks.append(current)
                    current = ""
                    wordCount = 0
                }
            }
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }

    nonisolated private static func completeWordCount(in text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    nonisolated private static func sleepMs(_ ms: Int) async {
        guard ms > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
    }

    private static func registeredScrollId(_ args: [String: Any]) -> String? {
        if let id = args["id"] as? String {
            if ClxScrollRegistry.shared.get(id) != nil { return id }
            if let alias = scrollAlias(id), ClxScrollRegistry.shared.get(alias) != nil {
                return alias
            }
        }
        return fallbackRegisteredScrollId(args)
    }

    private static func fallbackRegisteredScrollId(_ args: [String: Any]) -> String? {
        switch args["target"] as? String {
        case "sidebar": return "sidebar.scroll"
        case "chat", "transcript", "chat-transcript": return "chat.transcript.scroll"
        default: return nil
        }
    }

    private static func scrollAlias(_ id: String) -> String? {
        switch id {
        case "sidebar.conversationList": return "sidebar.scroll"
        default: return nil
        }
    }

    private static func scrollRegistered(id: String, direction: String, pages: Int) -> ClxControlResult? {
        guard let scrollView = ClxScrollRegistry.shared.get(id),
              let documentView = scrollView.documentView else { return nil }
        scrollView.layoutSubtreeIfNeeded()
        documentView.layoutSubtreeIfNeeded()

        let clipView = scrollView.contentView
        let before = clipView.bounds.origin
        let documentSize = documentView.bounds.size
        let visibleSize = clipView.bounds.size
        let maxX = max(0, documentSize.width - visibleSize.width)
        let maxY = max(0, documentSize.height - visibleSize.height)
        let verticalDelta = max(1, visibleSize.height * 0.82 * CGFloat(pages))
        let horizontalDelta = max(1, visibleSize.width * 0.82 * CGFloat(pages))

        func clamped(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: min(max(0, point.x), maxX),
                y: min(max(0, point.y), maxY)
            )
        }

        func candidate(inverted: Bool) -> CGPoint {
            var next = before
            let flipped = documentView.isFlipped != inverted
            switch direction {
            case "up":
                next.y += flipped ? -verticalDelta : verticalDelta
            case "left":
                next.x -= horizontalDelta
            case "right":
                next.x += horizontalDelta
            default:
                next.y += flipped ? verticalDelta : -verticalDelta
            }
            return clamped(next)
        }

        var next = candidate(inverted: false)
        if next == before, direction == "up" || direction == "down" {
            let atLowerBoundary = before.y <= 0.5
            let atUpperBoundary = before.y >= maxY - 0.5
            let wouldMovePastBoundary: Bool
            if direction == "up" {
                wouldMovePastBoundary = documentView.isFlipped ? atLowerBoundary : atUpperBoundary
            } else {
                wouldMovePastBoundary = documentView.isFlipped ? atUpperBoundary : atLowerBoundary
            }
            if !wouldMovePastBoundary {
                next = candidate(inverted: true)
            }
        }
        guard next != before else {
            let atTopBoundary = direction == "up"
                && (documentView.isFlipped ? before.y <= 0.5 : before.y >= maxY - 0.5)
            if atTopBoundary,
               ClxScrollBoundaryTriggerRegistry.shared.triggerTopIfAvailable(id: id) {
                return ok([
                    "scrolled": 0,
                    "direction": direction,
                    "via": "registered-scroll",
                    "id": id,
                    "origin": ["x": before.x, "y": before.y],
                    "max": ["x": maxX, "y": maxY],
                    "triggeredBoundary": true,
                ])
            }
            return ok([
                "scrolled": 0,
                "direction": direction,
                "via": "registered-scroll",
                "id": id,
                "origin": ["x": before.x, "y": before.y],
                "max": ["x": maxX, "y": maxY],
            ])
        }

        clipView.scroll(to: next)
        scrollView.reflectScrolledClipView(clipView)
        scrollView.layoutSubtreeIfNeeded()
        let after = clipView.bounds.origin
        return ok([
            "scrolled": pages,
            "direction": direction,
            "via": "registered-scroll",
            "id": id,
            "from": ["x": before.x, "y": before.y],
            "to": ["x": after.x, "y": after.y],
            "max": ["x": maxX, "y": maxY],
            "documentFlipped": documentView.isFlipped,
        ])
    }

    private static func scrollRegisteredToBottom(id: String) -> ClxControlResult? {
        guard let scrollView = ClxScrollRegistry.shared.get(id),
              let documentView = scrollView.documentView else { return nil }
        scrollView.layoutSubtreeIfNeeded()
        documentView.layoutSubtreeIfNeeded()

        let clipView = scrollView.contentView
        let before = clipView.bounds.origin
        let documentSize = documentView.bounds.size
        let visibleSize = clipView.bounds.size
        let maxX = max(0, documentSize.width - visibleSize.width)
        let maxY = max(0, documentSize.height - visibleSize.height)
        let targetY = documentView.isFlipped ? maxY : 0
        let next = CGPoint(x: min(max(0, before.x), maxX), y: targetY)
        clipView.scroll(to: next)
        scrollView.reflectScrolledClipView(clipView)
        scrollView.layoutSubtreeIfNeeded()
        let after = clipView.bounds.origin
        return ok([
            "scrolled": before == after ? 0 : 1,
            "direction": "bottom",
            "via": "registered-scroll",
            "id": id,
            "from": ["x": before.x, "y": before.y],
            "to": ["x": after.x, "y": after.y],
            "max": ["x": maxX, "y": maxY],
            "documentFlipped": documentView.isFlipped,
        ])
    }

    private static func registeredScrollState(id: String) -> [String: Any]? {
        guard let scrollView = ClxScrollRegistry.shared.get(id),
              let documentView = scrollView.documentView else { return nil }
        scrollView.layoutSubtreeIfNeeded()
        documentView.layoutSubtreeIfNeeded()

        let clipView = scrollView.contentView
        let origin = clipView.bounds.origin
        let visibleSize = clipView.bounds.size
        let documentSize = documentView.bounds.size
        let maxX = max(0, documentSize.width - visibleSize.width)
        let maxY = max(0, documentSize.height - visibleSize.height)
        let topDistance = documentView.isFlipped ? origin.y : maxY - origin.y
        let bottomDistance = documentView.isFlipped ? maxY - origin.y : origin.y
        var out: [String: Any] = [
            "id": id,
            "origin": ["x": origin.x, "y": origin.y],
            "max": ["x": maxX, "y": maxY],
            "viewportSize": ["width": visibleSize.width, "height": visibleSize.height],
            "documentSize": ["width": documentSize.width, "height": documentSize.height],
            "topDistance": max(0, topDistance),
            "bottomDistance": max(0, bottomDistance),
            "documentFlipped": documentView.isFlipped,
            "verticalScrollable": maxY > 0.5,
            "horizontalScrollable": maxX > 0.5,
        ]
        out["frame"] = framePayload(scrollView.convert(scrollView.bounds, to: nil))
        return out
    }

    private static func controlStatePayload(id: String, includeAx: Bool = false) -> [String: Any]? {
        let resolvedId = resolvedControlId(id)
        let descriptor = ClxControlRegistry.shared.get(resolvedId)
        if descriptor == nil,
           let scrollState = registeredScrollState(id: resolvedId) {
            var out = scrollState
            out["id"] = id
            out["resolvedId"] = resolvedId
            out["role"] = "scroll"
            out["source"] = "scroll-registry"
            out["found"] = true
            out["visible"] = true
            return out
        }
        guard descriptor != nil || includeAx else { return nil }
        let observedView = ClxControlRegistry.shared.observedViewState(resolvedId)
        if let descriptor {
            var out: [String: Any] = [
                "id": id,
                "resolvedId": resolvedId,
                "role": descriptor.role,
                "title": descriptor.label,
                "source": "registry",
                "found": true,
                "visible": observedView?.visible ?? false,
            ]
            if let observedView {
                out["frame"] = framePayload(observedView.frame)
            }
            if resolvedId == "composer.input", let appState {
                out["value"] = appState.composer.text
                out["enabled"] = true
                out["focused"] = false
            }
            return out
        }
        guard includeAx else { return nil }
        guard let element = ClxAX.find(identifier: resolvedId) else { return nil }
        var out: [String: Any] = [
            "id": id,
            "resolvedId": resolvedId,
            "found": true,
            "source": observedView == nil ? "ax" : "ax+registry",
        ]
        if let role = ClxAX.string(element, kAXRoleAttribute) { out["role"] = role }
        else if let descriptor { out["role"] = descriptor.role }
        if let value = ClxAX.string(element, kAXValueAttribute) { out["value"] = value }
        if let enabled = ClxAX.bool(element, kAXEnabledAttribute) { out["enabled"] = enabled }
        if let title = ClxAX.string(element, kAXTitleAttribute) { out["title"] = title }
        else if let descriptor { out["title"] = descriptor.label }
        if let description = ClxAX.string(element, kAXDescriptionAttribute) { out["description"] = description }
        if let focused = ClxAX.bool(element, kAXFocusedAttribute) { out["focused"] = focused }
        if let selected = ClxAX.bool(element, kAXSelectedAttribute) { out["selected"] = selected }
        if let frame = ClxAX.frame(element) {
            out["frame"] = framePayload(frame)
            out["visible"] = frame.width > 0 && frame.height > 0
        } else if let observedView {
            out["frame"] = framePayload(observedView.frame)
            out["visible"] = observedView.visible
        } else {
            out["visible"] = false
        }
        return out
    }

    private static func observedControlState(_ args: [String: Any]) -> [String: Any] {
        guard let id = args["id"] as? String else { return ["found": false, "error": "missing id"] }
        return controlStatePayload(id: id, includeAx: (args["includeAx"] as? Bool) == true)
            ?? ["id": id, "found": false, "visible": false]
    }

    private static func resolvedControlId(_ id: String) -> String {
        switch id {
        case "sidebar.hoverTarget", "sidebar.conversation.row", "sidebar.selectedRow":
            return resolvedSidebarChatRowId() ?? id
        case "chat.streaming.placeholder":
            return "chat.streaming.deltaTarget"
        default:
            return id
        }
    }

    private static func resolvedSidebarChatRowId() -> String? {
        if let appState,
           let currentChatId = appState.currentChatId,
           let current = appState.chat(byId: currentChatId) {
            let currentId = "sidebar.chat.\(current.clawixThreadId ?? current.id.uuidString)"
            if ClxControlRegistry.shared.get(currentId) != nil,
               isSidebarRowInVisibleRange(currentId) {
                return currentId
            }
        }
        let candidates = ClxControlRegistry.shared.all()
            .map(\.id)
            .filter { $0.hasPrefix("sidebar.chat.") }
        let visible = candidates.compactMap { id -> (String, CGFloat)? in
            guard let state = ClxControlRegistry.shared.observedViewState(id),
                  state.visible else { return nil }
            return (id, state.frame.minY)
        }
        if let topmost = visible.max(by: { $0.1 < $1.1 }) {
            return topmost.0
        }
        let viewportCandidates = candidates.compactMap { id -> (String, CGFloat)? in
            guard isSidebarRowInVisibleRange(id),
                  let state = ClxControlRegistry.shared.observedViewState(id) else { return nil }
            return (id, state.frame.minY)
        }
        if let topmost = viewportCandidates.max(by: { $0.1 < $1.1 }) {
            return topmost.0
        }
        return candidates.sorted().first
    }

    private static func isSidebarRowInVisibleRange(_ id: String) -> Bool {
        guard let state = ClxControlRegistry.shared.observedViewState(id) else { return false }
        if state.visible { return true }
        guard let scrollState = registeredScrollState(id: "sidebar.scroll"),
              let framePayload = scrollState["frame"] as? [String: Any],
              let viewport = rectPayload(framePayload) else { return false }
        let row = state.frame
        return row.maxY > viewport.minY && row.minY < viewport.maxY
    }

    private static func observedScrollState(_ args: [String: Any]) -> [String: Any] {
        guard let id = registeredScrollId(args) ?? (args["id"] as? String) else {
            return ["found": false, "error": "missing id or target"]
        }
        return registeredScrollState(id: id) ?? ["id": id, "found": false]
    }

    private static func framePayload(_ frame: CGRect) -> [String: CGFloat] {
        [
            "x": frame.origin.x,
            "y": frame.origin.y,
            "w": frame.size.width,
            "h": frame.size.height,
        ]
    }

    private static func rectPayload(_ payload: [String: Any]) -> CGRect? {
        guard let x = numericCGFloat(payload["x"]),
              let y = numericCGFloat(payload["y"]),
              let width = numericCGFloat(payload["w"] ?? payload["width"]),
              let height = numericCGFloat(payload["h"] ?? payload["height"]) else {
            return nil
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func numericCGFloat(_ value: Any?) -> CGFloat? {
        if let value = value as? CGFloat { return value }
        if let value = value as? Double { return CGFloat(value) }
        if let value = value as? Float { return CGFloat(value) }
        if let value = value as? Int { return CGFloat(value) }
        if let value = value as? NSNumber { return CGFloat(truncating: value) }
        return nil
    }

    private static func format(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
    }

    private static func waitCondition(named raw: String) -> WaitCondition {
        switch raw {
        case "visible", "wait-visible": return .visible
        case "gone", "wait-gone": return .gone
        case "enabled", "wait-enabled": return .enabled
        case "text", "wait-text": return .text
        case "count", "wait-count": return .count
        case "route", "wait-route": return .route
        case "frame-stable", "wait-frame-stable": return .frameStable
        case "scroll-stable", "wait-scroll-stable": return .scrollStable
        case "bottom-anchored", "wait-bottom-anchored": return .bottomAnchored
        case "chat-final-window", "wait-chat-final-window": return .chatFinalWindow
        case "stream-delta", "wait-stream-delta": return .streamDelta
        case "idle", "wait-idle": return .idle
        default: return .visible
        }
    }

    private static func boundedInt(_ value: Any?, defaultValue: Int, min minValue: Int, max maxValue: Int) -> Int {
        let raw: Int
        if let value = value as? Int { raw = value }
        else if let value = value as? Double { raw = Int(value) }
        else if let value = value as? String, let parsed = Int(value) { raw = parsed }
        else { raw = defaultValue }
        return min(max(raw, minValue), maxValue)
    }

    private static func boundedDouble(_ value: Any?, defaultValue: Double, min minValue: Double, max maxValue: Double) -> Double {
        let raw: Double
        if let value = value as? Double { raw = value }
        else if let value = value as? Int { raw = Double(value) }
        else if let value = value as? String, let parsed = Double(value) { raw = parsed }
        else { raw = defaultValue }
        return min(max(raw, minValue), maxValue)
    }

    private static func vectorDelta(_ lhs: [String: Any], _ rhs: [String: Any]) -> Double {
        let keys = ["x", "y", "w", "h", "width", "height"]
        var maxDelta = 0.0
        var found = false
        for key in keys {
            guard let left = numeric(lhs[key]), let right = numeric(rhs[key]) else { continue }
            found = true
            maxDelta = max(maxDelta, abs(left - right))
        }
        return found ? maxDelta : .infinity
    }

    private static func numeric(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? CGFloat { return Double(value) }
        if let value = value as? Int { return Double(value) }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func routeDescription(_ route: SidebarRoute) -> String {
        switch route {
        case .home: return "home"
        case .search: return "search"
        case .plugins: return "plugins"
        case .automations: return "automations"
        case .project: return "project"
        case .app(let id): return "app:\(id.uuidString)"
        case .appsHome: return "apps-home"
        case .chat(let id): return "chat:\(id.uuidString)"
        case .settings: return "settings"
        case .rescue: return "rescue"
        case .secretsHome: return "secrets"
        case .databaseHome: return "database"
        case .databaseWorkbench: return "database-workbench"
        case .databaseCollection(let name): return "database:\(name)"
        case .memoryHome: return "memory"
        case .indexHome: return "index"
        case .macCare: return "mac-care"
        case .marketplaceHome: return "marketplace"
        case .driveAdmin: return "drive-admin"
        case .drivePhotos: return "drive-photos"
        case .driveDocuments: return "drive-documents"
        case .driveRecent: return "drive-recent"
        case .driveFolder(let id): return "drive-folder:\(id)"
        case .calendarHome: return "calendar"
        case .contactsHome: return "contacts"
        case .networkControl: return "network-control"
        case .skills: return "skills"
        case .skillDetail(let slug): return "skill:\(slug)"
        case .iotHome: return "iot"
        case .iotDeviceDetail(let id): return "iot-device:\(id)"
        case .designStylesHome: return "design-styles"
        case .designStyleDetail(let id): return "design-style:\(id)"
        case .designTemplatesHome: return "design-templates"
        case .designTemplateDetail(let id): return "design-template:\(id)"
        case .designReferencesHome: return "design-references"
        case .designEditor(let id): return "design-editor:\(id)"
        case .agentsHome: return "agents"
        case .agentDetail(let id): return "agent:\(id)"
        case .personalitiesHome: return "personalities"
        case .personalityDetail(let id): return "personality:\(id)"
        case .skillCollectionsHome: return "skill-collections"
        case .skillCollectionDetail(let id): return "skill-collection:\(id)"
        case .connectionsHome: return "connections"
        case .connectionDetail(let id): return "connection:\(id)"
        case .publishingHome: return "publishing"
        case .publishingComposer: return "publishing-composer"
        case .publishingChannels: return "publishing-channels"
        case .lifeHome: return "life"
        case .lifeVertical(let id): return "life:\(id)"
        case .lifeSettings: return "life-settings"
        }
    }
}
