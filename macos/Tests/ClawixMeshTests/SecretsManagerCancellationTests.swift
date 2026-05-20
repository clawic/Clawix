import Foundation
import XCTest
@testable import Clawix

@MainActor
final class SecretsManagerCancellationTests: XCTestCase {
    func testStartingSecondLoadCancelsStaleSecretsState() async {
        let staleStarted = expectation(description: "Stale Secrets load started")
        let staleCancelled = expectation(description: "Stale Secrets load cancelled")
        let staleReturned = expectation(description: "Stale Secrets load returned")
        staleReturned.isInverted = true
        let freshReturned = expectation(description: "Fresh Secrets load returned")
        var calls = 0
        let manager = makeManager {
            calls += 1
            if calls == 1 {
                staleStarted.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    staleCancelled.fulfill()
                    throw CancellationError()
                }
                staleReturned.fulfill()
                return Self.state(initialized: false, unlocked: false)
            }
            freshReturned.fulfill()
            return Self.state(initialized: true, unlocked: false)
        }

        let first = Task { await manager.load() }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task { await manager.load() }

        await fulfillment(of: [freshReturned, staleCancelled], timeout: 1)
        await fulfillment(of: [staleReturned], timeout: 0.1)
        await first.value
        await second.value
        XCTAssertEqual(manager.state, .locked)
        XCTAssertNil(manager.lastError)
    }

    func testCancelSurfaceWorkCancelsSecretsLoadAndAllowsRetry() async {
        let loadStarted = expectation(description: "Secrets load started")
        let loadReturned = expectation(description: "Secrets load returned after teardown")
        loadReturned.isInverted = true
        let loadCancelled = expectation(description: "Secrets load cancelled after teardown")
        var calls = 0
        let manager = makeManager {
            calls += 1
            if calls == 1 {
                loadStarted.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    loadCancelled.fulfill()
                    throw CancellationError()
                }
                loadReturned.fulfill()
                throw URLError(.cannotConnectToHost)
            }
            return Self.state(initialized: true, unlocked: false)
        }

        let task = Task { await manager.load() }
        await fulfillment(of: [loadStarted], timeout: 1)

        manager.cancelSurfaceWork()

        await fulfillment(of: [loadCancelled], timeout: 1)
        await fulfillment(of: [loadReturned], timeout: 0.1)
        await task.value
        XCTAssertNil(manager.lastError)
        if case .openFailed(let message) = manager.state {
            XCTFail("Cancelled load published openFailed: \(message)")
        }

        await manager.load()
        XCTAssertEqual(manager.state, .locked)
    }

    private static func state(initialized: Bool, unlocked: Bool) -> ClawJSSecretsClient.SecretsServiceState {
        ClawJSSecretsClient.SecretsServiceState(
            tenantId: ClawJSSecretsClient.defaultTenantId,
            initialized: initialized,
            unlocked: unlocked,
            autoLockMinutes: 5
        )
    }

    private func makeManager(
        serviceStateOperation: @escaping SecretsManager.ServiceStateOperation
    ) -> SecretsManager {
        SecretsManager(
            client: ClawJSSecretsClient(baseURL: URL(string: "http://127.0.0.1:1")!),
            autoLoad: false,
            serviceStateOperation: serviceStateOperation
        )
    }
}
