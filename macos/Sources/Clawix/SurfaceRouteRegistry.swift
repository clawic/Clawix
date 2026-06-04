import SwiftUI

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
    static func entry(
        for route: SidebarRoute,
        appState: AppState? = nil
    ) -> SurfaceRouteRegistryEntry {
        // The chat surface needs the (non-observed) app-state reference threaded
        // explicitly (ChatView no longer pulls it from the environment). Other
        // surfaces ignore it; tests that only inspect descriptor/module/readiness
        // may omit it. Resolve a fallback only for the chat case so non-chat
        // callers never allocate one.
        return entry(for: route, resolvingAppState: { appState ?? AppState() })
    }

    @MainActor
    private static func entry(
        for route: SidebarRoute,
        resolvingAppState appStateProvider: () -> AppState
    ) -> SurfaceRouteRegistryEntry {
        switch route {
        case .home:
            return entry(route) { MainContentView() }
        case .search:
            return entry(route) {
                MainContentView()
                    .overlay(alignment: .top) {
                        SearchPopoverOverlay()
                            .padding(.top, 120)
                    }
            }
        case .plugins:
            return entry(route) { MainContentView() }
        case .automations:
            return entry(route) { AutomationsView() }
        case .project:
            return entry(route) { MainContentView() }
        case .appsHome:
            return entry(route) { AppsHomeView().appsPollingLease() }
        case .app(let id):
            return entry(route) { AppSurfaceView(appId: id).appsPollingLease() }
        case .chat(let id):
            let appState = appStateProvider()
            return entry(route) { ChatView(appState: appState, chatId: id) }
        case .settings:
            return entry(route) { SettingsContent() }
        case .rescue:
            return entry(route) { RescueDiagnosticsView() }
        case .secretsHome:
            return entry(route) { SecretsScreen() }
        case .databaseHome:
            return entry(route) { DatabaseScreen(mode: .admin) }
        case .databaseWorkbench:
            return entry(route) { DatabaseWorkbenchView() }
        case .databaseCollection(let name):
            return entry(route) { DatabaseScreen(mode: .curated(collectionName: name)) }
        case .memoryHome:
            return entry(route) { MemoryScreen() }
        case .indexHome:
            return entry(route) { IndexScreen() }
        case .macCare:
            return entry(route) { MacCareScreen() }
        case .marketplaceHome:
            return entry(route) { MarketplaceScreen() }
        case .driveAdmin:
            return entry(route) { DriveScreen(mode: .admin) }
        case .drivePhotos:
            return entry(route) { DriveScreen(mode: .photos) }
        case .driveDocuments:
            return entry(route) { DriveScreen(mode: .documents) }
        case .driveRecent:
            return entry(route) { DriveScreen(mode: .recent) }
        case .driveFolder(let id):
            return entry(route) { DriveScreen(mode: .folder(id)) }
        case .calendarHome:
            return entry(route) { CalendarScreen() }
        case .contactsHome:
            return entry(route) { ContactsScreen() }
        case .networkControl:
            return entry(route) { NetworkControlCenterScreen() }
        case .skills:
            return entry(route) { SkillsView() }
        case .skillDetail(let slug):
            return entry(route) { SkillDetailView(slug: slug) }
        case .iotHome:
            return entry(route) { IoTScreen() }
        case .iotDeviceDetail(let id):
            return entry(route) { IoTDeviceDetailView(deviceId: id) }
        case .designStylesHome:
            return entry(route) { StylesHomeView().designPollingLease() }
        case .designStyleDetail(let id):
            return entry(route) { StyleDetailView(styleId: id).designPollingLease() }
        case .designTemplatesHome:
            return entry(route) { TemplatesHomeView().designPollingLease() }
        case .designTemplateDetail(let id):
            return entry(route) { TemplateDetailView(templateId: id).designPollingLease() }
        case .designReferencesHome:
            return entry(route) { ReferencesHomeView().designPollingLease() }
        case .designEditor(let id):
            return entry(route) { EditorView(documentId: id).designPollingLease() }
        case .agentsHome:
            return entry(route) { AgentsHomeView() }
        case .agentDetail(let id):
            return entry(route) { AgentDetailView(agentId: id) }
        case .personalitiesHome:
            return entry(route) { PersonalitiesHomeView() }
        case .personalityDetail(let id):
            return entry(route) { PersonalityDetailView(personalityId: id) }
        case .skillCollectionsHome:
            return entry(route) { SkillCollectionsHomeView() }
        case .skillCollectionDetail(let id):
            return entry(route) { SkillCollectionDetailView(collectionId: id) }
        case .connectionsHome:
            return entry(route) { ConnectionsHomeView() }
        case .connectionDetail(let id):
            return entry(route) { ConnectionDetailView(connectionId: id) }
        case .publishingHome:
            return entry(route) {
                PublishingRootView { PublishingHomeView() }
            }
        case .publishingComposer(let prefill, let scheduleAt):
            return entry(route) {
                PublishingRootView {
                    PublishingComposerView(prefillBody: prefill, prefillScheduleAt: scheduleAt)
                }
            }
        case .publishingChannels:
            return entry(route) {
                PublishingRootView { PublishingChannelsView() }
            }
        case .lifeHome:
            return entry(route) { LifeHomeScreen() }
        case .lifeVertical(let id):
            return entry(route) { LifeVerticalScreen(verticalId: id) }
        case .lifeSettings:
            return entry(route) { LifeSettingsView() }
        }
    }

    @MainActor
    private static func entry<Content: View>(
        _ route: SidebarRoute,
        @ViewBuilder surface: @escaping @MainActor () -> Content
    ) -> SurfaceRouteRegistryEntry {
        let metadata = route.surfaceRouteMetadata
        return SurfaceRouteRegistryEntry(
            descriptor: metadata.descriptor,
            module: metadata.module,
            readinessMode: metadata.readinessMode,
            makeSurface: { AnyView(surface()) }
        )
    }
}
