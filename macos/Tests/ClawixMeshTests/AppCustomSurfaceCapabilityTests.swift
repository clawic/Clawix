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
            declaredCapabilities: [
                "search.query",
                "db.query",
                "jobs.list",
                "jobs.get",
                "jobs.events",
                "system.telemetry.snapshot",
                "system.telemetry.history",
                "secrets.broker",
                "iot.device.action.invoke"
            ]
        )

        let riskMap = AppCapabilityCatalog.riskMap(for: record)

        XCTAssertEqual(riskMap.authorityModel, "localWideReadsHighRiskApproval")
        XCTAssertTrue(riskMap.ordinaryAccess.contains("search.query"), "\(riskMap.ordinaryAccess)")
        XCTAssertTrue(riskMap.ordinaryAccess.contains("db.query"), "\(riskMap.ordinaryAccess)")
        XCTAssertTrue(riskMap.ordinaryAccess.contains("jobs.list"), "\(riskMap.ordinaryAccess)")
        XCTAssertTrue(riskMap.ordinaryAccess.contains("jobs.get"), "\(riskMap.ordinaryAccess)")
        XCTAssertTrue(riskMap.ordinaryAccess.contains("jobs.events"), "\(riskMap.ordinaryAccess)")
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
        XCTAssertEqual(ordinary.map(\.id).sorted(), ["db.query", "jobs.events", "jobs.get", "jobs.list", "resources.list", "resources.read", "search.query", "system.telemetry.history", "system.telemetry.snapshot"])
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
        XCTAssertEqual(AppCapabilityCatalog.descriptor(id: "jobs.stream")?.customAppAccess, .blocked)
        XCTAssertNil(AppCapabilityCatalog.descriptor(id: "jobs.stream")?.inputSchemaRef)
        XCTAssertNil(AppCapabilityCatalog.descriptor(id: "jobs.stream")?.outputSchemaRef)
        XCTAssertEqual(AppCapabilityCatalog.descriptor(id: "jobs.start")?.customAppAccess, .blocked)
        XCTAssertNil(AppCapabilityCatalog.descriptor(id: "jobs.start")?.inputSchemaRef)
        XCTAssertNil(AppCapabilityCatalog.descriptor(id: "jobs.start")?.outputSchemaRef)
        XCTAssertEqual(AppCapabilityCatalog.descriptor(id: "jobs.cancel")?.customAppAccess, .blocked)
        XCTAssertNil(AppCapabilityCatalog.descriptor(id: "jobs.cancel")?.inputSchemaRef)
        XCTAssertNil(AppCapabilityCatalog.descriptor(id: "jobs.cancel")?.outputSchemaRef)
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

    func testHighRiskActionDispatchResultsMapToAuditOutcomes() {
        XCTAssertEqual(
            AppHighRiskActionDispatchResult.dispatched(["ok": true]).receiptOutcome,
            .dispatched
        )
        XCTAssertEqual(
            AppHighRiskActionDispatchResult.unavailable("not wired").receiptOutcome,
            .approvalRecordedDispatchUnavailable
        )
        XCTAssertEqual(
            AppHighRiskActionDispatchResult.failed("runner failed").receiptOutcome,
            .dispatchFailed
        )
        XCTAssertNil(AppHighRiskActionDispatchResult.dispatched(NSNull()).rejectionMessage)
        XCTAssertEqual(
            AppHighRiskActionDispatchResult.failed("runner failed").rejectionMessage,
            "runner failed"
        )
    }

    func testCustomIoTActionRequestNormalizesArguments() throws {
        let request = try AppCustomIoTActionRequest(
            arguments: [
                "homeId": "home-1",
                "selector": "kitchen",
                "capability": "power",
                "action": "turn_on",
                "value": true,
                "targets": ["light-1", "  ", "light-2"]
            ],
            fallbackTool: "iot.device.toggle"
        ).request

        XCTAssertEqual(request.homeId, "home-1")
        XCTAssertEqual(request.selector, "kitchen")
        XCTAssertEqual(request.capability, "power")
        XCTAssertEqual(request.action, "turn_on")
        XCTAssertEqual(request.value?.asBool, true)
        XCTAssertEqual(request.targets, ["light-1", "light-2"])
    }

    func testCustomIoTActionRequestFallsBackToToolSuffix() throws {
        let request = try AppCustomIoTActionRequest(
            arguments: ["targets": ["light-1"]],
            fallbackTool: "iot.device.toggle"
        ).request

        XCTAssertEqual(request.action, "toggle")
        XCTAssertEqual(request.targets, ["light-1"])
    }

    func testCustomMacActionPlanRequestNormalizesArgumentsAndForcesDryRun() throws {
        let app = AppRecord(
            slug: "window-panel",
            name: "Window Panel",
            declaredCapabilities: ["mac.action.plan"]
        )

        let request = try AppCustomMacActionPlanRequest(
            app: app,
            arguments: [
                "capabilityId": "mac.window.move",
                "arguments": [
                    "app": "Safari",
                    "x": 20,
                    "y": "40",
                    "ignored": ["nested": true]
                ],
                "execute": false
            ],
            fallbackTool: "mac.window.plan"
        ).request

        XCTAssertEqual(request.capabilityId, "mac.window.move")
        XCTAssertEqual(request.actor.kind, "custom_app")
        XCTAssertEqual(request.actor.id, "window-panel")
        XCTAssertEqual(request.arguments["app"]?.stringValue, "Safari")
        XCTAssertEqual(request.arguments["x"]?.stringValue, "20")
        XCTAssertEqual(request.arguments["y"]?.stringValue, "40")
        XCTAssertNil(request.arguments["ignored"])
        XCTAssertTrue(request.dryRun)
        XCTAssertEqual(request.approved, false)
    }

    func testCustomMacActionPlanRequestRejectsExecution() {
        let app = AppRecord(
            slug: "window-panel",
            name: "Window Panel",
            declaredCapabilities: ["mac.action.plan"]
        )

        XCTAssertThrowsError(try AppCustomMacActionPlanRequest(
            app: app,
            arguments: ["capabilityId": "mac.window.close", "execute": true],
            fallbackTool: "mac.window.plan"
        ))
    }

    @MainActor
    func testFrameworkHighRiskActionDispatcherPlansMacActionWithoutExecuting() async throws {
        let app = AppRecord(
            slug: "window-panel",
            name: "Window Panel",
            declaredCapabilities: ["mac.action.plan"]
        )
        let descriptor = try XCTUnwrap(AppHighRiskActionAudit.descriptor(forTool: "mac.window.plan"))

        let result = await AppFrameworkHighRiskActionDispatcher().dispatch(
            AppHighRiskActionDispatchRequest(
                app: app,
                descriptor: descriptor,
                tool: "mac.window.plan",
                arguments: [
                    "capabilityId": "mac.window.move",
                    "app": "Safari",
                    "x": 20,
                    "y": 40
                ]
            )
        )

        XCTAssertEqual(result.receiptOutcome, .dispatched)
        guard case let .dispatched(value) = result,
              let object = value as? [String: Any] else {
            return XCTFail("Expected dispatched Mac Control plan")
        }
        XCTAssertEqual(object["capabilityId"] as? String, "mac.window.move")
        XCTAssertEqual(object["risk"] as? String, "low")
        XCTAssertEqual(object["willMutate"] as? Bool, true)
        XCTAssertEqual(object["executable"] as? Bool, true)
        XCTAssertEqual(object["blockedReasons"] as? [String], [])
    }

    @MainActor
    func testFrameworkHighRiskActionDispatcherRunsIoTAction() async throws {
        let fake = AppCustomSurfaceFakeIoTClient()
        fake.onRunAction = { request, homeId in
            XCTAssertNil(homeId)
            XCTAssertEqual(request.action, "turn_on")
            XCTAssertEqual(request.targets, ["light-1"])
            return AppCustomSurfaceFakeIoTClient.makeActionResult(status: "ok")
        }
        let manager = IoTManager(client: fake, adminTokenOperation: { "token" }, attachSupervisor: false)
        let app = AppRecord(
            slug: "iot-panel",
            name: "IoT Panel",
            declaredCapabilities: ["iot.device.action.invoke"]
        )
        let descriptor = try XCTUnwrap(AppHighRiskActionAudit.descriptor(forTool: "iot.device.toggle"))

        let result = await AppFrameworkHighRiskActionDispatcher(iotManager: manager).dispatch(
            AppHighRiskActionDispatchRequest(
                app: app,
                descriptor: descriptor,
                tool: "iot.device.toggle",
                arguments: ["action": "turn_on", "targets": ["light-1"]]
            )
        )

        XCTAssertEqual(result.receiptOutcome, .dispatched)
        guard case let .dispatched(value) = result,
              let object = value as? [String: Any] else {
            return XCTFail("Expected dispatched IoT result")
        }
        XCTAssertEqual(object["status"] as? String, "ok")
    }

    @MainActor
    func testDefaultHighRiskActionDispatcherKeepsDispatchUnavailable() async throws {
        let app = AppRecord(
            slug: "iot-panel",
            name: "IoT Panel",
            declaredCapabilities: ["iot.device.action.invoke"]
        )
        let descriptor = try XCTUnwrap(AppHighRiskActionAudit.descriptor(forTool: "iot.device.toggle"))
        let result = await AppUnavailableHighRiskActionDispatcher().dispatch(
            AppHighRiskActionDispatchRequest(
                app: app,
                descriptor: descriptor,
                tool: "iot.device.toggle",
                arguments: ["state": true]
            )
        )

        XCTAssertEqual(result.receiptOutcome, .approvalRecordedDispatchUnavailable)
        XCTAssertEqual(result.rejectionMessage, "Agent tool dispatch is not available in this build")
    }

    @MainActor
    func testFrameworkHighRiskActionDispatcherKeepsGenericActionsAndSecretsUnavailable() async throws {
        let app = AppRecord(
            slug: "ops-panel",
            name: "Ops Panel",
            declaredCapabilities: ["actions.invoke", "secrets.broker"]
        )
        let actions = try XCTUnwrap(AppCapabilityCatalog.descriptor(id: "actions.invoke"))
        let secrets = try XCTUnwrap(AppCapabilityCatalog.descriptor(id: "secrets.broker"))

        let actionResult = await AppFrameworkHighRiskActionDispatcher().dispatch(
            AppHighRiskActionDispatchRequest(
                app: app,
                descriptor: actions,
                tool: "actions.invoke",
                arguments: ["action": "record.create", "dryRun": true]
            )
        )
        XCTAssertEqual(actionResult.receiptOutcome, .approvalRecordedDispatchUnavailable)
        XCTAssertEqual(
            actionResult.rejectionMessage,
            "Generic framework action dispatch is unavailable until an allowlisted safe runner is registered"
        )

        let secretResult = await AppFrameworkHighRiskActionDispatcher().dispatch(
            AppHighRiskActionDispatchRequest(
                app: app,
                descriptor: secrets,
                tool: "secrets.broker",
                arguments: ["operation": "lease", "secretRef": "secret://service/token"]
            )
        )
        XCTAssertEqual(secretResult.receiptOutcome, .approvalRecordedDispatchUnavailable)
        XCTAssertEqual(
            secretResult.rejectionMessage,
            "Secrets broker dispatch is unavailable until a safe non-plaintext lease/ref runner is registered"
        )
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

    func testAppsSettingsHighRiskAuditPresentationSortsAndSummarizesReceipts() throws {
        let iot = AppRecord(
            slug: "iot-panel",
            name: "IoT Panel",
            declaredCapabilities: ["iot.device.action.invoke"]
        )
        let secrets = AppRecord(
            slug: "secrets-panel",
            name: "Secrets Panel",
            declaredCapabilities: ["secrets.broker"]
        )
        let iotDescriptor = try XCTUnwrap(AppHighRiskActionAudit.descriptor(forTool: "iot.device.toggle"))
        let secretsDescriptor = try XCTUnwrap(AppHighRiskActionAudit.descriptor(forTool: "secrets.read"))
        let approved = AppHighRiskActionReceipt(
            id: "approved",
            app: iot,
            descriptor: iotDescriptor,
            action: "iot.device.toggle",
            decision: .approvedOnce,
            outcome: .approvalRecordedDispatchUnavailable,
            createdAt: Date(timeIntervalSince1970: 1),
            reason: iotDescriptor.summary
        )
        let denied = AppHighRiskActionReceipt(
            id: "denied",
            app: secrets,
            descriptor: secretsDescriptor,
            action: "secrets.read",
            decision: .denied,
            outcome: .denied,
            createdAt: Date(timeIntervalSince1970: 2),
            reason: secretsDescriptor.summary
        )

        let model = AppsSettingsHighRiskAuditSheetModel(entries: [
            AppsSettingsHighRiskAuditEntry(record: iot, receipts: [approved]),
            AppsSettingsHighRiskAuditEntry(record: secrets, receipts: [denied])
        ])

        XCTAssertEqual(model.title, "High-risk action audit")
        XCTAssertEqual(model.subtitle, "All apps")
        XCTAssertEqual(model.emptyMessage, "No high-risk action receipts recorded for installed apps.")
        XCTAssertEqual(model.rows.map(\.id), ["denied", "approved"])
        XCTAssertEqual(model.rows.first?.title, "Secrets Panel · secrets.read")
        XCTAssertEqual(model.rows.first?.symbolName, "xmark.octagon")
        XCTAssertTrue(model.rows.first?.detail.contains("Capability: secrets.broker") == true)
        XCTAssertTrue(model.rows.first?.detail.contains("Decision: denied") == true)
        XCTAssertTrue(model.rows.first?.detail.contains("Outcome: denied") == true)
        XCTAssertTrue(model.rows.first?.detail.contains("Risk tier: critical") == true)
        XCTAssertEqual(model.rows.last?.title, "IoT Panel · iot.device.toggle")
        XCTAssertEqual(model.rows.last?.symbolName, "exclamationmark.shield")
    }

    func testAppsSettingsPerAppHighRiskAuditPresentationOmitsRepeatedAppName() throws {
        let iot = AppRecord(
            slug: "iot-panel",
            name: "IoT Panel",
            declaredCapabilities: ["iot.device.action.invoke"]
        )
        let descriptor = try XCTUnwrap(AppHighRiskActionAudit.descriptor(forTool: "iot.device.toggle"))
        let receipt = AppHighRiskActionReceipt(
            id: "approved",
            app: iot,
            descriptor: descriptor,
            action: "iot.device.toggle",
            decision: .approvedOnce,
            outcome: .approvalRecordedDispatchUnavailable,
            createdAt: Date(timeIntervalSince1970: 1),
            reason: descriptor.summary
        )

        let model = AppsSettingsHighRiskAuditSheetModel(record: iot, receipts: [receipt])

        XCTAssertEqual(model.id, "high-risk-\(iot.id.uuidString)")
        XCTAssertEqual(model.title, "High-risk action audit")
        XCTAssertEqual(model.subtitle, "IoT Panel · iot-panel")
        XCTAssertEqual(model.emptyMessage, "No high-risk action receipts recorded for this app.")
        XCTAssertEqual(model.rows.map(\.title), ["iot.device.toggle"])
        XCTAssertTrue(model.rows[0].detail.contains("Interruptive: yes"))
    }

    func testSwiftSurfaceRunnerPlanRequiresOutOfProcessDSL() throws {
        let app = AppRecord(
            slug: "swift-dashboard",
            name: "Swift Dashboard",
            declaredCapabilities: ["search.query", "db.query"],
            surfaceKind: .swiftDeclarative
        )
        let manifest = AppSwiftSurfaceManifest(
            root: AppSwiftSurfaceNode(
                kind: .stack,
                children: [
                    AppSwiftSurfaceNode(kind: .text, text: "Dashboard"),
                    AppSwiftSurfaceNode(
                        kind: .button,
                        text: "Search",
                        action: AppSwiftSurfaceAction(
                            invocation: .sdkRead,
                            capabilityId: "search.query",
                            operation: "search.query"
                        )
                    )
                ]
            ),
            requestedCapabilities: ["search.query", "db.query"]
        )

        let plan = try AppSwiftSurfaceContract.runnerPlan(
            app: app,
            manifest: manifest,
            manifestPath: "/tmp/swift-dashboard/surface.json"
        )

        XCTAssertEqual(plan.appId, app.id)
        XCTAssertEqual(plan.protocolVersion, 1)
        XCTAssertEqual(plan.outOfProcess, true)
        XCTAssertEqual(plan.allowedCapabilities, ["db.query", "search.query"])
    }

    func testSwiftSurfaceRenderPresentationBuildsDeclarativeTree() throws {
        let app = AppRecord(
            slug: "swift-dashboard",
            name: "Swift Dashboard",
            declaredCapabilities: ["search.query", "iot.device.action.invoke"],
            surfaceKind: .swiftDeclarative
        )
        let manifest = AppSwiftSurfaceManifest(
            root: AppSwiftSurfaceNode(
                kind: .stack,
                children: [
                    AppSwiftSurfaceNode(kind: .text, text: "Dashboard"),
                    AppSwiftSurfaceNode(
                        kind: .list,
                        dataSource: "search.results",
                        children: [
                            AppSwiftSurfaceNode(
                                kind: .button,
                                id: "search-button",
                                text: "Search",
                                action: AppSwiftSurfaceAction(
                                    invocation: .sdkRead,
                                    capabilityId: "search.query",
                                    operation: "search.query"
                                )
                            ),
                            AppSwiftSurfaceNode(
                                kind: .button,
                                text: "Toggle",
                                action: AppSwiftSurfaceAction(
                                    invocation: .sdkAction,
                                    capabilityId: "iot.device.action.invoke",
                                    operation: "iot.device.toggle"
                                )
                            )
                        ]
                    )
                ]
            ),
            requestedCapabilities: ["search.query", "iot.device.action.invoke"]
        )
        let plan = try AppSwiftSurfaceContract.runnerPlan(
            app: app,
            manifest: manifest,
            manifestPath: "/tmp/swift-dashboard/surface.json"
        )

        let presentation = AppSwiftSurfaceRenderPresentation(
            record: app,
            manifest: manifest,
            plan: plan
        )

        XCTAssertEqual(presentation.title, "Swift Dashboard")
        XCTAssertEqual(presentation.capabilitiesSummary, "iot.device.action.invoke, search.query")
        XCTAssertEqual(presentation.root.kind, .stack)
        XCTAssertEqual(presentation.root.children[0].label, "Dashboard")
        XCTAssertEqual(presentation.root.children[1].kind, .list)
        XCTAssertEqual(presentation.root.children[1].dataSource, "search.results")
        let readButton = presentation.root.children[1].children[0]
        XCTAssertEqual(readButton.id, "search-button")
        XCTAssertEqual(readButton.label, "Search")
        XCTAssertEqual(readButton.action?.operation, "search.query")
        XCTAssertEqual(readButton.action?.riskTier, .low)
        XCTAssertEqual(readButton.action?.requiresApproval, false)
        let actionButton = presentation.root.children[1].children[1]
        XCTAssertEqual(actionButton.label, "Toggle")
        XCTAssertEqual(actionButton.action?.capabilityId, "iot.device.action.invoke")
        XCTAssertEqual(actionButton.action?.riskTier, .high)
        XCTAssertEqual(actionButton.action?.requiresApproval, true)
    }

    func testSwiftSurfaceManifestDecodesAndRunnerPathIsExplicit() throws {
        let json = """
        {
          "schemaVersion": 1,
          "requestedCapabilities": ["search.query"],
          "root": {
            "kind": "button",
            "text": "Search",
            "action": {
              "invocation": "sdkRead",
              "capabilityId": "search.query",
              "operation": "search.query",
              "arguments": {
                "query": "agent",
                "limit": 5
              }
            },
            "children": []
          }
        }
        """.data(using: .utf8)!

        let manifest = try AppSwiftSurfaceContract.decodeManifest(data: json)

        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.requestedCapabilities, ["search.query"])
        XCTAssertEqual(manifest.root.action?.arguments?["query"], .string("agent"))
        XCTAssertEqual(manifest.root.action?.arguments?["limit"], .int(5))
        XCTAssertNil(AppSwiftSurfaceContract.runnerExecutablePath(environment: [:]))
        XCTAssertNil(
            AppSwiftSurfaceContract.runnerExecutablePath(environment: ["CLAWIX_SWIFT_SURFACE_RUNNER": "   "])
        )
        XCTAssertEqual(
            AppSwiftSurfaceContract.runnerExecutablePath(environment: ["CLAWIX_SWIFT_SURFACE_RUNNER": "/tmp/runner"]),
            "/tmp/runner"
        )
    }

    func testSwiftSurfaceRunnerExecutablePathFallsBackToBundledHelper() throws {
        XCTAssertEqual(AppSwiftSurfaceContract.runnerExecutableName, "ClawixSwiftSurfaceRunner")
        XCTAssertEqual(
            AppSwiftSurfaceContract.runnerExecutablePath(
                environment: ["CLAWIX_SWIFT_SURFACE_RUNNER": "  "],
                bundledExecutablePath: " /Applications/Clawix.app/Contents/Helpers/ClawixSwiftSurfaceRunner "
            ),
            "/Applications/Clawix.app/Contents/Helpers/ClawixSwiftSurfaceRunner"
        )
        XCTAssertEqual(
            AppSwiftSurfaceContract.runnerExecutablePath(
                environment: ["CLAWIX_SWIFT_SURFACE_RUNNER": "/tmp/dev-runner"],
                bundledExecutablePath: "/Applications/Clawix.app/Contents/Helpers/ClawixSwiftSurfaceRunner"
            ),
            "/tmp/dev-runner"
        )
    }

    func testSwiftSurfaceRunnerRenderMessageOverridesHostManifestThroughIPC() throws {
        let app = AppRecord(
            slug: "swift-dashboard",
            name: "Swift Dashboard",
            declaredCapabilities: ["search.query"],
            surfaceKind: .swiftDeclarative
        )
        let fallback = AppSwiftSurfaceManifest(
            root: AppSwiftSurfaceNode(kind: .text, text: "Fallback"),
            requestedCapabilities: ["search.query"]
        )
        let plan = try AppSwiftSurfaceContract.runnerPlan(
            app: app,
            manifest: fallback,
            manifestPath: "/tmp/swift-dashboard/surface.json"
        )
        let message = AppSwiftSurfaceRunnerRenderMessage(
            root: AppSwiftSurfaceNode(
                kind: .button,
                text: "Search",
                action: AppSwiftSurfaceAction(
                    invocation: .sdkRead,
                    capabilityId: "search.query",
                    operation: "search.query"
                )
            ),
            requestedCapabilities: ["search.query"]
        )
        let stdout = String(data: try JSONEncoder().encode(message), encoding: .utf8)!

        let rendered = try AppSwiftSurfaceContract.renderManifest(
            from: AppSwiftSurfaceRunnerResult(exitCode: 0, stdout: stdout),
            fallback: fallback,
            plan: plan,
            app: app
        )

        XCTAssertEqual(rendered.root.kind, .button)
        XCTAssertEqual(rendered.root.text, "Search")
        XCTAssertEqual(rendered.root.action?.capabilityId, "search.query")
    }

    func testSwiftSurfaceRunnerIPCRejectsCapabilitiesOutsideLaunchPlan() throws {
        let app = AppRecord(
            slug: "swift-dashboard",
            name: "Swift Dashboard",
            declaredCapabilities: ["search.query", "iot.device.action.invoke"],
            surfaceKind: .swiftDeclarative
        )
        let fallback = AppSwiftSurfaceManifest(
            root: AppSwiftSurfaceNode(kind: .text, text: "Fallback"),
            requestedCapabilities: ["search.query"]
        )
        let plan = try AppSwiftSurfaceContract.runnerPlan(
            app: app,
            manifest: fallback,
            manifestPath: "/tmp/swift-dashboard/surface.json"
        )
        let message = AppSwiftSurfaceRunnerRenderMessage(
            root: AppSwiftSurfaceNode(
                kind: .button,
                text: "Toggle",
                action: AppSwiftSurfaceAction(
                    invocation: .sdkAction,
                    capabilityId: "iot.device.action.invoke",
                    operation: "iot.device.toggle"
                )
            ),
            requestedCapabilities: ["iot.device.action.invoke"]
        )
        let stdout = String(data: try JSONEncoder().encode(message), encoding: .utf8)!

        XCTAssertThrowsError(
            try AppSwiftSurfaceContract.renderManifest(
                from: AppSwiftSurfaceRunnerResult(exitCode: 0, stdout: stdout),
                fallback: fallback,
                plan: plan,
                app: app
            )
        ) { error in
            XCTAssertEqual(error as? AppSwiftSurfaceValidationError, .runnerCapabilityNotAllowed("iot.device.action.invoke"))
        }
    }

    @MainActor
    func testSwiftSurfaceReadActionDoesNotRequestInterruptiveApproval() async throws {
        let app = AppRecord(
            slug: "swift-dashboard",
            name: "Swift Dashboard",
            declaredCapabilities: ["search.query"],
            surfaceKind: .swiftDeclarative
        )
        var reports: [SurfaceRouteReport] = []
        let reporter = SurfaceRouteReporter(surfaceID: "app:swift-dashboard") { report in
            reports.append(report)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let appsStore = AppsStore(rootURL: root)
        let action = AppSwiftSurfaceRenderedAction(
            action: AppSwiftSurfaceAction(
                invocation: .sdkRead,
                capabilityId: "search.query",
                operation: "search.query"
            )
        )

        let result = await AppSwiftSurfaceActionBridge(
            app: app,
            appsStore: appsStore,
            surfaceReporter: reporter,
            highRiskActionDispatcher: AppUnavailableHighRiskActionDispatcher(),
            approvalHandler: { _, _, _ in
                XCTFail("Read actions should not request interruptive approval")
            }
        ).handle(action)

        XCTAssertEqual(result, .failed("Swift surface search bridge is unavailable"))
        XCTAssertTrue(reports.contains(.error(message: "Swift surface search bridge is unavailable")))
    }

    @MainActor
    func testSwiftSurfaceResourceListExecutesThroughRegisteredResources() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let registryRoot = root.appendingPathComponent("registry", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = AppRecord(
            slug: "swift-dashboard",
            name: "Swift Dashboard",
            declaredCapabilities: ["resources.list"],
            surfaceKind: .swiftDeclarative
        )
        let appsStore = AppsStore(rootURL: root.appendingPathComponent("apps", isDirectory: true))
        let resource = makeResource(
            id: "res_swift1",
            kind: "instruction",
            locator: AppResourceLocator(kind: "path", value: "/tmp/swift-resource.md")
        )
        try writeResources([resource], to: registryRoot)
        let registry = AppResourceRegistryStore(directory: registryRoot)
        var reports: [SurfaceRouteReport] = []
        let reporter = SurfaceRouteReporter(surfaceID: "app:swift-dashboard") { report in
            reports.append(report)
        }
        let action = AppSwiftSurfaceRenderedAction(
            action: AppSwiftSurfaceAction(
                invocation: .sdkRead,
                capabilityId: "resources.list",
                operation: "resources.list",
                arguments: ["kind": .string("instruction")]
            )
        )

        let result = await AppSwiftSurfaceActionBridge(
            app: app,
            appsStore: appsStore,
            resourceRegistry: registry,
            surfaceReporter: reporter,
            highRiskActionDispatcher: AppUnavailableHighRiskActionDispatcher(),
            approvalHandler: { _, _, _ in
                XCTFail("Resource lists should not request interruptive approval")
            }
        ).handle(action)

        XCTAssertEqual(result, .executedRead("resources.list", 1))
        XCTAssertTrue(reports.contains(.loading(message: "Listing Swift surface resources", progress: 0.2)))
        XCTAssertTrue(reports.contains(.partial(message: "Swift surface listed 1 resources")))
    }

    @MainActor
    func testSwiftSurfaceResourceReadExecutesThroughRegisteredResources() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let registryRoot = root.appendingPathComponent("registry", isDirectory: true)
        let fileURL = root.appendingPathComponent("swift-resource.md", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "swift resource content".write(to: fileURL, atomically: true, encoding: .utf8)
        let app = AppRecord(
            slug: "swift-dashboard",
            name: "Swift Dashboard",
            declaredCapabilities: ["resources.read"],
            surfaceKind: .swiftDeclarative
        )
        let appsStore = AppsStore(rootURL: root.appendingPathComponent("apps", isDirectory: true))
        let resource = makeResource(
            id: "res_swift1",
            kind: "instruction",
            locator: AppResourceLocator(kind: "path", value: fileURL.path)
        )
        try writeResources([resource], to: registryRoot)
        let registry = AppResourceRegistryStore(directory: registryRoot)
        var reports: [SurfaceRouteReport] = []
        let reporter = SurfaceRouteReporter(surfaceID: "app:swift-dashboard") { report in
            reports.append(report)
        }
        let action = AppSwiftSurfaceRenderedAction(
            action: AppSwiftSurfaceAction(
                invocation: .sdkRead,
                capabilityId: "resources.read",
                operation: "resources.read",
                arguments: [
                    "id": .string("res_swift1"),
                    "maxBytes": .int(5)
                ]
            )
        )

        let result = await AppSwiftSurfaceActionBridge(
            app: app,
            appsStore: appsStore,
            resourceRegistry: registry,
            surfaceReporter: reporter,
            highRiskActionDispatcher: AppUnavailableHighRiskActionDispatcher(),
            approvalHandler: { _, _, _ in
                XCTFail("Resource reads should not request interruptive approval")
            }
        ).handle(action)

        XCTAssertEqual(result, .executedRead("resources.read", 1))
        XCTAssertTrue(reports.contains(.loading(message: "Reading Swift surface resource", progress: 0.2)))
        XCTAssertTrue(reports.contains(.partial(message: "Swift surface read resource: res_swift1")))
    }

    @MainActor
    func testSwiftSurfaceDBQueryExecutesThroughDatabaseManager() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let appsStore = AppsStore(rootURL: root)
        let client = AppCustomSurfaceFakeDatabaseClient()
        client.onListRecords = { namespace, collection, filter, sort, limit, offset in
            XCTAssertEqual(namespace, "clawix-local")
            XCTAssertEqual(collection, "tasks")
            XCTAssertEqual(filter?["status"] as? String, "todo")
            XCTAssertEqual(sort, "-updatedAt")
            XCTAssertEqual(limit, 10)
            XCTAssertEqual(offset, 0)
            return DBListResponse(total: 1, items: [
                self.makeDBRecord(id: "task-1", title: "Launch", status: "todo")
            ])
        }
        let manager = DatabaseManager(
            userDefaults: try makeDefaults(),
            client: client,
            attachSupervisor: false,
            initialState: .ready,
            initialCollections: [makeCollection("tasks")]
        )
        let app = AppRecord(
            slug: "swift-dashboard",
            name: "Swift Dashboard",
            declaredCapabilities: ["db.query"],
            surfaceKind: .swiftDeclarative
        )
        var reports: [SurfaceRouteReport] = []
        let reporter = SurfaceRouteReporter(surfaceID: "app:swift-dashboard") { report in
            reports.append(report)
        }
        let action = AppSwiftSurfaceRenderedAction(
            action: AppSwiftSurfaceAction(
                invocation: .sdkRead,
                capabilityId: "db.query",
                operation: "db.query",
                arguments: [
                    "collection": .string("tasks"),
                    "filter": .object(["status": .string("todo")]),
                    "sort": .string("-updatedAt"),
                    "limit": .int(10)
                ]
            )
        )

        let result = await AppSwiftSurfaceActionBridge(
            app: app,
            appsStore: appsStore,
            databaseManager: manager,
            surfaceReporter: reporter,
            highRiskActionDispatcher: AppUnavailableHighRiskActionDispatcher()
        ).handle(action)

        XCTAssertEqual(result, .executedRead("db.query", 1))
        XCTAssertEqual(client.listRecordsCallCount, 1)
        XCTAssertTrue(reports.contains(.partial(message: "Swift surface queried 1 database records")))
    }

    @MainActor
    func testSwiftSurfaceSearchQueryExecutesThroughDatabaseManager() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let appsStore = AppsStore(rootURL: root)
        let client = AppCustomSurfaceFakeDatabaseClient()
        client.onListRecords = { _, collection, _, sort, limit, offset in
            XCTAssertEqual(collection, "tasks")
            XCTAssertEqual(sort, "-updatedAt")
            XCTAssertEqual(limit, 100)
            XCTAssertEqual(offset, 0)
            return DBListResponse(total: nil, items: [
                self.makeDBRecord(id: "task-1", title: "Launch agent", status: "todo"),
                self.makeDBRecord(id: "task-2", title: "Ignore", status: "done")
            ])
        }
        let manager = DatabaseManager(
            userDefaults: try makeDefaults(),
            client: client,
            attachSupervisor: false,
            initialState: .ready,
            initialCollections: [makeCollection("tasks")]
        )
        let app = AppRecord(
            slug: "swift-dashboard",
            name: "Swift Dashboard",
            declaredCapabilities: ["search.query"],
            surfaceKind: .swiftDeclarative
        )
        var reports: [SurfaceRouteReport] = []
        let reporter = SurfaceRouteReporter(surfaceID: "app:swift-dashboard") { report in
            reports.append(report)
        }
        let action = AppSwiftSurfaceRenderedAction(
            action: AppSwiftSurfaceAction(
                invocation: .sdkRead,
                capabilityId: "search.query",
                operation: "search.query",
                arguments: [
                    "query": .string("agent"),
                    "collections": .array([.string("tasks")]),
                    "limit": .int(5)
                ]
            )
        )

        let result = await AppSwiftSurfaceActionBridge(
            app: app,
            appsStore: appsStore,
            databaseManager: manager,
            surfaceReporter: reporter,
            highRiskActionDispatcher: AppUnavailableHighRiskActionDispatcher()
        ).handle(action)

        XCTAssertEqual(result, .executedRead("search.query", 1))
        XCTAssertEqual(client.listRecordsCallCount, 1)
        XCTAssertTrue(reports.contains(.partial(message: "Swift surface found 1 search results")))
    }

    @MainActor
    func testSwiftSurfaceHighRiskActionUsesApprovalDispatcherAndAudit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let appsStore = AppsStore(rootURL: root)
        let app = AppRecord(
            slug: "swift-iot-dashboard",
            name: "Swift IoT Dashboard",
            declaredCapabilities: ["iot.device.action.invoke"],
            surfaceKind: .swiftDeclarative
        )
        let dispatcher = RecordingSwiftSurfaceActionDispatcher(result: .dispatched(["ok": true]))
        let action = AppSwiftSurfaceRenderedAction(
            action: AppSwiftSurfaceAction(
                invocation: .sdkAction,
                capabilityId: "iot.device.action.invoke",
                operation: "iot.device.toggle"
            )
        )

        let result = await AppSwiftSurfaceActionBridge(
            app: app,
            appsStore: appsStore,
            highRiskActionDispatcher: dispatcher,
            approvalHandler: { _, _, completion in completion(.once) }
        ).handle(action)

        XCTAssertEqual(result, .dispatched(.dispatched))
        XCTAssertEqual(dispatcher.requests.map(\.tool), ["iot.device.toggle"])
        XCTAssertEqual(dispatcher.requests.first?.descriptor.id, "iot.device.action.invoke")
        let receipts = try AppHighRiskActionAudit.read(from: appsStore.highRiskActionAuditURL(for: app))
        XCTAssertEqual(receipts.count, 1)
        XCTAssertEqual(receipts[0].capabilityId, "iot.device.action.invoke")
        XCTAssertEqual(receipts[0].action, "iot.device.toggle")
        XCTAssertEqual(receipts[0].decision, .approvedOnce)
        XCTAssertEqual(receipts[0].outcome, .dispatched)
    }

    func testSwiftSurfaceDSLRejectsUnknownCapabilities() {
        let app = AppRecord(
            slug: "swift-dashboard",
            name: "Swift Dashboard",
            declaredCapabilities: ["unknown.future"],
            surfaceKind: .swiftDeclarative
        )
        let manifest = AppSwiftSurfaceManifest(
            root: AppSwiftSurfaceNode(kind: .text, text: "Dashboard"),
            requestedCapabilities: ["unknown.future"]
        )

        XCTAssertThrowsError(try AppSwiftSurfaceContract.validate(manifest: manifest, for: app)) { error in
            XCTAssertEqual(error as? AppSwiftSurfaceValidationError, .unknownCapability("unknown.future"))
        }
    }

    func testSwiftSurfaceDSLRejectsHighRiskCapabilityAsRead() {
        let app = AppRecord(
            slug: "swift-iot-dashboard",
            name: "Swift IoT Dashboard",
            declaredCapabilities: ["iot.device.action.invoke"],
            surfaceKind: .swiftDeclarative
        )
        let manifest = AppSwiftSurfaceManifest(
            root: AppSwiftSurfaceNode(
                kind: .button,
                text: "Toggle",
                action: AppSwiftSurfaceAction(
                    invocation: .sdkRead,
                    capabilityId: "iot.device.action.invoke",
                    operation: "iot.device.toggle"
                )
            ),
            requestedCapabilities: ["iot.device.action.invoke"]
        )

        XCTAssertThrowsError(try AppSwiftSurfaceContract.validate(manifest: manifest, for: app)) { error in
            XCTAssertEqual(error as? AppSwiftSurfaceValidationError, .highRiskRead("iot.device.action.invoke"))
        }
    }

    func testSwiftSurfaceDSLAllowsHighRiskOnlyAsApprovalAction() throws {
        let app = AppRecord(
            slug: "swift-iot-dashboard",
            name: "Swift IoT Dashboard",
            declaredCapabilities: ["iot.device.action.invoke"],
            surfaceKind: .swiftDeclarative
        )
        let manifest = AppSwiftSurfaceManifest(
            root: AppSwiftSurfaceNode(
                kind: .button,
                text: "Toggle",
                action: AppSwiftSurfaceAction(
                    invocation: .sdkAction,
                    capabilityId: "iot.device.action.invoke",
                    operation: "iot.device.toggle"
                )
            ),
            requestedCapabilities: ["iot.device.action.invoke"]
        )

        XCTAssertNoThrow(try AppSwiftSurfaceContract.validate(manifest: manifest, for: app))
    }

    func testSwiftSurfaceRunnerSupervisorClassifiesCleanExit() throws {
        let launch = try makeSwiftRunnerLaunch(
            result: AppSwiftSurfaceRunnerResult(pid: 42, exitCode: 0)
        )
        let supervisor = AppSwiftSurfaceRunnerSupervisor(executor: RecordingSwiftRunnerExecutor(result: launch.result))

        let state = supervisor.launch(launch.launch)

        XCTAssertEqual(state, .exited(code: 0))
        XCTAssertEqual(supervisor.state, .exited(code: 0))
    }

    func testSwiftSurfaceRunnerSupervisorConvertsCrashToSurfaceState() throws {
        let launch = try makeSwiftRunnerLaunch(
            result: AppSwiftSurfaceRunnerResult(pid: 42, exitCode: 9, stderr: "runner crashed")
        )
        let supervisor = AppSwiftSurfaceRunnerSupervisor(executor: RecordingSwiftRunnerExecutor(result: launch.result))

        let state = supervisor.launch(launch.launch)

        XCTAssertEqual(state, .crashed(reason: "runner crashed"))
    }

    func testSwiftSurfaceRunnerSupervisorConvertsTimeoutToSurfaceState() throws {
        let launch = try makeSwiftRunnerLaunch(
            result: AppSwiftSurfaceRunnerResult(pid: 42, exitCode: nil, timedOut: true)
        )
        let supervisor = AppSwiftSurfaceRunnerSupervisor(executor: RecordingSwiftRunnerExecutor(result: launch.result))

        let state = supervisor.launch(launch.launch)

        XCTAssertEqual(state, .timedOut(seconds: 3))
    }

    func testSwiftSurfaceRunnerSupervisorConvertsCancellationToSurfaceState() throws {
        let launch = try makeSwiftRunnerLaunch(
            result: AppSwiftSurfaceRunnerResult(pid: 42, exitCode: nil, cancelled: true)
        )
        let supervisor = AppSwiftSurfaceRunnerSupervisor(executor: RecordingSwiftRunnerExecutor(result: launch.result))

        let state = supervisor.launch(launch.launch)

        XCTAssertEqual(state, .cancelled)
    }

    func testSwiftSurfaceProcessExecutorTerminatesProcessWhenTaskIsCancelled() async throws {
        let executable = try makeCancellableSwiftRunnerFixture()
        var launch = try makeSwiftRunnerLaunch(
            result: AppSwiftSurfaceRunnerResult(pid: 42, exitCode: 0)
        ).launch
        launch.executablePath = executable.path
        launch.timeoutSeconds = 10

        let task = Task {
            AppSwiftSurfaceProcessExecutor().run(launch)
        }
        try await Task.sleep(nanoseconds: 150_000_000)
        task.cancel()
        let result = await task.value

        XCTAssertTrue(result.cancelled)
        XCTAssertFalse(result.timedOut)
        XCTAssertNil(result.exitCode)
    }

    func testSwiftSurfaceRunnerSupervisorRejectsInProcessPlans() throws {
        var launch = try makeSwiftRunnerLaunch(
            result: AppSwiftSurfaceRunnerResult(pid: 42, exitCode: 0)
        ).launch
        launch.plan.outOfProcess = false
        let supervisor = AppSwiftSurfaceRunnerSupervisor(executor: RecordingSwiftRunnerExecutor(result: .init(pid: 42, exitCode: 0)))

        let state = supervisor.launch(launch)

        XCTAssertEqual(state, .crashed(reason: "Swift surface runner must be out-of-process."))
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

    func testActivationReviewPresentationIncludesPackageProvenance() {
        let record = AppRecord(
            slug: "imported-known-panel",
            name: "Imported Known Panel",
            declaredCapabilities: ["search.query", "db.query"],
            originClass: .imported,
            packageProvenance: AppPackageProvenance(
                importedAt: Date(timeIntervalSince1970: 0),
                importedBy: "Tester",
                sourcePath: "/tmp/focus-panel",
                sourceSlug: "focus-panel",
                sourceOriginClass: .localUserAuthored,
                packageKind: "folder",
                signatureStatus: .verified,
                signatureKeyId: "local-test-key",
                signatureTrustSource: "host-marketplace-test",
                packageDigestSHA256: "abc123",
                reviewReason: "Imported packages require local review before activation."
            )
        )
        let riskMap = AppCapabilityCatalog.riskMap(for: record)

        let presentation = AppActivationReviewPresentation(record: record, riskMap: riskMap)

        XCTAssertTrue(presentation.lines.contains(AppActivationReviewLine(title: "Imported from", value: "/tmp/focus-panel")))
        XCTAssertTrue(presentation.lines.contains(AppActivationReviewLine(title: "Source slug", value: "focus-panel")))
        XCTAssertTrue(presentation.lines.contains(AppActivationReviewLine(title: "Source origin", value: "localUserAuthored")))
        XCTAssertTrue(presentation.lines.contains(AppActivationReviewLine(title: "Signature", value: "Verified")))
        XCTAssertTrue(presentation.lines.contains(AppActivationReviewLine(title: "Signature key", value: "local-test-key")))
        XCTAssertTrue(presentation.lines.contains(AppActivationReviewLine(title: "Trust source", value: "host-marketplace-test")))
        XCTAssertTrue(presentation.lines.contains(AppActivationReviewLine(title: "Package SHA-256", value: "abc123")))
        XCTAssertTrue(presentation.lines.contains(AppActivationReviewLine(title: "Review reason", value: "Imported packages require local review before activation.")))
    }

    func testAppsSettingsTrustPresentationIncludesPackageProvenance() {
        let record = AppRecord(
            slug: "imported-known-panel",
            name: "Imported Known Panel",
            originClass: .imported,
            packageProvenance: AppPackageProvenance(
                importedAt: Date(timeIntervalSince1970: 0),
                importedBy: "Tester",
                sourcePath: "/tmp/focus-panel",
                sourceSlug: "focus-panel",
                sourceOriginClass: .localUserAuthored,
                packageKind: "folder",
                signatureStatus: .verified,
                signatureKeyId: "local-test-key",
                signatureTrustSource: "host-marketplace-test",
                packageDigestSHA256: "abc123"
            )
        )

        let presentation = AppsSettingsTrustPresentation(record: record)

        XCTAssertEqual(presentation.statusLabel, "Imported")
        XCTAssertEqual(presentation.symbolName, "tray.and.arrow.down")
        XCTAssertEqual(presentation.tone, .normal)
        XCTAssertTrue(presentation.helpText.contains("Origin: imported"))
        XCTAssertTrue(presentation.helpText.contains("Signature: Verified"))
        XCTAssertTrue(presentation.helpText.contains("Signature key: local-test-key"))
        XCTAssertTrue(presentation.helpText.contains("Trust source: host-marketplace-test"))
        XCTAssertTrue(presentation.helpText.contains("Package SHA-256: abc123"))
        XCTAssertTrue(presentation.helpText.contains("Source slug: focus-panel"))
        XCTAssertTrue(presentation.helpText.contains("Source path: /tmp/focus-panel"))
    }

    func testAppsSettingsTrustAuditPresentationSortsAndSummarizesEvents() {
        let record = AppRecord(
            slug: "imported-known-panel",
            name: "Imported Known Panel",
            declaredCapabilities: ["search.query", "iot.device.action.invoke"],
            originClass: .imported,
            packageProvenance: AppPackageProvenance(
                importedAt: Date(timeIntervalSince1970: 0),
                importedBy: "Tester",
                sourcePath: "/tmp/focus-panel",
                sourceSlug: "focus-panel",
                sourceOriginClass: .localUserAuthored,
                packageKind: "folder",
                signatureStatus: .verified,
                signatureKeyId: "local-test-key",
                signatureTrustSource: "host-marketplace-test",
                packageDigestSHA256: "abc123"
            )
        )
        let riskMap = AppCapabilityCatalog.riskMap(for: record)
        let imported = AppTrustAuditEvent(
            id: "import",
            app: record,
            eventType: .packageImported,
            actor: "Tester",
            createdAt: Date(timeIntervalSince1970: 1),
            reason: "Imported package requires review."
        )
        let approved = AppTrustAuditEvent(
            id: "approve",
            app: record,
            eventType: .activationApproved,
            actor: "Tester",
            createdAt: Date(timeIntervalSince1970: 2),
            riskMap: riskMap,
            reason: "Activation approved."
        )

        let model = AppsSettingsTrustAuditSheetModel(record: record, events: [imported, approved])

        XCTAssertEqual(model.title, "Trust audit")
        XCTAssertEqual(model.subtitle, "Imported Known Panel · imported-known-panel")
        XCTAssertEqual(model.emptyMessage, "No trust events recorded for this app.")
        XCTAssertEqual(model.rows.map(\.id), ["approve", "import"])
        XCTAssertEqual(model.rows.first?.title, "Activation approved")
        XCTAssertTrue(model.rows.first?.detail.contains("Risk map: \(AppCapabilityCatalog.source)") == true)
        XCTAssertTrue(model.rows.first?.detail.contains("Ordinary: search.query") == true)
        XCTAssertTrue(model.rows.first?.detail.contains("Approval: iot.device.action.invoke") == true)
        XCTAssertTrue(model.rows.first?.detail.contains("High risk: iot.device.action.invoke") == true)
        XCTAssertEqual(model.rows.last?.title, "Package imported")
        XCTAssertTrue(model.rows.last?.detail.contains("Signature: Verified") == true)
        XCTAssertTrue(model.rows.last?.detail.contains("Signature key: local-test-key") == true)
        XCTAssertTrue(model.rows.last?.detail.contains("Trust source: host-marketplace-test") == true)
        XCTAssertTrue(model.rows.last?.detail.contains("Package SHA-256: abc123") == true)
        XCTAssertTrue(model.rows.last?.detail.contains("Source path: /tmp/focus-panel") == true)
    }

    func testAppsSettingsGlobalTrustAuditPresentationSortsAcrossApps() {
        let first = AppRecord(
            slug: "first-panel",
            name: "First Panel",
            declaredCapabilities: ["search.query"],
            originClass: .imported
        )
        let second = AppRecord(
            slug: "second-panel",
            name: "Second Panel",
            declaredCapabilities: ["db.query"],
            originClass: .marketplace
        )
        let firstEvent = AppTrustAuditEvent(
            id: "first-import",
            app: first,
            eventType: .packageImported,
            actor: "Tester",
            createdAt: Date(timeIntervalSince1970: 1),
            reason: "First imported."
        )
        let secondEvent = AppTrustAuditEvent(
            id: "second-approve",
            app: second,
            eventType: .activationApproved,
            actor: "Tester",
            createdAt: Date(timeIntervalSince1970: 3),
            riskMap: AppCapabilityCatalog.riskMap(for: second),
            reason: "Second approved."
        )

        let model = AppsSettingsTrustAuditSheetModel(entries: [
            AppsSettingsTrustAuditEntry(record: first, events: [firstEvent]),
            AppsSettingsTrustAuditEntry(record: second, events: [secondEvent])
        ])

        XCTAssertEqual(model.title, "Trust audit")
        XCTAssertEqual(model.subtitle, "All apps")
        XCTAssertEqual(model.emptyMessage, "No trust events recorded for installed apps.")
        XCTAssertEqual(model.rows.map(\.id), ["second-approve", "first-import"])
        XCTAssertEqual(model.rows.first?.title, "Second Panel · Activation approved")
        XCTAssertTrue(model.rows.first?.detail.contains("Risk map: \(AppCapabilityCatalog.source)") == true)
        XCTAssertEqual(model.rows.last?.title, "First Panel · Package imported")
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

    func testBlockedCapabilitiesBlockActivationEvenAfterReview() {
        let record = AppRecord(
            slug: "blocked-stream-panel",
            name: "Blocked Stream Panel",
            declaredCapabilities: ["jobs.stream", "jobs.start", "jobs.cancel"],
            originClass: .localUserAuthored,
            activationReview: AppActivationReview(approvedBy: "Test", riskMapSource: AppCapabilityCatalog.source)
        )

        let riskMap = AppCapabilityCatalog.riskMap(for: record)

        XCTAssertEqual(riskMap.blocked, ["jobs.stream", "jobs.start", "jobs.cancel"])
        XCTAssertEqual(riskMap.ordinaryAccess, [])
        XCTAssertEqual(AppCapabilityCatalog.activationGate(for: record), .blockedCapabilities(["jobs.stream", "jobs.start", "jobs.cancel"]))
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
        XCTAssertTrue(ClawixAppsSDKJS.contains("capabilities.get"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("capabilities.contracts"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("capabilities.source"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("capabilities.riskMap"))
    }

    func testInjectedAppsSdkExposesMacPlanOnlyFacade() {
        XCTAssertTrue(ClawixAppsSDKJS.contains("mac.action.plan"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("planAction"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("dryRun: true"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("execute: false"))
    }

    func testInjectedAppsSdkExposesIoTActionFacade() {
        XCTAssertTrue(ClawixAppsSDKJS.contains("iot.device.action.invoke"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("invokeAction"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("homeId"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("targets"))
    }

    func testInjectedAppsSdkExposesActionsAndSecretsBrokerFacades() {
        XCTAssertTrue(ClawixAppsSDKJS.contains("actions.invoke"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("secrets.broker"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("secretRef"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("ttlSeconds"))
        XCTAssertFalse(ClawixAppsSDKJS.contains("secrets.read"))
    }

    func testInjectedAppsSdkExposesJobsListFacade() {
        XCTAssertTrue(ClawixAppsSDKJS.contains("jobs.list"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("jobs.get"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("jobs.events"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("kind"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("status"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("limit"))
    }

    func testHostBridgeExposesCustomAppSDKContractPayload() throws {
        let record = AppRecord(
            slug: "dashboard",
            name: "Dashboard",
            createdByChatId: nil,
            declaredCapabilities: ["search.query", "db.query", "jobs.list", "jobs.get", "jobs.events", "resources.list", "resources.read", "actions.invoke"]
        )
        let payload = AppCapabilityCatalog.contractsBridgeValue(for: record)
        XCTAssertEqual(payload["schemaVersion"] as? Int, 1)
        XCTAssertEqual(payload["hostBridgeRole"] as? String, "sdk_host_bridge_contract_resource")
        XCTAssertEqual(payload["richUiRuntime"] as? String, "sdk_host_bridge_not_cli_process")
        XCTAssertEqual(payload["missingSchemaRefs"] as? [String], [])
        let executionBoundary = try XCTUnwrap(payload["executionBoundary"] as? [String: Any])
        XCTAssertEqual(executionBoundary["kind"] as? String, "metadata_only_contract_catalog")
        XCTAssertEqual(executionBoundary["executesCapabilityCalls"] as? Bool, false)
        XCTAssertEqual(executionBoundary["richUiExecutionPath"] as? String, "sdk_host_bridge")
        XCTAssertEqual(executionBoundary["localExecutableSurface"] as? String, "host_bridge")
        XCTAssertEqual(executionBoundary["hostBridgeImplementation"] as? String, "window.clawix")
        XCTAssertEqual(executionBoundary["dbSearchExecution"] as? String, "host_bridge_only")
        let nonExecutableSurfaces = try XCTUnwrap(executionBoundary["nonExecutableSurfaces"] as? [String])
        XCTAssertTrue(nonExecutableSurfaces.contains("cli.inspect"))
        XCTAssertTrue(nonExecutableSurfaces.contains("mcp.custom_app_sdk"))
        XCTAssertTrue(nonExecutableSurfaces.contains("relay.remote.custom_app_sdk"))
        XCTAssertTrue((payload["schemaRefs"] as? [String])?.contains("claw.search.query.v1") == true)
        XCTAssertTrue((payload["schemaRefs"] as? [String])?.contains("claw.resources.list.v1") == true)
        XCTAssertTrue((payload["schemaRefs"] as? [String])?.contains("claw.resources.listResult.v1") == true)
        XCTAssertTrue((payload["schemaRefs"] as? [String])?.contains("claw.jobs.list.v1") == true)
        XCTAssertTrue((payload["schemaRefs"] as? [String])?.contains("claw.jobs.listResult.v1") == true)
        XCTAssertTrue((payload["schemaRefs"] as? [String])?.contains("claw.jobs.get.v1") == true)
        XCTAssertTrue((payload["schemaRefs"] as? [String])?.contains("claw.jobs.detail.v1") == true)
        XCTAssertTrue((payload["schemaRefs"] as? [String])?.contains("claw.jobs.events.v1") == true)
        XCTAssertTrue((payload["schemaRefs"] as? [String])?.contains("claw.jobs.eventsResult.v1") == true)
        XCTAssertTrue((payload["schemaRefs"] as? [String])?.contains("claw.mac.actionRequest.v1") == true)
        XCTAssertTrue((payload["referencedSchemaRefs"] as? [String])?.contains("claw.customApp.request.partial.v1") == true)
        XCTAssertTrue((payload["referencedSchemaRefs"] as? [String])?.contains("claw.actions.invoke.v1") == true)
        let riskMap = try XCTUnwrap(payload["riskMap"] as? [String: Any])
        XCTAssertEqual(riskMap["authorityModel"] as? String, "localWideReadsHighRiskApproval")
        XCTAssertTrue((riskMap["ordinaryAccess"] as? [String])?.contains("db.query") == true)
        XCTAssertTrue((riskMap["ordinaryAccess"] as? [String])?.contains("jobs.list") == true)
        XCTAssertTrue((riskMap["ordinaryAccess"] as? [String])?.contains("jobs.get") == true)
        XCTAssertTrue((riskMap["ordinaryAccess"] as? [String])?.contains("jobs.events") == true)
        XCTAssertTrue((riskMap["ordinaryAccess"] as? [String])?.contains("resources.list") == true)
        XCTAssertTrue((riskMap["approvalRequired"] as? [String])?.contains("actions.invoke") == true)
        let capabilities = try XCTUnwrap(payload["capabilities"] as? [[String: Any]])
        let blockedStream = try XCTUnwrap(capabilities.first { $0["id"] as? String == "jobs.stream" })
        XCTAssertEqual(blockedStream["customAppAccess"] as? String, "blocked")
        XCTAssertEqual(blockedStream["surfaces"] as? [[String: String]], AppCapabilityCatalog.blockedSurfaceBindingsBridgeValue)
        let blockedStreamDispatch = try XCTUnwrap(blockedStream["dispatch"] as? [String: Any])
        XCTAssertEqual(blockedStreamDispatch["status"] as? String, "unavailable")
        XCTAssertEqual(blockedStreamDispatch["mode"] as? String, "blocked")
        XCTAssertEqual(blockedStreamDispatch["approvalRequired"] as? Bool, false)
        let blockedStart = try XCTUnwrap(capabilities.first { $0["id"] as? String == "jobs.start" })
        XCTAssertEqual(blockedStart["customAppAccess"] as? String, "blocked")
        XCTAssertEqual(blockedStart["surfaces"] as? [[String: String]], AppCapabilityCatalog.blockedSurfaceBindingsBridgeValue)
        let blockedStartDispatch = try XCTUnwrap(blockedStart["dispatch"] as? [String: Any])
        XCTAssertEqual(blockedStartDispatch["status"] as? String, "unavailable")
        XCTAssertEqual(blockedStartDispatch["mode"] as? String, "blocked")
        XCTAssertEqual(blockedStartDispatch["approvalRequired"] as? Bool, false)
        let blockedCancel = try XCTUnwrap(capabilities.first { $0["id"] as? String == "jobs.cancel" })
        XCTAssertEqual(blockedCancel["customAppAccess"] as? String, "blocked")
        XCTAssertEqual(blockedCancel["surfaces"] as? [[String: String]], AppCapabilityCatalog.blockedSurfaceBindingsBridgeValue)
        let blockedCancelDispatch = try XCTUnwrap(blockedCancel["dispatch"] as? [String: Any])
        XCTAssertEqual(blockedCancelDispatch["status"] as? String, "unavailable")
        XCTAssertEqual(blockedCancelDispatch["mode"] as? String, "blocked")
        XCTAssertEqual(blockedCancelDispatch["approvalRequired"] as? Bool, false)
        let resourceList = try XCTUnwrap(capabilities.first { $0["id"] as? String == "resources.list" })
        XCTAssertEqual(resourceList["inputSchemaRef"] as? String, "claw.resources.list.v1")
        XCTAssertEqual(resourceList["outputSchemaRef"] as? String, "claw.resources.listResult.v1")
        let resourceListDispatch = try XCTUnwrap(resourceList["dispatch"] as? [String: Any])
        XCTAssertEqual(resourceListDispatch["mode"] as? String, "localWideRead")
        let resources = try XCTUnwrap(capabilities.first { $0["id"] as? String == "resources.read" })
        XCTAssertEqual(resources["redactionPolicyRef"] as? String, AppBridgeRedactionPolicy.policyId)
        let snapshot = try XCTUnwrap(capabilities.first { $0["id"] as? String == "system.telemetry.snapshot" })
        XCTAssertEqual(snapshot["outputSchemaRef"] as? String, "claw.system.telemetry.snapshot.v1")
        XCTAssertEqual(snapshot["redactionPolicyRef"] as? String, AppBridgeRedactionPolicy.policyId)
        let history = try XCTUnwrap(capabilities.first { $0["id"] as? String == "system.telemetry.history" })
        XCTAssertEqual(history["inputSchemaRef"] as? String, "claw.system.telemetry.history.request.v1")
        let historyDispatch = try XCTUnwrap(history["dispatch"] as? [String: Any])
        XCTAssertEqual(historyDispatch["mode"] as? String, "localWideRead")
        let jobs = try XCTUnwrap(capabilities.first { $0["id"] as? String == "jobs.list" })
        XCTAssertEqual(jobs["inputSchemaRef"] as? String, "claw.jobs.list.v1")
        XCTAssertEqual(jobs["outputSchemaRef"] as? String, "claw.jobs.listResult.v1")
        XCTAssertEqual(jobs["redactionPolicyRef"] as? String, AppBridgeRedactionPolicy.policyId)
        let jobsDispatch = try XCTUnwrap(jobs["dispatch"] as? [String: Any])
        XCTAssertEqual(jobsDispatch["mode"] as? String, "localWideRead")
        let jobDetail = try XCTUnwrap(capabilities.first { $0["id"] as? String == "jobs.get" })
        XCTAssertEqual(jobDetail["inputSchemaRef"] as? String, "claw.jobs.get.v1")
        XCTAssertEqual(jobDetail["outputSchemaRef"] as? String, "claw.jobs.detail.v1")
        XCTAssertEqual(jobDetail["redactionPolicyRef"] as? String, AppBridgeRedactionPolicy.policyId)
        let jobDetailDispatch = try XCTUnwrap(jobDetail["dispatch"] as? [String: Any])
        XCTAssertEqual(jobDetailDispatch["mode"] as? String, "localWideRead")
        let jobEvents = try XCTUnwrap(capabilities.first { $0["id"] as? String == "jobs.events" })
        XCTAssertEqual(jobEvents["inputSchemaRef"] as? String, "claw.jobs.events.v1")
        XCTAssertEqual(jobEvents["outputSchemaRef"] as? String, "claw.jobs.eventsResult.v1")
        XCTAssertEqual(jobEvents["redactionPolicyRef"] as? String, AppBridgeRedactionPolicy.policyId)
        let jobEventsDispatch = try XCTUnwrap(jobEvents["dispatch"] as? [String: Any])
        XCTAssertEqual(jobEventsDispatch["mode"] as? String, "localWideRead")
        let mac = try XCTUnwrap(capabilities.first { $0["id"] as? String == "mac.action.plan" })
        XCTAssertEqual(mac["inputSchemaRef"] as? String, "claw.mac.actionRequest.v1")
        XCTAssertEqual(mac["outputSchemaRef"] as? String, "claw.mac.actionPlan.v1")
        let macDispatch = try XCTUnwrap(mac["dispatch"] as? [String: Any])
        XCTAssertEqual(macDispatch["mode"] as? String, "approvalRequiredPlanOnly")
    }

    func testInjectedAppsSdkExposesSearchAndDBContracts() {
        XCTAssertTrue(ClawixAppsSDKJS.contains("search.query"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("db.query"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("resources.read"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("resources.list"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("jobs.list"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("jobs.get"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("jobs.events"))
        XCTAssertFalse(ClawixAppsSDKJS.contains("jobs.stream"))
        XCTAssertFalse(ClawixAppsSDKJS.contains("jobs.start"))
        XCTAssertFalse(ClawixAppsSDKJS.contains("jobs.cancel"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("system.telemetry.snapshot"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("system.telemetry.history"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("request.cancel"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("request.progress"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("request.partial"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("onProgress"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("onPartial"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("opts.signal"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("opts.cursor"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("opts.facets"))
        XCTAssertFalse(ClawixAppsSDKJS.lowercased().contains("sqlite"))
    }

    func testBridgeOperationPolicyDoesNotExposeEscapeHatches() {
        XCTAssertTrue(AppBridgeOperationPolicy.isAllowed("search.query"))
        XCTAssertTrue(AppBridgeOperationPolicy.isAllowed("db.query"))
        XCTAssertTrue(AppBridgeOperationPolicy.isAllowed("resources.list"))
        XCTAssertTrue(AppBridgeOperationPolicy.isAllowed("resources.read"))
        XCTAssertTrue(AppBridgeOperationPolicy.isAllowed("jobs.list"))
        XCTAssertTrue(AppBridgeOperationPolicy.isAllowed("jobs.get"))
        XCTAssertTrue(AppBridgeOperationPolicy.isAllowed("jobs.events"))
        XCTAssertFalse(AppBridgeOperationPolicy.isAllowed("jobs.stream"))
        XCTAssertFalse(AppBridgeOperationPolicy.isAllowed("jobs.start"))
        XCTAssertFalse(AppBridgeOperationPolicy.isAllowed("jobs.cancel"))
        XCTAssertTrue(AppBridgeOperationPolicy.isAllowed("system.telemetry.snapshot"))
        XCTAssertTrue(AppBridgeOperationPolicy.isAllowed("system.telemetry.history"))
        XCTAssertTrue(AppBridgeOperationPolicy.isAllowed("actions.invoke"))
        XCTAssertTrue(AppBridgeOperationPolicy.isAllowed("secrets.broker"))
        XCTAssertTrue(AppBridgeOperationPolicy.isAllowed("mac.action.plan"))
        XCTAssertTrue(AppBridgeOperationPolicy.isAllowed("iot.device.action.invoke"))
        XCTAssertTrue(AppBridgeOperationPolicy.isAllowed("capabilities.get"))
        XCTAssertTrue(AppBridgeOperationPolicy.isAllowed("capabilities.contracts"))
        XCTAssertTrue(AppBridgeOperationPolicy.isAllowed("capabilities.source"))

        for operation in AppBridgeOperationPolicy.forbiddenEscapeHatchOperations {
            XCTAssertFalse(AppBridgeOperationPolicy.isAllowed(operation), operation)
            XCTAssertFalse(ClawixAppsSDKJS.contains(operation), operation)
        }

        XCTAssertFalse(AppBridgeOperationPolicy.allowedOperations.contains { $0.contains("sqlite") })
        XCTAssertFalse(AppBridgeOperationPolicy.isAllowed("secrets.read"))
        XCTAssertFalse(AppBridgeOperationPolicy.allowedOperations.contains { $0.hasPrefix("cli.") })
        XCTAssertFalse(AppBridgeOperationPolicy.allowedOperations.contains { $0.hasPrefix("fs.") })
        XCTAssertFalse(AppBridgeOperationPolicy.allowedOperations.contains { $0.hasPrefix("process.") })
        XCTAssertFalse(AppBridgeOperationPolicy.allowedOperations.contains { $0.hasPrefix("native.") })
    }

    func testJobsListBridgeValueRedactsRunMetadataThroughSharedPolicy() {
        let run = ClawJSIndexClient.Run(
            id: "run-1",
            monitorId: "monitor-1",
            searchId: "search-1",
            kind: "search.run",
            status: "completed",
            startedAt: "2026-05-20T00:00:00Z",
            endedAt: nil,
            codexSessionId: "session-1",
            error: nil,
            entitiesSeen: 2,
            observationsCount: 3,
            alertsFired: 1,
            tokensIn: 10,
            tokensOut: 20,
            prompt: "Find updates",
            createdAt: "2026-05-20T00:00:01Z"
        )

        let value = AppBridgeMessageHandler.jobBridgeValue(run)

        XCTAssertEqual(value["id"] as? String, "run-1")
        XCTAssertEqual(value["kind"] as? String, "search.run")
        XCTAssertEqual(value["status"] as? String, "completed")
        XCTAssertEqual(value["source"] as? String, "index.runs")
        XCTAssertEqual(value["redactionPolicy"] as? String, AppBridgeRedactionPolicy.policyId)
        let metadata = value["metadata"] as? [String: Any]
        XCTAssertEqual(metadata?["searchId"] as? String, "search-1")
        XCTAssertEqual(metadata?["entitiesSeen"] as? Int, 2)
        XCTAssertEqual(metadata?["hasPrompt"] as? Bool, true)
        XCTAssertNil(metadata?["prompt"])
    }

    func testJobsGetBridgeValueRedactsEntityDetailsThroughSharedPolicy() throws {
        let run = ClawJSIndexClient.Run(
            id: "run-1",
            monitorId: "monitor-1",
            searchId: "search-1",
            kind: "search.run",
            status: "completed",
            startedAt: "2026-05-20T00:00:00Z",
            endedAt: nil,
            codexSessionId: "session-1",
            error: nil,
            entitiesSeen: 1,
            observationsCount: 2,
            alertsFired: 0,
            tokensIn: 10,
            tokensOut: 20,
            prompt: "Find private updates",
            createdAt: "2026-05-20T00:00:01Z"
        )
        let entity = ClawJSIndexClient.Entity(
            id: "entity-1",
            typeId: "type-1",
            typeName: "Task",
            identityKey: "private-identity-key",
            data: ["apiKey": .string("secret")],
            firstSeenAt: "2026-05-20T00:00:00Z",
            lastSeenAt: "2026-05-20T00:00:01Z",
            observationCount: 2,
            sourceUrl: "https://example.invalid/private",
            title: "Launch task",
            thumbnailUrl: "https://example.invalid/private-thumb.png"
        )
        let detail = ClawJSIndexClient.RunDetail(run: run, entities: [entity])

        let value = AppBridgeMessageHandler.jobDetailBridgeValue(detail)

        XCTAssertEqual(value["source"] as? String, "jobs.get")
        XCTAssertEqual(value["redactionPolicy"] as? String, AppBridgeRedactionPolicy.policyId)
        let runValue = try XCTUnwrap(value["run"] as? [String: Any])
        XCTAssertEqual(runValue["id"] as? String, "run-1")
        let entities = try XCTUnwrap(value["entities"] as? [[String: Any]])
        let entityValue = try XCTUnwrap(entities.first)
        XCTAssertEqual(entityValue["id"] as? String, "entity-1")
        XCTAssertEqual(entityValue["typeId"] as? String, "type-1")
        XCTAssertEqual(entityValue["typeName"] as? String, "Task")
        XCTAssertEqual(entityValue["title"] as? String, "Launch task")
        XCTAssertEqual(entityValue["hasSourceUrl"] as? Bool, true)
        XCTAssertEqual(entityValue["hasThumbnail"] as? Bool, true)
        XCTAssertEqual(entityValue["redactionPolicy"] as? String, AppBridgeRedactionPolicy.policyId)
        XCTAssertNil(entityValue["identityKey"])
        XCTAssertNil(entityValue["data"])
        XCTAssertNil(entityValue["sourceUrl"])
        XCTAssertNil(entityValue["thumbnailUrl"])
    }

    func testJobsEventsBridgeValuesDeriveRedactedTimelineFromRuns() throws {
        let run = ClawJSIndexClient.Run(
            id: "run-1",
            monitorId: "monitor-1",
            searchId: "search-1",
            kind: "search.run",
            status: "failed",
            startedAt: "2026-05-20T00:00:00Z",
            endedAt: "2026-05-20T00:00:05Z",
            codexSessionId: "session-1",
            error: "private stack trace",
            entitiesSeen: 2,
            observationsCount: 3,
            alertsFired: 1,
            tokensIn: 10,
            tokensOut: 20,
            prompt: "Find private updates",
            createdAt: "2026-05-19T23:59:59Z"
        )

        let events = AppBridgeMessageHandler.jobEventBridgeValues(run)

        XCTAssertEqual(events.map { $0["kind"] as? String }, ["job.created", "job.started", "job.status", "job.error"])
        let status = try XCTUnwrap(events.first { $0["kind"] as? String == "job.status" })
        XCTAssertEqual(status["id"] as? String, "run-1:status")
        XCTAssertEqual(status["jobId"] as? String, "run-1")
        XCTAssertEqual(status["level"] as? String, "error")
        XCTAssertEqual(status["message"] as? String, "Job status: failed")
        XCTAssertEqual(status["occurredAt"] as? String, "2026-05-20T00:00:05Z")
        XCTAssertEqual(status["source"] as? String, "index.runs")
        XCTAssertEqual(status["redactionPolicy"] as? String, AppBridgeRedactionPolicy.policyId)
        let metadata = try XCTUnwrap(status["metadata"] as? [String: Any])
        XCTAssertEqual(metadata["jobKind"] as? String, "search.run")
        XCTAssertEqual(metadata["searchId"] as? String, "search-1")
        XCTAssertEqual(metadata["hasPrompt"] as? Bool, true)
        XCTAssertEqual(metadata["hasError"] as? Bool, true)
        XCTAssertNil(metadata["prompt"])
        XCTAssertNil(metadata["error"])
    }

    func testSystemTelemetryBridgeValuesMatchSdkContracts() throws {
        let snapshot = SystemTelemetrySnapshotState(
            capturedAt: "2026-05-20T00:00:00Z",
            samples: [
                SystemTelemetrySample(
                    metricKey: "cpu.load",
                    value: 0.25,
                    stringValue: nil,
                    unit: "percent",
                    capturedAt: "2026-05-20T00:00:00Z",
                    source: "system.telemetry.local",
                    confidence: "official"
                ),
                SystemTelemetrySample(
                    metricKey: "focus.mode",
                    value: 0,
                    stringValue: "on",
                    unit: "state",
                    capturedAt: "2026-05-20T00:00:00Z",
                    source: "system.telemetry.local",
                    confidence: "local"
                )
            ],
            unavailableMetricKeys: ["fan.rpm"],
            defaultAgentAccess: "safe_read",
            retentionOwner: "monitor"
        )

        let bridgeSnapshot = AppBridgeMessageHandler.systemTelemetrySnapshotBridgeValue(
            snapshot,
            metricKeys: ["cpu.load", "fan.rpm"],
            includeUnavailable: true
        )
        XCTAssertEqual(bridgeSnapshot["schemaVersion"] as? Int, 1)
        XCTAssertEqual(bridgeSnapshot["source"] as? String, "system.telemetry.snapshot")
        XCTAssertEqual(bridgeSnapshot["redactionPolicy"] as? String, AppBridgeRedactionPolicy.policyId)
        XCTAssertEqual(bridgeSnapshot["unavailableMetrics"] as? [String], ["fan.rpm"])
        let samples = try XCTUnwrap(bridgeSnapshot["samples"] as? [[String: Any]])
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?["key"] as? String, "cpu.load")
        let sampleSource = try XCTUnwrap(samples.first?["source"] as? [String: Any])
        XCTAssertEqual(sampleSource["adapter"] as? String, "signed_host")
        XCTAssertEqual(sampleSource["confidence"] as? String, "official")

        let history = SystemTelemetryHistory(
            metricKey: "cpu.load",
            rangeMS: 3_600_000,
            retentionStatus: "recorded",
            chart: SystemTelemetryHistoryChart(
                kind: "line",
                metricKey: "cpu.load",
                unit: "percent",
                source: "metric_samples",
                points: [
                    SystemTelemetryHistoryPoint(timestampMS: 1, value: 0.1, sourceID: "system.telemetry.local", count: nil),
                    SystemTelemetryHistoryPoint(timestampMS: 2, value: 0.2, sourceID: "system.telemetry.local", count: 2)
                ],
                empty: false
            )
        )
        let bridgeHistory = AppBridgeMessageHandler.systemTelemetryHistoryBridgeValue(history)
        XCTAssertEqual(bridgeHistory["metricKey"] as? String, "cpu.load")
        XCTAssertEqual(bridgeHistory["source"] as? String, "system.telemetry.history")
        XCTAssertEqual(bridgeHistory["redactionPolicy"] as? String, AppBridgeRedactionPolicy.policyId)
        let retention = try XCTUnwrap(bridgeHistory["retention"] as? [String: Any])
        XCTAssertEqual(retention["store"] as? String, "monitor.sqlite")
        XCTAssertEqual(retention["status"] as? String, "recorded")
        let chart = try XCTUnwrap(bridgeHistory["chart"] as? [String: Any])
        XCTAssertEqual(chart["source"] as? String, "metric_samples")
        XCTAssertEqual((chart["points"] as? [[String: Any]])?.count, 2)
    }

    @MainActor
    func testBridgeCancelsTrackedRequestsWhenSurfaceCloses() async {
        let cancelled = expectation(description: "Tracked request cancelled")
        var reports: [SurfaceRouteReport] = []
        let reporter = SurfaceRouteReporter(surfaceID: "app:test") { report in
            reports.append(report)
        }
        let handler = AppBridgeMessageHandler(
            slug: "dashboard",
            appState: nil,
            surfaceReporter: reporter
        )

        handler.startTrackedRequest(requestId: "r-1", label: "Database query") {
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch is CancellationError {
                cancelled.fulfill()
            } catch {
                XCTFail("Unexpected cancellation error: \(error)")
            }
        }

        XCTAssertEqual(handler.activeRequestCount, 1)
        handler.cancelAllTrackedRequests(reason: "Surface closed")

        await fulfillment(of: [cancelled], timeout: 1)
        XCTAssertEqual(handler.activeRequestCount, 0)
        XCTAssertTrue(reports.contains(.loading(message: "Database query", progress: 0)))
        XCTAssertTrue(reports.contains(.partial(message: "Surface closed")))
    }

    func testCancellableBackgroundTaskCancelsDetachedBackgroundWork() async {
        let started = expectation(description: "Detached bridge work started")
        let cancelled = expectation(description: "Detached bridge work cancelled")
        let task = Task {
            try await CancellableBackgroundTask.run {
                started.fulfill()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch is CancellationError {
                    cancelled.fulfill()
                    throw CancellationError()
                }
                return "completed"
            }
        }

        await fulfillment(of: [started], timeout: 1)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected detached bridge work to be cancelled.")
        } catch is CancellationError {
            await fulfillment(of: [cancelled], timeout: 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testResourceRegistryReadsOnlyRegisteredPathResources() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let registryRoot = root.appendingPathComponent("registry", isDirectory: true)
        let fileURL = root.appendingPathComponent("instruction.md", isDirectory: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "read me\nand keep going".write(to: fileURL, atomically: true, encoding: .utf8)

        let resource = makeResource(
            id: "res_instruction1",
            kind: "instruction",
            locator: AppResourceLocator(kind: "path", value: fileURL.path),
            label: "Instruction"
        )
        try writeResources([resource], to: registryRoot)

        let store = AppResourceRegistryStore(directory: registryRoot)
        XCTAssertEqual(try store.list(kind: "instruction").map(\.id), ["res_instruction1"])

        let read = try store.read("res_instruction1", maxBytes: 7)
        XCTAssertEqual(read.content, "read me")
        XCTAssertEqual(read.truncated, true)
        XCTAssertNil(read.error)
        XCTAssertEqual(read.bridgeValue["redactionPolicy"] as? String, AppBridgeRedactionPolicy.policyId)
    }

    func testResourceRegistryRejectsUnregisteredDirectoryAndNonFileResources() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let registryRoot = root.appendingPathComponent("registry", isDirectory: true)
        let registeredDirectory = root.appendingPathComponent("folder", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: registeredDirectory, withIntermediateDirectories: true)

        let secret = makeResource(
            id: "res_secretref1",
            kind: "secret-ref",
            locator: AppResourceLocator(kind: "secret-ref", value: "vault://demo")
        )
        let directory = makeResource(
            id: "res_directory1",
            kind: "folder",
            locator: AppResourceLocator(kind: "path", value: registeredDirectory.path)
        )
        try writeResources([secret, directory], to: registryRoot)

        let store = AppResourceRegistryStore(directory: registryRoot)
        let read = try store.read("res_secretref1")
        XCTAssertNil(read.content)
        XCTAssertEqual(read.error, "Resource res_secretref1 is not a readable filesystem path.")
        let directoryRead = try store.read("res_directory1")
        XCTAssertNil(directoryRead.content)
        XCTAssertEqual(directoryRead.error, "Resource res_directory1 is a directory.")
        XCTAssertThrowsError(try store.read("res_missing1"))
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
            "offset": -10,
            "facets": ["status", "priority"]
        ])

        XCTAssertEqual(query.collection, "tasks")
        XCTAssertEqual(query.search, "launch")
        XCTAssertEqual(query.limit, 100)
        XCTAssertEqual(query.offset, 0)
        XCTAssertEqual(query.effectiveOffset, 0)
        XCTAssertEqual(query.facets, ["status", "priority"])
        XCTAssertEqual(query.sort, DBFilterState.Sort(field: "updatedAt", descending: true))
        XCTAssertEqual(query.backendFilterJSON?["status"] as? String, "todo")
        XCTAssertEqual(query.filterChips.first(where: { $0.field == "archivedAt" })?.op, .isNull)
        XCTAssertEqual(query.filterChips.first(where: { $0.field == "priority" })?.op, .neq)
    }

    func testDBQueryDSLAcceptsOpaqueCursorOverOffset() throws {
        let cursor = AppBridgeDBQuery.cursor(forOffset: 75)

        let query = try AppBridgeQueryDSL.dbQuery(from: [
            "collection": "tasks",
            "offset": 10,
            "cursor": cursor
        ])

        XCTAssertEqual(query.offset, 10)
        XCTAssertEqual(query.cursor, cursor)
        XCTAssertEqual(query.effectiveOffset, 75)
        XCTAssertEqual(AppBridgeDBQuery.offset(fromCursor: "not-a-cursor"), nil)
    }

    func testDBQueryDSLRejectsCollectionEscapesAndDDLKeys() throws {
        let valid = try AppBridgeQueryDSL.dbQuery(from: [
            "collection": "lab_results",
            "filter": ["patientId": "fixture_patient_ada"],
            "limit": 25
        ])
        XCTAssertEqual(valid.collection, "lab_results")

        XCTAssertThrowsError(try AppBridgeQueryDSL.dbQuery(from: [
            "collection": "../core.sqlite",
            "filter": [:]
        ])) { error in
            XCTAssertEqual(error as? AppBridgeQueryDSL.QueryError, .invalidCollection("../core.sqlite"))
        }
        XCTAssertThrowsError(try AppBridgeQueryDSL.dbQuery(from: [
            "collection": "sqlite_master",
            "filter": [:]
        ])) { error in
            XCTAssertEqual(error as? AppBridgeQueryDSL.QueryError, .invalidCollection("sqlite_master"))
        }
        XCTAssertThrowsError(try AppBridgeQueryDSL.dbQuery(from: [
            "collection": "tasks",
            "sql": "SELECT * FROM tasks"
        ])) { error in
            XCTAssertEqual(error as? AppBridgeQueryDSL.QueryError, .unsupportedQueryKey("sql"))
        }
        XCTAssertThrowsError(try AppBridgeQueryDSL.dbQuery(from: [
            "collection": "tasks",
            "schema": ["fields": [["name": "value", "type": "number"]]]
        ])) { error in
            XCTAssertEqual(error as? AppBridgeQueryDSL.QueryError, .unsupportedQueryKey("schema"))
        }
        XCTAssertThrowsError(try AppBridgeQueryDSL.dbQuery(from: [
            "collection": "tasks",
            "migration": "ALTER TABLE tasks ADD COLUMN raw_secret TEXT"
        ])) { error in
            XCTAssertEqual(error as? AppBridgeQueryDSL.QueryError, .unsupportedQueryKey("migration"))
        }
    }

    func testBridgeValuesRedactSensitiveFieldsAndBuildFacets() {
        let records = [
            DBRecord(
                id: "task-1",
                createdAt: "2026-05-19T00:00:00Z",
                updatedAt: "2026-05-19T00:00:00Z",
                data: [
                    "title": .string("Launch"),
                    "status": .string("todo"),
                    "apiKey": .string("secret-value")
                ]
            ),
            DBRecord(
                id: "task-2",
                createdAt: "2026-05-19T00:00:00Z",
                updatedAt: "2026-05-19T00:00:00Z",
                data: [
                    "title": .string("Ship"),
                    "status": .string("done"),
                    "password": .string("hidden")
                ]
            ),
            DBRecord(
                id: "task-3",
                createdAt: "2026-05-19T00:00:00Z",
                updatedAt: "2026-05-19T00:00:00Z",
                data: [
                    "title": .string("Review"),
                    "status": .string("todo")
                ]
            )
        ]

        let bridge = AppBridgeQueryDSL.bridgeValue(collection: "tasks", record: records[0])
        let data = bridge["data"] as? [String: Any]

        XCTAssertEqual(data?["title"] as? String, "Launch")
        XCTAssertNil(data?["apiKey"])
        XCTAssertEqual(bridge["redactedFields"] as? [String], ["apiKey"])
        XCTAssertEqual(bridge["redactionPolicy"] as? String, AppBridgeRedactionPolicy.policyId)

        let facets = AppBridgeQueryDSL.facetBridgeValue(records: records, fields: ["status", "apiKey"])
        let statusFacet = facets["status"] as? [[String: Any]]
        XCTAssertEqual(statusFacet?.first?["value"] as? String, "todo")
        XCTAssertEqual(statusFacet?.first?["count"] as? Int, 2)
        XCTAssertNil(facets["apiKey"])
    }

    func testBridgeRedactionPolicyMatchesSharedCustomAppContract() {
        XCTAssertEqual(AppBridgeRedactionPolicy.policyId, "claw.customApps.redaction.v1")
        XCTAssertTrue(AppBridgeRedactionPolicy.isSensitiveField("api_key"))
        XCTAssertTrue(AppBridgeRedactionPolicy.isSensitiveField("refresh-token"))
        XCTAssertTrue(AppBridgeRedactionPolicy.isSensitiveField("private key"))
        XCTAssertFalse(AppBridgeRedactionPolicy.isSensitiveField("displayName"))
    }

    func testNextCursorOnlyAppearsWhenMoreResultsMayExist() {
        let cursor = AppBridgeQueryDSL.nextCursor(offset: 20, returnedCount: 10, limit: 10, total: 100)
        XCTAssertEqual(AppBridgeDBQuery.offset(fromCursor: cursor), 30)
        XCTAssertNil(AppBridgeQueryDSL.nextCursor(offset: 90, returnedCount: 10, limit: 10, total: 100))
        XCTAssertNil(AppBridgeQueryDSL.nextCursor(offset: 20, returnedCount: 3, limit: 10, total: nil))
    }

    func testSearchQueryDSLNormalizesCollectionsAndLimits() throws {
        let query = try AppBridgeQueryDSL.searchQuery(from: [
            "query": "agent",
            "collections": ["tasks", "", "notes"],
            "limit": 0,
            "cursor": AppBridgeDBQuery.cursor(forOffset: 8),
            "facets": ["status"]
        ])

        XCTAssertEqual(query.query, "agent")
        XCTAssertEqual(query.collections, ["tasks", "notes"])
        XCTAssertEqual(query.limit, 1)
        XCTAssertEqual(query.effectiveOffset, 8)
        XCTAssertEqual(query.facets, ["status"])
    }

    func testSearchQueryDSLRejectsCollectionEscapes() throws {
        XCTAssertThrowsError(try AppBridgeQueryDSL.searchQuery(from: [
            "query": "agent",
            "collections": ["tasks", "sqlite_master"]
        ])) { error in
            XCTAssertEqual(error as? AppBridgeQueryDSL.QueryError, .invalidCollection("sqlite_master"))
        }
        XCTAssertThrowsError(try AppBridgeQueryDSL.searchQuery(from: [
            "query": "agent",
            "collections": ["../core.sqlite"]
        ])) { error in
            XCTAssertEqual(error as? AppBridgeQueryDSL.QueryError, .invalidCollection("../core.sqlite"))
        }
        XCTAssertThrowsError(try AppBridgeQueryDSL.searchQuery(from: [
            "query": "agent",
            "collections": ["tasks"],
            "sql": "SELECT * FROM tasks"
        ])) { error in
            XCTAssertEqual(error as? AppBridgeQueryDSL.QueryError, .unsupportedQueryKey("sql"))
        }
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
    func testVariantDefaultsExposeDefaultAppIdsForSettingsUI() throws {
        let defaults = try makeDefaults()
        let store = AppVariantDefaultsStore(userDefaults: defaults)
        let workspaceId = UUID()
        let variant = AppRecord(
            slug: "database-workbench-focus",
            name: "Database Workbench Focus",
            routeTarget: "database-workbench",
            variant: AppVariantMetadata(originalRoute: "database-workbench", defaultScope: "workspace"),
            protectedRoutePolicy: .variantOnly
        )

        XCTAssertNil(store.defaultAppId(routeTarget: "database-workbench", scope: .workspace, workspaceId: workspaceId))
        XCTAssertFalse(store.isDefault(app: variant, scope: .workspace, workspaceId: workspaceId))

        try store.setDefault(app: variant, scope: .workspace, workspaceId: workspaceId)

        XCTAssertEqual(
            store.defaultAppId(routeTarget: " database-workbench ", scope: .workspace, workspaceId: workspaceId),
            variant.id
        )
        XCTAssertTrue(store.isDefault(app: variant, scope: .workspace, workspaceId: workspaceId))

        store.clearDefault(routeTarget: "database-workbench", scope: .workspace, workspaceId: workspaceId)

        XCTAssertNil(store.defaultAppId(routeTarget: "database-workbench", scope: .workspace, workspaceId: workspaceId))
    }

    func testAppsSettingsVariantDefaultPresentationAllowsUserAndWorkspaceManagement() {
        let workspaceId = UUID()
        let variant = AppRecord(
            slug: "database-focus",
            name: "Database Focus",
            routeTarget: "database",
            variant: AppVariantMetadata(originalRoute: "database", defaultScope: "user"),
            protectedRoutePolicy: .variantOnly
        )

        let settable = AppsSettingsVariantDefaultPresentation(
            record: variant,
            workspaceId: workspaceId,
            userDefaultActive: false,
            workspaceDefaultActive: false
        )
        XCTAssertTrue(settable.isVariant)
        XCTAssertTrue(settable.canManageDefaults)
        XCTAssertTrue(settable.canSetWorkspaceDefault)
        XCTAssertEqual(settable.statusLabel, "Set")
        XCTAssertEqual(settable.symbolName, "square.grid.2x2")

        let workspaceDefault = AppsSettingsVariantDefaultPresentation(
            record: variant,
            workspaceId: workspaceId,
            userDefaultActive: true,
            workspaceDefaultActive: true
        )
        XCTAssertEqual(workspaceDefault.statusLabel, "Workspace")
        XCTAssertEqual(workspaceDefault.symbolName, "building.2")

        let noWorkspace = AppsSettingsVariantDefaultPresentation(
            record: variant,
            workspaceId: nil,
            userDefaultActive: false,
            workspaceDefaultActive: false
        )
        XCTAssertTrue(noWorkspace.canManageDefaults)
        XCTAssertFalse(noWorkspace.canSetWorkspaceDefault)
    }

    func testAppsSettingsVariantDefaultPresentationBlocksInvalidVariants() {
        let invalid = AppRecord(
            slug: "invalid-database-focus",
            name: "Invalid Database Focus",
            routeTarget: "database",
            variant: AppVariantMetadata(originalRoute: "memory", defaultScope: "user"),
            protectedRoutePolicy: .variantOnly
        )

        let presentation = AppsSettingsVariantDefaultPresentation(
            record: invalid,
            workspaceId: nil,
            userDefaultActive: true,
            workspaceDefaultActive: false
        )

        XCTAssertTrue(presentation.isVariant)
        XCTAssertFalse(presentation.canManageDefaults)
        XCTAssertFalse(presentation.canSetWorkspaceDefault)
        XCTAssertEqual(presentation.statusLabel, "Blocked")
        XCTAssertEqual(presentation.symbolName, "exclamationmark.triangle")
    }

    func testVariantOriginalRouteControlPresentsExplicitFallbackAffordance() {
        let variantActive = AppVariantOriginalRouteControlPresentation(
            appName: "Tasks Focus",
            scope: .workspace,
            isShowingOriginal: false
        )
        XCTAssertEqual(variantActive.symbolName, "arrow.uturn.backward")
        XCTAssertEqual(variantActive.primaryLabel, "Original")
        XCTAssertEqual(variantActive.scopeLabel, "workspace")
        XCTAssertEqual(variantActive.helpText, "Show original surface")

        let originalActive = AppVariantOriginalRouteControlPresentation(
            appName: "Tasks Focus",
            scope: .workspace,
            isShowingOriginal: true
        )
        XCTAssertEqual(originalActive.symbolName, "square.grid.2x2")
        XCTAssertEqual(originalActive.primaryLabel, "Tasks Focus")
        XCTAssertEqual(originalActive.scopeLabel, "workspace")
        XCTAssertEqual(originalActive.helpText, "Show custom variant")
    }

    func testVariantOriginalRouteControlFallsBackToGenericVariantName() {
        let presentation = AppVariantOriginalRouteControlPresentation(
            appName: "  ",
            scope: .user,
            isShowingOriginal: true
        )
        XCTAssertEqual(presentation.primaryLabel, "Custom view")
        XCTAssertEqual(presentation.scopeLabel, "user")
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

    private func makeResource(
        id: String,
        kind: String,
        locator: AppResourceLocator,
        label: String? = nil
    ) -> AppResourceRecord {
        AppResourceRecord(
            schemaVersion: 1,
            id: id,
            kind: kind,
            status: "active",
            locator: locator,
            scope: [:],
            label: label,
            fingerprint: nil,
            bookmark: nil,
            fileIdentity: nil,
            createdAt: "2026-05-19T00:00:00Z",
            updatedAt: "2026-05-19T00:00:00Z",
            lastSeenAt: nil,
            missingSince: nil
        )
    }

    private func writeResources(_ resources: [AppResourceRecord], to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let state = AppResourceRegistryState(
            schemaVersion: 1,
            resources: resources,
            updatedAt: "2026-05-19T00:00:00Z"
        )
        let data = try JSONEncoder().encode(state)
        try data.write(to: directory.appendingPathComponent(AppResourceRegistryStore.stateFileName))
    }

    private func makeCollection(_ name: String) -> DBCollection {
        DBCollection(
            namespaceId: "clawix-local",
            name: name,
            displayName: name.capitalized,
            fields: [
                DBFieldDefinition(name: "title", type: .text, required: true, options: nil, relation: nil),
                DBFieldDefinition(name: "status", type: .select, required: false, options: nil, relation: nil)
            ],
            indexes: [],
            builtin: true,
            protected: false,
            coreFieldNames: ["title", "status"],
            createdAt: "2026-05-20T00:00:00Z",
            updatedAt: "2026-05-20T00:00:00Z"
        )
    }

    private func makeDBRecord(id: String, title: String, status: String) -> DBRecord {
        DBRecord(
            id: id,
            createdAt: "2026-05-20T00:00:00Z",
            updatedAt: "2026-05-20T00:00:00Z",
            data: [
                "title": .string(title),
                "status": .string(status)
            ]
        )
    }

    private func makeSwiftRunnerLaunch(
        result: AppSwiftSurfaceRunnerResult
    ) throws -> (launch: AppSwiftSurfaceRunnerLaunch, result: AppSwiftSurfaceRunnerResult) {
        let app = AppRecord(
            slug: "swift-dashboard",
            name: "Swift Dashboard",
            declaredCapabilities: ["search.query"],
            surfaceKind: .swiftDeclarative
        )
        let manifest = AppSwiftSurfaceManifest(
            root: AppSwiftSurfaceNode(
                kind: .button,
                text: "Search",
                action: AppSwiftSurfaceAction(
                    invocation: .sdkRead,
                    capabilityId: "search.query",
                    operation: "search.query"
                )
            ),
            requestedCapabilities: ["search.query"]
        )
        let plan = try AppSwiftSurfaceContract.runnerPlan(
            app: app,
            manifest: manifest,
            manifestPath: "/tmp/swift-dashboard/surface.json"
        )
        return (
            AppSwiftSurfaceRunnerLaunch(
                plan: plan,
                executablePath: "/tmp/clawix-swift-surface-runner",
                timeoutSeconds: 3
            ),
            result
        )
    }

    private func makeCancellableSwiftRunnerFixture() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawix-swift-runner-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("runner.sh")
        try """
        #!/bin/sh
        sleep 5
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return executable
    }
}

private final class AppCustomSurfaceFakeIoTClient: IoTClienting, @unchecked Sendable {
    let origin = URL(string: "http://127.0.0.1:1")!
    var bearerToken: String?
    var onRunAction: (IoTActionRequest, String?) async throws -> IoTActionResult = { _, _ in
        makeActionResult()
    }

    func health() async -> Bool { true }

    func listTools() async throws -> RemoteToolCatalog {
        RemoteToolCatalog(generatedAt: "2026-05-20T00:00:00Z", tools: [])
    }

    func invokeTool(id: String, arguments: [String: Any]) async throws -> RemoteToolInvocationResult {
        RemoteToolInvocationResult(ok: true, value: ToolJSONValue([String: Any]()), error: nil, invocationId: id, durationMs: 1)
    }

    func listHomes() async throws -> [HomeRecord] { [] }
    func listDevices(homeId: String?) async throws -> [IoTDeviceRecord] { [] }
    func listAreas(homeId: String?) async throws -> [AreaRecord] { [] }
    func listScenes(homeId: String?) async throws -> [SceneRecord] { [] }
    func listAutomations(homeId: String?) async throws -> [AutomationRecord] { [] }
    func listApprovals(homeId: String?) async throws -> [ApprovalRecord] { [] }

    func runAction(_ request: IoTActionRequest, homeId: String?) async throws -> IoTActionResult {
        try await onRunAction(request, homeId)
    }

    func activateScene(sceneId: String, homeId: String?) async throws -> IoTActionResult {
        Self.makeActionResult()
    }

    func setAutomationEnabled(automationId: String, enabled: Bool, homeId: String?) async throws -> AutomationRecord {
        AutomationRecord(id: automationId, homeId: homeId ?? "home", label: automationId, enabled: enabled, trigger: ToolJSONValue([String: Any]()), conditions: [], actions: [])
    }

    func runAutomation(automationId: String, homeId: String?) async throws -> IoTActionResult {
        Self.makeActionResult()
    }

    func approveApproval(approvalId: String, homeId: String?) async throws -> IoTActionResult {
        Self.makeActionResult()
    }

    func denyApproval(approvalId: String, homeId: String?) async throws -> ApprovalRecord {
        ApprovalRecord(
            id: approvalId,
            homeId: homeId ?? "home",
            status: "denied",
            reason: "Denied",
            action: IoTActionRequest(homeId: nil, selector: nil, area: nil, family: nil, capability: nil, action: "noop", value: nil, targets: nil),
            createdAt: "2026-05-20T00:00:00Z",
            updatedAt: "2026-05-20T00:00:00Z"
        )
    }

    func addDevice(input: IoTClient.AddDeviceInput) async throws -> IoTDeviceRecord {
        IoTDeviceRecord(
            id: input.label ?? "device",
            homeId: input.homeId ?? "home",
            areaId: nil,
            label: input.label ?? "Device",
            aliases: [],
            kind: .switchKind,
            risk: .caution,
            connectorId: "connector",
            targetRef: input.targetRef ?? "target",
            metadata: nil,
            capabilities: []
        )
    }

    func removeDevice(deviceId: String, homeId: String?) async throws {}
    func startDiscovery(timeoutMs: Int?) async throws {}
    func stopDiscovery() async throws {}

    static func makeActionResult(status: String = "ok") -> IoTActionResult {
        IoTActionResult(
            status: status,
            homeId: "home",
            decision: "executed",
            reasons: [],
            updatedAt: "2026-05-20T00:00:00Z",
            targets: [],
            capabilityUpdates: [],
            approvalId: nil
        )
    }
}

private final class AppCustomSurfaceFakeDatabaseClient: DatabaseClienting {
    var bearerToken: String? = "test-token"
    let origin = URL(string: "http://127.0.0.1:1")!
    var listRecordsCallCount = 0
    var onListRecords: (
        String,
        String,
        [String: Any]?,
        String?,
        Int?,
        Int?
    ) async throws -> DBListResponse<DBRecord> = { _, _, _, _, _, _ in
        DBListResponse(total: 0, items: [])
    }

    func ensureNamespace(id: String, displayName: String?) async throws -> DBNamespace {
        DBNamespace(
            id: id,
            displayName: displayName ?? id,
            createdAt: "2026-05-20T00:00:00Z",
            updatedAt: "2026-05-20T00:00:00Z"
        )
    }

    func listCollections(namespaceId: String) async throws -> [DBCollection] { [] }

    func updateCollection(
        namespaceId: String,
        name: String,
        displayName: String,
        fields: [DBFieldDefinition],
        indexes: [DBIndexDefinition]
    ) async throws -> DBCollection {
        DBCollection(
            namespaceId: namespaceId,
            name: name,
            displayName: displayName,
            fields: fields,
            indexes: indexes,
            builtin: false,
            protected: false,
            coreFieldNames: [],
            createdAt: "2026-05-20T00:00:00Z",
            updatedAt: "2026-05-20T00:00:00Z"
        )
    }

    func listRecords(
        namespaceId: String,
        collection: String,
        filter: [String: Any]?,
        sort: String?,
        limit: Int?,
        offset: Int?
    ) async throws -> DBListResponse<DBRecord> {
        listRecordsCallCount += 1
        return try await onListRecords(namespaceId, collection, filter, sort, limit, offset)
    }

    func createRecord(namespaceId: String, collection: String, data: [String: DBJSON]) async throws -> DBRecord {
        DBRecord(id: "created", createdAt: "2026-05-20T00:00:00Z", updatedAt: "2026-05-20T00:00:00Z", data: data)
    }

    func updateRecord(namespaceId: String, collection: String, id: String, data: [String: DBJSON]) async throws -> DBRecord {
        DBRecord(id: id, createdAt: "2026-05-20T00:00:00Z", updatedAt: "2026-05-20T00:00:00Z", data: data)
    }

    func deleteRecord(namespaceId: String, collection: String, id: String) async throws -> Bool { true }

    func downloadFile(fileId: String) async throws -> Data { Data() }

    func uploadFile(
        namespaceId: String,
        collectionName: String?,
        recordId: String?,
        filename: String,
        contentType: String,
        data: Data
    ) async throws -> DBFileAsset {
        DBFileAsset(
            id: "file-1",
            namespaceId: namespaceId,
            collectionName: collectionName,
            recordId: recordId,
            filename: filename,
            contentType: contentType,
            sizeBytes: Int64(data.count),
            createdAt: "2026-05-20T00:00:00Z",
            downloadPath: "/files/file-1"
        )
    }
}

private struct RecordingSwiftRunnerExecutor: AppSwiftSurfaceRunnerExecuting {
    let result: AppSwiftSurfaceRunnerResult

    func run(_ launch: AppSwiftSurfaceRunnerLaunch) -> AppSwiftSurfaceRunnerResult {
        result
    }
}

@MainActor
private final class RecordingSwiftSurfaceActionDispatcher: AppHighRiskActionDispatcher {
    let result: AppHighRiskActionDispatchResult
    private(set) var requests: [AppHighRiskActionDispatchRequest] = []

    init(result: AppHighRiskActionDispatchResult) {
        self.result = result
    }

    func dispatch(_ request: AppHighRiskActionDispatchRequest) async -> AppHighRiskActionDispatchResult {
        requests.append(request)
        return result
    }
}
