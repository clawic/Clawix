import Foundation
import GRDB

/// GRDB row type for the `terminal_tabs` table. The split
/// tree is stored as a JSON blob so the schema doesn't need to know
/// about its recursive shape; encode/decode happens in the repository.
struct TerminalTabRecord: Codable, FetchableRecord, MutablePersistableRecord, Equatable {
    var id: String
    var chatId: String
    var label: String
    var initialCwd: String
    var layoutJson: String
    var focusedLeaf: String?
    var position: Int
    var createdAt: Int64

    static var databaseTableName: String { "terminal_tabs" }

    enum CodingKeys: String, CodingKey {
        case id
        case chatId = "chat_id"
        case label
        case initialCwd = "initial_cwd"
        case layoutJson = "layout_json"
        case focusedLeaf = "focused_leaf"
        case position
        case createdAt = "created_at"
    }
}

@MainActor
final class TerminalTabsRepository {
    static let shared = TerminalTabsRepository()

    private let dbProvider: @Sendable () -> DatabaseQueue?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(dbQueue: DatabaseQueue) {
        self.dbProvider = { dbQueue }
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    private init(dbProvider: @escaping @Sendable () -> DatabaseQueue? = { LazyDatabaseProvider.shared.dbQueue }) {
        self.dbProvider = dbProvider
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    func loadTabs(chatId: UUID) -> [TerminalTab] {
        guard let dbQueue = dbProvider() else { return [] }
        let chatKey = chatId.uuidString
        let records: [TerminalTabRecord]
        do {
            records = try dbQueue.read { db in
                try TerminalTabRecord
                    .filter(Column("chat_id") == chatKey)
                    .order(Column("position"))
                    .fetchAll(db)
            }
        } catch {
            return []
        }
        return records.compactMap { record -> TerminalTab? in
            guard let id = UUID(uuidString: record.id),
                  let layoutData = record.layoutJson.data(using: .utf8),
                  let layout = try? decoder.decode(TerminalSplitNode.self, from: layoutData) else {
                return nil
            }
            return TerminalTab(
                id: id,
                chatId: chatId,
                label: record.label,
                initialCwd: record.initialCwd,
                layout: layout,
                focusedLeafId: record.focusedLeaf.flatMap(UUID.init(uuidString:)),
                position: record.position,
                createdAt: Date(timeIntervalSince1970: TimeInterval(record.createdAt))
            )
        }
    }

    func upsert(_ tab: TerminalTab) {
        let dbQueue = dbProvider()
        guard let layoutData = try? encoder.encode(tab.layout),
              let layoutString = String(data: layoutData, encoding: .utf8) else {
            return
        }
        let record = TerminalTabRecord(
            id: tab.id.uuidString,
            chatId: tab.chatId.uuidString,
            label: tab.label,
            initialCwd: tab.initialCwd,
            layoutJson: layoutString,
            focusedLeaf: tab.focusedLeafId?.uuidString,
            position: tab.position,
            createdAt: Int64(tab.createdAt.timeIntervalSince1970)
        )
        if let dbQueue {
            do {
                try dbQueue.write { db in
                    var mutable = record
                    try mutable.save(db)
                }
            } catch {
                // Persistence failures are non-fatal: the live state is
                // still in memory; the next save attempt may succeed.
            }
        }
        ClawJSAppStateClient.upsertTerminalTab(
            id: tab.id.uuidString,
            title: tab.label,
            cwd: tab.initialCwd,
            sortOrder: tab.position,
            metadata: [
                "chatId": tab.chatId.uuidString,
                "layoutJson": layoutString,
                "focusedLeaf": tab.focusedLeafId?.uuidString ?? "",
            ]
        )
    }

    func delete(tabId: UUID) {
        let key = tabId.uuidString
        if let dbQueue = dbProvider() {
            try? dbQueue.write { db in
                _ = try TerminalTabRecord.deleteOne(db, key: key)
            }
        }
        ClawJSAppStateClient.deleteTerminalTab(id: key)
    }

    func deleteAllForChat(_ chatId: UUID) {
        let dbQueue = dbProvider()
        let tabIds: [String]
        if let dbQueue {
            tabIds = (try? dbQueue.read { db in
                try String.fetchAll(
                    db,
                    sql: "SELECT id FROM terminal_tabs WHERE chat_id = ?",
                    arguments: [chatId.uuidString]
                )
            }) ?? []
        } else {
            tabIds = []
        }
        let key = chatId.uuidString
        if let dbQueue {
            try? dbQueue.write { db in
                try TerminalTabRecord
                    .filter(Column("chat_id") == key)
                    .deleteAll(db)
            }
        }
        for tabId in tabIds {
            ClawJSAppStateClient.deleteTerminalTab(id: tabId)
        }
    }
}
