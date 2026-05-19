import Foundation
import XCTest
@testable import Clawix

@MainActor
final class ProfileSurfaceStoreCancellationTests: XCTestCase {
    func testStartingSecondBootstrapCancelsStaleBootstrap() async {
        let staleStarted = expectation(description: "Stale profile bootstrap started")
        let staleCancelled = expectation(description: "Stale profile bootstrap cancelled")
        let freshReturned = expectation(description: "Fresh profile bootstrap returned")
        let client = FakeProfileClient()
        var calls = 0
        client.onMe = {
            calls += 1
            if calls == 1 {
                staleStarted.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    staleCancelled.fulfill()
                    throw CancellationError()
                }
                return makeProfile(alias: "stale")
            }
            freshReturned.fulfill()
            return makeProfile(alias: "fresh")
        }
        let store = ProfileSurfaceStore(client: client, tokenOperation: { "token" })

        let first = Task { await store.bootstrap() }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task { await store.bootstrap() }

        await fulfillment(of: [staleCancelled, freshReturned], timeout: 1)
        await first.value
        await second.value
        XCTAssertEqual(store.me?.handle.alias, "fresh")
        XCTAssertEqual(store.loadState, .ready)
    }

    func testStaleBootstrapCannotOverwriteFreshBootstrap() async {
        let staleStarted = expectation(description: "Stale profile bootstrap started")
        let staleReturned = expectation(description: "Stale profile bootstrap returned")
        let freshReturned = expectation(description: "Fresh profile bootstrap returned")
        let client = FakeProfileClient()
        var calls = 0
        client.onMe = {
            calls += 1
            if calls == 1 {
                staleStarted.fulfill()
                try? await Task.sleep(nanoseconds: 100_000_000)
                staleReturned.fulfill()
                return makeProfile(alias: "stale")
            }
            freshReturned.fulfill()
            return makeProfile(alias: "fresh")
        }
        let store = ProfileSurfaceStore(client: client, tokenOperation: { "token" })

        let first = Task { await store.bootstrap() }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task { await store.bootstrap() }

        await fulfillment(of: [freshReturned, staleReturned], timeout: 1)
        await first.value
        await second.value
        XCTAssertEqual(store.me?.handle.alias, "fresh")
        XCTAssertEqual(store.loadState, .ready)
    }

    func testStartingSecondFeedRefreshCancelsStaleQuery() async {
        let staleStarted = expectation(description: "Stale feed refresh started")
        let staleCancelled = expectation(description: "Stale feed refresh cancelled")
        let freshReturned = expectation(description: "Fresh feed refresh returned")
        let client = FakeProfileClient()
        var calls = 0
        client.onListFeed = { _, _, keywords, _ in
            calls += 1
            if calls == 1 {
                XCTAssertEqual(keywords, "stale")
                staleStarted.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    staleCancelled.fulfill()
                    throw CancellationError()
                }
                return [makeFeedEntry(id: "stale")]
            }
            XCTAssertEqual(keywords, "fresh")
            freshReturned.fulfill()
            return [makeFeedEntry(id: "fresh")]
        }
        let store = ProfileSurfaceStore(client: client, tokenOperation: { "token" })

        store.feedKeywords = "stale"
        let first = Task { await store.refreshFeed() }
        await fulfillment(of: [staleStarted], timeout: 1)

        store.feedKeywords = "fresh"
        let second = Task { await store.refreshFeed() }

        await fulfillment(of: [staleCancelled, freshReturned], timeout: 1)
        await first.value
        await second.value
        XCTAssertEqual(store.feedEntries.map(\.blockId), ["fresh"])
    }

    func testCancelSurfaceWorkSuppressesInFlightFeedRefresh() async {
        let refreshStarted = expectation(description: "Feed refresh started")
        let refreshCancelled = expectation(description: "Feed refresh cancelled")
        let client = FakeProfileClient()
        client.onListFeed = { _, _, _, _ in
            refreshStarted.fulfill()
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                refreshCancelled.fulfill()
                throw CancellationError()
            }
            return [makeFeedEntry(id: "stale")]
        }
        let store = ProfileSurfaceStore(client: client, tokenOperation: { "token" })

        let task = Task { await store.refreshFeed() }
        await fulfillment(of: [refreshStarted], timeout: 1)

        store.cancelSurfaceWork()

        await fulfillment(of: [refreshCancelled], timeout: 1)
        await task.value
        XCTAssertTrue(store.feedEntries.isEmpty)
    }

    func testStartingSecondMessageLoadCancelsStalePeerLoad() async {
        let staleStarted = expectation(description: "Stale message load started")
        let staleCancelled = expectation(description: "Stale message load cancelled")
        let freshReturned = expectation(description: "Fresh message load returned")
        let client = FakeProfileClient()
        var calls = 0
        client.onListMessages = { peer, _, _ in
            XCTAssertEqual(peer, "peer")
            calls += 1
            if calls == 1 {
                staleStarted.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    staleCancelled.fulfill()
                    throw CancellationError()
                }
                return [makeChatMessage(id: "stale")]
            }
            freshReturned.fulfill()
            return [makeChatMessage(id: "fresh")]
        }
        let store = ProfileSurfaceStore(client: client, tokenOperation: { "token" })

        let first = Task { try? await store.loadMessages(peer: "peer") }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task { try? await store.loadMessages(peer: "peer") }

        await fulfillment(of: [staleCancelled, freshReturned], timeout: 1)
        _ = await first.value
        _ = await second.value
        XCTAssertEqual(store.messages(forPeer: "peer").map(\.id), ["fresh"])
    }

    func testStaleMessageLoadCannotOverwriteFreshPeerMessages() async {
        let staleStarted = expectation(description: "Stale message load started")
        let staleReturned = expectation(description: "Stale message load returned")
        let freshReturned = expectation(description: "Fresh message load returned")
        let client = FakeProfileClient()
        var calls = 0
        client.onListMessages = { _, _, _ in
            calls += 1
            if calls == 1 {
                staleStarted.fulfill()
                try? await Task.sleep(nanoseconds: 100_000_000)
                staleReturned.fulfill()
                return [makeChatMessage(id: "stale")]
            }
            freshReturned.fulfill()
            return [makeChatMessage(id: "fresh")]
        }
        let store = ProfileSurfaceStore(client: client, tokenOperation: { "token" })

        let first = Task { try? await store.loadMessages(peer: "peer") }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task { try? await store.loadMessages(peer: "peer") }

        await fulfillment(of: [freshReturned, staleReturned], timeout: 1)
        _ = await first.value
        _ = await second.value
        XCTAssertEqual(store.messages(forPeer: "peer").map(\.id), ["fresh"])
    }

    func testCancelChatSurfaceWorkSuppressesInFlightMessageLoad() async {
        let loadStarted = expectation(description: "Message load started")
        let loadCancelled = expectation(description: "Message load cancelled")
        let client = FakeProfileClient()
        client.onListMessages = { _, _, _ in
            loadStarted.fulfill()
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                loadCancelled.fulfill()
                throw CancellationError()
            }
            return [makeChatMessage(id: "stale")]
        }
        let store = ProfileSurfaceStore(client: client, tokenOperation: { "token" })

        let task = Task { try? await store.loadMessages(peer: "peer") }
        await fulfillment(of: [loadStarted], timeout: 1)

        store.cancelChatSurfaceWork()

        await fulfillment(of: [loadCancelled], timeout: 1)
        _ = await task.value
        XCTAssertTrue(store.messages(forPeer: "peer").isEmpty)
    }

    func testSendMessagePublishesThroughStoreMessages() async throws {
        let client = FakeProfileClient()
        client.onSendMessage = { peer, body in
            XCTAssertEqual(peer, "peer")
            return makeChatMessage(id: body)
        }
        let store = ProfileSurfaceStore(client: client, tokenOperation: { "token" })

        _ = try await store.sendMessage(peer: "peer", body: "sent")

        XCTAssertEqual(store.messages(forPeer: "peer").map(\.id), ["sent"])
    }

    func testCancelChatSurfaceWorkSuppressesInFlightSendMessage() async {
        let sendStarted = expectation(description: "P2P send started")
        let sendReturned = expectation(description: "P2P send returned after teardown")
        let client = FakeProfileClient()
        client.onSendMessage = { peer, body in
            XCTAssertEqual(peer, "peer")
            XCTAssertEqual(body, "stale")
            sendStarted.fulfill()
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            sendReturned.fulfill()
            return makeChatMessage(id: "stale")
        }
        let store = ProfileSurfaceStore(client: client, tokenOperation: { "token" })

        let task = Task { try? await store.sendMessage(peer: "peer", body: "stale") }
        await fulfillment(of: [sendStarted], timeout: 1)

        store.cancelChatSurfaceWork()

        await fulfillment(of: [sendReturned], timeout: 1)
        let result = await task.value
        XCTAssertNil(result)
        XCTAssertTrue(store.messages(forPeer: "peer").isEmpty)
    }

    func testConcurrentSendsRemainValidWhileChatSurfaceIsCurrent() async throws {
        let client = FakeProfileClient()
        client.onSendMessage = { _, body in
            try? await Task.sleep(nanoseconds: body == "first" ? 60_000_000 : 10_000_000)
            return makeChatMessage(id: body)
        }
        let store = ProfileSurfaceStore(client: client, tokenOperation: { "token" })

        async let first = store.sendMessage(peer: "peer", body: "first")
        async let second = store.sendMessage(peer: "peer", body: "second")
        _ = try await [first, second]

        XCTAssertEqual(Set(store.messages(forPeer: "peer").map(\.id)), Set(["first", "second"]))
    }

    func testCancelSurfaceWorkSuppressesInFlightProfileRename() async {
        let renameStarted = expectation(description: "Profile rename started")
        let renameReturned = expectation(description: "Profile rename returned after teardown")
        let client = FakeProfileClient()
        client.onSetHandle = { alias in
            XCTAssertEqual(alias, "stale")
            renameStarted.fulfill()
            try? await Task.sleep(nanoseconds: 50_000_000)
            renameReturned.fulfill()
            return makeProfile(alias: alias)
        }
        let store = ProfileSurfaceStore(client: client, tokenOperation: { "token" })

        let task = Task { try? await store.renameHandle(to: "stale") }
        await fulfillment(of: [renameStarted], timeout: 1)

        store.cancelSurfaceWork()

        await fulfillment(of: [renameReturned], timeout: 1)
        let result: Void? = await task.value
        XCTAssertNil(result)
        XCTAssertNil(store.me)
    }

    func testCancelSurfaceWorkSuppressesInFlightBlockCreation() async {
        let blockStarted = expectation(description: "Block creation started")
        let blockReturned = expectation(description: "Block creation returned after teardown")
        let client = FakeProfileClient()
        client.onCreateBlock = { input in
            XCTAssertEqual(input.archetype, "note")
            blockStarted.fulfill()
            try? await Task.sleep(nanoseconds: 50_000_000)
            blockReturned.fulfill()
            return makeBlock(id: "stale")
        }
        let store = ProfileSurfaceStore(client: client, tokenOperation: { "token" })

        let task = Task { try? await store.createBlock(makeCreateBlockInput(archetype: "note")) }
        await fulfillment(of: [blockStarted], timeout: 1)

        store.cancelSurfaceWork()

        await fulfillment(of: [blockReturned], timeout: 1)
        let result: Void? = await task.value
        XCTAssertNil(result)
        XCTAssertTrue(store.ownBlocks.isEmpty)
    }

}

private func makeProfile(alias: String) -> ClawJSProfileClient.Profile {
    ClawJSProfileClient.Profile(
        rootPubkey: "\(alias)-root",
        handle: makeHandle(alias: alias),
        blocks: [],
        groups: [],
        version: 1,
        updatedAt: 1
    )
}

private func makeHandle(alias: String) -> ClawJSProfileClient.Handle {
    ClawJSProfileClient.Handle(alias: alias, fingerprint: "\(alias)-fingerprint", rootPubkey: "\(alias)-root")
}

private func makeBlock(id: String) -> ClawJSProfileClient.Block {
    ClawJSProfileClient.Block(
        blockId: id,
        archetype: "note",
        vertical: "work",
        audience: .init(groups: []),
        fieldsPerLevel: [:],
        trackingRef: nil,
        overlay: nil,
        content: nil,
        createdAt: 1,
        updatedAt: 1,
        version: 1
    )
}

private func makeCreateBlockInput(archetype: String) -> ClawJSProfileClient.CreateBlockInput {
    ClawJSProfileClient.CreateBlockInput(
        vertical: "work",
        archetype: archetype,
        audience: .init(groups: []),
        fieldsPerLevel: [:],
        content: nil,
        overlay: nil,
        trackingRef: nil
    )
}

private func makeGroup(id: String) -> ClawJSProfileClient.Group {
    ClawJSProfileClient.Group(id: id, label: id, members: [], createdAt: 1, updatedAt: 1, inviteLink: nil)
}

private func makeFeedEntry(id: String) -> ClawJSProfileClient.FeedEntry {
    ClawJSProfileClient.FeedEntry(
        blockId: id,
        vertical: "work",
        owner: .init(rootPubkey: "\(id)-root", handle: makeHandle(alias: id)),
        publishedAt: 1,
        preview: [:]
    )
}

private func makeChatThread(id: String) -> ClawJSProfileClient.ChatThread {
    ClawJSProfileClient.ChatThread(
        peer: .init(rootPubkey: "\(id)-root", handle: makeHandle(alias: id)),
        lastMessageAt: 1,
        unreadCount: 0
    )
}

private func makeChatMessage(id: String) -> ClawJSProfileClient.ChatMessage {
    ClawJSProfileClient.ChatMessage(
        id: id,
        threadPeerRootPubkey: "\(id)-root",
        fromMe: false,
        body: id,
        sentAt: 1,
        draftFromAgent: false
    )
}

private func makeIntent(id: String) -> ClawJSProfileClient.DiscoveredIntent {
    ClawJSProfileClient.DiscoveredIntent(
        intentId: id,
        vertical: "work",
        side: "supply",
        fields: [:],
        geoZone: nil,
        tag: nil,
        priceBand: nil,
        expiresAt: 1,
        ownerHandle: makeHandle(alias: id)
    )
}

private final class FakeProfileClient: ClawJSProfileClienting, @unchecked Sendable {
    var indexBearerToken: String?
    var onMe: () async throws -> ClawJSProfileClient.Profile? = { nil }
    var onListFeed: (String?, String?, String?, Int) async throws -> [ClawJSProfileClient.FeedEntry] = { _, _, _, _ in [] }
    var onListMessages: (String, Int, Int?) async throws -> [ClawJSProfileClient.ChatMessage] = { peer, _, _ in
        [makeChatMessage(id: peer)]
    }
    var onSendMessage: (String, String) async throws -> ClawJSProfileClient.ChatMessage = { _, body in
        makeChatMessage(id: body)
    }
    var onSetHandle: (String) async throws -> ClawJSProfileClient.Profile = { alias in
        makeProfile(alias: alias)
    }
    var onCreateBlock: (ClawJSProfileClient.CreateBlockInput) async throws -> ClawJSProfileClient.Block = { input in
        makeBlock(id: input.archetype)
    }

    func initProfile(alias: String, mnemonic: String?, passphrase: String?) async throws -> ClawJSProfileClient.InitResponse {
        ClawJSProfileClient.InitResponse(profile: makeProfile(alias: alias), mnemonic: mnemonic ?? "mnemonic")
    }

    func me() async throws -> ClawJSProfileClient.Profile? {
        try await onMe()
    }

    func setHandle(alias: String) async throws -> ClawJSProfileClient.Profile {
        try await onSetHandle(alias)
    }

    func listBlocks(vertical: String?) async throws -> [ClawJSProfileClient.Block] {
        [makeBlock(id: vertical ?? "block")]
    }

    func createBlock(_ input: ClawJSProfileClient.CreateBlockInput) async throws -> ClawJSProfileClient.Block {
        try await onCreateBlock(input)
    }

    func deleteBlock(_ blockId: String) async throws {}

    func listGroups() async throws -> [ClawJSProfileClient.Group] {
        [makeGroup(id: "group")]
    }

    func createGroup(id: String, label: String?) async throws -> ClawJSProfileClient.Group {
        makeGroup(id: id)
    }

    func addMember(groupId: String, rootPubkeyHex: String) async throws -> ClawJSProfileClient.Group {
        makeGroup(id: groupId)
    }

    func issueCapability(blockId: String, level: String, issuedToHex: String?, ttlSeconds: Int?) async throws -> ClawJSProfileClient.Capability {
        ClawJSProfileClient.Capability(capId: "cap", blockId: blockId, level: level, issuedTo: issuedToHex, issuedAt: 1, expiresAt: 2)
    }

    func listPeers() async throws -> [ClawJSProfileClient.PeerDirectoryEntry] {
        [.init(handle: makeHandle(alias: "peer"), trustedLocally: true)]
    }

    func pairByFingerprint(pairingLink: String) async throws -> ClawJSProfileClient.Handle {
        makeHandle(alias: pairingLink)
    }

    func listFeed(vertical: String?, groupId: String?, keywords: String?, limit: Int) async throws -> [ClawJSProfileClient.FeedEntry] {
        try await onListFeed(vertical, groupId, keywords, limit)
    }

    func listChats() async throws -> [ClawJSProfileClient.ChatThread] {
        [makeChatThread(id: "chat")]
    }

    func listMessages(peer: String, limit: Int, before: Int?) async throws -> [ClawJSProfileClient.ChatMessage] {
        try await onListMessages(peer, limit, before)
    }

    func sendMessage(peer: String, body: String) async throws -> ClawJSProfileClient.ChatMessage {
        try await onSendMessage(peer, body)
    }

    func discoveredIntents(vertical: String?, geoZone: String?, tag: String?, priceBand: Int?, limit: Int) async throws -> [ClawJSProfileClient.DiscoveredIntent] {
        [makeIntent(id: vertical ?? "intent")]
    }

    func expressInterest(intentId: String, template: String?) async throws -> ClawJSProfileClient.ExpressInterestResult {
        ClawJSProfileClient.ExpressInterestResult(capabilityId: intentId, mailboxMessageId: "message")
    }
}
