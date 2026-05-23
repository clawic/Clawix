import XCTest
@testable import Clawix

final class ClawixDiagnosticStorageRoutesTests: XCTestCase {
    func testPersistentDiagnosticsDirectoryAndFilesAreCentralized() throws {
        let samplerSource = try readSource("Diagnostics/ResourceSampler.swift")
        let metricKitSource = try readSource("Diagnostics/MetricKitObserver.swift")
        let supportRoot = URL(fileURLWithPath: "/Users/demo/Library/Application Support", isDirectory: true)

        XCTAssertEqual(ClawixDiagnosticStorageRoutes.fallbackBundleIdentifier, "clawix.desktop")
        XCTAssertEqual(ClawixDiagnosticStorageRoutes.diagnosticsDirectoryName, "Diagnostics")
        XCTAssertEqual(
            ClawixDiagnosticStorageRoutes.diagnosticsDirectoryURL(
                applicationSupportRoot: supportRoot,
                bundleIdentifier: "com.example.clawix"
            ).path,
            "/Users/demo/Library/Application Support/com.example.clawix/Diagnostics"
        )
        XCTAssertEqual(
            ClawixDiagnosticStorageRoutes.diagnosticsFileURL(
                named: ResourceSampler.lastResourcesFileName,
                applicationSupportRoot: supportRoot,
                bundleIdentifier: "com.example.clawix"
            ).path,
            "/Users/demo/Library/Application Support/com.example.clawix/Diagnostics/last-resources.json"
        )
        XCTAssertTrue(samplerSource.contains("ClawixDiagnosticStorageRoutes.bundleIdentifier()"))
        XCTAssertTrue(samplerSource.contains("ClawixDiagnosticStorageRoutes.applicationSupportRoot"))
        XCTAssertTrue(samplerSource.contains("ClawixDiagnosticStorageRoutes.diagnosticsDirectoryURL"))
        XCTAssertTrue(samplerSource.contains("ClawixDiagnosticStorageRoutes.diagnosticsFileURL"))
        XCTAssertFalse(samplerSource.contains("appendingPathComponent(\"Diagnostics\""))
        XCTAssertFalse(metricKitSource.contains("~/Library/Application Support/<bundleId>/Diagnostics/"))
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
