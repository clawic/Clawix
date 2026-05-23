import Foundation

enum ClawixCacheRoutes {
    static let appCacheDirectoryName = ClawixPersistentSurfacePaths.components.clawix
    static let faviconsDirectoryName = ClawixPersistentSurfacePaths.components.favicons
    static let backendMetadataDirectoryName = ClawixPersistentSurfacePaths.components.backendMetadata
    static let localModelsDirectoryName = ClawixPersistentSurfacePaths.components.localModels
    static let devCacheDirectoryName = ClawixPersistentSurfacePaths.components.devCache
    static let devPairingFileName = "pairing.json"

    static func userCachesRoot(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? ClawixTemporaryRoutes.systemTemporaryDirectory(fileManager: fileManager)
    }

    static func appCacheRoot(cachesRoot: URL) -> URL {
        cachesRoot.appendingPathComponent(appCacheDirectoryName, isDirectory: true)
    }

    static func faviconsDirectory(cachesRoot: URL? = nil, fileManager: FileManager = .default) -> URL {
        appCacheRoot(cachesRoot: cachesRoot ?? userCachesRoot(fileManager: fileManager))
            .appendingPathComponent(faviconsDirectoryName, isDirectory: true)
    }

    static func backendMetadataDirectory(cachesRoot: URL? = nil, fileManager: FileManager = .default) -> URL {
        appCacheRoot(cachesRoot: cachesRoot ?? userCachesRoot(fileManager: fileManager))
            .appendingPathComponent(backendMetadataDirectoryName, isDirectory: true)
    }

    static func localModelsDirectory(cachesRoot: URL? = nil, fileManager: FileManager = .default) -> URL {
        appCacheRoot(cachesRoot: cachesRoot ?? userCachesRoot(fileManager: fileManager))
            .appendingPathComponent(localModelsDirectoryName, isDirectory: true)
    }

    static func devCacheRoot(cachesRoot: URL? = nil, fileManager: FileManager = .default) -> URL {
        (cachesRoot ?? userCachesRoot(fileManager: fileManager))
            .appendingPathComponent(devCacheDirectoryName, isDirectory: true)
    }

    static func devPairingFileURL(cachesRoot: URL? = nil, fileManager: FileManager = .default) -> URL {
        devCacheRoot(cachesRoot: cachesRoot, fileManager: fileManager)
            .appendingPathComponent(devPairingFileName, isDirectory: false)
    }
}
