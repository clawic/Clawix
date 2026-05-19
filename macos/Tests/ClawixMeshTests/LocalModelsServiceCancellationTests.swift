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

    private static func makeDefaults() -> UserDefaults {
        let suite = "LocalModelsServiceCancellationTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite) ?? .standard
    }
}
