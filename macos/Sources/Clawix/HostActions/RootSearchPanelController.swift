import AppKit
import SwiftUI

@MainActor
final class RootSearchPanelController {
    static let shared = RootSearchPanelController()

    private var panel: NSPanel?

    private init() {}

    func show() {
        let panel = existingOrCreatePanel()
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        panel?.close()
    }

    private func existingOrCreatePanel() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Root Search"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.contentView = NSHostingView(rootView: RootSearchPanel(onClose: { [weak self] in
            self?.close()
        }))
        self.panel = panel
        return panel
    }
}

@MainActor
final class RootSearchPanelStore: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case loaded
        case error(String)
    }

    @Published var query = ""
    @Published var profile = "framework"
    @Published private(set) var state: State = .idle
    @Published private(set) var results: [RootSearchResult] = []
    @Published private(set) var omittedSources: [RootSearchOmittedSource] = []
    @Published private(set) var actionPlans: [String: ActionPlanState] = [:]

    private var searchTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?

    enum ActionPlanState: Equatable {
        case planning
        case planned(String)
        case error(String)

        var message: String {
            switch self {
            case .planning:
                return "Planning"
            case .planned(let message), .error(let message):
                return message
            }
        }
    }

    deinit {
        searchTask?.cancel()
        actionTask?.cancel()
    }

    func submit() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            omittedSources = []
            actionPlans = [:]
            state = .idle
            return
        }

        searchTask?.cancel()
        state = .loading
        actionPlans = [:]
        searchTask = Task { [trimmed, profile] in
            do {
                let response = try RootSearchQueryBridge.query(trimmed, profile: profile)
                try Task.checkCancellation()
                self.results = response.data.results
                self.omittedSources = response.data.omittedSources ?? []
                self.state = .loaded
            } catch is CancellationError {
                return
            } catch {
                self.results = []
                self.omittedSources = []
                self.state = .error(error.localizedDescription)
            }
        }
    }

    func actionState(result: RootSearchResult, action: RootSearchAction) -> ActionPlanState? {
        actionPlans[actionPlanKey(resultId: result.id, actionId: action.id)]
    }

    func planAction(result: RootSearchResult, action: RootSearchAction) {
        let key = actionPlanKey(resultId: result.id, actionId: action.id)
        actionPlans[key] = .planning
        actionTask?.cancel()
        actionTask = Task { [resultId = result.id, actionId = action.id, key] in
            do {
                let searchPlan = try RootSearchQueryBridge.actionPlan(resultId: resultId, actionId: actionId)
                guard searchPlan.hostRequest != nil else {
                    self.actionPlans[key] = .planned(Self.summary(for: searchPlan))
                    return
                }
                let planBytes = try JSONEncoder().encode(searchPlan)
                let requestBytes = try SearchHostActionBridge.nativeRequestBytes(
                    from: planBytes,
                    host: Self.hostIdentity()
                )
                let nativePlanBytes = try NativeMacActionWire.planJSON(for: requestBytes)
                let nativePlan = try JSONDecoder().decode(NativeMacActionWirePlan.self, from: nativePlanBytes)
                self.actionPlans[key] = .planned(Self.summary(for: nativePlan))
            } catch is CancellationError {
                return
            } catch {
                self.actionPlans[key] = .error(error.localizedDescription)
            }
        }
    }

    private func actionPlanKey(resultId: String, actionId: String) -> String {
        "\(resultId)::\(actionId)"
    }

    private static func summary(for plan: NativeMacActionWirePlan) -> String {
        if let blocked = plan.blockedReasons.first {
            return "Blocked: \(blocked)"
        }
        if plan.requiredApprovals.isEmpty {
            return plan.executable ? "Ready for signed-host execution" : "Planned"
        }
        return "Approval required: \(plan.requiredApprovals.first?.risk ?? plan.risk)"
    }

    private static func summary(for plan: SearchHostActionExecutionPlan) -> String {
        if plan.requiresApproval == true {
            return "Approval required: \(plan.risk ?? "brokered")"
        }
        return "Brokered by Search: \(plan.status ?? "planned")"
    }

    private static func hostIdentity() -> NativeMacActionWireHost {
        NativeMacActionWireHost(
            hostId: ProcessInfo.processInfo.hostName,
            bundleId: Bundle.main.bundleIdentifier ?? "com.example.clawix",
            signingIdentity: nil,
            teamId: nil,
            appVariant: appVariant,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        )
    }

    private static var appVariant: String {
        #if DEBUG
        return "debug"
        #else
        return "release"
        #endif
    }
}

struct RootSearchPanel: View {
    private static let visibleResultLimit = 100

    @StateObject private var store = RootSearchPanelStore()
    @FocusState private var searchFocused: Bool

    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.overlay(0.12))
            results
        }
        .frame(width: 720, height: 560)
        .background(Palette.background)
        .onAppear {
            searchFocused = true
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                SearchIcon(size: 18)
                    .foregroundColor(Palette.textSecondary)
                Text("Root Search")
                    .font(BodyFont.system(size: 16, wght: 650))
                    .foregroundColor(Palette.textPrimary)
                Spacer()
                Picker("", selection: $store.profile) {
                    Text("Framework").tag("framework")
                    Text("Full").tag("full")
                }
                .labelsHidden()
                .frame(width: 128)
                Button(action: onClose) {
                    LucideIcon(.x, size: 14)
                        .foregroundColor(Palette.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close Root Search")
            }

            HStack(spacing: 10) {
                TextField("Search commands, docs, framework records…", text: $store.query)
                    .textFieldStyle(.plain)
                    .font(BodyFont.system(size: 14, wght: 500))
                    .foregroundColor(Palette.textPrimary)
                    .focused($searchFocused)
                    .onSubmit { store.submit() }
                Button {
                    store.submit()
                } label: {
                    SearchIcon(size: 13)
                        .foregroundColor(Palette.textPrimary)
                        .frame(width: 28, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Run Root Search")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Palette.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Palette.border, lineWidth: 0.5)
                    )
            )
        }
        .padding(18)
    }

    @ViewBuilder
    private var results: some View {
        switch store.state {
        case .idle:
            RootSearchEmptyState(title: "Search framework sources", detail: "Root Search stays separate from Command-G chat search.")
        case .loading:
            RootSearchEmptyState(title: "Searching", detail: "Fetching the first framework batch.")
        case .error(let message):
            RootSearchEmptyState(title: "Search unavailable", detail: message)
        case .loaded:
            if store.results.isEmpty {
                RootSearchEmptyState(title: "No results", detail: store.omittedSources.first?.message ?? "Try another query.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.results.prefix(Self.visibleResultLimit)) { result in
                            RootSearchResultRow(
                                result: result,
                                actionState: { action in store.actionState(result: result, action: action) },
                                onPlanAction: { action in store.planAction(result: result, action: action) }
                            )
                        }
                    }
                    .padding(18)
                }
                .thinScrollers()
            }
        }
    }
}

private struct RootSearchResultRow: View {
    let result: RootSearchResult
    let actionState: (RootSearchAction) -> RootSearchPanelStore.ActionPlanState?
    let onPlanAction: (RootSearchAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(result.title)
                    .font(BodyFont.system(size: 13.5, wght: 650))
                    .foregroundColor(Palette.textPrimary)
                    .lineLimit(1)
                Text(result.source)
                    .font(BodyFont.system(size: 10.5, wght: 600))
                    .foregroundColor(Palette.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Palette.cardHover)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                Spacer()
            }
            if let subtitle = result.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Palette.textSecondary)
                    .lineLimit(1)
            }
            if let snippet = result.snippet, !snippet.isEmpty {
                Text(snippet)
                    .font(BodyFont.system(size: 11.5))
                    .foregroundColor(Palette.textTertiary)
                    .lineLimit(2)
            }
            if let actions = result.actions, !actions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(actions, id: \.id) { action in
                        Button {
                            onPlanAction(action)
                        } label: {
                            Text(action.label)
                                .font(BodyFont.system(size: 10.5, wght: 650))
                                .foregroundColor(Palette.textPrimary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Palette.cardHover)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(actionState(action) == .planning)
                        .accessibilityLabel("Plan \(action.label)")
                    }
                    if let state = actions.compactMap({ actionState($0) }).last {
                        Text(state.message)
                            .font(BodyFont.system(size: 10.5, wght: 600))
                            .foregroundColor(actionStateColor(state))
                            .lineLimit(1)
                    }
                    Spacer()
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.cardFill)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func actionStateColor(_ state: RootSearchPanelStore.ActionPlanState) -> Color {
        switch state {
        case .planning:
            return Palette.textSecondary
        case .planned:
            return Palette.pastelBlue
        case .error:
            return .orange
        }
    }
}

private struct RootSearchEmptyState: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(BodyFont.system(size: 13.5, wght: 650))
                .foregroundColor(Palette.textPrimary)
            Text(detail)
                .font(BodyFont.system(size: 11.5))
                .foregroundColor(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
