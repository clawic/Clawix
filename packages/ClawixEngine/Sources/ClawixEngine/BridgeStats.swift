import Foundation
import ClawixCore

/// Shared, thread-safe counter for live bridge sessions. Updated by
/// `BridgeSession` on successful auth and on close; read from any
/// queue (notably the daemon heartbeat thread) without hopping back
/// to the MainActor. Locking instead of `@MainActor` because the
/// access pattern is one writer (the session lifecycle, on the main
/// queue) and one reader (a background timer in the daemon).
public final class BridgeStats: @unchecked Sendable {
    public static let shared = BridgeStats()
    public static let didChangeNotification = Notification.Name(ClawixBridgeStatusSurface.didChangeNotificationName)

    private let lock = NSLock()
    private var _activeSessions: Int = 0

    private init() {}

    public var activeSessionCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _activeSessions
    }

    func increment() {
        lock.lock()
        _activeSessions += 1
        lock.unlock()
        publishChange()
    }

    func decrement() {
        var changed = false
        lock.lock()
        if _activeSessions > 0 {
            _activeSessions -= 1
            changed = true
        }
        lock.unlock()
        if changed { publishChange() }
    }

    /// Reset to 0. Called by `BridgeServer.stop()` so a clean restart
    /// does not inherit stale counts from cancelled sessions.
    public func reset() {
        var changed = false
        lock.lock()
        changed = _activeSessions != 0
        _activeSessions = 0
        lock.unlock()
        if changed { publishChange() }
    }

    private func publishChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
