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

    func testProcessInspectionDoesNotUseSynchronousWaits() throws {
        let supportSource = try readSource("ClawJS/ClawJSProcessSupport.swift")
        let supervisorSource = try readSource("ClawJS/ClawJSServiceSupervisor.swift")

        XCTAssertFalse(supportSource.contains("waitUntilExit"))
        XCTAssertFalse(supervisorSource.contains("waitUntilExit"))
        XCTAssertTrue(supervisorSource.contains("actor ClawJSServiceSupervisor"))
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
