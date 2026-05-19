import XCTest
@testable import Clawix

@MainActor
final class PublishingWorkspaceStoreCancellationTests: XCTestCase {
    func testStartingSecondCalendarRefreshCancelsStaleRefresh() async {
        let staleStarted = expectation(description: "Stale calendar refresh started")
        let staleCancelled = expectation(description: "Stale calendar refresh cancelled")
        let freshStarted = expectation(description: "Fresh calendar refresh started")
        var calls = 0
        let store = PublishingWorkspaceStore(
            listPostsOperation: { _, _, _ in
                calls += 1
                if calls == 1 {
                    staleStarted.fulfill()
                    do {
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                    } catch is CancellationError {
                        staleCancelled.fulfill()
                        throw CancellationError()
                    }
                    return [Self.post(id: "stale")]
                }
                freshStarted.fulfill()
                return [Self.post(id: "fresh")]
            },
            attachSupervisor: false,
            initialState: .ready,
            workspaceId: "workspace"
        )

        let first = Task {
            await store.refreshCalendar(from: Self.date(1), to: Self.date(2))
        }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task {
            await store.refreshCalendar(from: Self.date(3), to: Self.date(4))
        }

        await fulfillment(of: [staleCancelled, freshStarted], timeout: 1)
        await first.value
        await second.value

        XCTAssertEqual(store.posts.map(\.id), ["fresh"])
        XCTAssertNil(store.lastError)
    }

    func testStaleCalendarRefreshCannotOverwriteFreshPosts() async {
        let staleStarted = expectation(description: "Stale calendar refresh started")
        let staleReturned = expectation(description: "Stale calendar refresh returned")
        let freshStarted = expectation(description: "Fresh calendar refresh started")
        var calls = 0
        let store = PublishingWorkspaceStore(
            listPostsOperation: { _, _, _ in
                calls += 1
                if calls == 1 {
                    staleStarted.fulfill()
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    staleReturned.fulfill()
                    return [Self.post(id: "stale")]
                }
                freshStarted.fulfill()
                return [Self.post(id: "fresh")]
            },
            attachSupervisor: false,
            initialState: .ready,
            workspaceId: "workspace"
        )

        let first = Task {
            await store.refreshCalendar(from: Self.date(1), to: Self.date(2))
        }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task {
            await store.refreshCalendar(from: Self.date(3), to: Self.date(4))
        }

        await fulfillment(of: [freshStarted, staleReturned], timeout: 1)
        await first.value
        await second.value

        XCTAssertEqual(store.posts.map(\.id), ["fresh"])
        XCTAssertNil(store.lastError)
    }

    func testResetCancelsInFlightCalendarRefresh() async {
        let refreshStarted = expectation(description: "Calendar refresh started")
        let refreshCancelled = expectation(description: "Calendar refresh cancelled")
        let store = PublishingWorkspaceStore(
            listPostsOperation: { _, _, _ in
                refreshStarted.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    refreshCancelled.fulfill()
                    throw CancellationError()
                }
                return [Self.post(id: "stale")]
            },
            attachSupervisor: false,
            initialState: .ready,
            workspaceId: "workspace"
        )

        let task = Task {
            await store.refreshCalendar(from: Self.date(1), to: Self.date(2))
        }
        await fulfillment(of: [refreshStarted], timeout: 1)

        store.reset(reason: "Publishing stopped")

        await fulfillment(of: [refreshCancelled], timeout: 1)
        await task.value

        XCTAssertTrue(store.posts.isEmpty)
        XCTAssertEqual(store.state, .unavailable("Publishing stopped"))
    }

    private static func date(_ day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = 2026
        components.month = 5
        components.day = day
        return components.date!
    }

    private static func post(id: String) -> ClawJSPublishingClient.Post {
        ClawJSPublishingClient.Post(
            id: id,
            workspaceId: "workspace",
            editorialStatus: "draft",
            publishStatus: "scheduled",
            scheduledAt: nil,
            publishedAt: nil,
            createdAt: 0,
            updatedAt: 0
        )
    }
}
