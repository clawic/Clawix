import XCTest
@testable import Clawix

final class ClawixDesignRoutesTests: XCTestCase {
    func testDesignDroppedImageTemporaryRouteIsCentralized() throws {
        let routesSource = try readSource("Design/ClawixDesignRoutes.swift")
        let referencesSource = try readSource("Design/ReferencesHomeView.swift")
        let temporaryDirectory = URL(fileURLWithPath: "/tmp", isDirectory: true)

        XCTAssertEqual(ClawixDesignRoutes.droppedImagePrefix, "clawix-drop")
        XCTAssertEqual(ClawixDesignRoutes.pngExtension, "png")
        XCTAssertEqual(
            ClawixDesignRoutes.droppedImageURL(
                id: "drop-token",
                temporaryDirectory: temporaryDirectory
            ).path,
            "/tmp/clawix-drop-drop-token.png"
        )

        XCTAssertTrue(routesSource.contains("ClawixTemporaryRoutes.systemTemporaryDirectory(fileManager: fileManager)"))
        XCTAssertFalse(routesSource.contains("fileManager.temporaryDirectory"))
        XCTAssertTrue(referencesSource.contains("ClawixDesignRoutes.droppedImageURL()"))
        XCTAssertFalse(referencesSource.contains("FileManager.default.temporaryDirectory"))
        XCTAssertFalse(referencesSource.contains("clawix-drop-\\(UUID().uuidString).png"))
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
