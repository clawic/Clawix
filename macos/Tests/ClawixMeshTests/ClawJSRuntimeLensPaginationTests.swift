import XCTest
@testable import Clawix

final class ClawJSRuntimeLensPaginationTests: XCTestCase {
    func testRuntimeLensPageSlicesBoundaryCounts() {
        let counts = [0, 1, 24, 25, 48, 49]

        let visibleCounts = counts.map { count in
            clawJSRuntimeLensPage(Array(0..<count), pageIndex: 0, pageSize: 24).rows.count
        }

        XCTAssertEqual(visibleCounts, [0, 1, 24, 24, 24, 24])
    }

    func testRuntimeLensPageReportsNavigationState() {
        let first = clawJSRuntimeLensPage(Array(0..<49), pageIndex: 0, pageSize: 24)
        XCTAssertEqual(first.pageIndex, 0)
        XCTAssertEqual(first.pageCount, 3)
        XCTAssertEqual(first.visibleStart, 1)
        XCTAssertEqual(first.visibleEnd, 24)
        XCTAssertFalse(first.hasPrevious)
        XCTAssertTrue(first.hasNext)

        let last = clawJSRuntimeLensPage(Array(0..<49), pageIndex: 2, pageSize: 24)
        XCTAssertEqual(last.rows, [48])
        XCTAssertEqual(last.visibleStart, 49)
        XCTAssertEqual(last.visibleEnd, 49)
        XCTAssertTrue(last.hasPrevious)
        XCTAssertFalse(last.hasNext)
    }

    func testRuntimeLensPageClampsAfterRowsShrink() {
        let slice = clawJSRuntimeLensPage(Array(0..<3), pageIndex: 8, pageSize: 24)

        XCTAssertEqual(slice.pageIndex, 0)
        XCTAssertEqual(slice.pageCount, 1)
        XCTAssertEqual(slice.rows, [0, 1, 2])
        XCTAssertFalse(slice.hasPrevious)
        XCTAssertFalse(slice.hasNext)
    }

    func testRuntimeLensPageKeysStayIndependent() {
        let domains = ClawJSRuntimeLensPageKey("domains")
        let inventory = ClawJSRuntimeLensPageKey("inventory-sessions")
        let pages: [ClawJSRuntimeLensPageKey: Int] = [
            domains: 1,
            inventory: 2,
        ]

        XCTAssertEqual(pages[domains], 1)
        XCTAssertEqual(pages[inventory], 2)
    }
}
