import SwiftUI
import AppKit

// MARK: - Dynamic color core
//
// Light mode is implemented centrally: instead of threading a colour
// scheme through every view, each semantic token is backed by a dynamic
// `NSColor` provider. SwiftUI re-resolves an `NSColor(name:) { … }`
// against the current effective appearance for free — the same mechanism
// asset-catalog colours use — so flipping `NSApp.appearance` repaints the
// whole tree with the matching branch and no call site changes.
//
// The rule the codebase follows:
//   • A *fill / surface / text* colour → `Color.dynamic(light:dark:)`,
//     authored with both perceptual values (see `STYLE.md` §2.4).
//   • An *additive highlight* (hover/press/selection lift, hairline drawn
//     with `Color.white.opacity(x)` on dark) → `Color.overlay(x)`, which
//     lifts with white on dark and darkens with black on light.
//   • A *shadow / scrim* stays black on both modes — do not flip it.

extension Color {
    /// A colour that resolves to `light` under a light effective
    /// appearance and `dark` under a dark one. Backed by a dynamic
    /// `NSColor`, so every SwiftUI view using it re-resolves automatically
    /// when the app appearance flips.
    static func dynamic(light: Color, dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.aqua, .darkAqua]) {
            case .darkAqua: return NSColor(dark)
            default:        return NSColor(light)
            }
        })
    }

    /// A neutral additive highlight: white at `alpha` on dark surfaces,
    /// black at `alpha` on light surfaces. This is the light-mode-correct
    /// replacement for every `Color.white.opacity(x)` used as a hover,
    /// press, selection, divider, or hairline lift. The perceptual role
    /// (a soft lift away from the surface) is preserved across modes.
    static func overlay(_ alpha: Double) -> Color {
        .dynamic(light: .black.opacity(alpha), dark: .white.opacity(alpha))
    }

    /// The inverse of `overlay`: a darkening wash that uses black on dark
    /// and white on light. Use for the rare highlight that lowers rather
    /// than lifts (e.g. a recessed well on a light card).
    static func overlayInverse(_ alpha: Double) -> Color {
        .dynamic(light: .white.opacity(alpha), dark: .black.opacity(alpha))
    }
}

// MARK: - Appearance preference

/// The user-chosen interface appearance. Mirrors `AppLanguage`: persisted
/// in the app prefs suite and applied process-wide by setting
/// `NSApp.appearance`, which drives both AppKit chrome and SwiftUI's
/// `colorScheme` environment (so the dynamic tokens above re-resolve).
enum AppAppearance: String, CaseIterable, Identifiable {
    /// Follow the operating system's light/dark setting.
    case system
    /// Force the light palette.
    case light
    /// Force the dark palette (the project's default identity).
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return L10n.t("System")
        case .light:  return L10n.t("Light")
        case .dark:   return L10n.t("Dark")
        }
    }

    /// Concrete appearance to install, or `nil` to follow the OS.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }
}

extension AppAppearance {
    /// Persistence key (suite `appPrefsSuite`).
    static let storageKey = "PreferredAppearance"
    static let storage = UserDefaults(suiteName: appPrefsSuite) ?? .standard

    /// Read the saved appearance. Defaults to `.dark` so existing installs
    /// keep the established dark-first identity until the user opts into
    /// light or system.
    static func loadPersisted() -> AppAppearance {
        if let raw = storage.string(forKey: storageKey),
           let value = AppAppearance(rawValue: raw) {
            return value
        }
        return .dark
    }

    /// Apply an appearance process-wide and persist it. Setting
    /// `NSApp.appearance` repaints every window and re-resolves all the
    /// dynamic tokens; `nil` hands control back to the OS.
    @MainActor
    static func apply(_ appearance: AppAppearance) {
        storage.set(appearance.rawValue, forKey: storageKey)
        NSApp.appearance = appearance.nsAppearance
    }

    /// Install the persisted appearance. Called from
    /// `applicationDidFinishLaunching` in place of the old hardcoded
    /// `NSApp.appearance = NSAppearance(named: .darkAqua)`.
    @MainActor
    static func applyPersisted() {
        apply(loadPersisted())
    }
}
