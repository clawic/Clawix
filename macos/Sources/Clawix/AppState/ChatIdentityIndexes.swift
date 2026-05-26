import Foundation
import ClawixCore

extension AppState {
    func chatIdByThreadId(_ source: [Chat]) -> [String: UUID] {
        var out: [String: UUID] = [:]
        out.reserveCapacity(source.count)
        for chat in source {
            guard let threadId = chat.clawixThreadId, out[threadId] == nil else { continue }
            out[threadId] = chat.id
        }
        return out
    }

    func chatByThreadId(_ source: [Chat]) -> [String: Chat] {
        var out: [String: Chat] = [:]
        out.reserveCapacity(source.count)
        for chat in source {
            guard let threadId = chat.clawixThreadId, out[threadId] == nil else { continue }
            out[threadId] = chat
        }
        return out
    }

    func chatSummaryIdByThreadId(_ source: [ChatSummary]) -> [String: UUID] {
        var out: [String: UUID] = [:]
        out.reserveCapacity(source.count)
        for summary in source {
            guard let threadId = summary.clawixThreadId, out[threadId] == nil else { continue }
            out[threadId] = summary.id
        }
        return out
    }

    func deduplicatedWireSessions(_ source: [WireSession]) -> [WireSession] {
        var out: [WireSession] = []
        var indexByKey: [String: Int] = [:]
        out.reserveCapacity(source.count)
        indexByKey.reserveCapacity(source.count)

        for wire in source {
            let key = wire.threadId.map { "thread:\($0.lowercased())" } ?? "id:\(wire.id.lowercased())"
            if let index = indexByKey[key] {
                let existingActivity = out[index].lastMessageAt ?? out[index].createdAt
                let incomingActivity = wire.lastMessageAt ?? wire.createdAt
                if incomingActivity >= existingActivity {
                    out[index] = wire
                }
            } else {
                indexByKey[key] = out.count
                out.append(wire)
            }
        }
        return out
    }

    func boundedSidebarWireSessions(_ source: [WireSession]) -> [WireSession] {
        let activeCount = source.lazy.filter { !$0.isArchived }.count
        let pinnedCount = source.lazy.filter { !$0.isArchived && $0.isPinned }.count
        let archivedCount = source.lazy.filter(\.isArchived).count
        guard activeCount > Self.sidebarBootstrapRecentLimit
            || pinnedCount > Self.startupPinnedSessionLimit
            || archivedCount > Self.archivedSidebarLimit
        else { return source }

        func activityDate(_ wire: WireSession) -> Date {
            wire.lastMessageAt ?? wire.createdAt
        }

        func key(_ wire: WireSession) -> String {
            wire.threadId.map { "thread:\($0.lowercased())" } ?? "id:\(wire.id.lowercased())"
        }

        let active = source
            .filter { !$0.isArchived }
            .sorted { activityDate($0) > activityDate($1) }
        let archived = source
            .filter(\.isArchived)
            .sorted { activityDate($0) > activityDate($1) }

        var selectedKeys = Set<String>()
        var bounded: [WireSession] = []
        bounded.reserveCapacity(Self.sidebarBootstrapRecentLimit + Self.archivedSidebarLimit)

        func appendActive(_ wire: WireSession) {
            guard bounded.count < Self.sidebarBootstrapRecentLimit else { return }
            let identity = key(wire)
            guard selectedKeys.insert(identity).inserted else { return }
            bounded.append(wire)
        }

        for wire in active where wire.hasActiveTurn {
            appendActive(wire)
        }

        var emittedPinned = bounded.filter(\.isPinned).count
        for wire in active where wire.isPinned && !wire.hasActiveTurn {
            guard emittedPinned < Self.startupPinnedSessionLimit else { break }
            let before = bounded.count
            appendActive(wire)
            if bounded.count > before {
                emittedPinned += 1
            }
        }

        for wire in active where !wire.isPinned && !wire.hasActiveTurn {
            appendActive(wire)
        }

        for wire in archived.prefix(Self.archivedSidebarLimit) {
            bounded.append(wire)
        }

        return bounded
    }

    func boundedSidebarThreads(
        _ source: [AgentThreadSummary],
        pinnedThreadIds: [String]
    ) -> [AgentThreadSummary] {
        let pinnedSet = Set(pinnedThreadIds)
        let activeCount = source.lazy.filter { !$0.archived }.count
        let pinnedCount = source.lazy.filter { !$0.archived && pinnedSet.contains($0.id) }.count
        let archivedCount = source.lazy.filter(\.archived).count
        guard activeCount > Self.sidebarBootstrapRecentLimit
            || pinnedCount > Self.startupPinnedSessionLimit
            || archivedCount > Self.archivedSidebarLimit
        else { return source }

        let active = source
            .filter { !$0.archived }
            .sorted { $0.updatedAt > $1.updatedAt }
        let archived = source
            .filter(\.archived)
            .sorted { $0.updatedAt > $1.updatedAt }

        var selectedIds = Set<String>()
        var bounded: [AgentThreadSummary] = []
        bounded.reserveCapacity(Self.sidebarBootstrapRecentLimit + Self.archivedSidebarLimit)

        func appendActive(_ thread: AgentThreadSummary) {
            guard bounded.count < Self.sidebarBootstrapRecentLimit else { return }
            guard selectedIds.insert(thread.id).inserted else { return }
            bounded.append(thread)
        }

        var emittedPinned = 0
        for thread in active where pinnedSet.contains(thread.id) {
            guard emittedPinned < Self.startupPinnedSessionLimit else { break }
            appendActive(thread)
            emittedPinned += 1
        }

        for thread in active where !pinnedSet.contains(thread.id) {
            appendActive(thread)
        }

        bounded.append(contentsOf: archived.prefix(Self.archivedSidebarLimit))
        return bounded
    }
}
