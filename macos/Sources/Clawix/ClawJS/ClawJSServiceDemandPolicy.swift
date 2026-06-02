import Foundation

enum ClawJSServiceStartReason: Equatable, Hashable, Sendable {
    case startupCore
    case tool(String)
    case route(String)
    case capability(String)
    case manual(String)

    var triggerDescription: String {
        switch self {
        case .startupCore:
            return "startup core"
        case .tool(let name):
            return "\(name) mini-app"
        case .route(let id):
            return "\(id) route"
        case .capability(let name):
            return name
        case .manual(let name):
            return name
        }
    }
}

enum ClawJSServiceVisibilityGate: Equatable {
    case stableCore
    case appFeature(AppFeature)
}

enum ClawJSServiceDemandPolicy {
    static let startupCoreServices: Set<ClawJSService> = []

    static func startupServices(for role: ClawixAppRole) -> Set<ClawJSService> {
        startupServices(for: role, isVisible: { _ in true })
    }

    static func startupServices(
        for role: ClawixAppRole,
        isVisible: (AppFeature) -> Bool
    ) -> Set<ClawJSService> {
        switch role {
        case .main:
            return startupCoreServices
        case .tool(let tool):
            guard isVisible(tool.requiredFeature) else { return [] }
            return services(for: tool)
        }
    }

    static func services(for tool: ClawixToolRole) -> Set<ClawJSService> {
        switch tool {
        case .tasks, .goals, .notes, .projects, .database:
            return [.database]
        case .memory:
            return [.memory]
        case .photos, .documents, .recent, .drive:
            return [.drive]
        case .secrets:
            return [.secrets]
        }
    }

    static func services(for route: SidebarRoute) -> Set<ClawJSService> {
        switch route {
        case .secretsHome:
            return [.secrets]
        case .databaseHome, .databaseWorkbench, .databaseCollection:
            return [.database]
        case .memoryHome:
            return [.memory]
        case .indexHome, .marketplaceHome:
            return [.index]
        case .driveAdmin, .drivePhotos, .driveDocuments, .driveRecent, .driveFolder:
            return [.drive]
        case .iotHome, .iotDeviceDetail:
            return [.iot]
        case .publishingHome, .publishingComposer, .publishingChannels:
            return [.publishing]
        case .chat:
            // Chat owns runtime/session demand so transcript first paint
            // can happen before backend attach work starts.
            return []
        case .home, .search, .plugins, .automations, .project, .app, .appsHome,
             .settings, .rescue, .calendarHome, .contactsHome, .macCare,
             .networkControl, .skills, .skillDetail, .designStylesHome,
             .designStyleDetail, .designTemplatesHome, .designTemplateDetail,
             .designReferencesHome, .designEditor, .agentsHome, .agentDetail,
             .personalitiesHome, .personalityDetail, .skillCollectionsHome,
             .skillCollectionDetail, .connectionsHome, .connectionDetail,
             .lifeHome, .lifeVertical, .lifeSettings:
            return []
        }
    }

    static func services(
        for route: SidebarRoute,
        isVisible: (AppFeature) -> Bool
    ) -> Set<ClawJSService> {
        guard let gatedFeature = route.gatedFeature else {
            return services(for: route)
        }
        guard isVisible(gatedFeature) else {
            return []
        }
        return services(for: route)
    }

    static func visibilityGate(for service: ClawJSService) -> ClawJSServiceVisibilityGate {
        switch service {
        case .runtime, .sessions, .audio:
            return .stableCore
        case .database, .secrets, .memory, .drive, .iot, .index, .publishing:
            return .appFeature(.tools)
        case .telegram:
            return .appFeature(.tools)
        }
    }

    static func isServiceVisible(
        _ service: ClawJSService,
        isVisible: (AppFeature) -> Bool
    ) -> Bool {
        switch visibilityGate(for: service) {
        case .stableCore:
            return true
        case .appFeature(let feature):
            return isVisible(feature)
        }
    }

    static func visibleServices(
        _ services: Set<ClawJSService>,
        isVisible: (AppFeature) -> Bool
    ) -> Set<ClawJSService> {
        services.filter { isServiceVisible($0, isVisible: isVisible) }
    }

    static func onDemandTrigger(for service: ClawJSService) -> String? {
        switch service {
        case .runtime, .sessions:
            return "chat opens"
        case .database:
            return "Database or Tasks opens"
        case .memory:
            return "Memory opens"
        case .drive:
            return "Drive opens"
        case .secrets:
            return "Secrets opens"
        case .telegram:
            return "Telegram settings opens"
        case .audio:
            return "audio capture or playback needs it"
        case .iot:
            return "IoT opens"
        case .index:
            return "Index or Marketplace opens"
        case .publishing:
            return "Publishing opens"
        }
    }
}

@MainActor
enum ClawixStartupCore {
    static func run(role: ClawixAppRole) async {
        let services = ClawJSServiceDemandPolicy.startupServices(
            for: role,
            isVisible: FeatureFlags.shared.isVisible
        )
        let reason: ClawJSServiceStartReason
        switch role {
        case .main:
            reason = .startupCore
        case .tool(let tool):
            reason = .tool(tool.rawValue)
        }
        if services.isEmpty {
            ClawJSServiceManager.shared.markServicesAvailableOnDemand(excluding: [])
        } else {
            _ = await ClawJSServiceManager.shared.acquire(
                services: services,
                reason: reason,
                consumer: "startup.core"
            )
        }
        LaunchMilestones.mark(.coreReady)
    }
}
