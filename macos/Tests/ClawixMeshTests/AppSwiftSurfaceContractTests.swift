import XCTest
@testable import Clawix

final class AppSwiftSurfaceContractTests: AppCustomSurfaceCapabilityTestCase {
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
}
