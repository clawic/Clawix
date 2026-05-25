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

    static func bind(appState: AppState) {
        guard ClxAgentInstance.isAgent else { return }
        self.appState = appState
    }

    static func handle(verb: String, args: [String: Any]) -> ClxControlResult {
        switch verb {
        case "ping":      return ok(["ok": true, "instanceId": ClxAgentInstance.instanceId])
        case "diagnostics": return diagnostics()
        case "accept-legal": return acceptLegal()
        case "open-chat": return openChat(args)
        case "mock-stream": return mockStream(args)
        case "mock-bridge-stream": return mockBridgeStream(args)
        case "inventory": return inventory()
        case "click":     return click(args)
        case "mark":      return mark(args)
        case "scroll":    return scroll(args)
        case "type":      return typeText(args)
        case "state":     return state(args)
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

    static func diagnostics() -> ClxControlResult {
        let fixturePath = ClawixEnv.value(ClawixEnv.threadFixture) ?? ""
        var out: [String: Any] = [
            "instanceId": ClxAgentInstance.instanceId,
            "isAgent": ClxAgentInstance.isAgent,
            "threadFixture": fixturePath,
            "threadFixtureCount": AgentThreadStore.fixtureThreads()?.count as Any,
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
        guard let chatId = resolvedChatId(args, appState: appState) else {
            return badRequest("missing current chat, id, threadId, title, or index")
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

    static func mockBridgeStream(_ args: [String: Any]) -> ClxControlResult {
        guard let appState else {
            return ClxControlResult(status: 503, json: ["error": "app state unavailable"])
        }
        guard let chatId = resolvedChatId(args, appState: appState) else {
            return badRequest("missing current chat, id, threadId, title, or index")
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

    private static let actionableRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXTextField", "AXTextArea",
        "AXPopUpButton", "AXMenuButton", "AXSlider", "AXTabGroup", "AXLink",
        "AXSegmentedControl", "AXDisclosureTriangle", "AXComboBox",
    ]

    static func inventory() -> ClxControlResult {
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
            if let frame = ClxAX.frame(element) {
                item["frame"] = ["x": frame.origin.x, "y": frame.origin.y, "w": frame.size.width, "h": frame.size.height]
            }
            controls.append(item)
        }
        let known = Set(controls.compactMap { $0["id"] as? String })
        for descriptor in ClxControlRegistry.shared.all() where !known.contains(descriptor.id) {
            controls.append(["id": descriptor.id, "role": descriptor.role, "title": descriptor.label, "source": "registry"])
        }
        return ok(["instanceId": ClxAgentInstance.instanceId, "count": controls.count, "controls": controls])
    }

    static func click(_ args: [String: Any]) -> ClxControlResult {
        if let id = args["id"] as? String {
            let started = CACurrentMediaTime()
            if let descriptor = ClxControlRegistry.shared.get(id), let activate = descriptor.activate {
                activate()
                return ok([
                    "clicked": id,
                    "via": "closure",
                    "elapsedMs": (CACurrentMediaTime() - started) * 1000,
                ])
            }
            if let element = ClxAX.find(identifier: id),
               AXUIElementPerformAction(element, kAXPressAction as CFString) == .success {
                return ok([
                    "clicked": id,
                    "via": "ax",
                    "elapsedMs": (CACurrentMediaTime() - started) * 1000,
                ])
            }
            return ClxControlResult(status: 404, json: ["error": "control not found or not pressable: \(id)"])
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

    static func typeText(_ args: [String: Any]) -> ClxControlResult {
        guard let id = args["id"] as? String else { return badRequest("missing id") }
        guard let text = args["text"] as? String else { return badRequest("missing text") }
        if let element = ClxAX.find(identifier: id) {
            AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            if AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFString) == .success {
                return ok(["typed": id, "via": "ax"])
            }
        }
        if let descriptor = ClxControlRegistry.shared.get(id), let setValue = descriptor.setValue {
            setValue(text)
            return ok(["typed": id, "via": "closure"])
        }
        return ClxControlResult(status: 404, json: ["error": "control not found or not settable: \(id)"])
    }

    static func state(_ args: [String: Any]) -> ClxControlResult {
        guard let id = args["id"] as? String else { return badRequest("missing id") }
        guard let element = ClxAX.find(identifier: id) else {
            if ClxControlRegistry.shared.get(id) != nil { return ok(["id": id, "source": "registry"]) }
            return ClxControlResult(status: 404, json: ["error": "control not found: \(id)"])
        }
        var out: [String: Any] = ["id": id]
        if let role = ClxAX.string(element, kAXRoleAttribute) { out["role"] = role }
        if let value = ClxAX.string(element, kAXValueAttribute) { out["value"] = value }
        if let enabled = ClxAX.bool(element, kAXEnabledAttribute) { out["enabled"] = enabled }
        if let title = ClxAX.string(element, kAXTitleAttribute) { out["title"] = title }
        return ok(out)
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
        if let id = args["id"] as? String, ClxScrollRegistry.shared.get(id) != nil {
            return id
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
