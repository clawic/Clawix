import AppKit
import SwiftUI
import ClawixCore

struct ChatScrollDeclarativeAnchors: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content
                .defaultScrollAnchor(.top, for: .alignment)
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .defaultScrollAnchor(.bottom, for: .sizeChanges)
        } else {
            content
        }
    }
}

struct ChatScrollUpSentinel: ViewModifier {
    let threshold: CGFloat
    let isEnabled: Bool
    let onTrigger: () -> Void

    init(threshold: CGFloat, isEnabled: Bool = true, onTrigger: @escaping () -> Void) {
        self.threshold = threshold
        self.isEnabled = isEnabled
        self.onTrigger = onTrigger
    }

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.onScrollGeometryChange(for: ChatScrollTopGeometryState.self) { geom in
                let realOverflow = geom.contentSize.height
                    > geom.containerSize.height - geom.contentInsets.top - geom.contentInsets.bottom + 1
                return ChatScrollTopGeometryState(
                    isNearTop: isEnabled && geom.contentOffset.y < threshold && realOverflow,
                    offsetY: geom.contentOffset.y
                )
            } action: { oldState, newState in
                if isEnabled,
                   newState.isNearTop,
                   !oldState.isNearTop,
                   newState.offsetY < oldState.offsetY {
                    onTrigger()
                }
            }
        } else {
            content
        }
    }
}

private struct ChatScrollTopGeometryState: Equatable {
    let isNearTop: Bool
    let offsetY: CGFloat
}

/// Reports whether the reader has scrolled meaningfully away from the
/// bottom of an overflowing transcript, driving the scroll-to-bottom
/// button's visibility. macOS 15+ only (mirrors `ChatScrollUpSentinel`);
/// on macOS 14 the flag stays `false` and the button never shows, which
/// is acceptable degradation.
struct ChatScrollBottomSentinel: ViewModifier {
    /// Distance from the tail, in points, past which the button appears.
    let threshold: CGFloat
    @Binding var awayFromBottom: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.onScrollGeometryChange(for: ChatScrollBottomGeometryState.self) { geom in
                let visible = geom.containerSize.height
                    - geom.contentInsets.top - geom.contentInsets.bottom
                let realOverflow = geom.contentSize.height > visible + 1
                let distanceFromBottom = geom.contentSize.height
                    - (geom.contentOffset.y + visible)
                let probeBucket = realOverflow
                    ? Int(max(0, distanceFromBottom) / 320)
                    : 0
                return ChatScrollBottomGeometryState(
                    isAwayFromBottom: realOverflow && distanceFromBottom > threshold,
                    probeBucket: probeBucket
                )
            } action: { oldState, newState in
                if oldState.probeBucket != newState.probeBucket {
                    RenderProbe.tick("ChatScroll.position")
                }
                if awayFromBottom != newState.isAwayFromBottom {
                    awayFromBottom = newState.isAwayFromBottom
                }
            }
        } else {
            content
        }
    }
}

private struct ChatScrollBottomGeometryState: Equatable {
    let isAwayFromBottom: Bool
    let probeBucket: Int
}

struct ChatTopScrollTriggerInstaller: NSViewRepresentable {
    let controlId: String
    let isEnabled: Bool
    let onTrigger: () -> Void

    func makeNSView(context: Context) -> ChatTopScrollTriggerInstallerView {
        let view = ChatTopScrollTriggerInstallerView(controlId: controlId, isEnabled: isEnabled)
        view.onTrigger = onTrigger
        return view
    }

    func updateNSView(_ nsView: ChatTopScrollTriggerInstallerView, context: Context) {
        nsView.controlId = controlId
        nsView.isEnabled = isEnabled
        nsView.onTrigger = onTrigger
        nsView.installIfNeeded()
    }

    static func dismantleNSView(_ nsView: ChatTopScrollTriggerInstallerView, coordinator: ()) {
        nsView.detach()
    }
}

final class ChatTopScrollTriggerInstallerView: NSView {
    var controlId: String {
        didSet {
            if oldValue != controlId {
                unregisterBoundaryTrigger(id: oldValue)
                registerBoundaryTriggerIfNeeded()
            }
        }
    }
    var isEnabled: Bool {
        didSet {
            if isEnabled {
                registerBoundaryTriggerIfNeeded()
            } else {
                unregisterBoundaryTrigger(id: controlId)
            }
        }
    }
    var onTrigger: (() -> Void)?

    private weak var installedScrollView: NSScrollView?
    private var wheelMonitor: Any?
    private var lastTriggerTime: CFTimeInterval = 0
    private var topBoundaryTriggered = false

    init(controlId: String, isEnabled: Bool) {
        self.controlId = controlId
        self.isEnabled = isEnabled
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            self?.installIfNeeded()
        }
    }

    func installIfNeeded() {
        if installedScrollView != nil {
            registerBoundaryTriggerIfNeeded()
            return
        }
        var current: NSView? = self.superview
        while let view = current {
            if let scrollView = view as? NSScrollView {
                attach(to: scrollView)
                return
            }
            current = view.superview
        }
    }

    func detach() {
        unregisterBoundaryTrigger(id: controlId)
        if let wheelMonitor {
            NSEvent.removeMonitor(wheelMonitor)
            self.wheelMonitor = nil
        }
        installedScrollView = nil
    }

    private func attach(to scrollView: NSScrollView) {
        installedScrollView = scrollView
        registerBoundaryTriggerIfNeeded()
        if wheelMonitor == nil {
            wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handleWheel(event)
                return event
            }
        }
    }

    private func registerBoundaryTriggerIfNeeded() {
        guard isEnabled else { return }
        guard let installedScrollView else { return }
        ClxScrollBoundaryTriggerRegistry.shared.upsert(scrollView: installedScrollView, id: controlId) { [weak self] in
            self?.triggerIfAllowed(source: "boundary-registry")
        }
    }

    private func unregisterBoundaryTrigger(id: String) {
        guard let installedScrollView else { return }
        ClxScrollBoundaryTriggerRegistry.shared.remove(id: id, scrollView: installedScrollView)
    }

    private func handleWheel(_ event: NSEvent) {
        guard isEnabled,
              let scrollView = installedScrollView,
              event.window === scrollView.window,
              event.scrollingDeltaY > 0,
              isEventInsideScrollView(event, scrollView: scrollView)
        else { return }

        guard isNativeScrollAtTop(scrollView) else {
            topBoundaryTriggered = false
            return
        }
        guard !topBoundaryTriggered else { return }
        topBoundaryTriggered = true
        triggerIfAllowed(source: "wheel")
    }

    private func isEventInsideScrollView(_ event: NSEvent, scrollView: NSScrollView) -> Bool {
        let point = scrollView.convert(event.locationInWindow, from: nil)
        return scrollView.bounds.contains(point)
    }

    private func isNativeScrollAtTop(_ scrollView: NSScrollView) -> Bool {
        scrollView.layoutSubtreeIfNeeded()
        guard let documentView = scrollView.documentView else { return false }
        documentView.layoutSubtreeIfNeeded()
        let clipView = scrollView.contentView
        let originY = clipView.bounds.origin.y
        let maxY = max(0, documentView.bounds.height - clipView.bounds.height)
        return documentView.isFlipped
            ? originY <= ChatView.loadOlderThreshold
            : originY >= maxY - ChatView.loadOlderThreshold
    }

    private func triggerIfAllowed(source: String) {
        let now = CACurrentMediaTime()
        guard now - lastTriggerTime >= ChatView.localRevealThrottle else { return }
        lastTriggerTime = now
        RenderProbe.mark("ChatOlderTopBoundaryTrigger", fields: ["source": source])
        onTrigger?()
    }
}

struct WorkPillAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

struct BranchPillAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}
