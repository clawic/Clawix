import XCTest
@testable import Clawix

final class TranscriptWindowModelTests: XCTestCase {
    func testLatestWindowBoundsMountedRowsAndTail() {
        let messages = makeMessages(count: 80)

        let model = TranscriptWindowModel.latestWindow(
            messages: messages,
            visibleLimit: 24,
            overscanBefore: 4,
            estimatedRowHeight: 320
        )

        XCTAssertEqual(model.totalCount, 80)
        XCTAssertEqual(model.visibleRange, 52..<80)
        XCTAssertEqual(model.mountedRowCount, 28)
        XCTAssertEqual(model.hiddenBeforeCount, 52)
        XCTAssertEqual(model.hiddenAfterCount, 0)
        XCTAssertTrue(model.windowComplete)
        XCTAssertTrue(model.isTailWindow)
        XCTAssertEqual(model.tailId, messages.last?.id)
    }

    func testOffsetWindowKeepsHiddenAfterCountAndAnchor() {
        let messages = makeMessages(count: 40)
        let anchor = messages[18].id

        let model = TranscriptWindowModel.window(
            messages: messages,
            endOffset: 8,
            visibleLimit: 10,
            overscanBefore: 2,
            overscanAfter: 3,
            anchorId: anchor,
            estimatedRowHeight: 240
        )

        XCTAssertEqual(model.visibleRange, 20..<35)
        XCTAssertEqual(model.hiddenBeforeCount, 20)
        XCTAssertEqual(model.hiddenAfterCount, 5)
        XCTAssertEqual(model.anchorId, anchor)
        XCTAssertFalse(model.isTailWindow)
        XCTAssertTrue(model.rows.allSatisfy { $0.estimatedHeight >= 96 })
    }

    func testNativeAnchorCorrectionClampsAndReportsResidualDelta() {
        let anchorId = UUID()
        let before = TranscriptAnchorSnapshot(
            messageId: anchorId,
            minYInScrollView: 120,
            scrollY: 300,
            documentHeight: 2_000,
            visibleHeight: 600
        )

        let correction = NativeTranscriptAnchorCoordinator.correction(
            before: before,
            afterMinYInScrollView: 450,
            afterDocumentHeight: 2_500
        )

        XCTAssertEqual(correction.messageId, anchorId)
        XCTAssertEqual(correction.deltaY, 330, accuracy: 0.01)
        XCTAssertEqual(correction.targetScrollY, 630, accuracy: 0.01)
        XCTAssertEqual(correction.correctedDeltaY, 0, accuracy: 0.01)
        XCTAssertTrue(correction.isWithinTolerance)
    }

    func testAnchorCorrectionExposesUncorrectableClampResidual() {
        let before = TranscriptAnchorSnapshot(
            messageId: UUID(),
            minYInScrollView: 60,
            scrollY: 10,
            documentHeight: 1_000,
            visibleHeight: 600
        )

        let correction = NativeTranscriptAnchorCoordinator.correction(
            before: before,
            afterMinYInScrollView: -80,
            afterDocumentHeight: 1_000
        )

        XCTAssertEqual(correction.targetScrollY, 0, accuracy: 0.01)
        XCTAssertEqual(correction.correctedDeltaY, -130, accuracy: 0.01)
        XCTAssertFalse(correction.isWithinTolerance)
    }

    private func makeMessages(count: Int) -> [ChatMessage] {
        (0..<count).map { index in
            ChatMessage(
                role: index.isMultiple(of: 2) ? .user : .assistant,
                content: "message \(index)",
                streamingFinished: index != count - 1
            )
        }
    }
}
