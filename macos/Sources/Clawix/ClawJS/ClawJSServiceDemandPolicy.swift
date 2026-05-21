import Foundation

enum ClawJSServiceStartReason: Equatable {
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

enum ClawJSServiceDemandPolicy {
    static let startupCoreServices: Set<ClawJSService> = [.runtime, .sessions]

    static func startupServices(for role: ClawixAppRole) -> Set<ClawJSService> {
        switch role {
        case .main:
            return startupCoreServices
        case .tool(let tool):
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
        case .home, .search, .plugins, .automations, .project, .app, .appsHome,
             .chat, .settings, .rescue, .calendarHome, .contactsHome,
             .networkControl, .skills, .skillDetail, .designStylesHome,
             .designStyleDetail, .designTemplatesHome, .designTemplateDetail,
             .designReferencesHome, .designEditor, .agentsHome, .agentDetail,
             .personalitiesHome, .personalityDetail, .skillCollectionsHome,
             .skillCollectionDetail, .connectionsHome, .connectionDetail,
             .lifeHome, .lifeVertical, .lifeSettings:
            return []
        }
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
        let services = ClawJSServiceDemandPolicy.startupServices(for: role)
        let reason: ClawJSServiceStartReason
        switch role {
        case .main:
            reason = .startupCore
        case .tool(let tool):
            reason = .tool(tool.rawValue)
        }
        ClawJSServiceManager.shared.markServicesAvailableOnDemand(excluding: services)
        await ClawJSServiceManager.shared.start(services, reason: reason)
        LaunchMilestones.mark(.coreReady)
    }
}
