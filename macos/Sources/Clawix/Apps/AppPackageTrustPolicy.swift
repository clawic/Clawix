import CryptoKit
import Foundation

struct AppPackageTrustPolicy {
    struct TrustedSignatureKey {
        var keyId: String
        var publicKey: Curve25519.Signing.PublicKey
        var trustSource: String
        var issuer: String?

        init(
            keyId: String,
            publicKey: Curve25519.Signing.PublicKey,
            trustSource: String = "host-local",
            issuer: String? = nil
        ) {
            self.keyId = keyId
            self.publicKey = publicKey
            self.trustSource = trustSource
            self.issuer = issuer
        }
    }

    static let filename = "app-package-trust-roots.json"
    static let empty = AppPackageTrustPolicy(trustedSignatureKeys: [])

    private let trustedKeysById: [String: TrustedSignatureKey]

    init(trustedSignatureKeys: [TrustedSignatureKey]) {
        self.trustedKeysById = Dictionary(uniqueKeysWithValues: trustedSignatureKeys.map { ($0.keyId, $0) })
    }

    var trustedSignaturePublicKeys: [String: Curve25519.Signing.PublicKey] {
        trustedKeysById.mapValues(\.publicKey)
    }

    func trustedSignatureKey(id: String) -> TrustedSignatureKey? {
        trustedKeysById[id]
    }

    static func defaultURL(forAppsRoot rootURL: URL) -> URL {
        rootURL.appendingPathComponent(filename, isDirectory: false)
    }

    static func load(from url: URL, fileManager: FileManager = .default) -> AppPackageTrustPolicy {
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              manifest.schemaVersion == 1 else {
            return .empty
        }
        let keys = manifest.trustedKeys.compactMap { entry -> TrustedSignatureKey? in
            guard entry.algorithm == "ed25519",
                  !entry.keyId.isEmpty,
                  let raw = Data(base64Encoded: entry.publicKeyBase64),
                  let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else {
                return nil
            }
            return TrustedSignatureKey(
                keyId: entry.keyId,
                publicKey: publicKey,
                trustSource: entry.trustSource,
                issuer: entry.issuer
            )
        }
        return AppPackageTrustPolicy(trustedSignatureKeys: keys)
    }

    private struct Manifest: Codable {
        var schemaVersion: Int
        var trustedKeys: [TrustedKey]
    }

    private struct TrustedKey: Codable {
        var keyId: String
        var algorithm: String
        var publicKeyBase64: String
        var trustSource: String
        var issuer: String?
    }
}
