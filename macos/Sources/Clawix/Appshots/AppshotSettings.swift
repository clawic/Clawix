import Foundation
import AppKit

// MARK: - Appshot hotkey

/// Double-modifier gesture that captures the frontmost window. The user
/// presses *both* physical keys of one modifier at once (e.g. both ⌘
/// keys), which never collides with normal single-modifier shortcuts.
/// `none` disables the keyboard trigger entirely (the "+" menu path
/// still works). Default is `commandCommand`.
enum AppshotHotkey: String, CaseIterable, Identifiable {
    case commandCommand
    case optionOption
    case shiftShift
    case none

    var id: String { rawValue }

    /// Trigger label shown in the Settings dropdown.
    var label: String {
        switch self {
        case .commandCommand: return "⌘ + ⌘"
        case .optionOption:   return "⌥ + ⌥"
        case .shiftShift:     return "⇧ + ⇧"
        case .none:           return String(localized: "None", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
    }

    /// Secondary line under each dropdown option explaining the gesture.
    var optionDescription: String {
        switch self {
        case .commandCommand: return String(localized: "Press both ⌘ keys simultaneously", bundle: AppLocale.bundle, locale: AppLocale.current)
        case .optionOption:   return String(localized: "Press both ⌥ keys simultaneously", bundle: AppLocale.bundle, locale: AppLocale.current)
        case .shiftShift:     return String(localized: "Press both ⇧ keys simultaneously", bundle: AppLocale.bundle, locale: AppLocale.current)
        case .none:           return String(localized: "No keyboard shortcut", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
    }

    /// Device-independent modifier flag the gesture rides on, or `nil`
    /// when the keyboard trigger is off.
    var deviceIndependentMask: NSEvent.ModifierFlags? {
        switch self {
        case .commandCommand: return .command
        case .optionOption:   return .option
        case .shiftShift:     return .shift
        case .none:           return nil
        }
    }

    /// Device-dependent bit set when the *left* physical key is down.
    /// Constants from `CGEventTypes.h` (`NX_DEVICEL*KEYMASK`).
    var leftBit: UInt? {
        switch self {
        case .commandCommand: return 0x000008
        case .optionOption:   return 0x000020
        case .shiftShift:     return 0x000002
        case .none:           return nil
        }
    }

    /// Device-dependent bit set when the *right* physical key is down
    /// (`NX_DEVICER*KEYMASK`). "Both keys down" means left ⋀ right ⋀ the
    /// device-independent flag.
    var rightBit: UInt? {
        switch self {
        case .commandCommand: return 0x000010
        case .optionOption:   return 0x000040
        case .shiftShift:     return 0x000004
        case .none:           return nil
        }
    }
}

// MARK: - Appshot preferences

/// One source of truth for the appshot on/off flag and the chosen
/// hotkey. Both the Settings page (`@AppStorage`) and the non-View code
/// (capture flow, hotkey monitor) read these through `UserDefaults.standard`
/// so they never drift.
enum AppshotSettings {
    static let enabledKey = "appshots.enabled"
    static let hotkeyKey = "appshots.hotkey"

    private static var defaults: UserDefaults { .standard }

    /// Appshots are opt-in: the first "Attach <app>" surfaces an enable
    /// modal, and the keyboard trigger stays dormant until the user
    /// turns this on.
    static var isEnabled: Bool {
        get { defaults.bool(forKey: enabledKey) }
        set { defaults.set(newValue, forKey: enabledKey) }
    }

    static var hotkey: AppshotHotkey {
        get {
            guard let raw = defaults.string(forKey: hotkeyKey),
                  let value = AppshotHotkey(rawValue: raw) else { return .commandCommand }
            return value
        }
        set { defaults.set(newValue.rawValue, forKey: hotkeyKey) }
    }
}
