import Foundation
import GRDB

@MainActor
final class HiddenRootsRepository {
    private let dbProvider: @Sendable () -> DatabaseQueue?

    init(db: DatabaseQueue) {
        self.dbProvider = { db }
    }

    init(dbProvider: @escaping @Sendable () -> DatabaseQueue? = { LazyDatabaseProvider.shared.dbQueue }) {
        self.dbProvider = dbProvider
    }

    func isHidden(_ path: String) -> Bool {
        guard let db = dbProvider() else { return false }
        return (try? db.read { try HiddenRootRecord.fetchOne($0, key: path) }) != nil
    }

    func allHidden() -> [String] {
        guard let db = dbProvider() else { return [] }
        let rows = (try? db.read {
            try HiddenRootRecord.order(Column("hidden_at").desc).fetchAll($0)
        }) ?? []
        return rows.map(\.path)
    }

    func count() -> Int {
        guard let db = dbProvider() else { return 0 }
        return (try? db.read { try HiddenRootRecord.fetchCount($0) }) ?? 0
    }

    func hide(_ path: String) {
        guard let db = dbProvider() else { return }
        let now = Int64(Date().timeIntervalSince1970)
        try? db.write { db in
            if try HiddenRootRecord.fetchOne(db, key: path) != nil { return }
            try HiddenRootRecord(path: path, hiddenAt: now).insert(db)
        }
    }

    func show(_ path: String) {
        guard let db = dbProvider() else { return }
        try? db.write { _ = try HiddenRootRecord.deleteOne($0, key: path) }
    }
}
