import XCTest
@testable import Clawix

final class StreamingFadeCompactionTests: XCTestCase {
    func testEmptyCheckpointsStayEmpty() {
        XCTAssertEqual(StreamingFade.compact(checkpoints: [], now: Date()), [])
    }

    func testActiveCheckpointsArePreserved() {
        let now = Date()
        let checkpoints = [
            StreamCheckpoint(prefixCount: 5, addedAt: now.addingTimeInterval(-StreamingFade.duration / 2)),
            StreamCheckpoint(prefixCount: 10, addedAt: now.addingTimeInterval(-StreamingFade.duration / 3))
        ]

        XCTAssertEqual(StreamingFade.compact(checkpoints: checkpoints, now: now), checkpoints)
    }

    func testSettledCheckpointsCollapseToSentinel() {
        let now = Date()
        let checkpoints = [
            StreamCheckpoint(prefixCount: 5, addedAt: now.addingTimeInterval(-StreamingFade.duration - 2)),
            StreamCheckpoint(prefixCount: 10, addedAt: now.addingTimeInterval(-StreamingFade.duration - 1))
        ]

        let compacted = StreamingFade.compact(checkpoints: checkpoints, now: now)

        XCTAssertEqual(compacted, [
            StreamCheckpoint(prefixCount: 10, addedAt: .distantPast)
        ])
    }

    func testMixedCheckpointsKeepSentinelPlusActiveTail() {
        let now = Date()
        let active = StreamCheckpoint(
            prefixCount: 15,
            addedAt: now.addingTimeInterval(-StreamingFade.duration / 2)
        )
        let checkpoints = [
            StreamCheckpoint(prefixCount: 5, addedAt: now.addingTimeInterval(-StreamingFade.duration - 2)),
            StreamCheckpoint(prefixCount: 10, addedAt: now.addingTimeInterval(-StreamingFade.duration - 1)),
            active
        ]

        let compacted = StreamingFade.compact(checkpoints: checkpoints, now: now)

        XCTAssertEqual(compacted, [
            StreamCheckpoint(prefixCount: 10, addedAt: .distantPast),
            active
        ])
    }

    func testSettledSentinelUsesLastPrefix() {
        let now = Date()
        let checkpoints = [
            StreamCheckpoint(prefixCount: 4, addedAt: now),
            StreamCheckpoint(prefixCount: 12, addedAt: now.addingTimeInterval(StreamingFade.stagger))
        ]

        XCTAssertEqual(StreamingFade.settled(checkpoints: checkpoints), [
            StreamCheckpoint(prefixCount: 12, addedAt: .distantPast)
        ])
    }

    func testIngestDoesNotScheduleBurstIntoFuture() {
        let now = Date()

        let result = StreamingFade.ingest(
            delta: "one two three ",
            pendingTail: "",
            scheduledLength: 0,
            lastFadeStart: now.addingTimeInterval(10),
            now: now
        )

        XCTAssertEqual(result.newCheckpoints.map(\.prefixCount), [4, 8, 14])
        XCTAssertTrue(result.newCheckpoints.allSatisfy { $0.addedAt == now })
        XCTAssertEqual(result.pendingTail, "")
    }

    func testSettlementDelayForPastCurrentAndFutureCheckpoints() {
        let now = Date()

        XCTAssertEqual(
            StreamingFade.settlementDelay(
                checkpoints: [StreamCheckpoint(prefixCount: 5, addedAt: now.addingTimeInterval(-StreamingFade.duration - 1))],
                now: now
            ),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            StreamingFade.settlementDelay(
                checkpoints: [StreamCheckpoint(prefixCount: 5, addedAt: now.addingTimeInterval(-StreamingFade.duration / 2))],
                now: now
            ),
            StreamingFade.duration / 2,
            accuracy: 0.001
        )
        XCTAssertEqual(
            StreamingFade.settlementDelay(
                checkpoints: [StreamCheckpoint(prefixCount: 5, addedAt: now.addingTimeInterval(0.1))],
                now: now
            ),
            StreamingFade.duration + 0.1,
            accuracy: 0.001
        )
    }
}
