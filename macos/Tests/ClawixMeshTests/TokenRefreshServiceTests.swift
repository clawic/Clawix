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
}
