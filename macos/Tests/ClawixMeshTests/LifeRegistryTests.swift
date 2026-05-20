import XCTest
@testable import Clawix

final class LifeRegistryTests: XCTestCase {
    func testDefaultRegistryExposesOnlyStableProductSurfaces() {
        let entries = LifeRegistry.entries

        XCTAssertFalse(entries.isEmpty)
        XCTAssertTrue(entries.allSatisfy { $0.status == .stable })
        XCTAssertNotNil(LifeRegistry.entry(byId: "health"))
        XCTAssertNotNil(LifeRegistry.entry(byId: "sleep"))
        XCTAssertNotNil(LifeRegistry.entry(byId: "nutrition"))
        XCTAssertNil(LifeRegistry.entry(byId: "hydration"))
    }

    func testDevOnlyLifeVerticalsRequireExplicitOptIn() {
        let stableBodyEntries = LifeRegistry.entries(in: .bodyHealth)
        let allBodyEntries = LifeRegistry.entries(in: .bodyHealth, includeDevOnly: true)
        let allEntries = LifeRegistry.entries(includeDevOnly: true)

        XCTAssertTrue(stableBodyEntries.allSatisfy { $0.status == .stable })
        XCTAssertGreaterThan(allBodyEntries.count, stableBodyEntries.count)
        XCTAssertTrue(allEntries.contains { $0.id == "hydration" && $0.status == .devOnly })
        XCTAssertNotNil(LifeRegistry.entry(byId: "hydration", includeDevOnly: true))
    }

    func testRegistryProjectionCarriesClawJSSourceAndSingleSignalsPort() {
        XCTAssertEqual(LifeRegistry.projectionVersion, "signals-registry.v1")
        XCTAssertTrue(LifeRegistry.sourceChecksum.hasPrefix("sha256:"))
        XCTAssertEqual(LifeRegistry.signalsServicePort, 24110)
    }

    func testSensitiveLifeVerticalsExposeLegalGuardMetadata() {
        let sensitiveEntries = LifeRegistry.entries(includeDevOnly: true).filter(\.sensitive)

        XCTAssertFalse(sensitiveEntries.isEmpty)
        XCTAssertTrue(sensitiveEntries.allSatisfy { $0.legalGuardLabel == "SENSITIVE" })
        XCTAssertTrue(sensitiveEntries.allSatisfy { entry in
            entry.legalGuardDescription?.contains("not professional advice") == true
        })
        XCTAssertNil(LifeRegistry.entry(byId: "sleep")?.legalGuardLabel)
    }
}
