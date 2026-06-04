import Foundation

struct StreamingRenderScheduler: Equatable {
    struct Delta: Equatable {
        enum Kind: Hashable {
            case content
            case reasoning
        }

        let chatId: UUID
        let messageId: UUID
        let kind: Kind
        let text: String
        let receivedAtMs: Double
    }

    struct Batch: Equatable {
        let chatId: UUID
        let messageId: UUID
        let kind: Delta.Kind
        let text: String
        let firstReceivedAtMs: Double
        let lastReceivedAtMs: Double
        let flushAtMs: Double
        let deltaCount: Int
        let backlogMs: Double
        let wasBackpressured: Bool
    }

    let frameBudgetMs: Double
    let maxBacklogMs: Double
    private var pending: [Key: Pending] = [:]

    init(frameBudgetMs: Double = 16.7, maxBacklogMs: Double = 50) {
        self.frameBudgetMs = max(1, frameBudgetMs)
        self.maxBacklogMs = max(self.frameBudgetMs, maxBacklogMs)
    }

    var pendingDeltaCount: Int {
        pending.values.reduce(0) { $0 + $1.count }
    }

    /// Discard every pending delta for a chat without applying it. Used when an
    /// authoritative replace (daemon canonical content, hydration) supersedes
    /// the coalesced live deltas so they are not double-appended on a later tick.
    mutating func discard(chatId: UUID) {
        pending = pending.filter { $0.key.chatId != chatId }
    }

    mutating func receive(_ delta: Delta) {
        guard !delta.text.isEmpty else { return }
        let key = Key(chatId: delta.chatId, messageId: delta.messageId, kind: delta.kind)
        if var existing = pending[key] {
            existing.text += delta.text
            existing.lastReceivedAtMs = delta.receivedAtMs
            existing.count += 1
            pending[key] = existing
        } else {
            pending[key] = Pending(
                text: delta.text,
                firstReceivedAtMs: delta.receivedAtMs,
                lastReceivedAtMs: delta.receivedAtMs,
                count: 1
            )
        }
    }

    func shouldFlush(nowMs: Double) -> Bool {
        pending.values.contains { pending in
            nowMs - pending.firstReceivedAtMs >= frameBudgetMs
                || nowMs - pending.lastReceivedAtMs >= frameBudgetMs
                || nowMs - pending.firstReceivedAtMs >= maxBacklogMs
        }
    }

    mutating func flush(nowMs: Double, force: Bool = false) -> [Batch] {
        guard force || shouldFlush(nowMs: nowMs) else { return [] }
        let batches = pending
            .map { key, value in
                let backlog = max(0, nowMs - value.firstReceivedAtMs)
                return Batch(
                    chatId: key.chatId,
                    messageId: key.messageId,
                    kind: key.kind,
                    text: value.text,
                    firstReceivedAtMs: value.firstReceivedAtMs,
                    lastReceivedAtMs: value.lastReceivedAtMs,
                    flushAtMs: nowMs,
                    deltaCount: value.count,
                    backlogMs: backlog,
                    wasBackpressured: backlog >= maxBacklogMs
                )
            }
            .sorted {
                if $0.firstReceivedAtMs == $1.firstReceivedAtMs {
                    return $0.messageId.uuidString < $1.messageId.uuidString
                }
                return $0.firstReceivedAtMs < $1.firstReceivedAtMs
            }
        pending.removeAll(keepingCapacity: true)
        return batches
    }

    private struct Key: Hashable {
        let chatId: UUID
        let messageId: UUID
        let kind: Delta.Kind
    }

    private struct Pending: Equatable {
        var text: String
        var firstReceivedAtMs: Double
        var lastReceivedAtMs: Double
        var count: Int
    }
}
