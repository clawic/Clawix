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

    func testOrdinaryCapabilitiesCannotCarryHighRiskFlags() {
        for descriptor in AppCapabilityCatalog.descriptors where descriptor.customAppAccess == .localWide {
            XCTAssertEqual(descriptor.riskTier, .low, descriptor.id)
            XCTAssertFalse(descriptor.interruptiveApproval, descriptor.id)
            XCTAssertFalse(descriptor.touchesSecrets, descriptor.id)
            XCTAssertFalse(descriptor.touchesNativeHost, descriptor.id)
            XCTAssertFalse(descriptor.touchesPhysicalWorld, descriptor.id)
            XCTAssertFalse(descriptor.destructive, descriptor.id)
        }
    }

    func testApprovalRequiredCapabilitiesAreInterruptiveHighRisk() {
        for descriptor in AppCapabilityCatalog.descriptors where descriptor.customAppAccess == .approvalRequired {
            XCTAssertTrue(descriptor.interruptiveApproval, descriptor.id)
            XCTAssertTrue(descriptor.riskTier == .high || descriptor.riskTier == .critical, descriptor.id)
        }
    }

    func testAgentToolNamesMapToHighRiskCapabilities() {
        XCTAssertEqual(AppHighRiskActionAudit.capabilityId(forTool: "secrets.read"), "secrets.broker")
        XCTAssertEqual(AppHighRiskActionAudit.capabilityId(forTool: "mac.window.plan"), "mac.action.plan")
        XCTAssertEqual(AppHighRiskActionAudit.capabilityId(forTool: "iot.device.toggle"), "iot.device.action.invoke")
        XCTAssertEqual(AppHighRiskActionAudit.capabilityId(forTool: "database_create_task"), "actions.invoke")

        for tool in ["secrets.read", "mac.window.plan", "iot.device.toggle", "database_create_task"] {
            let descriptor = AppHighRiskActionAudit.descriptor(forTool: tool)
            XCTAssertEqual(descriptor?.customAppAccess, .approvalRequired)
            XCTAssertEqual(descriptor?.interruptiveApproval, true)
        }
    }

    func testHighRiskActionAuditWritesApprovalReceipts() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let auditURL = root.appendingPathComponent(AppHighRiskActionAudit.filename)
        let app = AppRecord(
            slug: "iot-panel",
            name: "IoT Panel",
            declaredCapabilities: ["iot.device.action.invoke"]
        )
        let descriptor = try XCTUnwrap(AppHighRiskActionAudit.descriptor(forTool: "iot.device.toggle"))

        let receipt = try AppHighRiskActionAudit.append(
            app: app,
            descriptor: descriptor,
            action: "iot.device.toggle",
            decision: .approvedOnce,
            outcome: .approvalRecordedDispatchUnavailable,
            reason: descriptor.summary,
            auditURL: auditURL
        )

        let receipts = try AppHighRiskActionAudit.read(from: auditURL)
        XCTAssertEqual(receipts.count, 1)
        XCTAssertEqual(receipts.first?.id, receipt.id)
        XCTAssertEqual(receipts.first?.capabilityId, "iot.device.action.invoke")
        XCTAssertEqual(receipts.first?.riskTier, .high)
        XCTAssertEqual(receipts.first?.interruptiveApproval, true)
        XCTAssertEqual(receipts.first?.outcome, .approvalRecordedDispatchUnavailable)
    }

    func testHighRiskActionAuditWritesDenialReceipts() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let auditURL = root.appendingPathComponent(AppHighRiskActionAudit.filename)
        let app = AppRecord(
            slug: "secrets-panel",
            name: "Secrets Panel",
            declaredCapabilities: ["secrets.broker"]
        )
        let descriptor = try XCTUnwrap(AppHighRiskActionAudit.descriptor(forTool: "secrets.read"))

        _ = try AppHighRiskActionAudit.append(
            app: app,
            descriptor: descriptor,
            action: "secrets.read",
            decision: .denied,
            outcome: .denied,
            reason: descriptor.summary,
            auditURL: auditURL
        )

        let receipts = try AppHighRiskActionAudit.read(from: auditURL)
        XCTAssertEqual(receipts.count, 1)
        XCTAssertEqual(receipts[0].capabilityId, "secrets.broker")
        XCTAssertEqual(receipts[0].riskTier, .critical)
        XCTAssertEqual(receipts[0].decision, .denied)
        XCTAssertEqual(receipts[0].outcome, .denied)
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

    func testImportedAppsRequireReviewBeforeActivation() {
        let record = AppRecord(
            slug: "imported-known-panel",
            name: "Imported Known Panel",
            declaredCapabilities: ["search.query", "db.query"],
            originClass: .imported
        )

        switch AppCapabilityCatalog.activationGate(for: record) {
        case .reviewRequired(let riskMap):
            XCTAssertTrue(riskMap.requiresActivationReview)
        default:
            XCTFail("Imported app should require review before activation")
        }

        let reviewed = AppRecord(
            slug: "imported-known-panel",
            name: "Imported Known Panel",
            declaredCapabilities: ["search.query", "db.query"],
            originClass: .imported,
            activationReview: AppActivationReview(approvedBy: "Test", riskMapSource: AppCapabilityCatalog.source)
        )

        XCTAssertEqual(AppCapabilityCatalog.activationGate(for: reviewed), .allowed)
    }

    func testUnknownCapabilitiesBlockActivation() {
        let record = AppRecord(
            slug: "unknown-panel",
            name: "Unknown Panel",
            declaredCapabilities: ["unknown.future"],
            originClass: .imported
        )

        XCTAssertEqual(AppCapabilityCatalog.activationGate(for: record), .blockedUnknownCapabilities(["unknown.future"]))
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

    func testInjectedAppsSdkExposesSearchAndDBContracts() {
        XCTAssertTrue(ClawixAppsSDKJS.contains("search.query"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("db.query"))
        XCTAssertFalse(ClawixAppsSDKJS.lowercased().contains("sqlite"))
    }

    func testDBQueryDSLNormalizesFiltersSortAndLimits() throws {
        let query = try AppBridgeQueryDSL.dbQuery(from: [
            "collection": "tasks",
            "filter": [
                "status": "todo",
                "archivedAt": ["isNull": true],
                "priority": ["neq": "low"]
            ],
            "search": "launch",
            "sort": "-updatedAt",
            "limit": 999,
            "offset": -10
        ])

        XCTAssertEqual(query.collection, "tasks")
        XCTAssertEqual(query.search, "launch")
        XCTAssertEqual(query.limit, 100)
        XCTAssertEqual(query.offset, 0)
        XCTAssertEqual(query.sort, DBFilterState.Sort(field: "updatedAt", descending: true))
        XCTAssertEqual(query.backendFilterJSON?["status"] as? String, "todo")
        XCTAssertEqual(query.filterChips.first(where: { $0.field == "archivedAt" })?.op, .isNull)
        XCTAssertEqual(query.filterChips.first(where: { $0.field == "priority" })?.op, .neq)
    }

    func testSearchQueryDSLNormalizesCollectionsAndLimits() throws {
        let query = try AppBridgeQueryDSL.searchQuery(from: [
            "query": "agent",
            "collections": ["tasks", "", "notes"],
            "limit": 0
        ])

        XCTAssertEqual(query.query, "agent")
        XCTAssertEqual(query.collections, ["tasks", "notes"])
        XCTAssertEqual(query.limit, 1)
    }

    @MainActor
    func testVariantDefaultsResolveWorkspaceBeforeUserDefaultAndPreserveOriginal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let appsStore = AppsStore(rootURL: root)
        let defaults = try makeDefaults()
        let store = AppVariantDefaultsStore(userDefaults: defaults)
        let workspaceId = UUID()

        let userVariant = AppRecord(
            slug: "tasks-user-variant",
            name: "Tasks User Variant",
            routeTarget: "database/tasks",
            variant: AppVariantMetadata(originalRoute: "database/tasks", defaultScope: "user"),
            protectedRoutePolicy: .variantOnly
        )
        let workspaceVariant = AppRecord(
            slug: "tasks-workspace-variant",
            name: "Tasks Workspace Variant",
            routeTarget: "database/tasks",
            variant: AppVariantMetadata(originalRoute: "database/tasks", defaultScope: "workspace"),
            protectedRoutePolicy: .variantOnly
        )
        try appsStore.update(userVariant)
        try appsStore.update(workspaceVariant)

        try store.setDefault(app: userVariant, scope: .user)
        try store.setDefault(app: workspaceVariant, scope: .workspace, workspaceId: workspaceId)

        let scoped = store.resolution(
            for: "database/tasks",
            workspaceId: workspaceId,
            appsStore: appsStore
        )
        XCTAssertEqual(scoped?.appId, workspaceVariant.id)
        XCTAssertEqual(scoped?.scope, .workspace)
        XCTAssertEqual(scoped?.originalRouteAvailable, true)

        let fallback = store.resolution(for: "database/tasks", appsStore: appsStore)
        XCTAssertEqual(fallback?.appId, userVariant.id)
        XCTAssertEqual(fallback?.scope, .user)

        let original = store.resolution(
            for: "database/tasks",
            workspaceId: workspaceId,
            appsStore: appsStore,
            preferOriginal: true
        )
        XCTAssertNil(original)
    }

    @MainActor
    func testVariantDefaultsRejectProtectedReplacementWithoutVariantPolicy() throws {
        let defaults = try makeDefaults()
        let store = AppVariantDefaultsStore(userDefaults: defaults)
        let unsafe = AppRecord(
            slug: "secrets-replacement",
            name: "Secrets Replacement",
            routeTarget: "secrets",
            protectedRoutePolicy: .none
        )

        XCTAssertThrowsError(try store.setDefault(app: unsafe, scope: .user))
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "AppCustomSurfaceCapabilityTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
