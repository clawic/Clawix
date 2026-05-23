import Foundation

// Per-chat persistence for the unsent composer text (advanced mode).
// Keyed by chat id so a half-written prompt survives navigating away,
// opening another chat, or relaunching the app. Text only: attachments
// stay in-memory because their image bytes are not worth persisting for
// a draft. Saving an empty/whitespace string clears the entry, so the
// store never accumulates stale keys after a send.
enum ComposerDraftStore {
    private static let prefix = "clawix.advanced.draft."
    private static var defaults: UserDefaults { .standard }

    static func load(chatId: String) -> String {
        defaults.string(forKey: prefix + chatId) ?? ""
    }

    static func save(_ text: String, chatId: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clear(chatId: chatId)
        } else {
            defaults.set(text, forKey: prefix + chatId)
        }
    }

    static func clear(chatId: String) {
        defaults.removeObject(forKey: prefix + chatId)
    }
}
