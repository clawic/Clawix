import Foundation

/// Thin HTTP client for `@clawjs/runtime` on the stable runtime port.
/// It is intentionally scoped to the custom-app jobs bridge surface.
struct ClawJSRuntimeClient {
    enum Error: Swift.Error, LocalizedError {
        case serviceNotReady
        case invalidURL
        case http(status: Int, body: String?)
        case invalidJSON
        case transport(Swift.Error)

        var errorDescription: String? {
            switch self {
            case .serviceNotReady:
                return "ClawJS runtime service is not running."
            case .invalidURL:
                return "Could not build a URL for the runtime service."
            case .http(let status, let body):
                return "Runtime returned HTTP \(status)" + (body.map { ": \($0)" } ?? "")
            case .invalidJSON:
                return "Runtime returned a response that is not JSON."
            case .transport(let error):
                return "Could not reach runtime service: \(error.localizedDescription)"
            }
        }
    }

    var bearerToken: String?
    let origin: URL

    init(
        bearerToken: String? = nil,
        origin: URL = URL(string: "http://127.0.0.1:\(ClawJSService.runtime.port)")!
    ) {
        self.bearerToken = bearerToken
        self.origin = origin
    }

    func listJobEvents(jobId: String?, after: Int?, limit: Int?) async throws -> Any {
        let query = queryString([
            "jobId": jobId,
            "after": after.map(String.init),
            "limit": limit.map(String.init)
        ])
        return try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/runtime/jobs/events\(query)")
    }

    func listEventsForJob(id: String, after: Int?, limit: Int?) async throws -> Any {
        let query = queryString([
            "after": after.map(String.init),
            "limit": limit.map(String.init)
        ])
        return try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/runtime/jobs/\(Self.pathComponent(id))/events\(query)")
    }

    func startJob(kind: String, input: [String: Any], reason: String?) async throws -> Any {
        var body: [String: Any] = [
            "kind": kind,
            "input": input
        ]
        if let reason { body["reason"] = reason }
        return try await request(
            "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/runtime/jobs/start",
            method: "POST",
            body: body
        )
    }

    func cancelJob(id: String, reason: String?) async throws -> Any {
        var body: [String: Any] = [:]
        if let reason { body["reason"] = reason }
        return try await request(
            "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/runtime/jobs/\(Self.pathComponent(id))/cancel",
            method: "POST",
            body: body
        )
    }

    private func request(_ path: String, method: String = "GET", body: Any? = nil) async throws -> Any {
        guard let bearerToken else { throw Error.serviceNotReady }
        guard let url = URL(string: path, relativeTo: origin)?.absoluteURL else {
            throw Error.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: AnyJSONCodableBridge.swift(from: body))
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Error.transport(error)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Error.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
        guard !data.isEmpty else { return NSNull() }
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw Error.invalidJSON
        }
    }

    private func queryString(_ params: [String: String?]) -> String {
        let pairs = params.compactMap { key, value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return "\(Self.queryComponent(key))=\(Self.queryComponent(value))"
        }
        return pairs.isEmpty ? "" : "?\(pairs.joined(separator: "&"))"
    }

    private static func pathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private static func queryComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}
