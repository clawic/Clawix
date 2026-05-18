import Foundation

enum RescueFailureSignal: String, Codable, CaseIterable, Hashable {
    case migrationFailure
    case storageUnavailable
    case historyUnavailable
    case projectsUnavailable
    case bridgeRuntimeDown
    case startupHang
    case crashLoop
    case highCPU
    case highMemory
    case noRuntimeAvailable
}

enum RescueCapability: String, Codable, CaseIterable, Hashable {
    case launch
    case chat
    case agentExecution
    case repairContext
    case diagnosticsExport
    case nonCriticalUI
    case persistentHistory
}

enum RescueMode: String, Codable, Equatable {
    case normal
    case degraded
    case ephemeralChat
    case diagnosticsOnly
}

struct RescueSurvivalDecision: Equatable, Codable {
    var mode: RescueMode
    var preservedCapabilities: [RescueCapability]
    var disabledCapabilities: [RescueCapability]
    var pendingRepairSignals: [RescueFailureSignal]
    var circuitBreakers: [RescueFailureSignal]
    var requiresApprovalForRiskyRepair: Bool

    var canLaunch: Bool { preservedCapabilities.contains(.launch) }
    var canChat: Bool { preservedCapabilities.contains(.chat) }
    var canProvideRepairContext: Bool { preservedCapabilities.contains(.repairContext) }
}

enum RescueSurvivalPolicy {
    static func evaluate(
        signals rawSignals: Set<RescueFailureSignal>,
        availableRuntimeCount: Int
    ) -> RescueSurvivalDecision {
        var signals = rawSignals
        if availableRuntimeCount <= 0 {
            signals.insert(.noRuntimeAvailable)
        }

        let circuitBreakers = signals.filter {
            [.migrationFailure, .bridgeRuntimeDown, .startupHang, .crashLoop, .highCPU, .highMemory].contains($0)
        }.sortedByRawValue()

        if signals.contains(.noRuntimeAvailable) {
            return RescueSurvivalDecision(
                mode: .diagnosticsOnly,
                preservedCapabilities: [.launch, .repairContext, .diagnosticsExport],
                disabledCapabilities: [.chat, .agentExecution, .nonCriticalUI, .persistentHistory],
                pendingRepairSignals: signals.sortedByRawValue(),
                circuitBreakers: circuitBreakers,
                requiresApprovalForRiskyRepair: true
            )
        }

        if signals.intersects([.migrationFailure, .storageUnavailable, .historyUnavailable, .projectsUnavailable, .bridgeRuntimeDown]) {
            return RescueSurvivalDecision(
                mode: .ephemeralChat,
                preservedCapabilities: [.launch, .chat, .agentExecution, .repairContext, .diagnosticsExport],
                disabledCapabilities: [.nonCriticalUI, .persistentHistory],
                pendingRepairSignals: signals.sortedByRawValue(),
                circuitBreakers: circuitBreakers,
                requiresApprovalForRiskyRepair: true
            )
        }

        if signals.intersects([.startupHang, .crashLoop, .highCPU, .highMemory]) {
            return RescueSurvivalDecision(
                mode: .degraded,
                preservedCapabilities: [.launch, .chat, .agentExecution, .repairContext, .diagnosticsExport, .persistentHistory],
                disabledCapabilities: [.nonCriticalUI],
                pendingRepairSignals: signals.sortedByRawValue(),
                circuitBreakers: circuitBreakers,
                requiresApprovalForRiskyRepair: true
            )
        }

        return RescueSurvivalDecision(
            mode: .normal,
            preservedCapabilities: RescueCapability.allCases.sortedByRawValue(),
            disabledCapabilities: [],
            pendingRepairSignals: [],
            circuitBreakers: [],
            requiresApprovalForRiskyRepair: false
        )
    }
}

private extension Set where Element == RescueFailureSignal {
    func intersects(_ values: Set<RescueFailureSignal>) -> Bool {
        !intersection(values).isEmpty
    }
}

private extension Sequence where Element: RawRepresentable, Element.RawValue == String {
    func sortedByRawValue() -> [Element] {
        sorted { $0.rawValue < $1.rawValue }
    }
}
