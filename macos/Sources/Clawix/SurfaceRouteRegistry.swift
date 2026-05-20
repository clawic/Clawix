import SwiftUI

enum SurfaceRouteModule: String, Equatable, Hashable, CaseIterable {
    case core
    case protected
    case apps
    case automation
    case data
    case drive
    case time
    case skills
    case iot
    case design
    case agents
    case publishing
    case life
    case network
}

struct SurfaceRouteRegistryEntry {
    var descriptor: SurfaceRouteDescriptor
    var module: SurfaceRouteModule
    var readinessMode: SurfaceRouteReadinessMode

    private let makeSurface: @MainActor () -> AnyView

    init(
        descriptor: SurfaceRouteDescriptor,
        module: SurfaceRouteModule,
        readinessMode: SurfaceRouteReadinessMode,
        makeSurface: @escaping @MainActor () -> AnyView
    ) {
        self.descriptor = descriptor
        self.module = module
        self.readinessMode = readinessMode
        self.makeSurface = makeSurface
    }

    @MainActor
    func surface() -> AnyView {
        makeSurface()
    }
}

enum SurfaceRouteRegistry {
    @MainActor
    static func entry(for route: SidebarRoute) -> SurfaceRouteRegistryEntry {
        switch route {
        case .home:
            return entry(route, module: .core) { MainContentView() }
        case .search:
            return entry(route, module: .core) {
                MainContentView()
                    .overlay(alignment: .top) {
                        SearchPopoverOverlay()
                            .padding(.top, 120)
                    }
            }
        case .plugins:
            return entry(route, module: .automation) { MainContentView() }
        case .automations:
            return entry(route, module: .automation) { AutomationsView() }
        case .project:
            return entry(route, module: .core) { MainContentView() }
        case .appsHome:
            return entry(route, module: .apps) { AppsHomeView() }
        case .app(let id):
            return entry(route, module: .apps, readinessMode: .childReported) {
                AppSurfaceView(appId: id)
            }
        case .chat(let id):
            return entry(route, module: .core) { ChatView(chatId: id) }
        case .settings:
            return entry(route, module: .core) { SettingsContent() }
        case .rescue:
            return entry(route, module: .core) { RescueDiagnosticsView() }
        case .secretsHome:
            return entry(route, module: .protected) { SecretsScreen() }
        case .databaseHome:
            return entry(route, module: .data) { DatabaseScreen(mode: .admin) }
        case .databaseWorkbench:
            return entry(route, module: .data) { DatabaseWorkbenchView() }
        case .databaseCollection(let name):
            return entry(route, module: .data) { DatabaseScreen(mode: .curated(collectionName: name)) }
        case .memoryHome:
            return entry(route, module: .data) { MemoryScreen() }
        case .indexHome:
            return entry(route, module: .data) { IndexScreen() }
        case .marketplaceHome:
            return entry(route, module: .apps) { MarketplaceScreen() }
        case .driveAdmin:
            return entry(route, module: .drive) { DriveScreen(mode: .admin) }
        case .drivePhotos:
            return entry(route, module: .drive) { DriveScreen(mode: .photos) }
        case .driveDocuments:
            return entry(route, module: .drive) { DriveScreen(mode: .documents) }
        case .driveRecent:
            return entry(route, module: .drive) { DriveScreen(mode: .recent) }
        case .driveFolder(let id):
            return entry(route, module: .drive) { DriveScreen(mode: .folder(id)) }
        case .calendarHome:
            return entry(route, module: .time) { CalendarScreen() }
        case .contactsHome:
            return entry(route, module: .time) { ContactsScreen() }
        case .networkControl:
            return entry(route, module: .network) { NetworkControlCenterScreen() }
        case .skills:
            return entry(route, module: .skills) { SkillsView() }
        case .skillDetail(let slug):
            return entry(route, module: .skills) { SkillDetailView(slug: slug) }
        case .iotHome:
            return entry(route, module: .iot) { IoTScreen() }
        case .iotDeviceDetail(let id):
            return entry(route, module: .iot) { IoTDeviceDetailView(deviceId: id) }
        case .designStylesHome:
            return entry(route, module: .design) { StylesHomeView() }
        case .designStyleDetail(let id):
            return entry(route, module: .design) { StyleDetailView(styleId: id) }
        case .designTemplatesHome:
            return entry(route, module: .design) { TemplatesHomeView() }
        case .designTemplateDetail(let id):
            return entry(route, module: .design) { TemplateDetailView(templateId: id) }
        case .designReferencesHome:
            return entry(route, module: .design) { ReferencesHomeView() }
        case .designEditor(let id):
            return entry(route, module: .design) { EditorView(documentId: id) }
        case .agentsHome:
            return entry(route, module: .agents) { AgentsHomeView() }
        case .agentDetail(let id):
            return entry(route, module: .agents) { AgentDetailView(agentId: id) }
        case .personalitiesHome:
            return entry(route, module: .agents) { PersonalitiesHomeView() }
        case .personalityDetail(let id):
            return entry(route, module: .agents) { PersonalityDetailView(personalityId: id) }
        case .skillCollectionsHome:
            return entry(route, module: .skills) { SkillCollectionsHomeView() }
        case .skillCollectionDetail(let id):
            return entry(route, module: .skills) { SkillCollectionDetailView(collectionId: id) }
        case .connectionsHome:
            return entry(route, module: .agents) { ConnectionsHomeView() }
        case .connectionDetail(let id):
            return entry(route, module: .agents) { ConnectionDetailView(connectionId: id) }
        case .publishingHome:
            return entry(route, module: .publishing) { PublishingHomeView() }
        case .publishingComposer(let prefill, let scheduleAt):
            return entry(route, module: .publishing) {
                PublishingComposerView(prefillBody: prefill, prefillScheduleAt: scheduleAt)
            }
        case .publishingChannels:
            return entry(route, module: .publishing) { PublishingChannelsView() }
        case .lifeHome:
            return entry(route, module: .life) { LifeHomeScreen() }
        case .lifeVertical(let id):
            return entry(route, module: .life) { LifeVerticalScreen(verticalId: id) }
        case .lifeSettings:
            return entry(route, module: .life) { LifeSettingsView() }
        }
    }

    @MainActor
    private static func entry<Content: View>(
        _ route: SidebarRoute,
        module: SurfaceRouteModule,
        readinessMode: SurfaceRouteReadinessMode = .immediateAfterFirstRender,
        @ViewBuilder surface: @escaping @MainActor () -> Content
    ) -> SurfaceRouteRegistryEntry {
        SurfaceRouteRegistryEntry(
            descriptor: route.surfaceDescriptor,
            module: module,
            readinessMode: readinessMode,
            makeSurface: { AnyView(surface()) }
        )
    }
}
