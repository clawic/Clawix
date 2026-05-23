import AppKit

/// Watches `flagsChanged` events for the appshot double-modifier gesture
/// (both ⌘, both ⌥, or both ⇧ pressed at once) and triggers a capture of
/// the frontmost window. The gesture usually fires while another app is
/// frontmost, so the global monitor needs Input Monitoring; without that
/// grant the global callback is a silent no-op (the local monitor still
/// works when Clawix itself is in front, e.g. capturing a previous app).
///
/// Monitors are installed only when appshots are enabled AND a non-`none`
/// hotkey is chosen, mirroring the dictation monitor's opt-in policy so a
/// fresh install never touches `addGlobalMonitorForEvents`.
@MainActor
final class AppshotHotkeyMonitor {
    static let shared = AppshotHotkeyMonitor()

    private weak var appState: AppState?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    /// Edge state: only fire on the transition into "both keys down" so a
    /// single sustained press triggers exactly one capture.
    private var bothDown = false

    private init() {}

    /// Hand the monitor the live AppState so it can stage the capture into
    /// the composer. Called once from `App.init`.
    func attach(appState: AppState) {
        self.appState = appState
    }

    /// Install or remove the monitors to match the current settings.
    /// Idempotent — safe to call on launch and on every settings change.
    func refreshRegistration() {
        let active = AppshotSettings.isEnabled && AppshotSettings.hotkey != .none
        if active {
            install()
        } else {
            uninstall()
        }
    }

    private func install() {
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                Task { @MainActor in self?.handle(event) }
                return event
            }
        }
        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                Task { @MainActor in self?.handle(event) }
            }
        }
    }

    private func uninstall() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        bothDown = false
    }

    private func handle(_ event: NSEvent) {
        let hotkey = AppshotSettings.hotkey
        guard AppshotSettings.isEnabled,
              let parentMask = hotkey.deviceIndependentMask,
              let leftBit = hotkey.leftBit,
              let rightBit = hotkey.rightBit else {
            bothDown = false
            return
        }

        let raw = event.modifierFlags.rawValue
        let nowBoth = event.modifierFlags.contains(parentMask)
            && (raw & leftBit != 0)
            && (raw & rightBit != 0)

        if nowBoth {
            if !bothDown {
                bothDown = true
                appState?.captureAppshotFromHotkey()
            }
        } else {
            bothDown = false
        }
    }
}
