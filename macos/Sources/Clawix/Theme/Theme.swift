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
//     with white at low alpha on dark) → `Color.overlay(x)`, which
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
    /// replacement for every additive white highlight used as a hover,
    /// press, selection, divider, or hairline lift. The perceptual role
    /// (a soft lift away from the surface) is preserved across modes.
    static func overlay(_ alpha: Double) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let base: NSColor = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .white : .black
            return base.withAlphaComponent(alpha)
        })
    }

    /// The inverse of `overlay`: a darkening wash that uses black on dark
    /// and white on light. Use for the rare highlight that lowers rather
    /// than lifts (e.g. a recessed well on a light card).
    static func overlayInverse(_ alpha: Double) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let base: NSColor = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .black : .white
            return base.withAlphaComponent(alpha)
        })
    }

    /// Grayscale token that keeps its canonical dark value and mirrors to a
    /// derived light value. Terse wrapper over `dynamic` for the very common
    /// `Color(white:)` migration: a `0.92` light-on-dark text value
    /// becomes `Color.gray(light: 0.16, dark: 0.92)` (dark text on light).
    /// Pass the existing value as `dark` so dark mode is byte-for-byte
    /// preserved, and the perceptually mirrored value as `light`.
    static func gray(light: Double, dark: Double) -> Color {
        .dynamic(light: Color(white: light), dark: Color(white: dark))
    }
}

extension NSColor {
    /// AppKit counterpart of `Color.gray`: a dynamic grayscale `NSColor`
    /// for the few call sites that hand a raw `NSColor` to AppKit
    /// (`NSTextView.textColor`, scroller thumbs drawn with `setFill()`).
    static func dynamicGray(light: CGFloat, dark: CGFloat, alpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            let w = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(white: w, alpha: alpha)
        }
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
