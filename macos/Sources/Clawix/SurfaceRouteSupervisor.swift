import Foundation
import SwiftUI

enum SurfaceRouteSupervisionState: Equatable {
    case ready(surfaceID: String)
    case loading(surfaceID: String, timeoutSeconds: TimeInterval, message: String?, progress: Double?)
    case partial(surfaceID: String, message: String)
    case degraded(surfaceID: String, reason: String)
    case error(surfaceID: String, message: String)
    case unavailable(surfaceID: String, reason: String)
    case cancelled(surfaceID: String)

    var surfaceID: String {
        switch self {
        case .ready(let surfaceID),
             .loading(let surfaceID, _, _, _),
             .partial(let surfaceID, _),
             .degraded(let surfaceID, _),
             .error(let surfaceID, _),
             .unavailable(let surfaceID, _),
             .cancelled(let surfaceID):
            return surfaceID
        }
    }

    var isTerminal: Bool {
        switch self {
        case .ready, .degraded, .error, .unavailable, .cancelled:
            return true
        case .loading, .partial:
            return false
        }
    }
}

enum SurfaceRouteReport: Equatable {
    case loading(message: String?, progress: Double?)
    case partial(message: String)
    case ready
    case degraded(reason: String)
    case error(message: String)
    case unavailable(reason: String)
    case cancelled
}

enum SurfaceRouteReadinessMode: String, Equatable, Hashable {
    case immediateAfterFirstRender
    case childReported
}

enum SurfaceRouteReadinessPolicy {
    static func mode(
        for entry: SurfaceRouteRegistryEntry,
        hasActiveCustomVariant: Bool
    ) -> SurfaceRouteReadinessMode {
        hasActiveCustomVariant ? .childReported : entry.readinessMode
    }
}

enum SurfaceRouteSupervisor {
    static func start(descriptor: SurfaceRouteDescriptor) -> SurfaceRouteSupervisionState {
        guard descriptor.requiresIndependentDegradation,
              let timeoutSeconds = descriptor.timeoutSeconds else {
            return .ready(surfaceID: descriptor.id)
        }
        return .loading(
            surfaceID: descriptor.id,
            timeoutSeconds: timeoutSeconds,
            message: nil,
            progress: nil
        )
    }

    static func apply(
        report: SurfaceRouteReport,
        state: SurfaceRouteSupervisionState,
        descriptor: SurfaceRouteDescriptor
    ) -> SurfaceRouteSupervisionState {
        guard state.surfaceID == descriptor.id else { return state }
        switch report {
        case .loading(let message, let progress):
            guard descriptor.requiresIndependentDegradation,
                  let timeoutSeconds = descriptor.timeoutSeconds else {
                return .ready(surfaceID: descriptor.id)
            }
            return .loading(
                surfaceID: descriptor.id,
                timeoutSeconds: timeoutSeconds,
                message: message,
                progress: progress.map { min(max($0, 0), 1) }
            )
        case .partial(let message):
            return .partial(surfaceID: descriptor.id, message: message)
        case .ready:
            return .ready(surfaceID: descriptor.id)
        case .degraded(let reason):
            return .degraded(surfaceID: descriptor.id, reason: reason)
        case .error(let message):
            return .error(surfaceID: descriptor.id, message: message)
        case .unavailable(let reason):
            return .unavailable(surfaceID: descriptor.id, reason: reason)
        case .cancelled:
            return .cancelled(surfaceID: descriptor.id)
        }
    }

    static func afterFirstRender(
        state: SurfaceRouteSupervisionState,
        descriptor: SurfaceRouteDescriptor,
        readinessMode: SurfaceRouteReadinessMode
    ) -> SurfaceRouteSupervisionState {
        guard state.surfaceID == descriptor.id else { return state }
        switch readinessMode {
        case .immediateAfterFirstRender:
            return markReady(state: state, descriptor: descriptor)
        case .childReported:
            return state
        }
    }

    static func markReady(
        state: SurfaceRouteSupervisionState,
        descriptor: SurfaceRouteDescriptor
    ) -> SurfaceRouteSupervisionState {
        guard state.surfaceID == descriptor.id else { return state }
        return .ready(surfaceID: descriptor.id)
    }

    static func timeout(
        state: SurfaceRouteSupervisionState,
        descriptor: SurfaceRouteDescriptor
    ) -> SurfaceRouteSupervisionState {
        guard case .loading(let surfaceID, _, _, _) = state,
              surfaceID == descriptor.id else {
            return state
        }
        let seconds = Int(descriptor.timeoutSeconds ?? 0)
        return .degraded(
            surfaceID: descriptor.id,
            reason: "Surface did not become ready within \(seconds) seconds."
        )
    }

    static func cancel(
        state: SurfaceRouteSupervisionState,
        descriptor: SurfaceRouteDescriptor
    ) -> SurfaceRouteSupervisionState {
        guard state.surfaceID == descriptor.id else { return state }
        return .cancelled(surfaceID: descriptor.id)
    }
}

struct SurfaceRouteReporter {
    var surfaceID: String?
    var report: (SurfaceRouteReport) -> Void

    static let noop = SurfaceRouteReporter(surfaceID: nil, report: { _ in })

    func loading(_ message: String? = nil, progress: Double? = nil) {
        report(.loading(message: message, progress: progress))
    }

    func partial(_ message: String) {
        report(.partial(message: message))
    }

    func ready() {
        report(.ready)
    }

    func degraded(_ reason: String) {
        report(.degraded(reason: reason))
    }

    func error(_ message: String) {
        report(.error(message: message))
    }

    func unavailable(_ reason: String) {
        report(.unavailable(reason: reason))
    }

    func cancelled() {
        report(.cancelled)
    }
}

private struct SurfaceRouteReporterKey: EnvironmentKey {
    static let defaultValue: SurfaceRouteReporter = .noop
}

extension EnvironmentValues {
    var surfaceRouteReporter: SurfaceRouteReporter {
        get { self[SurfaceRouteReporterKey.self] }
        set { self[SurfaceRouteReporterKey.self] = newValue }
    }
}
