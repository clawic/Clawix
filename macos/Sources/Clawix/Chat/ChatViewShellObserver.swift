import Combine
import Foundation

/// The narrow, named-event observer for `ChatView`'s non-transcript shell.
///
/// `ChatView` no longer holds `@EnvironmentObject var appState` (ADR 0041/0042):
/// it must not re-evaluate the whole open session on every god-object write.
/// The transcript rows come from `SessionPresentationStore`; this object is the
/// session-side mirror of `SidebarStore` for the small set of shell fields the
/// `ChatView` body still reacts to:
///   - the active route (does this `ChatView` own the main route right now),
///   - the find bar (open flag, target chat, query),
///   - the per-chat summary snapshot (title / branch / git / fork banner).
///
/// It subscribes ONLY to the specific `AppState` publishers for those fields and
/// to `chatStore.$summaries` for the chat snapshot, re-publishing them through
/// its own `@Published` properties. A streaming delta (which never touches these
/// publishers) does not advance it; an unrelated `AppState` write (image preview,
/// browser chrome, search) does not advance it.
@MainActor
final class ChatViewShellObserver: ObservableObject {
    @Published private(set) var currentRoute: SidebarRoute = .home
    @Published private(set) var isFindBarOpen: Bool = false
    @Published private(set) var findChatId: UUID?
    @Published private(set) var findQuery: String = ""
    @Published private(set) var currentFindIndex: Int = 0
    @Published private(set) var findMatchCount: Int = 0
    /// Summary-only snapshot (no transcript messages) of the bound chat. Empty
    /// messages by design: the transcript is observed separately, so shell
    /// re-renders stay decoupled from per-token streaming.
    @Published private(set) var chat: Chat?

    private weak var appState: AppState?
    private weak var chatStore: ChatStore?
    private var chatId: UUID?
    private var cancellables: Set<AnyCancellable> = []

    init() {}

    /// Point the observer at one chat. Tears down the previous subscriptions and
    /// wires the narrow per-field publishers for the new chat.
    func bind(chatId: UUID, appState: AppState) {
        guard self.chatId != chatId || self.appState !== appState else { return }
        cancellables.removeAll()
        self.appState = appState
        self.chatStore = appState.chatStore
        self.chatId = chatId

        currentRoute = appState.currentRoute
        isFindBarOpen = appState.isFindBarOpen
        findChatId = appState.findChatId
        findQuery = appState.findQuery
        currentFindIndex = appState.currentFindIndex
        findMatchCount = appState.findMatches.count
        chat = appState.chatStore.summarySnapshot(id: chatId)

        appState.$currentRoute
            .removeDuplicates()
            .sink { [weak self] route in self?.currentRoute = route }
            .store(in: &cancellables)
        appState.$isFindBarOpen
            .removeDuplicates()
            .sink { [weak self] open in self?.isFindBarOpen = open }
            .store(in: &cancellables)
        appState.$findChatId
            .removeDuplicates()
            .sink { [weak self] id in self?.findChatId = id }
            .store(in: &cancellables)
        appState.$findQuery
            .removeDuplicates()
            .sink { [weak self] query in self?.findQuery = query }
            .store(in: &cancellables)
        appState.$currentFindIndex
            .removeDuplicates()
            .sink { [weak self] index in self?.currentFindIndex = index }
            .store(in: &cancellables)
        appState.$findMatches
            .map(\.count)
            .removeDuplicates()
            .sink { [weak self] count in self?.findMatchCount = count }
            .store(in: &cancellables)
        // A single-row summary change (title rename, branch switch, fork banner,
        // active-turn flip) re-publishes only this chat's snapshot.
        appState.chatStore.$summaries
            .map { [weak self] _ in self?.chatStore?.summarySnapshot(id: chatId) }
            .removeDuplicates()
            .sink { [weak self] snapshot in self?.chat = snapshot }
            .store(in: &cancellables)
    }

    /// True when this observer's chat owns the active main route.
    func isCurrentMainChatRoute(chatId: UUID) -> Bool {
        guard case let .chat(routeChatId) = currentRoute else { return false }
        return routeChatId == chatId
    }
}
