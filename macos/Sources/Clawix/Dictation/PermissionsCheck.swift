import Foundation

/// Lightweight wrapper around the three TCC permissions the dictation
/// flow needs:
///
/// - **Microphone** — capturing audio from the input device.
/// - **Input Monitoring** — required by `NSEvent.addGlobalMonitorForEvents`
///   when the hotkey listener watches modifier keys system-wide. Without
///   it, calling `addGlobalMonitorForEvents(matching: .flagsChanged)` on
///   macOS 26 (Tahoe) freezes event delivery to the app until the TCC
///   flow resolves — the "frozen-input bug" we hit when registering the
///   monitor eagerly from `App.init()` without first checking the grant.
/// - **Accessibility** — required by `TextInjector` to post the
///   synthetic Cmd+V that pastes the transcribed text into the
///   foreground app once recording stops.
///
/// The check helpers never throw and never block — they read the TCC
/// state and return it. The "open" helpers send the user to the right
/// pane in System Settings; macOS Sequoia's URL scheme is
/// stable enough to use directly.
@MainActor
enum DictationPermissions {

    typealias Status = NativeMacPermissionBroker.Status

    // MARK: - Microphone

    static func microphone() -> Status {
        NativeMacPermissionBroker.status(for: .microphone)
    }

    static func requestMicrophone() async -> Bool {
        await NativeMacPermissionBroker.request(.microphone)
    }

    static func openMicrophoneSettings() {
        NativeMacPermissionBroker.openSettings(for: .microphone)
    }

    // MARK: - Accessibility (AXUIElement)

    /// macOS only reports trusted/untrusted for Accessibility; there is no
    /// system-level "not determined" bit. To still distinguish a fresh
    /// install (where the right CTA is "Request Access") from an
    /// explicit denial (where only "Open Settings" makes sense), we
    /// remember whether the OS prompt has ever been triggered for this
    /// process and treat the pre-prompt state as `.notDetermined`.
    nonisolated static let hasRequestedAccessibilityKey = NativeMacPermissionBroker.accessibilityRequestedKey

    static func accessibility() -> Status {
        NativeMacPermissionBroker.status(for: .accessibility)
    }

    /// Triggers the standard accessibility prompt. The OS dialog is
    /// non-blocking; the actual grant is reflected on the next call to
    /// `accessibility()` once the user toggles the switch in System
    /// Settings. Marks the permission as "asked" so subsequent calls
    /// fall into the `.denied` bucket and the UI surfaces "Open
    /// Settings" instead of asking again (the prompt is one-shot).
    @discardableResult
    static func requestAccessibility() -> Bool {
        NativeMacPermissionBroker.requestAccessibility()
    }

    static func openAccessibilitySettings() {
        NativeMacPermissionBroker.openSettings(for: .accessibility)
    }

    // MARK: - Input Monitoring

    /// IOKit reports a tri-state directly, so unlike `accessibility()`
    /// we don't need to remember whether a prompt has been shown.
    static func inputMonitoring() -> Status {
        NativeMacPermissionBroker.status(for: .inputMonitoring)
    }

    /// Triggers the system "would like to monitor your keyboard" prompt.
    /// The grant takes effect immediately on the next call but does not
    /// re-arm previously-installed monitors — call `register()` again
    /// afterwards.
    @discardableResult
    static func requestInputMonitoring() -> Bool {
        NativeMacPermissionBroker.requestInputMonitoring()
    }

    static func openInputMonitoringSettings() {
        NativeMacPermissionBroker.openSettings(for: .inputMonitoring)
    }
}
