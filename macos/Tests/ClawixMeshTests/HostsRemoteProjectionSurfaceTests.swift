import XCTest

final class HostsRemoteProjectionSurfaceTests: XCTestCase {
    func testHostsPageConsumesClawJSRemoteProjection() throws {
        let source = try readSource("Settings/HostsPage.swift")

        XCTAssertTrue(source.contains("@StateObject private var remoteProjectionStore = ClawJSRemoteProjectionStore()"))
        XCTAssertTrue(source.contains("remoteProjectionStore: remoteProjectionStore"))
        XCTAssertTrue(source.contains("SectionLabel(title: \"Framework remote readiness\")"))
        XCTAssertTrue(source.contains("remoteProjectionStore.load()"))
        XCTAssertTrue(source.contains("remoteProjectionStore.cancel()"))
        XCTAssertTrue(source.contains("snapshot.conformanceStatus"))
        XCTAssertTrue(source.contains("snapshot.requiredRoutes.count - snapshot.missingRouteIds.count"))
        XCTAssertTrue(source.contains("snapshot.contracts.count"))
        XCTAssertTrue(source.contains("snapshot.externalPendingCount"))
        XCTAssertTrue(source.contains("snapshot.externalReadinessStatus"))
        XCTAssertTrue(source.contains("snapshot.blockedExternalRequirementSummary"))
        XCTAssertTrue(source.contains("snapshot.closureBlockersSummary"))
        XCTAssertTrue(source.contains("snapshot.providerDeviceE2ESummary"))
        for prefix in Self.remoteRoutePrefixes {
            XCTAssertFalse(source.contains(prefix))
        }
    }

    func testHostDetailReusesHostsRemoteProjection() throws {
        let source = try readSource("Settings/HostDetailView.swift")

        XCTAssertTrue(source.contains("@ObservedObject var remoteProjectionStore: ClawJSRemoteProjectionStore"))
        XCTAssertTrue(source.contains("remoteReadinessCard"))
        XCTAssertTrue(source.contains("DetailCard(title: \"Framework remote readiness\")"))
        XCTAssertTrue(source.contains("snapshot.conformanceStatus"))
        XCTAssertTrue(source.contains("snapshot.requiredRoutes.count - snapshot.missingRouteIds.count"))
        XCTAssertTrue(source.contains("snapshot.contracts.count"))
        XCTAssertTrue(source.contains("snapshot.externalPendingCount"))
        XCTAssertTrue(source.contains("snapshot.externalReadinessStatus"))
        XCTAssertTrue(source.contains("snapshot.blockedExternalRequirementSummary"))
        XCTAssertTrue(source.contains("snapshot.closureBlockersSummary"))
        XCTAssertTrue(source.contains("snapshot.providerDeviceE2ESummary"))
        XCTAssertFalse(source.contains("remoteProjectionStore.load()"))
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
