import Foundation
import GRDB

@MainActor
final class MetaRepository {
    private let dbProvider: @Sendable () -> DatabaseQueue?

    init(db: DatabaseQueue) {
        self.dbProvider = { db }
    }

    init(dbProvider: @escaping @Sendable () -> DatabaseQueue? = { LazyDatabaseProvider.shared.dbQueue }) {
        self.dbProvider = dbProvider
    }

    func string(forKey key: String) -> String? {
        guard let db = dbProvider() else { return nil }
        return try? db.read { try MetaRow.fetchOne($0, key: key)?.value }
    }

    func setString(_ value: String, forKey key: String) {
        guard let db = dbProvider() else { return }
        try? db.write { try MetaRow(key: key, value: value).upsert($0) }
    }

    func boolValue(forKey key: String) -> Bool {
        string(forKey: key) == "true"
    }

    func setBool(_ value: Bool, forKey key: String) {
        setString(value ? "true" : "false", forKey: key)
    }
}
