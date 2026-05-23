import Foundation

struct AppResourceRegistryStore: Sendable {
    static let stateFileName = ClawixAppResourceRoutes.stateFileName

    let directory: URL

    static func defaultDirectory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        ClawixAppResourceRoutes.defaultDirectory(environment: environment)
    }

    static func expandHome(_ value: String) -> URL {
        ClawixAppResourceRoutes.expandHome(value)
    }

    var stateURL: URL {
        ClawixAppResourceRoutes.stateFileURL(directory: directory)
    }

    func list(status: String? = nil, kind: String? = nil) throws -> [AppResourceRecord] {
        try readState().resources
            .map(refreshStatus)
            .filter { status == nil || $0.status == status }
            .filter { kind == nil || $0.kind == kind }
    }

    func resolve(_ id: String) throws -> AppResourceRecord {
        guard let resource = try readState().resources.first(where: { $0.id == id }) else {
            throw AppResourceRegistryError.notFound(id)
        }
        return refreshStatus(resource)
    }

    func read(_ id: String, maxBytes: Int = 64_000) throws -> AppResourceReadResult {
        let resource = try resolve(id)
        guard resource.status == "active" else {
            return AppResourceReadResult(resource: resource, content: nil, truncated: false, error: "Resource \(id) is \(resource.status).")
        }
        guard resource.locator.kind == "path" else {
            return AppResourceReadResult(resource: resource, content: nil, truncated: false, error: "Resource \(id) is not a readable filesystem path.")
        }

        let url = Self.expandHome(resource.locator.value)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return AppResourceReadResult(resource: resource, content: nil, truncated: false, error: "Resource \(id) is a directory.")
        }

        let limit = min(max(maxBytes, 1), 256_000)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        let visible = data.prefix(limit)
        return AppResourceReadResult(
            resource: resource,
            content: String(data: visible, encoding: .utf8) ?? "",
            truncated: data.count > limit,
            error: nil
        )
    }

    private func readState() throws -> AppResourceRegistryState {
        guard FileManager.default.fileExists(atPath: stateURL.path) else {
            return AppResourceRegistryState(schemaVersion: 1, resources: [], updatedAt: "")
        }
        let data = try Data(contentsOf: stateURL)
        return try JSONDecoder().decode(AppResourceRegistryState.self, from: data)
    }

    private func refreshStatus(_ resource: AppResourceRecord) -> AppResourceRecord {
        guard resource.locator.kind == "path" else { return resource.withStatus("active") }
        return FileManager.default.fileExists(atPath: Self.expandHome(resource.locator.value).path)
            ? resource.withStatus("active")
            : resource.withStatus("missing")
    }
}

struct AppResourceRegistryState: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var resources: [AppResourceRecord]
    var updatedAt: String
}

struct AppResourceRecord: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var id: String
    var kind: String
    var status: String
    var locator: AppResourceLocator
    var scope: [String: String]?
    var label: String?
    var fingerprint: String?
    var bookmark: String?
    var fileIdentity: String?
    var createdAt: String
    var updatedAt: String
    var lastSeenAt: String?
    var missingSince: String?

    func withStatus(_ nextStatus: String) -> AppResourceRecord {
        var next = self
        next.status = nextStatus
        return next
    }

    var bridgeValue: [String: Any] {
        var value: [String: Any] = [
            "schemaVersion": schemaVersion,
            "id": id,
            "kind": kind,
            "status": status,
            "locator": locator.bridgeValue,
            "scope": scope ?? [:],
            "createdAt": createdAt,
            "updatedAt": updatedAt
        ]
        if let label { value["label"] = label }
        if let fingerprint { value["fingerprint"] = fingerprint }
        if let bookmark { value["bookmark"] = bookmark }
        if let fileIdentity { value["fileIdentity"] = fileIdentity }
        if let lastSeenAt { value["lastSeenAt"] = lastSeenAt }
        if let missingSince { value["missingSince"] = missingSince }
        return value
    }
}

struct AppResourceLocator: Codable, Equatable, Sendable {
    var kind: String
    var value: String

    var bridgeValue: [String: Any] {
        [
            "kind": kind,
            "value": value
        ]
    }
}

struct AppResourceReadResult: Equatable, Sendable {
    var resource: AppResourceRecord
    var content: String?
    var truncated: Bool
    var error: String?

    var bridgeValue: [String: Any] {
        var value: [String: Any] = [
            "resource": resource.bridgeValue,
            "truncated": truncated,
            "redactionPolicy": AppBridgeRedactionPolicy.policyId,
            "source": "resources.read"
        ]
        if let content {
            value["content"] = content
        }
        if let error {
            value["error"] = error
        }
        return value
    }
}

enum AppResourceRegistryError: LocalizedError, Equatable, Sendable {
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let id):
            return "Resource not found: \(id)"
        }
    }
}
