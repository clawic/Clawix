import Foundation

public enum ClawixBridgeEndpointResolver {
    public static let loopbackHost = "127.0.0.1"
    public static let defaultWebSocketPort: UInt16 = 24_080
    public static let defaultHTTPPort: UInt16 = 24_081

    public static func webSocketURL(port: UInt16 = defaultWebSocketPort, path: String = "/") -> URL {
        var components = URLComponents()
        components.scheme = "ws"
        components.host = loopbackHost
        components.port = Int(port)
        components.path = path.hasPrefix("/") ? path : "/\(path)"
        guard let url = components.url else {
            preconditionFailure("Invalid Clawix bridge WebSocket URL for port \(port)")
        }
        return url
    }

    public static func httpOrigin(
        host: String = loopbackHost,
        port: UInt16 = defaultHTTPPort
    ) -> URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = Int(port)
        guard let url = components.url else {
            preconditionFailure("Invalid Clawix bridge HTTP origin for \(host):\(port)")
        }
        return url
    }
}
