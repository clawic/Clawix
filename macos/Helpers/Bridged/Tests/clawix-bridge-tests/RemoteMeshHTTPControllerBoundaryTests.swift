import XCTest
@testable import clawix_bridge
import ClawixCore
import ClawixEngine

@MainActor
final class RemoteMeshHTTPControllerBoundaryTests: XCTestCase {
    func testLoopbackOnlyCompatibilityRoutesDoNotHandleNonLoopbackRequests() async throws {
        let controller = makeController()
        let cases: [(String, String, Data)] = [
            ("GET", ClawixMeshRoute.peers, Data()),
            ("GET", ClawixMeshRoute.workspaces, Data()),
            ("GET", "\(ClawixMeshRoute.jobsPrefix)job-1", Data()),
            ("POST", ClawixMeshRoute.peers, Data("{}".utf8)),
            ("POST", ClawixMeshRoute.workspaces, Data("{}".utf8)),
            ("POST", ClawixMeshRoute.link, Data("{}".utf8)),
            ("POST", ClawixMeshRoute.remoteJobs, Data("{}".utf8)),
        ]

        for (method, path, body) in cases {
            let response = await controller.handle(
                HTTPRequest(method: method, path: path, body: body),
                isLoopback: false
            )
            XCTAssertNil(response, "\(method) \(path) must stay loopback-only")
        }
    }

    func testPeerSignedCompatibilityRoutesFailClosedForInvalidRemoteEnvelopes() async throws {
        let controller = makeController()
        let routes = [
            ClawixMeshRoute.jobs,
            ClawixMeshRoute.jobsCancel,
            ClawixMeshRoute.jobsEvents,
        ]

        for route in routes {
            let response = await controller.handle(
                HTTPRequest(method: "POST", path: route, body: Data("{}".utf8)),
                isLoopback: false
            )
            XCTAssertEqual(response?.status, 400, "invalid peer envelope should fail closed for \(route)")
        }
    }

    func testPublicIdentityAndPairingRoutesRemainExplicitlyNonLoopback() async throws {
        let controller = makeController()

        let identity = await controller.handle(
            HTTPRequest(method: "GET", path: ClawixMeshRoute.identity, body: Data()),
            isLoopback: false
        )
        XCTAssertEqual(identity?.status, 200)

        let invalidPair = await controller.handle(
            HTTPRequest(method: "POST", path: ClawixMeshRoute.pair, body: Data("{}".utf8)),
            isLoopback: false
        )
        XCTAssertEqual(invalidPair?.status, 400)
    }

    private func makeController() -> RemoteMeshHTTPController {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawix-remote-mesh-boundary-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "clawix-remote-mesh-boundary-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let pairing = PairingService(defaults: defaults)
        let store = RemoteMeshStore(root: root)
        let identity = RemoteMeshIdentity(root: root, displayName: "Boundary Test Mac")
        let host = DaemonEngineHost(pairing: pairing, environment: [:])
        return RemoteMeshHTTPController(
            identity: identity,
            store: store,
            host: host,
            pairing: pairing,
            bridgePort: ClawixBridgeEndpointResolver.defaultWebSocketPort,
            httpPort: ClawixBridgeEndpointResolver.defaultHTTPPort
        )
    }
}
