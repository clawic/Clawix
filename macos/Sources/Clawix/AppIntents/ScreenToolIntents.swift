import AppIntents
import AppKit
import Foundation

enum ScreenToolsIntentError: Error, CustomLocalizedStringResourceConvertible {
    case disabled

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .disabled:
            return "Screen Tools is currently unavailable in this Clawix build."
        }
    }
}

@MainActor
private func ensureScreenToolsEnabled() throws {
    guard FeatureFlags.shared.isVisible(.screenTools) else {
        throw ScreenToolsIntentError.disabled
    }
}

@available(macOS 13.0, *)
struct RestoreLastCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Restore last capture"
    static let description = IntentDescription(
        "Reopen the most recent local capture in a Quick Access overlay."
    )
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        try ensureScreenToolsEnabled()
        NSApp.activate(ignoringOtherApps: true)
        ScreenToolService.shared.restoreLastCapture()
        return .result()
    }
}

@available(macOS 13.0, *)
struct ShowLastCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Show last capture"
    static let description = IntentDescription(
        "Show the most recent local capture in a Quick Access overlay."
    )
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        try ensureScreenToolsEnabled()
        NSApp.activate(ignoringOtherApps: true)
        ScreenToolService.shared.showLastCaptureOverlay()
        return .result()
    }
}

@available(macOS 13.0, *)
struct PinLastCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Pin last capture"
    static let description = IntentDescription(
        "Pin the most recent local capture to the screen."
    )
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        try ensureScreenToolsEnabled()
        NSApp.activate(ignoringOtherApps: true)
        ScreenToolService.shared.pinLastCapture()
        return .result()
    }
}

@available(macOS 13.0, *)
struct CopyLastCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Copy last capture"
    static let description = IntentDescription(
        "Copy the most recent local capture to the clipboard."
    )
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        try ensureScreenToolsEnabled()
        NSApp.activate(ignoringOtherApps: true)
        ScreenToolService.shared.copyLastCapture()
        return .result()
    }
}

@available(macOS 13.0, *)
struct OpenLastCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Open last capture"
    static let description = IntentDescription(
        "Open the most recent local capture in its default app."
    )
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        try ensureScreenToolsEnabled()
        NSApp.activate(ignoringOtherApps: true)
        ScreenToolService.shared.openLastCapture()
        return .result()
    }
}

@available(macOS 13.0, *)
struct RevealLastCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Reveal last capture"
    static let description = IntentDescription(
        "Show the most recent local capture in Finder."
    )
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        try ensureScreenToolsEnabled()
        NSApp.activate(ignoringOtherApps: true)
        ScreenToolService.shared.revealLastCapture()
        return .result()
    }
}

@available(macOS 13.0, *)
struct RecognizeLastCaptureTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Recognize last capture text"
    static let description = IntentDescription(
        "Recognize text from the most recent local capture and copy it to the clipboard."
    )
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        try ensureScreenToolsEnabled()
        NSApp.activate(ignoringOtherApps: true)
        ScreenToolService.shared.recognizeLastCaptureText()
        return .result()
    }
}

@available(macOS 13.0, *)
struct RevealCaptureFolderIntent: AppIntent {
    static let title: LocalizedStringResource = "Reveal capture folder"
    static let description = IntentDescription(
        "Show the local Screen Tools export folder in Finder."
    )
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        try ensureScreenToolsEnabled()
        NSApp.activate(ignoringOtherApps: true)
        ScreenToolService.shared.revealCaptureFolder()
        return .result()
    }
}
