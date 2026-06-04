import Combine
import XCTest
@testable import Clawix

/// Contract tests for the session presentation layer (P2). Mirrors
/// `SidebarStoreTests`: the store derives draw-only models, advances `revision`
/// only on named per-chat events, and an UNRELATED `AppState` write never
/// reaches it.
@MainActor
final class SessionPresentationStoreTests: XCTestCase {
    private var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        setenv("CLAWIX_DISABLE_BACKEND", "1", 1)
        setenv("CLAWIX_BRIDGE_DISABLE", "1", 1)
        setenv("CLAWIX_RENDER_PROBE", "1", 1)
        RenderProbe.resetMeasurementWindow()
    }

    override func tearDown() {
        cancellables.removeAll()
        unsetenv("CLAWIX_DISABLE_BACKEND")
        unsetenv("CLAWIX_BRIDGE_DISABLE")
        unsetenv("CLAWIX_RENDER_PROBE")
        super.tearDown()
    }

    private func makeBoundStore(
        chatId: UUID,
        messages: [ChatMessage]
    ) -> (AppState, SessionPresentationStore) {
        let state = AppState()
        state.projects = []
        state.pinnedOrder = []
        state.archivedChats = []
        state.chats = [
            Chat(id: chatId, title: "Session", messages: messages, createdAt: Date())
        ]
        let store = SessionPresentationStore()
        store.bind(chatId: chatId, chatStore: state.chatStore)
        return (state, store)
    }

    // MARK: - Initial derivation

    func testBindDerivesDrawOnlyRowsForExistingMessages() {
        let chatId = UUID()
        let userId = UUID()
        let assistantId = UUID()
        let (_, store) = makeBoundStore(
            chatId: chatId,
            messages: [
                ChatMessage(id: userId, role: .user, content: "hi"),
                ChatMessage(id: assistantId, role: .assistant, content: "hello there")
            ]
        )

        XCTAssertEqual(store.rows.map(\.id), [userId, assistantId])
        XCTAssertEqual(store.window.orderedIds, [userId, assistantId])
        XCTAssertEqual(store.model(for: userId)?.role, .user)
        XCTAssertEqual(store.model(for: assistantId)?.state, .done)
        // The assistant body is pre-segmented in the model, never in a view.
        XCTAssertEqual(
            store.model(for: assistantId)?.contentBlocks,
            [.text(id: "\(assistantId.uuidString):seg:0", body: "hello there")]
        )
    }

    // MARK: - Named event: message added (structure)

    func testAppendingMessageAdvancesRevisionAndAddsOneRow() {
        let chatId = UUID()
        let userId = UUID()
        let (state, store) = makeBoundStore(
            chatId: chatId,
            messages: [ChatMessage(id: userId, role: .user, content: "hi")]
        )
        let revision = store.revision
        XCTAssertEqual(store.rows.count, 1)

        let assistantId = UUID()
        state.chatStore.appendMessage(
            chatId: chatId,
            ChatMessage(id: assistantId, role: .assistant, content: "reply")
        )

        XCTAssertGreaterThan(store.revision, revision)
        XCTAssertEqual(store.rows.map(\.id), [userId, assistantId])
        XCTAssertEqual(store.window.orderedIds, [userId, assistantId])
    }

    // MARK: - Named event: one message changed (content)

    func testContentChangeReDerivesOnlyThatRowAndBumpsRevision() {
        let chatId = UUID()
        let userId = UUID()
        let assistantId = UUID()
        let (state, store) = makeBoundStore(
            chatId: chatId,
            messages: [
                ChatMessage(id: userId, role: .user, content: "hi"),
                ChatMessage(id: assistantId, role: .assistant, content: "", streamingFinished: false)
            ]
        )
        let userModelBefore = store.model(for: userId)
        // While streaming with an empty canonical body, the draw-only model has
        // no content blocks; the live-streaming surface stays in the legacy row.
        XCTAssertEqual(store.model(for: assistantId)?.state, .streaming)
        XCTAssertEqual(store.model(for: assistantId)?.contentBlocks, [])

        // Settle the turn with a final answer: the model's display value now
        // changes (state -> done, content blocks appear), so the named content
        // event re-derives only this row and bumps the revision.
        let revision = store.revision
        state.appendAssistantDelta(chatId: chatId, delta: "streamed answer")
        state.markAssistantFinished(chatId: chatId, messageId: assistantId)

        XCTAssertEqual(store.model(for: userId), userModelBefore, "the sibling row's model must not change")
        XCTAssertEqual(store.model(for: assistantId)?.state, .done)
        XCTAssertEqual(
            store.model(for: assistantId)?.contentBlocks,
            [.text(id: "\(assistantId.uuidString):seg:0", body: "streamed answer")]
        )
        XCTAssertGreaterThan(store.revision, revision)
    }

    // MARK: - Per-row publish bound: 1000 tokens, siblings publish 0

    func testThousandStreamingTokensBoundActiveRowAndLeaveSiblingsUntouched() {
        let chatId = UUID()
        let siblingId = UUID()
        let activeId = UUID()
        let (state, store) = makeBoundStore(
            chatId: chatId,
            messages: [
                ChatMessage(id: siblingId, role: .assistant, content: "older answer"),
                ChatMessage(id: activeId, role: .assistant, content: "", streamingFinished: false)
            ]
        )

        guard let transcript = state.chatStore.transcript(for: chatId),
              let activeStore = transcript.messageStore(id: activeId),
              let siblingStore = transcript.messageStore(id: siblingId)
        else {
            return XCTFail("missing message stores")
        }

        var activePublishes = 0
        var siblingPublishes = 0
        var structurePublishes = 0
        activeStore.$message.dropFirst().sink { _ in activePublishes += 1 }.store(in: &cancellables)
        siblingStore.$message.dropFirst().sink { _ in siblingPublishes += 1 }.store(in: &cancellables)
        transcript.$messageIds.dropFirst().sink { _ in structurePublishes += 1 }.store(in: &cancellables)

        let siblingModelBefore = store.model(for: siblingId)

        for index in 0..<1_000 {
            state.appendAssistantDelta(chatId: chatId, delta: "token-\(index) ")
            state.flushPendingAssistantTextDeltas(chatId: chatId)
        }

        // The active row's store published per applied delta (bounded to the
        // active message), the sibling published zero, and no structure publish
        // fired (no message added/removed during a pure content stream).
        XCTAssertGreaterThan(activePublishes, 0)
        XCTAssertEqual(siblingPublishes, 0, "a delta on the active row must not touch a sibling row's store")
        XCTAssertEqual(structurePublishes, 0, "streaming content must not republish the id structure")
        // The sibling's draw-only model is byte-for-byte unchanged.
        XCTAssertEqual(store.model(for: siblingId), siblingModelBefore)
    }

    // MARK: - Unrelated AppState write does not re-derive the session

    func testUnrelatedAppStateWriteDoesNotAdvanceSessionRevision() {
        let chatId = UUID()
        let (state, store) = makeBoundStore(
            chatId: chatId,
            messages: [ChatMessage(id: UUID(), role: .user, content: "hi")]
        )
        let revision = store.revision
        let rowsBefore = store.rows

        // A synthetic unrelated write to the god-object: image preview, browser
        // loading, search query. None of these belong to this chat's transcript.
        state.imagePreviewURL = URL(string: "file:///tmp/x.png")
        state.searchQuery = "anything"
        state.browserTabsLoading = [UUID()]
        state.archivedLoading = true

        XCTAssertEqual(store.revision, revision, "an unrelated AppState write must not re-derive the session")
        XCTAssertEqual(store.rows, rowsBefore)
    }

    // MARK: - Detach on route teardown

    func testRebindingToNilDetachesAndClears() {
        let chatId = UUID()
        let (state, store) = makeBoundStore(
            chatId: chatId,
            messages: [ChatMessage(id: UUID(), role: .user, content: "hi")]
        )
        XCTAssertFalse(store.rows.isEmpty)

        store.bind(chatId: nil, chatStore: state.chatStore)
        XCTAssertNil(store.chatId)
        XCTAssertTrue(store.rows.isEmpty)
        XCTAssertEqual(store.window, .empty)

        // A delta on the now-detached chat does not resurrect the store.
        let revision = store.revision
        state.appendAssistantDelta(chatId: chatId, delta: "ignored")
        state.flushPendingAssistantTextDeltas(chatId: chatId)
        XCTAssertEqual(store.revision, revision)
        XCTAssertTrue(store.rows.isEmpty)
    }

    // MARK: - Draw-only timestamp / state flag (no Date math in the row)

    func testDisplayModelCarriesPreformattedTimestampAndStateFlag() {
        let chatId = UUID()
        let errorId = UUID()
        let (_, store) = makeBoundStore(
            chatId: chatId,
            messages: [
                ChatMessage(id: errorId, role: .assistant, content: "boom", isError: true)
            ]
        )
        let model = store.model(for: errorId)
        XCTAssertEqual(model?.state, .error)
        XCTAssertFalse(model?.formattedTimestamp.isEmpty ?? true)
    }
}
