import XCTest
@testable import Clawix

final class BackendMetadataCacheTests: XCTestCase {
    func testRoundTripsBackendMetadataSnapshot() throws {
        let directory = temporaryDirectory()
        let cache = BackendMetadataCache(directory: directory)
        let snapshot = BackendMetadataCache.Snapshot(
            updatedAt: Date(timeIntervalSince1970: 1_777_000_000),
            models: [
                .init(slug: "gpt-5.5", display: "GPT-5.5")
            ],
            rateLimits: RateLimitSnapshot(
                primary: RateLimitWindow(usedPercent: 42, resetsAt: 1_777_001_000, windowDurationMins: 300),
                secondary: nil,
                credits: nil,
                limitId: "codex",
                limitName: "Codex"
            ),
            rateLimitsByLimitId: [:]
        )

        cache.write(snapshot)

        XCTAssertEqual(cache.load(), snapshot)
    }

    func testRejectsStaleSnapshotByMaxAge() {
        let cache = BackendMetadataCache(directory: temporaryDirectory())
        let snapshot = BackendMetadataCache.Snapshot(
            updatedAt: Date(timeIntervalSince1970: 100),
            models: [],
            rateLimits: nil,
            rateLimitsByLimitId: [:]
        )

        XCTAssertFalse(cache.isFresh(snapshot, maxAge: 10, now: Date(timeIntervalSince1970: 111)))
        XCTAssertTrue(cache.isFresh(snapshot, maxAge: 12, now: Date(timeIntervalSince1970: 111)))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("clawix-backend-metadata-cache-\(UUID().uuidString)", isDirectory: true)
    }
}
