import Combine
import Foundation

@MainActor
final class SidebarStore: ObservableObject {
    @Published private(set) var snapshot: SidebarSnapshot = .empty
    @Published private(set) var selectedRoute: SidebarRoute = .home
    @Published private(set) var revision: UInt64 = 0

    private var cancellables: Set<AnyCancellable> = []
    private var summaries: [ChatSummary]
    private var archivedSummaries: [ChatSummary]
    private var pinnedOrder: [UUID]
    private var projects: [Project]
    private var manualProjectOrder: [UUID]
    private var currentRoute: SidebarRoute
    private var archivedLoading: Bool
    private var summarySignature: [SidebarSummarySignature]
    private var archivedSummarySignature: [SidebarSummarySignature]
    /// Coarse named tick for relative-age labels. Fires when the wall-clock
    /// minute rolls over (not per body, not per frame), recomputing only the
    /// precomputed display models so "3 min" becomes "4 min" without re-sorting.
    private var ageTickTimer: Timer?

    init(appState: AppState) {
        summaries = appState.chatStore.summaries
        archivedSummaries = appState.chatStore.archivedSummaries
        pinnedOrder = appState.pinnedOrder
        projects = appState.projects
        manualProjectOrder = appState.manualProjectOrder
        currentRoute = appState.currentRoute
        selectedRoute = appState.currentRoute
        archivedLoading = appState.archivedLoading
        summarySignature = Self.signature(for: summaries)
        archivedSummarySignature = Self.signature(for: archivedSummaries)
        rebuild()

        // Sidebar invalidation boundary: observe stable summary projections
        // only. Full transcript and streaming message deltas stay in
        // ChatMessageStore/ChatTranscriptStore so token flow cannot rebuild
        // sidebar sorts, filters, or chrome.
        appState.chatStore.$summaries
            .dropFirst()
            .sink { [weak self] summaries in
                self?.updateSummaries(summaries)
            }
            .store(in: &cancellables)

        appState.chatStore.$archivedSummaries
            .dropFirst()
            .sink { [weak self] summaries in
                self?.updateArchivedSummaries(summaries)
            }
            .store(in: &cancellables)

        appState.$pinnedOrder
            .dropFirst()
            .sink { [weak self] order in
                self?.updatePinnedOrder(order)
            }
            .store(in: &cancellables)

        appState.$projects
            .dropFirst()
            .sink { [weak self] projects in
                self?.updateProjects(projects)
            }
            .store(in: &cancellables)

        appState.$manualProjectOrder
            .dropFirst()
            .sink { [weak self] order in
                self?.updateManualProjectOrder(order)
            }
            .store(in: &cancellables)

        appState.$currentRoute
            .dropFirst()
            .sink { [weak self] route in
                self?.currentRoute = route
                self?.selectedRoute = route
            }
            .store(in: &cancellables)

        appState.$archivedLoading
            .dropFirst()
            .sink { [weak self] loading in
                self?.updateArchivedLoading(loading)
            }
            .store(in: &cancellables)

        scheduleAgeTick()
    }

    deinit {
        ageTickTimer?.invalidate()
    }

    /// Recompute the precomputed leaf display models against the current wall
    /// clock and re-publish only if at least one row's label rolled over. A
    /// named, coarse event: the labels are the only thing that changes, so we
    /// rebuild the `displayByChat` map in place and keep the heavy sorted
    /// buckets untouched.
    func refreshAgeLabels(now: Date = Date()) {
        guard !snapshot.displayByChat.isEmpty else { return }
        var next = snapshot.displayByChat
        var changed = false
        let allChats = snapshot.pinned + snapshot.chrono + snapshot.archived
        for chat in allChats {
            let model = RecentChatRowDisplayModel.make(from: chat, now: now)
            if next[chat.id] != model {
                next[chat.id] = model
                changed = true
            }
        }
        guard changed else { return }
        snapshot = snapshot.replacingDisplay(next)
        revision &+= 1
    }

    /// Fire the age tick at the next minute boundary, then every minute. The
    /// minute granularity matches the coarsest sub-hour bucket of the relative
    /// label, so a label can only roll over on a tick.
    private func scheduleAgeTick() {
        ageTickTimer?.invalidate()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshAgeLabels()
            }
        }
        // `.common` so the tick keeps firing during scroll/drag tracking.
        RunLoop.main.add(timer, forMode: .common)
        ageTickTimer = timer
    }

    private func updateSummaries(_ next: [ChatSummary]) {
        let nextSignature = Self.signature(for: next)
        summaries = next
        guard nextSignature != summarySignature else { return }
        summarySignature = nextSignature
        rebuild()
    }

    private func updateArchivedSummaries(_ next: [ChatSummary]) {
        let nextSignature = Self.signature(for: next)
        archivedSummaries = next
        guard nextSignature != archivedSummarySignature else { return }
        archivedSummarySignature = nextSignature
        rebuild()
    }

    private func updatePinnedOrder(_ next: [UUID]) {
        guard next != pinnedOrder else { return }
        pinnedOrder = next
        rebuild()
    }

    private func updateProjects(_ next: [Project]) {
        guard next != projects else { return }
        projects = next
        rebuild()
    }

    private func updateManualProjectOrder(_ next: [UUID]) {
        guard next != manualProjectOrder else { return }
        manualProjectOrder = next
        rebuild()
    }

    private func updateArchivedLoading(_ next: Bool) {
        guard next != archivedLoading else { return }
        archivedLoading = next
        rebuild()
    }

    private func rebuild() {
        let next = SidebarSnapshot.make(
            summaries: summaries,
            archivedSummaries: archivedSummaries,
            pinnedOrder: pinnedOrder,
            projects: projects,
            manualProjectOrder: manualProjectOrder,
            currentRoute: currentRoute,
            archivedLoading: archivedLoading
        )
        // Compare structure only. The precomputed `displayByChat` carries a
        // wall-clock-dependent relative-age label, so two rebuilds of the same
        // structure milliseconds apart can differ purely in that label. Folding
        // it into this gate would turn a structural no-op into a spurious
        // revision bump. Age-label rollover is the age tick's job, not here.
        guard !next.structurallyEqual(to: snapshot) else { return }
        snapshot = next
        revision &+= 1
    }

    private static func signature(for summaries: [ChatSummary]) -> [SidebarSummarySignature] {
        summaries.map(SidebarSummarySignature.init)
    }
}

private struct SidebarSummarySignature: Equatable {
    let id: UUID
    let title: String
    let createdAt: Date
    let clawixThreadId: String?
    let hasActiveTurn: Bool
    let projectId: UUID?
    let isArchived: Bool
    let isPinned: Bool
    let hasUnreadCompletion: Bool
    let cwd: String?
    let forkedFromChatId: UUID?
    let forkedFromTitle: String?
    let forkBannerAfterMessageId: UUID?
    let isQuickAskTemporary: Bool
    let isSideChat: Bool
    let agentId: String

    init(_ summary: ChatSummary) {
        id = summary.id
        title = summary.title
        createdAt = summary.createdAt
        clawixThreadId = summary.clawixThreadId
        hasActiveTurn = summary.hasActiveTurn
        projectId = summary.projectId
        isArchived = summary.isArchived
        isPinned = summary.isPinned
        hasUnreadCompletion = summary.hasUnreadCompletion
        cwd = summary.cwd
        forkedFromChatId = summary.forkedFromChatId
        forkedFromTitle = summary.forkedFromTitle
        forkBannerAfterMessageId = summary.forkBannerAfterMessageId
        isQuickAskTemporary = summary.isQuickAskTemporary
        isSideChat = summary.isSideChat
        agentId = summary.agentId
    }
}

/// Draw-only display values for one sidebar chat row, precomputed once by the
/// compute layer (`SidebarSnapshot.make`) so `RecentChatRow.body` never derives
/// at render time: no `Date()`/`Calendar` relative-age math, no empty-title
/// fallback branch. The two leaf derivations the row used to run inline live
/// here. `ageLabel` is refreshed on a coarse named tick (a wall-clock unit
/// rollover), not per body.
struct RecentChatRowDisplayModel: Equatable {
    let id: UUID
    /// Title with the empty-title fallback already applied.
    let displayTitle: String
    /// Relative-age string ("now", "4 min", "4 d"), already formatted/localized.
    let ageLabel: String

    /// Self-derive a model from a chat. Used by the snapshot's compute layer and
    /// as a safe accessor fallback. Never called from a view body.
    static func make(from chat: Chat, now: Date) -> RecentChatRowDisplayModel {
        RecentChatRowDisplayModel(
            id: chat.id,
            displayTitle: chat.title.isEmpty
                ? String(localized: "Conversation", bundle: AppLocale.packageBundle)
                : chat.title,
            ageLabel: SidebarRelativeAgeLabel.label(from: chat.createdAt, now: now)
        )
    }
}

struct SidebarSnapshot: Equatable {
    let pinned: [Chat]
    let byProject: [UUID: [Chat]]
    let recentDateByProject: [UUID: Date]
    let chrono: [Chat]
    let projectless: [Chat]
    let archived: [Chat]
    let archivedLoading: Bool
    let currentRoute: SidebarRoute
    let projects: [Project]
    let projectsRecent: [Project]
    let projectsCreation: [Project]
    let projectsName: [Project]
    let projectsCustom: [Project]
    let pinnedFilterSources: [PinnedFilterSource]
    let chronoFilterSources: [PinnedFilterSource]
    /// Precomputed leaf display values per chat id. The row looks its model up
    /// here instead of deriving in `body`.
    let displayByChat: [UUID: RecentChatRowDisplayModel]

    static let empty = SidebarSnapshot(
        pinned: [],
        byProject: [:],
        recentDateByProject: [:],
        chrono: [],
        projectless: [],
        archived: [],
        archivedLoading: false,
        currentRoute: .home,
        projects: [],
        projectsRecent: [],
        projectsCreation: [],
        projectsName: [],
        projectsCustom: [],
        pinnedFilterSources: [],
        chronoFilterSources: [],
        displayByChat: [:]
    )

    /// Draw-only accessor for the row. Returns the precomputed model, or a freshly
    /// derived one (compute layer, not render) for an id the map somehow lacks.
    func display(for chat: Chat) -> RecentChatRowDisplayModel {
        displayByChat[chat.id] ?? RecentChatRowDisplayModel.make(from: chat, now: Date())
    }

    /// Structural equality that ignores the wall-clock-dependent `displayByChat`
    /// projection. Used by the store's rebuild gate so a no-op rebuild stays a
    /// no-op even though its display labels were recomputed with a fresh `now`.
    func structurallyEqual(to other: SidebarSnapshot) -> Bool {
        pinned == other.pinned
            && byProject == other.byProject
            && recentDateByProject == other.recentDateByProject
            && chrono == other.chrono
            && projectless == other.projectless
            && archived == other.archived
            && archivedLoading == other.archivedLoading
            && currentRoute == other.currentRoute
            && projects == other.projects
            && projectsRecent == other.projectsRecent
            && projectsCreation == other.projectsCreation
            && projectsName == other.projectsName
            && projectsCustom == other.projectsCustom
            && pinnedFilterSources == other.pinnedFilterSources
            && chronoFilterSources == other.chronoFilterSources
    }

    /// Return a copy with only the precomputed display map swapped. Used by the
    /// coarse age tick to roll relative-age labels without re-sorting buckets.
    func replacingDisplay(_ next: [UUID: RecentChatRowDisplayModel]) -> SidebarSnapshot {
        SidebarSnapshot(
            pinned: pinned,
            byProject: byProject,
            recentDateByProject: recentDateByProject,
            chrono: chrono,
            projectless: projectless,
            archived: archived,
            archivedLoading: archivedLoading,
            currentRoute: currentRoute,
            projects: projects,
            projectsRecent: projectsRecent,
            projectsCreation: projectsCreation,
            projectsName: projectsName,
            projectsCustom: projectsCustom,
            pinnedFilterSources: pinnedFilterSources,
            chronoFilterSources: chronoFilterSources,
            displayByChat: next
        )
    }

    func sortedProjects(for mode: ProjectSortMode) -> [Project] {
        switch mode {
        case .recent: return projectsRecent
        case .creation: return projectsCreation
        case .name: return projectsName
        case .custom: return projectsCustom
        }
    }

    func project(id: UUID) -> Project? {
        projects.first { $0.id == id }
    }

    static func make(
        summaries: [ChatSummary],
        archivedSummaries: [ChatSummary],
        pinnedOrder: [UUID],
        projects: [Project],
        manualProjectOrder: [UUID],
        currentRoute: SidebarRoute,
        archivedLoading: Bool,
        now: Date = Date()
    ) -> SidebarSnapshot {
        PerfSignpost.uiSidebar.interval("snapshot") {
        RenderProbe.time("makeSnapshot") {
            let chats = summaries.compactMap(Self.sidebarChat(from:))
            let archived = archivedSummaries.compactMap(Self.sidebarChat(from:))
            let pinIndex = Dictionary(uniqueKeysWithValues: pinnedOrder.enumerated().map { ($1, $0) })
            var pinnedRaw: [Chat] = []
            var byProjectRaw: [UUID: [Chat]] = [:]
            var chronoRaw: [Chat] = []

            for chat in chats {
                if chat.isSideChat { continue }
                if chat.isPinned {
                    pinnedRaw.append(chat)
                    continue
                }
                if let pid = chat.projectId {
                    byProjectRaw[pid, default: []].append(chat)
                }
                chronoRaw.append(chat)
            }

            pinnedRaw.sort { lhs, rhs in
                let li = pinIndex[lhs.id] ?? Int.max
                let ri = pinIndex[rhs.id] ?? Int.max
                if li != ri { return li < ri }
                return lhs.createdAt > rhs.createdAt
            }
            chronoRaw.sort { $0.createdAt > $1.createdAt }

            var byProject: [UUID: [Chat]] = [:]
            var recentDateByProject: [UUID: Date] = [:]
            byProject.reserveCapacity(byProjectRaw.count)
            recentDateByProject.reserveCapacity(byProjectRaw.count)
            for (pid, list) in byProjectRaw {
                let sortedList = list.sorted { $0.createdAt > $1.createdAt }
                byProject[pid] = Array(sortedList.prefix(10))
                recentDateByProject[pid] = sortedList.first?.createdAt
            }

            let projectless = chronoRaw.filter { $0.projectId == nil }

            // Precompute the two leaf display values per row (relative age +
            // empty-title fallback) once here, so RecentChatRow.body draws and
            // never derives. Covers every bucket a row can be drawn from.
            var displayByChat: [UUID: RecentChatRowDisplayModel] = [:]
            displayByChat.reserveCapacity(chats.count + archived.count)
            for chat in chats {
                displayByChat[chat.id] = RecentChatRowDisplayModel.make(from: chat, now: now)
            }
            for chat in archived where displayByChat[chat.id] == nil {
                displayByChat[chat.id] = RecentChatRowDisplayModel.make(from: chat, now: now)
            }

            return SidebarSnapshot(
                pinned: pinnedRaw,
                byProject: byProject,
                recentDateByProject: recentDateByProject,
                chrono: chronoRaw,
                projectless: projectless,
                archived: archived,
                archivedLoading: archivedLoading,
                currentRoute: currentRoute,
                projects: projects,
                projectsRecent: sortedProjectsRecent(projects, recentDateByProject: recentDateByProject),
                projectsCreation: projects,
                projectsName: sortedProjectsName(projects),
                projectsCustom: sortedProjectsCustom(projects, manualProjectOrder: manualProjectOrder),
                pinnedFilterSources: filterSources(from: pinnedRaw, projects: projects),
                chronoFilterSources: filterSources(from: chronoRaw, projects: projects),
                displayByChat: displayByChat
            )
        }
        }
    }

    private static func sidebarChat(from summary: ChatSummary) -> Chat? {
        if summary.isSideChat { return nil }
        return Chat(
            id: summary.id,
            title: summary.title,
            messages: [],
            createdAt: summary.createdAt,
            clawixThreadId: summary.clawixThreadId,
            rolloutPath: nil,
            historyHydrated: false,
            hasActiveTurn: summary.hasActiveTurn,
            projectId: summary.projectId,
            isArchived: summary.isArchived,
            isPinned: summary.isPinned,
            hasUnreadCompletion: summary.hasUnreadCompletion,
            cwd: summary.cwd,
            hasGitRepo: false,
            branch: nil,
            availableBranches: [],
            uncommittedFiles: nil,
            forkedFromChatId: summary.forkedFromChatId,
            forkedFromTitle: summary.forkedFromTitle,
            forkBannerAfterMessageId: summary.forkBannerAfterMessageId,
            lastTurnInterrupted: false,
            isQuickAskTemporary: summary.isQuickAskTemporary,
            isSideChat: summary.isSideChat,
            agentId: summary.agentId,
            lastMessageAt: summary.lastMessageAt
        )
    }

    private static func sortedProjectsRecent(
        _ projects: [Project],
        recentDateByProject: [UUID: Date]
    ) -> [Project] {
        projects.sorted { lhs, rhs in
            let l = recentDateByProject[lhs.id] ?? .distantPast
            let r = recentDateByProject[rhs.id] ?? .distantPast
            return l > r
        }
    }

    private static func sortedProjectsName(_ projects: [Project]) -> [Project] {
        projects.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func sortedProjectsCustom(
        _ projects: [Project],
        manualProjectOrder: [UUID]
    ) -> [Project] {
        let positionById = Dictionary(
            uniqueKeysWithValues: manualProjectOrder.enumerated().map { ($1, $0) }
        )
        let naturalIdx = Dictionary(
            uniqueKeysWithValues: projects.enumerated().map { ($1.id, $0) }
        )
        return projects.sorted { lhs, rhs in
            let l = positionById[lhs.id] ?? Int.max
            let r = positionById[rhs.id] ?? Int.max
            if l != r { return l < r }
            return (naturalIdx[lhs.id] ?? 0) < (naturalIdx[rhs.id] ?? 0)
        }
    }

    private static func filterSources(from chats: [Chat], projects: [Project]) -> [PinnedFilterSource] {
        var hasNoProject = false
        var projectIds: Set<UUID> = []
        for chat in chats {
            if let pid = chat.projectId {
                projectIds.insert(pid)
            } else {
                hasNoProject = true
            }
        }
        let projectsById = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        var sources: [PinnedFilterSource] = projectIds.compactMap { id in
            guard let project = projectsById[id] else { return nil }
            return PinnedFilterSource(
                token: id.uuidString,
                label: project.name,
                isNoProject: false
            )
        }
        sources.sort { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        if hasNoProject {
            sources.append(PinnedFilterSource(
                token: SidebarView.pinnedFilterNoProjectToken,
                label: String(localized: "Without project", bundle: AppLocale.packageBundle),
                isNoProject: true
            ))
        }
        return sources
    }
}
