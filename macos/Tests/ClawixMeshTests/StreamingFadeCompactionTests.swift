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
}
