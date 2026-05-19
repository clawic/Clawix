import XCTest
@testable import Clawix

final class AppCustomSurfaceCapabilityTests: XCTestCase {
    func testLegacyAppManifestDecodesWithSdkFirstDefaults() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "slug": "tasks-panel",
          "name": "Tasks Panel",
          "description": "",
          "icon": "",
          "accentColor": "",
          "tags": [],
          "permissions": { "internet": false, "callAgent": true, "allowedTools": [] },
          "pinned": false,
          "createdAt": 0,
          "updatedAt": 0
        }
        """.data(using: .utf8)!

        let record = try JSONDecoder().decode(AppRecord.self, from: json)

        XCTAssertEqual(record.effectiveDeclaredCapabilities, [])
        XCTAssertEqual(record.effectiveOriginClass, .localUserAuthored)
        XCTAssertEqual(record.effectiveSurfaceKind, .web)
        XCTAssertEqual(record.effectiveProtectedRoutePolicy, .blocked)
    }

    func testCapabilityRiskMapSeparatesOrdinaryReadsFromApprovalRequiredActions() {
        let record = AppRecord(
            slug: "workspace-panel",
            name: "Workspace Panel",
            declaredCapabilities: ["search.query", "db.query", "secrets.broker", "iot.device.action.invoke"]
        )

        let riskMap = AppCapabilityCatalog.riskMap(for: record)

        XCTAssertEqual(riskMap.authorityModel, "localWideReadsHighRiskApproval")
        XCTAssertTrue(riskMap.ordinaryAccess.contains("search.query"))
        XCTAssertTrue(riskMap.ordinaryAccess.contains("db.query"))
        XCTAssertTrue(riskMap.approvalRequired.contains("secrets.broker"))
        XCTAssertTrue(riskMap.approvalRequired.contains("iot.device.action.invoke"))
        XCTAssertTrue(riskMap.highRisk.contains("secrets.broker"))
        XCTAssertTrue(riskMap.highRisk.contains("iot.device.action.invoke"))
        XCTAssertFalse(riskMap.capabilityIds.contains("core.sqlite"))
    }

    func testImportedOrUnknownCapabilitiesRequireReview() {
        let record = AppRecord(
            slug: "imported-panel",
            name: "Imported Panel",
            declaredCapabilities: ["search.query", "unknown.future"],
            originClass: .imported
        )

        let riskMap = AppCapabilityCatalog.riskMap(for: record)

        XCTAssertEqual(riskMap.unknown, ["unknown.future"])
        XCTAssertTrue(riskMap.requiresActivationReview)
    }

    func testProtectedRoutesCannotBeReplacedWithoutVariantFallback() {
        let blocked = AppRecord(
            slug: "secrets-panel",
            name: "Secrets Panel",
            routeTarget: "secrets",
            protectedRoutePolicy: .blocked
        )
        XCTAssertFalse(AppCapabilityCatalog.protectedRouteViolations(for: blocked).isEmpty)

        let variant = AppRecord(
            slug: "secrets-variant",
            name: "Secrets Variant",
            routeTarget: "secrets",
            variant: AppVariantMetadata(originalRoute: "secrets", defaultScope: "workspace"),
            protectedRoutePolicy: .variantOnly
        )
        XCTAssertEqual(AppCapabilityCatalog.protectedRouteViolations(for: variant), [])
    }

    func testInjectedAppsSdkExposesCapabilityInspection() {
        XCTAssertTrue(ClawixAppsSDKJS.contains("capabilities.list"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("capabilities.riskMap"))
    }
}
