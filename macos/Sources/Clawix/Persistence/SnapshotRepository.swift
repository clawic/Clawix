import Foundation
import GRDB

// Persistent cache of the sidebar's last applied state, used to paint
// Pinned + recent chats instantly on the next launch instead of waiting
// for the runtime to bootstrap and paginate threads.
//
// This is presentation cache, not source of truth: every successful
// `applyThreads` / `mergeThreads` rewrites it from the just-applied
// `chats[]`. Reads are cheap (one indexed query). Writes happen off
// the main thread via GRDB's serialized queue, so the repository is
// nonisolated and Sendable on purpose.
final class SnapshotRepository: @unchecked Sendable {
    private let dbProvider: @Sendable () -> DatabaseQueue?

    init(db: DatabaseQueue) {
        self.dbProvider = { db }
    }

    @MainActor
    init(dbProvider: @escaping @Sendable () -> DatabaseQueue? = { LazyDatabaseProvider.shared.dbQueue }) {
        self.dbProvider = dbProvider
    }

    func count() -> Int {
        guard let db = dbProvider() else { return 0 }
        return (try? db.read { try SidebarSnapshotRow.fetchCount($0) }) ?? 0
    }

    func isAvailable() -> Bool {
        dbProvider() != nil
    }

    /// Top N rows for the first paint, ordered so pinned chats land first
    /// and the rest follow by recency.
    func loadTop(limit: Int) -> [SidebarSnapshotRow] {
        guard let db = dbProvider() else { return [] }
        return (try? db.read { db in
            try SidebarSnapshotRow.fetchAll(db, sql: """
                SELECT * FROM sidebar_snapshot
                ORDER BY pinned DESC, updated_at DESC
                LIMIT ?
            """, arguments: [limit])
        }) ?? []
    }

    func loadAll() -> [SidebarSnapshotRow] {
        guard let db = dbProvider() else { return [] }
        return (try? db.read { db in
            try SidebarSnapshotRow.fetchAll(db, sql: """
                SELECT * FROM sidebar_snapshot
                ORDER BY pinned DESC, updated_at DESC
            """)
        }) ?? []
    }

    func load(chatUuid: String) -> SidebarSnapshotRow? {
        guard let db = dbProvider() else { return nil }
        return try? db.read { db in
            try SidebarSnapshotRow.fetchOne(
                db,
                sql: """
                    SELECT * FROM sidebar_snapshot
                    WHERE lower(chat_uuid) = lower(?)
                    LIMIT 1
                """,
                arguments: [chatUuid]
            )
        }
    }

    func load(threadId: String) -> SidebarSnapshotRow? {
        guard let db = dbProvider() else { return nil }
        return try? db.read { db in
            try SidebarSnapshotRow.fetchOne(
                db,
                sql: """
                    SELECT * FROM sidebar_snapshot
                    WHERE lower(thread_id) = lower(?)
                    LIMIT 1
                """,
                arguments: [threadId]
            )
        }
    }

    /// Replace the whole snapshot in a single transaction. Called after
    /// every successful applyThreads/mergeThreads with the canonical
    /// in-memory chats list.
    func replaceAll(_ rows: [SidebarSnapshotRow]) {
        if let db = dbProvider() {
            try? db.write { db in
                try db.execute(sql: "DELETE FROM sidebar_snapshot")
                for row in rows {
                    try row.insert(db)
                }
            }
        }
        let snapshots = rows.map {
            ClawJSAppStateSidebarSnapshot(
                threadId: $0.threadId,
                chatUuid: $0.chatUuid,
                title: $0.title,
                cwd: $0.cwd,
                projectId: $0.projectId,
                projectPath: $0.projectPath,
                updatedAt: ISO8601DateFormatter().string(
                    from: Date(timeIntervalSince1970: TimeInterval($0.updatedAt))
                ),
                archived: $0.archived != 0,
                pinned: $0.pinned != 0
            )
        }
        Task { @MainActor in
            ClawJSAppStateClient.replaceSidebarSnapshots(snapshots)
        }
    }

    /// Returns every persisted per-project row, ordered so each
    /// project's most-recent chats come first. Kept for maintenance and
    /// migration tests; first paint must use paged project reads instead.
    func loadAllProjectIndexed() -> [SidebarSnapshotProjectRow] {
        guard let db = dbProvider() else { return [] }
        return (try? db.read { db in
            try SidebarSnapshotProjectRow.fetchAll(db, sql: """
                SELECT * FROM sidebar_snapshot_project
                WHERE (project_id IS NOT NULL AND project_id <> '')
                   OR (project_path IS NOT NULL AND project_path <> '')
                ORDER BY COALESCE(NULLIF(project_id, ''), project_path) ASC, updated_at DESC
            """)
        }) ?? []
    }

    /// Paged read for one project's persisted sidebar rows. Current rows
    /// match on stable `project_id`; legacy rows with no id fall back to
    /// `project_path` so older caches remain usable without a migration.
    func loadProjectIndexed(
        projectId: String?,
        projectPath: String,
        limit: Int,
        offset: Int = 0
    ) -> [SidebarSnapshotProjectRow] {
        guard let db = dbProvider(), limit > 0 else { return [] }
        let stableId = projectId?.isEmpty == false ? projectId : nil
        guard stableId != nil || !projectPath.isEmpty else { return [] }
        return (try? db.read { db in
            if let stableId {
                return try SidebarSnapshotProjectRow.fetchAll(db, sql: """
                    SELECT * FROM (
                        SELECT * FROM sidebar_snapshot_project
                        WHERE project_id = ?
                          AND project_id <> ''

                        UNION ALL

                        SELECT * FROM sidebar_snapshot_project
                        WHERE
                           (project_id IS NULL OR project_id = '')
                           AND project_path = ?
                    )
                    ORDER BY updated_at DESC
                    LIMIT ? OFFSET ?
                """, arguments: [stableId, projectPath, limit, max(offset, 0)])
            }
            return try SidebarSnapshotProjectRow.fetchAll(db, sql: """
                SELECT * FROM sidebar_snapshot_project
                WHERE (project_id IS NULL OR project_id = '')
                  AND project_path = ?
                ORDER BY updated_at DESC
                LIMIT ? OFFSET ?
            """, arguments: [projectPath, limit, max(offset, 0)])
        }) ?? []
    }

    func projectPathHints() -> [String] {
        guard let db = dbProvider() else { return [] }
        return (try? db.read { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT project_path
                FROM (
                    SELECT project_path FROM sidebar_snapshot_project
                    UNION ALL
                    SELECT project_path FROM sidebar_snapshot
                )
                WHERE project_path IS NOT NULL AND project_path <> ''
                ORDER BY lower(project_path)
            """)
        }) ?? []
    }

    /// Replace the entire per-project index in one transaction. Called
    /// after every applyThreads/mergeThreads with the in-memory chats
    /// already filtered to those that belong to a known project.
    func replaceProjectIndex(_ rows: [SidebarSnapshotProjectRow]) {
        guard let db = dbProvider() else { return }
        try? db.write { db in
            try db.execute(sql: "DELETE FROM sidebar_snapshot_project")
            for row in rows {
                try row.insert(db)
            }
        }
    }

    /// Replace the rows for a single project. Used by the per-project
    /// background refresh so a fresh fetch for one folder doesn't have
    /// to rewrite every other project's rows.
    func replaceProjectIndexFor(projectId: String, projectPath: String, rows: [SidebarSnapshotProjectRow]) {
        guard let db = dbProvider() else { return }
        try? db.write { db in
            try db.execute(
                sql: """
                    DELETE FROM sidebar_snapshot_project
                    WHERE project_id = ?
                       OR (
                           (project_id IS NULL OR project_id = '')
                           AND project_path = ?
                       )
                """,
                arguments: [projectId, projectPath]
            )
            for row in rows where row.projectId == projectId {
                try row.insert(db)
            }
        }
    }
}
