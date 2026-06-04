import Combine
import XCTest
@testable import Clawix

@MainActor
final class ChatStorePublicationTests: XCTestCase {
    private var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        setenv("CLAWIX_DISABLE_BACKEND", "1", 1)
        setenv("CLAWIX_BRIDGE_DISABLE", "1", 1)
    }

    override func tearDown() {
        cancellables.removeAll()
        unsetenv("CLAWIX_DISABLE_BACKEND")
        unsetenv("CLAWIX_BRIDGE_DISABLE")
        super.tearDown()
    }

    func testAssistantDeltaPublishesMessageStoreWithoutPublishingLegacyChats() {
        let state = AppState()
        let chatId = UUID()
        let assistant = ChatMessage(role: .assistant, content: "", streamingFinished: false)
        state.chats = [
            Chat(id: chatId, title: "Streaming", messages: [assistant], createdAt: Date())
        ]

        var chatsPublishes = 0
        var messagePublishes = 0
        state.$chats.dropFirst().sink { _ in
            chatsPublishes += 1
        }.store(in: &cancellables)
        let messageStore = state.chatStore.transcript(for: chatId)?.messageStore(id: assistant.id)
        messageStore!.objectWillChange.sink {
            messagePublishes += 1
        }.store(in: &cancellables)

        state.appendAssistantDelta(chatId: chatId, delta: "hello")
        state.flushPendingAssistantTextDeltas(chatId: chatId)

        XCTAssertEqual(chatsPublishes, 0)
        XCTAssertEqual(messagePublishes, 1)
        XCTAssertEqual(messageStore?.message.content, "hello")
        XCTAssertEqual(state.chats.first?.messages.count, 0)
    }

    func testAssistantDeltasPublishImmediatelyWithoutLegacyChatPublication() {
        let state = AppState()
        let chatId = UUID()
        let assistant = ChatMessage(role: .assistant, content: "", streamingFinished: false)
        state.chats = [
            Chat(id: chatId, title: "Streaming", messages: [assistant], createdAt: Date())
        ]

        var chatsPublishes = 0
        var messagePublishes = 0
        state.$chats.dropFirst().sink { _ in
            chatsPublishes += 1
        }.store(in: &cancellables)
        let messageStore = state.chatStore.transcript(for: chatId)?.messageStore(id: assistant.id)
        messageStore!.objectWillChange.sink {
            messagePublishes += 1
        }.store(in: &cancellables)

        for part in ["hel", "lo ", "world"] {
            state.appendAssistantDelta(chatId: chatId, delta: part)
        }

        XCTAssertEqual(chatsPublishes, 0)
        XCTAssertEqual(messagePublishes, 3)
        XCTAssertEqual(messageStore?.message.content, "hello world")

        state.flushPendingAssistantTextDeltas(chatId: chatId)

        XCTAssertEqual(chatsPublishes, 0)
        XCTAssertEqual(messagePublishes, 3)
        XCTAssertEqual(messageStore?.message.content, "hello world")
    }

    func testDaemonStreamingReplacementDoesNotPublishLegacyChatsUntilFinished() {
        let state = AppState()
        let chatId = UUID()
        let assistant = ChatMessage(role: .assistant, content: "", streamingFinished: false)
        state.chats = [
            Chat(id: chatId, title: "Daemon", messages: [assistant], createdAt: Date())
        ]

        var chatsPublishes = 0
        state.$chats.dropFirst().sink { _ in
            chatsPublishes += 1
        }.store(in: &cancellables)

        state.applyDaemonStreaming(
            chatId: chatId.uuidString,
            messageId: assistant.id.uuidString,
            content: "partial",
            reasoningText: "",
            finished: false
        )

        XCTAssertEqual(chatsPublishes, 0)
        XCTAssertEqual(
            state.chatStore.transcript(for: chatId)?.messageStore(id: assistant.id)?.message.content,
            "partial"
        )
        XCTAssertEqual(state.chats.first?.messages.count, 0)

        state.applyDaemonStreaming(
            chatId: chatId.uuidString,
            messageId: assistant.id.uuidString,
            content: "final",
            reasoningText: "",
            finished: true
        )

        XCTAssertEqual(chatsPublishes, 1)
        XCTAssertEqual(state.chats.first?.messages.count, 0)
    }

    func testReasoningDeltasPublishImmediatelyWithoutLegacyChats() {
        let state = AppState()
        let chatId = UUID()
        let assistant = ChatMessage(role: .assistant, content: "", streamingFinished: false)
        state.chats = [
            Chat(id: chatId, title: "Reasoning", messages: [assistant], createdAt: Date())
        ]

        var chatsPublishes = 0
        var messagePublishes = 0
        state.$chats.dropFirst().sink { _ in
            chatsPublishes += 1
        }.store(in: &cancellables)
        let messageStore = state.chatStore.transcript(for: chatId)?.messageStore(id: assistant.id)
        messageStore!.objectWillChange.sink {
            messagePublishes += 1
        }.store(in: &cancellables)

        state.appendReasoningDelta(chatId: chatId, delta: "think ")
        state.appendReasoningDelta(chatId: chatId, delta: "more ")

        XCTAssertEqual(chatsPublishes, 0)
        XCTAssertEqual(messagePublishes, 2)
        XCTAssertEqual(messageStore?.message.reasoningText, "think more ")
        XCTAssertEqual(reasoningTexts(in: messageStore?.message.timeline ?? []), ["think more "])

        state.flushPendingReasoningDeltas(chatId: chatId)

        XCTAssertEqual(chatsPublishes, 0)
        XCTAssertEqual(messagePublishes, 2)
        XCTAssertEqual(messageStore?.message.reasoningText, "think more ")
        XCTAssertEqual(reasoningTexts(in: messageStore?.message.timeline ?? []), ["think more "])
    }

    func testTextReasoningTextTimelineOrderIsPreserved() {
        let state = AppState()
        let chatId = UUID()
        let assistant = ChatMessage(role: .assistant, content: "", streamingFinished: false)
        state.chats = [
            Chat(id: chatId, title: "Order", messages: [assistant], createdAt: Date())
        ]

        state.appendAssistantDelta(chatId: chatId, delta: "hello ")
        state.appendReasoningDelta(chatId: chatId, delta: "why ")
        state.appendAssistantDelta(chatId: chatId, delta: "answer ")
        state.flushPendingAssistantTextDeltas(chatId: chatId)

        let message = state.chatStore.transcript(for: chatId)?.messageStore(id: assistant.id)?.message
        XCTAssertEqual(timelineKindsAndTexts(in: message?.timeline ?? []), [
            "message:hello ",
            "reasoning:why ",
            "message:answer "
        ])
    }

    func testLongStreamingPublishesOnlyMessageStoreAndNotGlobalSurfaces() {
        let state = AppState()
        let chatId = UUID()
        let assistant = ChatMessage(role: .assistant, content: "", streamingFinished: false)
        state.chats = [
            Chat(id: chatId, title: "Boundary", messages: [assistant], createdAt: Date())
        ]
        let sidebarStore = SidebarStore(appState: state)
        let sidebarRevision = sidebarStore.revision

        var chatsPublishes = 0
        var summariesPublishes = 0
        var searchRoutePublishes = 0
        var messagePublishes = 0
        state.$chats.dropFirst().sink { _ in
            chatsPublishes += 1
        }.store(in: &cancellables)
        state.chatStore.$summaries.dropFirst().sink { _ in
            summariesPublishes += 1
        }.store(in: &cancellables)
        // `searchResultRoutes` now lives on the focused `SearchStore` (P4); the
        // negative lock is the same intent (a stream must not touch search).
        state.searchStore.$searchResultRoutes.dropFirst().sink { _ in
            searchRoutePublishes += 1
        }.store(in: &cancellables)
        let messageStore = state.chatStore.transcript(for: chatId)?.messageStore(id: assistant.id)
        messageStore!.objectWillChange.sink {
            messagePublishes += 1
        }.store(in: &cancellables)

        for index in 0..<1_000 {
            state.appendAssistantDelta(chatId: chatId, delta: "token-\(index) ")
            state.flushPendingAssistantTextDeltas(chatId: chatId)
        }

        XCTAssertEqual(chatsPublishes, 0)
        XCTAssertEqual(summariesPublishes, 0)
        XCTAssertEqual(searchRoutePublishes, 0)
        XCTAssertEqual(sidebarStore.revision, sidebarRevision)
        XCTAssertEqual(messagePublishes, 1_000)
        XCTAssertEqual(state.chats.first?.messages.count, 0)
        XCTAssertEqual(
            messageStore?.message.content,
            (0..<1_000).map { "token-\($0) " }.joined()
        )
    }

    func testTranscriptDeltasUseDedicatedBridgePublisherWithoutChatStoreObjectWillChange() async {
        let state = AppState()
        let chatId = UUID()
        let assistant = ChatMessage(role: .assistant, content: "", streamingFinished: false)
        state.chats = [
            Chat(id: chatId, title: "Bridge", messages: [assistant], createdAt: Date())
        ]

        var chatStorePublishes = 0
        var bridgePublishes = 0
        var lastBridgeContent = ""
        let streamed = expectation(description: "bridge publisher receives coalesced transcript content")

        state.chatStore.objectWillChange.sink {
            chatStorePublishes += 1
        }.store(in: &cancellables)
        state.bridgeChatsPublisher.dropFirst().sink { snapshots in
            bridgePublishes += 1
            lastBridgeContent = snapshots.first?.messages.last?.content ?? ""
            if lastBridgeContent == "hello world" {
                streamed.fulfill()
            }
        }.store(in: &cancellables)

        for part in ["he", "ll", "o ", "wor", "ld"] {
            state.appendAssistantDelta(chatId: chatId, delta: part)
            state.flushPendingAssistantTextDeltas(chatId: chatId)
        }

        await fulfillment(of: [streamed], timeout: 1.0)

        XCTAssertEqual(chatStorePublishes, 0)
        XCTAssertLessThan(bridgePublishes, 5)
        XCTAssertEqual(lastBridgeContent, "hello world")
        XCTAssertEqual(state.chats.first?.messages.count, 0)
    }

    func testTranscriptReverseLookupsFindActionBarMessagesWithoutMaterializingSnapshot() {
        let transcript = ChatTranscriptStore(chatId: UUID(), messages: [
            ChatMessage(role: .user, content: "first"),
            ChatMessage(role: .assistant, content: "old", streamingFinished: true),
            ChatMessage(role: .user, content: "latest"),
            ChatMessage(role: .assistant, content: "streaming", streamingFinished: false),
            ChatMessage(role: .assistant, content: "failed", streamingFinished: true, isError: true)
        ])

        let lastUserId = transcript.lastMessageId { $0.role == .user }
        let lastCompletedAssistantId = transcript.lastMessageId {
            $0.role == .assistant && $0.streamingFinished && !$0.isError
        }
        let lastAssistant = transcript.lastMessage { $0.role == .assistant }

        XCTAssertEqual(lastUserId, transcript.messageStores[2].id)
        XCTAssertEqual(lastCompletedAssistantId, transcript.messageStores[1].id)
        XCTAssertEqual(lastAssistant?.content, "failed")
    }

    func testPendingReasoningFlushesBeforeToolTimelineEntry() {
        let state = AppState()
        let chatId = UUID()
        let assistant = ChatMessage(role: .assistant, content: "", streamingFinished: false)
        state.chats = [
            Chat(id: chatId, title: "Tools", messages: [assistant], createdAt: Date())
        ]
        let item = WorkItem(
            id: "item_1",
            kind: .command(text: "pwd", actions: []),
            status: .inProgress
        )

        state.appendReasoningDelta(chatId: chatId, delta: "thinking ")
        state.upsertWorkItem(chatId: chatId, messageId: assistant.id, item: item)

        let message = state.chatStore.transcript(for: chatId)?.messageStore(id: assistant.id)?.message
        XCTAssertEqual(timelineKindsAndTexts(in: message?.timeline ?? []), [
            "reasoning:thinking ",
            "tools:1"
        ])
    }

    func testCompletedAssistantSettlesTextCheckpointsAfterFadeWindow() {
        let state = AppState()
        let chatId = UUID()
        let assistant = assistantWithCheckpoints(content: "hello world ")
        state.chats = [
            Chat(id: chatId, title: "Complete", messages: [assistant], createdAt: Date())
        ]

        state.markAssistantCompleted(chatId: chatId, finalText: "hello world ")

        let message = state.chatStore.transcript(for: chatId)?.messageStore(id: assistant.id)?.message
        XCTAssertEqual(message?.streamingFinished, true)
        XCTAssertEqual(message?.streamCheckpoints, [
            StreamCheckpoint(prefixCount: 12, addedAt: .distantPast)
        ])
        XCTAssertEqual(state.chats.first?.messages.count, 0)
    }

    func testCanonicalReplacementIsAlreadySettled() {
        let state = AppState()
        let chatId = UUID()
        let assistant = assistantWithCheckpoints(content: "partial ")
        state.chats = [
            Chat(id: chatId, title: "Replacement", messages: [assistant], createdAt: Date())
        ]

        state.markAssistantCompleted(chatId: chatId, finalText: "final answer")

        let message = state.chatStore.transcript(for: chatId)?.messageStore(id: assistant.id)?.message
        XCTAssertEqual(message?.content, "final answer")
        XCTAssertEqual(message?.streamCheckpoints, [
            StreamCheckpoint(prefixCount: "final answer".count, addedAt: .distantPast)
        ])
    }

    func testCompletedAssistantSettlesReasoningBucketsAndDropsOrphans() {
        let state = AppState()
        let chatId = UUID()
        let firstReasoningId = UUID()
        let secondReasoningId = UUID()
        let orphanId = UUID()
        let now = Date()
        let assistant = ChatMessage(
            role: .assistant,
            content: "answer ",
            reasoningText: "first second",
            streamingFinished: false,
            timeline: [
                .reasoning(id: firstReasoningId, text: "first "),
                .tools(id: UUID(), items: []),
                .reasoning(id: secondReasoningId, text: "second ")
            ],
            streamCheckpoints: [],
            reasoningCheckpoints: [
                firstReasoningId: [
                    StreamCheckpoint(prefixCount: 3, addedAt: now.addingTimeInterval(-2)),
                    StreamCheckpoint(prefixCount: 6, addedAt: now.addingTimeInterval(-1))
                ],
                secondReasoningId: [
                    StreamCheckpoint(prefixCount: 4, addedAt: now.addingTimeInterval(-2)),
                    StreamCheckpoint(prefixCount: 7, addedAt: now.addingTimeInterval(-1))
                ],
                orphanId: [
                    StreamCheckpoint(prefixCount: 99, addedAt: now.addingTimeInterval(-1))
                ]
            ],
            reasoningPendingTails: [
                orphanId: "orphan"
            ]
        )
        state.chats = [
            Chat(id: chatId, title: "Reasoning complete", messages: [assistant], createdAt: Date())
        ]

        state.markAssistantCompleted(chatId: chatId, finalText: nil)

        let message = state.chatStore.transcript(for: chatId)?.messageStore(id: assistant.id)?.message
        XCTAssertEqual(message.map { Set($0.reasoningCheckpoints.keys) } ?? Set<UUID>(), [firstReasoningId, secondReasoningId])
        XCTAssertEqual(message?.reasoningCheckpoints[firstReasoningId], [
            StreamCheckpoint(prefixCount: 6, addedAt: .distantPast)
        ])
        XCTAssertEqual(message?.reasoningCheckpoints[secondReasoningId], [
            StreamCheckpoint(prefixCount: 7, addedAt: .distantPast)
        ])
        XCTAssertEqual(message?.reasoningPendingTails ?? [:], [:])
    }

    func testFailedAssistantDoesNotRetainPerWordCheckpoints() {
        let state = AppState()
        let chatId = UUID()
        let assistant = assistantWithCheckpoints(content: "partial ")
        state.chats = [
            Chat(id: chatId, title: "Failed", messages: [assistant], createdAt: Date())
        ]

        state.markAssistantFailed(chatId: chatId, messageId: assistant.id, error: "network failed")

        let message = state.chatStore.transcript(for: chatId)?.messageStore(id: assistant.id)?.message
        XCTAssertEqual(message?.isError, true)
        XCTAssertEqual(message?.streamCheckpoints.count, 1)
        XCTAssertEqual(message?.streamCheckpoints.first?.addedAt, .distantPast)
    }

    func testLocalAssistantFinishDoesNotRetainPerWordCheckpoints() {
        let state = AppState()
        let chatId = UUID()
        let assistant = assistantWithCheckpoints(content: "local answer ")
        state.chats = [
            Chat(id: chatId, title: "Local", messages: [assistant], createdAt: Date())
        ]

        state.markAssistantFinished(chatId: chatId, messageId: assistant.id)

        let message = state.chatStore.transcript(for: chatId)?.messageStore(id: assistant.id)?.message
        XCTAssertEqual(message?.streamingFinished, true)
        XCTAssertEqual(message?.streamCheckpoints, [
            StreamCheckpoint(prefixCount: "local answer ".count, addedAt: .distantPast)
        ])
    }

    func testForkedHistoryDoesNotCopyPerWordCheckpoints() {
        let state = AppState()
        let chatId = UUID()
        let assistant = assistantWithCheckpoints(content: "forked answer ")
        state.chats = [
            Chat(id: chatId, title: "Fork source", messages: [assistant], createdAt: Date())
        ]

        let forkId = state.forkConversation(chatId: chatId)
        let forkedMessage = forkId.flatMap { state.chatStore.transcript(for: $0)?.messages.first }

        XCTAssertNotEqual(forkedMessage?.id, assistant.id)
        XCTAssertEqual(forkedMessage?.streamingFinished, true)
        XCTAssertEqual(forkedMessage?.streamCheckpoints, [
            StreamCheckpoint(prefixCount: "forked answer ".count, addedAt: .distantPast)
        ])
    }

    private func reasoningTexts(in timeline: [AssistantTimelineEntry]) -> [String] {
        timeline.compactMap { entry in
            guard case .reasoning(_, let text) = entry else { return nil }
            return text
        }
    }

    private func timelineKindsAndTexts(in timeline: [AssistantTimelineEntry]) -> [String] {
        timeline.map { entry in
            switch entry {
            case .message(_, let text):
                return "message:\(text)"
            case .reasoning(_, let text):
                return "reasoning:\(text)"
            case .steered:
                return "steered"
            case .divider(_, let text):
                return "divider:\(text)"
            case .tools(_, let items, _):
                return "tools:\(items.count)"
            }
        }
    }

    private func assistantWithCheckpoints(content: String) -> ChatMessage {
        let now = Date()
        return ChatMessage(
            role: .assistant,
            content: content,
            streamingFinished: false,
            timeline: [.message(id: UUID(), text: content)],
            streamCheckpoints: [
                StreamCheckpoint(prefixCount: max(1, content.count / 2), addedAt: now.addingTimeInterval(-2)),
                StreamCheckpoint(prefixCount: content.count, addedAt: now.addingTimeInterval(-1))
            ]
        )
    }
}
