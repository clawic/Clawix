import XCTest
@testable import Clawix

@MainActor
final class DeviceCodeSignInCoordinatorTests: XCTestCase {
    private struct TestFailure: LocalizedError {
        let errorDescription: String?
    }

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
        XCTAssertEqual(coordinator.phase, .requesting)
        XCTAssertNil(coordinator.deviceCode)
        XCTAssertNil(coordinator.error)
        XCTAssertTrue(didOpenVerificationURL)
        XCTAssertFalse(didPersistAccount)
        XCTAssertFalse(didComplete)
    }

    func testRestartingDeviceCodeFlowClearsStaleCodeBeforeRequestReturns() async {
        let firstRequested = expectation(description: "First device code requested")
        let secondRequestStarted = expectation(description: "Second device code request started")
        let deviceCode = GitHubCopilotDeviceFlow.DeviceCode(
            deviceCode: "device-code",
            userCode: "USER-CODE",
            verificationUri: URL(string: "https://github.com/login/device")!,
            interval: 1,
            expiresAt: Date().addingTimeInterval(60)
        )
        var requestCount = 0
        let coordinator = DeviceCodeSignInCoordinator(operations: .init(
            requestDeviceCode: {
                requestCount += 1
                if requestCount == 1 {
                    firstRequested.fulfill()
                    return deviceCode
                }
                secondRequestStarted.fulfill()
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return deviceCode
            },
            openVerificationURL: { _ in },
            pollAccessToken: { _, _, _ in
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return "token"
            },
            persistAccount: { _, _ in },
            refreshStore: {},
            completionDelay: {}
        ))

        coordinator.start {}
        await fulfillment(of: [firstRequested], timeout: 1)
        XCTAssertEqual(coordinator.deviceCode?.userCode, "USER-CODE")

        coordinator.start {}

        XCTAssertEqual(coordinator.phase, .requesting)
        XCTAssertNil(coordinator.deviceCode)
        await fulfillment(of: [secondRequestStarted], timeout: 1)
        coordinator.cancel()
    }

    func testRequestFailureUsesClassifiedLocalizedMessage() async {
        let failed = expectation(description: "Device code request failed")
        let coordinator = DeviceCodeSignInCoordinator(operations: .init(
            requestDeviceCode: {
                failed.fulfill()
                throw TestFailure(errorDescription: "The Internet connection appears to be offline.")
            },
            openVerificationURL: { _ in },
            pollAccessToken: { _, _, _ in "token" },
            persistAccount: { _, _ in },
            refreshStore: {},
            completionDelay: {}
        ))

        coordinator.start {}

        await fulfillment(of: [failed], timeout: 1)
        await Task.yield()
        XCTAssertEqual(
            coordinator.error,
            L10n.t("The network appears to be offline. Reconnect, then try again.")
        )
    }
}
