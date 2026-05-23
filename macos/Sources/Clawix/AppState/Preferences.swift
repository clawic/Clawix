import SwiftUI
import Combine
import AppKit
import ClawixCore
import ClawixEngine

enum IntelligenceLevel: String, CaseIterable, Identifiable {
    case low, medium, high, extra
    var id: String { rawValue }
    var label: String {
        switch self {
        case .low:    return String(localized: "Low", bundle: AppLocale.bundle, locale: AppLocale.current)
        case .medium: return String(localized: "Medium", bundle: AppLocale.bundle, locale: AppLocale.current)
        case .high:   return String(localized: "High", bundle: AppLocale.bundle, locale: AppLocale.current)
        case .extra:  return String(localized: "Extra high", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
    }

    var clawixEffort: String {
        switch self {
        case .low:    return "low"
        case .medium: return "medium"
        case .high:   return "high"
        case .extra:  return "xhigh"
        }
    }
}

enum SpeedLevel: String, CaseIterable, Identifiable {
    case standard, fast
    var id: String { rawValue }
    var label: String {
        switch self {
        case .standard: return String(localized: "Standard", bundle: AppLocale.bundle, locale: AppLocale.current)
        case .fast:     return String(localized: "Fast", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
    }
    var description: String {
        switch self {
        case .standard: return String(localized: "Default speed, normal usage", bundle: AppLocale.bundle, locale: AppLocale.current)
        case .fast:     return String(localized: "1.5x faster speed, higher usage", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
    }
}

enum PermissionMode: String, CaseIterable, Identifiable {
    case defaultPermissions, autoReview, fullAccess
    var id: String { rawValue }

    var label: String {
        switch self {
        case .defaultPermissions: return String(localized: "Default permissions", bundle: AppLocale.bundle, locale: AppLocale.current)
        case .autoReview:         return String(localized: "Automatic review", bundle: AppLocale.bundle, locale: AppLocale.current)
        case .fullAccess:         return String(localized: "Full access", bundle: AppLocale.bundle, locale: AppLocale.current)
        }
    }

    var iconName: String {
        switch self {
        case .defaultPermissions: return "hand.raised"
        case .autoReview:         return "checkmark.shield"
        case .fullAccess:         return "exclamationmark.octagon"
        }
    }

    var accent: Color {
        switch self {
        // The three modes are told apart by icon + label + neutral weight,
        // not by brand colour: default is a dim neutral, the non-default
        // automatic-review is a brighter neutral (the "active" lift), and
        // only the risky full-access keeps a colour (warning orange). This
        // keeps the composer chrome neutral-except-risk instead of spending
        // brand blue on a mode label.
        case .defaultPermissions: return Color.gray(light: 0.27, dark: 0.78)
        case .autoReview:         return Color.gray(light: 0.16, dark: 0.92)
        case .fullAccess:         return Color(red: 0.95, green: 0.50, blue: 0.20)
        }
    }

    /// Maps to the Codex daemon `approval_policy` accepted by
    /// `thread/start`. Default permissions surfaces approval requests
    /// for actions the sandbox can't authorise on its own; the other
    /// two never prompt.
    var codexApprovalPolicy: String {
        switch self {
        case .defaultPermissions: return "on-request"
        case .autoReview:         return "never"
        case .fullAccess:         return "never"
        }
    }

    /// Maps to the Codex daemon `sandbox_mode` accepted by
    /// `thread/start`. Workspace-write keeps Codex inside the project
    /// cwd; danger-full-access drops the sandbox entirely.
    var codexSandbox: String {
        switch self {
        case .defaultPermissions: return "workspace-write"
        case .autoReview:         return "workspace-write"
        case .fullAccess:         return "danger-full-access"
        }
    }

    static let userDefaultsKey = "ClawixPermissionMode"

    static func loadPersisted() -> PermissionMode {
        let defaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard
        if let raw = defaults.string(forKey: userDefaultsKey),
           let mode = PermissionMode(rawValue: raw) {
            return mode
        }
        return .defaultPermissions
    }

    func persist() {
        let defaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard
        defaults.set(rawValue, forKey: PermissionMode.userDefaultsKey)
    }
}

enum AgentRuntimeChoice: String, CaseIterable, Identifiable {
    case codex
    case opencode

    var id: String { rawValue }

    var label: String {
        switch self {
        case .codex: return "Codex"
        case .opencode: return "OpenCode"
        }
    }

    static let runtimeKey = "ClawixAgentRuntime"
    static let openCodeModelKey = "ClawixOpenCodeModel"
    static let defaultOpenCodeModel = "deepseekv4/deepseek-v4-pro"

    @MainActor
    static func visibleCases() -> [AgentRuntimeChoice] {
        FeatureFlags.shared.isVisible(.openCode) ? allCases : [.codex]
    }

    @MainActor
    static func loadPersisted() -> AgentRuntimeChoice {
        let defaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard
        if let raw = defaults.string(forKey: runtimeKey),
           let runtime = AgentRuntimeChoice(rawValue: raw) {
            if runtime == .opencode, !FeatureFlags.shared.isVisible(.openCode) {
                return .codex
            }
            return runtime
        }
        return .codex
    }

    static func persistedOpenCodeModel() -> String {
        let defaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard
        return defaults.string(forKey: openCodeModelKey) ?? defaultOpenCodeModel
    }

    @MainActor
    static func persist(runtime: AgentRuntimeChoice, openCodeModel: String) {
        let resolvedRuntime: AgentRuntimeChoice = {
            if runtime == .opencode, !FeatureFlags.shared.isVisible(.openCode) {
                return .codex
            }
            return runtime
        }()
        for defaults in [
            UserDefaults(suiteName: appPrefsSuite) ?? .standard,
            UserDefaults(suiteName: ClawixPersistentSurfaceKeys.bridgeDefaultsSuite) ?? .standard
        ] {
            defaults.set(resolvedRuntime.rawValue, forKey: runtimeKey)
            defaults.set(openCodeModel, forKey: openCodeModelKey)
        }
    }
}

enum Personality: String, CaseIterable, Identifiable {
    case friendly
    case pragmatic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .friendly:  return "Friendly"
        case .pragmatic: return "Pragmatic"
        }
    }

    var blurb: String {
        switch self {
        case .friendly:  return "Warm, collaborative, and helpful"
        case .pragmatic: return "Concise, task-focused, and direct"
        }
    }

    static let userDefaultsKey = "ClawixPersonality"

    static func loadPersisted() -> Personality {
        let defaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard
        if let raw = defaults.string(forKey: userDefaultsKey),
           let value = Personality(rawValue: raw) {
            return value
        }
        return .pragmatic
    }

    func persist() {
        let defaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard
        defaults.set(rawValue, forKey: Personality.userDefaultsKey)
    }
}

/// Identity + text content of a captured app window (an "appshot"). When
/// present on a `ComposerAttachment`, the chip renders the window-shot
/// variant (thumbnail + app-icon badge + window title) and the window text
/// rides along with the outgoing message.
struct AppshotMetadata: Equatable {
    let appName: String
    let bundleId: String?
    let windowTitle: String?
    let windowText: String
}

/// A comment the user pinned on an element of the in-app browser. When
/// present on a `ComposerAttachment`, the chip renders the annotation
/// variant (page screenshot thumbnail + comment marker) and the comment
/// rides along inline with the outgoing message.
struct BrowserAnnotationMetadata: Equatable {
    let pageTitle: String?
    let pageURL: String
    let comment: String
    /// Numbered marker placed on the page where the user clicked.
    let marker: Int
}

struct ComposerAttachment: Identifiable, Equatable {
    let id: UUID
    let url: URL
    /// Non-nil when this attachment is an appshot (frontmost-window capture).
    let appshot: AppshotMetadata?
    /// Non-nil when this attachment is a browser annotation (a comment
    /// pinned on a page element in the in-app browser).
    let annotation: BrowserAnnotationMetadata?

    init(
        id: UUID = UUID(),
        url: URL,
        appshot: AppshotMetadata? = nil,
        annotation: BrowserAnnotationMetadata? = nil
    ) {
        self.id = id
        self.url = url
        self.appshot = appshot
        self.annotation = annotation
    }

    var filename: String { url.lastPathComponent }

    var isImage: Bool {
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "heif", "tiff", "tif", "bmp", "webp"]
        return imageExts.contains(url.pathExtension.lowercased())
    }

    var isAppshot: Bool { appshot != nil }

    var isAnnotation: Bool { annotation != nil }

    /// Label shown on the chip. Appshots prefer the window title, then the
    /// app name; annotations prefer the comment; everything else falls back
    /// to the file name.
    var displayName: String {
        if let appshot {
            if let title = appshot.windowTitle, !title.isEmpty { return title }
            return appshot.appName
        }
        if let annotation {
            let comment = annotation.comment.trimmingCharacters(in: .whitespacesAndNewlines)
            if !comment.isEmpty { return comment }
            return "Annotation \(annotation.marker)"
        }
        return filename
    }
}

struct FindMatch: Equatable, Identifiable {
    let id = UUID()
    let messageId: UUID
    let range: NSRange

    static func == (lhs: FindMatch, rhs: FindMatch) -> Bool {
        lhs.messageId == rhs.messageId
            && lhs.range.location == rhs.range.location
            && lhs.range.length == rhs.range.length
    }
}

final class ComposerState: ObservableObject {
    @Published var text: String = ""
    /// Files staged in the composer (paperclip menu / drag-and-drop /
    /// future paste). On `sendMessage` each url is prepended to the
    /// outgoing text as `@<path>` and the array is cleared.
    @Published var attachments: [ComposerAttachment] = []
    /// Bumped whenever something wants to pull keyboard focus back into
    /// the composer (e.g. ⌘N from home, switching chats from the
    /// sidebar). The composer text editor watches this token and calls
    /// `makeFirstResponder` on change.
    @Published var focusToken: Int = 0
}
