import Foundation
import XCTest
@testable import ClawixEngine

@MainActor
final class MeshNodeFactoryRegistryTests: XCTestCase {
    func testRegisteredFactoryOverridesStubAndClearRestoresFallback() async throws {
        let relayURL = try XCTUnwrap(URL(string: "https://relay.example.test"))
        MeshNodeFactoryRegistry.register { relayURL in
            TestMeshNode(nodeID: MeshNodeID("factory-node"), relayURL: relayURL)
        }
        defer { MeshNodeFactoryRegistry.clear() }

        let registered = try await MeshKit.makeNode(relayURL: relayURL)

        let testNode = try XCTUnwrap(registered as? TestMeshNode)
        XCTAssertEqual(testNode.nodeID, MeshNodeID("factory-node"))
        XCTAssertEqual(testNode.relayURL, relayURL)

        MeshNodeFactoryRegistry.clear()
        let fallback = try await MeshKit.makeNode(relayURL: relayURL)
        XCTAssertFalse(fallback is TestMeshNode)
        let endpoint = await fallback.describeEndpoint()
        XCTAssertEqual(endpoint.relayURL, relayURL)
    }
}

private final class TestMeshNode: MeshNode {
    let nodeID: MeshNodeID
    let relayURL: URL?

    init(nodeID: MeshNodeID, relayURL: URL?) {
        self.nodeID = nodeID
        self.relayURL = relayURL
    }

    func start() async throws {}
    func stop() async {}

    func describeEndpoint() async -> (relayURL: URL?, publicAddresses: [String]) {
        (relayURL, [])
    }

    func connect(_ remote: MeshRemote) async throws -> MeshBiStream {
        throw MeshKitError.unsupported("test node has no streams")
    }

    func onInbound(_ handler: @escaping (MeshBiStream, MeshNodeID) -> Void) {}
}
