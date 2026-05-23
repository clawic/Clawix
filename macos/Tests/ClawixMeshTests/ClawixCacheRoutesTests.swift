import XCTest
@testable import Clawix

final class ClawixCacheRoutesTests: XCTestCase {
    func testAppCacheSubdirectoriesAreCentralized() throws {
        let routesSource = try readSource("ClawixCacheRoutes.swift")
        let faviconSource = try readSource("Browser/FaviconCache.swift")
        let backendMetadataSource = try readSource("AgentBackend/BackendMetadataCache.swift")
        let localModelsDownloadSource = try readSource("LocalModels/LocalModelsRuntimeDownloadDelegate.swift")
        let sidebarSource = try readSource("AppState/SidebarItems.swift")
        let cachesRoot = URL(fileURLWithPath: "/Users/demo/Library/Caches", isDirectory: true)

        XCTAssertEqual(ClawixCacheRoutes.appCacheDirectoryName, "Clawix")
        XCTAssertEqual(ClawixCacheRoutes.faviconsDirectoryName, "Favicons")
        XCTAssertEqual(ClawixCacheRoutes.backendMetadataDirectoryName, "BackendMetadata")
        XCTAssertEqual(ClawixCacheRoutes.localModelsDirectoryName, "local-models")
        XCTAssertEqual(ClawixCacheRoutes.devCacheDirectoryName, "Clawix-Dev")
        XCTAssertEqual(ClawixCacheRoutes.devPairingFileName, "pairing.json")
        XCTAssertEqual(
            ClawixCacheRoutes.appCacheRoot(cachesRoot: cachesRoot).path,
            "/Users/demo/Library/Caches/Clawix"
        )
        XCTAssertEqual(
            ClawixCacheRoutes.faviconsDirectory(cachesRoot: cachesRoot).path,
            "/Users/demo/Library/Caches/Clawix/Favicons"
        )
        XCTAssertEqual(
            ClawixCacheRoutes.backendMetadataDirectory(cachesRoot: cachesRoot).path,
            "/Users/demo/Library/Caches/Clawix/BackendMetadata"
        )
        XCTAssertEqual(
            ClawixCacheRoutes.localModelsDirectory(cachesRoot: cachesRoot).path,
            "/Users/demo/Library/Caches/Clawix/local-models"
        )
        XCTAssertEqual(
            ClawixCacheRoutes.devCacheRoot(cachesRoot: cachesRoot).path,
            "/Users/demo/Library/Caches/Clawix-Dev"
        )
        XCTAssertEqual(
            ClawixCacheRoutes.devPairingFileURL(cachesRoot: cachesRoot).path,
            "/Users/demo/Library/Caches/Clawix-Dev/pairing.json"
        )

        XCTAssertTrue(routesSource.contains("ClawixTemporaryRoutes.systemTemporaryDirectory(fileManager: fileManager)"))
        XCTAssertFalse(routesSource.contains("fileManager.temporaryDirectory"))
        XCTAssertTrue(faviconSource.contains("ClawixCacheRoutes.faviconsDirectory()"))
        XCTAssertTrue(backendMetadataSource.contains("ClawixCacheRoutes.backendMetadataDirectory()"))
        XCTAssertTrue(localModelsDownloadSource.contains("ClawixCacheRoutes.localModelsDirectory"))
        XCTAssertTrue(sidebarSource.contains("ClawixCacheRoutes.devPairingFileURL()"))
        for source in [faviconSource, backendMetadataSource, localModelsDownloadSource] {
            XCTAssertFalse(source.contains(".urls(for: .cachesDirectory, in: .userDomainMask)"))
            XCTAssertFalse(source.contains("appendingPathComponent(ClawixPersistentSurfacePaths.components.clawix"))
        }
        XCTAssertFalse(backendMetadataSource.contains("appendingPathComponent(\"BackendMetadata\""))
        XCTAssertFalse(sidebarSource.contains("ClawixPersistentSurfacePaths.cacheRoot()"))
        XCTAssertFalse(sidebarSource.contains("FileManager.default.temporaryDirectory"))
        XCTAssertFalse(sidebarSource.contains("appendingPathComponent(\"pairing.json\""))
    }

    private func readSource(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.sources, isDirectory: true)
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.clawix, isDirectory: true)
        return try String(
            contentsOf: root.appendingPathComponent(relativePath, isDirectory: false),
            encoding: .utf8
        )
    }
}
