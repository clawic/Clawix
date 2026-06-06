import XCTest
@testable import ClawixEngine

#if canImport(WhisperKit)
final class DictationModelStoreTests: XCTestCase {
    func testInvalidatedNotificationIsAvailableOffMainActor() async throws {
        let posted = expectation(description: "dictation invalidation notification")
        let observer = NotificationCenter.default.addObserver(
            forName: DictationModelStore.modelInvalidatedNotification,
            object: "tiny",
            queue: nil
        ) { _ in
            posted.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        await Task.detached {
            NotificationCenter.default.post(
                name: DictationModelStore.modelInvalidatedNotification,
                object: "tiny"
            )
        }.value

        await fulfillment(of: [posted], timeout: 1.0)
    }
}
#endif
