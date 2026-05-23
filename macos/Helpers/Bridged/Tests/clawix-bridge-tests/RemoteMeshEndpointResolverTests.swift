import XCTest
@testable import clawix_bridge
import ClawixCore

final class RemoteMeshEndpointResolverTests: XCTestCase {
    func testBuildsIdentityURLFromTypedMeshRoute() {
        let url = RemoteMeshEndpointResolver.url(
            host: "remote.example.test",
            httpPort: 25081,
            path: ClawixMeshRoute.identity
        )

        XCTAssertEqual(url.scheme, "http")
        XCTAssertEqual(url.host, "remote.example.test")
        XCTAssertEqual(url.port, 25081)
        XCTAssertEqual(url.path, "/v1/mesh/identity")
        XCTAssertEqual(url.absoluteString, "http://remote.example.test:25081/v1/mesh/identity")
    }

    func testNormalizesRoutePathWithoutLeadingSlash() {
        let url = RemoteMeshEndpointResolver.url(
            host: "127.0.0.1",
            httpPort: 24081,
            path: "v1/mesh/pair"
        )

        XCTAssertEqual(url.path, "/v1/mesh/pair")
        XCTAssertEqual(url.absoluteString, "http://127.0.0.1:24081/v1/mesh/pair")
    }

    func testBuildsRemoteJobURLFromTypedMeshRoute() {
        let url = RemoteMeshEndpointResolver.url(
            host: "node-a.local",
            httpPort: 24181,
            path: ClawixMeshRoute.jobs
        )

        XCTAssertEqual(url.path, "/v1/mesh/jobs")
        XCTAssertEqual(url.absoluteString, "http://node-a.local:24181/v1/mesh/jobs")
    }
}
