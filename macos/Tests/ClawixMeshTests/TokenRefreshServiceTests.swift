import XCTest
@testable import Clawix

@MainActor
final class TokenRefreshServiceTests: XCTestCase {
    func testStopCancelsRunningTokenRefreshTick() async {
        let started = expectation(description: "Token refresh tick started")
        let cancelled = expectation(description: "Token refresh tick cancelled")
        let service = TokenRefreshService(interval: 60) {
            started.fulfill()
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                cancelled.fulfill()
            } catch {
                XCTFail("Unexpected token refresh cancellation error: \(error)")
            }
        }

        service.start()
        await fulfillment(of: [started], timeout: 1)

        service.stop()

        await fulfillment(of: [cancelled], timeout: 1)
    }

    func testDelayedStartDoesNotRunImmediateTick() async {
        let eventuallyStarted = expectation(description: "Token refresh tick eventually starts")
        var tickCount = 0
        let service = TokenRefreshService(interval: 60) {
            tickCount += 1
            eventuallyStarted.fulfill()
        }

        service.start(firstTickDelay: 0.2)

        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(tickCount, 0)
        await fulfillment(of: [eventuallyStarted], timeout: 1)
        service.stop()
    }

    func testStopCancelsPendingDelayedTokenRefreshTick() async {
        var tickCount = 0
        let service = TokenRefreshService(interval: 60) {
            tickCount += 1
        }

        service.start(firstTickDelay: 0.5)
        service.stop()

        try? await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertEqual(tickCount, 0)
    }
}
