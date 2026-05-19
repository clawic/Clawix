import Foundation

enum SurfaceRouteSupervisionState: Equatable {
    case ready(surfaceID: String)
    case loading(surfaceID: String, timeoutSeconds: TimeInterval)
    case degraded(surfaceID: String, reason: String)
    case cancelled(surfaceID: String)

    var surfaceID: String {
        switch self {
        case .ready(let surfaceID),
             .loading(let surfaceID, _),
             .degraded(let surfaceID, _),
             .cancelled(let surfaceID):
            return surfaceID
        }
    }

    var isTerminal: Bool {
        switch self {
        case .ready, .degraded, .cancelled:
            return true
        case .loading:
            return false
        }
    }
}

enum SurfaceRouteSupervisor {
    static func start(descriptor: SurfaceRouteDescriptor) -> SurfaceRouteSupervisionState {
        guard descriptor.requiresIndependentDegradation,
              let timeoutSeconds = descriptor.timeoutSeconds else {
            return .ready(surfaceID: descriptor.id)
        }
        return .loading(surfaceID: descriptor.id, timeoutSeconds: timeoutSeconds)
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
        guard state == start(descriptor: descriptor) else { return state }
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
