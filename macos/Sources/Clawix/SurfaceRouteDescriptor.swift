import Foundation

enum SurfaceRouteCriticality: String, Equatable, Hashable {
    case core
    case protected
    case extensionSurface
}

enum SurfaceRouteDependency: String, Equatable, Hashable, CaseIterable {
    case languageModels
    case searchIndex
    case databaseBackfill
    case customApps
    case connectors
    case downloads
    case externalProviders
}

struct SurfaceRouteDescriptor: Equatable, Hashable {
    var id: String
    var criticality: SurfaceRouteCriticality
    var routeTarget: String?
    var supportsVariantDefault: Bool
    var timeoutSeconds: TimeInterval?
    var requiresIndependentDegradation: Bool

    var isCoreSurvivalRoute: Bool { criticality == .core }
    var canUseCustomVariantDefault: Bool { supportsVariantDefault && routeTarget != nil }
}

enum SurfaceShellIsolationPolicy {
    static func criticalShellDependencies(
        for descriptor: SurfaceRouteDescriptor
    ) -> Set<SurfaceRouteDependency> {
        []
    }

    static func surfaceDependencies(
        for descriptor: SurfaceRouteDescriptor
    ) -> Set<SurfaceRouteDependency> {
        guard !descriptor.isCoreSurvivalRoute else { return [] }

        if descriptor.criticality == .protected {
            return []
        }

        if descriptor.id.hasPrefix("app:") || descriptor.id == "apps" {
            return [.customApps, .downloads]
        }
        if descriptor.id.hasPrefix("database") {
            return [.databaseBackfill]
        }
        if descriptor.id == "index" || descriptor.id.hasPrefix("memory") {
            return [.searchIndex]
        }
        if descriptor.id.hasPrefix("drive")
            || descriptor.id == "calendar"
            || descriptor.id == "contacts"
            || descriptor.id.hasPrefix("connection") {
            return [.connectors, .downloads]
        }
        if descriptor.id.hasPrefix("iot") {
            return [.connectors, .externalProviders]
        }
        if descriptor.id.hasPrefix("agent") || descriptor.id.hasPrefix("personality") {
            return [.languageModels]
        }
        if descriptor.id == "network-control" {
            return [.connectors]
        }
        if descriptor.id.hasPrefix("publishing") {
            return [.connectors, .externalProviders]
        }

        return []
    }

    static func unavailableSurfaceDependencies(
        for descriptor: SurfaceRouteDescriptor,
        unavailableDependencies: Set<SurfaceRouteDependency>
    ) -> Set<SurfaceRouteDependency> {
        surfaceDependencies(for: descriptor).intersection(unavailableDependencies)
    }

    static func startCriticalShellState(
        for descriptor: SurfaceRouteDescriptor,
        unavailableDependencies: Set<SurfaceRouteDependency>
    ) -> SurfaceRouteSupervisionState {
        guard descriptor.isCoreSurvivalRoute else {
            return SurfaceRouteSupervisor.start(descriptor: descriptor)
        }
        return .ready(surfaceID: descriptor.id)
    }
}

extension SidebarRoute {
    var surfaceDescriptor: SurfaceRouteDescriptor {
        let routeTarget = appVariantRouteTarget.map(Self.normalizedSurfaceRouteTarget)
        return SurfaceRouteDescriptor(
            id: surfaceStableID,
            criticality: surfaceCriticality,
            routeTarget: routeTarget,
            supportsVariantDefault: routeTarget != nil,
            timeoutSeconds: surfaceTimeoutSeconds,
            requiresIndependentDegradation: surfaceCriticality != .core
        )
    }

    private static func normalizedSurfaceRouteTarget(_ routeTarget: String) -> String {
        routeTarget.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var surfaceCriticality: SurfaceRouteCriticality {
        switch self {
        case .home, .search, .project, .chat, .settings, .rescue:
            return .core
        case .secretsHome:
            return .protected
        case .app, .appsHome, .plugins, .automations, .databaseHome,
             .databaseWorkbench, .databaseCollection, .memoryHome, .indexHome,
             .marketplaceHome, .driveAdmin, .drivePhotos, .driveDocuments,
             .driveRecent, .driveFolder, .calendarHome, .contactsHome,
             .networkControl, .skills, .skillDetail, .iotHome, .iotDeviceDetail,
             .designStylesHome, .designStyleDetail, .designTemplatesHome,
             .designTemplateDetail, .designReferencesHome, .designEditor,
             .agentsHome, .agentDetail, .personalitiesHome, .personalityDetail,
             .skillCollectionsHome, .skillCollectionDetail,
             .connectionsHome, .connectionDetail, .publishingHome,
             .publishingComposer, .publishingChannels, .lifeHome,
             .lifeVertical, .lifeSettings:
            return .extensionSurface
        }
    }

    private var surfaceTimeoutSeconds: TimeInterval? {
        switch surfaceCriticality {
        case .core:
            return nil
        case .protected:
            return 8
        case .extensionSurface:
            return 5
        }
    }

    private var surfaceStableID: String {
        switch self {
        case .home:
            return "home"
        case .search:
            return "search"
        case .plugins:
            return "plugins"
        case .automations:
            return "automations"
        case .project:
            return "project"
        case .app(let id):
            return "app:\(id.uuidString)"
        case .appsHome:
            return "apps"
        case .chat(let id):
            return "chat:\(id.uuidString)"
        case .settings:
            return "settings"
        case .rescue:
            return "rescue"
        case .secretsHome:
            return "secrets"
        case .databaseHome:
            return "database"
        case .databaseWorkbench:
            return "database-workbench"
        case .databaseCollection(let name):
            return "database:\(name)"
        case .memoryHome:
            return "memory"
        case .indexHome:
            return "index"
        case .marketplaceHome:
            return "marketplace"
        case .driveAdmin:
            return "drive"
        case .drivePhotos:
            return "drive:photos"
        case .driveDocuments:
            return "drive:documents"
        case .driveRecent:
            return "drive:recent"
        case .driveFolder(let id):
            return "drive:folder:\(id)"
        case .calendarHome:
            return "calendar"
        case .contactsHome:
            return "contacts"
        case .networkControl:
            return "network-control"
        case .skills:
            return "skills"
        case .skillDetail(let slug):
            return "skill:\(slug)"
        case .iotHome:
            return "iot"
        case .iotDeviceDetail(let id):
            return "iot:device:\(id)"
        case .designStylesHome:
            return "design:styles"
        case .designStyleDetail(let id):
            return "design:style:\(id)"
        case .designTemplatesHome:
            return "design:templates"
        case .designTemplateDetail(let id):
            return "design:template:\(id)"
        case .designReferencesHome:
            return "design:references"
        case .designEditor(let id):
            return "design:editor:\(id)"
        case .agentsHome:
            return "agents"
        case .agentDetail(let id):
            return "agent:\(id)"
        case .personalitiesHome:
            return "personalities"
        case .personalityDetail(let id):
            return "personality:\(id)"
        case .skillCollectionsHome:
            return "skill-collections"
        case .skillCollectionDetail(let id):
            return "skill-collection:\(id)"
        case .connectionsHome:
            return "connections"
        case .connectionDetail(let id):
            return "connection:\(id)"
        case .publishingHome:
            return "publishing"
        case .publishingComposer(let prefill, let scheduleAt):
            return "publishing:composer:\(prefill?.hashValue ?? 0):\(scheduleAt?.timeIntervalSince1970 ?? 0)"
        case .publishingChannels:
            return "publishing:channels"
        case .lifeHome:
            return "life"
        case .lifeVertical(let id):
            return "life:\(id)"
        case .lifeSettings:
            return "life:settings"
        }
    }
}
