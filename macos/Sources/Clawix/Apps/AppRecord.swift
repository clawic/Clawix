import Foundation

/// One mini-app the user can open from the sidebar. Created by an agent
/// (or imported by the user). Persisted as a manifest.json plus loose
/// files under `~/.claw/apps/<slug>/`.
///
/// The split between manifest metadata and on-disk files keeps two
/// concerns separate: the manifest is the index the sidebar/grid read
/// from, while the files are what `WKURLSchemeHandler` streams when the
/// user opens the app. Files are kept on disk (not inlined into the
/// manifest) so swapping a single asset doesn't rewrite the whole
/// manifest, and so binary blobs (icons, images) don't bloat the JSON.
struct AppRecord: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    /// URL-safe slug used as both the on-disk folder name and the
    /// scheme-host: WKWebView loads `clawix-app://<slug>/index.html`.
    /// Must be unique across all apps; the store enforces this on write.
    var slug: String
    var name: String
    var description: String
    /// Emoji preferred. Empty means "use default app icon".
    var icon: String
    /// Hex like `#RA66FF` or empty. Tints the row in the sidebar.
    var accentColor: String
    /// Optional binding. Apps don't nest under projects in the sidebar
    /// (they are top-level), but `projectId` lets the home grid filter
    /// by project so the agent can keep work-related apps grouped.
    var projectId: UUID?
    var tags: [String]
    var permissions: AppPermissions
    /// `true` floats the app to the top of the sidebar Apps section.
    var pinned: Bool
    var lastOpenedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    /// Which chat created the app, if any. Used by `clawix.agent.sendMessage`
    /// to route messages back to the originating thread.
    var createdByChatId: UUID?
    /// SDK-first capability ids requested by the app manifest. Empty means
    /// ordinary storage/UI capabilities only.
    var declaredCapabilities: [String]?
    /// Where the app came from. Imported and marketplace apps need review
    /// before activation; local user-authored apps still show their risk map.
    var originClass: AppOriginClass?
    /// Rendering/runtime lane for this surface.
    var surfaceKind: AppSurfaceKind?
    /// Optional sidebar or built-in route target when the app is a variant.
    var routeTarget: String?
    /// Variant/fork metadata. The original route must remain reachable.
    var variant: AppVariantMetadata?
    /// Replacement policy for sensitive built-in routes.
    var protectedRoutePolicy: AppProtectedRoutePolicy?
    /// Review receipt for imported/marketplace apps after the user has seen
    /// the origin/capability/risk ficha.
    var activationReview: AppActivationReview?

    /// Default to a fresh UUID + sane defaults so the agent can call
    /// `AppRecord(slug:name:)` and start writing files immediately.
    init(
        id: UUID = UUID(),
        slug: String,
        name: String,
        description: String = "",
        icon: String = "",
        accentColor: String = "",
        projectId: UUID? = nil,
        tags: [String] = [],
        permissions: AppPermissions = .defaults,
        pinned: Bool = false,
        lastOpenedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        createdByChatId: UUID? = nil,
        declaredCapabilities: [String] = [],
        originClass: AppOriginClass = .localUserAuthored,
        surfaceKind: AppSurfaceKind = .web,
        routeTarget: String? = nil,
        variant: AppVariantMetadata? = nil,
        protectedRoutePolicy: AppProtectedRoutePolicy = .blocked,
        activationReview: AppActivationReview? = nil
    ) {
        self.id = id
        self.slug = slug
        self.name = name
        self.description = description
        self.icon = icon
        self.accentColor = accentColor
        self.projectId = projectId
        self.tags = tags
        self.permissions = permissions
        self.pinned = pinned
        self.lastOpenedAt = lastOpenedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.createdByChatId = createdByChatId
        self.declaredCapabilities = declaredCapabilities
        self.originClass = originClass
        self.surfaceKind = surfaceKind
        self.routeTarget = routeTarget
        self.variant = variant
        self.protectedRoutePolicy = protectedRoutePolicy
        self.activationReview = activationReview
    }

    var effectiveDeclaredCapabilities: [String] { declaredCapabilities ?? [] }
    var effectiveOriginClass: AppOriginClass { originClass ?? .localUserAuthored }
    var effectiveSurfaceKind: AppSurfaceKind { surfaceKind ?? .web }
    var effectiveProtectedRoutePolicy: AppProtectedRoutePolicy { protectedRoutePolicy ?? .blocked }
}

/// Sandbox knobs gating what an app can do at runtime. Defaults closed:
/// no internet, no pre-approved tool calls. The first time an app tries
/// something, the user gets a native prompt and can persist "always".
struct AppPermissions: Codable, Equatable, Hashable {
    /// `false` blocks `fetch()` to anything outside `clawix-app://` via
    /// CSP `connect-src 'self'`. Flip to `true` to relax to `https:`.
    var internet: Bool
    /// Apps can post messages to the originating chat without prompting.
    /// Flip to `false` to require a prompt for every `sendMessage`.
    var callAgent: Bool
    /// Allowlist of agent tool names the app can invoke without prompting
    /// (e.g. `db.read`, `drive.list`). Anything else triggers a native
    /// confirmation sheet on first call.
    var allowedTools: [String]

    static let defaults = AppPermissions(internet: false, callAgent: true, allowedTools: [])
}

enum AppOriginClass: String, Codable, Equatable, Hashable {
    case localUserAuthored
    case imported
    case marketplace
    case system
}

enum AppSurfaceKind: String, Codable, Equatable, Hashable {
    case web
    case swiftDeclarative
}

enum AppProtectedRoutePolicy: String, Codable, Equatable, Hashable {
    case none
    case variantOnly
    case blocked
}

struct AppVariantMetadata: Codable, Equatable, Hashable {
    var originalRoute: String
    var defaultScope: String?
    var notes: String?

    init(originalRoute: String, defaultScope: String? = nil, notes: String? = nil) {
        self.originalRoute = originalRoute
        self.defaultScope = defaultScope
        self.notes = notes
    }
}

struct AppActivationReview: Codable, Equatable, Hashable {
    var approvedAt: Date
    var approvedBy: String
    var riskMapSource: String

    init(approvedAt: Date = Date(), approvedBy: String = NSFullUserName(), riskMapSource: String) {
        self.approvedAt = approvedAt
        self.approvedBy = approvedBy
        self.riskMapSource = riskMapSource
    }
}
