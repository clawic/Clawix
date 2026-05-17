import XCTest
@testable import Clawix

@MainActor
final class MacControlCenterTests: XCTestCase {
    func testPlansWifiConnectThroughWireWithoutPlaintextSecret() throws {
        let center = MacControlCenter(runner: RecordingMacActionRunner(), defaults: try makeDefaults())
        let capability = try XCTUnwrap(MacControlSettingsCapability.capability(id: "mac.wifi.connect"))

        center.plan(capability, arguments: ["ssid": "Office", "secretRef": "sec_wifi_office", "device": "en0"])

        XCTAssertNil(center.lastError)
        XCTAssertEqual(center.lastPlan?.capabilityId, "mac.wifi.connect")
        XCTAssertEqual(center.lastPlan?.risk, "high")
        XCTAssertEqual(center.lastPlan?.blockedReasons, [])
        XCTAssertEqual(center.lastPlan?.requiredApprovals.first?.approverRoles, ["owner", "admin"])
    }

    func testExecutesShortcutRunThroughInjectedRunner() throws {
        let runner = RecordingMacActionRunner()
        let center = MacControlCenter(runner: runner, defaults: try makeDefaults())
        let capability = try XCTUnwrap(MacControlSettingsCapability.capability(id: "mac.shortcut.run"))

        center.execute(capability, arguments: ["name": "Daily Plan"], approved: true)

        XCTAssertNil(center.lastError)
        XCTAssertEqual(center.lastEvaluation?.decision, "allow")
        XCTAssertEqual(center.lastEvaluation?.receipt?.result, "ok")
        XCTAssertEqual(runner.processCalls, [
            RecordingMacActionRunner.ProcessCall(executable: "/usr/bin/shortcuts", arguments: ["run", "Daily Plan"]),
        ])
    }

    func testWindowMoveMissingCoordinatesIsBlockedByBrokerPlan() throws {
        let center = MacControlCenter(runner: RecordingMacActionRunner(), defaults: try makeDefaults())
        let capability = try XCTUnwrap(MacControlSettingsCapability.capability(id: "mac.window.move"))

        center.plan(capability, arguments: ["app": "Safari"])

        XCTAssertNil(center.lastError)
        XCTAssertEqual(center.lastPlan?.capabilityId, "mac.window.move")
        XCTAssertEqual(center.lastPlan?.executable, false)
        XCTAssertEqual(center.lastPlan?.blockedReasons, ["Window move requires integer x and y arguments."])
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "MacControlCenterTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
