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
/// Each `_baseline` test asserts the CURRENT (intentionally-bad) numbers and
/// names the P1 target in a comment. When P1 retires the legacy mirror on the
/// hot path these flip to the target (broad publish == 0, scan == 0) and
/// become the permanent locks. The named single-row `chatStore` event
/// (`summaries` publish) is the correct path and stays at 1.
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

    /// A turn-boundary status flip (`hasActiveTurn`) is conceptually a
    /// single-row event: it should update exactly that row's spinner. Today
    /// it ALSO re-publishes the whole `AppState.chats` mirror (fanning
    /// `AppState.objectWillChange` to all observers) and walks the N-chat array
    /// via the legacy sync.
    ///
    /// P1 target: chatsPublishes == 0, appStatePublishes == 0, scan == 0;
    /// summariesPublishes stays == 1 (the named single-row event is all that fires).
    func testTurnBoundaryFansOutToGlobalAppStateToday_baseline() {
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

        // KEYSTONE BUG (P1 target == 0): the global mirror is broadcast for a single-row event.
        XCTAssertGreaterThanOrEqual(
            chatsPublishes, 1,
            "Today a turn boundary re-publishes AppState.chats. P1 target: 0."
        )
        XCTAssertGreaterThanOrEqual(
            appStatePublishes, 1,
            "Today a turn boundary fans AppState.objectWillChange out to every @EnvironmentObject observer. P1 target: 0."
        )
        XCTAssertEqual(
            scan, 200,
            "Today a single-row turn flip walks all N chats via the legacy sync. P1 target: 0."
        )
        // The correct named single-row event fires (this stays after P1).
        XCTAssertEqual(summariesPublishes, 1)
        XCTAssertGreaterThan(sidebar.revision, sidebarRevision)
        XCTAssertEqual(state.chatStore.summary(id: target)?.hasActiveTurn, true)
    }

    // MARK: - Send keystone

    /// Mirrors `AppState.sendMessage()` lines 34-35 for an existing chat: the
    /// named append event (correct, kept) followed by the legacy mirror sync
    /// (the avoidable broad publish + O(N) scan on the send hot path).
    ///
    /// P1 target: chatsPublishes == 0, appStatePublishes == 0, scan == 0.
    func testSendLegacyMirrorStepFansOutToGlobalAppStateToday_baseline() {
        let (state, ids) = makeState(chatCount: 200)
        let target = ids[0]
        state.currentRoute = .chat(target)

        var appStatePublishes = 0
        var chatsPublishes = 0
        state.objectWillChange.sink { _ in appStatePublishes += 1 }.store(in: &cancellables)
        state.$chats.dropFirst().sink { _ in chatsPublishes += 1 }.store(in: &cancellables)

        RenderProbe.resetMeasurementWindow()
        // The send hot path, surgically: named append (kept) + legacy sync (removed in P1).
        state.chatStore.appendMessage(chatId: target, ChatMessage(role: .user, content: "hello"))
        state.syncLegacyChatFromStore(chatId: target)
        let scan = legacySyncScan()

        XCTAssertGreaterThanOrEqual(
            chatsPublishes, 1,
            "Today a send re-publishes AppState.chats before the bubble paints. P1 target: 0."
        )
        XCTAssertGreaterThanOrEqual(
            appStatePublishes, 1,
            "Today a send fans AppState.objectWillChange out to every observer. P1 target: 0."
        )
        XCTAssertEqual(
            scan, 200,
            "Today a send walks all N chats via the legacy sync. P1 target: 0."
        )
        // The bubble is in the per-message store immediately (optimistic, kept).
        XCTAssertEqual(
            state.chatStore.transcript(for: target)?.messages.last?.content,
            "hello"
        )
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
    /// a test. Prove `RenderProbe.snapshotTimings()` surfaces the timed legacy
    /// hot path so P1 can assert a send-to-bubble compute budget.
    func testRenderProbeTimingsAreReadableFromCode() {
        let (state, ids) = makeState(chatCount: 50)
        RenderProbe.resetMeasurementWindow()
        state.markChat(chatId: ids[0], hasActiveTurn: true)

        let timings = RenderProbe.snapshotTimings()
        let legacy = timings["legacy.sync"]
        XCTAssertNotNil(legacy, "RenderProbe.time should expose the legacy sync duration to code.")
        XCTAssertGreaterThanOrEqual(legacy?.count ?? 0, 1)
        XCTAssertGreaterThanOrEqual(legacy?.totalMs ?? 0, 0)
    }
}
