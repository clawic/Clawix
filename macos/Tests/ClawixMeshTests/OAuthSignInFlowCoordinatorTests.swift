import AIProviders
import XCTest
@testable import Clawix

@MainActor
final class OAuthSignInFlowCoordinatorTests: XCTestCase {
    func testCancelStopsOAuthSignInBeforeCompletingSheet() async {
        let started = expectation(description: "OAuth sign-in started")
        let cancelled = expectation(description: "OAuth sign-in cancelled")
        var cancelOperationCount = 0
        var didComplete = false
        let coordinator = OAuthSignInFlowCoordinator(operations: .init(
            signIn: { _ in
                started.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    cancelled.fulfill()
                    throw CancellationError()
                }
            },
            cancel: {
                cancelOperationCount += 1
            }
        ))

        coordinator.start(flavor: .anthropicClaudeAi) {
            didComplete = true
        }
        await fulfillment(of: [started], timeout: 1)

        coordinator.cancel()

        await fulfillment(of: [cancelled], timeout: 1)
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertGreaterThan(cancelOperationCount, 0)
        XCTAssertFalse(didComplete)
    }
}
