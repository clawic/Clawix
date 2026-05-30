import SwiftUI
import AppKit

/// Cooldown-based scroll gate. Sidebar hover handlers avoid writing state
/// while scroll is active, then coalesce the final hover after the cooldown.
/// Tracking a moving cursor over passing rows is what costs during scroll:
/// ungated, every row crossed produces two `@State` mutations and two body
/// re-evaluations.
///
/// Implementation: every observed scroll event stamps `lastScrollTime`.
/// `isScrolling` returns `true` for `cooldown` seconds after the last
/// stamp, no timers. Self-clearing, robust to gaps between event sources.
final class SidebarScrollState {
    static let shared = SidebarScrollState()

    /// How long after the last scroll event the gate stays engaged.
    /// Keep the gate short so hover can re-engage quickly; delayed replay
    /// below bridges the final cooldown window after scrolling settles.
    private static let cooldown: TimeInterval = 0.08

    private var lastScrollTime: TimeInterval = 0

    private init() {}

    var isScrolling: Bool {
        CFAbsoluteTimeGetCurrent() - lastScrollTime < Self.cooldown
    }

    var remainingCooldown: TimeInterval {
        max(0, Self.cooldown - (CFAbsoluteTimeGetCurrent() - lastScrollTime))
    }

    /// Stamp scroll activity. Called from the AppKit-side installer on
    /// every signal that the sidebar is being scrolled (wheel events,
    /// live scroll notifications, clip-view bounds changes).
    func bump() {
        lastScrollTime = CFAbsoluteTimeGetCurrent()
    }
}

@MainActor
final class SidebarHoverLatencyProbe {
    static let shared = SidebarHoverLatencyProbe()

    private struct ArmedProbe {
        let token: UUID
        let startedAt: CFTimeInterval
    }

    private struct RecordedProbe {
        let token: UUID
        let elapsedMs: Double
        let active: Bool
    }

    private var armed: [String: ArmedProbe] = [:]
    private var recorded: [String: RecordedProbe] = [:]
    private var handlers: [String: (Bool) -> Void] = [:]

    private init() {}

    func arm(id: String) -> UUID {
        let token = UUID()
        armed[id] = ArmedProbe(token: token, startedAt: CACurrentMediaTime())
        recorded[id] = nil
        return token
    }

    func record(id: String, active: Bool) {
        guard let probe = armed[id] else { return }
        recorded[id] = RecordedProbe(
            token: probe.token,
            elapsedMs: (CACurrentMediaTime() - probe.startedAt) * 1000,
            active: active
        )
    }

    func result(id: String, token: UUID) -> [String: Any]? {
        guard let value = recorded[id], value.token == token else { return nil }
        return [
            "id": id,
            "hoverActive": value.active,
            "hoverLatencyMs": value.elapsedMs,
        ]
    }

    func register(id: String, handler: @escaping (Bool) -> Void) {
        guard ClxAgentInstance.isAgent else { return }
        handlers[id] = handler
    }

    func unregister(id: String) {
        handlers[id] = nil
    }

    func invoke(id: String, active: Bool) -> Bool {
        guard let handler = handlers[id] else { return false }
        handler(active)
        return true
    }
}

/// Drop this as a `.background(...)` inside the sidebar's scroll content.
/// On attach it walks up the AppKit hierarchy to find the surrounding
/// `NSScrollView`, then bumps `SidebarScrollState.shared` from three
/// independent sources to cover trackpad live scroll, wheel/discrete
/// scroll, and any programmatic scroll path that mutates the clip view's
/// bounds.
struct SidebarScrollStateInstaller: NSViewRepresentable {
    func makeNSView(context: Context) -> SidebarScrollStateInstallerView {
        SidebarScrollStateInstallerView()
    }

    func updateNSView(_ nsView: SidebarScrollStateInstallerView, context: Context) {
        nsView.installIfNeeded()
    }
}

final class SidebarScrollStateInstallerView: NSView {
    private weak var observed: NSScrollView?
    private var startObs: NSObjectProtocol?
    private var liveObs: NSObjectProtocol?
    private var boundsObs: NSObjectProtocol?
    private var wheelMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Defer to next runloop so SwiftUI has time to wire the hosting
        // view into the scroll view's clip view before we walk superviews.
        DispatchQueue.main.async { [weak self] in
            self?.installIfNeeded()
        }
    }

    func installIfNeeded() {
        guard observed == nil else { return }
        var current: NSView? = self.superview
        while let view = current {
            if let scroll = view as? NSScrollView {
                attach(to: scroll)
                return
            }
            current = view.superview
        }
    }

    private func attach(to scrollView: NSScrollView) {
        observed = scrollView

        // Trackpad live scroll: posted at start and on every frame during
        // the gesture. Catches the gesture immediately (no first-frame
        // hover leak) and keeps stamping while inertia continues.
        startObs = NotificationCenter.default.addObserver(
            forName: NSScrollView.willStartLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { _ in
            SidebarScrollState.shared.bump()
        }
        liveObs = NotificationCenter.default.addObserver(
            forName: NSScrollView.didLiveScrollNotification,
            object: scrollView,
            queue: .main
        ) { _ in
            SidebarScrollState.shared.bump()
        }

        // Clip-view bounds change: fires for every scroll source (wheel,
        // animated, programmatic, key-driven) on every frame the bounds
        // actually move. The trackpad notifications above don't cover
        // wheel mice, so this is the catch-all.
        let clip = scrollView.contentView
        clip.postsBoundsChangedNotifications = true
        boundsObs = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clip,
            queue: .main
        ) { _ in
            SidebarScrollState.shared.bump()
        }

        // Local NSEvent monitor for `.scrollWheel`: fires *before* the
        // scroll view processes the event and *before* any bounds change
        // is posted, so the gate is engaged by the time SwiftUI dispatches
        // the synthetic hover events caused by content moving under the
        // cursor. Filter by window so wheel events outside our window
        // don't engage the sidebar's gate.
        wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak scrollView] event in
            if let win = scrollView?.window, event.window === win {
                SidebarScrollState.shared.bump()
            }
            return event
        }
    }

    deinit {
        if let o = startObs { NotificationCenter.default.removeObserver(o) }
        if let o = liveObs { NotificationCenter.default.removeObserver(o) }
        if let o = boundsObs { NotificationCenter.default.removeObserver(o) }
        if let m = wheelMonitor { NSEvent.removeMonitor(m) }
    }
}

extension View {
    /// `onHover` variant that coalesces hover writes while the sidebar is in
    /// a scroll cooldown window. The final hover state is applied shortly
    /// after scroll settles, so feedback returns without waiting for another
    /// physical mouse movement.
    func sidebarHover(_ action: @escaping (Bool) -> Void) -> some View {
        modifier(SidebarHoverModifier(probeId: nil, action: action))
    }

    func sidebarHover(id: String, _ action: @escaping (Bool) -> Void) -> some View {
        modifier(SidebarHoverModifier(probeId: id, action: action))
    }
}

private struct SidebarHoverModifier: ViewModifier {
    let probeId: String?
    let action: (Bool) -> Void
    @State private var pending: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard let probeId else { return }
                SidebarHoverLatencyProbe.shared.register(id: probeId) { entered in
                    handleHover(entered)
                }
            }
            .onDisappear {
                guard let probeId else { return }
                SidebarHoverLatencyProbe.shared.unregister(id: probeId)
            }
            .onHover(perform: handleHover)
    }

    private func handleHover(_ entered: Bool) {
        pending?.cancel()
        if SidebarScrollState.shared.isScrolling {
            let delay = SidebarScrollState.shared.remainingCooldown + 0.01
            pending = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                if !SidebarScrollState.shared.isScrolling {
                    action(entered)
                    recordProbe(entered)
                }
            }
        } else {
            action(entered)
            recordProbe(entered)
        }
    }

    private func recordProbe(_ entered: Bool) {
        guard let probeId else { return }
        SidebarHoverLatencyProbe.shared.record(id: probeId, active: entered)
    }
}
