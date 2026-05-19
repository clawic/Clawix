import SwiftUI

struct SurfaceRouterView: View {
    let route: SidebarRoute

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var appsStore: AppsStore = .shared
    @ObservedObject private var variantDefaults: AppVariantDefaultsStore = .shared
    @State private var preferredOriginalTargets: Set<String> = []
    @State private var supervisionState: SurfaceRouteSupervisionState = .ready(surfaceID: "initial")

    var body: some View {
        let descriptor = route.surfaceDescriptor
        ZStack(alignment: .topTrailing) {
            SurfaceRouteHost(
                descriptor: descriptor,
                state: $supervisionState
            ) {
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
        route.surfaceDescriptor.routeTarget
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

private struct SurfaceRouteHost<Content: View>: View {
    let descriptor: SurfaceRouteDescriptor
    @Binding var state: SurfaceRouteSupervisionState
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            content()
                .id(descriptor.id)
                .environment(\.surfaceRouteReporter, reporter)

            overlay
        }
        .onAppear { state = SurfaceRouteSupervisor.start(descriptor: descriptor) }
        .onChange(of: descriptor.id) { _, _ in
            state = SurfaceRouteSupervisor.start(descriptor: descriptor)
        }
        .task(id: descriptor.id) {
            await supervise()
        }
    }

    @ViewBuilder
    private var overlay: some View {
        switch state {
        case .loading(let surfaceID, _, let message, let progress) where surfaceID == descriptor.id:
            VStack(spacing: 10) {
                if let progress {
                    ProgressView(value: progress)
                        .frame(width: 160)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(message ?? "Loading surface")
                    .font(BodyFont.system(size: 13, wght: 500))
                    .foregroundColor(Color(white: 0.72))
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(white: 0.08).opacity(0.86))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
            )
            .allowsHitTesting(false)
        case .partial(let surfaceID, let message) where surfaceID == descriptor.id:
            VStack {
                Spacer()
                Text(message)
                    .font(BodyFont.system(size: 12.5, wght: 500))
                    .foregroundColor(Color(white: 0.72))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(white: 0.08).opacity(0.78))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
                    )
                    .padding(.bottom, 16)
            }
            .allowsHitTesting(false)
        case .degraded(let surfaceID, let reason) where surfaceID == descriptor.id:
            blockingStatus(title: "Surface unavailable", message: reason)
        case .error(let surfaceID, let message) where surfaceID == descriptor.id:
            blockingStatus(title: "Surface failed", message: message)
        case .unavailable(let surfaceID, let reason) where surfaceID == descriptor.id:
            blockingStatus(title: "Surface unavailable", message: reason)
        default:
            EmptyView()
        }
    }

    private var reporter: SurfaceRouteReporter {
        SurfaceRouteReporter(surfaceID: descriptor.id) { report in
            state = SurfaceRouteSupervisor.apply(
                report: report,
                state: state,
                descriptor: descriptor
            )
        }
    }

    private func blockingStatus(title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(Color(red: 0.95, green: 0.62, blue: 0.30))
            Text(title)
                .font(BodyFont.system(size: 17, wght: 600))
                .foregroundColor(Palette.textPrimary)
            Text(message)
                .font(BodyFont.system(size: 13.5, wght: 400))
                .foregroundColor(Color(white: 0.66))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background.opacity(0.92))
    }

    private func supervise() async {
        state = SurfaceRouteSupervisor.start(descriptor: descriptor)
        guard case .loading(_, let timeoutSeconds, _, _) = state else { return }
        await Task.yield()
        guard !Task.isCancelled else {
            state = SurfaceRouteSupervisor.cancel(state: state, descriptor: descriptor)
            return
        }
        state = SurfaceRouteSupervisor.markReady(state: state, descriptor: descriptor)

        let nanoseconds = UInt64(max(0, timeoutSeconds) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
        guard !Task.isCancelled else {
            state = SurfaceRouteSupervisor.cancel(state: state, descriptor: descriptor)
            return
        }
        state = SurfaceRouteSupervisor.timeout(state: state, descriptor: descriptor)
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
