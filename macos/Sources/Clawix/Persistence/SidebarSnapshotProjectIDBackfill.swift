import Foundation
import GRDB

struct SidebarSnapshotProjectIDBackfillBatchResult: Equatable {
    let sidebarRows: Int
    let projectRows: Int

    var totalRows: Int { sidebarRows + projectRows }
}

final class SidebarSnapshotProjectIDBackfill: @unchecked Sendable {
    static let statusKey = "sidebar_snapshot_project_id_backfill_status"
    static let pendingStatus = "pending"
    static let completeStatus = "complete"

    private enum BackfillError: Error {
        case databaseUnavailable
    }

    private let dbProvider: @Sendable () -> DatabaseQueue?
    private let batchSize: Int
    private let pauseNanos: UInt64

    convenience init(batchSize: Int = 250, pauseNanos: UInt64 = 50_000_000) {
        self.init(
            dbProvider: { LazyDatabaseProvider.shared.dbQueue },
            batchSize: batchSize,
            pauseNanos: pauseNanos
        )
    }

    init(db: DatabaseQueue, batchSize: Int = 250, pauseNanos: UInt64 = 50_000_000) {
        self.dbProvider = { db }
        self.batchSize = max(1, batchSize)
        self.pauseNanos = pauseNanos
    }

    init(
        dbProvider: @escaping @Sendable () -> DatabaseQueue?,
        batchSize: Int = 250,
        pauseNanos: UInt64 = 50_000_000
    ) {
        self.dbProvider = dbProvider
        self.batchSize = max(1, batchSize)
        self.pauseNanos = pauseNanos
    }

    func runUntilComplete() async {
        do {
            guard try currentStatus() != Self.completeStatus else { return }
            while true {
                try Task.checkCancellation()
                let result = try runBatch()
                if result.totalRows == 0 { return }
                if pauseNanos > 0 {
                    try await Task.sleep(nanoseconds: pauseNanos)
                }
            }
        } catch is CancellationError {
            return
        } catch {
            try? markStatus(Self.pendingStatus)
        }
    }

    @discardableResult
    func runBatch() throws -> SidebarSnapshotProjectIDBackfillBatchResult {
        let db = try queue()
        try Task.checkCancellation()
        let sidebarRows = try db.write { database in
            try Self.backfillBatch(in: database, table: "sidebar_snapshot", limit: batchSize)
        }
        try Task.checkCancellation()
        let projectRows = try db.write { database in
            try Self.backfillBatch(in: database, table: "sidebar_snapshot_project", limit: batchSize)
        }
        let result = SidebarSnapshotProjectIDBackfillBatchResult(
            sidebarRows: sidebarRows,
            projectRows: projectRows
        )
        if result.totalRows == 0 {
            try markStatus(Self.completeStatus)
        } else {
            try markStatus(Self.pendingStatus)
        }
        return result
    }

    func currentStatus() throws -> String? {
        let db = try queue()
        return try db.read { database in
            try MetaRow.fetchOne(database, key: Self.statusKey)?.value
        }
    }

    private func markStatus(_ status: String) throws {
        let db = try queue()
        try db.write { database in
            try MetaRow(key: Self.statusKey, value: status).upsert(database)
        }
    }

    private func queue() throws -> DatabaseQueue {
        guard let db = dbProvider() else { throw BackfillError.databaseUnavailable }
        return db
    }

    private static func backfillBatch(in db: GRDB.Database, table: String, limit: Int) throws -> Int {
        let candidates = try Row.fetchAll(db, sql: """
            SELECT snapshot.thread_id AS thread_id, projects.id AS project_id
            FROM \(table) AS snapshot
            JOIN projects ON projects.path = snapshot.project_path
            WHERE (snapshot.project_id IS NULL OR snapshot.project_id = '')
              AND snapshot.project_path IS NOT NULL
              AND snapshot.project_path <> ''
            ORDER BY snapshot.updated_at DESC
            LIMIT ?
        """, arguments: [limit])

        for row in candidates {
            let threadId: String = row["thread_id"]
            let projectId: String = row["project_id"]
            try db.execute(
                sql: "UPDATE \(table) SET project_id = ? WHERE thread_id = ?",
                arguments: [projectId, threadId]
            )
        }

        return candidates.count
    }
}
