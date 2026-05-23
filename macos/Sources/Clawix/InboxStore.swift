import Foundation
import Combine

// MARK: - Inbox
//
// A lightweight activity inbox: results and notices the runtime (automations,
// background tasks, scheduled work) leaves for the user. The source of truth is
// a file the runtime appends to at `~/.clawix/inbox/items.json`; this store
// reads it and tracks read-state locally so marking items read survives without
// fighting the writer. When the file is absent the inbox is simply empty.

struct InboxItem: Identifiable, Equatable {
    let id: String
    let title: String
    let summary: String?
    /// Origin label, e.g. the automation that produced this.
    let source: String?
    let createdAt: Date
    /// Optional chat to open when the item is tapped.
    let threadId: String?
    var read: Bool
}

@MainActor
final class InboxStore: ObservableObject {
    static let shared = InboxStore()

    @Published private(set) var items: [InboxItem] = []

    private let readDefaultsKey = "clawix.inbox.readIds"

    private init() {}

    var unreadCount: Int { items.lazy.filter { !$0.read }.count }

    func refresh() {
        let readIds = loadReadIds()
        items = readDisk().map { item in
            var copy = item
            if readIds.contains(item.id) { copy.read = true }
            return copy
        }
    }

    func markRead(_ id: String) {
        var readIds = loadReadIds()
        readIds.insert(id)
        saveReadIds(readIds)
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].read = true
        }
    }

    func markAllRead() {
        var readIds = loadReadIds()
        for item in items { readIds.insert(item.id) }
        saveReadIds(readIds)
        items = items.map { var copy = $0; copy.read = true; return copy }
    }

    // MARK: - Disk

    private func readDisk() -> [InboxItem] {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".clawix/inbox/items.json", isDirectory: false)
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = root["items"] as? [[String: Any]] else { return [] }
        var out: [InboxItem] = []
        for entry in raw {
            guard let id = entry["id"] as? String,
                  let title = (entry["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else { continue }
            let createdMs = (entry["createdAtMs"] as? Double) ?? 0
            out.append(InboxItem(
                id: id,
                title: title,
                summary: (entry["summary"] as? String),
                source: (entry["source"] as? String),
                createdAt: Date(timeIntervalSince1970: createdMs / 1000.0),
                threadId: (entry["threadId"] as? String),
                read: (entry["read"] as? Bool) ?? false
            ))
        }
        // Newest first.
        return out.sorted { $0.createdAt > $1.createdAt }
    }

    private func loadReadIds() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: readDefaultsKey) ?? [])
    }

    private func saveReadIds(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids), forKey: readDefaultsKey)
    }
}
