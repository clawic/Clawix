import XCTest
@testable import Clawix

@MainActor
final class MacControlCenterTests: XCTestCase {
    func testPlansWifiConnectThroughWireWithoutPlaintextSecret() throws {
        let center = MacControlCenter(runner: RecordingMacActionRunner(), defaults: try makeDefaults(), persistence: makePersistence())
        let capability = try XCTUnwrap(MacControlSettingsCapability.capability(id: "mac.wifi.connect"))

        center.plan(capability, arguments: ["ssid": "Office", "secretRef": "sec_wifi_office", "device": "en0"])

        XCTAssertNil(center.lastError)
        XCTAssertEqual(center.lastPlan?.capabilityId, "mac.wifi.connect")
        XCTAssertEqual(center.lastPlan?.risk, "high")
        XCTAssertEqual(center.lastPlan?.blockedReasons, [])
        XCTAssertEqual(center.lastPlan?.requiredApprovals.first?.approverRoles, ["owner", "admin"])
        XCTAssertEqual(center.pendingApprovals.first?.capabilityId, "mac.wifi.connect")
        XCTAssertEqual(center.pendingApprovals.first?.risk, "high")
        XCTAssertEqual(center.timeline.map(\.kind), [.approval, .plan])
        XCTAssertEqual(center.timeline.first?.decision, "approval_required")
    }

    func testExecutesShortcutRunThroughInjectedRunner() throws {
        let runner = RecordingMacActionRunner()
        let center = MacControlCenter(runner: runner, defaults: try makeDefaults(), persistence: makePersistence())
        let capability = try XCTUnwrap(MacControlSettingsCapability.capability(id: "mac.shortcut.run"))

        center.execute(capability, arguments: ["name": "Daily Plan"], approved: true)

        XCTAssertNil(center.lastError)
        XCTAssertEqual(center.lastEvaluation?.decision, "allow")
        XCTAssertEqual(center.lastEvaluation?.receipt?.result, "ok")
        XCTAssertEqual(center.pendingApprovals, [])
        XCTAssertEqual(center.timeline.first?.kind, .evaluation)
        XCTAssertEqual(center.timeline.first?.receiptId, center.lastEvaluation?.receipt?.id)
        XCTAssertEqual(runner.processCalls, [
            RecordingMacActionRunner.ProcessCall(executable: "/usr/bin/shortcuts", arguments: ["run", "Daily Plan"]),
        ])
    }

    func testWindowMoveMissingCoordinatesIsBlockedByBrokerPlan() throws {
        let center = MacControlCenter(runner: RecordingMacActionRunner(), defaults: try makeDefaults(), persistence: makePersistence())
        let capability = try XCTUnwrap(MacControlSettingsCapability.capability(id: "mac.window.move"))

        center.plan(capability, arguments: ["app": "Safari"])

        XCTAssertNil(center.lastError)
        XCTAssertEqual(center.lastPlan?.capabilityId, "mac.window.move")
        XCTAssertEqual(center.lastPlan?.executable, false)
        XCTAssertEqual(center.lastPlan?.blockedReasons, ["Window move requires integer x and y arguments."])
        XCTAssertEqual(center.timeline.first?.decision, "blocked")
        XCTAssertEqual(center.timeline.first?.detail, "Window move requires integer x and y arguments.")
    }

    func testClearTimelineRemovesEventsAndPendingApprovals() throws {
        let persistence = makePersistence()
        let center = MacControlCenter(runner: RecordingMacActionRunner(), defaults: try makeDefaults(), persistence: persistence)
        let capability = try XCTUnwrap(MacControlSettingsCapability.capability(id: "mac.shortcut.run"))

        center.plan(capability, arguments: ["name": "Daily Plan"])
        XCTAssertFalse(center.timeline.isEmpty)
        XCTAssertFalse(center.pendingApprovals.isEmpty)

        center.clearTimeline()

        XCTAssertEqual(center.timeline, [])
        XCTAssertEqual(center.pendingApprovals, [])
        XCTAssertEqual(MacControlCenter(runner: RecordingMacActionRunner(), defaults: try makeDefaults(), persistence: persistence).timeline, [])
    }

    func testTimelineAndPendingApprovalsPersistAcrossCenters() throws {
        let persistence = makePersistence()
        let capability = try XCTUnwrap(MacControlSettingsCapability.capability(id: "mac.wifi.connect"))
        let center = MacControlCenter(runner: RecordingMacActionRunner(), defaults: try makeDefaults(), persistence: persistence)

        center.plan(capability, arguments: ["ssid": "Office", "secretRef": "sec_wifi_office"])

        let restored = MacControlCenter(runner: RecordingMacActionRunner(), defaults: try makeDefaults(), persistence: persistence)
        XCTAssertEqual(restored.timeline.map(\.kind), [.approval, .plan])
        XCTAssertEqual(restored.timeline.first?.decision, "approval_required")
        XCTAssertEqual(restored.pendingApprovals.first?.capabilityId, "mac.wifi.connect")
    }

    func testProjectedPendingApprovalIdsPersistAcrossCenters() throws {
        let persistence = makePersistence()
        let capability = try XCTUnwrap(MacControlSettingsCapability.capability(id: "mac.wifi.connect"))
        let center = MacControlCenter(runner: RecordingMacActionRunner(), defaults: try makeDefaults(), persistence: persistence)

        center.plan(capability, arguments: ["ssid": "Office", "secretRef": "sec_wifi_office"])
        let approval = try XCTUnwrap(center.pendingApprovals.first)

        center.markPendingApprovalProjected(
            id: approval.id,
            approvalRecordId: "approval_1",
            inboxThreadId: "thread_1",
            inboxMessageId: "message_1"
        )

        let restored = MacControlCenter(runner: RecordingMacActionRunner(), defaults: try makeDefaults(), persistence: persistence)
        XCTAssertEqual(restored.pendingApprovals.first?.globalApprovalRecordId, "approval_1")
        XCTAssertEqual(restored.pendingApprovals.first?.globalInboxThreadId, "thread_1")
        XCTAssertEqual(restored.pendingApprovals.first?.globalInboxMessageId, "message_1")
        XCTAssertEqual(restored.pendingApprovals.first?.isProjectedToGlobalInbox, true)
    }

    func testPermissionSnapshotIncludesPrivacyDataDomains() {
        let ids = Set(MacControlPermissionSnapshot.current.map(\.id))

        XCTAssertTrue(ids.contains("mac.permission.calendar"))
        XCTAssertTrue(ids.contains("mac.permission.contacts"))
        XCTAssertTrue(ids.contains("mac.permission.reminders"))
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "MacControlCenterTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makePersistence() -> MacControlCenterPersistence {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-control-center-\(UUID().uuidString)", isDirectory: true)
        return MacControlCenterPersistence(
            timelineURL: directory.appendingPathComponent("timeline.jsonl"),
            pendingApprovalsURL: directory.appendingPathComponent("pending-approvals.json")
        )
    }
}
