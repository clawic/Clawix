import SwiftUI

struct SurfaceRouterView: View {
    let route: SidebarRoute

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var appsStore: AppsStore = .shared
    @ObservedObject private var variantDefaults: AppVariantDefaultsStore = .shared
    @State private var preferredOriginalTargets: Set<String> = []

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let resolution = activeVariantResolution {
                    AppSurfaceView(appId: resolution.appId)
                } else {
                    routedSurface
                }
            }

            if let control = variantControl {
                AppVariantOriginalRouteControl(
                    appName: control.appName,
                    scope: control.resolution.scope,
                    isShowingOriginal: control.isShowingOriginal,
                    onShowOriginal: { preferredOriginalTargets.insert(control.resolution.routeTarget) },
                    onShowVariant: { preferredOriginalTargets.remove(control.resolution.routeTarget) }
                )
                .padding(.top, 12)
                .padding(.trailing, 12)
            }
        }
    }

    private var activeVariantResolution: AppVariantResolution? {
        guard let target = normalizedVariantTarget,
              !preferredOriginalTargets.contains(target) else {
            return nil
        }
        return defaultVariantResolution
    }

    private var defaultVariantResolution: AppVariantResolution? {
        guard let target = normalizedVariantTarget else { return nil }
        return variantDefaults.resolution(
            for: target,
            workspaceId: appState.selectedProject?.id,
            appsStore: appsStore
        )
    }

    private var normalizedVariantTarget: String? {
        route.appVariantRouteTarget.map(AppVariantDefaultsStore.normalizedRouteTarget)
    }

    private var variantControl: AppVariantOriginalRouteControlModel? {
        guard let target = normalizedVariantTarget,
              let resolution = defaultVariantResolution,
              resolution.originalRouteAvailable else {
            return nil
        }
        let record = appsStore.record(forId: resolution.appId)
        return AppVariantOriginalRouteControlModel(
            resolution: resolution,
            appName: displayName(for: record),
            isShowingOriginal: preferredOriginalTargets.contains(target)
        )
    }

    private func displayName(for record: AppRecord?) -> String {
        let name = record?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Custom view" : name
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

private struct AppVariantOriginalRouteControlModel {
    var resolution: AppVariantResolution
    var appName: String
    var isShowingOriginal: Bool
}

private struct AppVariantOriginalRouteControl: View {
    let appName: String
    let scope: AppVariantDefaultScope
    let isShowingOriginal: Bool
    let onShowOriginal: () -> Void
    let onShowVariant: () -> Void

    var body: some View {
        Button {
            isShowingOriginal ? onShowVariant() : onShowOriginal()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isShowingOriginal ? "square.grid.2x2" : "arrow.uturn.backward")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 18, height: 18)
                Text(isShowingOriginal ? appName : "Original")
                    .font(BodyFont.system(size: 12.5, wght: 600))
                    .lineLimit(1)
                Text(scope.rawValue)
                    .font(BodyFont.system(size: 11, wght: 500))
                    .foregroundColor(Color(white: 0.58))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(white: 0.10).opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.7)
        )
        .foregroundColor(Color(white: 0.92))
        .buttonStyle(.plain)
        .help(isShowingOriginal ? "Show custom variant" : "Show original surface")
    }
}
