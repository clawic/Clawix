import XCTest
@testable import ClawixCore

final class MarkdownBlockCacheTests: XCTestCase {
    func testCacheHitDoesNotReproduceValue() {
        let cache = MarkdownBlockCache<String>(countLimit: 4, totalCostLimit: 1_024, maxEntryCost: 1_024)
        var produceCount = 0

        let first = cache.parse("hello") { source in
            produceCount += 1
            return source.uppercased()
        }
        let second = cache.parse("hello") { source in
            produceCount += 1
            return source.lowercased()
        }

        XCTAssertEqual(first, "HELLO")
        XCTAssertEqual(second, "HELLO")
        XCTAssertEqual(produceCount, 1)
    }

    func testOversizedEntryIsNotCached() {
        let cache = MarkdownBlockCache<String>(countLimit: 4, totalCostLimit: 32, maxEntryCost: 8)
        var produceCount = 0

        _ = cache.parse("123456789") { source in
            produceCount += 1
            return source
        }
        _ = cache.parse("123456789") { source in
            produceCount += 1
            return source
        }

        XCTAssertEqual(produceCount, 2)
        XCTAssertNil(cache.get(for: "123456789"))
    }

    func testTotalCostLimitEvictsOldestEntries() {
        let cache = MarkdownBlockCache<String>(countLimit: 4, totalCostLimit: 20, maxEntryCost: 20)

        cache.set("first", for: "first-source", cost: 12)
        cache.set("second", for: "second-source", cost: 12)

        XCTAssertNil(cache.get(for: "first-source"))
        XCTAssertEqual(cache.get(for: "second-source"), "second")
    }

    func testLegacyParseAPIStillCaches() {
        let cache = MarkdownBlockCache<Int>()
        var produceCount = 0

        let first = cache.parse("same") { _ in
            produceCount += 1
            return 1
        }
        let second = cache.parse("same") { _ in
            produceCount += 1
            return 2
        }

        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 1)
        XCTAssertEqual(produceCount, 1)
    }
}
