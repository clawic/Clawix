import Foundation

enum ClawJSServiceEndpointResolver {
    static let loopbackHost = "127.0.0.1"

    static func origin(for service: ClawJSService, scheme: String = "http") -> URL {
        loopbackURL(port: service.port, scheme: scheme)
    }

    static func webSocketOrigin(for service: ClawJSService) -> URL {
        origin(for: service, scheme: "ws")
    }

    static func healthURL(for service: ClawJSService) -> URL {
        url(for: service, path: service.healthPath)
    }

    static func url(for service: ClawJSService, path: String, scheme: String = "http") -> URL {
        var components = baseComponents(port: service.port, scheme: scheme)
        components.path = path.hasPrefix("/") ? path : "/\(path)"
        guard let url = components.url else {
            preconditionFailure("Invalid ClawJS service URL for \(service.rawValue)")
        }
        return url
    }

    static func originString(for service: ClawJSService, scheme: String = "http") -> String {
        origin(for: service, scheme: scheme).absoluteString
    }

    static func loopbackURL(port: UInt16, scheme: String = "http") -> URL {
        let components = baseComponents(port: port, scheme: scheme)
        guard let url = components.url else {
            preconditionFailure("Invalid ClawJS loopback URL for port \(port)")
        }
        return url
    }

    private static func baseComponents(port: UInt16, scheme: String) -> URLComponents {
        var components = URLComponents()
        components.scheme = scheme
        components.host = loopbackHost
        components.port = Int(port)
        return components
    }
}
