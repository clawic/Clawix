import SwiftUI
import AppKit
import Combine

// MARK: - Companion overlay
//
// Hosts `PetView` in a small, frameless, always-on-top, draggable panel that
// floats over the desktop across Spaces. Toggled via the `/pet` command; its
// open state and last position persist across launches.

@MainActor
final class PetController: ObservableObject {
    static let shared = PetController()

    @Published private(set) var isOpen = false

    private var panel: NSPanel?
    private let openKey = "clawix.pet.open"
    private let frameKey = "clawix.pet.frame"

    private init() {}

    /// Re-open on launch if it was open last time. Call once at startup.
    func restoreIfNeeded() {
        if UserDefaults.standard.bool(forKey: openKey) { show() }
    }

    func toggle() { isOpen ? tuck() : show() }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.orderFrontRegardless()
        isOpen = true
        UserDefaults.standard.set(true, forKey: openKey)
    }

    func tuck() {
        persistFrame()
        panel?.orderOut(nil)
        isOpen = false
        UserDefaults.standard.set(false, forKey: openKey)
    }

    private func makePanel() -> NSPanel {
        let hosting = NSHostingView(rootView: PetView(onTuck: { [weak self] in self?.tuck() }))
        hosting.layer?.backgroundColor = .clear

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = hosting

        if let saved = savedFrameOrigin() {
            panel.setFrameOrigin(saved)
        } else if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameTopLeftPoint(NSPoint(x: visible.maxX - 150, y: visible.maxY - 40))
        }
        return panel
    }

    private func persistFrame() {
        guard let origin = panel?.frame.origin else { return }
        UserDefaults.standard.set(["x": origin.x, "y": origin.y], forKey: frameKey)
    }

    private func savedFrameOrigin() -> NSPoint? {
        guard let dict = UserDefaults.standard.dictionary(forKey: frameKey) as? [String: Double],
              let x = dict["x"], let y = dict["y"] else { return nil }
        return NSPoint(x: x, y: y)
    }
}
