import XCTest
@testable import Clawix

final class ClawJSMacCareRoutesTests: XCTestCase {
    func testMacCareFinalizerPreviewRoutesAreCentralized() throws {
        let routesSource = try readSource("ClawJS/ClawJSMacCareRoutes.swift")
        let clientSource = try readSource("ClawJS/ClawJSMacCareClient.swift")
        let temporaryDirectory = URL(fileURLWithPath: "/tmp", isDirectory: true)

        XCTAssertEqual(
            ClawJSMacCareRoutes.finalizerActionPlanDirectory(
                temporaryDirectory: temporaryDirectory
            ).path,
            "/tmp/clawix-mac-care-finalizer"
        )
        XCTAssertEqual(
            ClawJSMacCareRoutes.finalizerActionPlanURL(
                id: "plan-token",
                temporaryDirectory: temporaryDirectory
            ).path,
            "/tmp/clawix-mac-care-finalizer/plan-token.json"
        )

        XCTAssertTrue(routesSource.contains("ClawixTemporaryRoutes.systemTemporaryDirectory(fileManager: fileManager)"))
        XCTAssertFalse(routesSource.contains("fileManager.temporaryDirectory"))
        XCTAssertTrue(clientSource.contains("ClawJSMacCareRoutes.finalizerActionPlanDirectory()"))
        XCTAssertTrue(clientSource.contains("ClawJSMacCareRoutes.finalizerActionPlanURL()"))
        XCTAssertFalse(clientSource.contains("FileManager.default.temporaryDirectory"))
        XCTAssertFalse(clientSource.contains("appendingPathComponent(\"clawix-mac-care-finalizer\""))
        XCTAssertFalse(clientSource.contains("appendingPathComponent(\"\\(UUID().uuidString).json\")"))
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
