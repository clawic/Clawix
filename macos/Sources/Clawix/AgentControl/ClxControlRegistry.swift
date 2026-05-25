import AppKit
import Foundation

/// Lightweight metadata sidecar for a programmatically controllable UI element.
/// The accessibility tree is the comprehensive, "real" source of truth for
/// driving the UI (see ClxControlHandlers); this registry only adds role/label
/// hints and an optional closure fallback for the cases where the accessibility
/// path is unavailable.
struct ClxControlDescriptor {
    let id: String
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
    private var controls: [String: ClxControlDescriptor] = [:]
    private init() {}

    func upsert(_ descriptor: ClxControlDescriptor) { controls[descriptor.id] = descriptor }
    func remove(id: String) { controls[id] = nil }
    func all() -> [ClxControlDescriptor] { Array(controls.values) }
    func get(_ id: String) -> ClxControlDescriptor? { controls[id] }
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
