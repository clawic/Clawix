import XCTest
@testable import Clawix

final class WorkSummaryDurationFormattingTests: XCTestCase {
    func testWorkedForUsesHourComponentAfterSixtyMinutes() {
        XCTAssertEqual(L10n.workedFor(seconds: 4_271), "Worked for 1h 11m 11s")
    }

    func testWorkedForKeepsCompactMinuteAndSecondLabelsBelowHour() {
        XCTAssertEqual(L10n.workedFor(seconds: 131), "Worked for 2m 11s")
        XCTAssertEqual(L10n.workedFor(seconds: 11), "Worked for 11s")
    }
}
