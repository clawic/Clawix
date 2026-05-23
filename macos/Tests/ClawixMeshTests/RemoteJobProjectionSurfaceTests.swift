import XCTest

final class RemoteJobProjectionSurfaceTests: XCTestCase {
    func testChatViewLoadsRemoteProjectionOnlyForVisibleRemoteJobs() throws {
        let source = try readSource("ChatView.swift")

        XCTAssertTrue(source.contains("@StateObject private var remoteProjectionStore = ClawJSRemoteProjectionStore()"))
        XCTAssertTrue(source.contains("let activeRemoteJobs = flags.isVisible(.remoteMesh)"))
        XCTAssertTrue(source.contains("RemoteJobCard("))
        XCTAssertTrue(source.contains("remoteProjectionState: remoteProjectionStore.state"))
        XCTAssertTrue(source.contains(".task { remoteProjectionStore.load() }"))
        XCTAssertTrue(source.contains(".onDisappear { remoteProjectionStore.cancel() }"))
    }

    func testRemoteJobCardRendersProjectionWithoutDeclaringRemoteRoutes() throws {
        let source = try readSource("Bridge/RemoteJobCard.swift")

        XCTAssertTrue(source.contains("var remoteProjectionState: ClawJSRemoteProjectionStore.State = .idle"))
        XCTAssertTrue(source.contains("remoteProjectionBanner"))
        XCTAssertTrue(source.contains("Checking ClawJS remote contracts"))
        XCTAssertTrue(source.contains("snapshot.requiredRoutes.count - snapshot.missingRouteIds.count"))
        XCTAssertTrue(source.contains("snapshot.externalReadinessStatus"))
        XCTAssertTrue(source.contains("snapshot.blockedExternalRequirementSummary"))
        for prefix in Self.remoteRoutePrefixes {
            XCTAssertFalse(source.contains(prefix))
        }
    }

    private func readSource(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Clawix")
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private static var remoteRoutePrefixes: [String] {
        ["remote", "gateway", "sync"].map { "/v1/" + $0 + "/" }
    }
}
