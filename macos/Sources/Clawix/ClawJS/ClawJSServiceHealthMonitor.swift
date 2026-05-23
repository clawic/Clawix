import Foundation

enum ClawJSServiceMonitorMode: Equatable {
    case local(pid: pid_t)
    case daemonOwned
}

struct ClawJSServiceMonitor: Equatable {
    var mode: ClawJSServiceMonitorMode
    var readyDeadline: Date
    var hasReachedReady: Bool
    var consecutiveFailures: Int
    var nextProbeAt: Date
    var lastDaemonUpdateAt: Date?
}

enum ClawJSLocalHealthAction: Equatable {
    case none
    case markReady(pid: pid_t, port: UInt16)
    case terminate(reason: String)
}

struct ClawJSLocalHealthProbeOutcome: Equatable {
    var monitor: ClawJSServiceMonitor?
    var action: ClawJSLocalHealthAction
}

enum ClawJSDaemonHealthAction: Equatable {
    case none
    case daemonPushFresh
    case publishDaemonReady
    case markReachableUnavailable
    case launchLocal
    case markDaemonUnavailable(reason: String)
}

struct ClawJSDaemonHealthProbeOutcome: Equatable {
    var monitor: ClawJSServiceMonitor?
    var action: ClawJSDaemonHealthAction
}

enum ClawJSServiceHealthMonitor {
    static let localStartupProbeInterval: TimeInterval = 1
    static let localReadyProbeInterval: TimeInterval = 5
    static let daemonStartupProbeInterval: TimeInterval = 1
    static let daemonFallbackProbeInterval: TimeInterval = 15
    static let daemonPushFreshWindow: TimeInterval = 30

    static func localMonitor(pid: pid_t, now: Date = Date()) -> ClawJSServiceMonitor {
        ClawJSServiceMonitor(
            mode: .local(pid: pid),
            readyDeadline: now.addingTimeInterval(15),
            hasReachedReady: false,
            consecutiveFailures: 0,
            nextProbeAt: now,
            lastDaemonUpdateAt: nil
        )
    }

    static func daemonMonitor(
        readyTimeout: TimeInterval,
        reachedReady: Bool = false,
        now: Date = Date()
    ) -> ClawJSServiceMonitor {
        ClawJSServiceMonitor(
            mode: .daemonOwned,
            readyDeadline: now.addingTimeInterval(readyTimeout),
            hasReachedReady: reachedReady,
            consecutiveFailures: 0,
            nextProbeAt: reachedReady
                ? now.addingTimeInterval(daemonFallbackProbeInterval)
                : now,
            lastDaemonUpdateAt: reachedReady ? now : nil
        )
    }

    static func daemonPushMonitor(
        existing: ClawJSServiceMonitor?,
        mappedState: ClawJSServiceState,
        now: Date = Date()
    ) -> ClawJSServiceMonitor {
        var monitor = existing ?? ClawJSServiceMonitor(
            mode: .daemonOwned,
            readyDeadline: now.addingTimeInterval(6),
            hasReachedReady: mappedState.isReady,
            consecutiveFailures: 0,
            nextProbeAt: now.addingTimeInterval(daemonPushFreshWindow),
            lastDaemonUpdateAt: now
        )
        monitor.mode = .daemonOwned
        monitor.hasReachedReady = monitor.hasReachedReady || mappedState.isReady
        monitor.consecutiveFailures = 0
        monitor.lastDaemonUpdateAt = now
        monitor.nextProbeAt = now.addingTimeInterval(daemonPushFreshWindow)
        return monitor
    }

    static func nextSleepInterval(monitors: [ClawJSService: ClawJSServiceMonitor], now: Date = Date()) -> TimeInterval? {
        guard !monitors.isEmpty else { return nil }
        let next = monitors.values.map(\.nextProbeAt).min() ?? now.addingTimeInterval(1)
        return max(0.05, next.timeIntervalSince(now))
    }

    static func probeLocalService(
        service: ClawJSService,
        pid: pid_t,
        monitor: ClawJSServiceMonitor,
        now: Date,
        alive: Bool
    ) -> ClawJSLocalHealthProbeOutcome {
        var monitor = monitor
        if alive {
            monitor.consecutiveFailures = 0
            if !monitor.hasReachedReady {
                monitor.hasReachedReady = true
                monitor.nextProbeAt = now.addingTimeInterval(localReadyProbeInterval)
                return ClawJSLocalHealthProbeOutcome(
                    monitor: monitor,
                    action: .markReady(pid: pid, port: service.port)
                )
            }
            monitor.nextProbeAt = now.addingTimeInterval(localReadyProbeInterval)
            return ClawJSLocalHealthProbeOutcome(monitor: monitor, action: .none)
        }

        monitor.consecutiveFailures += 1
        monitor.nextProbeAt = now.addingTimeInterval(localStartupProbeInterval)
        if !monitor.hasReachedReady, now > monitor.readyDeadline {
            return ClawJSLocalHealthProbeOutcome(
                monitor: nil,
                action: .terminate(reason: "did not become ready within 15s")
            )
        }
        if monitor.hasReachedReady, monitor.consecutiveFailures >= 5 {
            return ClawJSLocalHealthProbeOutcome(
                monitor: nil,
                action: .terminate(reason: "\(service.healthPath) silent for 5 consecutive checks")
            )
        }
        return ClawJSLocalHealthProbeOutcome(monitor: monitor, action: .none)
    }

    static func probeDaemonOwnedService(
        service: ClawJSService,
        monitor: ClawJSServiceMonitor,
        now: Date,
        alive: Bool,
        canAdopt: Bool,
        canLaunchLocal: Bool
    ) -> ClawJSDaemonHealthProbeOutcome {
        var monitor = monitor
        if let fresh = daemonPushFreshOutcome(monitor: monitor, now: now) {
            return fresh
        }

        if alive {
            monitor.consecutiveFailures = 0
            monitor.hasReachedReady = true
            monitor.nextProbeAt = now.addingTimeInterval(daemonFallbackProbeInterval)
            return ClawJSDaemonHealthProbeOutcome(
                monitor: monitor,
                action: canAdopt ? .publishDaemonReady : .markReachableUnavailable
            )
        }

        monitor.consecutiveFailures += 1
        monitor.nextProbeAt = now.addingTimeInterval(daemonStartupProbeInterval)
        if monitor.hasReachedReady || now > monitor.readyDeadline {
            if canLaunchLocal {
                return ClawJSDaemonHealthProbeOutcome(monitor: nil, action: .launchLocal)
            }
            return ClawJSDaemonHealthProbeOutcome(
                monitor: monitor,
                action: .markDaemonUnavailable(
                    reason: "\(service.displayName) is not reachable on 127.0.0.1:\(service.port) while the bridge daemon is active."
                )
            )
        }
        return ClawJSDaemonHealthProbeOutcome(monitor: monitor, action: .none)
    }

    static func daemonPushFreshOutcome(
        monitor: ClawJSServiceMonitor,
        now: Date
    ) -> ClawJSDaemonHealthProbeOutcome? {
        guard let lastDaemonUpdateAt = monitor.lastDaemonUpdateAt,
              now.timeIntervalSince(lastDaemonUpdateAt) < daemonPushFreshWindow else {
            return nil
        }
        var monitor = monitor
        monitor.nextProbeAt = lastDaemonUpdateAt.addingTimeInterval(daemonPushFreshWindow)
        return ClawJSDaemonHealthProbeOutcome(monitor: monitor, action: .daemonPushFresh)
    }
}
