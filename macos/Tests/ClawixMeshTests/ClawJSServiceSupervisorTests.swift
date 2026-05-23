import XCTest
import ClawixCore
@testable import Clawix

final class ClawJSServiceSupervisorTests: XCTestCase {
    func testManagerFacadeDoesNotOwnProcessSupervision() throws {
        let managerSource = try readSource("ClawJS/ClawJSServiceManager.swift")

        XCTAssertFalse(managerSource.contains("waitUntilExit"))
        XCTAssertFalse(managerSource.contains("Process()"))
        XCTAssertFalse(managerSource.contains("[ClawJSService: Process]"))
        XCTAssertFalse(managerSource.contains("healthTasks"))
        XCTAssertFalse(managerSource.contains("restartTasks"))
        XCTAssertTrue(managerSource.contains("ClawJSServiceSupervisor"))
    }

    func testServiceHealthUsesAggregateMonitorTask() throws {
        let supervisorSource = try readSource("ClawJS/ClawJSServiceSupervisor.swift")
        let healthSource = try readSource("ClawJS/ClawJSServiceHealthMonitor.swift")

        XCTAssertTrue(supervisorSource.contains("private var monitorTask: Task<Void, Never>?"))
        XCTAssertTrue(supervisorSource.contains("private var serviceMonitors: [ClawJSService: ClawJSServiceMonitor]"))
        XCTAssertTrue(healthSource.contains("struct ClawJSServiceMonitor"))
        XCTAssertTrue(supervisorSource.contains("runAggregateMonitor()"))
        XCTAssertTrue(supervisorSource.contains("monitorDueServices()"))
        XCTAssertFalse(supervisorSource.contains("healthTasks"))
        XCTAssertFalse(supervisorSource.contains("pollHealth(for:"))
        XCTAssertFalse(supervisorSource.contains("pollDaemonOwnedService("))
    }

    func testDaemonPushStatusSuppressesFallbackProbeWindow() throws {
        let supervisorSource = try readSource("ClawJS/ClawJSServiceSupervisor.swift")
        let healthSource = try readSource("ClawJS/ClawJSServiceHealthMonitor.swift")

        XCTAssertTrue(supervisorSource.contains("applyDaemonServiceStatuses("))
        XCTAssertTrue(supervisorSource.contains("activeDemand: Set<ClawJSService>"))
        XCTAssertTrue(healthSource.contains("daemonPushFreshWindow"))
        XCTAssertTrue(supervisorSource.contains("monitor.daemon_push_fresh"))
        XCTAssertTrue(healthSource.contains("daemonFallbackProbeInterval"))
    }

    func testDaemonPushWithoutDemandDoesNotCreateFallbackMonitor() throws {
        let supervisorSource = try readSource("ClawJS/ClawJSServiceSupervisor.swift")

        XCTAssertTrue(supervisorSource.contains("guard hasActiveDemand else"))
        XCTAssertTrue(supervisorSource.contains("serviceMonitors[service] = nil"))
        XCTAssertTrue(supervisorSource.contains("return"))
    }

    func testStopCancelsServiceMonitorAndProcessOwnership() throws {
        let supervisorSource = try readSource("ClawJS/ClawJSServiceSupervisor.swift")

        XCTAssertTrue(supervisorSource.contains("func stop(_ services: Set<ClawJSService>) async"))
        XCTAssertTrue(supervisorSource.contains("restartTasks[service]?.cancel()"))
        XCTAssertTrue(supervisorSource.contains("serviceMonitors[service] = nil"))
        XCTAssertTrue(supervisorSource.contains("_ = await stopTrackedProcess(for: service)"))
        XCTAssertTrue(supervisorSource.contains("$0.state = ClawJSServiceSupervisorPolicy.availableOnDemandState(for: service)"))
    }

    func testProcessInspectionDoesNotUseSynchronousWaits() throws {
        let supportSource = try readSource("ClawJS/ClawJSProcessSupport.swift")
        let supervisorSource = try readSource("ClawJS/ClawJSServiceSupervisor.swift")

        XCTAssertFalse(supportSource.contains("waitUntilExit"))
        XCTAssertFalse(supervisorSource.contains("waitUntilExit"))
        XCTAssertTrue(supervisorSource.contains("actor ClawJSServiceSupervisor"))
    }

    func testProcessInspectionSystemToolsAreCentralized() throws {
        let supportSource = try readSource("ClawJS/ClawJSProcessSupport.swift")

        XCTAssertEqual(ClawJSMacProcessToolRoutes.shell, "/bin/sh")
        XCTAssertEqual(ClawJSMacProcessToolRoutes.lsof, "/usr/sbin/lsof")
        XCTAssertEqual(ClawJSMacProcessToolRoutes.ps, "/bin/ps")
        XCTAssertEqual(ClawixSystemToolRoutes.shellCLI, "/bin/sh")
        XCTAssertEqual(ClawixSystemToolRoutes.lsofCLI, "/usr/sbin/lsof")
        XCTAssertEqual(ClawixSystemToolRoutes.psCLI, "/bin/ps")
        XCTAssertEqual(ClawixTemporaryRoutes.nullDevicePath, "/dev/null")
        XCTAssertEqual(ClawJSMacProcessToolRoutes.nullDevice, "/dev/null")
        XCTAssertEqual(ClawJSMacProcessToolRoutes.bundledClawJSSidecarFragment, "/Clawix.app/Contents/Resources/clawjs/")
        XCTAssertEqual(ClawJSMacProcessToolRoutes.appSupportClawJSSidecarFragment, "/Application Support/Clawix/clawjs/")
        XCTAssertEqual(
            ClawJSMacProcessToolRoutes.listenerPIDCommand(port: 4567),
            "/usr/sbin/lsof -nP -tiTCP:4567 -sTCP:LISTEN 2>/dev/null | head -n 1"
        )
        XCTAssertTrue(supportSource.contains("ClawJSMacProcessToolRoutes.listenerPIDCommand(port: port)"))
        XCTAssertTrue(supportSource.contains("static let shell = ClawixSystemToolRoutes.shellCLI"))
        XCTAssertTrue(supportSource.contains("static let lsof = ClawixSystemToolRoutes.lsofCLI"))
        XCTAssertTrue(supportSource.contains("static let ps = ClawixSystemToolRoutes.psCLI"))
        XCTAssertTrue(supportSource.contains("static let nullDevice = ClawixTemporaryRoutes.nullDevicePath"))
        XCTAssertTrue(supportSource.contains("ClawJSMacProcessToolRoutes.bundledClawJSSidecarFragment"))
        XCTAssertTrue(supportSource.contains("ClawJSMacProcessToolRoutes.appSupportClawJSSidecarFragment"))
        XCTAssertFalse(supportSource.contains("2>/dev/null | head -n 1\"]"))
        XCTAssertFalse(supportSource.contains("static let shell = \"/bin/sh\""))
        XCTAssertFalse(supportSource.contains("static let lsof = \"/usr/sbin/lsof\""))
        XCTAssertFalse(supportSource.contains("static let ps = \"/bin/ps\""))
        XCTAssertFalse(supportSource.contains("static let nullDevice = \"/dev/null\""))
        XCTAssertFalse(supportSource.contains("command.contains(\"/Application Support/Clawix/clawjs/\")"))
    }

    func testIotLaunchSystemToolPathIsCentralized() throws {
        let launchAdapterSource = try readSource("ClawJS/ClawJSServiceLaunchAdapter.swift")

        XCTAssertEqual(ClawJSServiceSupervisorRoutes.envCLI, "/usr/bin/env")
        XCTAssertEqual(ClawixSystemToolRoutes.envCLI, "/usr/bin/env")
        XCTAssertTrue(launchAdapterSource.contains("ClawJSServiceSupervisorRoutes.envURL"))
        XCTAssertFalse(launchAdapterSource.contains("URL(fileURLWithPath: \"/usr/bin/env\")"))
    }

    func testClawJSServiceEndpointResolverCentralizesLoopbackOrigins() throws {
        let resolverSource = try readSource("ClawJS/ClawJSServiceEndpointResolver.swift")
        let runtimeSource = try readSource("ClawJS/ClawJSRuntimeClient.swift")
        let supervisorSource = try readSource("ClawJS/ClawJSServiceSupervisor.swift")
        let environmentSource = try readSource("ClawJS/ClawJSServiceEnvironmentBuilder.swift")

        XCTAssertEqual(ClawJSServiceEndpointResolver.loopbackHost, "127.0.0.1")
        XCTAssertEqual(
            ClawJSServiceEndpointResolver.origin(for: .runtime).absoluteString,
            "http://127.0.0.1:24100"
        )
        XCTAssertEqual(
            ClawJSServiceEndpointResolver.webSocketOrigin(for: .drive).absoluteString,
            "ws://127.0.0.1:24104"
        )
        XCTAssertEqual(
            ClawJSServiceEndpointResolver.healthURL(for: .publishing).absoluteString,
            "http://127.0.0.1:24111/healthz"
        )
        XCTAssertEqual(
            ClawJSServiceEndpointResolver.url(
                for: .iot,
                path: "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/events/stream"
            ).absoluteString,
            "http://127.0.0.1:24152/v1/events/stream"
        )
        XCTAssertTrue(resolverSource.contains("static let loopbackHost = \"127.0.0.1\""))
        XCTAssertTrue(runtimeSource.contains("ClawJSServiceEndpointResolver.origin(for: .runtime)"))
        XCTAssertTrue(supervisorSource.contains("ClawJSServiceEndpointResolver.healthURL(for: service)"))
        XCTAssertTrue(environmentSource.contains("ClawJSServiceEndpointResolver.originString(for: .sessions)"))
    }

    func testServiceSupervisorStorageRoutesAreCentralized() throws {
        let supervisorSource = try readSource("ClawJS/ClawJSServiceSupervisor.swift")
        let routesSource = try readSource("ClawJS/ClawJSServiceSupervisorRoutes.swift")
        let resolverSource = try readSource("ClawJS/ClawJSServiceDirectoryResolver.swift")
        let applicationSupportRoot = URL(fileURLWithPath: "/tmp/clawix-fixture-home/Library/Application Support/Clawix/clawjs", isDirectory: true)
        let workspaceURL = ClawJSServiceSupervisorRoutes.workspaceURL(applicationSupportRoot: applicationSupportRoot)
        let frameworkRoot = URL(fileURLWithPath: "/tmp/clawix-fixture-home/.claw", isDirectory: true)

        XCTAssertEqual(ClawJSServiceSupervisorRoutes.workspaceDirectoryName, "workspace")
        XCTAssertEqual(ClawJSServiceSupervisorRoutes.homeDirectoryName, "home")
        XCTAssertEqual(ClawJSServiceSupervisorRoutes.secretsDirectoryName, "secrets")
        XCTAssertEqual(ClawJSServiceSupervisorRoutes.runtimeDatabaseFileName, "runtime.sqlite")
        XCTAssertEqual(ClawJSServiceSupervisorRoutes.adminTokenFileName, ".admin-token")
        XCTAssertEqual(ClawJSServiceSupervisorRoutes.devPointersDirectoryName, "dev-pointers")
        XCTAssertEqual(ClawJSServiceSupervisorRoutes.iotPointerFileName, "iot.dir")
        XCTAssertEqual(
            ClawJSServiceSupervisorRoutes.applicationSupportRoot(
                environment: [ClawixEnv.dummyMode: "1", ClawixEnv.backendHome: "/tmp/clawjs-home"]
            ).path,
            "/tmp/clawjs-home"
        )
        XCTAssertEqual(workspaceURL.path, "/tmp/clawix-fixture-home/Library/Application Support/Clawix/clawjs/workspace")
        XCTAssertEqual(
            ClawJSServiceSupervisorRoutes.mainDatabaseURL(mainDataDirectoryURL: applicationSupportRoot).lastPathComponent,
            "clawix.sqlite"
        )
        XCTAssertEqual(
            ClawJSServiceSupervisorRoutes.mainFilesDirectoryURL(mainDataDirectoryURL: applicationSupportRoot).lastPathComponent,
            "files"
        )
        XCTAssertEqual(
            ClawJSServiceSupervisorRoutes.frameworkGlobalRoot(
                environment: [:],
                homeDirectory: URL(fileURLWithPath: "/tmp/clawix-fixture-home", isDirectory: true)
            ).path,
            "/tmp/clawix-fixture-home/.claw"
        )
        XCTAssertEqual(
            ClawJSServiceSupervisorRoutes.frameworkGlobalRoot(
                environment: [ClawEnv.home: "/tmp/framework-home"],
                homeDirectory: URL(fileURLWithPath: "/tmp/clawix-fixture-home", isDirectory: true)
            ).path,
            "/tmp/framework-home"
        )
        XCTAssertEqual(
            ClawJSServiceSupervisorRoutes.frameworkSecretsDirectory(frameworkGlobalRoot: frameworkRoot).path,
            "/tmp/clawix-fixture-home/.claw/secrets"
        )
        XCTAssertEqual(
            ClawJSServiceSupervisorRoutes.statusFileURL(service: .database, applicationSupportRoot: applicationSupportRoot).path,
            "/tmp/clawix-fixture-home/Library/Application Support/Clawix/clawjs/status/database.json"
        )
        XCTAssertEqual(
            ClawJSServiceSupervisorRoutes.homeURL(applicationSupportRoot: applicationSupportRoot).path,
            "/tmp/clawix-fixture-home/Library/Application Support/Clawix/clawjs/home"
        )
        XCTAssertEqual(
            ClawJSServiceSupervisorRoutes.secretsProxyURL(
                homeDirectory: URL(fileURLWithPath: "/tmp/clawix-fixture-home", isDirectory: true)
            ).path,
            "/tmp/clawix-fixture-home/bin/secrets-proxy"
        )
        XCTAssertEqual(
            ClawJSServiceSupervisorRoutes.runtimeDatabaseURL(runtimeDataDirectoryURL: workspaceURL).lastPathComponent,
            "runtime.sqlite"
        )
        XCTAssertEqual(
            ClawJSServiceSupervisorRoutes.sessionsDatabaseURL(dataDirectoryURL: workspaceURL).lastPathComponent,
            "sessions.sqlite"
        )
        XCTAssertEqual(
            ClawJSServiceSupervisorRoutes.secretsDatabaseURL(dataDirectoryURL: workspaceURL).lastPathComponent,
            "secrets.sqlite"
        )
        XCTAssertEqual(
            ClawJSServiceSupervisorRoutes.serviceDataDirectoryURL(
                service: .drive,
                workspaceURL: workspaceURL,
                mainDataDirectoryURL: applicationSupportRoot,
                frameworkSecretsDirectoryURL: ClawJSServiceSupervisorRoutes.frameworkSecretsDirectory(frameworkGlobalRoot: frameworkRoot)
            ).path,
            "/tmp/clawix-fixture-home/Library/Application Support/Clawix/clawjs/workspace/.claw/drive"
        )
        XCTAssertEqual(
            ClawJSServiceSupervisorRoutes.adminTokenURL(dataDirectoryURL: workspaceURL).lastPathComponent,
            ".admin-token"
        )
        XCTAssertEqual(
            ClawJSServiceSupervisorRoutes.iotPointerURL(applicationSupportRoot: applicationSupportRoot).path,
            "/tmp/clawix-fixture-home/Library/Application Support/Clawix/clawjs/dev-pointers/iot.dir"
        )

        XCTAssertTrue(resolverSource.contains("static var workspaceURL: URL"))
        XCTAssertTrue(resolverSource.contains("ClawJSServiceSupervisorRoutes.applicationSupportRoot()"))
        XCTAssertTrue(resolverSource.contains("ClawJSServiceSupervisorRoutes.workspaceURL(applicationSupportRoot: applicationSupportRoot)"))
        XCTAssertTrue(resolverSource.contains("ClawJSServiceSupervisorRoutes.serviceDataDirectoryURL("))
        XCTAssertTrue(routesSource.contains("static func userHomeDirectory() -> URL"))
        XCTAssertTrue(routesSource.contains("ClawixUserHomeRoutes.directory()"))
        XCTAssertTrue(routesSource.contains("homeDirectory ?? userHomeDirectory()"))
        XCTAssertFalse(routesSource.contains("FileManager.default.homeDirectoryForCurrentUser"))
        XCTAssertFalse(routesSource.contains("homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser"))
        XCTAssertFalse(routesSource.contains("secretsProxyURL(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser)"))
        XCTAssertFalse(supervisorSource.contains("FileManager.default.urls(for: .applicationSupportDirectory"))
        XCTAssertFalse(supervisorSource.contains(".appendingPathComponent(\"workspace\", isDirectory: true)"))
        XCTAssertFalse(supervisorSource.contains(".appendingPathComponent(\"runtime.sqlite\", isDirectory: false)"))
        XCTAssertFalse(supervisorSource.contains(".appendingPathComponent(\"bin/secrets-proxy\", isDirectory: false)"))
        XCTAssertFalse(supervisorSource.contains(".appendingPathComponent(\"dev-pointers\", isDirectory: true)"))
        XCTAssertFalse(supervisorSource.contains(".appendingPathComponent(\"iot.dir\", isDirectory: false)"))
    }

    func testRuntimeStartsFromBundleDirectoryForModuleResolution() throws {
        let resolverSource = try readSource("ClawJS/ClawJSServiceDirectoryResolver.swift")

        XCTAssertEqual(ClawJSServiceDirectoryResolver.workingDirectoryURL(for: .runtime), ClawJSRuntime.bundleRootURL)
        XCTAssertTrue(resolverSource.contains("if service == .runtime"))
        XCTAssertTrue(resolverSource.contains("return ClawJSRuntime.bundleRootURL"))
    }

    func testRuntimeLaunchAdapterUsesEvalFromBundleRuntimePackage() throws {
        let launchAdapterSource = try readSource("ClawJS/ClawJSServiceLaunchAdapter.swift")

        XCTAssertTrue(launchAdapterSource.contains("node_modules/@clawjs/runtime/package.json"))
        XCTAssertTrue(launchAdapterSource.contains("--input-type=module"))
        XCTAssertTrue(launchAdapterSource.contains("--eval"))
        XCTAssertTrue(launchAdapterSource.contains("buildRuntimeApp"))
        XCTAssertTrue(launchAdapterSource.contains("await app.listen"))
    }

    func testPublishingLaunchAdapterUsesDirectBundledServer() throws {
        let launchAdapterSource = try readSource("ClawJS/ClawJSServiceLaunchAdapter.swift")

        XCTAssertTrue(launchAdapterSource.contains("node_modules/publishing/dist/server.js"))
        XCTAssertTrue(launchAdapterSource.contains("return [serverJs.path]"))
    }

    func testIotLaunchAdapterResolvesPointerBundleAndMissingServer() throws {
        let root = try temporaryDirectory()
        let applicationSupportRoot = root.appendingPathComponent("support", isDirectory: true)
        let pointerDirectory = ClawJSServiceSupervisorRoutes.iotPointerURL(
            applicationSupportRoot: applicationSupportRoot
        ).deletingLastPathComponent()
        let devProject = root.appendingPathComponent("dev-iot", isDirectory: true)
        let devServer = devProject.appendingPathComponent("dist/server.js", isDirectory: false)
        try FileManager.default.createDirectory(at: pointerDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: devServer.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        _ = FileManager.default.createFile(atPath: devServer.path, contents: Data("iot".utf8))
        try devProject.path.write(
            to: ClawJSServiceSupervisorRoutes.iotPointerURL(applicationSupportRoot: applicationSupportRoot),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertEqual(
            ClawJSServiceLaunchAdapter.iotProjectDirectory(
                applicationSupportRoot: applicationSupportRoot,
                bundleURL: root.appendingPathComponent("empty.app", isDirectory: true)
            ),
            devProject
        )

        try FileManager.default.removeItem(at: ClawJSServiceSupervisorRoutes.iotPointerURL(
            applicationSupportRoot: applicationSupportRoot
        ))
        let bundleURL = root.appendingPathComponent("Clawix.app", isDirectory: true)
        let bundledProject = bundleURL.appendingPathComponent("Contents/Resources/clawjs-iot", isDirectory: true)
        let bundledServer = bundledProject.appendingPathComponent("dist/server.js", isDirectory: false)
        try FileManager.default.createDirectory(
            at: bundledServer.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        _ = FileManager.default.createFile(atPath: bundledServer.path, contents: Data("iot".utf8))

        XCTAssertEqual(
            ClawJSServiceLaunchAdapter.iotProjectDirectory(
                applicationSupportRoot: applicationSupportRoot,
                bundleURL: bundleURL
            ),
            bundledProject
        )

        XCTAssertNil(ClawJSServiceLaunchAdapter.iotProjectDirectory(
            applicationSupportRoot: root.appendingPathComponent("missing-support", isDirectory: true),
            bundleURL: root.appendingPathComponent("missing.app", isDirectory: true)
        ))
    }

    func testServiceSupervisorPolicyKeepsTokenAuthenticatedServicesUnadoptable() {
        XCTAssertFalse(ClawJSServiceSupervisorPolicy.canAdoptExistingService(.secrets))
        XCTAssertFalse(ClawJSServiceSupervisorPolicy.canAdoptExistingService(.database))
        XCTAssertTrue(ClawJSServiceSupervisorPolicy.canAdoptExistingService(.memory))
    }

    func testRestartPolicyBackoffBudgetAndHealthyResetWindow() throws {
        let supervisorSource = try readSource("ClawJS/ClawJSServiceSupervisor.swift")

        XCTAssertEqual(ClawJSServiceSupervisorPolicy.restartBudget, 5)
        XCTAssertEqual(ClawJSServiceSupervisorPolicy.healthyResetWindow, 60)
        XCTAssertEqual(ClawJSServiceSupervisorPolicy.restartDelay(for: 0), 1)
        XCTAssertEqual(ClawJSServiceSupervisorPolicy.restartDelay(for: 3), 8)
        XCTAssertEqual(ClawJSServiceSupervisorPolicy.restartDelay(for: 100), 60)
        XCTAssertTrue(supervisorSource.contains("Date().timeIntervalSince(lastReady) > Self.healthyResetWindow"))
        XCTAssertTrue(supervisorSource.contains("snap.restartCount = 0"))
        XCTAssertTrue(supervisorSource.contains("snap.restartCount < Self.restartBudget"))
        XCTAssertTrue(supervisorSource.contains("ClawJSServiceSupervisorPolicy.restartDelay(for: snap.restartCount)"))
    }

    func testHealthMonitorDaemonPushSuppressesFallbackProbeWindow() throws {
        let now = Date(timeIntervalSince1970: 100)
        let monitor = ClawJSServiceHealthMonitor.daemonPushMonitor(
            existing: nil,
            mappedState: .readyFromDaemon(port: ClawJSService.database.port),
            now: now
        )

        XCTAssertEqual(monitor.mode, .daemonOwned)
        XCTAssertTrue(monitor.hasReachedReady)
        XCTAssertEqual(monitor.lastDaemonUpdateAt, now)
        XCTAssertEqual(
            monitor.nextProbeAt,
            now.addingTimeInterval(ClawJSServiceHealthMonitor.daemonPushFreshWindow)
        )
        let fresh = try XCTUnwrap(ClawJSServiceHealthMonitor.daemonPushFreshOutcome(
            monitor: monitor,
            now: now.addingTimeInterval(1)
        ))
        XCTAssertEqual(fresh.action, .daemonPushFresh)
    }

    func testHealthMonitorLocalProbeMarksReadyAndTimeouts() throws {
        let now = Date(timeIntervalSince1970: 100)
        let starting = ClawJSServiceHealthMonitor.localMonitor(pid: 123, now: now)
        let ready = ClawJSServiceHealthMonitor.probeLocalService(
            service: .database,
            pid: 123,
            monitor: starting,
            now: now,
            alive: true
        )

        XCTAssertEqual(ready.action, .markReady(pid: 123, port: ClawJSService.database.port))
        XCTAssertTrue(try XCTUnwrap(ready.monitor).hasReachedReady)

        let timedOut = ClawJSServiceHealthMonitor.probeLocalService(
            service: .database,
            pid: 123,
            monitor: starting,
            now: now.addingTimeInterval(16),
            alive: false
        )

        XCTAssertNil(timedOut.monitor)
        XCTAssertEqual(timedOut.action, .terminate(reason: "did not become ready within 15s"))
    }

    func testHealthMonitorDaemonProbeChoosesFallbackOrUnavailable() {
        let now = Date(timeIntervalSince1970: 100)
        let monitor = ClawJSServiceHealthMonitor.daemonMonitor(readyTimeout: 6, now: now)
        let fallback = ClawJSServiceHealthMonitor.probeDaemonOwnedService(
            service: .database,
            monitor: monitor,
            now: now.addingTimeInterval(7),
            alive: false,
            canAdopt: false,
            canLaunchLocal: true
        )

        XCTAssertNil(fallback.monitor)
        XCTAssertEqual(fallback.action, .launchLocal)

        let unavailable = ClawJSServiceHealthMonitor.probeDaemonOwnedService(
            service: .database,
            monitor: monitor,
            now: now.addingTimeInterval(7),
            alive: false,
            canAdopt: false,
            canLaunchLocal: false
        )

        XCTAssertEqual(
            unavailable.action,
            .markDaemonUnavailable(reason: "Database is not reachable on 127.0.0.1:24102 while the bridge daemon is active.")
        )
    }

    func testTokenBootstrapPayloadsStayLineDelimitedJson() throws {
        let adminPayload = try ClawJSServiceTokenVault.localAdminBootstrapPayload(adminToken: "abc123")
        XCTAssertEqual(String(data: adminPayload, encoding: .utf8), "{\"adminToken\":\"abc123\"}\n")

        let secretsPayload = try ClawJSServiceTokenVault.secretsBootstrapPayload(
            adminToken: "admin",
            signedHostToken: "host",
            hostAssertionKeyBase64: "assertion",
            platformKey: Data([1, 2, 3])
        )
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(secretsPayload.dropLast()),
            options: []
        ) as? [String: String])
        XCTAssertEqual(decoded["adminToken"], "admin")
        XCTAssertEqual(decoded["signedHostToken"], "host")
        XCTAssertEqual(decoded["hostAssertionKeyBase64"], "assertion")
        XCTAssertEqual(decoded["kekBase64"], Data([1, 2, 3]).base64EncodedString())
        XCTAssertEqual(secretsPayload.last, 0x0a)
    }

    func testAsyncProcessRunnerCapturesOutput() async throws {
        let result = try await ClawJSAsyncProcessRunner.run(
            executable: "/bin/echo",
            arguments: ["clawix-supervisor"],
            timeoutNanoseconds: 1_000_000_000
        )

        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertEqual(String(data: result.standardOutput, encoding: .utf8), "clawix-supervisor\n")
    }

    func testAsyncProcessRunnerTimesOut() async throws {
        do {
            _ = try await ClawJSAsyncProcessRunner.run(
                executable: "/bin/sleep",
                arguments: ["2"],
                timeoutNanoseconds: 50_000_000
            )
            XCTFail("Expected the process runner to time out.")
        } catch ClawJSAsyncProcessRunner.Error.timedOut {
            return
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func readSource(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.sources, isDirectory: true)
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.clawix, isDirectory: true)
        return try String(
            contentsOf: root.appendingPathComponent(relativePath, isDirectory: false),
            encoding: .utf8
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawix-supervisor-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
