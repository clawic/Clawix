import Foundation
import XCTest
@testable import Clawix

@MainActor
final class MarketplaceManagerCancellationTests: XCTestCase {
    func testStartingSecondRefreshCancelsStaleMarketplaceLoad() async {
        let staleStarted = expectation(description: "Stale marketplace refresh started")
        let staleCancelled = expectation(description: "Stale marketplace refresh cancelled")
        let freshReturned = expectation(description: "Fresh marketplace refresh returned")
        let client = FakeMarketplaceClient()
        var calls = 0
        client.onListRoots = {
            calls += 1
            if calls == 1 {
                staleStarted.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    staleCancelled.fulfill()
                    throw CancellationError()
                }
                return [makeRoot(id: "stale")]
            }
            freshReturned.fulfill()
            return [makeRoot(id: "fresh")]
        }
        let manager = MarketplaceManager(client: client, tokenOperation: { "token" })

        let first = Task { await manager.refresh() }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task { await manager.refresh() }

        await fulfillment(of: [staleCancelled, freshReturned], timeout: 1)
        await first.value
        await second.value
        XCTAssertEqual(manager.roots.map(\.id), ["fresh"])
        XCTAssertEqual(manager.state, .ready)
    }

    func testStaleMarketplaceRefreshCannotOverwriteFreshState() async {
        let staleStarted = expectation(description: "Stale marketplace refresh started")
        let staleReturned = expectation(description: "Stale marketplace refresh returned")
        let freshReturned = expectation(description: "Fresh marketplace refresh returned")
        let client = FakeMarketplaceClient()
        var calls = 0
        client.onListRoots = {
            calls += 1
            if calls == 1 {
                staleStarted.fulfill()
                try? await Task.sleep(nanoseconds: 100_000_000)
                staleReturned.fulfill()
                return [makeRoot(id: "stale")]
            }
            freshReturned.fulfill()
            return [makeRoot(id: "fresh")]
        }
        let manager = MarketplaceManager(client: client, tokenOperation: { "token" })

        let first = Task { await manager.refresh() }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task { await manager.refresh() }

        await fulfillment(of: [freshReturned, staleReturned], timeout: 1)
        await first.value
        await second.value
        XCTAssertEqual(manager.roots.map(\.id), ["fresh"])
        XCTAssertEqual(manager.state, .ready)
    }

    func testCancelSurfaceWorkSuppressesInFlightMarketplaceRefresh() async {
        let refreshStarted = expectation(description: "Marketplace refresh started")
        let refreshCancelled = expectation(description: "Marketplace refresh cancelled")
        let client = FakeMarketplaceClient()
        client.onListRoots = {
            refreshStarted.fulfill()
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                refreshCancelled.fulfill()
                throw CancellationError()
            }
            return [makeRoot(id: "stale")]
        }
        let manager = MarketplaceManager(client: client, tokenOperation: { "token" })

        let task = Task { await manager.refresh() }
        await fulfillment(of: [refreshStarted], timeout: 1)

        manager.cancelSurfaceWork()

        await fulfillment(of: [refreshCancelled], timeout: 1)
        await task.value
        XCTAssertTrue(manager.roots.isEmpty)
    }

    func testCancelSurfaceWorkCancelsInFlightMarkRead() async {
        let markStarted = expectation(description: "Marketplace mark read started")
        let markCancelled = expectation(description: "Marketplace mark read cancelled")
        let client = FakeMarketplaceClient()
        client.onMarkRead = { _ in
            markStarted.fulfill()
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                markCancelled.fulfill()
                throw CancellationError()
            }
            throw MarketplaceTestError.serviceNotReady
        }
        let manager = MarketplaceManager(client: client, tokenOperation: { "token" })

        let task = Task { await manager.markRead(messageId: "message") }
        await fulfillment(of: [markStarted], timeout: 1)

        manager.cancelSurfaceWork()

        await fulfillment(of: [markCancelled], timeout: 1)
        await task.value
        XCTAssertNil(manager.state.errorMessage)
    }

    func testCancelSurfaceWorkCancelsInFlightIntentStatusUpdate() async {
        let updateStarted = expectation(description: "Marketplace intent update started")
        let updateCancelled = expectation(description: "Marketplace intent update cancelled")
        let refreshStarted = expectation(description: "Marketplace refresh should not start")
        refreshStarted.isInverted = true
        let client = FakeMarketplaceClient()
        client.onUpdateIntentStatus = { _, _ in
            updateStarted.fulfill()
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                updateCancelled.fulfill()
                throw CancellationError()
            }
        }
        client.onListRoots = {
            refreshStarted.fulfill()
            return [makeRoot(id: "unexpected")]
        }
        let manager = MarketplaceManager(client: client, tokenOperation: { "token" })

        let task = Task { await manager.updateIntentStatus(id: "intent", status: "withdrawn") }
        await fulfillment(of: [updateStarted], timeout: 1)

        manager.cancelSurfaceWork()

        await fulfillment(of: [updateCancelled, refreshStarted], timeout: 1)
        await task.value
        XCTAssertTrue(manager.roots.isEmpty)
        XCTAssertNil(manager.state.errorMessage)
    }
}

private extension MarketplaceManager.State {
    var errorMessage: String? {
        if case .error(let message) = self { return message }
        return nil
    }
}

private enum MarketplaceTestError: Error {
    case serviceNotReady
}

private func makeRoot(id: String) -> ClawJSMarketplaceClient.RootKey {
    ClawJSMarketplaceClient.RootKey(
        id: id,
        pubkey: "\(id)-pubkey",
        label: id,
        createdAt: "2026-05-19T00:00:00Z",
        revokedAt: nil
    )
}

private func makeDevice(id: String = "device") -> ClawJSMarketplaceClient.DeviceKey {
    ClawJSMarketplaceClient.DeviceKey(
        id: id,
        rootKeyId: "root",
        pubkey: "\(id)-pubkey",
        deviceName: id,
        certificateCbor: "cert",
        createdAt: "2026-05-19T00:00:00Z",
        revokedAt: nil
    )
}

private func makeRole(id: String = "role") -> ClawJSMarketplaceClient.RoleKey {
    ClawJSMarketplaceClient.RoleKey(
        id: id,
        rootKeyId: "root",
        pubkey: "\(id)-pubkey",
        roleName: id,
        vertical: "work",
        certificateCbor: "cert",
        createdAt: "2026-05-19T00:00:00Z",
        revokedAt: nil
    )
}

private func makeIntent(id: String, side: String, provenance: String, roleKeyId: String? = "role") -> ClawJSMarketplaceClient.Intent {
    ClawJSMarketplaceClient.Intent(
        id: id,
        intentIdHash: "\(id)-hash",
        side: side,
        roleKeyId: roleKeyId,
        vertical: "work",
        payload: .object(["title": .string(id)]),
        visibilityLevels: [:],
        provenance: provenance,
        observedSource: nil,
        observedExternalUrl: nil,
        status: "published",
        expiresAt: nil,
        createdAt: "2026-05-19T00:00:00Z",
        publishedAt: "2026-05-19T00:00:00Z",
        withdrawnAt: nil
    )
}

private func makeReceipt(id: String = "receipt") -> ClawJSMarketplaceClient.MatchReceipt {
    ClawJSMarketplaceClient.MatchReceipt(
        id: id,
        receiptHash: "\(id)-hash",
        myRoleKeyId: "role",
        peerRolePubkey: "peer",
        offerIntentId: "offer",
        wantIntentId: "want",
        reachedLevel: 1,
        fieldsRevealed: [],
        contactHandover: nil,
        status: "signed",
        proposedAt: "2026-05-19T00:00:00Z",
        signedAt: "2026-05-19T00:00:00Z",
        rejectedAt: nil
    )
}

private func makeInbound(id: String = "message") -> ClawJSMarketplaceClient.InboundMessage {
    ClawJSMarketplaceClient.InboundMessage(
        id: id,
        recipientRoleKeyId: "role",
        senderPubkey: "peer",
        threadId: nil,
        intentIdRef: "offer",
        kind: "inquiry",
        plaintext: .object(["body": .string(id)]),
        receivedAt: "2026-05-19T00:00:00Z",
        readAt: nil
    )
}

private func makePeerLevel(id: String = "peer") -> ClawJSMarketplaceClient.PeerLevel {
    ClawJSMarketplaceClient.PeerLevel(
        id: id,
        myRoleKeyId: "role",
        peerPubkey: "\(id)-pubkey",
        intentId: "offer",
        currentLevel: 1,
        proofs: nil,
        lastUpdatedAt: "2026-05-19T00:00:00Z"
    )
}

private func makeBroker(id: String = "broker") -> ClawJSMarketplaceClient.Broker {
    ClawJSMarketplaceClient.Broker(
        id: id,
        brokerPubkey: "\(id)-pubkey",
        endpoints: [],
        verticalsSupported: ["work"],
        trustLocal: true,
        lastSeenAt: "2026-05-19T00:00:00Z"
    )
}

private final class FakeMarketplaceClient: ClawJSMarketplaceClienting, @unchecked Sendable {
    var indexBearerToken: String?
    var onListRoots: () async throws -> [ClawJSMarketplaceClient.RootKey] = {
        [makeRoot(id: "root")]
    }
    var onUpdateIntentStatus: (String, String) async throws -> Void = { _, _ in }
    var onMarkRead: (String) async throws -> Void = { _ in }

    func listRoots() async throws -> [ClawJSMarketplaceClient.RootKey] {
        try await onListRoots()
    }

    func listDevices(rootKeyId: String?) async throws -> [ClawJSMarketplaceClient.DeviceKey] {
        [makeDevice()]
    }

    func listRoles(rootKeyId: String?, vertical: String?) async throws -> [ClawJSMarketplaceClient.RoleKey] {
        [makeRole()]
    }

    func listIntents(filter: ClawJSMarketplaceClient.IntentFilter) async throws -> [ClawJSMarketplaceClient.Intent] {
        if filter.provenance == "observed" {
            return [makeIntent(id: "observed", side: "offer", provenance: "observed", roleKeyId: nil)]
        }
        return [makeIntent(id: filter.side ?? "intent", side: filter.side ?? "offer", provenance: filter.provenance ?? "native")]
    }

    func updateIntentStatus(id: String, status: String) async throws {
        try await onUpdateIntentStatus(id, status)
    }

    func listMatchReceipts(myRoleKeyId: String?, status: String?) async throws -> [ClawJSMarketplaceClient.MatchReceipt] {
        [makeReceipt()]
    }

    func listInbound(recipientRoleKeyId: String?) async throws -> [ClawJSMarketplaceClient.InboundMessage] {
        [makeInbound()]
    }

    func markRead(messageId: String) async throws {
        try await onMarkRead(messageId)
    }

    func listPeerLevels(myRoleKeyId: String?) async throws -> [ClawJSMarketplaceClient.PeerLevel] {
        [makePeerLevel()]
    }

    func listBrokers(vertical: String?) async throws -> [ClawJSMarketplaceClient.Broker] {
        [makeBroker()]
    }
}
