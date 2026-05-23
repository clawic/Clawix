import XCTest
@testable import Clawix

final class ClawJSSettingsPageBoundaryTests: XCTestCase {
    func testSettingsPageUsesExtractedRuntimeLensSection() throws {
        let settingsPageSource = try readSource("Settings/ClawJSSettingsPage.swift")
        let runtimeSectionSource = try readSource("Settings/ClawJSRuntimeLensSection.swift")

        XCTAssertTrue(settingsPageSource.contains("ClawJSRuntimeLensSection()"))
        XCTAssertTrue(runtimeSectionSource.contains("struct ClawJSRuntimeLensSection: View"))
        XCTAssertFalse(settingsPageSource.contains("private var runtimeLensSection"))
        XCTAssertFalse(settingsPageSource.contains("runtimeLensSessionActionsInFlight"))
        XCTAssertFalse(settingsPageSource.contains("private func runtimeLensSummary"))
        XCTAssertFalse(settingsPageSource.contains("private func refreshRuntimeLens"))
    }

    private func readSource(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("Clawix")
            .appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
