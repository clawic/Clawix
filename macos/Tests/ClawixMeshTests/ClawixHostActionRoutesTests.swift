import XCTest
@testable import Clawix

final class ClawixHostActionRoutesTests: XCTestCase {
    func testHostActionPersistenceRoutesAreCentralized() throws {
        let routesSource = try readSource("HostActions/ClawixHostActionRoutes.swift")
        let policySource = try readSource("HostActions/HostActionPolicy.swift")
        let centerSource = try readSource("HostActions/MacControlCenter.swift")
        let applicationSupportDirectory = URL(fileURLWithPath: "/Users/demo/Library/Application Support", isDirectory: true)

        XCTAssertEqual(
            ClawixHostActionRoutes.clawixSupportDirectory(
                applicationSupportDirectory: applicationSupportDirectory
            ).path,
            "/Users/demo/Library/Application Support/Clawix"
        )
        XCTAssertEqual(
            ClawixHostActionRoutes.hostActionAuditURL(
                applicationSupportDirectory: applicationSupportDirectory
            ).path,
            "/Users/demo/Library/Application Support/Clawix/host-action-audit.jsonl"
        )
        XCTAssertEqual(
            ClawixHostActionRoutes.macControlTimelineURL(
                applicationSupportDirectory: applicationSupportDirectory
            ).path,
            "/Users/demo/Library/Application Support/Clawix/mac-control-timeline.jsonl"
        )
        XCTAssertEqual(
            ClawixHostActionRoutes.macControlPendingApprovalsURL(
                applicationSupportDirectory: applicationSupportDirectory
            ).path,
            "/Users/demo/Library/Application Support/Clawix/mac-control-pending-approvals.json"
        )

        XCTAssertTrue(routesSource.contains("ClawixTemporaryRoutes.systemTemporaryDirectory(fileManager: fileManager)"))
        XCTAssertFalse(routesSource.contains("fileManager.temporaryDirectory"))
        XCTAssertTrue(policySource.contains("ClawixHostActionRoutes.hostActionAuditURL()"))
        XCTAssertTrue(centerSource.contains("ClawixHostActionRoutes.macControlTimelineURL()"))
        XCTAssertTrue(centerSource.contains("ClawixHostActionRoutes.macControlPendingApprovalsURL()"))
        XCTAssertFalse(policySource.contains("NSTemporaryDirectory()"))
        XCTAssertFalse(centerSource.contains("NSTemporaryDirectory()"))
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
