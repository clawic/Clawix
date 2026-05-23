import Foundation
import Observation

// Opt-in "Advanced mode" for power users. Everything here is additive
// and gated: with `enabled == false` the iPhone companion behaves
// exactly as it always has. Flipping it on layers extra affordances
// onto the existing chat surface (a slash-command palette in the
// composer, the ability to queue follow-up prompts while a turn is
// still running, and a running indicator on the chat list) without
// replacing any of the default UI.
//
// Persistence mirrors `IOSLegalSafetyStore`: an `@Observable` singleton
// whose properties write through to `UserDefaults` on `didSet`, so a
// SwiftUI view that reads `AdvancedSettings.shared.enabled` in its body
// re-renders the moment the toggle changes.
@Observable
final class AdvancedSettings {
    static let shared = AdvancedSettings()

    private let defaults: UserDefaults

    /// Master switch. When off, every sub-feature is treated as off no
    /// matter its individual flag, so callers only have to consult the
    /// `*Active` helpers below.
    var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Keys.enabled) }
    }

    /// Queue follow-up prompts while a turn is running; they flush one
    /// at a time as each turn finishes.
    var queuedDrafts: Bool {
        didSet { defaults.set(queuedDrafts, forKey: Keys.queuedDrafts) }
    }

    /// Slash-command palette above the composer (type `/`).
    var commandPalette: Bool {
        didSet { defaults.set(commandPalette, forKey: Keys.commandPalette) }
    }

    /// A discrete "running" cue on chat-list rows with an active turn.
    var runningBadge: Bool {
        didSet { defaults.set(runningBadge, forKey: Keys.runningBadge) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.enabled = defaults.bool(forKey: Keys.enabled)
        // Sub-features default to ON so enabling the master switch is a
        // single tap that lights everything up; the user can then trim
        // individual affordances back. `object(forKey:) ?? true` keeps
        // "never set" distinct from "explicitly turned off".
        self.queuedDrafts = defaults.object(forKey: Keys.queuedDrafts) as? Bool ?? true
        self.commandPalette = defaults.object(forKey: Keys.commandPalette) as? Bool ?? true
        self.runningBadge = defaults.object(forKey: Keys.runningBadge) as? Bool ?? true
    }

    /// `true` only when the master switch and the feature flag are both on.
    var queuedDraftsActive: Bool { enabled && queuedDrafts }
    var commandPaletteActive: Bool { enabled && commandPalette }
    var runningBadgeActive: Bool { enabled && runningBadge }

    private enum Keys {
        static let enabled = "clawix.advanced.enabled"
        static let queuedDrafts = "clawix.advanced.queuedDrafts"
        static let commandPalette = "clawix.advanced.commandPalette"
        static let runningBadge = "clawix.advanced.runningBadge"
    }
}
