import SwiftUI
import Combine
import AppKit
import ClawixCore
import ClawixEngine


private let daemonBridgePort: UInt16 = 24080

// MARK: - AppState

@MainActor
final class AppState: ObservableObject {
    /// Weak back-reference to the live main-window state, set from
    /// `ClawixApp.init`. Lets app-lifecycle code (e.g. the quit guard in
    /// `AppDelegate`) ask about in-flight work without threading the
    /// object through AppKit. Never assigned for the sidebar-tool roles.
    static weak var shared: AppState?

    /// True while at least one local chat still has an unfinished turn
    /// (the agent is mid-response). Drives the confirm-before-quit guard
    /// so a `⌘Q` during an active turn doesn't silently drop the work.
    var hasActiveLocalWork: Bool {
        chats.contains { $0.hasActiveTurn }
    }

    @Published var currentRoute: SidebarRoute = .home {
        didSet {
            let visibleRoute = currentRoute.visibleRoute(isVisible: FeatureFlags.shared.isVisible)
            if visibleRoute != currentRoute {
                currentRoute = visibleRoute
                return
            }
            clearUnreadIfChatRoute()
            if case let .chat(id) = currentRoute {
                daemonBridgeClient?.openSession(id)
                scheduleChatRuntimeDemandIfReady(chatId: id)
            }
            persistLaunchRoute()
            // Scope only outlives the search popup itself; once the user
            // navigates anywhere else the chip gets cleared so the next
            // open lands on the unscoped pinned-chats view.
            if currentRoute != .search, searchScopedProjectId != nil {
                searchScopedProjectId = nil
            }
            // ⌘F binds to the chat that owned it; navigating away closes
            // the bar so the highlights don't bleed into the next view.
            if isFindBarOpen {
                if case .chat(let id) = currentRoute, id == findChatId {
                    // Same chat, keep the bar.
                } else {
                    closeFindBar()
                }
            }
        }
    }
    @Published var driveQuickUploadRequestID: UUID? = nil

    @Published var searchQuery: String = ""
    @Published var searchResults: [String] = []
    @Published var searchResultRoutes: [String: SidebarRoute] = [:]
    /// In-page Find (⌘F) state. Operates on the chat that owns the
    /// current view; closes when the user navigates anywhere else.
    @Published var isFindBarOpen: Bool = false
    @Published var findQuery: String = ""
    @Published var isFinding: Bool = false
    @Published var findMatches: [FindMatch] = []
    @Published var currentFindIndex: Int = 0
    @Published var findChatId: UUID? = nil
    var findDebounce: DispatchWorkItem?
    @Published var chats: [Chat] = [] {
        didSet {
            guard !syncingLegacyChatsFromStore else { return }
            chatStore.replaceActive(with: chats)
            stripLegacyTranscriptPayloadsIfNeeded()
        }
    }
    let chatStore = ChatStore()
    var syncingLegacyChatsFromStore = false
    /// Manual ordering for pinned chats. Persisted via metadata as the
    /// order of `pinnedThreadIds`. The sidebar sorts pinned rows by the
    /// index a chat appears at here; chats not in this array fall to the
    /// bottom of the pinned section.
    @Published var pinnedOrder: [UUID] = []
    /// Chats the runtime has marked as archived. Kept separate from
    /// `chats` so the regular sidebar lists never need to filter on
    /// `isArchived`. Populated lazily the first time the sidebar's
    /// archived section is expanded, plus optimistically appended when
    /// the user archives a chat from inside the app.
    @Published var archivedChats: [Chat] = [] {
        didSet {
            guard !syncingLegacyChatsFromStore else { return }
            chatStore.replaceArchived(with: archivedChats)
            stripLegacyTranscriptPayloadsIfNeeded()
        }
    }
    /// True while a `listThreads(archived: true)` request is in flight.
    /// The sidebar shows a spinner inside the section while this is set.
    @Published var archivedLoading: Bool = false
    /// Tracks whether the lazy fetch has succeeded at least once during
    /// this session, so re-expanding the section doesn't re-hit the
    /// runtime. `unarchiveChat` triggers a refetch when the active list
    /// reload completes.
    var archivedLoaded: Bool = false
    /// Cap applied to the sidebar's archived section. The settings page
    /// can surface a larger list if we ever wire it up; the sidebar is
    /// for browsing recent archives, not exhaustive history.
    static let archivedSidebarLimit: Int = 30
    static let startupRecentSessionLimit: Int = 40
    static let startupPinnedSessionLimit: Int = 100
    static let sidebarBootstrapRecentLimit: Int = 200
    let sampleChat: Chat
    let browserSampleChat: Chat
    let computerUseSampleChat: Chat
    @Published var plugins: [Plugin] = []
    @Published var automations: [Automation] = []
    @Published var projects: [Project] = []
    @Published var selectedProject: Project?
    /// Manual ordering of projects for the sidebar's "Custom" sort mode.
    /// IDs not present here fall back to natural order from `projects`.
    /// Persisted via `ProjectOrdersRepository`.
    @Published var manualProjectOrder: [UUID] = []
    /// Currently selected agent for the next composer send. Defaults
    /// to the built-in Codex agent. The composer dropdown writes this;
    /// `ChatView` reads it when minting a new chat. `AgentRuntimeChoice`
    /// below stays as the internal-resolved-runtime representation: the
    /// dropdown still derives runtime + model from the chosen agent.
    @Published var selectedAgentId: String = Agent.defaultCodexId

    @Published var selectedAgentRuntime: AgentRuntimeChoice = .codex {
        didSet {
            guard oldValue != selectedAgentRuntime else { return }
            if selectedAgentRuntime == .opencode, !FeatureFlags.shared.isVisible(.openCode) {
                selectedAgentRuntime = .codex
                return
            }
            if selectedAgentRuntime == .opencode, !selectedModel.contains("/") {
                selectedModel = AgentRuntimeChoice.persistedOpenCodeModel()
            } else if selectedAgentRuntime == .codex, selectedModel.contains("/") {
                selectedModel = "5.5"
            }
            AgentRuntimeChoice.persist(
                runtime: selectedAgentRuntime,
                openCodeModel: openCodeModelSelection
            )
        }
    }
    @Published var selectedModel: String = "5.5" {
        didSet {
            guard oldValue != selectedModel else { return }
            if selectedModel.contains("/"), !FeatureFlags.shared.isVisible(.openCode) {
                selectedModel = "5.5"
                return
            }
            if selectedAgentRuntime == .opencode {
                AgentRuntimeChoice.persist(
                    runtime: selectedAgentRuntime,
                    openCodeModel: openCodeModelSelection
                )
            }
        }
    }
    @Published var selectedIntelligence: IntelligenceLevel = .high
    @Published var selectedSpeed: SpeedLevel = .standard
    @Published var permissionMode: PermissionMode = .defaultPermissions {
        didSet {
            guard oldValue != permissionMode else { return }
            permissionMode.persist()
        }
    }
    @Published var personality: Personality = Personality.loadPersisted() {
        didSet {
            guard oldValue != personality else { return }
            personality.persist()
        }
    }
    /// Central library of Skills. Owns the catalog (built-ins + user
    /// + auto-imported), the active set per scope, and the registered
    /// sync targets. `nil` until `bootstrap()` wires it up so views can
    /// fall back to a local instance during preview-mode rendering.
    @Published var skillsStore: SkillsStore? = nil
    var makeSkillsStore: (_ seedBuiltins: Bool, _ loadMode: SkillsStore.LoadMode) -> SkillsStore = { seedBuiltins, loadMode in
        SkillsStore(seedBuiltins: seedBuiltins, loadMode: loadMode)
    }
    /// Global plan-mode toggle. When on, subsequent turns are sent with
    /// `collaborationMode = "plan"` so the agent surfaces
    /// `item/tool/requestUserInput` instead of acting directly. Toggled by
    /// `/plan`, the composer pill, or the "+" menu row.
    @Published var planMode: Bool = false
    /// Per-chat plan-mode questions awaiting an answer. Set when the
    /// backend sends `item/tool/requestUserInput`; cleared on submit /
    /// dismiss / turn completion. The sidebar surfaces an awaiting-answer
    /// hint while this is non-nil for a chat.
    @Published var pendingPlanQuestions: [UUID: PendingPlanQuestion] = [:]
    /// URL of an image currently being previewed in the fullscreen
    /// viewer. Same overlay used by composer chips and chat bubbles.
    @Published var imagePreviewURL: URL?
    /// Drives the rename sheet from anywhere in the UI (chat-title
    /// ellipsis, sidebar right-click). Setting non-nil presents the sheet;
    /// the sheet clears it on dismiss.
    @Published var pendingRenameChat: Chat?
    /// Drives the global confirmation dialog (destructive actions, writes
    /// to Codex state). Set non-nil to present, the sheet clears it on
    /// dismiss or after the user confirms.
    @Published var pendingConfirmation: ConfirmationRequest?
    /// Composer text + staged attachments + focus token live here so
    /// typing only fires `objectWillChange` on this child object,
    /// leaving AppState's other observers untouched.
    let composer = ComposerState()
    /// Remote Agent Mesh state (paired Macs, allowed workspaces,
    /// outbound jobs in flight). Refreshed lazily from the Settings
    /// page and the composer's "Run on" menu. Initialised in the
    /// init body (not as a default expression) so that calling a
    /// `@MainActor` initialiser does not defer past the rest of the
    /// stored-property setup the rest of init relies on.
    let meshStore: MeshStore
    /// Currently-selected destination for outbound prompts. `.local`
    /// runs through the regular Codex/daemon path. `.peer(nodeId)`
    /// routes through `/v1/mesh/remote-jobs` instead.
    @Published var selectedMeshTarget: MeshTarget = .local {
        didSet {
            reconcileRemoteTargetBridgeDemand()
        }
    }
    @Published var pinnedItems: [PinnedItem] = []
    @Published var isLeftSidebarOpen: Bool = AppState.sidebarDefaults.object(forKey: AppState.leftSidebarOpenKey) as? Bool ?? true
    @Published var isCommandPaletteOpen: Bool = false
    /// When non-nil, the global search popup is currently scoped to
    /// this project. The sidebar's per-project "View all" footer sets
    /// this and routes to `.search` so the same popup the user already
    /// likes (`SearchPopoverOverlay`) doubles as the project's "all
    /// chats" surface, with the project name shown as a removable
    /// filter chip.
    @Published var searchScopedProjectId: UUID? = nil
    /// When `true`, the right sidebar takes over the full width of the
    /// content area (everything to the right of the left sidebar),
    /// completely covering the main view. The persisted column width is
    /// preserved so collapsing brings the panel back to its previous size.
    @Published var isRightSidebarMaximized: Bool = false
    /// One sidebar state per chat (keyed by `Chat.id`). Switching chats
    /// rebinds every consumer of `currentSidebar`/`isRightSidebarOpen` to
    /// the destination chat's entry, so the right column animates to
    /// whatever was open in that chat last (or closes if the chat had no
    /// items).
    @Published var chatSidebars: [UUID: ChatSidebarState] = [:]
    /// Right-sidebar state used on every non-chat route (home / new
    /// conversation, search, plugins, automations, project, settings).
    /// Without this the toggle would no-op outside chats because
    /// `currentSidebar`'s setter has nowhere to attach the state.
    /// Persisted independently from per-chat sidebars so Home browser tabs
    /// survive relaunches without leaking into individual conversations.
    @Published var globalSidebar: ChatSidebarState = .empty
    /// Cross-tab favicon memory keyed by the registrable host. A tab freshly
    /// opened to a host visited before therefore renders its real favicon
    /// from the very first frame instead of cycling through the monogram and
    /// the Google s2 fallback while WKWebView re-extracts the page's
    /// `<link rel="icon">`. Persisted to UserDefaults under
    /// `HostFavicons` so it survives relaunches.
    @Published var hostFavicons: [String: URL] = [:]
    /// One-shot signal consumed by `BrowserView` to reload the active web
    /// view. Set when `openLinkInBrowser` is asked to open a URL already
    /// present in the strip and the user expects the existing tab to refresh
    /// instead of a duplicate opening. The view resets it back to nil after
    /// firing the reload.
    @Published var pendingReloadTabId: UUID?
    /// One-shot command the menu / keyboard shortcuts dispatch toward the
    /// active browser tab. `BrowserView` consumes this via `.onChange`,
    /// translates it to a controller method, and resets it to nil. We use a
    /// counter-tagged value so two consecutive same-action presses (e.g.
    /// Cmd+R twice) still fire as distinct events even if the enum case
    /// matches.
    @Published var pendingBrowserCommand: BrowserCommandRequest?
    /// Tagged signal for the URL field to grab focus and pre-fill with the
    /// full URL. Carries the active tab's id at dispatch time so a stale
    /// view in another tab doesn't hijack the focus.
    @Published var pendingFocusURLBar: BrowserFocusURLBarRequest?
    /// Per-tab "is the WKWebView currently navigating" mirror. The
    /// `BrowserTabController` keeps the source-of-truth as `@Published
    /// isLoading`, but the tab-strip pills live outside that observation
    /// chain, so we forward the bit here so each pill can show a spinner
    /// without needing a reference to the live controller.
    @Published var browserTabsLoading: Set<UUID> = []
    /// Per-web-tab live page background colour sampled from the bottom-left
    /// pixel of each browser webview. Keyed by the web item's id so the
    /// bottom-trailing rounded-corner cutout blends with whatever the
    /// active page is currently painting at that edge.
    @Published var browserPageBackgroundColors: [UUID: Color] = [:]
    @Published var clawixBackendStatus: ClawixService.Status = .idle {
        didSet {
            rescueDecision = RescueRuntimeSignalMapper.decision(
                backendStatus: clawixBackendStatus,
                runtimeHealth: ResourceSampler.latestHealthSnapshot(
                    bridgeReachable: clawixBackendStatus.isRescueBridgeReachable,
                    runtimeCount: clawixBackendStatus.defaultRescueRuntimeCount
                )
            )
        }
    }
    @Published var rescueDecision: RescueSurvivalDecision = RescueSurvivalPolicy.evaluate(signals: [], availableRuntimeCount: 1)
    /// Snapshot of the user's primary/secondary rate-limit windows as
    /// reported by the backend (`account/rateLimits/read` once at boot,
    /// then refreshed by `account/rateLimits/updated`). nil while the
    /// initial fetch is in flight or when the backend declined to answer.
    @Published var rateLimits: RateLimitSnapshot? = nil
    /// Per-bucket rate-limit snapshots keyed by metered `limit_id`
    /// (e.g. "codex", "codex_<model>"). Empty when the backend doesn't
    /// surface a per-bucket view.
    @Published var rateLimitsByLimitId: [String: RateLimitSnapshot] = [:]
    /// Paths whose right-sidebar file viewer is rendering raw text with
    /// line numbers and basic syntax tinting instead of the parsed
    /// markdown body. Toggled from the breadcrumb's ellipsis menu via
    /// "Disable rich view" / "Enable rich view". In-memory only.
    @Published var richViewDisabledPaths: Set<String> = []
    /// Paths whose raw / plain file view (and only raw / plain) wraps
    /// long lines instead of showing a horizontal scroll. Same source
    /// of truth as the breadcrumb's "Enable word wrap" toggle.
    @Published var wordWrapEnabledPaths: Set<String> = []
    /// When true, fenced code blocks rendered in chat messages wrap
    /// long lines so everything is visible without a horizontal scroll.
    /// Toggled from the small wrap button next to each code block's
    /// copy action; the choice is global because the same code is often
    /// quoted across messages.
    @Published var chatCodeBlockWordWrap: Bool = true
    @Published var settingsCategory: SettingsCategory = .general
    let legalSafety = LegalSafetyStore.shared
    /// User-selected interface language. Persisted via UserDefaults
    /// (suite `appPrefsSuite`, key `PreferredLanguage`). Changing
    /// this immediately re-applies the language process-wide
    /// (`AppleLanguages` + `AppLocale.current`) and SwiftUI re-renders
    /// because the root view binds `\.locale` to it.
    @Published var preferredLanguage: AppLanguage = .spanish {
        didSet {
            guard oldValue != preferredLanguage else { return }
            AppLanguage.apply(preferredLanguage)
        }
    }
    /// Cache of resolved `<title>` for URLs the chat surfaces in the
    /// trailing "Website" card. Populated lazily — the card paints with
    /// the URL host until the fetch lands.
    let linkMetadata = LinkMetadataStore()

    @Published var availableModels = ["5.5", "5.4"]
    @Published var otherModels = ["5.4-Mini", "5.3-Pro", "5.3-Pro-Spark", "5.2"]

    let clawixBinary: ClawixBinaryResolution?
    let clawix: ClawixService?
    let auth = BackendAuthCoordinator()
    private var authObserver: AnyCancellable?
    /// Diagnostic only: counts every `objectWillChange` fired by AppState so
    /// `RenderProbe` shows how chatty the publisher is. Each tick on this
    /// counter explains one downstream `SidebarView` invalidation.
    private var willChangeProbe: AnyCancellable?
    /// Bag of per-property publish probes. Each one ticks
    /// `AppState.<propname>` whenever that `@Published` property is set,
    /// so the render log can attribute every `AppState.willChange` to a
    /// specific source.
    private var publishProbes: [AnyCancellable] = []
    /// Most recent auto-reload time. Used to debounce the focus-driven
    /// reload to at most one trigger per second.
    var lastAutoReloadAt: Date?
    var focusReloadObserver: NSObjectProtocol?

    var daemonBridgeClient: DaemonBridgeClient?
    private let localBridgeLauncher: any LocalBridgeHelperLaunching
    private let backgroundBridgeIsActive: @MainActor () -> Bool
    private let backgroundBridgeIsEnabled: @MainActor () -> Bool
    private let makeDaemonBridgeClient: @MainActor (AppState, PairingService) -> DaemonBridgeClient?
    private var bridgeDemandLeases: [UUID: LocalBridgeDemandReason] = [:]
    private var selectedRemoteTargetLease: BridgeDemandLease?

    let databaseProvider: LazyDatabaseProvider
    let projectsRepo = ProjectsRepository()
    let projectOrdersRepo = ProjectOrdersRepository()
    let pinsRepo = PinsRepository()
    let chatProjectsRepo = ChatProjectsRepository()
    let metaRepo = MetaRepository()
    let archivesRepo = ArchivesRepository()
    let hiddenRootsRepo = HiddenRootsRepository()
    var clawJSSessionsCanonicalActive = false
    var clawJSSessionsProjectsLoaded = false
    var clawJSSessionsProjectsLoading = false
    var clawJSSessionsCanonicalLease: ServiceDemandLease?
    /// Persistent cache of the sidebar's last applied state. Used to
    /// paint Pinned + recent chats instantly at launch from local SQLite,
    /// before the runtime bootstraps and paginates the real thread list.
    /// Rewritten at the end of every applyThreads / mergeThreads.
    let snapshotRepo: SnapshotRepository
    private let dummyModeActive: Bool = ProcessInfo.processInfo.environment["CLAWIX_DUMMY_MODE"] == "1"
    /// True when the snapshot cache is active. Disabled while fixtures
    /// are driving the threads list (CLAWIX_THREAD_FIXTURE) so tests
    /// stay deterministic and the snapshot table never sees fixture
    /// data.
    let snapshotEnabled: Bool = (AgentThreadStore.fixtureThreads() == nil
                                         && ProcessInfo.processInfo.environment["CLAWIX_DUMMY_MODE"] != "1")
    var backendState: BackendState = .empty

    /// Resolves user renames and generated titles persisted by Clawix.
    /// Runtime titles arrive from the ClawJS sessions adapter.
    let titlesRepo = SessionTitlesRepository()
    /// Available only when ClawixBinary.resolve() returned a path. If
    /// nil, automatic title generation is silently disabled and
    /// historic sessions without an entry in titlesRepo keep their
    /// firstMessage fallback.
    private let titleGenerator: TitleGenerator?
    /// Chats already considered for post-turn title generation. Prevents
    /// re-firing on every turn of the same chat.
    var titledChatIds: Set<UUID> = []

    /// Per-chat pagination state for the bridge's `loadOlderMessages`
    /// flow. Mirrors the iOS `BridgeStore` model: `oldestKnownId` is the
    /// cursor passed to the next request, `hasMore` is whether the
    /// daemon told us older history exists, `loadingOlder` guards
    /// against duplicate requests when the scroll-up sentinel
    /// re-materializes during fast scrolls. Reset whenever a fresh
    /// `messagesSnapshot` arrives for the chat.
    struct ChatPagination: Equatable {
        var oldestKnownId: String?
        var hasMore: Bool
        var loadingOlder: Bool
    }
    @Published var messagesPaginationByChat: [UUID: ChatPagination] = [:]

    /// Wire mirror of what the daemon (or the on-disk snapshot) last
    /// delivered. This preserves the same `WireSession` / `WireMessage`
    /// shapes the iPhone uses while `chats` remains a summary-only UI
    /// compatibility adapter.
    /// Updated by every `applyDaemon*` and `appendDaemonMessage` path.
    /// Streaming partials are deliberately NOT mirrored here: the on-
    /// disk snapshot only holds settled messages, matching iOS.
    var cachedWireSessions: [WireSession] = []
    var cachedWireMessagesByChat: [String: [WireMessage]] = [:]
    var optimisticUserMessageIdsByChat: [UUID: Set<UUID>] = [:]
    var clawJSSessionsClientFactory: () -> ClawJSSessionsClient = { ClawJSSessionsClient.local() }
    var clawJSAppStateCacheRefresh: () async -> Void = { await ClawJSAppStateCacheSync.refreshFromCanonicalStore() }
    var runtimeThreadPageLoader: ((_ cursor: String?, _ limit: Int) async throws -> ClawixService.ThreadListPage)?
    var agentRuntimeStartTask: Task<Bool, Never>?
    var chatRuntimeDemandTask: Task<Void, Never>?
    var deferredCodexImportTask: Task<Void, Never>?
    var codexRolloutLocator: @Sendable (String) -> URL? = { CodexRolloutLocator.find(threadId: $0) }
    var codexRolloutPathByThreadId: [String: URL] = [:]
    var missingCodexRolloutPathThreadIds: Set<String> = []
    var sessionHistoryHydrationTasks: [UUID: Task<Void, Never>] = [:]
    var sessionHistoryHydrationAttempts = 8
    var sessionHistoryHydrationInitialDelayNanos: UInt64 = 250_000_000
    var projectThreadListLoader: (@MainActor (Project, Int) async throws -> [AgentThreadSummary])?
    /// Drives `SnapshotCache.save` after a quiet 500ms window. Each
    /// call cancels the previous in-flight task; streaming bursts and
    /// rapid chat updates collapse into a single write. The actual IO
    /// runs on a background priority Task so the main thread stays out
    /// of the file-system path entirely.
    var persistTask: Task<Void, Never>?
    var postFirstFramePersistenceStarted = false
    var postFirstFrameFaviconCacheStarted = false
    var appStateCanonicalReconciliationTask: Task<Void, Never>?
    var sidebarSnapshotProjectIDBackfillTask: Task<Void, Never>?
    var loadedProjectSnapshotKeys: Set<String> = []
    /// Per-chat git probes. `git status` can block on large repos or
    /// filesystem state, so chat navigation must never wait on it.
    var gitInspectionTasks: [UUID: Task<Void, Never>] = [:]

    deinit {
        for job in projectRefreshJobs.values {
            job.task?.cancel()
        }
        appStateCanonicalReconciliationTask?.cancel()
        let launcher = localBridgeLauncher
        let client = daemonBridgeClient
        Task { @MainActor in
            launcher.stop()
            client?.disconnect()
        }
    }

    @discardableResult
    func acquireLocalBridge(reason: LocalBridgeDemandReason) -> BridgeDemandLease {
        let lease = BridgeDemandLease(reason: reason, owner: self)
        bridgeDemandLeases[lease.id] = reason
        reconcileBridgeTransport(reason: "acquire:\(reason.rawValue)")
        return lease
    }

    func releaseLocalBridge(_ lease: BridgeDemandLease) {
        releaseLocalBridge(id: lease.id, reason: lease.reason)
    }

    func releaseLocalBridge(id: UUID, reason: LocalBridgeDemandReason) {
        guard bridgeDemandLeases.removeValue(forKey: id) != nil else { return }
        reconcileBridgeTransport(reason: "release:\(reason.rawValue)")
    }

    func reconcileBridgeTransport(reason: String) {
        guard ProcessInfo.processInfo.environment["CLAWIX_BRIDGE_DISABLE"] != "1" else {
            stopDemandBridge(reason: "\(reason):disabled")
            disconnectDaemonBridgeClient()
            return
        }

        let fixtureActive = AgentThreadStore.fixtureThreads() != nil || dummyModeActive
        guard !fixtureActive else {
            stopDemandBridge(reason: "\(reason):fixture")
            disconnectDaemonBridgeClient()
            return
        }

        let pairing = sharedBridgePairingService()
        if backgroundBridgeIsEnabled() {
            stopDemandBridge(reason: "\(reason):background-enabled")
            if backgroundBridgeIsActive() {
                connectDaemonBridgeIfNeeded(pairing: pairing)
                Self.publishPairingForDevMenu(pairing)
            } else {
                disconnectDaemonBridgeClient()
            }
            return
        }

        if !localBridgeLauncher.isRunning, backgroundBridgeIsActive() {
            connectDaemonBridgeIfNeeded(pairing: pairing)
            Self.publishPairingForDevMenu(pairing)
            return
        }

        disconnectDaemonBridgeClient()
        if bridgeDemandLeases.isEmpty {
            stopDemandBridge(reason: "\(reason):idle")
            return
        }

        if localBridgeLauncher.start() {
            Self.publishPairingForDevMenu(pairing)
        }
    }

    func sharedBridgePairingService() -> PairingService {
        PairingService(
            defaults: UserDefaults(suiteName: ClawixPersistentSurfaceKeys.bridgeDefaultsSuite) ?? .standard,
            port: daemonBridgePort
        )
    }

    var activeLocalBridgeDemandReasonsForTests: Set<LocalBridgeDemandReason> {
        Set(bridgeDemandLeases.values)
    }

    var isTemporaryLocalBridgeRunningForTests: Bool {
        localBridgeLauncher.isRunning
    }

    private static func defaultDaemonBridgeClient(appState: AppState, pairing: PairingService) -> DaemonBridgeClient? {
        let client = DaemonBridgeClient(appState: appState, pairing: pairing)
        client.connect()
        return client
    }

    private func connectDaemonBridgeIfNeeded(pairing: PairingService) {
        guard daemonBridgeClient == nil else { return }
        daemonBridgeClient = makeDaemonBridgeClient(self, pairing)
    }

    private func disconnectDaemonBridgeClient() {
        daemonBridgeClient?.disconnect()
        daemonBridgeClient = nil
    }

    private func stopDemandBridge(reason: String) {
        guard localBridgeLauncher.isRunning else { return }
        BridgeLog.write("demand-bridge-stop reason=\(reason)")
        localBridgeLauncher.stop()
    }

    private func reconcileRemoteTargetBridgeDemand() {
        if FeatureFlags.shared.isVisible(.remoteMesh),
           case .peer = selectedMeshTarget {
            if selectedRemoteTargetLease == nil {
                selectedRemoteTargetLease = acquireLocalBridge(reason: .remoteTools)
            }
        } else {
            selectedRemoteTargetLease?.release()
            selectedRemoteTargetLease = nil
        }
    }

    init(
        databaseProvider: LazyDatabaseProvider = .shared,
        snapshotRepository: SnapshotRepository? = nil,
        localBridgeLauncher: (any LocalBridgeHelperLaunching)? = nil,
        backgroundBridgeIsActive: @escaping @MainActor () -> Bool = { BackgroundBridgeService.shared.isActive },
        backgroundBridgeIsEnabled: @escaping @MainActor () -> Bool = { BackgroundBridgeService.shared.isEnabled },
        makeDaemonBridgeClient: @escaping @MainActor (AppState, PairingService) -> DaemonBridgeClient? = AppState.defaultDaemonBridgeClient
    ) {
        self.databaseProvider = databaseProvider
        self.snapshotRepo = snapshotRepository ?? SnapshotRepository()
        self.localBridgeLauncher = localBridgeLauncher ?? ProcessLocalBridgeHelperLauncher()
        self.backgroundBridgeIsActive = backgroundBridgeIsActive
        self.backgroundBridgeIsEnabled = backgroundBridgeIsEnabled
        self.makeDaemonBridgeClient = makeDaemonBridgeClient
        // Mesh store has to be wired before any other stored-property
        // assignment that uses `self`, because Swift's definite-init
        // analysis treats any read of `self.foo` as requiring every
        // stored property to already be in place.
        self.meshStore = MeshStore()
        // Initial language: read directly from persisted storage so the
        // didSet observer doesn't fire (and re-apply) during init.
        // ClawixApp.init() has already called AppLanguage.bootstrap()
        // before AppState is constructed, so AppLocale.current and the
        // AppleLanguages override are already in place.
        self.preferredLanguage = AppLanguage.loadPersisted()
        self.permissionMode = PermissionMode.loadPersisted()
        let persistedRuntime = AgentRuntimeChoice.loadPersisted()
        self.selectedAgentRuntime = persistedRuntime
        if persistedRuntime == .opencode {
            self.selectedModel = AgentRuntimeChoice.persistedOpenCodeModel()
        }

        sampleChat = Chat(
            id: UUID(uuidString: "8B46DFE1-B932-48E6-94E7-C86E65F7F18D")!,
            title: "Refactor authentication module",
            messages: [
                ChatMessage(role: .user,
                            content: "Can you help me refactor the authentication module?",
                            timestamp: Date()),
                ChatMessage(role: .assistant,
                            content: "Sure. I'll start by analyzing the module's current structure and suggest improvements to readability and security.",
                            timestamp: Date())
            ],
            createdAt: Date()
        )

        let browserStart = Date().addingTimeInterval(-180)
        let browserEnd = browserStart.addingTimeInterval(150)
        browserSampleChat = Chat(
            id: UUID(uuidString: "C0FFEE11-CAFE-4BAB-9B0E-BAB1E7B0FFEE")!,
            title: "Find round titanium frames on 1688",
            messages: [
                ChatMessage(
                    role: .user,
                    content: "I'm looking for round titanium glasses frames similar to the ones in this photo. Can you browse 1688 and pull a few options?",
                    timestamp: browserStart
                ),
                ChatMessage(
                    role: .assistant,
                    content: "Found a handful of close matches: aviator-style with metal bridge, full titanium frame and prescription-ready. Listings open in the integrated browser if you want to compare them side by side.",
                    timestamp: browserEnd,
                    workSummary: WorkSummary(
                        startedAt: browserStart,
                        endedAt: browserEnd,
                        items: [
                            WorkItem(id: "tool-browser-1",
                                     kind: .dynamicTool(name: "the browser"),
                                     status: .completed),
                            WorkItem(id: "tool-search-1", kind: .webSearch, status: .completed),
                            WorkItem(id: "tool-search-2", kind: .webSearch, status: .completed),
                            WorkItem(id: "tool-search-3", kind: .webSearch, status: .completed),
                            WorkItem(id: "tool-search-4", kind: .webSearch, status: .completed)
                        ]
                    )
                )
            ],
            createdAt: browserStart
        )

        let computerUseStart = Date().addingTimeInterval(-90)
        let computerUseEnd = computerUseStart.addingTimeInterval(28)
        let computerUseTimelineGroupID = UUID(uuidString: "C0A111CE-0000-4000-8000-C0A111CE0001")!
        let computerUseTimelineItems = [
            WorkItem(
                id: "tool-computer-use-1",
                kind: .mcpTool(server: "computer_use", tool: "get_app_state"),
                status: .completed
            )
        ]
        computerUseSampleChat = Chat(
            id: UUID(uuidString: "A11CE000-CAFE-4BAB-9B0E-C001A11CE001")!,
            title: "Inspect the current Mac app",
            messages: [
                ChatMessage(
                    role: .user,
                    content: "Inspect the screen and tell me what is open.",
                    timestamp: computerUseStart
                ),
                ChatMessage(
                    role: .assistant,
                    content: "The active window is visible and ready.",
                    timestamp: computerUseEnd,
                    workSummary: WorkSummary(
                        startedAt: computerUseStart,
                        endedAt: computerUseEnd,
                        items: computerUseTimelineItems
                    ),
                    timeline: [
                        .tools(
                            id: computerUseTimelineGroupID,
                            items: computerUseTimelineItems,
                            presentation: ToolTimelinePresentation.snapshot(
                                groupID: computerUseTimelineGroupID,
                                items: computerUseTimelineItems
                            )
                        ),
                        .message(
                            id: UUID(uuidString: "C0A111CE-0000-4000-8000-C0A111CE0002")!,
                            text: "The active window is visible and ready."
                        )
                    ]
                )
            ],
            createdAt: computerUseStart
        )

        let resolvedBinary = ClawixBinary.resolve()
        self.clawixBinary = resolvedBinary
        self.clawix = resolvedBinary.map { ClawixService(binary: $0) }
        self.titleGenerator = nil

        manualProjectOrder = projectOrdersRepo.orderedIds()
        loadMockStartupState()
        if let fixtureThreads = AgentThreadStore.fixtureThreads() {
            applyThreads(fixtureThreads)
        } else if dummyModeActive {
            chats = [computerUseSampleChat, browserSampleChat, sampleChat]
            currentRoute = .chat(computerUseSampleChat.id)
        } else {
            // First paint comes from a compact JSON cache so AppState
            // construction never opens or migrates SQLite. The real local
            // database hydrates after SwiftUI has rendered the first frame.
            applyFirstPaintCacheForLaunch()
            // Hydrate the most-recent transcripts from the on-disk
            // bridge snapshot (~/Library/Application Support/clawix/
            // snapshot.json) so a tap on a chat in the sidebar lands
            // immediately on the last-known body instead of an empty
            // ScrollView while the daemon's `messagesSnapshot` races
            // back. Idempotent / silent if the file is missing.
            loadCachedSnapshot()
        }
        loadHostFavicons()
        loadChatSidebars()
        applyLaunchRoute()
        syncChatStoreFromLegacySnapshots()

        // Forward auth coordinator changes so views observing AppState
        // also rebuild when login / logout state flips. Coalesce bursts
        // into one tick per 150 ms: auth flips are user-visible but
        // never urgent, and an unthrottled forward fans out an
        // `objectWillChange` storm to every `@EnvironmentObject`
        // observer (sidebar, chat, composer, message rows, ...).
        auth.bootstrap()
        authObserver = auth.objectWillChange
            .throttle(for: .milliseconds(150), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
        if RenderProbe.isEnabled {
            willChangeProbe = objectWillChange.sink { _ in
                RenderProbe.tick("AppState.willChange")
            }
            // Per-property publish probes. `$prop` for an `@Published var prop`
            // emits each time the value is set, so each tick on `AppState.<x>`
            // tells us what slice of state mutated immediately before a
            // matching `AppState.willChange` tick. The `dropFirst()` skips the
            // synchronous initial value emission.
            publishProbes = [
                $chats.dropFirst().sink { _ in RenderProbe.tick("AppState.chats") },
                $pinnedOrder.dropFirst().sink { _ in RenderProbe.tick("AppState.pinnedOrder") },
                $archivedChats.dropFirst().sink { _ in RenderProbe.tick("AppState.archivedChats") },
                $archivedLoading.dropFirst().sink { _ in RenderProbe.tick("AppState.archivedLoading") },
                $availableModels.dropFirst().sink { _ in RenderProbe.tick("AppState.availableModels") },
                $otherModels.dropFirst().sink { _ in RenderProbe.tick("AppState.otherModels") },
                $projects.dropFirst().sink { _ in RenderProbe.tick("AppState.projects") },
                $selectedProject.dropFirst().sink { _ in RenderProbe.tick("AppState.selectedProject") },
                $currentRoute.dropFirst().sink { _ in RenderProbe.tick("AppState.currentRoute") },
                $pendingPlanQuestions.dropFirst().sink { _ in RenderProbe.tick("AppState.pendingPlanQuestions") },
                $clawixBackendStatus.dropFirst().sink { _ in RenderProbe.tick("AppState.clawixBackendStatus") },
                $rateLimits.dropFirst().sink { _ in RenderProbe.tick("AppState.rateLimits") },
                $rateLimitsByLimitId.dropFirst().sink { _ in RenderProbe.tick("AppState.rateLimitsByLimitId") },
                $hostFavicons.dropFirst().sink { _ in RenderProbe.tick("AppState.hostFavicons") },
                $browserPageBackgroundColors.dropFirst().sink { _ in RenderProbe.tick("AppState.browserPageBackgroundColors") },
                $chatSidebars.dropFirst().sink { _ in RenderProbe.tick("AppState.chatSidebars") },
                $pendingReloadTabId.dropFirst().sink { _ in RenderProbe.tick("AppState.pendingReloadTabId") },
                $richViewDisabledPaths.dropFirst().sink { _ in RenderProbe.tick("AppState.richViewDisabledPaths") },
                $wordWrapEnabledPaths.dropFirst().sink { _ in RenderProbe.tick("AppState.wordWrapEnabledPaths") },
                $isLeftSidebarOpen.dropFirst().sink { open in
                    AppState.sidebarDefaults.set(open, forKey: AppState.leftSidebarOpenKey)
                    RenderProbe.tick("AppState.isLeftSidebarOpen")
                },
                $isRightSidebarMaximized.dropFirst().sink { _ in RenderProbe.tick("AppState.isRightSidebarMaximized") },
                $isCommandPaletteOpen.dropFirst().sink { _ in RenderProbe.tick("AppState.isCommandPaletteOpen") },
                $imagePreviewURL.dropFirst().sink { _ in RenderProbe.tick("AppState.imagePreviewURL") },
                $pendingRenameChat.dropFirst().sink { _ in RenderProbe.tick("AppState.pendingRenameChat") },
                $pendingConfirmation.dropFirst().sink { _ in RenderProbe.tick("AppState.pendingConfirmation") },
                $searchQuery.dropFirst().sink { _ in RenderProbe.tick("AppState.searchQuery") },
                $searchResults.dropFirst().sink { _ in RenderProbe.tick("AppState.searchResults") },
            ]
        }

        // `isActive`, not `isEnabled`: SMAppService.status is bundle-
        // relative, so a daemon registered by the npm CLI doesn't show
        // up as enabled for the GUI's own SMAppService.agent. Treat any
        // reachable daemon on loopback as authoritative — otherwise the
        // GUI would race the CLI-installed daemon for Codex ownership.
        //
        // Fixture mode (showcase / dummy / E2E) overrides this: the
        // fixture is the canonical dataset and the daemon owns the
        // user's REAL Codex sessions, so connecting would let the
                // daemon's `sessionsSnapshot` overwrite the curated fixture chats
        // with live data and leak the user's real chats into a recording.
        let fixtureActive = AgentThreadStore.fixtureThreads() != nil || dummyModeActive
        let daemonBridgeEnabled = !fixtureActive && backgroundBridgeIsActive()
        clawix?.appState = self
        if let clawix {
            clawix.primeFromCache(appState: self)
            if ProcessInfo.processInfo.environment["CLAWIX_DISABLE_BACKEND"] != "1",
               !daemonBridgeEnabled {
                // GUI-owned backend startup is demand-driven; keep the
                // launch guard explicit so daemon-backed runs never start
                // a second local runtime during app bootstrap.
            }
        }

        // Bridge transport is no longer opened on app launch. A
        // user-enabled/reachable background bridge remains canonical, but
        // otherwise port 24080/24081 stay closed until an explicit pairing,
        // companion, or remote-tools surface acquires a demand lease.
        reconcileBridgeTransport(reason: "startup")

        // Auto-reload threads when the app gains focus, debounced to avoid
        // hammering the runtime when the user alt-tabs rapidly. Gated by
        // SyncSettings.autoReloadOnFocus.
        focusReloadObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleAppDidBecomeActive() }
        }
        // AppIntents → AppState bridge (#13). Shortcuts.app posts
        // these notifications when the user invokes NewChat or
        // SendMessage; we react by routing to home (so the composer
        // is in scope) and, for SendMessage, prefilling the composer
        // and submitting.
        NotificationCenter.default.addObserver(
            forName: Notification.Name("clawix.intent.newChat"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleNewChatIntent() }
        }
        NotificationCenter.default.addObserver(
            forName: Notification.Name("clawix.intent.sendMessage"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            let prompt = note.userInfo?["prompt"] as? String ?? ""
            Task { @MainActor in self?.handleSendMessageIntent(prompt) }
        }
        NotificationCenter.default.addObserver(
            forName: .clawixOpenURL,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let url = note.object as? URL else { return }
            Task { @MainActor in
                _ = self?.handleOpenURL(url)
            }
        }
    }

    enum ProjectRefreshIntent: Int {
        case visible
        case expanded

        var priority: TaskPriority {
            switch self {
            case .visible: return .utility
            case .expanded: return .userInitiated
            }
        }

        var reportErrors: Bool {
            self == .expanded
        }
    }

    struct ProjectRefreshJob {
        var project: Project
        var intent: ProjectRefreshIntent
        var token: UUID?
        var task: Task<Void, Never>?
    }

    /// Tracks the last successful per-project refresh so accordion
    /// toggles or focus events don't fire a fresh RPC every time.
    var lastProjectRefreshAt: [String: Date] = [:]
    var projectRefreshJobs: [UUID: ProjectRefreshJob] = [:]
    var projectRefreshIdsByPath: [String: UUID] = [:]
    var projectRefreshQueue: [UUID] = []
    /// Skip a per-project refresh if the previous one finished less
    /// than this many seconds ago. Tuned so a user toggling an
    /// accordion shut and back open feels instant without a redundant
    /// round-trip, while still picking up changes the daemon makes
    /// outside the bridge's notification path.
    static let projectRefreshDebounce: TimeInterval = 2.0
    /// Maximum simultaneous progressive project refreshes. Visible row
    /// requests can arrive in bursts, especially in custom sort mode
    /// where drag-and-drop keeps every project row materialised.
    static let projectRefreshConcurrency = 2

    func mergedProjects() -> [Project] {
        let localPaths = Set(projectsRepo.all().map(\.path).filter { !$0.isEmpty })
        let hidden = Set(hiddenRootsRepo.allHidden())
        // Drop Codex roots the user explicitly hid. Local projects with the
        // same path stay visible (hidden_codex_roots only filters the
        // backend-sourced bucket; the local entry is the user's own data).
        var result = backendState.workspaceRoots.filter { root in
            if hidden.contains(root.path) && !localPaths.contains(root.path) {
                return false
            }
            return true
        }
        var seen = Set(result.map { $0.path })
        for project in projectsRepo.all() {
            guard !project.path.isEmpty, !seen.contains(project.path) else { continue }
            seen.insert(project.path)
            result.append(project)
        }
        for path in snapshotRepo.projectPathHints() {
            guard !seen.contains(path) else { continue }
            guard !hidden.contains(path) || localPaths.contains(path) else { continue }
            seen.insert(path)
            result.append(Project(
                id: StableProjectID.uuid(for: path),
                name: URL(fileURLWithPath: path).lastPathComponent.isEmpty ? path : URL(fileURLWithPath: path).lastPathComponent,
                path: path
            ))
        }
        return result
    }

    /// True when the path corresponds to a Codex-sourced workspace root
    /// that does NOT also exist as a local project. Used by the sidebar
    /// context menu to expose the "Hide from sidebar" affordance only on
    /// Codex roots; local projects offer "Delete" instead.
    func isCodexSourcedProject(path: String) -> Bool {
        guard !path.isEmpty else { return false }
        let isCodexRoot = backendState.workspaceRoots.contains(where: { $0.path == path })
        let isLocal = projectsRepo.all().contains(where: { $0.path == path })
        return isCodexRoot && !isLocal
    }

    func hideCodexRoot(path: String) {
        guard isCodexSourcedProject(path: path) else { return }
        hiddenRootsRepo.hide(path)
        if !clawJSSessionsCanonicalActive {
            projects = mergedProjects()
        }
    }

    func showCodexRoot(path: String) {
        hiddenRootsRepo.show(path)
        if !clawJSSessionsCanonicalActive {
            projects = mergedProjects()
        }
    }

    func hiddenCodexRoots() -> [String] {
        hiddenRootsRepo.allHidden()
    }

    func localOverrideCounts() -> Database.LocalOverrideCounts {
        Database.LocalOverrideCounts(
            pins: pinsRepo.count(),
            projects: projectsRepo.count(),
            chatProjectOverrides: chatProjectsRepo.overridesCount(),
            projectlessThreads: chatProjectsRepo.projectlessCount(),
            archives: archivesRepo.count(),
            titles: titlesRepo.count(),
            hiddenRoots: hiddenRootsRepo.count()
        )
    }

    /// Wipe all local user-curated state and rebuild from the runtime on
    /// the next reload. Codex's data and other Codex apps are NOT
    /// touched. Triggered from Settings via the destructive confirmation
    /// dialog.
    func resetLocalOverrides() {
        if case .ready(let dbQueue) = databaseProvider.openIfNeeded() {
            Database(dbQueue: dbQueue).resetLocalOverrides()
        }
        // Refresh in-memory derived state so SwiftUI rerenders without
        // waiting for the next runtime reload.
        pinnedOrder = []
        manualProjectOrder = []
        if !clawJSSessionsCanonicalActive {
            projects = mergedProjects()
        }
        titlesRepo.reload()
        Task { @MainActor in
            guard await self.ensureAgentRuntimeReady(reason: .manualRefresh) else { return }
            await loadThreadsFromRuntime()
        }
    }

    /// Per-project cap when persisting `sidebar_snapshot_project` and
    /// the matching `listThreads` limit. The sidebar accordion only
    /// renders 5 chats by default and 10 after "Show more", so caching
    /// past 10 is wasted work — anything beyond that is reachable
    /// through the per-project "View all" popup, which fetches its own
    /// page on open. Keeps the in-memory `chats[]` list and the
    /// `sidebar_snapshot_project` table tight even for power users
    /// with thousands of conversations per workspace root.
    static let snapshotPerProjectCap = 10
    /// Hard global cap on `sidebar_snapshot_project` rows. Bounds disk
    /// use for power users with hundreds of workspace roots.
    static let snapshotGlobalCap = 5000
    /// Page size for the per-project "View all" popup fetch. Generous
    /// enough that a typical workspace fully materialises on open
    /// (so the popup's local title filter sees every chat) without
    /// merging tens of thousands of rows for a power user — those
    /// surface through subsequent server-side searches.
    static let popupFullProjectFetchLimit = 500

    // MARK: - ClawixService callbacks

    func attachThreadId(_ threadId: String, to chatId: UUID) {
        guard let existing = chatStore.summary(id: chatId) else { return }
        chatStore.updateSummary(id: chatId) { summary in
            summary.clawixThreadId = threadId
            summary.historyHydrated = true
        }
        // Reflect any pre-attach state onto the freshly-known thread id:
        // a chat created already pinned, or with a project selected,
        // must persist now that we have an id to key by.
        let chat = existing
        if chat.isPinned {
            pinsRepo.setPinned(threadId, atEnd: true)
        }
        if let pid = chat.projectId,
           let project = projects.first(where: { $0.id == pid }), !project.path.isEmpty {
            chatProjectsRepo.setOverride(threadId: threadId, projectPath: project.path)
        }
        syncLegacyChatFromStore(chatId: chatId)
    }

    func appendAssistantPlaceholder(chatId: UUID) -> UUID? {
        guard chatStore.summary(id: chatId) != nil else { return nil }
        let msg = ChatMessage(
            role: .assistant,
            content: "",
            reasoningText: "",
            streamingFinished: false
        )
        chatStore.appendMessage(chatId: chatId, msg)
        chatStore.updateSummary(id: chatId) { summary in
            summary.hasActiveTurn = true
        }
        syncLegacyChatFromStore(chatId: chatId)
        return msg.id
    }

    /// Pending text deltas keyed by chat ID. The bridge can fire many
    /// `nAgentMsgDelta` notifications per main-runloop tick (the daemon
    /// emits per-token); mutating `chats` once per token publishes
    /// `@Published var chats` once per token, which invalidates every
    /// subscribed view body in the transcript per token. Buffering and
    /// applying once per tick collapses that to a single publish per
    /// frame, dropping invalidation work by ~10x without changing the
    /// observable streaming semantics (the user still sees per-word
    /// fades because the StreamCheckpoint schedule keeps its leaky-
    /// bucket spacing inside `applyAssistantTextDelta`).
    ///
    /// Text and reasoning deltas are coalesced independently. Each
    /// cross-stream boundary drains the older buffer first so the
    /// timeline preserves the backend's arrival order.
    var pendingAssistantTextBuffers: [UUID: String] = [:]
    var assistantTextFlushScheduled = false
    var pendingReasoningBuffers: [UUID: String] = [:]
    var reasoningFlushScheduled = false
    var streamingSettlementTasks: [UUID: Task<Void, Never>] = [:]
    /// Wall-clock of the previous `applyAssistantTextDelta` call, used by
    /// the perf log to surface inter-arrival jitter.
    var lastDeltaArrivalTime: Double = 0

}
