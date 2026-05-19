import XCTest
@testable import Clawix

@MainActor
final class PublishingWorkspaceStoreCancellationTests: XCTestCase {
    func testResetCancelsInFlightBootstrap() async {
        let bootstrapStarted = expectation(description: "Bootstrap started")
        let bootstrapCancelled = expectation(description: "Bootstrap cancelled")
        let store = PublishingWorkspaceStore(
            bootstrapAvailabilityOperation: { nil },
            bootstrapOperation: {
                bootstrapStarted.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    bootstrapCancelled.fulfill()
                    throw CancellationError()
                }
                return .init(
                    workspaceId: "stale-workspace",
                    families: [Self.family(id: "stale")],
                    channels: [Self.account(id: "stale", familyId: "stale")]
                )
            },
            attachSupervisor: false
        )

        store.bootstrap()
        await fulfillment(of: [bootstrapStarted], timeout: 1)

        store.reset(reason: "Publishing stopped")

        await fulfillment(of: [bootstrapCancelled], timeout: 1)
        await Task.yield()

        XCTAssertEqual(store.state, .unavailable("Publishing stopped"))
        XCTAssertTrue(store.families.isEmpty)
        XCTAssertTrue(store.channels.isEmpty)
    }

    func testStaleBootstrapCannotOverwriteFreshBootstrap() async {
        let staleStarted = expectation(description: "Stale bootstrap started")
        let staleReturned = expectation(description: "Stale bootstrap returned")
        let freshStarted = expectation(description: "Fresh bootstrap started")
        var calls = 0
        let store = PublishingWorkspaceStore(
            bootstrapAvailabilityOperation: { nil },
            bootstrapOperation: {
                calls += 1
                if calls == 1 {
                    staleStarted.fulfill()
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    staleReturned.fulfill()
                    return .init(
                        workspaceId: "stale-workspace",
                        families: [Self.family(id: "stale")],
                        channels: [Self.account(id: "stale", familyId: "stale")]
                    )
                }
                freshStarted.fulfill()
                return .init(
                    workspaceId: "fresh-workspace",
                    families: [Self.family(id: "fresh")],
                    channels: [Self.account(id: "fresh", familyId: "fresh")]
                )
            },
            attachSupervisor: false
        )

        store.bootstrap()
        await fulfillment(of: [staleStarted], timeout: 1)

        store.reset(reason: "Retry bootstrap")
        store.bootstrap()

        await fulfillment(of: [freshStarted, staleReturned], timeout: 1)
        await Task.yield()

        XCTAssertEqual(store.state, .ready)
        XCTAssertEqual(store.workspaceId, "fresh-workspace")
        XCTAssertEqual(store.families.map(\.id), ["fresh"])
        XCTAssertEqual(store.channels.map(\.id), ["fresh"])
    }

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

    func testResetThenSameFamilyConnectDoesNotRecycleStaleGeneration() async throws {
        let staleStarted = expectation(description: "Stale connect started")
        let staleReturned = expectation(description: "Stale connect returned after reset")
        let freshStarted = expectation(description: "Fresh connect started")
        let releaseStale = AsyncGate()
        var calls = 0
        let store = PublishingWorkspaceStore(
            connectChannelOperation: { _, familyId, _ in
                calls += 1
                if calls == 1 {
                    staleStarted.fulfill()
                    await releaseStale.wait()
                    staleReturned.fulfill()
                    throw TestError(message: "stale connect failed")
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

        store.reset(reason: "Publishing stopped")
        let second = Task {
            try await store.connect(familyId: "devnull", payload: [:])
        }
        await fulfillment(of: [freshStarted], timeout: 1)

        await releaseStale.open()

        await fulfillment(of: [staleReturned], timeout: 1)
        do {
            _ = try await first.value
            XCTFail("Stale connect unexpectedly succeeded")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected stale connect error after reset: \(error)")
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

    func testResetThenSameAccountDisconnectDoesNotRecycleStaleGeneration() async {
        let staleStarted = expectation(description: "Stale disconnect started")
        let staleReturned = expectation(description: "Stale disconnect returned after reset")
        let freshStarted = expectation(description: "Fresh disconnect started")
        let releaseStale = AsyncGate()
        var calls = 0
        let account = Self.account(id: "main", familyId: "devnull")
        let store = PublishingWorkspaceStore(
            disconnectChannelOperation: { _, _ in
                calls += 1
                if calls == 1 {
                    staleStarted.fulfill()
                    await releaseStale.wait()
                    staleReturned.fulfill()
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

        store.reset(reason: "Publishing stopped")
        let second = Task { await store.disconnect(account: account) }
        await fulfillment(of: [freshStarted], timeout: 1)

        await releaseStale.open()

        await fulfillment(of: [staleReturned], timeout: 1)
        await first.value
        await second.value

        XCTAssertNil(store.lastError)
    }

    func testResetCancelsInFlightCreatePost() async {
        let createStarted = expectation(description: "Create post started")
        let createCancelled = expectation(description: "Create post cancelled")
        let store = PublishingWorkspaceStore(
            createPostOperation: { _, _ in
                createStarted.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    createCancelled.fulfill()
                    throw CancellationError()
                }
                return Self.post(id: "stale")
            },
            attachSupervisor: false,
            initialState: .ready,
            workspaceId: "workspace"
        )

        let task = Task {
            try await store.createPost(spec: Self.postSpec())
        }
        await fulfillment(of: [createStarted], timeout: 1)

        store.reset(reason: "Publishing stopped")

        await fulfillment(of: [createCancelled], timeout: 1)
        do {
            _ = try await task.value
            XCTFail("Cancelled post creation unexpectedly succeeded")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected create post error: \(error)")
        }

        XCTAssertTrue(store.posts.isEmpty)
        XCTAssertEqual(store.state, .unavailable("Publishing stopped"))
    }

    func testStartingSecondCreatePostCancelsStaleCreate() async throws {
        let staleStarted = expectation(description: "Stale create post started")
        let staleCancelled = expectation(description: "Stale create post cancelled")
        let freshStarted = expectation(description: "Fresh create post started")
        var calls = 0
        let store = PublishingWorkspaceStore(
            createPostOperation: { _, _ in
                calls += 1
                if calls == 1 {
                    staleStarted.fulfill()
                    do {
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                    } catch is CancellationError {
                        staleCancelled.fulfill()
                        throw CancellationError()
                    }
                    return Self.post(id: "stale")
                }
                freshStarted.fulfill()
                return Self.post(id: "fresh")
            },
            attachSupervisor: false,
            initialState: .ready,
            workspaceId: "workspace"
        )

        let first = Task {
            try await store.createPost(spec: Self.postSpec())
        }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task {
            try await store.createPost(spec: Self.postSpec())
        }

        await fulfillment(of: [staleCancelled, freshStarted], timeout: 1)
        do {
            _ = try await first.value
            XCTFail("Stale create post unexpectedly succeeded")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected stale create post error: \(error)")
        }
        let post = try await second.value

        XCTAssertEqual(post.id, "fresh")
        XCTAssertEqual(store.posts.map(\.id), ["fresh"])
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

    private static func postSpec() -> ClawJSPublishingClient.PostSpec {
        .init(
            accounts: ["main"],
            editorialStatus: "draft",
            schedule: .unscheduled,
            variants: [
                .init(
                    isOriginal: true,
                    channelAccountId: nil,
                    blocks: [.init(body: "Hello")]
                )
            ]
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

    private actor AsyncGate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var isOpen = false

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }

        func open() {
            guard !isOpen else { return }
            isOpen = true
            continuation?.resume()
            continuation = nil
        }
    }
}
