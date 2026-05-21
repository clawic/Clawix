import SwiftUI

struct SurfaceRouterView: View {
    let route: SidebarRoute

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var appsStore: AppsStore = .shared
    @ObservedObject private var variantDefaults: AppVariantDefaultsStore = .shared
    @State private var preferredOriginalTargets: Set<String> = []
    @State private var supervisionState: SurfaceRouteSupervisionState = .ready(surfaceID: "initial")

    var body: some View {
        let entry = routeRegistryEntry
        let resolution = activeVariantResolution
        let readinessMode = SurfaceRouteReadinessPolicy.mode(
            for: entry,
            hasActiveCustomVariant: resolution != nil
        )
        let demandedServices = ClawJSServiceDemandPolicy.services(for: route)
        ZStack(alignment: .topTrailing) {
            SurfaceRouteHost(
                descriptor: entry.descriptor,
                readinessMode: readinessMode,
                demandedServices: demandedServices,
                state: $supervisionState
            ) {
                if let resolution {
                    AppSurfaceView(appId: resolution.appId)
                } else {
                    entry.surface()
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

    @MainActor
    private var routeRegistryEntry: SurfaceRouteRegistryEntry {
        SurfaceRouteRegistry.entry(for: route)
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
}

private struct SurfaceRouteHost<Content: View>: View {
    let descriptor: SurfaceRouteDescriptor
    let readinessMode: SurfaceRouteReadinessMode
    let demandedServices: Set<ClawJSService>
    @Binding var state: SurfaceRouteSupervisionState
    @ObservedObject private var serviceManager = ClawJSServiceManager.shared
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

    @MainActor
    private func supervise() async {
        state = SurfaceRouteSupervisor.start(descriptor: descriptor)
        guard case .loading(_, _, _, _) = state else { return }
        if !demandedServices.isEmpty {
            await serviceManager.start(demandedServices, reason: .route(descriptor.id))
            if let issue = serviceManager.startupIssue(for: demandedServices) {
                state = .degraded(surfaceID: descriptor.id, reason: issue)
                return
            }
        }
        await Task.yield()
        guard !Task.isCancelled else {
            state = SurfaceRouteSupervisor.cancel(state: state, descriptor: descriptor)
            return
        }
        state = SurfaceRouteSupervisor.afterFirstRender(
            state: state,
            descriptor: descriptor,
            readinessMode: readinessMode
        )
        guard case .loading(_, let currentTimeoutSeconds, _, _) = state else { return }

        let nanoseconds = UInt64(max(0, currentTimeoutSeconds) * 1_000_000_000)
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

struct AppVariantOriginalRouteControlPresentation: Equatable {
    let symbolName: String
    let primaryLabel: String
    let scopeLabel: String
    let helpText: String

    init(appName: String, scope: AppVariantDefaultScope, isShowingOriginal: Bool) {
        let trimmedName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let variantName = trimmedName.isEmpty ? "Custom view" : trimmedName
        self.symbolName = isShowingOriginal ? "square.grid.2x2" : "arrow.uturn.backward"
        self.primaryLabel = isShowingOriginal ? variantName : "Original"
        self.scopeLabel = scope.rawValue
        self.helpText = isShowingOriginal ? "Show custom variant" : "Show original surface"
    }
}

private struct AppVariantOriginalRouteControl: View {
    let appName: String
    let scope: AppVariantDefaultScope
    let isShowingOriginal: Bool
    let onShowOriginal: () -> Void
    let onShowVariant: () -> Void

    var body: some View {
        let presentation = AppVariantOriginalRouteControlPresentation(
            appName: appName,
            scope: scope,
            isShowingOriginal: isShowingOriginal
        )
        Button {
            isShowingOriginal ? onShowVariant() : onShowOriginal()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: presentation.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 18, height: 18)
                Text(presentation.primaryLabel)
                    .font(BodyFont.system(size: 12.5, wght: 600))
                    .lineLimit(1)
                Text(presentation.scopeLabel)
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
        .help(presentation.helpText)
    }
}
