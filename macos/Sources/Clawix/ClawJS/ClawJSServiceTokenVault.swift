import Foundation
import SecretsCrypto

struct ClawJSServiceTokenVault {
    private var adminTokens: [ClawJSService: String] = [:]
    private var signedHostTokens: [ClawJSService: String] = [:]
    private var hostAssertionKeys: [ClawJSService: String] = [:]

    func snapshot() -> ClawJSSessionTokenSnapshot {
        ClawJSSessionTokenSnapshot(
            adminTokens: adminTokens,
            signedHostTokens: signedHostTokens,
            hostAssertionKeys: hostAssertionKeys
        )
    }

    func adminTokenIfSpawned(for service: ClawJSService) -> String? {
        adminTokens[service]
    }

    func signedHostTokenIfSpawned(for service: ClawJSService) -> String? {
        signedHostTokens[service]
    }

    func hostAssertionKeyIfSpawned(for service: ClawJSService) -> String? {
        hostAssertionKeys[service]
    }

    mutating func ensureAdminToken(for service: ClawJSService) -> String? {
        guard ClawJSServiceSupervisorPolicy.requiresSessionAdminToken(service) else { return nil }
        if let existing = adminTokens[service] { return existing }
        let token = Self.urlSafeToken()
        adminTokens[service] = token
        return token
    }

    mutating func ensureSignedHostToken(for service: ClawJSService) -> String? {
        guard service == .secrets else { return nil }
        if let existing = signedHostTokens[service] { return existing }
        let token = Self.urlSafeToken()
        signedHostTokens[service] = token
        return token
    }

    mutating func ensureHostAssertionKey(for service: ClawJSService) -> String? {
        guard service == .secrets else { return nil }
        if let existing = hostAssertionKeys[service] { return existing }
        let key = SecureRandom.bytes(32).base64EncodedString()
        hostAssertionKeys[service] = key
        return key
    }

    static func secretsBootstrapPayload(
        adminToken: String?,
        signedHostToken: String?,
        hostAssertionKeyBase64: String?,
        platformKey: Data?
    ) throws -> Data {
        var payload: [String: String] = [:]
        if let adminToken {
            payload["adminToken"] = adminToken
        }
        if let signedHostToken {
            payload["signedHostToken"] = signedHostToken
        }
        if let hostAssertionKeyBase64 {
            payload["hostAssertionKeyBase64"] = hostAssertionKeyBase64
        }
        if let platformKey {
            payload["kekBase64"] = platformKey.base64EncodedString()
        }
        return try JSONSerialization.data(withJSONObject: payload, options: [])
            + Data([0x0a])
    }

    static func localAdminBootstrapPayload(adminToken: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["adminToken": adminToken], options: [])
            + Data([0x0a])
    }

    private static func urlSafeToken() -> String {
        SecureRandom.bytes(32).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
