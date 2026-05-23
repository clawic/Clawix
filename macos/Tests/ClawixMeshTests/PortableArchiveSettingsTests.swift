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

        XCTAssertFalse(page.contains("@State private var state"))
        XCTAssertFalse(page.contains("state = ."))
        XCTAssertFalse(page.contains("PortableArchiveActionStatus(label: \"Pending\")"))
        XCTAssertTrue(page.contains("PortableArchiveActionStatus"))
        XCTAssertTrue(page.contains("private enum PortableArchiveAction: CaseIterable"))
        XCTAssertTrue(page.contains("Blocked until the signed host route returns a dry-run archive plan and approval evidence."))
        XCTAssertTrue(page.contains("External pending until a completed restore report exists; Settings does not synthesize one."))
        XCTAssertTrue(page.contains("Source: claw archive restore --signed-host"))
        XCTAssertTrue(page.contains("Source: PortableArchiveRestoreReport from signed host"))
        XCTAssertTrue(page.contains(".accessibilityHint(Text(\"\\(reason) \\(source)\"))"))
        XCTAssertTrue(page.contains("signed host route returns dry-run and result evidence"))
    }
}
