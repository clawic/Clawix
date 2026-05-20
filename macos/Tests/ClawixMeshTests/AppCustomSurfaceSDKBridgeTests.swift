import XCTest
@testable import Clawix

final class AppCustomSurfaceSDKBridgeTests: AppCustomSurfaceCapabilityTestCase {
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
        XCTAssertTrue(ClawixAppsSDKJS.contains("jobs.stream"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("jobs.start"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("jobs.cancel"))
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
        XCTAssertTrue((payload["schemaRefs"] as? [String])?.contains("claw.jobs.stream.v1") == true)
        XCTAssertTrue((payload["schemaRefs"] as? [String])?.contains("claw.jobs.streamResult.v1") == true)
        XCTAssertTrue((payload["schemaRefs"] as? [String])?.contains("claw.jobs.start.v1") == true)
        XCTAssertTrue((payload["schemaRefs"] as? [String])?.contains("claw.jobs.startResult.v1") == true)
        XCTAssertTrue((payload["schemaRefs"] as? [String])?.contains("claw.jobs.cancel.v1") == true)
        XCTAssertTrue((payload["schemaRefs"] as? [String])?.contains("claw.jobs.cancelResult.v1") == true)
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
        let jobStream = try XCTUnwrap(capabilities.first { $0["id"] as? String == "jobs.stream" })
        XCTAssertEqual(jobStream["customAppAccess"] as? String, "localWide")
        let jobStreamDispatch = try XCTUnwrap(jobStream["dispatch"] as? [String: Any])
        XCTAssertEqual(jobStreamDispatch["status"] as? String, "available")
        XCTAssertEqual(jobStreamDispatch["mode"] as? String, "localWideRead")
        XCTAssertEqual(jobStreamDispatch["approvalRequired"] as? Bool, false)
        let jobStart = try XCTUnwrap(capabilities.first { $0["id"] as? String == "jobs.start" })
        XCTAssertEqual(jobStart["customAppAccess"] as? String, "approvalRequired")
        let jobStartDispatch = try XCTUnwrap(jobStart["dispatch"] as? [String: Any])
        XCTAssertEqual(jobStartDispatch["status"] as? String, "available")
        XCTAssertEqual(jobStartDispatch["mode"] as? String, "approvalRequiredDispatch")
        XCTAssertEqual(jobStartDispatch["approvalRequired"] as? Bool, true)
        let jobCancel = try XCTUnwrap(capabilities.first { $0["id"] as? String == "jobs.cancel" })
        XCTAssertEqual(jobCancel["customAppAccess"] as? String, "approvalRequired")
        let jobCancelDispatch = try XCTUnwrap(jobCancel["dispatch"] as? [String: Any])
        XCTAssertEqual(jobCancelDispatch["status"] as? String, "available")
        XCTAssertEqual(jobCancelDispatch["mode"] as? String, "approvalRequiredDispatch")
        XCTAssertEqual(jobCancelDispatch["approvalRequired"] as? Bool, true)
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

    func testHostBridgeSurfaceBindingsAreCompleteAndResolvedWhenPublished() throws {
        let record = AppRecord(
            slug: "dashboard",
            name: "Dashboard",
            declaredCapabilities: ["jobs.stream", "jobs.start", "jobs.cancel"]
        )
        let payload = AppCapabilityCatalog.contractsBridgeValue(for: record)
        let capabilities = try XCTUnwrap(payload["capabilities"] as? [[String: Any]])
        var checkedSurfaceGroups = 0

        for capability in capabilities {
            let surfaces = try XCTUnwrap(capability["surfaces"] as? [[String: String]])

            checkedSurfaceGroups += 1
            XCTAssertEqual(surfaces.map { $0["surface"] }, AppCapabilityCatalog.canonicalSurfaceNames, capability["id"] as? String ?? "unknown")
            for surface in surfaces {
                XCTAssertNotEqual(surface["status"], "pending", "\(capability["id"] as? String ?? "unknown"):\(surface["surface"] ?? "unknown")")
                if surface["status"] == "available" {
                    XCTAssertNotNil(surface["ref"], "\(capability["id"] as? String ?? "unknown"):\(surface["surface"] ?? "unknown")")
                }
            }
        }

        XCTAssertEqual(checkedSurfaceGroups, capabilities.count)
        let jobsList = try XCTUnwrap(capabilities.first { $0["id"] as? String == "jobs.list" })
        let jobsListSurfaces = try XCTUnwrap(jobsList["surfaces"] as? [[String: String]])
        XCTAssertEqual(jobsListSurfaces.first { $0["surface"] == "cli" }?["status"], "blocked")
        XCTAssertNil(jobsListSurfaces.first { $0["surface"] == "cli" }?["ref"])
        XCTAssertEqual(jobsListSurfaces.first { $0["surface"] == "sdk" }?["ref"], "window.clawix.jobs.list")
        let secrets = try XCTUnwrap(capabilities.first { $0["id"] as? String == "secrets.broker" })
        let secretsSurfaces = try XCTUnwrap(secrets["surfaces"] as? [[String: String]])
        XCTAssertEqual(secretsSurfaces.first { $0["surface"] == "mcp" }?["status"], "blocked")
        XCTAssertNil(secretsSurfaces.first { $0["surface"] == "mcp" }?["ref"])
        XCTAssertEqual(secretsSurfaces.first { $0["surface"] == "hostBridge" }?["ref"], "window.clawix")
    }

    func testInjectedAppsSdkExposesSearchAndDBContracts() {
        XCTAssertTrue(ClawixAppsSDKJS.contains("search.query"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("db.query"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("resources.read"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("resources.list"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("jobs.list"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("jobs.get"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("jobs.events"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("jobs.stream"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("jobs.start"))
        XCTAssertTrue(ClawixAppsSDKJS.contains("jobs.cancel"))
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
        XCTAssertTrue(AppBridgeOperationPolicy.isAllowed("jobs.stream"))
        XCTAssertTrue(AppBridgeOperationPolicy.isAllowed("jobs.start"))
        XCTAssertTrue(AppBridgeOperationPolicy.isAllowed("jobs.cancel"))
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
}
