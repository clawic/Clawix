import XCTest
@testable import Clawix

@MainActor
final class NativeMacPermissionSimulationAgentTests: XCTestCase {
    typealias PermissionID = NativeMacPermissionBroker.PermissionID
    typealias Status = NativeMacPermissionBroker.Status
    typealias Agent = NativeMacPermissionSimulationAgent

    func testSimulatedStatesProduceExpectedBlockingActionsWithoutNativePrompt() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let cases: [(Status, Bool, Agent.Action)] = [
            (.granted, false, .continueWithoutPrompt),
            (.denied, true, .openSystemSettings),
            (.notDetermined, true, .requestAccess),
            (.restricted, true, .openSystemSettings),
            (.revoked, true, .openSystemSettings),
        ]

        for (status, isBlocked, action) in cases {
            let evaluation = Agent.evaluate(
                permission: .microphone,
                currentStatus: status,
                hostId: "Unit Test Host",
                bundleId: "com.example.clawix.tests",
                now: now
            )

            XCTAssertEqual(evaluation.status, status)
            XCTAssertEqual(evaluation.block.isBlocked, isBlocked)
            XCTAssertEqual(evaluation.block.action, action)
            XCTAssertEqual(evaluation.receipt.status, status)
            XCTAssertEqual(evaluation.receipt.source, "simulated_native_permission_agent")
            XCTAssertEqual(evaluation.receipt.realValidation, "external_pending_signed_host")
            XCTAssertEqual(evaluation.receipt.issuedAt, now)
        }
    }

    func testSystemSettingsRoutesAreAttachedToBlockedReceipts() {
        let evaluation = Agent.evaluate(permission: .camera, currentStatus: .denied)

        XCTAssertEqual(
            evaluation.receipt.settingsURLString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        )
        XCTAssertEqual(evaluation.block.settingsURLString, evaluation.receipt.settingsURLString)
        XCTAssertEqual(evaluation.block.receiptId, evaluation.receipt.id)
    }

    func testGrantedStateDoesNotExposeBlockingSettingsAction() {
        let evaluation = Agent.evaluate(permission: .contacts, currentStatus: .granted)

        XCTAssertFalse(evaluation.block.isBlocked)
        XCTAssertNil(evaluation.block.reason)
        XCTAssertEqual(evaluation.block.action, .continueWithoutPrompt)
        XCTAssertNil(evaluation.block.settingsURLString)
    }

    func testPriorGrantedReceiptConvertsLostGrantToRevoked() {
        let previous = Agent.evaluate(permission: .accessibility, currentStatus: .granted).receipt
        let evaluation = Agent.evaluate(
            permission: .accessibility,
            currentStatus: .denied,
            previousReceipt: previous
        )

        XCTAssertEqual(evaluation.status, .revoked)
        XCTAssertTrue(evaluation.block.isBlocked)
        XCTAssertEqual(evaluation.block.action, .openSystemSettings)
        XCTAssertEqual(evaluation.receipt.status, .revoked)
    }

    func testSnapshotCoversEveryPermissionWithHostReceipts() {
        let statuses: [PermissionID: Status] = [
            .microphone: .granted,
            .speechRecognition: .denied,
            .camera: .notDetermined,
            .accessibility: .restricted,
            .inputMonitoring: .revoked,
        ]

        let snapshot = Agent.snapshot(statuses: statuses, hostId: "unit-host")

        XCTAssertEqual(snapshot.count, PermissionID.allCases.count)
        XCTAssertEqual(Set(snapshot.map(\.permissionId)), Set(PermissionID.allCases))
        XCTAssertTrue(snapshot.allSatisfy { $0.receipt.hostId == "unit-host" })
        XCTAssertEqual(snapshot.first { $0.permissionId == .inputMonitoring }?.status, .revoked)
        XCTAssertEqual(snapshot.first { $0.permissionId == .contacts }?.status, .notDetermined)
    }
}
