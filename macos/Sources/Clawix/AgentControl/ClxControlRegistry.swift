import AppKit
import Foundation

/// Lightweight metadata sidecar for a programmatically controllable UI element.
/// The accessibility tree is the comprehensive, "real" source of truth for
/// driving the UI (see ClxControlHandlers); this registry only adds role/label
/// hints and an optional closure fallback for the cases where the accessibility
/// path is unavailable.
struct ClxControlDescriptor {
    let id: String
    let token: UUID
    let sequence: UInt64
    let role: String
    let label: String
    let activate: (() -> Void)?
    let setValue: ((String) -> Void)?
}

struct ClxControlObservedViewState {
    let id: String
    let frame: CGRect
    let visible: Bool
}

/// In-process registry of controls instrumented with `.clxControl`. Only ever
/// populated in agent instances; inert in normal user builds.
@MainActor
final class ClxControlRegistry {
    static let shared = ClxControlRegistry()

    private final class WeakObservedView {
        weak var value: NSView?
        let sequence: UInt64

        init(_ value: NSView, sequence: UInt64) {
            self.value = value
            self.sequence = sequence
        }
    }

    private var controls: [String: [UUID: ClxControlDescriptor]] = [:]
    private var observedViews: [String: [UUID: WeakObservedView]] = [:]
    private var nextSequence: UInt64 = 0
    private init() {}

    func upsert(
        id: String,
        token: UUID,
        role: String,
        label: String,
        activate: (() -> Void)?,
        setValue: ((String) -> Void)?
    ) {
        nextSequence += 1
        controls[id, default: [:]][token] = ClxControlDescriptor(
            id: id,
            token: token,
            sequence: nextSequence,
            role: role,
            label: label,
            activate: activate,
            setValue: setValue
        )
    }

    func upsertObservedView(id: String, token: UUID, view: NSView) {
        guard ClxAgentInstance.isAgent else { return }
        nextSequence += 1
        observedViews[id, default: [:]][token] = WeakObservedView(view, sequence: nextSequence)
    }

    func remove(id: String, token: UUID) {
        controls[id]?[token] = nil
        if controls[id]?.isEmpty == true {
            controls[id] = nil
        }
    }

    func all() -> [ClxControlDescriptor] {
        controls.values.compactMap { descriptors in
            descriptors.values.max { $0.sequence < $1.sequence }
        }
    }

    func get(_ id: String) -> ClxControlDescriptor? {
        controls[id]?.values.max { $0.sequence < $1.sequence }
    }

    func removeObservedView(id: String, token: UUID) {
        observedViews[id]?[token] = nil
        if observedViews[id]?.isEmpty == true {
            observedViews[id] = nil
        }
    }

    func observedViewState(_ id: String) -> ClxControlObservedViewState? {
        guard let entries = observedViews[id] else { return nil }
        let live = entries.compactMap { token, entry -> (UUID, WeakObservedView)? in
            entry.value == nil ? nil : (token, entry)
        }
        observedViews[id] = Dictionary(uniqueKeysWithValues: live)
        guard let entry = live.map(\.1).max(by: { $0.sequence < $1.sequence }),
              let view = entry.value,
              let window = view.window
        else { return nil }
        let windowFrame = view.convert(view.bounds, to: nil)
        let screenFrame = window.convertToScreen(windowFrame)
        let visibleBounds = view.visibleRect.intersection(view.bounds)
        let visible = screenFrame.width > 0
            && screenFrame.height > 0
            && !visibleBounds.isEmpty
            && !visibleBounds.isNull
            && screenFrame.intersects(window.frame)
            && view.isEffectivelyVisible
        return ClxControlObservedViewState(id: id, frame: screenFrame, visible: visible)
    }
}

private extension NSView {
    var isEffectivelyVisible: Bool {
        if isHidden || alphaValue <= 0 { return false }
        var parent = superview
        while let view = parent {
            if view.isHidden || view.alphaValue <= 0 { return false }
            parent = view.superview
        }
        return window?.isVisible == true
    }
}

@MainActor
final class ClxScrollRegistry {
    static let shared = ClxScrollRegistry()

    private final class WeakScrollView {
        weak var value: NSScrollView?
        init(_ value: NSScrollView) {
            self.value = value
        }
    }

    private var scrollViews: [String: WeakScrollView] = [:]

    private init() {}

    func upsert(_ scrollView: NSScrollView, id: String) {
        guard ClxAgentInstance.isAgent else { return }
        scrollViews[id] = WeakScrollView(scrollView)
    }

    func remove(id: String, scrollView: NSScrollView) {
        guard ClxAgentInstance.isAgent else { return }
        if scrollViews[id]?.value === scrollView {
            scrollViews.removeValue(forKey: id)
        }
    }

    func get(_ id: String) -> NSScrollView? {
        guard let scrollView = scrollViews[id]?.value else {
            scrollViews.removeValue(forKey: id)
            return nil
        }
        return scrollView
    }

    func allIds() -> [String] {
        scrollViews = scrollViews.filter { $0.value.value != nil }
        return Array(scrollViews.keys).sorted()
    }
}

@MainActor
final class ClxScrollBoundaryTriggerRegistry {
    static let shared = ClxScrollBoundaryTriggerRegistry()

    private struct Entry {
        weak var scrollView: NSScrollView?
        let triggerTop: () -> Void
    }

    private var entries: [String: Entry] = [:]

    private init() {}

    func upsert(scrollView: NSScrollView, id: String, triggerTop: @escaping () -> Void) {
        guard ClxAgentInstance.isAgent else { return }
        entries[id] = Entry(scrollView: scrollView, triggerTop: triggerTop)
    }

    func remove(id: String, scrollView: NSScrollView) {
        guard ClxAgentInstance.isAgent else { return }
        if entries[id]?.scrollView === scrollView {
            entries.removeValue(forKey: id)
        }
    }

    func triggerTopIfAvailable(id: String) -> Bool {
        guard let entry = entries[id] else { return false }
        guard entry.scrollView != nil else {
            entries.removeValue(forKey: id)
            return false
        }
        entry.triggerTop()
        return true
    }
}
