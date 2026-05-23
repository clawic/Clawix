import XCTest

final class CompanionProjectionSurfaceTests: XCTestCase {
    func testPairWindowConsumesRemoteProjectionWhileVisible() throws {
        let source = try readSource("Bridge/PairWindowView.swift")

        XCTAssertTrue(source.contains("@StateObject private var remoteProjectionStore = ClawJSRemoteProjectionStore()"))
        XCTAssertTrue(source.contains("remoteReadinessCard"))
        XCTAssertTrue(source.contains("remoteProjectionStore.load()"))
        XCTAssertTrue(source.contains("remoteProjectionStore.cancel()"))
        XCTAssertTrue(source.contains("Framework remote readiness"))
        XCTAssertTrue(source.contains("snapshot.requiredRoutes.count - snapshot.missingRouteIds.count"))
        XCTAssertTrue(source.contains("snapshot.externalPendingCount"))
        XCTAssertTrue(source.contains("snapshot.externalReadinessStatus"))
        XCTAssertTrue(source.contains("snapshot.closureBlockersSummary"))
        XCTAssertTrue(source.contains("snapshot.providerDeviceE2ESummary"))
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
