import Combine
import XCTest
@testable import Clawix

/// P0 baseline contracts for the render-layer-thinness refactor.
///
/// These tests measure, FROM CODE (no Instruments, no clicking), the broad
/// invalidation the refactor exists to remove. They characterize today's
/// behavior so later phases have a deterministic regression lock.
///
/// The keystone bug: a conceptually single-row event (a turn-boundary status
/// flip, or appending the user's message on send) re-publishes the legacy
/// `AppState.chats` mirror via `syncLegacyChatFromStore`. That:
///   - fans `AppState.objectWillChange` out to every @EnvironmentObject
///     observer (the open-session shell + chrome re-evaluate), and
///   - walks/rebuilds the bounded `chats` array O(N-chats) per event.
///
/// Note the synthesis hypothesis that the `chats` didSet runs an O(N)
/// `ChatStore.replaceActive` per send is FALSE: that didSet is guarded out
/// while `syncingLegacyChatsFromStore` is set. The real per-event cost is the
/// `legacy.sync` scan + the broad publish, which is exactly what these probes
/// capture (`legacy.sync.scanned` == N walked).
///
/// P1 retired the legacy mirror on the send/turn-boundary hot path. These
/// tests are now the permanent locks: a single-row turn flip or a send routes
/// only through the named `chatStore` events, so the broad `AppState.chats`
/// publish and the O(N-chats) legacy scan are gone (both == 0), while the
/// named single-row `summaries` publish stays at exactly 1.
@MainActor
final class UIThinnessContractTests: XCTestCase {
    private var cancellables: Set<AnyCancellable> = []

    override func setUp() {
        super.setUp()
        setenv("CLAWIX_DISABLE_BACKEND", "1", 1)
        setenv("CLAWIX_BRIDGE_DISABLE", "1", 1)
        // Force RenderProbe on so the deterministic counters/timings are
        // populated regardless of debug/release test configuration.
        setenv("CLAWIX_RENDER_PROBE", "1", 1)
        RenderProbe.resetMeasurementWindow()
    }

    override func tearDown() {
        cancellables.removeAll()
        unsetenv("CLAWIX_DISABLE_BACKEND")
        unsetenv("CLAWIX_BRIDGE_DISABLE")
        unsetenv("CLAWIX_RENDER_PROBE")
        super.tearDown()
    }

    private func makeState(chatCount: Int) -> (AppState, [UUID]) {
        let state = AppState()
        state.projects = []
        state.pinnedOrder = []
        state.archivedChats = []
        var ids: [UUID] = []
        var chats: [Chat] = []
        for index in 0..<chatCount {
            let id = UUID()
            ids.append(id)
            chats.append(
                Chat(
                    id: id,
                    title: "Chat \(index)",
                    messages: [],
                    createdAt: Date(timeIntervalSince1970: TimeInterval(1_000 + index))
                )
            )
        }
        state.chats = chats
        return (state, ids)
    }

    private func legacySyncScan() -> Int {
        RenderProbe.snapshotCounts()["legacy.sync.scanned"] ?? 0
    }

    // MARK: - Turn boundary keystone

    /// A turn-boundary status flip (`hasActiveTurn`) is a single-row event: it
    /// updates exactly that row's spinner through the named `chatStore`
    /// summary update. P1 removed the legacy `AppState.chats` mirror sync from
    /// this hot path, so the broad `AppState.objectWillChange` fan-out and the
    /// O(N-chats) legacy scan are gone; only the named `summaries` publish fires.
    func testTurnBoundaryDoesNotFanOutToGlobalAppState() {
        let (state, ids) = makeState(chatCount: 200)
        let target = ids[0]
        let sidebar = SidebarStore(appState: state)
        let sidebarRevision = sidebar.revision

        var appStatePublishes = 0
        var chatsPublishes = 0
        var summariesPublishes = 0
        state.objectWillChange.sink { _ in appStatePublishes += 1 }.store(in: &cancellables)
        state.$chats.dropFirst().sink { _ in chatsPublishes += 1 }.store(in: &cancellables)
        state.chatStore.$summaries.dropFirst().sink { _ in summariesPublishes += 1 }.store(in: &cancellables)

        RenderProbe.resetMeasurementWindow()
        state.markChat(chatId: target, hasActiveTurn: true)
        let scan = legacySyncScan()

        // Keystone fixed: no broad mirror broadcast for a single-row event.
        XCTAssertEqual(
            chatsPublishes, 0,
            "A turn boundary must not re-publish AppState.chats."
        )
        XCTAssertEqual(
            appStatePublishes, 0,
            "A turn boundary must not fan AppState.objectWillChange out to every @EnvironmentObject observer."
        )
        XCTAssertEqual(
            scan, 0,
            "A single-row turn flip must not walk the N-chat array via the legacy sync."
        )
        // The correct named single-row event is all that fires.
        XCTAssertEqual(summariesPublishes, 1)
        XCTAssertGreaterThan(sidebar.revision, sidebarRevision)
        XCTAssertEqual(state.chatStore.summary(id: target)?.hasActiveTurn, true)
    }

    // MARK: - Send keystone

    /// The send hot path for an existing chat now routes only through the named
    /// `chatStore.appendMessage` event (which optimistically lands the bubble
    /// and publishes one summary update). The legacy mirror sync that used to
    /// follow it on the hot path is gone, so the broad `AppState.chats` publish
    /// and the O(N) scan never fire.
    func testSendDoesNotFanOutToGlobalAppState() {
        let (state, ids) = makeState(chatCount: 200)
        let target = ids[0]
        state.currentRoute = .chat(target)

        var appStatePublishes = 0
        var chatsPublishes = 0
        state.objectWillChange.sink { _ in appStatePublishes += 1 }.store(in: &cancellables)
        state.$chats.dropFirst().sink { _ in chatsPublishes += 1 }.store(in: &cancellables)

        RenderProbe.resetMeasurementWindow()
        // The send hot path: named append only (no legacy mirror sync).
        state.chatStore.appendMessage(chatId: target, ChatMessage(role: .user, content: "hello"))
        let scan = legacySyncScan()

        XCTAssertEqual(
            chatsPublishes, 0,
            "A send must not re-publish AppState.chats before the bubble paints."
        )
        XCTAssertEqual(
            appStatePublishes, 0,
            "A send must not fan AppState.objectWillChange out to every observer."
        )
        XCTAssertEqual(
            scan, 0,
            "A send must not walk the N-chat array via the legacy sync."
        )
        // The bubble is in the per-message store immediately (optimistic, kept).
        XCTAssertEqual(
            state.chatStore.transcript(for: target)?.messages.last?.content,
            "hello"
        )
    }

    // MARK: - Send call budget (independent of N-chats)

    /// One send is exactly one `messageIds` structure publish + one `summaries`
    /// single-row publish + zero broad `AppState.objectWillChange` / `$chats`
    /// publishes, regardless of how many chats exist. `appendMessage` updates
    /// `lastMessageAt`/`lastTurnInterrupted` on the summary (one summaries
    /// publish) and appends one id to the transcript (one messageIds publish).
    func testSendCallBudgetIsIndependentOfChatCount() {
        for chatCount in [1, 500] {
            cancellables.removeAll()
            let (state, ids) = makeState(chatCount: chatCount)
            let target = ids[0]
            state.currentRoute = .chat(target)
            guard let transcript = state.chatStore.transcript(for: target) else {
                XCTFail("missing transcript for \(chatCount)")
                continue
            }

            var appStatePublishes = 0
            var chatsPublishes = 0
            var summariesPublishes = 0
            var messageIdsPublishes = 0
            state.objectWillChange.sink { _ in appStatePublishes += 1 }.store(in: &cancellables)
            state.$chats.dropFirst().sink { _ in chatsPublishes += 1 }.store(in: &cancellables)
            state.chatStore.$summaries.dropFirst().sink { _ in summariesPublishes += 1 }.store(in: &cancellables)
            transcript.$messageIds.dropFirst().sink { _ in messageIdsPublishes += 1 }.store(in: &cancellables)

            RenderProbe.resetMeasurementWindow()
            state.chatStore.appendMessage(chatId: target, ChatMessage(role: .user, content: "hello"))

            XCTAssertEqual(messageIdsPublishes, 1, "chatCount=\(chatCount): exactly one structure publish")
            XCTAssertEqual(summariesPublishes, 1, "chatCount=\(chatCount): exactly one single-row summary publish")
            XCTAssertEqual(chatsPublishes, 0, "chatCount=\(chatCount): no AppState.chats publish")
            XCTAssertEqual(appStatePublishes, 0, "chatCount=\(chatCount): no broad AppState publish")
            XCTAssertEqual(legacySyncScan(), 0, "chatCount=\(chatCount): no legacy O(N) scan")
        }
    }

    // MARK: - Streaming stays isolated (positive lock, already holds)

    /// Per-token deltas must never touch the global mirror or the sidebar.
    /// This already passes (ADR 0036) and stays a lock through the refactor.
    func testStreamingDeltaDoesNotBroadcastGlobalChatsOrSidebar() {
        let state = AppState()
        state.projects = []
        state.pinnedOrder = []
        state.archivedChats = []
        let chatId = UUID()
        let assistant = ChatMessage(role: .assistant, content: "", streamingFinished: false)
        state.chats = [Chat(id: chatId, title: "Streaming", messages: [assistant], createdAt: Date())]
        let sidebar = SidebarStore(appState: state)
        let sidebarRevision = sidebar.revision

        var chatsPublishes = 0
        state.$chats.dropFirst().sink { _ in chatsPublishes += 1 }.store(in: &cancellables)

        for index in 0..<500 {
            state.appendAssistantDelta(chatId: chatId, delta: "token-\(index) ")
            state.flushPendingAssistantTextDeltas(chatId: chatId)
        }

        XCTAssertEqual(chatsPublishes, 0)
        XCTAssertEqual(sidebar.revision, sidebarRevision)
    }

    // MARK: - Code-latency observability primitive

    /// The refactor's measurement law (#6) requires reading code latency from
    /// a test. The legacy-sync timing is gone from the hot path (P1); prove the
    /// `RenderProbe.snapshotTimings()` primitive still surfaces a centralized
    /// compute-layer duration (the sidebar snapshot build) to code so later
    /// phases can assert code-latency budgets.
    func testRenderProbeTimingsAreReadableFromCode() {
        let (state, _) = makeState(chatCount: 50)
        RenderProbe.resetMeasurementWindow()
        // Building the sidebar store runs SidebarSnapshot.make under
        // RenderProbe.time("makeSnapshot"), the bounded compute layer.
        _ = SidebarStore(appState: state)

        let timings = RenderProbe.snapshotTimings()
        let snapshot = timings["makeSnapshot"]
        XCTAssertNotNil(snapshot, "RenderProbe.time should expose the snapshot build duration to code.")
        XCTAssertGreaterThanOrEqual(snapshot?.count ?? 0, 1)
        XCTAssertGreaterThanOrEqual(snapshot?.totalMs ?? 0, 0)
    }

    // MARK: - P4 god-object split: focused-store writes are isolated

    /// Wires the three charter surfaces (the god-object publish itself, the
    /// sidebar compute layer, and an open session's presentation layer) so a
    /// test can prove an unrelated write touches none of them.
    private func makeChartedSurfaces(
        chatCount: Int
    ) -> (state: AppState, sidebar: SidebarStore, session: SessionPresentationStore, target: UUID) {
        let (state, ids) = makeState(chatCount: chatCount)
        let target = ids[0]
        state.currentRoute = .chat(target)
        // Seed one message so the session presentation layer has a row to draw.
        state.chatStore.appendMessage(chatId: target, ChatMessage(role: .user, content: "hello"))

        let sidebar = SidebarStore(appState: state)
        let session = SessionPresentationStore()
        session.bind(chatId: target, chatStore: state.chatStore)
        return (state, sidebar, session, target)
    }

    /// The P4 contract: a write to a focused store (browser chrome / rate
    /// limit / search) fires only that store's `objectWillChange`. It must NOT
    /// fan `AppState.objectWillChange` out to the ~90 `@EnvironmentObject`
    /// observers, must NOT advance `SidebarStore.revision`, and must NOT
    /// advance the open session's `SessionPresentationStore.revision`. The
    /// focused store's OWN publish still fires (the store is reactive for its
    /// own consumers); only the chat/sidebar surfaces are unaffected.
    func testRateLimitWriteDoesNotReEvaluateChatOrSidebar() {
        let (state, sidebar, session, _) = makeChartedSurfaces(chatCount: 200)
        let sidebarRevision = sidebar.revision
        let sessionRevision = session.revision

        var appStatePublishes = 0
        var rateLimitPublishes = 0
        state.objectWillChange.sink { _ in appStatePublishes += 1 }.store(in: &cancellables)
        state.rateLimitStore.objectWillChange.sink { _ in rateLimitPublishes += 1 }.store(in: &cancellables)

        state.rateLimits = RateLimitSnapshot(primary: nil, secondary: nil, credits: nil, limitId: nil, limitName: nil)
        state.rateLimitsByLimitId = ["codex": RateLimitSnapshot(primary: nil, secondary: nil, credits: nil, limitId: nil, limitName: nil)]

        XCTAssertEqual(appStatePublishes, 0, "A rate-limit write must not fan AppState.objectWillChange out to chat/sidebar observers.")
        XCTAssertEqual(sidebar.revision, sidebarRevision, "A rate-limit write must not advance the sidebar compute layer.")
        XCTAssertEqual(session.revision, sessionRevision, "A rate-limit write must not advance the open session's presentation layer.")
        XCTAssertGreaterThan(rateLimitPublishes, 0, "The focused store still publishes to its own consumers.")
    }

    func testSearchWriteDoesNotReEvaluateChatOrSidebar() {
        let (state, sidebar, session, _) = makeChartedSurfaces(chatCount: 200)
        let sidebarRevision = sidebar.revision
        let sessionRevision = session.revision

        var appStatePublishes = 0
        var searchPublishes = 0
        state.objectWillChange.sink { _ in appStatePublishes += 1 }.store(in: &cancellables)
        state.searchStore.objectWillChange.sink { _ in searchPublishes += 1 }.store(in: &cancellables)

        // A keystroke into the search field plus a results update.
        state.searchQuery = "design"
        state.searchResults = ["Design — title match"]
        state.searchResultRoutes = ["Design — title match": .home]

        XCTAssertEqual(appStatePublishes, 0, "A search write must not fan AppState.objectWillChange out to chat/sidebar observers.")
        XCTAssertEqual(sidebar.revision, sidebarRevision, "A search write must not advance the sidebar compute layer.")
        XCTAssertEqual(session.revision, sessionRevision, "A search write must not advance the open session's presentation layer.")
        XCTAssertGreaterThan(searchPublishes, 0, "The focused store still publishes to its own consumers.")
    }

    func testBrowserChromeWriteDoesNotReEvaluateChatOrSidebar() {
        let (state, sidebar, session, _) = makeChartedSurfaces(chatCount: 200)
        let sidebarRevision = sidebar.revision
        let sessionRevision = session.revision

        var appStatePublishes = 0
        var chromePublishes = 0
        state.objectWillChange.sink { _ in appStatePublishes += 1 }.store(in: &cancellables)
        state.browserChromeStore.objectWillChange.sink { _ in chromePublishes += 1 }.store(in: &cancellables)

        let tab = UUID()
        state.browserTabsLoading = [tab]
        state.browserPageBackgroundColors = [tab: .black]
        state.pendingReloadTabId = tab
        state.hostFavicons = ["example.com": URL(string: "https://example.com/favicon.ico")!]

        XCTAssertEqual(appStatePublishes, 0, "A browser-chrome write must not fan AppState.objectWillChange out to chat/sidebar observers.")
        XCTAssertEqual(sidebar.revision, sidebarRevision, "A browser-chrome write must not advance the sidebar compute layer.")
        XCTAssertEqual(session.revision, sessionRevision, "A browser-chrome write must not advance the open session's presentation layer.")
        XCTAssertGreaterThan(chromePublishes, 0, "The focused store still publishes to its own consumers.")
    }

    /// The forwarders are not write-only sugar: a value written through the
    /// `AppState.<x>` forwarder round-trips, and reading it back returns the
    /// child store's value (and vice versa). Proves the split preserves the
    /// existing source-compatible call sites.
    func testFocusedStoreForwardersRoundTrip() {
        let state = AppState()

        state.searchQuery = "abc"
        XCTAssertEqual(state.searchStore.searchQuery, "abc")
        state.searchStore.searchQuery = "xyz"
        XCTAssertEqual(state.searchQuery, "xyz")

        let snapshot = RateLimitSnapshot(primary: nil, secondary: nil, credits: nil, limitId: nil, limitName: nil)
        state.rateLimits = snapshot
        XCTAssertNotNil(state.rateLimitStore.rateLimits)

        let tab = UUID()
        state.pendingReloadTabId = tab
        XCTAssertEqual(state.browserChromeStore.pendingReloadTabId, tab)
        state.browserChromeStore.pendingReloadTabId = nil
        XCTAssertNil(state.pendingReloadTabId)
    }
}
