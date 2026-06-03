import XCTest
@testable import Clawix

final class StreamingRenderSchedulerTests: XCTestCase {
    func testCoalescesDeltasForSameVisibleRow() {
        let chatId = UUID()
        let messageId = UUID()
        var scheduler = StreamingRenderScheduler(frameBudgetMs: 16, maxBacklogMs: 48)

        scheduler.receive(.init(chatId: chatId, messageId: messageId, kind: .content, text: "one ", receivedAtMs: 0))
        scheduler.receive(.init(chatId: chatId, messageId: messageId, kind: .content, text: "two ", receivedAtMs: 6))
        scheduler.receive(.init(chatId: chatId, messageId: messageId, kind: .content, text: "three", receivedAtMs: 12))

        XCTAssertEqual(scheduler.pendingDeltaCount, 3)
        XCTAssertFalse(scheduler.shouldFlush(nowMs: 12))

        let batches = scheduler.flush(nowMs: 18)

        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches[0].chatId, chatId)
        XCTAssertEqual(batches[0].messageId, messageId)
        XCTAssertEqual(batches[0].kind, .content)
        XCTAssertEqual(batches[0].text, "one two three")
        XCTAssertEqual(batches[0].deltaCount, 3)
        XCTAssertEqual(batches[0].backlogMs, 18, accuracy: 0.01)
        XCTAssertFalse(batches[0].wasBackpressured)
        XCTAssertEqual(scheduler.pendingDeltaCount, 0)
    }

    func testKeepsReasoningAndContentBatchesSeparate() {
        let chatId = UUID()
        let messageId = UUID()
        var scheduler = StreamingRenderScheduler(frameBudgetMs: 16, maxBacklogMs: 48)

        scheduler.receive(.init(chatId: chatId, messageId: messageId, kind: .reasoning, text: "thinking ", receivedAtMs: 0))
        scheduler.receive(.init(chatId: chatId, messageId: messageId, kind: .content, text: "answer", receivedAtMs: 1))

        let batches = scheduler.flush(nowMs: 20)

        XCTAssertEqual(batches.count, 2)
        XCTAssertEqual(Set(batches.map(\.kind)), [.reasoning, .content])
    }

    func testMarksBackpressureWhenBacklogExceedsBudget() {
        let chatId = UUID()
        let messageId = UUID()
        var scheduler = StreamingRenderScheduler(frameBudgetMs: 16, maxBacklogMs: 32)

        scheduler.receive(.init(chatId: chatId, messageId: messageId, kind: .content, text: "late", receivedAtMs: 0))

        let batches = scheduler.flush(nowMs: 40)

        XCTAssertEqual(batches.count, 1)
        XCTAssertTrue(batches[0].wasBackpressured)
        XCTAssertEqual(batches[0].backlogMs, 40, accuracy: 0.01)
    }

    func testForceFlushAppliesBeforeCompletionEvenWithinFrameBudget() {
        let chatId = UUID()
        let messageId = UUID()
        var scheduler = StreamingRenderScheduler(frameBudgetMs: 16, maxBacklogMs: 48)

        scheduler.receive(.init(chatId: chatId, messageId: messageId, kind: .content, text: "tail", receivedAtMs: 100))

        XCTAssertTrue(scheduler.flush(nowMs: 104).isEmpty)
        XCTAssertEqual(scheduler.flush(nowMs: 104, force: true).map(\.text), ["tail"])
    }
}
