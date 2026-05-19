import AIProviders
import XCTest
@testable import Clawix

@MainActor
final class ProviderConnectionProbeTests: XCTestCase {
    func testNewProbeCancelsStaleProviderConnectionTest() async {
        let slowStarted = expectation(description: "Slow provider probe started")
        let slowCancelled = expectation(description: "Slow provider probe cancelled")
        let fastFinished = expectation(description: "Fast provider probe finished")
        let probe = ProviderConnectionProbe { _, apiKey, _ in
            if apiKey == "slow" {
                slowStarted.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    slowCancelled.fulfill()
                    throw CancellationError()
                }
                return
            }
            fastFinished.fulfill()
        }

        probe.run(providerId: .openai, apiKey: "slow", baseURL: nil)
        await fulfillment(of: [slowStarted], timeout: 1)

        probe.run(providerId: .openai, apiKey: "fast", baseURL: nil)

        await fulfillment(of: [slowCancelled, fastFinished], timeout: 1)
        XCTAssertEqual(probe.state, .ok)
    }

    func testCancelStopsRunningProviderConnectionTest() async {
        let started = expectation(description: "Provider probe started")
        let cancelled = expectation(description: "Provider probe cancelled")
        let probe = ProviderConnectionProbe { _, _, _ in
            started.fulfill()
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                cancelled.fulfill()
                throw CancellationError()
            }
        }

        probe.run(providerId: .openai, apiKey: "slow", baseURL: nil)
        await fulfillment(of: [started], timeout: 1)

        probe.cancel()

        await fulfillment(of: [cancelled], timeout: 1)
        XCTAssertEqual(probe.state, .idle)
    }
}
