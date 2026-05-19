import XCTest
@testable import Clawix

@MainActor
final class DeviceCodeSignInCoordinatorTests: XCTestCase {
    func testCancelStopsDeviceCodePollingBeforePersistingAccount() async {
        let requested = expectation(description: "Device code requested")
        let pollingStarted = expectation(description: "Polling started")
        let pollingCancelled = expectation(description: "Polling cancelled")
        let deviceCode = GitHubCopilotDeviceFlow.DeviceCode(
            deviceCode: "device-code",
            userCode: "USER-CODE",
            verificationUri: URL(string: "https://github.com/login/device")!,
            interval: 1,
            expiresAt: Date().addingTimeInterval(60)
        )
        var didOpenVerificationURL = false
        var didPersistAccount = false
        var didComplete = false
        let coordinator = DeviceCodeSignInCoordinator(operations: .init(
            requestDeviceCode: {
                requested.fulfill()
                return deviceCode
            },
            openVerificationURL: { _ in
                didOpenVerificationURL = true
            },
            pollAccessToken: { _, _, _ in
                pollingStarted.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    pollingCancelled.fulfill()
                    throw CancellationError()
                }
                return "token"
            },
            persistAccount: { _, _ in
                didPersistAccount = true
            },
            refreshStore: {},
            completionDelay: {}
        ))

        coordinator.start {
            didComplete = true
        }
        await fulfillment(of: [requested, pollingStarted], timeout: 1)

        coordinator.cancel()

        await fulfillment(of: [pollingCancelled], timeout: 1)
        XCTAssertEqual(coordinator.phase, .waiting)
        XCTAssertEqual(coordinator.deviceCode?.userCode, "USER-CODE")
        XCTAssertTrue(didOpenVerificationURL)
        XCTAssertFalse(didPersistAccount)
        XCTAssertFalse(didComplete)
    }
}
