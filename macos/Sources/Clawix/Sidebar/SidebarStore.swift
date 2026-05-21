import Combine
import Foundation

@MainActor
final class SidebarStore: ObservableObject {
    @Published private(set) var snapshot: SidebarSnapshot = .empty
    @Published private(set) var revision: UInt64 = 0

    private var cancellables: Set<AnyCancellable> = []
    private var summaries: [ChatSummary]
    private var archivedSummaries: [ChatSummary]
    private var pinnedOrder: [UUID]
    private var projects: [Project]
    private var manualProjectOrder: [UUID]
    private var currentRoute: SidebarRoute
    private var archivedLoading: Bool

    init(appState: AppState) {
        summaries = appState.chatStore.summaries
        archivedSummaries = appState.chatStore.archivedSummaries
        pinnedOrder = appState.pinnedOrder
        projects = appState.projects
        manualProjectOrder = appState.manualProjectOrder
        currentRoute = appState.currentRoute
        archivedLoading = appState.archivedLoading
        rebuild()

        appState.chatStore.$summaries
            .dropFirst()
            .sink { [weak self] summaries in
                self?.summaries = summaries
                self?.rebuild()
            }
            .store(in: &cancellables)

        appState.chatStore.$archivedSummaries
            .dropFirst()
            .sink { [weak self] summaries in
                self?.archivedSummaries = summaries
                self?.rebuild()
            }
            .store(in: &cancellables)

        appState.$pinnedOrder
            .dropFirst()
            .sink { [weak self] order in
                self?.pinnedOrder = order
                self?.rebuild()
            }
            .store(in: &cancellables)

        appState.$projects
            .dropFirst()
            .sink { [weak self] projects in
                self?.projects = projects
                self?.rebuild()
            }
            .store(in: &cancellables)

        appState.$manualProjectOrder
            .dropFirst()
            .sink { [weak self] order in
                self?.manualProjectOrder = order
                self?.rebuild()
            }
            .store(in: &cancellables)

        appState.$currentRoute
            .dropFirst()
            .sink { [weak self] route in
                self?.currentRoute = route
                self?.rebuild()
            }
            .store(in: &cancellables)

        appState.$archivedLoading
            .dropFirst()
            .sink { [weak self] loading in
                self?.archivedLoading = loading
                self?.rebuild()
            }
            .store(in: &cancellables)
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
        guard next != snapshot else { return }
        snapshot = next
        revision &+= 1
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
        chronoFilterSources: []
    )

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
        archivedLoading: Bool
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
                chronoFilterSources: filterSources(from: chronoRaw, projects: projects)
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
