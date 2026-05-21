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
        let notImmediate = expectation(description: "Token refresh tick is delayed")
        notImmediate.isInverted = true
        let eventuallyStarted = expectation(description: "Token refresh tick eventually starts")
        let service = TokenRefreshService(interval: 60) {
            notImmediate.fulfill()
            eventuallyStarted.fulfill()
        }

        service.start(firstTickDelay: 0.2)

        await fulfillment(of: [notImmediate], timeout: 0.05)
        await fulfillment(of: [eventuallyStarted], timeout: 1)
        service.stop()
    }

    func testStopCancelsPendingDelayedTokenRefreshTick() async {
        let notStarted = expectation(description: "Delayed token refresh tick was cancelled before start")
        notStarted.isInverted = true
        let service = TokenRefreshService(interval: 60) {
            notStarted.fulfill()
        }

        service.start(firstTickDelay: 0.5)
        service.stop()

        await fulfillment(of: [notStarted], timeout: 0.7)
    }
}
