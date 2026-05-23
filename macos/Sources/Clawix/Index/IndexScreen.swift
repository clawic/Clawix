import SwiftUI

enum IndexTab: String, CaseIterable, Identifiable, Hashable {
    case catalog
    case searches
    case monitors
    case runs
    case alerts

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .catalog: return "Catalog"
        case .searches: return "Searches"
        case .monitors: return "Monitors"
        case .runs: return "Runs"
        case .alerts: return "Alerts"
        }
    }
}

struct IndexScreen: View {
    @StateObject private var store = IndexStore()
    @State private var activeTab: IndexTab = .catalog
    @State private var showCreateSearchSheet = false

    var body: some View {
        VStack(spacing: 0) {
            IndexHeaderBar(
                store: store,
                activeTab: $activeTab,
                onCreateSearch: { showCreateSearchSheet = true },
                onRefresh: { store.requestRefresh() }
            )
            CardDivider()
            Group {
                switch store.state {
                case .idle, .loading:
                    IndexLoadingView()
                case .error(let message):
                    IndexEmptyState(
                        title: "Index unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: message
                    )
                case .ready:
                    contentForActiveTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black.opacity(0.001))
        .task {
            let services = ClawJSServiceDemandPolicy.services(
                for: .indexHome,
                isVisible: FeatureFlags.shared.isVisible
            )
            let lease = await ClawJSServiceManager.shared.acquire(
                services: services,
                reason: .route("index"),
                consumer: "route.index"
            )
            defer { Task { await ClawJSServiceManager.shared.release(lease) } }
            if store.state == .idle {
                store.requestRefresh()
            }
            await ClawJSServiceManager.holdDemandUntilCancelled()
        }
        .onDisappear {
            store.cancelSurfaceWork()
        }
        .sheet(isPresented: $showCreateSearchSheet) {
            SearchEditorSheet(store: store, onDismiss: { showCreateSearchSheet = false })
        }
    }

    @ViewBuilder
    private var contentForActiveTab: some View {
        switch activeTab {
        case .catalog:
            CatalogTabView(store: store)
        case .searches:
            SearchesTabView(store: store, onCreate: { showCreateSearchSheet = true })
        case .monitors:
            MonitorsTabView(store: store)
        case .runs:
            RunsTabView(store: store)
        case .alerts:
            AlertsTabView(store: store)
        }
    }
}

struct IndexEmptyState: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 8) {
            LucideIcon.auto(systemImage, size: 28)
                .foregroundColor(Color.overlay(0.30))
                .frame(width: 36, height: 36)
            Text(title)
                .font(BodyFont.system(size: 13, wght: 600))
                .foregroundColor(Color.overlay(0.68))
                .fixedSize(horizontal: false, vertical: true)
            Text(description)
                .font(BodyFont.system(size: 11, wght: 400))
                .foregroundColor(Color.overlay(0.42))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct IndexHeaderBar: View {
    @ObservedObject var store: IndexStore
    @Binding var activeTab: IndexTab
    let onCreateSearch: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 8) {
                    IndexIcon(size: 18)
                        .foregroundColor(Color.overlay(0.9))
                    Text("Index")
                        .font(BodyFont.system(size: 17, wght: 600))
                        .foregroundColor(Palette.textPrimary)
                    if store.unreadAlerts > 0 {
                        Text("\(store.unreadAlerts)")
                            .font(BodyFont.system(size: 11, wght: 600))
                            .foregroundColor(Palette.background)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.orange.opacity(0.9))
                            )
                    }
                }
                Spacer()
                Button(action: onCreateSearch) {
                    HStack(spacing: 6) {
                        LucideIcon.auto("plus", size: 12)
                        Text("New search")
                            .font(BodyFont.system(size: 12.5, wght: 500))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.overlay(0.08))
                    )
                    .foregroundColor(Palette.textPrimary)
                }
                .buttonStyle(.plain)

                Button(action: onRefresh) {
                    LucideIcon.auto("arrow.triangle.2.circlepath", size: 12)
                        .foregroundColor(Color.overlay(0.7))
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.overlay(0.04))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            HStack {
                IndexTabBar(activeTab: $activeTab, unreadAlerts: store.unreadAlerts)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }
}

private struct IndexTabBar: View {
    @Binding var activeTab: IndexTab
    let unreadAlerts: Int

    var body: some View {
        SlidingSegmented<IndexTab>(
            selection: $activeTab,
            options: IndexTab.allCases.map { tab in
                if tab == .alerts && unreadAlerts > 0 {
                    return (tab, "\(tab.displayName) · \(unreadAlerts)")
                }
                return (tab, tab.displayName)
            },
            height: 30
        )
        .frame(width: 460)
    }
}

private struct IndexLoadingView: View {
    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.regular)
                .tint(Color.overlay(0.7))
            Text("Loading Index…")
                .font(BodyFont.system(size: 12, wght: 400))
                .foregroundColor(Color.overlay(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
