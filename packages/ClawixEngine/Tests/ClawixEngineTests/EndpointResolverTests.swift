import XCTest
@testable import ClawixEngine

final class EndpointResolverTests: XCTestCase {
    func testBridgeEndpointResolverUsesCanonicalLoopbackPorts() {
        XCTAssertEqual(ClawixBridgeEndpointResolver.loopbackHost, "127.0.0.1")
        XCTAssertEqual(ClawixBridgeEndpointResolver.defaultWebSocketPort, 24_080)
        XCTAssertEqual(ClawixBridgeEndpointResolver.defaultHTTPPort, 24_081)
        XCTAssertEqual(
            ClawixBridgeEndpointResolver.webSocketURL().absoluteString,
            "ws://127.0.0.1:24080/"
        )
        XCTAssertEqual(
            ClawixBridgeEndpointResolver.httpOrigin().absoluteString,
            "http://127.0.0.1:24081"
        )
    }

    func testAudioEndpointResolverUsesCanonicalLoopbackOrigin() {
        XCTAssertEqual(ClawJSAudioEndpointResolver.loopbackHost, "127.0.0.1")
        XCTAssertEqual(ClawJSAudioEndpointResolver.defaultPort, clawJSAudioDefaultPort)
        XCTAssertEqual(
            ClawJSAudioEndpointResolver.origin().absoluteString,
            "http://127.0.0.1:7794"
        )
    }
}
