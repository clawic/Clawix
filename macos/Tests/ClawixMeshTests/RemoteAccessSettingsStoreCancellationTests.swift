import XCTest
import ClawixEngine
@testable import Clawix

@MainActor
final class RemoteAccessSettingsStoreCancellationTests: XCTestCase {
    func testStartingConsumeCancelsStaleMagicLinkRequest() async throws {
        let requestStarted = expectation(description: "Magic link request started")
        let requestCancelled = expectation(description: "Magic link request cancelled")
        let consumeStarted = expectation(description: "Token consume started")
        var savedDeviceId: String?
        let store = RemoteAccessSettingsStore(
            requestMagicLinkOperation: { _, _, _, _ in
                requestStarted.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    requestCancelled.fulfill()
                    throw CancellationError()
                }
            },
            consumeMagicLinkOperation: { _, _, _, _, _, _ in
                consumeStarted.fulfill()
                return try Self.session(deviceId: "fresh-device")
            }
        )

        let first = store.sendMagicLink(
            coordinatorUrlString: "https://relay.example.com",
            email: "person@example.com",
            deviceLabel: "Mac"
        )
        await fulfillment(of: [requestStarted], timeout: 1)

        let second = store.consumeToken(
            coordinatorUrlString: "https://relay.example.com",
            token: "mlk_fresh",
            deviceLabel: "Mac",
            platformVersion: "macOS Test",
            irohNodeID: "node"
        ) { session in
            savedDeviceId = session.deviceId
        }

        await fulfillment(of: [requestCancelled, consumeStarted], timeout: 1)
        await first?.value
        await second?.value

        XCTAssertEqual(savedDeviceId, "fresh-device")
        XCTAssertEqual(store.status, .info("This Mac is registered as fresh-device. Refresh token stashed locally."))
        XCTAssertFalse(store.inFlight)
    }

    func testCancelInFlightSuppressesTokenConsumeSession() async throws {
        let consumeStarted = expectation(description: "Token consume started")
        let consumeCancelled = expectation(description: "Token consume cancelled")
        var didSaveSession = false
        let store = RemoteAccessSettingsStore(
            consumeMagicLinkOperation: { _, _, _, _, _, _ in
                consumeStarted.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    consumeCancelled.fulfill()
                    throw CancellationError()
                }
                return try Self.session(deviceId: "stale-device")
            }
        )

        let task = store.consumeToken(
            coordinatorUrlString: "https://relay.example.com",
            token: "mlk_stale",
            deviceLabel: "Mac",
            platformVersion: "macOS Test",
            irohNodeID: "node"
        ) { _ in
            didSaveSession = true
        }
        await fulfillment(of: [consumeStarted], timeout: 1)

        store.cancelInFlight()

        await fulfillment(of: [consumeCancelled], timeout: 1)
        await task?.value

        XCTAssertFalse(didSaveSession)
        XCTAssertEqual(store.status, .idle)
        XCTAssertFalse(store.inFlight)
    }

    func testStaleMagicLinkResultDoesNotOverwriteCurrentStatus() async {
        let staleStarted = expectation(description: "Stale magic link request started")
        let staleReturned = expectation(description: "Stale magic link request returned")
        let freshStarted = expectation(description: "Fresh magic link request started")
        var calls = 0
        let store = RemoteAccessSettingsStore(
            requestMagicLinkOperation: { _, _, _, _ in
                calls += 1
                if calls == 1 {
                    staleStarted.fulfill()
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    staleReturned.fulfill()
                    return
                }
                freshStarted.fulfill()
            }
        )

        let first = store.sendMagicLink(
            coordinatorUrlString: "https://relay.example.com",
            email: "stale@example.com",
            deviceLabel: "Mac"
        )
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = store.sendMagicLink(
            coordinatorUrlString: "https://relay.example.com",
            email: "fresh@example.com",
            deviceLabel: "Mac"
        )

        await fulfillment(of: [freshStarted, staleReturned], timeout: 1)
        await first?.value
        await second?.value

        XCTAssertEqual(store.status, .info("Magic link sent to fresh@example.com. Open it on this Mac, then paste the token below."))
        XCTAssertFalse(store.inFlight)
    }

    private static func session(deviceId: String) throws -> CoordinatorClient.DeviceSession {
        let json = """
        {
          "deviceId": "\(deviceId)",
          "tenantId": "tenant",
          "accessToken": "access",
          "refreshToken": "refresh",
          "expiresInSec": 3600,
          "coordinator": {
            "publicBaseUrl": "https://relay.example.com",
            "irohRelay": null
          }
        }
        """
        let data = Data(json.utf8)
        return try JSONDecoder().decode(CoordinatorClient.DeviceSession.self, from: data)
    }
}
