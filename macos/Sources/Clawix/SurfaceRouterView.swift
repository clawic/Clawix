import SwiftUI

struct SurfaceRouterView: View {
    let route: SidebarRoute

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var appsStore: AppsStore = .shared
    @ObservedObject private var variantDefaults: AppVariantDefaultsStore = .shared

    var body: some View {
        Group {
            if let resolution = variantResolution {
                AppSurfaceView(appId: resolution.appId)
            } else {
                routedSurface
            }
        }
    }

    private var variantResolution: AppVariantResolution? {
        guard let target = route.appVariantRouteTarget else { return nil }
        return variantDefaults.resolution(
            for: target,
            workspaceId: appState.selectedProject?.id,
            appsStore: appsStore
        )
    }

    @ViewBuilder
    private var routedSurface: some View {
        switch route {
            case .home:
                MainContentView()
            case .search:
                MainContentView()
                    .overlay(alignment: .top) {
                        SearchPopoverOverlay()
                            .padding(.top, 120)
                    }
            case .plugins:
                MainContentView()
            case .automations:
                AutomationsView()
            case .project:
                MainContentView()
            case .appsHome:
                AppsHomeView()
            case .app(let id):
                AppSurfaceView(appId: id)
            case .chat(let id):
                ChatView(chatId: id)
            case .settings:
                SettingsContent()
            case .rescue:
                RescueDiagnosticsView()
            case .secretsHome:
                SecretsScreen()
            case .databaseHome:
                DatabaseScreen(mode: .admin)
            case .databaseWorkbench:
                DatabaseWorkbenchView()
            case .databaseCollection(let name):
                DatabaseScreen(mode: .curated(collectionName: name))
            case .memoryHome:
                MemoryScreen()
            case .indexHome:
                IndexScreen()
            case .marketplaceHome:
                MarketplaceScreen()
            case .driveAdmin:
                DriveScreen(mode: .admin)
            case .drivePhotos:
                DriveScreen(mode: .photos)
            case .driveDocuments:
                DriveScreen(mode: .documents)
            case .driveRecent:
                DriveScreen(mode: .recent)
            case .driveFolder(let id):
                DriveScreen(mode: .folder(id))
            case .calendarHome:
                CalendarScreen()
            case .contactsHome:
                ContactsScreen()
            case .skills:
                SkillsView()
            case .skillDetail(let slug):
                SkillDetailView(slug: slug)
            case .iotHome:
                IoTScreen()
            case .iotDeviceDetail(let id):
                IoTDeviceDetailView(deviceId: id)
            case .designStylesHome:
                StylesHomeView()
            case .designStyleDetail(let id):
                StyleDetailView(styleId: id)
            case .designTemplatesHome:
                TemplatesHomeView()
            case .designTemplateDetail(let id):
                TemplateDetailView(templateId: id)
            case .designReferencesHome:
                ReferencesHomeView()
            case .designEditor(let id):
                EditorView(documentId: id)
            case .agentsHome:
                AgentsHomeView()
            case .agentDetail(let id):
                AgentDetailView(agentId: id)
            case .personalitiesHome:
                PersonalitiesHomeView()
            case .personalityDetail(let id):
                PersonalityDetailView(personalityId: id)
            case .skillCollectionsHome:
                SkillCollectionsHomeView()
            case .skillCollectionDetail(let id):
                SkillCollectionDetailView(collectionId: id)
            case .connectionsHome:
                ConnectionsHomeView()
            case .connectionDetail(let id):
                ConnectionDetailView(connectionId: id)
            case .publishingHome:
                PublishingHomeView()
            case .publishingComposer(let prefill, let scheduleAt):
                PublishingComposerView(prefillBody: prefill, prefillScheduleAt: scheduleAt)
            case .publishingChannels:
                PublishingChannelsView()
            case .lifeHome:
                LifeHomeScreen()
            case .lifeVertical(let id):
                LifeVerticalScreen(verticalId: id)
            case .lifeSettings:
                LifeSettingsView()
        }
    }
}
