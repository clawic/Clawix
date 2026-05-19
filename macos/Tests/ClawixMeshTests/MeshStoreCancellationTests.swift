import Foundation
import XCTest
import ClawixCore
@testable import Clawix

@MainActor
final class MeshStoreCancellationTests: XCTestCase {
    func testStartingSecondHostsRefreshSuppressesStaleRefresh() async {
        let staleStarted = expectation(description: "Stale hosts refresh started")
        let staleReturned = expectation(description: "Stale hosts refresh returned")
        let freshReturned = expectation(description: "Fresh hosts refresh returned")
        let client = FakeMeshClient()
        var calls = 0
        client.onIdentity = {
            calls += 1
            if calls == 1 {
                staleStarted.fulfill()
                try? await Task.sleep(nanoseconds: 100_000_000)
                staleReturned.fulfill()
                return MeshTestFixtures.nodeIdentity(displayName: "Stale Mac")
            }
            freshReturned.fulfill()
            return MeshTestFixtures.nodeIdentity(displayName: "Fresh Mac")
        }
        let store = MeshStore(client: client)

        let first = Task { await store.refreshAll() }
        await fulfillment(of: [staleStarted], timeout: 1)

        let second = Task { await store.refreshAll() }

        await fulfillment(of: [freshReturned, staleReturned], timeout: 1)
        await first.value
        await second.value
        XCTAssertEqual(store.identity?.displayName, "Fresh Mac")
        XCTAssertFalse(store.isRefreshing)
    }

    func testCancelHostsSurfaceWorkSuppressesInFlightRefresh() async {
        let refreshStarted = expectation(description: "Hosts refresh started")
        let refreshReturned = expectation(description: "Hosts refresh returned after teardown")
        let client = FakeMeshClient()
        client.onIdentity = {
            refreshStarted.fulfill()
            try? await Task.sleep(nanoseconds: 50_000_000)
            refreshReturned.fulfill()
            return MeshTestFixtures.nodeIdentity(displayName: "Late Mac")
        }
        let store = MeshStore(client: client)

        let task = Task { await store.refreshAll() }
        await fulfillment(of: [refreshStarted], timeout: 1)

        store.cancelHostsSurfaceWork()

        await fulfillment(of: [refreshReturned], timeout: 1)
        await task.value
        XCTAssertNil(store.identity)
        XCTAssertTrue(store.peers.isEmpty)
        XCTAssertTrue(store.workspaces.isEmpty)
        XCTAssertFalse(store.isRefreshing)
    }

    func testCancelHostsSurfaceWorkSuppressesInFlightPairingResult() async {
        let linkStarted = expectation(description: "Pairing link started")
        let linkReturned = expectation(description: "Pairing link returned after teardown")
        let peerRefreshStarted = expectation(description: "Stale pairing refresh should not start")
        peerRefreshStarted.isInverted = true
        let client = FakeMeshClient()
        client.onLink = { _, _, _, _ in
            linkStarted.fulfill()
            try? await Task.sleep(nanoseconds: 50_000_000)
            linkReturned.fulfill()
            return MeshTestFixtures.peer(nodeId: "late-peer", displayName: "Late Peer")
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

        await fulfillment(of: [linkReturned, peerRefreshStarted], timeout: 1)
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

    func testCancelHostsSurfaceWorkSuppressesInFlightWorkspaceRefresh() async {
        let addStarted = expectation(description: "Workspace add started")
        let addReturned = expectation(description: "Workspace add returned after teardown")
        let workspaceRefreshStarted = expectation(description: "Stale workspace reload should not start")
        workspaceRefreshStarted.isInverted = true
        let client = FakeMeshClient()
        client.onAddWorkspace = { path, label in
            XCTAssertEqual(path, "/tmp/late")
            XCTAssertNil(label)
            addStarted.fulfill()
            try? await Task.sleep(nanoseconds: 50_000_000)
            addReturned.fulfill()
            return MeshTestFixtures.workspace(path: path, label: "late")
        }
        client.onWorkspaces = {
            workspaceRefreshStarted.fulfill()
            return [MeshTestFixtures.workspace(path: "/tmp/unexpected")]
        }
        let store = MeshStore(client: client)

        let task = Task { await store.addWorkspace(path: "/tmp/late") }
        await fulfillment(of: [addStarted], timeout: 1)

        store.cancelHostsSurfaceWork()

        await fulfillment(of: [addReturned, workspaceRefreshStarted], timeout: 1)
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
