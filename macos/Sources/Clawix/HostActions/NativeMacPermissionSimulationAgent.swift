import Foundation

@MainActor
enum NativeMacPermissionSimulationAgent {
    typealias PermissionID = NativeMacPermissionBroker.PermissionID
    typealias Status = NativeMacPermissionBroker.Status

    enum Action: String, Codable, Equatable {
        case continueWithoutPrompt
        case requestAccess
        case openSystemSettings
    }

    struct HostReceipt: Codable, Equatable, Identifiable {
        let id: String
        let hostId: String
        let bundleId: String
        let permissionId: PermissionID
        let status: Status
        let issuedAt: Date
        let source: String
        let settingsURLString: String
        let realValidation: String
    }

    struct BlockState: Codable, Equatable {
        let isBlocked: Bool
        let reason: String?
        let action: Action
        let settingsURLString: String?
        let receiptId: String?
    }

    struct Evaluation: Codable, Equatable, Identifiable {
        var id: String { permissionId.rawValue }

        let permissionId: PermissionID
        let status: Status
        let receipt: HostReceipt
        let block: BlockState
    }

    static func evaluate(
        permission: PermissionID,
        currentStatus: Status,
        previousReceipt: HostReceipt? = nil,
        hostId: String = "simulated-host",
        bundleId: String = "com.example.clawix",
        now: Date = Date()
    ) -> Evaluation {
        let reconciledStatus = reconcile(currentStatus: currentStatus, previousReceipt: previousReceipt)
        let settingsURLString = NativeMacPermissionBroker.settingsURLString(for: permission)
        let receipt = HostReceipt(
            id: receiptId(permission: permission, status: reconciledStatus, hostId: hostId),
            hostId: hostId,
            bundleId: bundleId,
            permissionId: permission,
            status: reconciledStatus,
            issuedAt: now,
            source: "simulated_native_permission_agent",
            settingsURLString: settingsURLString,
            realValidation: "external_pending_signed_host"
        )
        return Evaluation(
            permissionId: permission,
            status: reconciledStatus,
            receipt: receipt,
            block: blockState(status: reconciledStatus, receipt: receipt)
        )
    }

    static func snapshot(
        statuses: [PermissionID: Status],
        previousReceipts: [PermissionID: HostReceipt] = [:],
        hostId: String = "simulated-host",
        bundleId: String = "com.example.clawix",
        now: Date = Date()
    ) -> [Evaluation] {
        PermissionID.allCases.map { permission in
            evaluate(
                permission: permission,
                currentStatus: statuses[permission] ?? .notDetermined,
                previousReceipt: previousReceipts[permission],
                hostId: hostId,
                bundleId: bundleId,
                now: now
            )
        }
    }

    static func reconcile(currentStatus: Status, previousReceipt: HostReceipt?) -> Status {
        guard previousReceipt?.status == .granted, currentStatus != .granted else {
            return currentStatus
        }
        return .revoked
    }

    private static func blockState(status: Status, receipt: HostReceipt) -> BlockState {
        let action: Action
        switch status {
        case .granted:
            action = .continueWithoutPrompt
        case .notDetermined:
            action = .requestAccess
        case .denied, .restricted, .revoked:
            action = .openSystemSettings
        }
        return BlockState(
            isBlocked: !status.isGranted,
            reason: status.blockedReason,
            action: action,
            settingsURLString: status.isGranted ? nil : receipt.settingsURLString,
            receiptId: receipt.id
        )
    }

    private static func receiptId(permission: PermissionID, status: Status, hostId: String) -> String {
        let safePermission = permission.rawValue.replacingOccurrences(of: ".", with: "_")
        let safeHost = hostId
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9_-]+"#, with: "_", options: .regularExpression)
        return "permission_receipt_\(safeHost)_\(safePermission)_\(status.rawValue)"
    }
}
