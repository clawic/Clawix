import Combine
import CoreGraphics
import Foundation

/// The centralized, bounded compute/presentation layer for ONE open chat. The
/// session-side mirror of `SidebarStore`.
///
/// It subscribes ONLY to the narrow per-chat publishers:
///   - the chat's `ChatTranscriptStore.$messageIds` for structure (a message
///     added/removed re-derives the window + the one new row), and
///   - each visible message's `ChatMessageStore.$message` for content (a delta
///     on one message re-derives only that one row's display model).
///
/// It produces draw-only value types (`MessageRowDisplayModel`,
/// `TranscriptWindow`) and bumps `revision` only on named events. A delta on a
/// sibling message store advances nothing for the unaffected rows; an unrelated
/// `AppState` write never reaches this store at all because it observes the
/// per-chat stores, not the god-object.
///
/// One instance per open chat, created and destroyed by the route. `bind` lets
/// `ChatView` retarget the same store object as the route changes without
/// re-subscribing the whole app.
@MainActor
final class SessionPresentationStore: ObservableObject {
    @Published private(set) var chatId: UUID?
    @Published private(set) var rows: [MessageRowDisplayModel] = []
    @Published private(set) var window: TranscriptWindow = .empty
    @Published private(set) var revision: UInt64 = 0

    /// Windowing knobs. Kept here so the store owns the single "what to draw"
    /// decision; the view passes geometry, the store decides the bounded set.
    var visibleLimit: Int = 40
    var overscanBefore: Int = 6
    var estimatedRowHeight: CGFloat = 320

    private weak var chatStore: ChatStore?
    private var transcript: ChatTranscriptStore?
    private var structureCancellable: AnyCancellable?
    private var contentCancellables: [UUID: AnyCancellable] = [:]
    private var modelsById: [UUID: MessageRowDisplayModel] = [:]

    init() {}

    /// Point the store at a chat. Tears down the previous chat's subscriptions
    /// (a destroyed route stops observing) and wires the new chat's narrow
    /// per-chat publishers. Passing `nil` detaches the store.
    func bind(chatId: UUID?, chatStore: ChatStore) {
        guard self.chatId != chatId || self.chatStore !== chatStore else { return }
        teardown()
        self.chatStore = chatStore
        self.chatId = chatId
        guard let chatId else {
            publishEmpty()
            return
        }
        let transcript = chatStore.transcript(forCreating: chatId)
        self.transcript = transcript

        // Structure: a message added/removed publishes the id list once. We
        // re-derive only the rows whose id set changed and rebuild the window.
        structureCancellable = transcript.$messageIds
            .sink { [weak self] ids in
                self?.applyStructure(ids)
            }
    }

    /// Read-only access for the view: the precomputed model for an id, if any.
    func model(for id: UUID) -> MessageRowDisplayModel? {
        modelsById[id]
    }

    // MARK: - Structure (named event: message added/removed)

    private func applyStructure(_ ids: [UUID]) {
        guard let transcript else { return }
        let idSet = Set(ids)

        // Drop content subscriptions + cached models for ids that left.
        for id in Array(contentCancellables.keys) where !idSet.contains(id) {
            contentCancellables[id] = nil
            modelsById[id] = nil
        }

        // Subscribe to any newly-present message stores; derive their model now.
        for id in ids where contentCancellables[id] == nil {
            guard let store = transcript.messageStore(id: id) else { continue }
            modelsById[id] = MessageRowDisplayModel.make(from: store.message, now: Date())
            // Per-message content subscription: a delta on THIS message store
            // re-derives only THIS row. `dropFirst` so the initial value (just
            // derived above) does not double-publish.
            contentCancellables[id] = store.$message
                .dropFirst()
                .sink { [weak self] message in
                    self?.applyContent(message)
                }
        }

        rebuild(ids: ids)
    }

    // MARK: - Content (named event: one message changed)

    private func applyContent(_ message: ChatMessage) {
        let next = MessageRowDisplayModel.make(from: message, now: Date())
        guard modelsById[message.id] != next else { return }
        modelsById[message.id] = next
        if let index = rows.firstIndex(where: { $0.id == message.id }) {
            rows[index] = next
            revision &+= 1
        }
    }

    // MARK: - Rebuild

    private func rebuild(ids: [UUID]) {
        let nextRows = ids.compactMap { modelsById[$0] }
        let messages = (transcript?.messages) ?? []
        let model = TranscriptWindowModel.latestWindow(
            messages: messages,
            visibleLimit: visibleLimit,
            overscanBefore: overscanBefore,
            estimatedRowHeight: estimatedRowHeight
        )
        let nextWindow = TranscriptWindow(orderedIds: ids, model: model)

        var changed = false
        if rows != nextRows {
            rows = nextRows
            changed = true
        }
        if window != nextWindow {
            window = nextWindow
            changed = true
        }
        if changed {
            revision &+= 1
        }
    }

    private func publishEmpty() {
        modelsById.removeAll()
        if !rows.isEmpty { rows = [] }
        if window != .empty { window = .empty }
        revision &+= 1
    }

    private func teardown() {
        structureCancellable = nil
        contentCancellables.removeAll()
        transcript = nil
    }
}
