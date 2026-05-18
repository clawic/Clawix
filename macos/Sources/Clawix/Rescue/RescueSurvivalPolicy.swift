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

struct RescueRepairStatusSummary: Equatable, Codable {
    var mode: RescueMode
    var pendingCount: Int
    var title: String
    var detail: String
    var actionTitle: String

    init?(decision: RescueSurvivalDecision) {
        guard decision.mode != .normal || !decision.pendingRepairSignals.isEmpty else { return nil }
        mode = decision.mode
        pendingCount = decision.pendingRepairSignals.count
        actionTitle = "Diagnose"
        switch decision.mode {
        case .normal:
            title = "Repair pending"
            detail = Self.countText(pendingCount)
        case .degraded:
            title = "Repair pending"
            detail = Self.countText(pendingCount)
        case .ephemeralChat:
            title = "Repair pending"
            detail = "Chat is available"
        case .diagnosticsOnly:
            title = "Diagnostics available"
            detail = "Chat runtime unavailable"
        }
    }

    private static func countText(_ count: Int) -> String {
        count == 1 ? "1 issue" : "\(count) issues"
    }
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

struct RescueRuntimeHealthThresholds: Equatable, Codable {
    var highCPUPercent: Double
    var highResidentBytes: UInt64
    var highFootprintBytes: UInt64
    var startupHangSeconds: TimeInterval
    var mainThreadStallMs: Double
    var crashLoopCount: Int

    static let defaults = RescueRuntimeHealthThresholds(
        highCPUPercent: 350,
        highResidentBytes: 3 * 1024 * 1024 * 1024,
        highFootprintBytes: 3 * 1024 * 1024 * 1024,
        startupHangSeconds: 45,
        mainThreadStallMs: 2_000,
        crashLoopCount: 3
    )
}

enum RescueRuntimeSignalDetector {
    static func signals(
        from health: RescueRuntimeHealthSnapshot?,
        thresholds: RescueRuntimeHealthThresholds = .defaults
    ) -> Set<RescueFailureSignal> {
        guard let health else { return [] }

        var signals: Set<RescueFailureSignal> = []
        if health.bridgeReachable == false {
            signals.insert(.bridgeRuntimeDown)
        }
        if let processCpuPercent = health.processCpuPercent,
           processCpuPercent >= thresholds.highCPUPercent {
            signals.insert(.highCPU)
        }
        if let residentBytes = health.residentBytes,
           residentBytes >= thresholds.highResidentBytes {
            signals.insert(.highMemory)
        }
        if let footprintBytes = health.footprintBytes,
           footprintBytes >= thresholds.highFootprintBytes {
            signals.insert(.highMemory)
        }
        if let startupElapsedSeconds = health.startupElapsedSeconds,
           startupElapsedSeconds >= thresholds.startupHangSeconds,
           health.bridgeReachable != true {
            signals.insert(.startupHang)
        }
        if let mainThreadStallMs = health.mainThreadStallMs,
           mainThreadStallMs >= thresholds.mainThreadStallMs {
            signals.insert(.startupHang)
        }
        if let recentCrashCount = health.recentCrashCount,
           recentCrashCount >= thresholds.crashLoopCount {
            signals.insert(.crashLoop)
        }
        return signals
    }
}

enum RescueRuntimeSignalMapper {
    static func decision(
        backendStatus: ClawixService.Status,
        runtimeHealth: RescueRuntimeHealthSnapshot? = nil,
        thresholds: RescueRuntimeHealthThresholds = .defaults
    ) -> RescueSurvivalDecision {
        var signals = RescueRuntimeSignalDetector.signals(from: runtimeHealth, thresholds: thresholds)
        let runtimeCount = runtimeHealth?.runtimeCount ?? defaultRuntimeCount(for: backendStatus)
        switch backendStatus {
        case .error:
            signals.insert(.bridgeRuntimeDown)
        case .idle, .starting, .ready:
            break
        }
        return RescueSurvivalPolicy.evaluate(signals: signals, availableRuntimeCount: runtimeCount)
    }

    private static func defaultRuntimeCount(for backendStatus: ClawixService.Status) -> Int {
        switch backendStatus {
        case .error:
            return 0
        case .idle, .starting, .ready:
            return 1
        }
    }
}

extension ClawixService.Status {
    var isRescueBridgeReachable: Bool? {
        switch self {
        case .ready:
            return true
        case .error:
            return false
        case .idle, .starting:
            return nil
        }
    }

    var defaultRescueRuntimeCount: Int {
        switch self {
        case .error:
            return 0
        case .idle, .starting, .ready:
            return 1
        }
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
