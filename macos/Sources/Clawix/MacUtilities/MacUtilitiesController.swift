import Combine
import Foundation

enum MacUtilityGroup: String, CaseIterable, Identifiable {
    case windows
    case system
    case toggles
    case tools
    case apps
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .windows:  return "Windows"
        case .system:   return "System"
        case .toggles:  return "Toggles"
        case .tools:    return "Tools"
        case .apps:     return "Apps"
        case .settings: return "System Settings"
        }
    }
}

enum MacUtilityActionID: String, CaseIterable, Identifiable {
    case hideAllWindows
    case minimizeAllWindows
    case minimizeAllWindowsExceptFrontmost
    case minimizeAppWindowsExceptFrontmost
    case isolateWindow
    case unminimizeAllWindows
    case showDesktop
    case clearClipboard
    case sleepDisplays
    case centerMousePointer
    case showColorPicker
    case toggleDarkMode
    case toggleMuteSound
    case toggleKeepAwake
    case toggleDesktopIcons
    case openFinder
    case openTerminal
    case openShortcuts
    case openPasswords
    case openAirDrop
    case openVPNSettings
    case openPrivateRelaySettings
    case openHideMyEmailSettings
    case openKeyboardSettings
    case openDisplaySettings
    case openDesktopDockSettings
    case openNotificationsSettings
    case openSoundSettings
    case openPrivacySettings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hideAllWindows: return "Hide All Windows"
        case .minimizeAllWindows: return "Minimize All Windows"
        case .minimizeAllWindowsExceptFrontmost: return "Minimize All Windows Except Frontmost"
        case .minimizeAppWindowsExceptFrontmost: return "Minimize App Windows Except Frontmost"
        case .isolateWindow: return "Isolate Window"
        case .unminimizeAllWindows: return "Unminimize All Windows"
        case .showDesktop: return "Show Desktop"
        case .clearClipboard: return "Clear Clipboard"
        case .sleepDisplays: return "Sleep Displays"
        case .centerMousePointer: return "Center Mouse Pointer"
        case .showColorPicker: return "Pick Color"
        case .toggleDarkMode: return "Dark Mode"
        case .toggleMuteSound: return "Mute Sound"
        case .toggleKeepAwake: return "Keep Awake"
        case .toggleDesktopIcons: return "Desktop Icons"
        case .openFinder: return "Finder"
        case .openTerminal: return "Terminal"
        case .openShortcuts: return "Shortcuts"
        case .openPasswords: return "Passwords"
        case .openAirDrop: return "AirDrop"
        case .openVPNSettings: return "VPN & Filters"
        case .openPrivateRelaySettings: return "Private Relay"
        case .openHideMyEmailSettings: return "Hide My Email"
        case .openKeyboardSettings: return "Keyboard"
        case .openDisplaySettings: return "Displays"
        case .openDesktopDockSettings: return "Desktop & Dock"
        case .openNotificationsSettings: return "Notifications"
        case .openSoundSettings: return "Sound"
        case .openPrivacySettings: return "Privacy & Security"
        }
    }

    var detail: String {
        switch self {
        case .hideAllWindows: return "Hide visible app windows without quitting apps."
        case .minimizeAllWindows: return "Minimize all visible windows in the current space."
        case .minimizeAllWindowsExceptFrontmost: return "Keep the active window visible and minimize the rest."
        case .minimizeAppWindowsExceptFrontmost: return "Minimize the other windows of the active app."
        case .isolateWindow: return "Hide other apps and minimize the active app's other windows."
        case .unminimizeAllWindows: return "Restore minimized windows across visible apps."
        case .showDesktop: return "Use the system Show Desktop shortcut."
        case .clearClipboard: return "Remove all current pasteboard contents."
        case .sleepDisplays: return "Put connected displays to sleep immediately."
        case .centerMousePointer: return "Move the pointer to the center of the main display."
        case .showColorPicker: return "Open the system color picker."
        case .toggleDarkMode: return "Switch the system appearance between light and dark."
        case .toggleMuteSound: return "Toggle the default output mute state."
        case .toggleKeepAwake: return "Prevent idle sleep until disabled or Clawix quits."
        case .toggleDesktopIcons: return "Show or hide Finder desktop items."
        case .openFinder: return "Open or focus Finder."
        case .openTerminal: return "Open or focus Terminal."
        case .openShortcuts: return "Open or focus Shortcuts."
        case .openPasswords: return "Open or focus Passwords."
        case .openAirDrop: return "Open AirDrop in Finder."
        case .openVPNSettings: return "Open Network settings."
        case .openPrivateRelaySettings: return "Open iCloud Private Relay settings."
        case .openHideMyEmailSettings: return "Open iCloud Hide My Email settings."
        case .openKeyboardSettings: return "Open Keyboard settings."
        case .openDisplaySettings: return "Open Displays settings."
        case .openDesktopDockSettings: return "Open Desktop & Dock settings."
        case .openNotificationsSettings: return "Open Notifications settings."
        case .openSoundSettings: return "Open Sound settings."
        case .openPrivacySettings: return "Open Privacy & Security settings."
        }
    }

    var requiresConfirmation: Bool {
        switch self {
        case .clearClipboard:
            return true
        default:
            return false
        }
    }

    var group: MacUtilityGroup {
        switch self {
        case .hideAllWindows,
             .minimizeAllWindows,
             .minimizeAllWindowsExceptFrontmost,
             .minimizeAppWindowsExceptFrontmost,
             .isolateWindow,
             .unminimizeAllWindows,
             .showDesktop:
            return .windows
        case .clearClipboard, .sleepDisplays:
            return .system
        case .centerMousePointer, .showColorPicker:
            return .tools
        case .toggleDarkMode, .toggleMuteSound, .toggleKeepAwake, .toggleDesktopIcons:
            return .toggles
        case .openFinder, .openTerminal, .openShortcuts, .openPasswords, .openAirDrop:
            return .apps
        case .openVPNSettings,
             .openPrivateRelaySettings,
             .openHideMyEmailSettings,
             .openKeyboardSettings,
             .openDisplaySettings,
             .openDesktopDockSettings,
             .openNotificationsSettings,
             .openSoundSettings,
             .openPrivacySettings:
            return .settings
        }
    }

    var systemImage: String {
        switch self {
        case .hideAllWindows: return "eye.slash"
        case .minimizeAllWindows: return "minus.square"
        case .minimizeAllWindowsExceptFrontmost: return "rectangle.on.rectangle.slash"
        case .minimizeAppWindowsExceptFrontmost: return "rectangle.stack"
        case .isolateWindow: return "scope"
        case .unminimizeAllWindows: return "plus.square.on.square"
        case .showDesktop: return "desktopcomputer"
        case .clearClipboard: return "clipboard"
        case .sleepDisplays: return "display"
        case .centerMousePointer: return "cursorarrow.motionlines"
        case .showColorPicker: return "eyedropper"
        case .toggleDarkMode: return "moon"
        case .toggleMuteSound: return "speaker.slash"
        case .toggleKeepAwake: return "cup.and.saucer"
        case .toggleDesktopIcons: return "square.grid.3x3"
        case .openFinder: return "face.smiling"
        case .openTerminal: return "terminal"
        case .openShortcuts: return "sparkles"
        case .openPasswords: return "key"
        case .openAirDrop: return "antenna.radiowaves.left.and.right"
        case .openVPNSettings: return "network"
        case .openPrivateRelaySettings: return "icloud"
        case .openHideMyEmailSettings: return "envelope.badge.shield.half.filled"
        case .openKeyboardSettings: return "keyboard"
        case .openDisplaySettings: return "display"
        case .openDesktopDockSettings: return "dock.rectangle"
        case .openNotificationsSettings: return "bell"
        case .openSoundSettings: return "speaker.wave.2"
        case .openPrivacySettings: return "hand.raised"
        }
    }

    static func actions(in group: MacUtilityGroup) -> [MacUtilityActionID] {
        allCases.filter { $0.group == group }
    }
}

@MainActor
final class MacUtilitiesController: ObservableObject {
    static let shared = MacUtilitiesController()

    @Published private(set) var keepAwakeEnabled = false
    @Published private(set) var activeAction: MacUtilityActionID?
    @Published private(set) var lastStatusMessage: String?
    @Published private(set) var lastStatusIsError = false

    private let runner: NativeMacActionCommandRunning
    private let auditURL: URL?

    init(
        runner: NativeMacActionCommandRunning = NativeMacActionProcessRunner(),
        auditURL: URL? = nil
    ) {
        self.runner = runner
        self.auditURL = auditURL
    }

    func perform(_ action: MacUtilityActionID) {
        guard activeAction == nil else { return }
        activeAction = action
        lastStatusMessage = nil
        defer { activeAction = nil }

        guard FeatureFlags.shared.isVisible(.macUtilities) else {
            publishStatus("Mac Utilities are disabled by feature flags.", isError: true)
            return
        }
        let authorization = HostActionPolicy.authorize(
            surface: .macUtilities,
            action: action.id,
            origin: .userInterface
        )
        guard authorization.allowed else {
            let message = authorization.reason ?? "Action blocked by host policy"
            publishStatus(message, isError: true)
            ToastCenter.shared.show(message, icon: .warning)
            return
        }
        do {
            try executeBrokeredAction(action)
            if action == .toggleKeepAwake {
                keepAwakeEnabled.toggle()
            }
            publishStatus("\(action.title) done", isError: false)
            ToastCenter.shared.show("\(action.title) done")
        } catch {
            publishStatus(error.localizedDescription, isError: true)
            ToastCenter.shared.show(error.localizedDescription, icon: .error)
        }
    }

    private func publishStatus(_ message: String, isError: Bool) {
        lastStatusMessage = message
        lastStatusIsError = isError
    }

    private func executeBrokeredAction(_ action: MacUtilityActionID) throws {
        let receipt = NativeMacActionBroker.evaluate(
            NativeMacActionRequest(
                capabilityId: action.brokerCapabilityId(keepAwakeEnabled: keepAwakeEnabled),
                actorId: "clawix.mac-utilities",
                origin: .userUI,
                actorKind: "user_ui"
            ),
            auditURL: auditURL,
            runner: runner
        )
        guard receipt.outcome == .executed else {
            throw MacUtilityError.message(receipt.error ?? "Mac Utility action did not execute.")
        }
    }
}

private enum MacUtilityError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

private extension MacUtilityActionID {
    func brokerCapabilityId(keepAwakeEnabled: Bool) -> String {
        switch self {
        case .hideAllWindows: return "mac.utility.hide_all_windows"
        case .minimizeAllWindows: return "mac.utility.minimize_all_windows"
        case .minimizeAllWindowsExceptFrontmost: return "mac.utility.minimize_all_windows_except_frontmost"
        case .minimizeAppWindowsExceptFrontmost: return "mac.utility.minimize_app_windows_except_frontmost"
        case .isolateWindow: return "mac.utility.isolate_window"
        case .unminimizeAllWindows: return "mac.utility.unminimize_all_windows"
        case .showDesktop: return "mac.utility.show_desktop"
        case .clearClipboard: return "mac.utility.clear_clipboard"
        case .sleepDisplays: return "mac.utility.sleep_displays"
        case .centerMousePointer: return "mac.utility.center_mouse_pointer"
        case .showColorPicker: return "mac.utility.show_color_picker"
        case .toggleDarkMode: return "mac.utility.toggle_dark_mode"
        case .toggleMuteSound: return "mac.utility.toggle_mute_sound"
        case .toggleKeepAwake: return keepAwakeEnabled ? "mac.utility.keep_awake_off" : "mac.utility.keep_awake_on"
        case .toggleDesktopIcons: return "mac.utility.toggle_desktop_icons"
        case .openFinder: return "mac.utility.open_finder"
        case .openTerminal: return "mac.utility.open_terminal"
        case .openShortcuts: return "mac.utility.open_shortcuts"
        case .openPasswords: return "mac.utility.open_passwords"
        case .openAirDrop: return "mac.utility.open_airdrop"
        case .openVPNSettings: return "mac.utility.open_vpn_settings"
        case .openPrivateRelaySettings: return "mac.utility.open_private_relay_settings"
        case .openHideMyEmailSettings: return "mac.utility.open_hide_my_email_settings"
        case .openKeyboardSettings: return "mac.utility.open_keyboard_settings"
        case .openDisplaySettings: return "mac.utility.open_display_settings"
        case .openDesktopDockSettings: return "mac.utility.open_desktop_dock_settings"
        case .openNotificationsSettings: return "mac.utility.open_notifications_settings"
        case .openSoundSettings: return "mac.utility.open_sound_settings"
        case .openPrivacySettings: return "mac.utility.open_privacy_settings"
        }
    }
}
