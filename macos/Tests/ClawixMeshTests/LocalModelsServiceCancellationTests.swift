import XCTest
@testable import Clawix

@MainActor
final class LocalModelsServiceCancellationTests: XCTestCase {
    func testStartingSameModelPullCancelsStalePullTask() async {
        let slowStarted = expectation(description: "Slow model pull started")
        let slowCancelled = expectation(description: "Slow model pull cancelled")
        let fastStarted = expectation(description: "Fast model pull started")
        var calls = 0
        var refreshCount = 0
        let service = LocalModelsService(
            defaults: Self.makeDefaults(),
            bindRuntimeState: false,
            pullOperation: { _ in
                calls += 1
                if calls == 1 {
                    return Self.slowPullStream(started: slowStarted, cancelled: slowCancelled)
                }
                return AsyncThrowingStream { continuation in
                    fastStarted.fulfill()
                    continuation.yield(Self.pullEvent(status: "success"))
                    continuation.finish()
                }
            },
            refreshModelListOperation: {
                refreshCount += 1
            }
        )

        let first = Task { await service.pull(model: "llama3.2:1b") }
        await fulfillment(of: [slowStarted], timeout: 1)

        let second = Task { await service.pull(model: "llama3.2:1b") }

        await fulfillment(of: [slowCancelled, fastStarted], timeout: 1)
        await first.value
        await second.value

        XCTAssertNil(service.downloads["llama3.2:1b"])
        XCTAssertEqual(refreshCount, 1)
    }

    func testCancelPullClearsRunningDownloadAndStopsStream() async {
        let started = expectation(description: "Model pull started")
        let cancelled = expectation(description: "Model pull cancelled")
        let service = LocalModelsService(
            defaults: Self.makeDefaults(),
            bindRuntimeState: false,
            pullOperation: { _ in
                Self.slowPullStream(started: started, cancelled: cancelled)
            },
            refreshModelListOperation: {}
        )

        let task = Task { await service.pull(model: "mistral:latest") }
        await fulfillment(of: [started], timeout: 1)

        service.cancelPull(model: "mistral:latest")

        await fulfillment(of: [cancelled], timeout: 1)
        await task.value
        XCTAssertNil(service.downloads["mistral:latest"])
    }

    func testCancelEnableStopsRunningRuntimeActivation() async {
        let started = expectation(description: "Local runtime activation started")
        let cancelled = expectation(description: "Local runtime activation cancelled")
        let service = LocalModelsService(
            defaults: Self.makeDefaults(),
            bindRuntimeState: false,
            pullOperation: { _ in
                AsyncThrowingStream { continuation in continuation.finish() }
            },
            refreshModelListOperation: {},
            enableOperation: { _, _ in
                started.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    cancelled.fulfill()
                } catch {
                    XCTFail("Unexpected enable cancellation error: \(error)")
                }
            }
        )

        let task = Task { await service.enable() }
        await fulfillment(of: [started], timeout: 1)

        service.cancelEnable()

        await fulfillment(of: [cancelled], timeout: 1)
        await task.value
    }

    func testCancelInstallStopsRunningRuntimeActivation() async {
        let started = expectation(description: "Local runtime install activation started")
        let cancelled = expectation(description: "Local runtime install activation cancelled")
        let service = LocalModelsService(
            defaults: Self.makeDefaults(),
            bindRuntimeState: false,
            pullOperation: { _ in
                AsyncThrowingStream { continuation in continuation.finish() }
            },
            refreshModelListOperation: {},
            enableOperation: { _, _ in
                started.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    cancelled.fulfill()
                } catch {
                    XCTFail("Unexpected install cancellation error: \(error)")
                }
            }
        )

        let task = Task { await service.enable() }
        await fulfillment(of: [started], timeout: 1)

        service.cancelInstall()

        await fulfillment(of: [cancelled], timeout: 1)
        await task.value
    }

    func testStartingSameUnloadCancelsStaleModelAction() async {
        let slowStarted = expectation(description: "Slow model unload started")
        let slowCancelled = expectation(description: "Slow model unload cancelled")
        let fastStarted = expectation(description: "Fast model unload started")
        var calls = 0
        var refreshCount = 0
        let service = LocalModelsService(
            defaults: Self.makeDefaults(),
            bindRuntimeState: false,
            pullOperation: { _ in
                AsyncThrowingStream { continuation in continuation.finish() }
            },
            refreshModelListOperation: {
                refreshCount += 1
            },
            unloadOperation: { _ in
                calls += 1
                if calls == 1 {
                    try await Self.slowModelAction(started: slowStarted, cancelled: slowCancelled)
                } else {
                    fastStarted.fulfill()
                }
            }
        )

        let first = Task { await service.unload(model: "llama3.2:1b") }
        await fulfillment(of: [slowStarted], timeout: 1)

        let second = Task { await service.unload(model: "llama3.2:1b") }

        await fulfillment(of: [slowCancelled, fastStarted], timeout: 1)
        await first.value
        await second.value

        XCTAssertNil(service.actionError)
        XCTAssertEqual(refreshCount, 1)
    }

    func testDisableCancelsRunningModelActions() async {
        let started = expectation(description: "Model delete started")
        let cancelled = expectation(description: "Model delete cancelled")
        let service = LocalModelsService(
            defaults: Self.makeDefaults(),
            bindRuntimeState: false,
            pullOperation: { _ in
                AsyncThrowingStream { continuation in continuation.finish() }
            },
            refreshModelListOperation: {},
            deleteOperation: { _ in
                try await Self.slowModelAction(started: started, cancelled: cancelled)
            }
        )

        let task = Task { await service.delete(model: "mistral:latest") }
        await fulfillment(of: [started], timeout: 1)

        service.disable()

        await fulfillment(of: [cancelled], timeout: 1)
        await task.value
        XCTAssertNil(service.actionError)
    }

    func testEndingPollingSuppressesStaleDaemonVersion() async {
        let started = expectation(description: "Daemon version poll started")
        let returned = expectation(description: "Daemon version poll returned")
        let service = LocalModelsService(
            defaults: Self.makeDefaults(),
            bindRuntimeState: false,
            pullOperation: { _ in
                AsyncThrowingStream { continuation in continuation.finish() }
            },
            refreshModelListOperation: {},
            daemonVersionOperation: {
                started.fulfill()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                returned.fulfill()
                return "stale-version"
            }
        )

        service.beginPolling()
        await fulfillment(of: [started], timeout: 1)

        service.endPolling()

        await fulfillment(of: [returned], timeout: 1)
        await Task.yield()
        XCTAssertNil(service.runtimeVersion)
    }

    func testPullFailureUsesUserFacingClassifiedMessage() async {
        let service = LocalModelsService(
            defaults: Self.makeDefaults(),
            bindRuntimeState: false,
            pullOperation: { _ in
                AsyncThrowingStream { continuation in
                    continuation.finish(throwing: TestLocalizedError(message: "No model available for this provider."))
                }
            },
            refreshModelListOperation: {}
        )

        await service.pull(model: "missing:model")

        guard case .failed(let message) = service.downloads["missing:model"]?.state else {
            return XCTFail("Expected failed download state")
        }
        XCTAssertEqual(message, L10n.t("That model is not available. Pick another model and try again."))
    }

    func testModelActionFailureUsesUserFacingClassifiedMessage() async {
        let service = LocalModelsService(
            defaults: Self.makeDefaults(),
            bindRuntimeState: false,
            pullOperation: { _ in
                AsyncThrowingStream { continuation in continuation.finish() }
            },
            refreshModelListOperation: {},
            unloadOperation: { _ in
                throw TestLocalizedError(message: "connection refused")
            }
        )

        await service.unload(model: "llama3.2:1b")

        XCTAssertEqual(
            service.actionError,
            String(
                format: L10n.t("Could not unload %@: %@"),
                locale: AppLocale.current,
                "llama3.2:1b",
                L10n.t("The background bridge is unavailable. Try again after it reconnects.")
            )
        )
    }

    private static func slowPullStream(
        started: XCTestExpectation,
        cancelled: XCTestExpectation
    ) -> AsyncThrowingStream<LocalModelsClient.PullEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                started.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    cancelled.fulfill()
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func pullEvent(status: String) -> LocalModelsClient.PullEvent {
        LocalModelsClient.PullEvent(
            status: status,
            digest: nil,
            total: nil,
            completed: nil,
            error: nil
        )
    }

    private static func slowModelAction(
        started: XCTestExpectation,
        cancelled: XCTestExpectation
    ) async throws {
        started.fulfill()
        do {
            try await Task.sleep(nanoseconds: 5_000_000_000)
        } catch is CancellationError {
            cancelled.fulfill()
            throw CancellationError()
        }
    }

    private static func makeDefaults() -> UserDefaults {
        let suite = "LocalModelsServiceCancellationTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite) ?? .standard
    }

    private struct TestLocalizedError: LocalizedError {
        let message: String

        var errorDescription: String? { message }
    }
}
