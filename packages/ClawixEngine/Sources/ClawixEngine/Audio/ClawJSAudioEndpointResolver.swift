import Foundation

public enum ClawJSAudioEndpointResolver {
    public static let loopbackHost = "127.0.0.1"
    public static let defaultPort: UInt16 = 7_794

    public static func origin(port: UInt16 = defaultPort) -> URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = loopbackHost
        components.port = Int(port)
        guard let url = components.url else {
            preconditionFailure("Invalid ClawJS audio origin for port \(port)")
        }
        return url
    }
}
