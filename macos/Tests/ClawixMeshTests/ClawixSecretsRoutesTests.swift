import XCTest
@testable import Clawix

final class ClawixSecretsRoutesTests: XCTestCase {
    func testSecretsStorageRoutesAreCentralized() throws {
        let routesSource = try readSource("Secrets/ClawixSecretsRoutes.swift")
        let secretsPathsSource = try readSource("Secrets/SecretsPaths.swift")
        let secretsManagerSource = try readSource("Secrets/SecretsManager.swift")
        let secretsSettingsSource = try readSource("Secrets/SecretsSettingsPage.swift")
        let supportRoot = URL(fileURLWithPath: "/Users/demo/Library/Application Support", isDirectory: true)
        let home = URL(fileURLWithPath: "/Users/demo", isDirectory: true)
        let overrideDirectory = ClawixSecretsRoutes.directoryURL(
            environment: [ClawixSecretsRoutes.overrideDirectoryEnvName: "~/ClawixSecrets"],
            applicationSupportRoot: supportRoot
        )
        let productionDirectory = ClawixSecretsRoutes.directoryURL(
            environment: [:],
            applicationSupportRoot: supportRoot
        )

        XCTAssertEqual(ClawixSecretsRoutes.overrideDirectoryEnvName, "CLAWIX_SECRETS_DIR")
        XCTAssertEqual(ClawixSecretsRoutes.appSupportDirectoryName, "Clawix")
        XCTAssertEqual(ClawixSecretsRoutes.secretsDirectoryName, "secrets")
        XCTAssertEqual(ClawixSecretsRoutes.databaseFileName, "secrets.sqlite")
        XCTAssertEqual(ClawixSecretsRoutes.proxySocketFileName, "proxy.sock")
        XCTAssertEqual(ClawixSecretsRoutes.shellBinDirectoryName, "bin")
        XCTAssertEqual(ClawixSecretsRoutes.clawCLISymlinkFileName, "claw")
        XCTAssertFalse(ClawixSecretsRoutes.userHomeDirectory().path.isEmpty)
        XCTAssertEqual(productionDirectory.path, "/Users/demo/Library/Application Support/Clawix/secrets")
        XCTAssertTrue(overrideDirectory.path.hasSuffix("/ClawixSecrets"))
        XCTAssertEqual(
            ClawixSecretsRoutes.databaseFileURL(directory: productionDirectory).path,
            "/Users/demo/Library/Application Support/Clawix/secrets/secrets.sqlite"
        )
        XCTAssertEqual(
            ClawixSecretsRoutes.proxySocketFileURL(directory: productionDirectory).path,
            "/Users/demo/Library/Application Support/Clawix/secrets/proxy.sock"
        )
        XCTAssertEqual(
            ClawixSecretsRoutes.shellBinDirectory(userHomeDirectory: home).path,
            "/Users/demo/bin"
        )
        XCTAssertEqual(
            ClawixSecretsRoutes.clawCLISymlinkURL(
                binDirectory: ClawixSecretsRoutes.shellBinDirectory(userHomeDirectory: home)
            ).path,
            "/Users/demo/bin/claw"
        )

        XCTAssertTrue(secretsPathsSource.contains("ClawixSecretsRoutes.directoryURL()"))
        XCTAssertTrue(secretsPathsSource.contains("ClawixSecretsRoutes.databaseFileURL(directory: directory)"))
        XCTAssertTrue(secretsPathsSource.contains("ClawixSecretsRoutes.proxySocketFileURL(directory: directory)"))
        XCTAssertTrue(secretsManagerSource.contains("ClawixSecretsRoutes.shellBinDirectory()"))
        XCTAssertTrue(secretsManagerSource.contains("ClawixSecretsRoutes.clawCLISymlinkURL(binDirectory: binDir)"))
        XCTAssertTrue(secretsSettingsSource.contains("ClawixSecretsRoutes.clawCLISymlinkURL().path"))
        XCTAssertTrue(routesSource.contains("static func userHomeDirectory() -> URL"))
        XCTAssertTrue(routesSource.contains("ClawixUserHomeRoutes.directory()"))
        XCTAssertTrue(routesSource.contains("explicitUserHomeDirectory ?? Self.userHomeDirectory()"))
        XCTAssertFalse(routesSource.contains("FileManager.default.homeDirectoryForCurrentUser"))
        XCTAssertFalse(routesSource.contains("userHomeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser"))
        XCTAssertFalse(secretsPathsSource.contains("CLAWIX_SECRETS_DIR"))
        XCTAssertFalse(secretsPathsSource.contains("for: .applicationSupportDirectory"))
        XCTAssertFalse(secretsPathsSource.contains("ClawixPersistentSurfacePaths.components.secrets"))
        XCTAssertFalse(secretsPathsSource.contains("ClawixPersistentSurfacePaths.components.secretsDatabase"))
        XCTAssertFalse(secretsPathsSource.contains("\"proxy.sock\""))
        for source in [secretsManagerSource, secretsSettingsSource] {
            XCTAssertFalse(source.contains("FileManager.default.homeDirectoryForCurrentUser"))
            XCTAssertFalse(source.contains("appendingPathComponent(\"bin\""))
            XCTAssertFalse(source.contains("appendingPathComponent(\"bin/claw\""))
            XCTAssertFalse(source.contains("appendingPathComponent(\"claw\""))
        }
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
