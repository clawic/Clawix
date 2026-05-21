import Foundation
import GRDB

@MainActor
final class ChatProjectsRepository {
    private let dbProvider: @Sendable () -> DatabaseQueue?

    init(db: DatabaseQueue) {
        self.dbProvider = { db }
    }

    init(dbProvider: @escaping @Sendable () -> DatabaseQueue? = { LazyDatabaseProvider.shared.dbQueue }) {
        self.dbProvider = dbProvider
    }

    func overridesCount() -> Int {
        guard let db = dbProvider() else { return 0 }
        return (try? db.read { try ChatProjectOverrideRow.fetchCount($0) }) ?? 0
    }

    func projectlessCount() -> Int {
        guard let db = dbProvider() else { return 0 }
        return (try? db.read { try ProjectlessThreadRow.fetchCount($0) }) ?? 0
    }

    func allOverrides() -> [String: String] {
        guard let db = dbProvider() else { return [:] }
        let rows = (try? db.read { try ChatProjectOverrideRow.fetchAll($0) }) ?? []
        var dict: [String: String] = [:]
        for row in rows { dict[row.threadId] = row.projectPath }
        return dict
    }

    func overridePath(for threadId: String) -> String? {
        guard let db = dbProvider() else { return nil }
        return try? db.read { try ChatProjectOverrideRow.fetchOne($0, key: threadId)?.projectPath }
    }

    func setOverride(threadId: String, projectPath: String) {
        guard let db = dbProvider() else { return }
        try? db.write { db in
            let row = ChatProjectOverrideRow(threadId: threadId, projectPath: projectPath)
            try row.upsert(db)
            _ = try ProjectlessThreadRow.deleteOne(db, key: threadId)
        }
    }

    func clearOverride(threadId: String) {
        guard let db = dbProvider() else { return }
        try? db.write { _ = try ChatProjectOverrideRow.deleteOne($0, key: threadId) }
    }

    func allProjectless() -> Set<String> {
        guard let db = dbProvider() else { return [] }
        let rows = (try? db.read { try ProjectlessThreadRow.fetchAll($0) }) ?? []
        return Set(rows.map(\.threadId))
    }

    func isProjectless(_ threadId: String) -> Bool {
        guard let db = dbProvider() else { return false }
        return (try? db.read { try ProjectlessThreadRow.fetchOne($0, key: threadId) }) != nil
    }

    func markProjectless(_ threadId: String) {
        guard let db = dbProvider() else { return }
        try? db.write { db in
            try ProjectlessThreadRow(threadId: threadId).upsert(db)
            _ = try ChatProjectOverrideRow.deleteOne(db, key: threadId)
        }
    }

    func unmarkProjectless(_ threadId: String) {
        guard let db = dbProvider() else { return }
        try? db.write { _ = try ProjectlessThreadRow.deleteOne($0, key: threadId) }
    }
}
