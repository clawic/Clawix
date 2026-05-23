import XCTest

final class PortableArchiveSettingsTests: XCTestCase {
    func testSettingsDataSurfaceIncludesPortableArchiveStatesAndSignedHostGate() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let page = try String(contentsOf: root.appendingPathComponent("Sources/Clawix/Settings/PortableArchiveSettingsPage.swift"))
        let settings = try String(contentsOf: root.appendingPathComponent("Sources/Clawix/SettingsView.swift"))

        XCTAssertTrue(settings.contains("case portableArchive"))
        XCTAssertTrue(settings.contains("PortableArchiveSettingsPage()"))
        XCTAssertTrue(settings.contains("return \"Data\""))

        for required in [
            "ready",
            "verificationFailed",
            "secretsRequireReauth",
            "externalSourceReferenced",
            "cacheWillRebuild",
            "restoreBlocked",
            "restoreComplete",
            ".clawbackup",
            ".clawexport",
            ".clawsecrets",
            "signed-host proof",
            "exact target confirmation"
        ] {
            XCTAssertTrue(page.contains(required), "missing \(required)")
        }
    }
}
