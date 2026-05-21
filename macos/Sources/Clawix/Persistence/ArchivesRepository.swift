import Foundation
import GRDB

@MainActor
final class ArchivesRepository {
    private let dbProvider: @Sendable () -> DatabaseQueue?

    init(db: DatabaseQueue) {
        self.dbProvider = { db }
    }

    init(dbProvider: @escaping @Sendable () -> DatabaseQueue? = { LazyDatabaseProvider.shared.dbQueue }) {
        self.dbProvider = dbProvider
    }

    func count() -> Int {
        guard let db = dbProvider() else { return 0 }
        return (try? db.read { try LocalArchiveRecord.fetchCount($0) }) ?? 0
    }

    func isArchived(_ threadId: String) -> Bool {
        guard let db = dbProvider() else { return false }
        return (try? db.read { try LocalArchiveRecord.fetchOne($0, key: threadId) }) != nil
    }

    func allArchived() -> Set<String> {
        guard let db = dbProvider() else { return [] }
        let rows = (try? db.read { try LocalArchiveRecord.fetchAll($0) }) ?? []
        return Set(rows.map(\.threadId))
    }

    func archive(_ threadId: String) {
        let now = Int64(Date().timeIntervalSince1970)
        if let db = dbProvider() {
            try? db.write { db in
                if try LocalArchiveRecord.fetchOne(db, key: threadId) != nil { return }
                try LocalArchiveRecord(threadId: threadId, archivedAt: now).insert(db)
            }
        }
        ClawJSAppStateClient.archive(threadId: threadId)
    }

    func unarchive(_ threadId: String) {
        if let db = dbProvider() {
            try? db.write { _ = try LocalArchiveRecord.deleteOne($0, key: threadId) }
        }
        ClawJSAppStateClient.unarchive(threadId: threadId)
    }

    func bulkArchive(_ threadIds: [String]) {
        guard !threadIds.isEmpty else { return }
        let now = Int64(Date().timeIntervalSince1970)
        if let db = dbProvider() {
            try? db.write { db in
                for threadId in threadIds {
                    if try LocalArchiveRecord.fetchOne(db, key: threadId) != nil { continue }
                    try LocalArchiveRecord(threadId: threadId, archivedAt: now).insert(db)
                }
            }
        }
        for threadId in threadIds {
            ClawJSAppStateClient.archive(threadId: threadId)
        }
    }

    func bulkUnarchive(_ threadIds: [String]) {
        guard !threadIds.isEmpty else { return }
        if let db = dbProvider() {
            try? db.write { db in
                for threadId in threadIds {
                    _ = try LocalArchiveRecord.deleteOne(db, key: threadId)
                }
            }
        }
        for threadId in threadIds {
            ClawJSAppStateClient.unarchive(threadId: threadId)
        }
    }
}
