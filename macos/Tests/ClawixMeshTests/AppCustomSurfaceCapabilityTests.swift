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

    func testOrdinaryReadCapabilitiesExposeSharedRedactionPolicy() {
        let ordinary = AppCapabilityCatalog.descriptors.filter { $0.customAppAccess == .localWide }
        XCTAssertEqual(ordinary.map(\.id).sorted(), ["db.query", "resources.read", "search.query"])
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
        XCTAssertEqual(AppCapabilityCatalog.descriptor(id: "resources.read")?.inputSchemaRef, "claw.resources.read.v1")
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
              "operation": "search.query"
            },
            "children": []
          }
        }
        """.data(using: .utf8)!

        let manifest = try AppSwiftSurfaceContract.decodeManifest(data: json)

        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.requestedCapabilities, ["search.query"])
        XCTAssertNil(AppSwiftSurfaceContract.runnerExecutablePath(environment: [:]))
        XCTAssertNil(
            AppSwiftSurfaceContract.runnerExecutablePath(environment: ["CLAWIX_SWIFT_SURFACE_RUNNER": "   "])
        )
        XCTAssertEqual(
            AppSwiftSurfaceContract.runnerExecutablePath(environment: ["CLAWIX_SWIFT_SURFACE_RUNNER": "/tmp/runner"]),
            "/tmp/runner"
        )
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
                signatureStatus: .notVerified,
                packageDigestSHA256: "abc123",
                reviewReason: "Imported packages require local review before activation."
            )
        )
        let riskMap = AppCapabilityCatalog.riskMap(for: record)

        let presentation = AppActivationReviewPresentation(record: record, riskMap: riskMap)

        XCTAssertTrue(presentation.lines.contains(AppActivationReviewLine(title: "Imported from", value: "/tmp/focus-panel")))
        XCTAssertTrue(presentation.lines.contains(AppActivationReviewLine(title: "Source slug", value: "focus-panel")))
        XCTAssertTrue(presentation.lines.contains(AppActivationReviewLine(title: "Source origin", value: "localUserAuthored")))
        XCTAssertTrue(presentation.lines.contains(AppActivationReviewLine(title: "Signature", value: "Not verified")))
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
                signatureStatus: .notVerified,
                packageDigestSHA256: "abc123"
            )
        )

        let presentation = AppsSettingsTrustPresentation(record: record)

        XCTAssertEqual(presentation.statusLabel, "Imported")
        XCTAssertEqual(presentation.symbolName, "tray.and.arrow.down")
        XCTAssertEqual(presentation.tone, .warning)
        XCTAssertTrue(presentation.helpText.contains("Origin: imported"))
        XCTAssertTrue(presentation.helpText.contains("Signature: Not verified"))
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
                signatureStatus: .notVerified,
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
        XCTAssertTrue(model.rows.last?.detail.contains("Signature: Not verified") == true)
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
        XCTAssertTrue(ClawixAppsSDKJS.contains("capabilities.contracts"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("capabilities.riskMap"))
    }

    func testHostBridgeExposesCustomAppSDKContractPayload() throws {
        let record = AppRecord(
            slug: "dashboard",
            name: "Dashboard",
            createdByChatId: nil,
            declaredCapabilities: ["search.query", "db.query", "resources.read", "actions.invoke"]
        )
        let payload = AppCapabilityCatalog.contractsBridgeValue(for: record)
        XCTAssertEqual(payload["schemaVersion"] as? Int, 1)
        XCTAssertEqual(payload["hostBridgeRole"] as? String, "sdk_host_bridge_contract_resource")
        XCTAssertEqual(payload["richUiRuntime"] as? String, "sdk_host_bridge_not_cli_process")
        XCTAssertEqual(payload["missingSchemaRefs"] as? [String], [])
        XCTAssertTrue((payload["schemaRefs"] as? [String])?.contains("claw.search.query.v1") == true)
        XCTAssertTrue((payload["referencedSchemaRefs"] as? [String])?.contains("claw.customApp.request.partial.v1") == true)
        let riskMap = try XCTUnwrap(payload["riskMap"] as? [String: Any])
        XCTAssertEqual(riskMap["authorityModel"] as? String, "localWideReadsHighRiskApproval")
        XCTAssertTrue((riskMap["ordinaryAccess"] as? [String])?.contains("db.query") == true)
        XCTAssertTrue((riskMap["approvalRequired"] as? [String])?.contains("actions.invoke") == true)
        let capabilities = try XCTUnwrap(payload["capabilities"] as? [[String: Any]])
        let resources = try XCTUnwrap(capabilities.first { $0["id"] as? String == "resources.read" })
        XCTAssertEqual(resources["redactionPolicyRef"] as? String, AppBridgeRedactionPolicy.policyId)
    }

    func testInjectedAppsSdkExposesSearchAndDBContracts() {
        XCTAssertTrue(ClawixAppsSDKJS.contains("search.query"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("db.query"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("resources.read"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("resources.list"))
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
        XCTAssertTrue(AppBridgeOperationPolicy.isAllowed("resources.read"))
        XCTAssertTrue(AppBridgeOperationPolicy.isAllowed("capabilities.contracts"))

        for operation in AppBridgeOperationPolicy.forbiddenEscapeHatchOperations {
            XCTAssertFalse(AppBridgeOperationPolicy.isAllowed(operation), operation)
            XCTAssertFalse(ClawixAppsSDKJS.contains(operation), operation)
        }

        XCTAssertFalse(AppBridgeOperationPolicy.allowedOperations.contains { $0.contains("sqlite") })
        XCTAssertFalse(AppBridgeOperationPolicy.allowedOperations.contains { $0.hasPrefix("secrets.") })
        XCTAssertFalse(AppBridgeOperationPolicy.allowedOperations.contains { $0.hasPrefix("cli.") })
        XCTAssertFalse(AppBridgeOperationPolicy.allowedOperations.contains { $0.hasPrefix("fs.") })
        XCTAssertFalse(AppBridgeOperationPolicy.allowedOperations.contains { $0.hasPrefix("process.") })
        XCTAssertFalse(AppBridgeOperationPolicy.allowedOperations.contains { $0.hasPrefix("native.") })
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

private struct RecordingSwiftRunnerExecutor: AppSwiftSurfaceRunnerExecuting {
    let result: AppSwiftSurfaceRunnerResult

    func run(_ launch: AppSwiftSurfaceRunnerLaunch) -> AppSwiftSurfaceRunnerResult {
        result
    }
}
