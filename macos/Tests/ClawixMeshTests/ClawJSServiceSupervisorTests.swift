import XCTest
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

        XCTAssertTrue(supervisorSource.contains("private var monitorTask: Task<Void, Never>?"))
        XCTAssertTrue(supervisorSource.contains("private var serviceMonitors: [ClawJSService: ServiceMonitor]"))
        XCTAssertTrue(supervisorSource.contains("runAggregateMonitor()"))
        XCTAssertTrue(supervisorSource.contains("monitorDueServices()"))
        XCTAssertFalse(supervisorSource.contains("healthTasks"))
        XCTAssertFalse(supervisorSource.contains("pollHealth(for:"))
        XCTAssertFalse(supervisorSource.contains("pollDaemonOwnedService("))
    }

    func testDaemonPushStatusSuppressesFallbackProbeWindow() throws {
        let supervisorSource = try readSource("ClawJS/ClawJSServiceSupervisor.swift")

        XCTAssertTrue(supervisorSource.contains("applyDaemonServiceStatuses("))
        XCTAssertTrue(supervisorSource.contains("activeDemand: Set<ClawJSService>"))
        XCTAssertTrue(supervisorSource.contains("daemonPushFreshWindow"))
        XCTAssertTrue(supervisorSource.contains("monitor.daemon_push_fresh"))
        XCTAssertTrue(supervisorSource.contains("daemonFallbackProbeInterval"))
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
        XCTAssertTrue(supervisorSource.contains("$0.state = Self.availableOnDemandState(for: service)"))
    }

    func testProcessInspectionDoesNotUseSynchronousWaits() throws {
        let supportSource = try readSource("ClawJS/ClawJSProcessSupport.swift")
        let supervisorSource = try readSource("ClawJS/ClawJSServiceSupervisor.swift")

        XCTAssertFalse(supportSource.contains("waitUntilExit"))
        XCTAssertFalse(supervisorSource.contains("waitUntilExit"))
        XCTAssertTrue(supervisorSource.contains("actor ClawJSServiceSupervisor"))
    }

    func testRuntimeStartsFromBundleDirectoryForModuleResolution() throws {
        let supervisorSource = try readSource("ClawJS/ClawJSServiceSupervisor.swift")

        XCTAssertTrue(supervisorSource.contains("process.currentDirectoryURL = Self.workingDirectoryURL(for: service)"))
        XCTAssertTrue(supervisorSource.contains("if service == .runtime"))
        XCTAssertTrue(supervisorSource.contains("return ClawJSRuntime.bundleRootURL"))
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
}
