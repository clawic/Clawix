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
}
