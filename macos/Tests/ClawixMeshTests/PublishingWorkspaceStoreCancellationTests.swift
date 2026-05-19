import XCTest
@testable import Clawix

@MainActor
final class PublishingWorkspaceStoreCancellationTests: XCTestCase {
    func testStartingSecondFamiliesRefreshCancelsStaleRefresh() async {
        let staleStarted = expectation(description: "Stale families refresh started")
        let staleCancelled = expectation(description: "Stale families refresh cancelled")
        let freshStarted = expectation(description: "Fresh families refresh started")
        var calls = 0
        let store = PublishingWorkspaceStore(
            listFamiliesOperation: {
                calls += 1
                if calls == 1 {
                    staleStarted.fulfill()
                    do {
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                    } catch is CancellationError {
                        staleCancelled.fulfill()
                        throw CancellationError()
                    }
                    return [Self.family(id: "stale")]
                }
                freshStarted.fulfill()
                return [Self.family(id: "fresh")]
            },
            attachSupervisor: false,
            initialState: .ready,
            workspaceId: "workspace"
        )

        let first = Task { await store.refreshFamilies() }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task { await store.refreshFamilies() }

        await fulfillment(of: [staleCancelled, freshStarted], timeout: 1)
        await first.value
        await second.value

        XCTAssertEqual(store.families.map(\.id), ["fresh"])
        XCTAssertNil(store.lastError)
    }

    func testStaleChannelsRefreshCannotOverwriteFreshChannels() async {
        let staleStarted = expectation(description: "Stale channels refresh started")
        let staleReturned = expectation(description: "Stale channels refresh returned")
        let freshStarted = expectation(description: "Fresh channels refresh started")
        var calls = 0
        let store = PublishingWorkspaceStore(
            listChannelsOperation: { _ in
                calls += 1
                if calls == 1 {
                    staleStarted.fulfill()
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    staleReturned.fulfill()
                    return [Self.account(id: "stale", familyId: "stale")]
                }
                freshStarted.fulfill()
                return [Self.account(id: "fresh", familyId: "fresh")]
            },
            attachSupervisor: false,
            initialState: .ready,
            workspaceId: "workspace"
        )

        let first = Task { await store.refreshChannels() }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task { await store.refreshChannels() }

        await fulfillment(of: [freshStarted, staleReturned], timeout: 1)
        await first.value
        await second.value

        XCTAssertEqual(store.channels.map(\.id), ["fresh"])
        XCTAssertNil(store.lastError)
    }

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

    func testStartingSecondConnectCancelsStaleConnect() async throws {
        let staleStarted = expectation(description: "Stale connect started")
        let staleCancelled = expectation(description: "Stale connect cancelled")
        let freshStarted = expectation(description: "Fresh connect started")
        var calls = 0
        let store = PublishingWorkspaceStore(
            connectChannelOperation: { _, familyId, _ in
                calls += 1
                if calls == 1 {
                    staleStarted.fulfill()
                    do {
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                    } catch is CancellationError {
                        staleCancelled.fulfill()
                        throw CancellationError()
                    }
                    return Self.account(id: "stale", familyId: familyId)
                }
                freshStarted.fulfill()
                return Self.account(id: "fresh", familyId: familyId)
            },
            attachSupervisor: false,
            initialState: .ready,
            workspaceId: "workspace"
        )

        let first = Task {
            try await store.connect(familyId: "devnull", payload: [:])
        }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task {
            try await store.connect(familyId: "devnull", payload: [:])
        }

        await fulfillment(of: [staleCancelled, freshStarted], timeout: 1)
        do {
            _ = try await first.value
            XCTFail("Stale connect unexpectedly succeeded")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected stale connect error: \(error)")
        }
        let account = try await second.value

        XCTAssertEqual(account.id, "fresh")
        XCTAssertEqual(store.channels.map(\.id), ["fresh"])
        XCTAssertNil(store.lastError)
    }

    func testStartingSecondDisconnectSuppressesStaleFailure() async {
        let staleStarted = expectation(description: "Stale disconnect started")
        let staleCancelled = expectation(description: "Stale disconnect cancelled")
        let freshStarted = expectation(description: "Fresh disconnect started")
        var calls = 0
        let account = Self.account(id: "main", familyId: "devnull")
        let store = PublishingWorkspaceStore(
            disconnectChannelOperation: { _, _ in
                calls += 1
                if calls == 1 {
                    staleStarted.fulfill()
                    do {
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                    } catch is CancellationError {
                        staleCancelled.fulfill()
                        throw CancellationError()
                    }
                    throw TestError(message: "stale disconnect failed")
                }
                freshStarted.fulfill()
                return true
            },
            attachSupervisor: false,
            initialState: .ready,
            workspaceId: "workspace"
        )

        let first = Task { await store.disconnect(account: account) }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task { await store.disconnect(account: account) }

        await fulfillment(of: [staleCancelled, freshStarted], timeout: 1)
        await first.value
        await second.value

        XCTAssertNil(store.lastError)
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

    private static func family(id: String) -> ClawJSPublishingClient.Family {
        ClawJSPublishingClient.Family(
            id: id,
            name: id.capitalized,
            group: "social",
            authKind: "none",
            capabilities: .init(
                contentKinds: ["text"],
                text: .init(
                    minChars: nil,
                    maxChars: 300,
                    supportsMarkdown: false,
                    supportsMentions: false,
                    supportsHashtags: false
                ),
                multiVariant: "none"
            )
        )
    }

    private static func account(id: String, familyId: String) -> ClawJSPublishingClient.ChannelAccount {
        ClawJSPublishingClient.ChannelAccount(
            id: id,
            workspaceId: "workspace",
            familyId: familyId,
            providerAccountId: "provider-\(id)",
            displayName: id.capitalized,
            handle: id,
            avatarUrl: nil,
            authorized: true,
            createdAt: 0
        )
    }

    private struct TestError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}
