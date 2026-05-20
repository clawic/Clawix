import XCTest
@testable import Clawix

final class AppCustomSurfaceCapabilityCatalogTests: AppCustomSurfaceCapabilityTestCase {
    private let expectedCustomAppCapabilityIds = [
        "actions.invoke",
        "db.query",
        "iot.device.action.invoke",
        "jobs.cancel",
        "jobs.events",
        "jobs.get",
        "jobs.list",
        "jobs.start",
        "jobs.stream",
        "mac.action.plan",
        "resources.list",
        "resources.read",
        "search.query",
        "secrets.broker",
        "system.telemetry.history",
        "system.telemetry.snapshot"
    ]
    private let expectedOrdinaryAccessCapabilityIds = [
        "db.query",
        "jobs.events",
        "jobs.get",
        "jobs.list",
        "jobs.stream",
        "resources.list",
        "resources.read",
        "search.query",
        "system.telemetry.history",
        "system.telemetry.snapshot"
    ]
    private let expectedApprovalRequiredCapabilityIds = [
        "actions.invoke",
        "iot.device.action.invoke",
        "jobs.cancel",
        "jobs.start",
        "mac.action.plan",
        "secrets.broker"
    ]
    private let expectedCliBlockedSurfaceCapabilityIds = [
        "jobs.cancel",
        "jobs.events",
        "jobs.get",
        "jobs.list",
        "jobs.start",
        "jobs.stream"
    ]
    private let expectedMcpBlockedSurfaceCapabilityIds = ["secrets.broker"]

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
            declaredCapabilities: expectedCustomAppCapabilityIds
        )

        let riskMap = AppCapabilityCatalog.riskMap(for: record)

        XCTAssertEqual(riskMap.authorityModel, "localWideReadsHighRiskApproval")
        XCTAssertEqual(riskMap.capabilityIds.sorted(), expectedCustomAppCapabilityIds)
        XCTAssertEqual(AppCapabilityCatalog.descriptors.map(\.id).sorted(), expectedCustomAppCapabilityIds)
        XCTAssertEqual(riskMap.ordinaryAccess.sorted(), expectedOrdinaryAccessCapabilityIds)
        XCTAssertEqual(riskMap.approvalRequired.sorted(), expectedApprovalRequiredCapabilityIds)
        XCTAssertEqual(riskMap.highRisk.sorted(), expectedApprovalRequiredCapabilityIds)
        XCTAssertEqual(riskMap.blocked, [])
        XCTAssertTrue(riskMap.ordinaryAccess.contains("search.query"), "\(riskMap.ordinaryAccess)")
        XCTAssertTrue(riskMap.ordinaryAccess.contains("db.query"), "\(riskMap.ordinaryAccess)")
        XCTAssertTrue(riskMap.ordinaryAccess.contains("jobs.list"), "\(riskMap.ordinaryAccess)")
        XCTAssertTrue(riskMap.ordinaryAccess.contains("jobs.get"), "\(riskMap.ordinaryAccess)")
        XCTAssertTrue(riskMap.ordinaryAccess.contains("jobs.events"), "\(riskMap.ordinaryAccess)")
        XCTAssertTrue(riskMap.ordinaryAccess.contains("jobs.stream"), "\(riskMap.ordinaryAccess)")
        XCTAssertTrue(riskMap.approvalRequired.contains("jobs.start"), "\(riskMap.approvalRequired)")
        XCTAssertTrue(riskMap.approvalRequired.contains("jobs.cancel"), "\(riskMap.approvalRequired)")
        XCTAssertTrue(riskMap.ordinaryAccess.contains("system.telemetry.snapshot"), "\(riskMap.ordinaryAccess)")
        XCTAssertTrue(riskMap.ordinaryAccess.contains("system.telemetry.history"), "\(riskMap.ordinaryAccess)")
        XCTAssertTrue(riskMap.approvalRequired.contains("secrets.broker"), "\(riskMap.approvalRequired)")
        XCTAssertTrue(riskMap.approvalRequired.contains("iot.device.action.invoke"), "\(riskMap.approvalRequired)")
        XCTAssertTrue(riskMap.highRisk.contains("secrets.broker"), "\(riskMap.highRisk)")
        XCTAssertTrue(riskMap.highRisk.contains("iot.device.action.invoke"), "\(riskMap.highRisk)")
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

    func testOrdinaryReadCapabilitiesExposeSharedRedactionPolicy() {
        let ordinary = AppCapabilityCatalog.descriptors.filter { $0.customAppAccess == .localWide }
        XCTAssertEqual(ordinary.map(\.id).sorted(), ["db.query", "jobs.events", "jobs.get", "jobs.list", "jobs.stream", "resources.list", "resources.read", "search.query", "system.telemetry.history", "system.telemetry.snapshot"])
        for descriptor in ordinary {
            XCTAssertEqual(descriptor.redactionPolicyRef, AppBridgeRedactionPolicy.policyId, descriptor.id)
            XCTAssertEqual(descriptor.bridgeValue["redactionPolicyRef"] as? String, AppBridgeRedactionPolicy.policyId)
            XCTAssertNotNil(descriptor.inputSchemaRef, descriptor.id)
            XCTAssertNotNil(descriptor.outputSchemaRef, descriptor.id)
            XCTAssertEqual(descriptor.eventSchemaRefs?.cancel, AppCapabilityCatalog.requestCancelSchemaRef, descriptor.id)
            XCTAssertEqual(descriptor.eventSchemaRefs?.progress, AppCapabilityCatalog.requestProgressSchemaRef, descriptor.id)
            XCTAssertEqual(descriptor.eventSchemaRefs?.partial, AppCapabilityCatalog.requestPartialSchemaRef, descriptor.id)
        }
        XCTAssertEqual(AppCapabilityCatalog.descriptor(id: "search.query")?.inputSchemaRef, "claw.search.query.v1")
        XCTAssertEqual(AppCapabilityCatalog.descriptor(id: "db.query")?.outputSchemaRef, "claw.db.records.v1")
        XCTAssertEqual(AppCapabilityCatalog.descriptor(id: "resources.list")?.inputSchemaRef, "claw.resources.list.v1")
        XCTAssertEqual(AppCapabilityCatalog.descriptor(id: "resources.list")?.outputSchemaRef, "claw.resources.listResult.v1")
        XCTAssertEqual(AppCapabilityCatalog.descriptor(id: "resources.read")?.inputSchemaRef, "claw.resources.read.v1")
        XCTAssertEqual(AppCapabilityCatalog.descriptor(id: "system.telemetry.snapshot")?.outputSchemaRef, "claw.system.telemetry.snapshot.v1")
        XCTAssertEqual(AppCapabilityCatalog.descriptor(id: "system.telemetry.history")?.inputSchemaRef, "claw.system.telemetry.history.request.v1")
        XCTAssertEqual(AppCapabilityCatalog.descriptor(id: "jobs.list")?.inputSchemaRef, "claw.jobs.list.v1")
        XCTAssertEqual(AppCapabilityCatalog.descriptor(id: "jobs.list")?.outputSchemaRef, "claw.jobs.listResult.v1")
        XCTAssertEqual(AppCapabilityCatalog.descriptor(id: "jobs.get")?.inputSchemaRef, "claw.jobs.get.v1")
        XCTAssertEqual(AppCapabilityCatalog.descriptor(id: "jobs.get")?.outputSchemaRef, "claw.jobs.detail.v1")
        XCTAssertEqual(AppCapabilityCatalog.descriptor(id: "jobs.events")?.inputSchemaRef, "claw.jobs.events.v1")
        XCTAssertEqual(AppCapabilityCatalog.descriptor(id: "jobs.events")?.outputSchemaRef, "claw.jobs.eventsResult.v1")
        XCTAssertEqual(AppCapabilityCatalog.descriptor(id: "jobs.stream")?.inputSchemaRef, "claw.jobs.stream.v1")
        XCTAssertEqual(AppCapabilityCatalog.descriptor(id: "jobs.stream")?.outputSchemaRef, "claw.jobs.streamResult.v1")
    }

    func testApprovalRequiredCapabilitiesAreInterruptiveHighRisk() {
        for descriptor in AppCapabilityCatalog.descriptors where descriptor.customAppAccess == .approvalRequired {
            XCTAssertTrue(descriptor.interruptiveApproval, descriptor.id)
            XCTAssertTrue(descriptor.riskTier == .high || descriptor.riskTier == .critical, descriptor.id)
        }
    }

    func testApprovalRequiredCapabilitiesExposeSharedSchemaRefs() throws {
        let expected: [String: (String, String)] = [
            "actions.invoke": ("claw.actions.invoke.v1", "claw.actions.receipt.v1"),
            "jobs.start": ("claw.jobs.start.v1", "claw.jobs.startResult.v1"),
            "jobs.cancel": ("claw.jobs.cancel.v1", "claw.jobs.cancelResult.v1"),
            "secrets.broker": ("claw.secrets.broker.v1", "claw.secrets.receipt.v1"),
            "mac.action.plan": ("claw.mac.actionRequest.v1", "claw.mac.actionPlan.v1"),
            "iot.device.action.invoke": ("claw.iot.action.v1", "claw.iot.actionResult.v1")
        ]

        for (id, refs) in expected {
            let descriptor = try XCTUnwrap(AppCapabilityCatalog.descriptor(id: id))
            XCTAssertEqual(descriptor.inputSchemaRef, refs.0)
            XCTAssertEqual(descriptor.outputSchemaRef, refs.1)
            XCTAssertTrue(AppCapabilityCatalog.schemaRefs.contains(refs.0), id)
            XCTAssertTrue(AppCapabilityCatalog.schemaRefs.contains(refs.1), id)
        }
        XCTAssertEqual(AppCapabilityCatalog.missingSchemaRefs, [])
    }

    func testCapabilityContractsExposeDispatchAvailabilityAndGaps() throws {
        let search = try XCTUnwrap(AppCapabilityCatalog.descriptor(id: "search.query")?.bridgeValue["dispatch"] as? [String: Any])
        XCTAssertEqual(search["status"] as? String, "available")
        XCTAssertEqual(search["mode"] as? String, "localWideRead")
        XCTAssertEqual(search["approvalRequired"] as? Bool, false)

        let mac = try XCTUnwrap(AppCapabilityCatalog.descriptor(id: "mac.action.plan")?.bridgeValue["dispatch"] as? [String: Any])
        XCTAssertEqual(mac["status"] as? String, "available")
        XCTAssertEqual(mac["mode"] as? String, "approvalRequiredPlanOnly")
        XCTAssertEqual(mac["approvalRequired"] as? Bool, true)
        XCTAssertEqual(mac["runner"] as? String, "NativeMacActionWire.planJSON")

        let iot = try XCTUnwrap(AppCapabilityCatalog.descriptor(id: "iot.device.action.invoke")?.bridgeValue["dispatch"] as? [String: Any])
        XCTAssertEqual(iot["status"] as? String, "available")
        XCTAssertEqual(iot["mode"] as? String, "approvalRequiredDispatch")
        XCTAssertEqual(iot["externalValidation"] as? String, "EXTERNAL PENDING")

        let actions = try XCTUnwrap(AppCapabilityCatalog.descriptor(id: "actions.invoke")?.bridgeValue["dispatch"] as? [String: Any])
        XCTAssertEqual(actions["status"] as? String, "unavailable")
        XCTAssertEqual(actions["mode"] as? String, "approvalRequiredNoRunner")

        let secrets = try XCTUnwrap(AppCapabilityCatalog.descriptor(id: "secrets.broker")?.bridgeValue["dispatch"] as? [String: Any])
        XCTAssertEqual(secrets["status"] as? String, "unavailable")
        XCTAssertEqual(secrets["mode"] as? String, "approvalRequiredNoPlaintextBroker")

        let jobStream = try XCTUnwrap(AppCapabilityCatalog.descriptor(id: "jobs.stream")?.bridgeValue["dispatch"] as? [String: Any])
        XCTAssertEqual(jobStream["status"] as? String, "available")
        XCTAssertEqual(jobStream["mode"] as? String, "localWideRead")

        let jobStart = try XCTUnwrap(AppCapabilityCatalog.descriptor(id: "jobs.start")?.bridgeValue["dispatch"] as? [String: Any])
        XCTAssertEqual(jobStart["status"] as? String, "available")
        XCTAssertEqual(jobStart["mode"] as? String, "approvalRequiredDispatch")
        XCTAssertEqual(jobStart["runner"] as? String, "ClawJSRuntimeClient")
    }

    func testRegisteredCapabilitiesDoNotFallBackToUnknownDispatch() throws {
        let pendingRunnerIds: Set<String> = ["actions.invoke", "secrets.broker"]

        for descriptor in AppCapabilityCatalog.descriptors {
            let dispatch = try XCTUnwrap(descriptor.bridgeValue["dispatch"] as? [String: Any], descriptor.id)
            XCTAssertNotEqual(dispatch["mode"] as? String, "unknown", descriptor.id)
            if dispatch["runner"] as? String == "pending" {
                XCTAssertTrue(pendingRunnerIds.contains(descriptor.id), descriptor.id)
                XCTAssertEqual(dispatch["status"] as? String, "unavailable", descriptor.id)
            }
        }
    }

    func testSurfaceBindingsKeepReviewedBlockedPartitions() throws {
        var cliBlocked: [String] = []
        var mcpBlocked: [String] = []

        for descriptor in AppCapabilityCatalog.descriptors {
            let surfaces = try XCTUnwrap(descriptor.bridgeValue["surfaces"] as? [[String: String]], descriptor.id)
            XCTAssertEqual(surfaces.map { $0["surface"] }, AppCapabilityCatalog.canonicalSurfaceNames, descriptor.id)
            for surface in surfaces {
                if surface["status"] == "blocked" {
                    XCTAssertNil(surface["ref"], "\(descriptor.id):\(surface["surface"] ?? "unknown")")
                    if surface["surface"] == "cli" { cliBlocked.append(descriptor.id) }
                    if surface["surface"] == "mcp" { mcpBlocked.append(descriptor.id) }
                }
                if surface["surface"] == "relay", surface["status"] == "available" {
                    XCTAssertEqual(surface["ref"], "relay.remote.custom_app_sdk metadata-only contract projection", descriptor.id)
                }
            }
        }

        XCTAssertEqual(cliBlocked.sorted(), expectedCliBlockedSurfaceCapabilityIds)
        XCTAssertEqual(mcpBlocked.sorted(), expectedMcpBlockedSurfaceCapabilityIds)
    }

    func testAgentToolNamesMapToHighRiskCapabilities() {
        XCTAssertEqual(AppHighRiskActionAudit.capabilityId(forTool: "secrets.read"), "secrets.broker")
        XCTAssertEqual(AppHighRiskActionAudit.capabilityId(forTool: "mac.window.plan"), "mac.action.plan")
        XCTAssertEqual(AppHighRiskActionAudit.capabilityId(forTool: "iot.device.toggle"), "iot.device.action.invoke")
        XCTAssertEqual(AppHighRiskActionAudit.capabilityId(forTool: "jobs.start"), "jobs.start")
        XCTAssertEqual(AppHighRiskActionAudit.capabilityId(forTool: "jobs.cancel"), "jobs.cancel")
        XCTAssertEqual(AppHighRiskActionAudit.capabilityId(forTool: "database_create_task"), "actions.invoke")

        for tool in ["secrets.read", "mac.window.plan", "iot.device.toggle", "jobs.start", "jobs.cancel", "database_create_task"] {
            let descriptor = AppHighRiskActionAudit.descriptor(forTool: tool)
            XCTAssertEqual(descriptor?.customAppAccess, .approvalRequired)
            XCTAssertEqual(descriptor?.interruptiveApproval, true)
        }
    }
}
