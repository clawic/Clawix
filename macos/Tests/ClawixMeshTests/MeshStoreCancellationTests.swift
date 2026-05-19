import Foundation
import XCTest
import ClawixCore
@testable import Clawix

@MainActor
final class MeshStoreCancellationTests: XCTestCase {
    func testStartingSecondHostsRefreshSuppressesStaleRefresh() async {
        let staleStarted = expectation(description: "Stale hosts refresh started")
        let staleCancelled = expectation(description: "Stale hosts refresh cancelled")
        let staleReturned = expectation(description: "Stale hosts refresh should not return")
        staleReturned.isInverted = true
        let freshReturned = expectation(description: "Fresh hosts refresh returned")
        let client = FakeMeshClient()
        var calls = 0
        client.onIdentity = {
            calls += 1
            if calls == 1 {
                staleStarted.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 100_000_000)
                    staleReturned.fulfill()
                    return MeshTestFixtures.nodeIdentity(displayName: "Stale Mac")
                } catch is CancellationError {
                    staleCancelled.fulfill()
                    throw CancellationError()
                }
            }
            freshReturned.fulfill()
            return MeshTestFixtures.nodeIdentity(displayName: "Fresh Mac")
        }
        let store = MeshStore(client: client)

        let first = Task { await store.refreshAll() }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task { await store.refreshAll() }

        await fulfillment(of: [freshReturned, staleCancelled, staleReturned], timeout: 1)
        await first.value
        await second.value
        XCTAssertEqual(store.identity?.displayName, "Fresh Mac")
        XCTAssertFalse(store.isRefreshing)
    }

    func testCancelHostsSurfaceWorkCancelsInFlightRefresh() async {
        let refreshStarted = expectation(description: "Hosts refresh started")
        let refreshCancelled = expectation(description: "Hosts refresh cancelled after teardown")
        let refreshReturned = expectation(description: "Hosts refresh should not return after teardown")
        refreshReturned.isInverted = true
        let client = FakeMeshClient()
        client.onIdentity = {
            refreshStarted.fulfill()
            do {
                try await Task.sleep(nanoseconds: 50_000_000)
                refreshReturned.fulfill()
                return MeshTestFixtures.nodeIdentity(displayName: "Late Mac")
            } catch is CancellationError {
                refreshCancelled.fulfill()
                throw CancellationError()
            }
        }
        let store = MeshStore(client: client)

        let task = Task { await store.refreshAll() }
        await fulfillment(of: [refreshStarted], timeout: 1)

        store.cancelHostsSurfaceWork()

        await fulfillment(of: [refreshCancelled, refreshReturned], timeout: 1)
        await task.value
        XCTAssertNil(store.identity)
        XCTAssertTrue(store.peers.isEmpty)
        XCTAssertTrue(store.workspaces.isEmpty)
        XCTAssertFalse(store.isRefreshing)
    }

    func testCancelHostsSurfaceWorkCancelsInFlightPairing() async {
        let linkStarted = expectation(description: "Pairing link started")
        let linkCancelled = expectation(description: "Pairing link cancelled after teardown")
        let linkReturned = expectation(description: "Pairing link should not return after teardown")
        linkReturned.isInverted = true
        let peerRefreshStarted = expectation(description: "Stale pairing refresh should not start")
        peerRefreshStarted.isInverted = true
        let client = FakeMeshClient()
        client.onLink = { _, _, _, _ in
            linkStarted.fulfill()
            do {
                try await Task.sleep(nanoseconds: 50_000_000)
                linkReturned.fulfill()
                return MeshTestFixtures.peer(nodeId: "late-peer", displayName: "Late Peer")
            } catch is CancellationError {
                linkCancelled.fulfill()
                throw CancellationError()
            }
        }
        client.onPeers = {
            peerRefreshStarted.fulfill()
            return [MeshTestFixtures.peer(nodeId: "unexpected")]
        }
        let store = MeshStore(client: client)

        let task = Task {
            await store.pair(host: "127.0.0.1", httpPort: 24081, token: "token", profile: .scoped)
        }
        await fulfillment(of: [linkStarted], timeout: 1)

        store.cancelHostsSurfaceWork()

        await fulfillment(of: [linkCancelled, linkReturned, peerRefreshStarted], timeout: 1)
        await task.value
        XCTAssertTrue(store.peers.isEmpty)
        XCTAssertNil(store.lastPairingResult)
    }

    func testStandalonePeerRefreshDoesNotCancelInFlightPairing() async {
        let linkStarted = expectation(description: "Pairing link started")
        let linkReturned = expectation(description: "Pairing link returned")
        let pairedPeer = MeshTestFixtures.peer(nodeId: "paired-peer", displayName: "Paired Peer")
        let client = FakeMeshClient()
        var peerRefreshes = 0
        client.onLink = { _, _, _, _ in
            linkStarted.fulfill()
            try? await Task.sleep(nanoseconds: 50_000_000)
            linkReturned.fulfill()
            return pairedPeer
        }
        client.onPeers = {
            peerRefreshes += 1
            return peerRefreshes == 1 ? [] : [pairedPeer]
        }
        let store = MeshStore(client: client)

        let pairing = Task {
            await store.pair(host: "127.0.0.1", httpPort: 24081, token: "token", profile: .scoped)
        }
        await fulfillment(of: [linkStarted], timeout: 1)

        await store.refreshPeers()

        await fulfillment(of: [linkReturned], timeout: 1)
        await pairing.value
        XCTAssertEqual(store.peers.map(\.nodeId), ["paired-peer"])
        XCTAssertEqual(store.lastPairingResult, .success(displayName: "Paired Peer"))
    }

    func testCancelHostsSurfaceWorkCancelsInFlightHostRemoval() async {
        let removalStarted = expectation(description: "Host removal started")
        let removalCancelled = expectation(description: "Host removal cancelled after teardown")
        let removalReturned = expectation(description: "Host removal should not return after teardown")
        removalReturned.isInverted = true
        let peerRefreshStarted = expectation(description: "Stale host removal refresh should not start")
        peerRefreshStarted.isInverted = true
        let client = FakeMeshClient()
        client.onRemoveHost = { nodeId in
            XCTAssertEqual(nodeId, "late-host")
            removalStarted.fulfill()
            do {
                try await Task.sleep(nanoseconds: 50_000_000)
                removalReturned.fulfill()
            } catch is CancellationError {
                removalCancelled.fulfill()
                throw CancellationError()
            }
        }
        client.onPeers = {
            peerRefreshStarted.fulfill()
            return [MeshTestFixtures.peer(nodeId: "unexpected")]
        }
        let store = MeshStore(client: client)

        let task = Task {
            await store.removeHost(nodeId: "late-host")
        }
        await fulfillment(of: [removalStarted], timeout: 1)

        store.cancelHostsSurfaceWork()

        await fulfillment(of: [removalCancelled, removalReturned, peerRefreshStarted], timeout: 1)
        let result = await task.value
        switch result {
        case .success:
            XCTFail("Cancelled host removal should not succeed")
        case .failure(let error):
            XCTAssertEqual(error, .cancelled)
        }
        XCTAssertTrue(store.peers.isEmpty)
        XCTAssertNil(store.lastError)
    }

    func testCancelHostsSurfaceWorkCancelsInFlightWorkspaceAdd() async {
        let addStarted = expectation(description: "Workspace add started")
        let addCancelled = expectation(description: "Workspace add cancelled after teardown")
        let addReturned = expectation(description: "Workspace add should not return after teardown")
        addReturned.isInverted = true
        let workspaceRefreshStarted = expectation(description: "Stale workspace reload should not start")
        workspaceRefreshStarted.isInverted = true
        let client = FakeMeshClient()
        client.onAddWorkspace = { path, label in
            XCTAssertEqual(path, "/tmp/late")
            XCTAssertNil(label)
            addStarted.fulfill()
            do {
                try await Task.sleep(nanoseconds: 50_000_000)
                addReturned.fulfill()
                return MeshTestFixtures.workspace(path: path, label: "late")
            } catch is CancellationError {
                addCancelled.fulfill()
                throw CancellationError()
            }
        }
        client.onWorkspaces = {
            workspaceRefreshStarted.fulfill()
            return [MeshTestFixtures.workspace(path: "/tmp/unexpected")]
        }
        let store = MeshStore(client: client)

        let task = Task { await store.addWorkspace(path: "/tmp/late") }
        await fulfillment(of: [addStarted], timeout: 1)

        store.cancelHostsSurfaceWork()

        await fulfillment(of: [addCancelled, addReturned, workspaceRefreshStarted], timeout: 1)
        await task.value
        XCTAssertTrue(store.workspaces.isEmpty)
        XCTAssertNil(store.lastError)
    }
}

private final class FakeMeshClient: MeshClienting {
    var onIdentity: () async throws -> NodeIdentity = {
        MeshTestFixtures.nodeIdentity()
    }
    var onPeers: () async throws -> [PeerRecord] = {
        []
    }
    var onLink: (String, Int, String, PeerPermissionProfile) async throws -> PeerRecord = { _, _, _, _ in
        MeshTestFixtures.peer()
    }
    var onWorkspaces: () async throws -> [RemoteWorkspace] = {
        []
    }
    var onAddWorkspace: (String, String?) async throws -> RemoteWorkspace = { path, label in
        MeshTestFixtures.workspace(path: path, label: label ?? "workspace")
    }
    var onStartRemoteJob: (String, String, String, String?) async throws -> RemoteJob = { _, workspacePath, prompt, jobId in
        RemoteJob(
            id: jobId ?? "job",
            requesterNodeId: "node-this",
            workspacePath: workspacePath,
            prompt: prompt,
            status: .queued
        )
    }
    var onJob: (String) async throws -> MeshClient.JobOutput = { _ in
        MeshClient.JobOutput(job: nil, events: [])
    }
    var onUpsertHost: (HostInput, SshSecretInput?) async throws -> PeerRecord = { host, _ in
        MeshTestFixtures.peer(nodeId: host.id ?? "host", displayName: host.displayName)
    }
    var onRevokePeer: (String) async throws -> Void = { _ in }
    var onUnrevokePeer: (String) async throws -> Void = { _ in }
    var onRemoveHost: (String) async throws -> Void = { _ in }

    func identity() async throws -> NodeIdentity {
        try await onIdentity()
    }

    func peers() async throws -> [PeerRecord] {
        try await onPeers()
    }

    func link(host: String, httpPort: Int, token: String, profile: PeerPermissionProfile) async throws -> PeerRecord {
        try await onLink(host, httpPort, token, profile)
    }

    func workspaces() async throws -> [RemoteWorkspace] {
        try await onWorkspaces()
    }

    func addWorkspace(path: String, label: String?) async throws -> RemoteWorkspace {
        try await onAddWorkspace(path, label)
    }

    func startRemoteJob(peerId: String, workspacePath: String, prompt: String, jobId: String?) async throws -> RemoteJob {
        try await onStartRemoteJob(peerId, workspacePath, prompt, jobId)
    }

    func job(id: String) async throws -> MeshClient.JobOutput {
        try await onJob(id)
    }

    func upsertHost(_ host: HostInput, sshSecret: SshSecretInput?) async throws -> PeerRecord {
        try await onUpsertHost(host, sshSecret)
    }

    func revokePeer(nodeId: String) async throws {
        try await onRevokePeer(nodeId)
    }

    func unrevokePeer(nodeId: String) async throws {
        try await onUnrevokePeer(nodeId)
    }

    func removeHost(nodeId: String) async throws {
        try await onRemoveHost(nodeId)
    }
}
