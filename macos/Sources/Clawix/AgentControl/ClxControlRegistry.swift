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

/// In-process registry of controls instrumented with `.clxControl`. Only ever
/// populated in agent instances; inert in normal user builds.
@MainActor
final class ClxControlRegistry {
    static let shared = ClxControlRegistry()
    private var controls: [String: [UUID: ClxControlDescriptor]] = [:]
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
