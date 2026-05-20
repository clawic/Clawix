import Foundation

enum AppPackageImportValidator {
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
