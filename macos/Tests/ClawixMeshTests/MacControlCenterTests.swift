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

    func testGlobalInboxProjectorCreatesApprovalThreadAndMessage() async throws {
        let createdAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-05-18T08:00:00Z"))
        let approval = MacControlPendingApproval(
            id: "approval_mac_wifi",
            requestId: "macreq_wifi",
            capabilityId: "mac.wifi.connect",
            risk: "high",
            approverRoles: ["owner", "admin"],
            reason: "Requires explicit Mac Control approval.",
            createdAt: createdAt
        )
        let writer = RecordingGlobalInboxWriter()

        let projection = try await MacControlGlobalInboxProjector.project(approval, using: writer)

        XCTAssertEqual(projection.approvalRecordId, "approvals_1")
        XCTAssertEqual(projection.inboxThreadId, "inbox_threads_1")
        XCTAssertEqual(projection.inboxMessageId, "inbox_messages_1")
        XCTAssertEqual(writer.created.map(\.collection), ["approvals", "inbox_threads", "inbox_messages"])
        XCTAssertEqual(writer.created[0].data["kind"], .string("policy_gate"))
        XCTAssertEqual(writer.created[0].data["status"], .string("pending"))
        XCTAssertEqual(writer.created[0].data["policyReason"], .string("Requires explicit Mac Control approval."))
        XCTAssertEqual(writer.created[1].data["channel"], .string("mac_control"))
        XCTAssertEqual(writer.created[1].data["externalThreadId"], .string("approval_mac_wifi"))
        XCTAssertEqual(writer.created[2].data["threadId"], .string("inbox_threads_1"))
        XCTAssertEqual(writer.created[2].data["externalMessageId"], .string("macreq_wifi"))
        XCTAssertEqual(
            writer.created[2].data["attachments"],
            .object([
                "approvalRecordId": .string("approvals_1"),
                "capabilityId": .string("mac.wifi.connect"),
            ])
        )
    }

    func testGlobalInboxProjectorCleansUpApprovalWhenThreadCreationFails() async throws {
        let approval = MacControlPendingApproval(
            id: "approval_mac_wifi",
            requestId: "macreq_wifi",
            capabilityId: "mac.wifi.connect",
            risk: "high",
            approverRoles: ["owner", "admin"],
            reason: "Requires explicit Mac Control approval.",
            createdAt: Date()
        )
        let writer = RecordingGlobalInboxWriter(failingCollection: "inbox_threads")

        do {
            _ = try await MacControlGlobalInboxProjector.project(approval, using: writer)
            XCTFail("Projection should fail when inbox thread creation fails.")
        } catch {
            XCTAssertEqual(writer.deleted, [
                RecordingGlobalInboxWriter.Deleted(collection: "approvals", id: "approvals_1"),
            ])
        }
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

@MainActor
private final class RecordingGlobalInboxWriter: MacControlGlobalInboxWriting {
    struct Created: Equatable {
        let collection: String
        let data: [String: DBJSON]
    }

    struct Deleted: Equatable {
        let collection: String
        let id: String
    }

    enum Failure: Error {
        case requested
    }

    private let failingCollection: String?
    private var counters: [String: Int] = [:]
    private(set) var created: [Created] = []
    private(set) var deleted: [Deleted] = []

    init(failingCollection: String? = nil) {
        self.failingCollection = failingCollection
    }

    func createRecord(collection name: String, data: [String: DBJSON]) async throws -> DBRecord {
        if name == failingCollection {
            throw Failure.requested
        }
        let next = (counters[name] ?? 0) + 1
        counters[name] = next
        let id = "\(name)_\(next)"
        created.append(Created(collection: name, data: data))
        return DBRecord(id: id, createdAt: "2026-05-18T08:00:00Z", updatedAt: "2026-05-18T08:00:00Z", data: data)
    }

    func deleteRecord(collection name: String, id: String) async throws {
        deleted.append(Deleted(collection: name, id: id))
    }
}
