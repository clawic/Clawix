import XCTest
@testable import Clawix

final class AppHighRiskActionDispatcherTests: AppCustomSurfaceCapabilityTestCase {
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
}
