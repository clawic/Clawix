import CryptoKit
import Foundation

enum AppPackageImportValidator {
    static let signatureFilename = "package-signature.json"

    private static let reservedHostOwnedFilenames: Set<String> = [
        AppTrustAudit.filename,
        AppHighRiskActionAudit.filename
    ]

    static func validateSourceDirectory(_ sourceURL: URL, manifestName: String) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw AppsStoreImportError.sourceNotDirectory(sourceURL.path)
        }
        if try isSymbolicLink(sourceURL) {
            throw AppsStoreImportError.symlinkNotAllowed(sourceURL.path)
        }
        let manifestURL = sourceURL.appendingPathComponent(manifestName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw AppsStoreImportError.missingManifest(sourceURL.path)
        }
        if try isSymbolicLink(manifestURL) {
            throw AppsStoreImportError.symlinkNotAllowed(manifestURL.path)
        }
    }

    static func validatePackageContents(
        sourceURL: URL,
        manifestName: String,
        record: AppRecord
    ) throws {
        try validateTree(sourceURL: sourceURL, manifestName: manifestName)
        switch record.effectiveSurfaceKind {
        case .web:
            try requireEntryFile(
                sourceURL.appendingPathComponent("index.html", isDirectory: false),
                description: "index.html"
            )
        case .swiftDeclarative:
            let surfaceURL = sourceURL.appendingPathComponent(AppSwiftSurfaceContract.manifestFilename, isDirectory: false)
            try requireEntryFile(surfaceURL, description: AppSwiftSurfaceContract.manifestFilename)
            let data = try Data(contentsOf: surfaceURL)
            let manifest = try AppSwiftSurfaceContract.decodeManifest(data: data)
            try AppSwiftSurfaceContract.validate(manifest: manifest, for: record)
        }
    }

    static func contentDigestSHA256(sourceURL: URL, manifestName: String) throws -> String {
        try validateTree(sourceURL: sourceURL, manifestName: manifestName)
        let files = try regularFileURLs(in: sourceURL)
            .filter { $0.lastPathComponent != signatureFilename }
        var hasher = SHA256()
        for url in files {
            let relativePath = relativePath(for: url, under: sourceURL)
            let data = try Data(contentsOf: url)
            hasher.update(data: Data(relativePath.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: Data(String(data.count).utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: data)
            hasher.update(data: Data([0]))
        }
        return SHA256Digest.hexString(from: hasher.finalize())
    }

    static func signatureStatus(
        sourceURL: URL,
        packageDigestSHA256: String,
        trustedPublicKeys: [String: Curve25519.Signing.PublicKey]
    ) throws -> AppPackageSignatureStatus {
        try signatureEvaluation(
            sourceURL: sourceURL,
            packageDigestSHA256: packageDigestSHA256,
            trustPolicy: AppPackageTrustPolicy(
                trustedSignatureKeys: trustedPublicKeys.map {
                    AppPackageTrustPolicy.TrustedSignatureKey(keyId: $0.key, publicKey: $0.value)
                }
            )
        ).status
    }

    static func signatureEvaluation(
        sourceURL: URL,
        packageDigestSHA256: String,
        trustPolicy: AppPackageTrustPolicy
    ) throws -> AppPackageSignatureEvaluation {
        let signatureURL = sourceURL.appendingPathComponent(signatureFilename, isDirectory: false)
        guard FileManager.default.fileExists(atPath: signatureURL.path) else {
            return AppPackageSignatureEvaluation(status: .notVerified)
        }
        if try isSymbolicLink(signatureURL) {
            throw AppsStoreImportError.symlinkNotAllowed(signatureURL.path)
        }
        do {
            let manifest = try JSONDecoder().decode(
                AppPackageSignatureManifest.self,
                from: Data(contentsOf: signatureURL)
            )
            guard manifest.schemaVersion == 1,
                  manifest.algorithm == "ed25519",
                  manifest.digestSHA256 == packageDigestSHA256,
                  let trustedKey = trustPolicy.trustedSignatureKey(id: manifest.keyId),
                  let signature = Data(base64Encoded: manifest.signatureBase64) else {
                return AppPackageSignatureEvaluation(
                    status: .failed,
                    keyId: manifest.keyId,
                    trustSource: trustPolicy.trustedSignatureKey(id: manifest.keyId)?.trustSource
                )
            }
            let status: AppPackageSignatureStatus = trustedKey.publicKey.isValidSignature(
                signature,
                for: signaturePayload(packageDigestSHA256: packageDigestSHA256)
            ) ? .verified : .failed
            return AppPackageSignatureEvaluation(
                status: status,
                keyId: manifest.keyId,
                trustSource: trustedKey.trustSource
            )
        } catch {
            return AppPackageSignatureEvaluation(status: .failed)
        }
    }

    static func signaturePayload(packageDigestSHA256: String) -> Data {
        Data("clawix-app-package-v1\n\(packageDigestSHA256)".utf8)
    }

    private static func validateTree(sourceURL: URL, manifestName: String) throws {
        guard let enumerator = FileManager.default.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [],
            errorHandler: { url, _ in
                return false
            }
        ) else {
            throw AppsStoreImportError.sourceNotDirectory(sourceURL.path)
        }

        for case let url as URL in enumerator {
            if try isSymbolicLink(url) {
                throw AppsStoreImportError.symlinkNotAllowed(url.path)
            }
            let filename = url.lastPathComponent
            if filename != manifestName, reservedHostOwnedFilenames.contains(filename) {
                throw AppsStoreImportError.hostOwnedFileNotAllowed(url.path)
            }
        }
    }

    private static func regularFileURLs(in sourceURL: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [],
            errorHandler: { _, _ in false }
        ) else {
            throw AppsStoreImportError.sourceNotDirectory(sourceURL.path)
        }
        var urls: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                urls.append(url.standardizedFileURL)
            }
        }
        return urls.sorted { relativePath(for: $0, under: sourceURL) < relativePath(for: $1, under: sourceURL) }
    }

    private static func relativePath(for url: URL, under rootURL: URL) -> String {
        let root = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(root + "/") else { return url.lastPathComponent }
        return String(path.dropFirst(root.count + 1))
    }

    private static func requireEntryFile(_ url: URL, description: String) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw AppsStoreImportError.missingRenderEntry(description)
        }
        if try isSymbolicLink(url) {
            throw AppsStoreImportError.symlinkNotAllowed(url.path)
        }
    }

    private static func isSymbolicLink(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
        return values.isSymbolicLink == true
    }
}

struct AppPackageSignatureEvaluation: Equatable, Hashable {
    var status: AppPackageSignatureStatus
    var keyId: String?
    var trustSource: String?
}

struct AppPackageSignatureManifest: Codable, Equatable, Hashable {
    var schemaVersion: Int
    var algorithm: String
    var keyId: String
    var digestSHA256: String
    var signatureBase64: String

    init(
        schemaVersion: Int = 1,
        algorithm: String = "ed25519",
        keyId: String,
        digestSHA256: String,
        signatureBase64: String
    ) {
        self.schemaVersion = schemaVersion
        self.algorithm = algorithm
        self.keyId = keyId
        self.digestSHA256 = digestSHA256
        self.signatureBase64 = signatureBase64
    }
}

private enum SHA256Digest {
    static func hexString<D: Sequence>(from digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
