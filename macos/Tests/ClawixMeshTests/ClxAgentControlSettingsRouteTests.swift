import XCTest
@testable import Clawix

final class ClxAgentControlSettingsRouteTests: XCTestCase {
    func testControlBusExposesDeterministicSettingsRouteForClawJSLensEvidence() throws {
        let source = try readSource("AgentControl/ClxControlHandlers.swift")

        XCTAssertTrue(source.contains("case \"open-settings\": return openSettings(args)"))
        XCTAssertTrue(source.contains("static func openSettings(_ args: [String: Any]) -> ClxControlResult"))
        XCTAssertTrue(source.contains("SettingsCategory.init(rawValue:)"))
        XCTAssertTrue(source.contains("appState.settingsCategory = category"))
        XCTAssertTrue(source.contains("appState.currentRoute = .settings"))
        XCTAssertTrue(source.contains("\"settingsCategory\": appState.settingsCategory.rawValue"))
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
