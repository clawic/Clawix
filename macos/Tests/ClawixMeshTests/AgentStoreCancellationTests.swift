import Foundation
import XCTest
@testable import Clawix

@MainActor
final class AgentStoreCancellationTests: XCTestCase {
    func testSecondAgentReloadSuppressesFirstStaleSnapshot() async {
        let staleStarted = expectation(description: "Stale agent reload started")
        let staleReturned = expectation(description: "Stale agent reload returned")
        let freshReturned = expectation(description: "Fresh agent reload returned")
        var calls = 0
        let store = makeStore { _, _ in
            calls += 1
            if calls == 1 {
                staleStarted.fulfill()
                try? await Task.sleep(nanoseconds: 100_000_000)
                staleReturned.fulfill()
                return Self.snapshot(agentId: "agent.stale")
            }
            freshReturned.fulfill()
            return Self.snapshot(agentId: "agent.fresh")
        }

        let first = Task { await store.refresh() }
        await fulfillment(of: [staleStarted], timeout: 1)
        let second = Task { await store.refresh() }

        await fulfillment(of: [freshReturned, staleReturned], timeout: 1)
        await first.value
        await second.value
        XCTAssertEqual(store.agents.map(\.id), ["agent.fresh"])
        XCTAssertFalse(store.isLoading)
    }

    func testCancelSurfaceWorkSuppressesLateAgentReload() async {
        let loadStarted = expectation(description: "Agent reload started")
        let loadReturned = expectation(description: "Agent reload returned after teardown")
        let store = makeStore { _, _ in
            loadStarted.fulfill()
            try? await Task.sleep(nanoseconds: 50_000_000)
            loadReturned.fulfill()
            return Self.snapshot(agentId: "agent.closed")
        }

        let task = Task { await store.refresh() }
        await fulfillment(of: [loadStarted], timeout: 1)
        store.cancelSurfaceWork()

        await fulfillment(of: [loadReturned], timeout: 1)
        await task.value
        XCTAssertTrue(store.agents.isEmpty)
        XCTAssertFalse(store.isLoading)
    }

    func testUpsertAgentRemainsImmediatelyVisibleWhileReloadIsAsync() {
        let store = makeStore { _, _ in
            try? await Task.sleep(nanoseconds: 100_000_000)
            return Self.snapshot(agentId: "agent.disk")
        }
        let agent = Self.agent(id: "agent.instant")

        store.upsertAgent(agent)

        XCTAssertEqual(store.agents.map(\.id), ["agent.instant"])
        store.cancelSurfaceWork()
    }

    func testFrameworkUpsertAgentReturnsBeforeAsyncPersistenceCompletes() async {
        let upsertStarted = expectation(description: "Async framework upsert started")
        let upsertFinished = expectation(description: "Async framework upsert finished")
        let client = ClawJSFrameworkRecordsClient(
            runner: .init { _ in
                XCTFail("AgentStore should not use synchronous framework persistence for agent upsert")
                return Data(#"{"ok":true,"data":{"items":[]}}"#.utf8)
            },
            asyncRunner: .init { args in
                if args.starts(with: ["agents", "upsert", "agent.instant"]) {
                    upsertStarted.fulfill()
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    upsertFinished.fulfill()
                    return Data(#"{"ok":true,"data":{}}"#.utf8)
                }
                return Data(#"{"ok":true,"data":{"items":[]}}"#.utf8)
            }
        )
        let store = AgentStore(
            home: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true),
            frameworkClient: client,
            autoLoad: false
        )

        store.upsertAgent(Self.agent(id: "agent.instant"))

        XCTAssertEqual(store.agents.map(\.id), ["agent.instant"])
        await fulfillment(of: [upsertStarted], timeout: 1)
        XCTAssertEqual(store.agents.map(\.id), ["agent.instant"])
        await fulfillment(of: [upsertFinished], timeout: 1)
        store.cancelSurfaceWork()
    }

    private func makeStore(
        loadOperation: @escaping AgentStore.LoadOperation
    ) -> AgentStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return AgentStore(home: root, autoLoad: false, loadOperation: loadOperation)
    }

    private static func snapshot(agentId: String) -> AgentStore.AgentSnapshot {
        AgentStore.AgentSnapshot(
            agents: [agent(id: agentId)],
            personalities: [],
            skillCollections: [],
            connections: []
        )
    }

    private static func agent(id: String) -> Agent {
        var agent = Agent.defaultCodex()
        agent.id = id
        agent.name = id
        agent.isBuiltin = false
        return agent
    }
}
