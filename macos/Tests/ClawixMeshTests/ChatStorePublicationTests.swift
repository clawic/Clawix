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
        XCTAssertEqual(state.chats.first?.messages.first?.content, "")
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
        XCTAssertEqual(state.chats.first?.messages.first?.content, "")

        state.applyDaemonStreaming(
            chatId: chatId.uuidString,
            messageId: assistant.id.uuidString,
            content: "final",
            reasoningText: "",
            finished: true
        )

        XCTAssertEqual(chatsPublishes, 1)
        XCTAssertEqual(state.chats.first?.messages.first?.content, "final")
    }

    func testReasoningDeltasCoalesceWithoutPublishingLegacyChats() {
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
        XCTAssertEqual(messagePublishes, 0)

        state.flushPendingReasoningDeltas(chatId: chatId)

        XCTAssertEqual(chatsPublishes, 0)
        XCTAssertEqual(messagePublishes, 1)
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
            case .tools(_, let items):
                return "tools:\(items.count)"
            }
        }
    }
}
