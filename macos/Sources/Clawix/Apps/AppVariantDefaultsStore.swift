import Foundation

enum AppVariantDefaultScope: String, Codable, Equatable, Hashable {
    case user
    case workspace
}

struct AppVariantResolution: Equatable {
    var appId: UUID
    var routeTarget: String
    var scope: AppVariantDefaultScope
    var originalRouteAvailable: Bool
}

@MainActor
final class AppVariantDefaultsStore: ObservableObject {
    static let shared = AppVariantDefaultsStore()

    @Published private(set) var defaults: [String: UUID] = [:]

    private let userDefaults: UserDefaults
    private let storageKey = ClawixPersistentSurfaceKeys.appsVariantDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        load()
    }

    func setDefault(
        app: AppRecord,
        scope: AppVariantDefaultScope,
        workspaceId: UUID? = nil
    ) throws {
        let routeTarget = try validatedVariantTarget(app)
        defaults[key(routeTarget: routeTarget, scope: scope, workspaceId: workspaceId)] = app.id
        persist()
    }

    func clearDefault(
        routeTarget: String,
        scope: AppVariantDefaultScope,
        workspaceId: UUID? = nil
    ) {
        defaults.removeValue(forKey: key(routeTarget: routeTarget, scope: scope, workspaceId: workspaceId))
        persist()
    }

    func defaultAppId(
        routeTarget: String,
        scope: AppVariantDefaultScope,
        workspaceId: UUID? = nil
    ) -> UUID? {
        defaults[key(routeTarget: routeTarget, scope: scope, workspaceId: workspaceId)]
    }

    func isDefault(
        app: AppRecord,
        scope: AppVariantDefaultScope,
        workspaceId: UUID? = nil
    ) -> Bool {
        guard let routeTarget = app.routeTarget else { return false }
        return defaultAppId(routeTarget: routeTarget, scope: scope, workspaceId: workspaceId) == app.id
    }

    func resolution(
        for routeTarget: String,
        workspaceId: UUID? = nil,
        appsStore: AppsStore,
        preferOriginal: Bool = false
    ) -> AppVariantResolution? {
        guard !preferOriginal else { return nil }
        let normalizedTarget = Self.normalizedRouteTarget(routeTarget)

        let candidates: [(AppVariantDefaultScope, UUID?)] = [
            (.workspace, workspaceId),
            (.user, nil)
        ]
        for (scope, workspaceId) in candidates {
            guard let appId = defaults[key(routeTarget: normalizedTarget, scope: scope, workspaceId: workspaceId)],
                  let record = appsStore.record(forId: appId),
                  isUsableVariant(record, for: normalizedTarget) else {
                continue
            }
            return AppVariantResolution(
                appId: appId,
                routeTarget: normalizedTarget,
                scope: scope,
                originalRouteAvailable: true
            )
        }
        return nil
    }

    nonisolated static func normalizedRouteTarget(_ routeTarget: String) -> String {
        routeTarget.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func validatedVariantTarget(_ app: AppRecord) throws -> String {
        let routeTarget = Self.normalizedRouteTarget(app.routeTarget ?? "")
        guard !routeTarget.isEmpty,
              let variant = app.variant,
              Self.normalizedRouteTarget(variant.originalRoute) == routeTarget else {
            throw AppVariantDefaultsError.invalidVariant(app.slug)
        }
        let violations = AppCapabilityCatalog.protectedRouteViolations(for: app)
        guard violations.isEmpty else {
            throw AppVariantDefaultsError.protectedRouteViolation(violations.joined(separator: " "))
        }
        return routeTarget
    }

    private func isUsableVariant(_ app: AppRecord, for routeTarget: String) -> Bool {
        guard Self.normalizedRouteTarget(app.routeTarget ?? "") == routeTarget,
              let variant = app.variant,
              Self.normalizedRouteTarget(variant.originalRoute) == routeTarget,
              AppCapabilityCatalog.protectedRouteViolations(for: app).isEmpty else {
            return false
        }
        if case .allowed = AppCapabilityCatalog.activationGate(for: app) {
            return true
        }
        return false
    }

    private func key(routeTarget: String, scope: AppVariantDefaultScope, workspaceId: UUID?) -> String {
        let workspace = scope == .workspace ? (workspaceId?.uuidString.lowercased() ?? "global") : "user"
        return "\(scope.rawValue):\(workspace):\(Self.normalizedRouteTarget(routeTarget))"
    }

    private func load() {
        guard let data = userDefaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: UUID].self, from: data) else {
            defaults = [:]
            return
        }
        defaults = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(defaults) else { return }
        userDefaults.set(data, forKey: storageKey)
    }
}

enum AppVariantDefaultsError: LocalizedError, Equatable {
    case invalidVariant(String)
    case protectedRouteViolation(String)

    var errorDescription: String? {
        switch self {
        case .invalidVariant(let slug):
            return "App is not a valid route variant: \(slug)"
        case .protectedRouteViolation(let message):
            return message
        }
    }
}

extension SidebarRoute {
    var appVariantRouteTarget: String? {
        switch self {
        case .secretsHome:
            return "secrets"
        case .databaseHome:
            return "database"
        case .databaseWorkbench:
            return "database-workbench"
        case .databaseCollection(let name):
            return "database/\(name)"
        case .memoryHome:
            return "memory"
        case .indexHome:
            return "index"
        case .marketplaceHome:
            return "marketplace"
        case .driveAdmin:
            return "drive"
        case .drivePhotos:
            return "drive/photos"
        case .driveDocuments:
            return "drive/documents"
        case .driveRecent:
            return "drive/recent"
        case .calendarHome:
            return "calendar"
        case .contactsHome:
            return "contacts"
        case .networkControl:
            return "network-control"
        case .skills:
            return "skills"
        case .iotHome:
            return "iot"
        case .designStylesHome:
            return "design/styles"
        case .designTemplatesHome:
            return "design/templates"
        case .designReferencesHome:
            return "design/references"
        case .agentsHome:
            return "agents"
        case .connectionsHome:
            return "connections"
        case .publishingHome:
            return "publishing"
        case .lifeHome:
            return "life"
        case .home, .search, .plugins, .automations, .project, .app, .appsHome,
             .chat, .settings, .rescue, .driveFolder, .skillDetail, .iotDeviceDetail,
             .designStyleDetail, .designTemplateDetail, .designEditor,
             .agentDetail, .personalitiesHome, .personalityDetail,
             .skillCollectionsHome, .skillCollectionDetail, .connectionDetail,
             .publishingComposer, .publishingChannels, .lifeVertical, .lifeSettings:
            return nil
        }
    }
}
