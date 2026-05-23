import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    let appState: AppState
    @EnvironmentObject var flags: FeatureFlags
    @StateObject private var sidebarStore: SidebarStore
    @State private var settingsPopoverOpen: Bool = false
    @State private var projectEditor: ProjectEditorContext?
    @State private var projectRenameTarget: Project?
    @State private var projectMenuOpenId: UUID?
    @State private var expandedProjects: Set<UUID> = []
    /// Projects that the user has expanded past the default 5-chat
    /// preview by tapping "Show more" in their accordion. Cleared on
    /// collapse so reopening a project comes back to the trimmed view.
    @State private var projectsShowingExtended: Set<UUID> = []
    @State private var projectsHeaderHovered: Bool = false
    @State private var newProjectMenuOpen: Bool = false
    @State private var organizeMenuOpen: Bool = false
    @AppStorage(ClawixPersistentSurfaceKeys.sidebarViewMode, store: SidebarPrefs.store)
    private var viewModeRaw: String = SidebarViewMode.grouped.rawValue
    @AppStorage(ClawixPersistentSurfaceKeys.projectSortMode, store: SidebarPrefs.store)
    private var projectSortModeRaw: String = ProjectSortMode.recent.rawValue
    @State private var pinnedExpanded: Bool = SidebarPrefs.bool(forKey: ClawixPersistentSurfaceKeys.sidebarPinnedExpanded, default: true)
    @State private var pinnedFilterMenuOpen: Bool = false
    /// Comma-separated list of disabled pinned-filter tokens. UUIDs identify
    /// projects; the literal `__none__` represents the implicit "no project"
    /// bucket. Persisted as a single string so the existing `SidebarPrefs`
    /// `UserDefaults` suite can hold it without a custom codec.
    @AppStorage(ClawixPersistentSurfaceKeys.sidebarPinnedFilterDisabled, store: SidebarPrefs.store)
    private var pinnedFilterDisabledRaw: String = ""
    /// Mirror of `pinnedFilterDisabledRaw` for the chronological "All chats"
    /// list. Same comma-separated UUID + `__none__` sentinel format. Edited
    /// from inside the Organize popup's "Filter > By project" submenu.
    @AppStorage(ClawixPersistentSurfaceKeys.sidebarChronoFilterDisabled, store: SidebarPrefs.store)
    private var chronoFilterDisabledRaw: String = ""
    @State private var chronoExpanded: Bool = SidebarPrefs.bool(forKey: ClawixPersistentSurfaceKeys.sidebarChronoExpanded, default: true)
    @State private var noProjectExpanded: Bool = SidebarPrefs.bool(forKey: ClawixPersistentSurfaceKeys.sidebarNoProjectExpanded, default: true)
    @State private var projectsExpanded: Bool = SidebarPrefs.bool(forKey: ClawixPersistentSurfaceKeys.sidebarProjectsExpanded, default: true)
    @State private var archivedExpanded: Bool = SidebarPrefs.bool(forKey: ClawixPersistentSurfaceKeys.sidebarArchivedExpanded, default: false)
    @State private var toolsExpanded: Bool = SidebarPrefs.bool(forKey: ClawixPersistentSurfaceKeys.sidebarToolsExpanded, default: true)
    /// Master switch for the Apps surface. Mirrors the Settings toggle
    /// that lives on `SidebarPrefs.store`; defaults on for new users.
    @AppStorage(ClawixPersistentSurfaceKeys.appsFeatureEnabled, store: SidebarPrefs.store)
    private var appsFeatureEnabled: Bool = true
    /// Custom order of tools, persisted as a comma-separated list of
    /// catalog ids. Empty string means "use the catalog's natural order".
    /// New tools added to the catalog in future releases append at the
    /// end of the saved order on first launch.
    @AppStorage(ClawixPersistentSurfaceKeys.sidebarToolsOrder, store: SidebarPrefs.store)
    private var toolsOrderRaw: String = ""
    /// Hidden tools, persisted as a comma-separated list of catalog ids.
    /// Toggled from the section's filter popup; tools in this set are
    /// dropped from the rendered list but stay in the saved order so
    /// re-enabling them restores their previous position.
    @AppStorage(ClawixPersistentSurfaceKeys.sidebarToolsHidden, store: SidebarPrefs.store)
    private var toolsHiddenRaw: String = ""
    @State private var toolsFilterMenuOpen: Bool = false
    @State private var chronoLimit: Int = 100

    init(appState: AppState) {
        self.appState = appState
        _sidebarStore = StateObject(wrappedValue: SidebarStore(appState: appState))
    }

    private var viewMode: SidebarViewMode {
        SidebarViewMode(rawValue: viewModeRaw) ?? .grouped
    }

    private var projectSortMode: ProjectSortMode {
        ProjectSortMode(rawValue: projectSortModeRaw) ?? .recent
    }

    private func recentChatCallbacks(for chat: Chat, archived: Bool) -> RecentChatRowCallbacks {
        makeRecentChatCallbacks(appState: appState, chat: chat, archived: archived)
    }

    /// One project row inside the sidebar's grouped view: the existing
    /// `ChatDropTarget` (so chats can be dragged onto a project to be
    /// reassigned) wrapping a `ProjectAccordion`. Extracted so both the
    /// `LazyVStack` (regular sort modes) and `ProjectReorderableList`
    /// (custom sort mode) call sites render identical content.
    @ViewBuilder
    private func projectRow(
        _ project: Project,
        snapshot: SidebarSnapshot,
        currentChatId: UUID?
    ) -> some View {
        ChatDropTarget { droppedId in
            appState.moveChatToProject(chatId: droppedId, projectId: project.id)
            return true
        } content: {
            ProjectAccordion(
                project: project,
                expanded: expandedProjects.contains(project.id),
                chats: snapshot.byProject[project.id] ?? [],
                showingExtended: projectsShowingExtended.contains(project.id),
                onToggle: {
                    if expandedProjects.contains(project.id) {
                        expandedProjects.remove(project.id)
                        // Re-collapsing a project resets the extended
                        // 10-chat slice so the next open lands back on
                        // the 5-chat preview, per design.
                        projectsShowingExtended.remove(project.id)
                    } else {
                        expandedProjects.insert(project.id)
                        appState.requestExpandedProjectRefresh(project)
                    }
                },
                onMenuToggle: {
                    projectMenuOpenId = projectMenuOpenId == project.id ? nil : project.id
                },
                onNewChat: {
                    appState.startNewChat(in: project)
                },
                onShowMore: {
                    let pid = project.id
                    withAnimation(.easeOut(duration: 0.22)) {
                        _ = projectsShowingExtended.insert(pid)
                    }
                },
                onViewAll: {
                    appState.searchScopedProjectId = project.id
                    appState.currentRoute = .search
                },
                menuOpen: projectMenuOpenId == project.id,
                selectedChatId: currentChatId,
                chatCallbacks: { recentChatCallbacks(for: $0, archived: false) }
            )
            .equatable()
            .onAppear {
                appState.requestVisibleProjectRefresh(project)
            }
            .onDisappear {
                if !expandedProjects.contains(project.id) {
                    appState.cancelProjectRefresh(project)
                }
            }
        }
    }

    private var selectedChatId: UUID? {
        if case let .chat(id) = sidebarStore.snapshot.currentRoute { return id }
        return nil
    }

    @ViewBuilder
    private func sidebarScrollContent(snapshot: SidebarSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if flags.isVisible(.secrets) {
                toolsSection
            }

            if flags.isVisible(.agents) {
                AgentsSidebarSection()
            }

            if appsFeatureEnabled && flags.isVisible(.apps) {
                AppsSidebarSection(appsStore: .shared)
            }

            if flags.isVisible(.design) {
                DesignSidebarSection()
            }

            if flags.isVisible(.life) {
                LifeSidebarSection()
            }

            if !snapshot.pinned.isEmpty {
                let pinnedSources = snapshot.pinnedFilterSources
                let visiblePinned = applyPinnedFilter(to: snapshot.pinned, sources: pinnedSources)
                let canFilterPinned = pinnedSources.count >= 2
                BasicSectionHeader(
                    title: "Pinned",
                    expanded: $pinnedExpanded,
                    leadingIcon: AnyView(PinIcon(size: 15.0, lineWidth: 1.5)),
                    trailingIcon: canFilterPinned ? AnyView(pinnedFilterButton) : nil,
                    trailingForceVisible: pinnedFilterMenuOpen
                )
                SidebarAccordion(
                    expanded: pinnedExpanded,
                    targetHeight: visiblePinned.isEmpty
                        ? 26 + SidebarRowMetrics.sectionEdgePadding
                        : CGFloat(visiblePinned.count) * 35
                            + SidebarRowMetrics.sectionEdgePadding
                ) {
                    // Populated case: `PinnedReorderableList.trailingSlotZone`
                    // already ends with a `sectionEdgePadding`-tall strip that
                    // provides the bottom gap and the drop-at-end target, so
                    // we don't add a parent spacer there. The empty case has
                    // no list, so we add the spacer manually to match the
                    // bottom gap every other closable section shows.
                    if visiblePinned.isEmpty {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            Text(UserFacingEmptyState.pinnedChatsFiltered.message)
                                .font(BodyFont.system(size: 13.5, wght: 500))
                                .foregroundColor(Color.gray(light: 0.54, dark: 0.40))
                                .padding(.leading, 34)
                                .padding(.vertical, 4)
                            Color.clear.frame(height: SidebarRowMetrics.sectionEdgePadding)
                        }
                    } else {
                        PinnedReorderableList(
                            appState: appState,
                            pinned: visiblePinned,
                            selectedChatId: selectedChatId
                        )
                        .equatable()
                        .padding(.leading, 8)
                        .padding(.trailing, 0)
                    }
                }
            }

            if viewMode == .chronological {
                chronoHeader
                    .padding(.leading, 16)
                    .padding(.trailing, 9)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                    .sidebarHover { projectsHeaderHovered = $0 }
                let visibleChrono = applyChronoFilter(to: snapshot.chrono, sources: snapshot.chronoFilterSources)
                let chronoCount = min(visibleChrono.count, chronoLimit)
                let chronoFilterActive = !effectiveDisabledTokens(
                    chronoFilterDisabled,
                    sources: snapshot.chronoFilterSources
                ).isEmpty
                let showEmptyState = visibleChrono.isEmpty
                SidebarAccordion(
                    expanded: chronoExpanded,
                    targetHeight: showEmptyState
                        ? 26 + SidebarRowMetrics.sectionEdgePadding
                        : SidebarRowMetrics.recentChats(count: chronoCount)
                            + SidebarRowMetrics.sectionEdgePadding
                ) {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            if showEmptyState {
                                Text((chronoFilterActive && !snapshot.chrono.isEmpty
                                      ? UserFacingEmptyState.chatsFiltered
                                      : UserFacingEmptyState.chats).message)
                                    .font(BodyFont.system(size: 13.5, wght: 500))
                                    .foregroundColor(Color.gray(light: 0.54, dark: 0.40))
                                    .padding(.leading, 34)
                                    .padding(.vertical, 4)
                            } else {
                                let currentChatId = selectedChatId
                                ForEach(visibleChrono.prefix(chronoLimit), id: \.id) { chat in
                                    RecentChatRow(
                                        chat: chat,
                                        isSelected: currentChatId == chat.id,
                                        leadingIcon: .pinOnHover,
                                        callbacks: recentChatCallbacks(for: chat, archived: false)
                                    )
                                    .equatable()
                                }
                            }
                        }
                        .padding(.leading, 8)
                        if !showEmptyState {
                            Color.clear.frame(height: SidebarRowMetrics.sectionEdgePadding)
                        }
                    }
                }
            } else {
                let projectlessChats = snapshot.projectless
                if !projectlessChats.isEmpty {
                    sectionHeader(
                        "Chats",
                        expanded: $noProjectExpanded,
                        leadingIcon: AnyView(
                            LucideIcon(.messageCircle, size: 16)
                        )
                    )
                    SidebarAccordion(
                        expanded: noProjectExpanded,
                        targetHeight: SidebarRowMetrics.recentChats(count: projectlessChats.count)
                            + SidebarRowMetrics.sectionEdgePadding
                    ) {
                        let currentChatId = selectedChatId
                        VStack(alignment: .leading, spacing: 0) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(projectlessChats) { chat in
                                    RecentChatRow(
                                        chat: chat,
                                        isSelected: currentChatId == chat.id,
                                        leadingIcon: .pinOnHover,
                                        callbacks: recentChatCallbacks(for: chat, archived: false)
                                    )
                                    .equatable()
                                }
                            }
                            .padding(.leading, 8)
                            Color.clear.frame(height: SidebarRowMetrics.sectionEdgePadding)
                        }
                    }
                }

                projectsHeader
                    .padding(.leading, 16)
                    .padding(.trailing, 9)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                    .sidebarHover { projectsHeaderHovered = $0 }

                // Projects list. We add/remove the whole subtree when
                // toggling. Wrapping in `ExpandableContainer` collapses the
                // section to 0pt on first layout: its measurement twin sees
                // each `ProjectAccordion` clip its inner `SmoothAccordion`
                // to height 0 while collapsed, so the height preference
                // arrives as 0 and never recovers.
                if projectsExpanded {
                    let currentChatId = selectedChatId
                    let projectsList = snapshot.sortedProjects(for: projectSortMode)
                    // Same pattern as every other collapsible section: render
                    // `sectionEdgePadding` as a real `Color.clear` spacer at
                    // the end of the accordion's content. `SidebarAccordion`
                    // takes `max(target, measured)` for the frame, so the
                    // visible bottom gap is governed by the content's
                    // intrinsic size — which always includes the spacer —
                    // rather than by `targetHeight` overshoot. Earlier this
                    // section relied on overshoot to "produce" the buffer
                    // and the row-height estimate (28pt) was too low vs the
                    // actual ~35pt rows; `measured > target` ate the buffer
                    // entirely, so Projects appeared glued to Archived
                    // while Pinned/Chats had a generous gap.
                    let projectRowHeightEstimate: CGFloat = 28
                    let projectsListHeightEstimate = CGFloat(projectsList.count) * projectRowHeightEstimate
                        + CGFloat(max(projectsList.count - 1, 0)) * 4
                    SidebarAccordion(
                        expanded: true,
                        targetHeight: projectsListHeightEstimate
                            + SidebarRowMetrics.sectionEdgePadding
                    ) {
                        VStack(alignment: .leading, spacing: 0) {
                            Group {
                                if projectSortMode == .custom {
                                    // `ProjectReorderableList` adds drag-and-drop
                                    // gap zones between every row and persists the
                                    // resulting order via `appState.reorderProject`.
                                    // It uses a non-lazy `VStack` because measuring
                                    // row frames for the drag chip needs every row
                                    // to be in the layout tree.
                                    ProjectReorderableList(
                                        appState: appState,
                                        projects: projectsList
                                    ) { project in
                                        projectRow(
                                            project,
                                            snapshot: snapshot,
                                            currentChatId: currentChatId
                                        )
                                    }
                                } else {
                                    // `LazyVStack` instead of `VStack` so accordion
                                    // bodies for projects scrolled out of view never
                                    // instantiate. Visible projects still re-evaluate
                                    // normally; the saving is the long tail of
                                    // off-screen ones (~70-90 out of ~100 in a
                                    // typical sidebar).
                                    LazyVStack(alignment: .leading, spacing: 0) {
                                        ForEach(projectsList) { project in
                                            projectRow(
                                                project,
                                                snapshot: snapshot,
                                                currentChatId: currentChatId
                                            )
                                        }
                                    }
                                }
                            }
                            .padding(.leading, 8)
                            // Only the alphabetical (LazyVStack) path needs an
                            // explicit trailing spacer; in `.custom` mode
                            // `ProjectReorderableList.trailingSlotZone` already
                            // ends with a `sectionEdgePadding` strip that
                            // doubles as the section gap. Adding a parent
                            // spacer in custom mode would stack on top of that
                            // strip and bloat the gap.
                            if projectSortMode != .custom {
                                Color.clear.frame(height: SidebarRowMetrics.sectionEdgePadding)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            archivedSection
        }
        .padding(.bottom, 10)
        .onChange(of: pinnedExpanded) { _, v in SidebarPrefs.store.set(v, forKey: ClawixPersistentSurfaceKeys.sidebarPinnedExpanded) }
        .onChange(of: chronoExpanded) { _, v in SidebarPrefs.store.set(v, forKey: ClawixPersistentSurfaceKeys.sidebarChronoExpanded) }
        .onChange(of: noProjectExpanded) { _, v in SidebarPrefs.store.set(v, forKey: ClawixPersistentSurfaceKeys.sidebarNoProjectExpanded) }
        .onChange(of: projectsExpanded) { _, v in
            SidebarPrefs.store.set(v, forKey: ClawixPersistentSurfaceKeys.sidebarProjectsExpanded)
            if v { Task { await appState.loadCanonicalProjectsIfNeeded() } }
        }
        .onChange(of: archivedExpanded) { _, v in
            SidebarPrefs.store.set(v, forKey: ClawixPersistentSurfaceKeys.sidebarArchivedExpanded)
            if v { Task { await appState.loadArchivedChats() } }
        }
        .onChange(of: toolsExpanded) { _, v in SidebarPrefs.store.set(v, forKey: ClawixPersistentSurfaceKeys.sidebarToolsExpanded) }
        .task {
            if archivedExpanded { await appState.loadArchivedChats() }
        }
    }

    /// Sentinel token used inside `pinnedFilterDisabledRaw` to represent
    /// pinned chats with no associated project. Distinct from any UUID
    /// string so it can coexist with project ids in the same set.
    static let pinnedFilterNoProjectToken = "__none__"

    private var pinnedFilterDisabled: Set<String> {
        let parts = pinnedFilterDisabledRaw.split(separator: ",").map(String.init)
        return Set(parts.filter { !$0.isEmpty })
    }

    private func setPinnedFilterDisabled(_ next: Set<String>) {
        pinnedFilterDisabledRaw = next.sorted().joined(separator: ",")
    }

    /// Drops chats whose source bucket is in the disabled set. Empty set
    /// short-circuits to the original list so the renderer's hot path
    /// stays cheap when no filter is active.
    private func applyPinnedFilter(to pinned: [Chat], sources: [PinnedFilterSource]) -> [Chat] {
        let disabled = effectiveDisabledTokens(
            pinnedFilterDisabled,
            sources: sources
        )
        guard !disabled.isEmpty else { return pinned }
        return pinned.filter { chat in
            if let pid = chat.projectId {
                return !disabled.contains(pid.uuidString)
            }
            return !disabled.contains(Self.pinnedFilterNoProjectToken)
        }
    }

    /// Tools the user has hidden via the filter popup. Stored as a
    /// comma-separated string of catalog ids inside
    /// `toolsHiddenRaw` so the existing `SidebarPrefs` UserDefaults
    /// suite holds it without a custom codec.
    private var toolsHidden: Set<String> {
        let parts = toolsHiddenRaw.split(separator: ",").map(String.init)
        return Set(parts.filter { !$0.isEmpty })
    }

    private func setToolsHidden(_ next: Set<String>) {
        toolsHiddenRaw = next.sorted().joined(separator: ",")
    }

    /// Catalog entries laid out in the user's custom order. New tools
    /// (i.e. entries in the catalog whose id isn't in the saved order)
    /// append at the end in catalog order, so adding a new tool in a
    /// future release lands it predictably without erasing the user's
    /// arrangement of the existing ones.
    private var orderedTools: [SidebarToolEntry] {
        let saved = toolsOrderRaw.split(separator: ",").map(String.init)
        var seen: Set<String> = []
        var result: [SidebarToolEntry] = []
        for id in saved {
            guard !seen.contains(id), let entry = SidebarToolsCatalog.entry(byId: id) else { continue }
            result.append(entry)
            seen.insert(id)
        }
        for entry in SidebarToolsCatalog.entries where !seen.contains(entry.id) {
            result.append(entry)
        }
        return result
    }

    private var visibleTools: [SidebarToolEntry] {
        let hidden = toolsHidden
        return orderedTools.filter { entry in
            if hidden.contains(entry.id) { return false }
            if let feature = SidebarToolsCatalog.gatedFeature(for: entry.id),
               !flags.isVisible(feature) {
                return false
            }
            return true
        }
    }

    /// Persists a reorder of the tools list. `beforeId == nil` drops the
    /// tool at the end. Operates on the FULL ordered list (including
    /// hidden tools) so toggling a tool's visibility doesn't lose its
    /// position in the user's arrangement.
    fileprivate func reorderTools(toolId: String, beforeId: String?) {
        var current = orderedTools.map(\.id)
        current.removeAll { $0 == toolId }
        if let beforeId, let idx = current.firstIndex(of: beforeId) {
            current.insert(toolId, at: idx)
        } else {
            current.append(toolId)
        }
        toolsOrderRaw = current.joined(separator: ",")
    }

    /// Funnel button anchoring `ToolsFilterPopup`. Mirrors
    /// `pinnedFilterButton` so both filter affordances share the same
    /// visual language and animation.
    private var toolsFilterButton: some View {
        HeaderHoverIcon(tooltip: "Show or hide tools") {
            toolsFilterMenuOpen.toggle()
        } label: { color in
            OrganizeFunnelIcon()
                .foregroundColor(color)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .anchorPreference(key: ToolsFilterAnchorKey.self, value: .bounds) { anchor in
            toolsFilterMenuOpen ? anchor : nil
        }
    }

    /// Funnel button anchoring `PinnedFilterPopup`. Same icon shape as
    /// the `Organize` button on Projects/All chats so the two filter
    /// affordances share the same visual language across the sidebar.
    private var pinnedFilterButton: some View {
        HeaderHoverIcon(tooltip: "Filter pinned by project") {
            pinnedFilterMenuOpen.toggle()
        } label: { color in
            OrganizeFunnelIcon()
                .foregroundColor(color)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .anchorPreference(key: PinnedFilterAnchorKey.self, value: .bounds) { anchor in
            pinnedFilterMenuOpen ? anchor : nil
        }
    }

    private var chronoFilterDisabled: Set<String> {
        let parts = chronoFilterDisabledRaw.split(separator: ",").map(String.init)
        return Set(parts.filter { !$0.isEmpty })
    }

    private func setChronoFilterDisabled(_ next: Set<String>) {
        chronoFilterDisabledRaw = next.sorted().joined(separator: ",")
    }

    private func applyChronoFilter(to chrono: [Chat], sources: [PinnedFilterSource]) -> [Chat] {
        let disabled = effectiveDisabledTokens(
            chronoFilterDisabled,
            sources: sources
        )
        guard !disabled.isEmpty else { return chrono }
        return chrono.filter { chat in
            if let pid = chat.projectId {
                return !disabled.contains(pid.uuidString)
            }
            return !disabled.contains(Self.pinnedFilterNoProjectToken)
        }
    }

    private func effectiveDisabledTokens(_ disabled: Set<String>, sources: [PinnedFilterSource]) -> Set<String> {
        guard !disabled.isEmpty, !sources.isEmpty else { return disabled }
        let available = Set(sources.map(\.token))
        return available.isSubset(of: disabled) ? [] : disabled
    }

    /// Always-visible section so users learn that archived chats land
    /// here. Lazy-fetches the list the first time it's expanded; the
    /// runtime filter `archived: true` guarantees these chats never
    /// also appear in the pinned / project / chronological lists.
    @ViewBuilder
    private var archivedSection: some View {
        sectionHeader(
            "Archived",
            expanded: $archivedExpanded,
            leadingIcon: AnyView(ArchiveIcon(size: 16.5, lineWidth: 1.28))
        )
        SidebarAccordion(
            expanded: archivedExpanded,
            targetHeight: sidebarStore.snapshot.archived.isEmpty
                ? 26
                : SidebarRowMetrics.recentChats(count: sidebarStore.snapshot.archived.count)
                    + SidebarRowMetrics.sectionEdgePadding
        ) {
                        VStack(alignment: .leading, spacing: 0) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                    if sidebarStore.snapshot.archived.isEmpty {
                        HStack(spacing: 6) {
                            if sidebarStore.snapshot.archivedLoading {
                                SidebarChatRowSpinner()
                                    .frame(width: 9, height: 9)
                            }
                            Text(sidebarStore.snapshot.archivedLoading ? "Loading…" : "No archived chats")
                                .font(BodyFont.system(size: 13.5, wght: 500))
                                .foregroundColor(Color.gray(light: 0.54, dark: 0.40))
                        }
                        .padding(.leading, 34)
                        .padding(.vertical, 4)
                    } else {
                        let currentChatId = selectedChatId
                        ForEach(sidebarStore.snapshot.archived) { chat in
                            RecentChatRow(
                                chat: chat,
                                isSelected: currentChatId == chat.id,
                                leadingIcon: .unarchive,
                                archivedRow: true,
                                callbacks: recentChatCallbacks(for: chat, archived: true)
                            )
                            .equatable()
                        }
                    }
                }
                .padding(.leading, 8)
                if !sidebarStore.snapshot.archived.isEmpty {
                    Color.clear.frame(height: SidebarRowMetrics.sectionEdgePadding)
                }
            }
        }
    }

    /// Tools section: top-level entries to feature areas other than chat.
    /// The header is collapsible like the rest of the sidebar and exposes
    /// a per-tool visibility filter on hover (mirrors the Pinned section's
    /// funnel button). Rows are drag-reorderable; their order persists via
    /// `toolsOrderRaw`.
    @ViewBuilder
    private var toolsSection: some View {
        BasicSectionHeader(
            title: "Tools",
            expanded: $toolsExpanded,
            leadingIcon: AnyView(WrenchLineIcon(size: 18)),
            trailingIcon: SidebarToolsCatalog.entries.count >= 2 ? AnyView(toolsFilterButton) : nil,
            trailingForceVisible: toolsFilterMenuOpen
        )
        SidebarAccordion(
            expanded: toolsExpanded,
            targetHeight: visibleTools.isEmpty
                ? 26 + SidebarRowMetrics.sectionEdgePadding
                : CGFloat(visibleTools.count) * ToolsReorderableList.rowSlotHeight
                    + SidebarRowMetrics.sectionEdgePadding
        ) {
            toolsAccordionContent
        }
    }

    @ViewBuilder
    private var toolsAccordionContent: some View {
        let visible = visibleTools
        if visible.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(UserFacingEmptyState.tools.message)
                    .font(BodyFont.system(size: 13.5, wght: 500))
                    .foregroundColor(Color.gray(light: 0.54, dark: 0.40))
                    .padding(.leading, 34)
                    .padding(.vertical, 4)
                Color.clear.frame(height: SidebarRowMetrics.sectionEdgePadding)
            }
        } else {
            ToolsReorderableList(
                tools: visible,
                selectedRoute: sidebarStore.snapshot.currentRoute,
                onSelect: { route in appState.navigate(to: route) },
                onReorder: { toolId, beforeId in
                    reorderTools(toolId: toolId, beforeId: beforeId)
                }
            )
            .padding(.leading, 8)
        }
    }

    var body: some View {
        LaunchMilestones.mark(.firstSidebarPaint)
        RenderProbe.tick("SidebarView")
        let sidebarSnapshot = sidebarStore.snapshot
        return ZStack(alignment: .bottomLeading) {
            VStack(spacing: 0) {
                // Top nav: new chat, search.
                // Plugins and automations rows kept commented out for now.
                VStack(spacing: 1) {
                    SidebarButton(title: "New chat",
                                  icon: "square.and.pencil",
                                  customShape: AnyShape(ComposeIcon()),
                                  customShapeSize: 12.8,
                                  customShapeStroke: 1.25,
                                  route: .home,
                                  actionOnly: true,
                                  shortcut: "⌘N")
                    SidebarButton(title: "Search",
                                  icon: "magnifyingglass",
                                  customShape: AnyShape(SearchIconShape()),
                                  customShapeSize: 13.8,
                                  customShapeStroke: 1.65,
                                  route: .search,
                                  shortcut: "⌘G")
                    if flags.isVisible(.skills) {
                        SidebarButton(title: "Skills",
                                      icon: "puzzle",
                                      route: .skills,
                                      shortcut: "⌘⇧K")
                    }
                    SidebarButton(title: "Network",
                                  icon: "network",
                                  route: .networkControl)
                    if let rescueSummary = RescueRepairStatusSummary(decision: appState.rescueDecision) {
                        RescueRepairSidebarButton(summary: rescueSummary) {
                            appState.openRescueSurface()
                        }
                    }
                    /*
                    SidebarButton(title: "Plugins",
                                  icon: "circle.grid.2x2",
                                  route: .plugins,
                                  shortcut: "⌘⇧E")
                    SidebarButton(title: "Automations",
                                  icon: "clock",
                                  route: .automations,
                                  shortcut: "⌘⇧A")
                    */
                }
                .padding(.leading, 6)
                .padding(.trailing, 22)
                .padding(.top, 6)

                // Legacy mode reserves the scroller's 14pt column outside
                // the clipView, so the gutter only needs the small breathing
                // strip between content and that column.
                ThinScrollView(trailingGutter: 4) {
                    sidebarScrollContent(snapshot: sidebarSnapshot)
                        .background(SidebarScrollStateInstaller().allowsHitTesting(false))
                }

                // Settings button at bottom (toggles account popover above it)
                SettingsBottomButton(open: $settingsPopoverOpen)
                    .padding(.leading, 6)
                    .padding(.trailing, 22)
                    .padding(.bottom, 10)
                    .padding(.top, 6)
            }
            .frame(maxHeight: .infinity)

            // Account popover floats above the settings button
            if settingsPopoverOpen {
                SettingsAccountPopover(isOpen: $settingsPopoverOpen)
                    .background(MenuOutsideClickWatcher(isPresented: $settingsPopoverOpen))
                    .padding(.leading, 6)
                    .padding(.bottom, 50)
                    .transition(.softNudgeSymmetric(y: 4))
            }
        }
        .animation(.easeOut(duration: 0.20), value: settingsPopoverOpen)
        .onChange(of: sidebarSnapshot.currentRoute) { _, _ in
            settingsPopoverOpen = false
        }
        .sheet(item: $projectEditor) { ctx in
            ProjectEditorSheet(context: ctx) { projectEditor = nil }
                .environmentObject(appState)
        }
        .sheet(item: $projectRenameTarget) { project in
            ProjectRenameSheet(project: project) { projectRenameTarget = nil }
                .environmentObject(appState)
        }
        .overlayPreferenceValue(OrganizeMenuAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if organizeMenuOpen, let anchor {
                    let buttonFrame = proxy[anchor]
                    let popupWidth: CGFloat = OrganizeMenuPopup.mainColumnWidth
                    let chronoSources = sidebarSnapshot.chronoFilterSources
                    let chronoDisabled = effectiveDisabledTokens(chronoFilterDisabled, sources: chronoSources)
                    OrganizeMenuPopup(
                        isPresented: $organizeMenuOpen,
                        viewModeRaw: $viewModeRaw,
                        projectSortModeRaw: $projectSortModeRaw,
                        chronoFilterSources: chronoSources,
                        chronoFilterDisabled: chronoDisabled,
                        toggleChronoFilter: { token in
                            var next = chronoFilterDisabled
                            if next.contains(token) {
                                next.remove(token)
                            } else {
                                next.insert(token)
                            }
                            setChronoFilterDisabled(next)
                        },
                        showAllChronoFilter: { setChronoFilterDisabled([]) },
                        hideAllChronoFilter: {
                            setChronoFilterDisabled(Set(chronoSources.map { $0.token }))
                        }
                    )
                    .frame(width: popupWidth)
                    .anchoredPopupPlacement(
                        buttonFrame: buttonFrame,
                        proxy: proxy,
                        horizontal: .trailing()
                    )
                    .transition(.softNudge(y: 4))
                }
            }
            .allowsHitTesting(organizeMenuOpen)
            .animation(MenuStyle.openAnimation, value: organizeMenuOpen)
        }
        .overlayPreferenceValue(NewProjectAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if newProjectMenuOpen, let anchor {
                    let buttonFrame = proxy[anchor]
                    let popupWidth: CGFloat = 244
                    NewProjectPopup(
                        isPresented: $newProjectMenuOpen,
                        onBlank: {
                            newProjectMenuOpen = false
                            startBlankProject()
                        },
                        onPickFolder: {
                            newProjectMenuOpen = false
                            createProjectFromFolder()
                        }
                    )
                    .frame(width: popupWidth)
                    .anchoredPopupPlacement(
                        buttonFrame: buttonFrame,
                        proxy: proxy,
                        horizontal: .trailing()
                    )
                    .transition(.softNudge(y: 4))
                }
            }
            .allowsHitTesting(newProjectMenuOpen)
            .animation(MenuStyle.openAnimation, value: newProjectMenuOpen)
        }
        .overlayPreferenceValue(ProjectMenuAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if let openId = projectMenuOpenId,
                   let project = sidebarSnapshot.project(id: openId),
                   let anchor {
                    let buttonFrame = proxy[anchor]
                    let popupWidth: CGFloat = 268
                    ProjectRowMenuPopup(
                        project: project,
                        isCodexSourced: appState.isCodexSourcedProject(path: project.path),
                        isPresented: Binding(
                            get: { projectMenuOpenId == project.id },
                            set: { if !$0 { projectMenuOpenId = nil } }
                        ),
                        onOpenInFinder: {
                            let path = (project.path as NSString).expandingTildeInPath
                            if !path.isEmpty,
                               FileManager.default.fileExists(atPath: path) {
                                NSWorkspace.shared.open(URL(fileURLWithPath: path))
                            }
                            projectMenuOpenId = nil
                        },
                        onRename: {
                            projectMenuOpenId = nil
                            projectRenameTarget = project
                        },
                        onRemove: {
                            projectMenuOpenId = nil
                            appState.deleteProject(project.id)
                        },
                        onHide: {
                            projectMenuOpenId = nil
                            appState.hideCodexRoot(path: project.path)
                        }
                    )
                    .frame(width: popupWidth)
                    .anchoredPopupPlacement(
                        buttonFrame: buttonFrame,
                        proxy: proxy,
                        horizontal: .trailing(offset: 4),
                        gap: 4
                    )
                    .transition(.softNudge(y: 4))
                }
            }
            .allowsHitTesting(projectMenuOpenId != nil)
            .animation(MenuStyle.openAnimation, value: projectMenuOpenId)
        }
        .overlayPreferenceValue(PinnedFilterAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if pinnedFilterMenuOpen, let anchor {
                    let buttonFrame = proxy[anchor]
                    let popupWidth: CGFloat = 244
                    let sources = sidebarSnapshot.pinnedFilterSources
                    let disabled = effectiveDisabledTokens(pinnedFilterDisabled, sources: sources)
                    PinnedFilterPopup(
                        isPresented: $pinnedFilterMenuOpen,
                        sources: sources,
                        disabled: disabled,
                        toggle: { token in
                            var next = pinnedFilterDisabled
                            if next.contains(token) {
                                next.remove(token)
                            } else {
                                next.insert(token)
                            }
                            setPinnedFilterDisabled(next)
                        },
                        showAll: { setPinnedFilterDisabled([]) },
                        hideAll: { setPinnedFilterDisabled(Set(sources.map { $0.token })) }
                    )
                    .frame(width: popupWidth)
                    .anchoredPopupPlacement(
                        buttonFrame: buttonFrame,
                        proxy: proxy,
                        horizontal: .trailing()
                    )
                    .transition(.softNudge(y: 4))
                }
            }
            .allowsHitTesting(pinnedFilterMenuOpen)
            .animation(MenuStyle.openAnimation, value: pinnedFilterMenuOpen)
        }
        .overlayPreferenceValue(ToolsFilterAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if toolsFilterMenuOpen, let anchor {
                    let buttonFrame = proxy[anchor]
                    let popupWidth: CGFloat = 244
                    let allIds = SidebarToolsCatalog.entries.map(\.id)
                    ToolsFilterPopup(
                        isPresented: $toolsFilterMenuOpen,
                        entries: orderedTools,
                        hidden: toolsHidden,
                        toggle: { id in
                            var next = toolsHidden
                            if next.contains(id) {
                                next.remove(id)
                            } else {
                                next.insert(id)
                            }
                            setToolsHidden(next)
                        },
                        showAll: { setToolsHidden([]) },
                        hideAll: { setToolsHidden(Set(allIds)) }
                    )
                    .frame(width: popupWidth)
                    .anchoredPopupPlacement(
                        buttonFrame: buttonFrame,
                        proxy: proxy,
                        horizontal: .trailing()
                    )
                    .transition(.softNudge(y: 4))
                }
            }
            .allowsHitTesting(toolsFilterMenuOpen)
            .animation(MenuStyle.openAnimation, value: toolsFilterMenuOpen)
        }
    }

    private func sectionHeader(
        _ title: LocalizedStringKey,
        expanded: Binding<Bool>,
        leadingIcon: AnyView? = nil
    ) -> some View {
        BasicSectionHeader(title: title, expanded: expanded, leadingIcon: leadingIcon)
    }

    private var projectsHeader: some View {
        sidebarHeader(title: "Projects",
                      showCollapseAll: true,
                      showNewChat: false,
                      leadingIcon: AnyView(FolderMorphIcon(size: 14.5, progress: 0, lineWidthScale: 1.027)),
                      expanded: $projectsExpanded)
    }

    private var chronoHeader: some View {
        sidebarHeader(title: "All chats",
                      showCollapseAll: false,
                      showAddProject: false,
                      showNewChat: false,
                      leadingIcon: AnyView(
                          LucideIcon(.messageCircle, size: 16)
                      ),
                      expanded: $chronoExpanded)
    }

    @ViewBuilder
    private func sidebarHeader(
        title: LocalizedStringKey,
        showCollapseAll: Bool,
        showAddProject: Bool = true,
        showNewChat: Bool,
        alwaysShow: Bool = false,
        leadingIcon: AnyView? = nil,
        expanded: Binding<Bool>? = nil
    ) -> some View {
        // Fixed-height header. Icons are always laid out (so the row never
        // changes height) and toggled with opacity + hit-testing only.
        // Tapping outside the icon group toggles the section's collapsed
        // state, which is why the whole row is a `.contentShape(Rectangle())`
        // with `.onTapGesture`. Inner icon buttons absorb their own clicks
        // because SwiftUI prefers the innermost gesture handler.
        let iconsVisible = alwaysShow || projectsHeaderHovered || newProjectMenuOpen || organizeMenuOpen
        let toggle: () -> Void = {
            guard let expanded else { return }
            withAnimation(SidebarSection.toggleAnimation) { expanded.wrappedValue.toggle() }
        }
        // Each action icon is laid out in a 22pt slot with 2pt spacing.
        // `organize` is always present; the others are gated by their flags.
        let iconCount = (showCollapseAll ? 1 : 0) + 1 + (showAddProject ? 1 : 0) + (showNewChat ? 1 : 0)
        let iconsWidth = CGFloat(iconCount) * 22 + CGFloat(max(iconCount - 1, 0)) * 2
        // Trailing clearance leaves a 6pt visual gap between the right
        // hairline and the leading edge of the icon group when hovered.
        let trailingClearance: CGFloat = iconsWidth + 6
        HStack(spacing: 4) {
            if let expanded {
                CollapsibleSectionLabel(title: title,
                                        expanded: expanded.wrappedValue,
                                        hovered: projectsHeaderHovered,
                                        trailingIconsActive: iconsVisible,
                                        chevronLeadingPadding: 2,
                                        leadingIcon: leadingIcon,
                                        trailingIconsClearance: trailingClearance)
            } else {
                HStack(spacing: 0) {
                    if let leadingIcon {
                        leadingIcon
                            .foregroundColor(Color.gray(light: 0.27, dark: 0.78))
                            .frame(width: 15, height: 15, alignment: .center)
                            .padding(.trailing, 11)
                    }
                    Text(title)
                        .font(BodyFont.system(size: 13.5, wght: 500))
                        .foregroundColor(Color.gray(light: 0.14, dark: 0.92))
                }
                Spacer()
            }
        }
        .frame(height: 24)
        .contentShape(Rectangle())
        .onTapGesture {
            if expanded != nil { toggle() }
        }
        // Action icons live as a trailing overlay so they don't reserve
        // layout space when invisible: the right hairline inside the
        // label fills the row to its trailing edge, then animates a
        // trailing inset on hover to clear the icons that fade in.
        // Each icon fades in with its own staggered delay so the group
        // cascades after the chevron; on hover-out they all clear at
        // once via the disappear branch of `hoverStaggerFade`.
        .overlay(alignment: .trailing) {
            let firstDelay = SidebarSection.trailingIconsFirstDelay
            let stagger = SidebarSection.trailingIconsStagger
            let collapseAllDelay = firstDelay
            let organizeSlot = (showCollapseAll ? 1 : 0)
            let newProjectSlot = organizeSlot + 1
            let newChatSlot = newProjectSlot + (showAddProject ? 1 : 0)
            let organizeDelay = firstDelay + Double(organizeSlot) * stagger
            let newProjectDelay = firstDelay + Double(newProjectSlot) * stagger
            let newChatDelay = firstDelay + Double(newChatSlot) * stagger
            HStack(spacing: 2) {
                if showCollapseAll {
                    let allCollapsed = expandedProjects.isEmpty
                    HeaderHoverIcon(
                        tooltip: allCollapsed ? "Expand all" : "Collapse all"
                    ) {
                        toggleAllProjectsCollapsed()
                    } label: { color in
                        CornerBracketsIcon(
                            size: 12,
                            variant: allCollapsed ? .expanded : .collapsed,
                            lineWidth: 1.4
                        )
                        .foregroundColor(color)
                        .frame(width: 22, height: 22)
                    }
                    .hoverStaggerFade(visible: iconsVisible, appearDelay: collapseAllDelay)
                }
                organizeButton
                    .hoverStaggerFade(visible: iconsVisible, appearDelay: organizeDelay)
                if showAddProject {
                    HeaderHoverIcon(tooltip: "Add new project") {
                        newProjectMenuOpen.toggle()
                    } label: { color in
                        FolderAddIcon(size: 15.5, plusStrokeWidth: 1.4)
                            .foregroundColor(color)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .anchorPreference(key: NewProjectAnchorKey.self, value: .bounds) { $0 }
                    .hoverStaggerFade(visible: iconsVisible, appearDelay: newProjectDelay)
                }
                if showNewChat {
                    HeaderHoverIcon(tooltip: "New chat") {
                        appState.currentRoute = .home
                    } label: { color in
                        ComposeIcon()
                            .stroke(color,
                                    style: StrokeStyle(lineWidth: 1.0, lineCap: .round, lineJoin: .round))
                            .frame(width: 11.2, height: 11.2)
                            .frame(width: 22, height: 22)
                    }
                    .hoverStaggerFade(visible: iconsVisible, appearDelay: newChatDelay)
                }
            }
            .disabled(!iconsVisible)
        }
    }

    /// Funnel button that anchors `OrganizeMenuPopup` and uses the
    /// project-wide dropdown chrome.
    private var organizeButton: some View {
        HeaderHoverIcon(tooltip: "Filter, sort, and organize chats") {
            organizeMenuOpen.toggle()
        } label: { color in
            OrganizeFunnelIcon()
                .foregroundColor(color)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .anchorPreference(key: OrganizeMenuAnchorKey.self, value: .bounds) { anchor in
            organizeMenuOpen ? anchor : nil
        }
    }

    // MARK: - Header actions

    private func toggleAllProjectsCollapsed() {
        withAnimation(.easeOut(duration: 0.28)) {
            if expandedProjects.isEmpty {
                // Expand all
                expandedProjects = Set(sidebarStore.snapshot.projects.map { $0.id })
                for project in sidebarStore.snapshot.projects {
                    appState.requestExpandedProjectRefresh(project)
                }
            } else {
                for project in sidebarStore.snapshot.projects where expandedProjects.contains(project.id) {
                    appState.cancelProjectRefresh(project)
                }
                expandedProjects.removeAll()
            }
        }
    }

    private func startBlankProject() {
        let project = appState.createProject(
            name: String(localized: "New project", bundle: AppLocale.packageBundle),
            path: ""
        )
        appState.selectedProject = project
        appState.currentRoute = .home
        expandedProjects.insert(project.id)
    }

    private func createProjectFromFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Select", bundle: AppLocale.packageBundle)
        if panel.runModal() == .OK, let url = panel.url {
            let project = appState.createProject(
                name: url.lastPathComponent,
                path: url.path
            )
            appState.selectedProject = project
            appState.currentRoute = .home
            expandedProjects.insert(project.id)
        }
    }
}
