import XCTest
import Observation
import ClawixCore
@testable import Clawix

@MainActor
final class BridgeStoreInvalidationTests: XCTestCase {

    func testStreamingLoopDoesNotNotifySummaryObservation() {
        let store = BridgeStore()
        store.applyChatsSnapshot([session("s1")])
        store.applyMessagesSnapshot(
            chatId: "s1",
            messages: [message("m1", content: "")],
            hasMore: false
        )

        var summaryInvalidations = 0
        withObservationTracking {
            _ = store.chats
        } onChange: {
            summaryInvalidations += 1
        }

        for index in 0..<100 {
            store.transcriptStore.applyStreamingBatch([
                PendingStreamUpdate(
                    sessionId: "s1",
                    messageId: "m1",
                    content: "token \(index)",
                    reasoning: "reason \(index)",
                    finished: false
                )
            ])
        }

        XCTAssertEqual(summaryInvalidations, 0)
        XCTAssertEqual(store.chats.map(\.id), ["s1"])
        XCTAssertEqual(store.transcriptStore.messages(for: "s1").first?.content, "token 99")
    }

    func testStreamingLoopDoesNotifyActiveTranscriptObservation() {
        let store = BridgeStore()
        store.applyChatsSnapshot([session("s1")])
        store.applyMessagesSnapshot(
            chatId: "s1",
            messages: [message("m1", content: "")],
            hasMore: false
        )

        var transcriptInvalidations = 0
        withObservationTracking {
            _ = store.transcriptStore.messages(for: "s1")
        } onChange: {
            transcriptInvalidations += 1
        }

        store.transcriptStore.applyStreamingBatch([
            PendingStreamUpdate(
                sessionId: "s1",
                messageId: "m1",
                content: "partial",
                reasoning: "thinking",
                finished: false
            )
        ])

        XCTAssertEqual(transcriptInvalidations, 1)
        XCTAssertEqual(store.transcriptStore.messages(for: "s1").first?.reasoningText, "thinking")
    }

    func testMessagesSnapshotAndPageUpdateOnlyTargetTranscript() {
        let store = BridgeStore()
        store.applyChatsSnapshot([session("s1"), session("s2")])
        store.applyMessagesSnapshot(chatId: "s1", messages: [message("m1", content: "one")], hasMore: true)
        store.applyMessagesSnapshot(chatId: "s2", messages: [message("m2", content: "two")], hasMore: false)

        var otherTranscriptInvalidations = 0
        withObservationTracking {
            _ = store.transcriptStore.messages(for: "s2")
        } onChange: {
            otherTranscriptInvalidations += 1
        }

        store.applyMessagesPage(chatId: "s1", messages: [message("m0", content: "older")], hasMore: false)

        XCTAssertEqual(otherTranscriptInvalidations, 0)
        XCTAssertEqual(store.transcriptStore.messages(for: "s1").map(\.id), ["m0", "m1"])
        XCTAssertEqual(store.transcriptStore.messages(for: "s2").map(\.id), ["m2"])
    }

    func testSessionUpdatedChangesSummaryWithoutTranscriptMutation() {
        let store = BridgeStore()
        store.applyChatsSnapshot([session("s1", title: "Before")])
        store.applyMessagesSnapshot(chatId: "s1", messages: [message("m1", content: "stable")], hasMore: false)

        var transcriptInvalidations = 0
        withObservationTracking {
            _ = store.transcriptStore.messages(for: "s1")
        } onChange: {
            transcriptInvalidations += 1
        }

        store.applyChatUpdate(session("s1", title: "After"))

        XCTAssertEqual(transcriptInvalidations, 0)
        XCTAssertEqual(store.chat("s1")?.title, "After")
        XCTAssertEqual(store.transcriptStore.messages(for: "s1").first?.content, "stable")
    }

    func testStreamingBatchDoesNotReorderSummaries() {
        let store = BridgeStore()
        store.applyChatsSnapshot([
            session("s1", title: "First"),
            session("s2", title: "Second")
        ])
        store.applyMessagesSnapshot(chatId: "s2", messages: [message("m2", content: "")], hasMore: false)

        store.transcriptStore.applyStreamingBatch([
            PendingStreamUpdate(
                sessionId: "s2",
                messageId: "m2",
                content: "streaming",
                reasoning: "",
                finished: false
            )
        ])

        XCTAssertEqual(store.chats.map(\.id), ["s1", "s2"])
        XCTAssertEqual(store.transcriptStore.messages(for: "s2").first?.content, "streaming")
    }

    func testOptimisticNewChatWritesTranscriptAndSummaryTogether() {
        let store = BridgeStore()
        let chatId = store.startNewChat(cwd: "/tmp/project")

        XCTAssertTrue(store.transcriptStore.hasLoadedMessages(chatId))

        let messageId = store.beginPendingTurn(chatId: chatId, text: "hello", attachmentCount: 0)

        XCTAssertNotNil(messageId)
        XCTAssertEqual(store.transcriptStore.messages(for: chatId).first?.content, "hello")
        XCTAssertEqual(store.chat(chatId)?.hasActiveTurn, true)
        XCTAssertEqual(store.chat(chatId)?.cwd, "/tmp/project")
    }

    func testStreamingHandlingDoesNotCallSnapshotPersistenceDirectly() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Clawix/Bridge/BridgeClient.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let streamingCase = try XCTUnwrap(
            source.range(of: #"case \.messageStreaming[\s\S]*?case \.errorEvent"#, options: .regularExpression)
        )

        XCTAssertFalse(source[streamingCase].contains("persistSnapshotDebounced"))
    }

    private func session(_ id: String, title: String? = nil) -> WireSession {
        WireSession(
            id: id,
            title: title ?? id,
            createdAt: Date(),
            isPinned: false,
            isArchived: false,
            hasActiveTurn: false,
            lastMessageAt: nil,
            lastMessagePreview: nil,
            branch: nil,
            cwd: nil,
            lastTurnInterrupted: false,
            threadId: nil
        )
    }

    private func message(_ id: String, content: String) -> WireMessage {
        WireMessage(
            id: id,
            role: .assistant,
            content: content,
            timestamp: Date()
        )
    }
}
