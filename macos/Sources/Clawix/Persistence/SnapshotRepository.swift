import Foundation
import GRDB

// Persistent cache of the sidebar's last applied state, used to paint
// Pinned + chat list instantly on the next launch instead of waiting for
// the runtime to bootstrap and paginate threads.
//
// This is presentation cache, not source of truth: every successful
// `applyThreads` / `mergeThreads` rewrites it from the just-applied
// `chats[]`. Reads are cheap (one indexed query). Writes happen off
// the main thread via GRDB's serialized queue, so the repository is
// nonisolated and Sendable on purpose.
final class SnapshotRepository: @unchecked Sendable {
    private let db: DatabaseQueue

    @MainActor
    init(db: DatabaseQueue = Database.shared.dbQueue) {
        self.db = db
    }

    func count() -> Int {
        (try? db.read { try SidebarSnapshotRow.fetchCount($0) }) ?? 0
    }

    /// Top N rows for the first paint, ordered so pinned chats land first
    /// and the rest follow by recency.
    func loadTop(limit: Int) -> [SidebarSnapshotRow] {
        (try? db.read { db in
            try SidebarSnapshotRow.fetchAll(db, sql: """
                SELECT * FROM sidebar_snapshot
                ORDER BY pinned DESC, updated_at DESC
                LIMIT ?
            """, arguments: [limit])
        }) ?? []
    }

    func loadAll() -> [SidebarSnapshotRow] {
        (try? db.read { db in
            try SidebarSnapshotRow.fetchAll(db, sql: """
                SELECT * FROM sidebar_snapshot
                ORDER BY pinned DESC, updated_at DESC
            """)
        }) ?? []
    }

    func load(chatUuid: String) -> SidebarSnapshotRow? {
        try? db.read { db in
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
        try? db.read { db in
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
        try? db.write { db in
            try db.execute(sql: "DELETE FROM sidebar_snapshot")
            for row in rows {
                try row.insert(db)
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
    /// project's most-recent chats come first. Loaded on first paint
    /// so every accordion has content available before the runtime
    /// answers a single RPC.
    func loadAllProjectIndexed() -> [SidebarSnapshotProjectRow] {
        (try? db.read { db in
            try SidebarSnapshotProjectRow.fetchAll(db, sql: """
                SELECT * FROM sidebar_snapshot_project
                WHERE project_id IS NOT NULL AND project_id <> ''
                ORDER BY project_id ASC, updated_at DESC
            """)
        }) ?? []
    }

    func projectPathHints() -> [String] {
        (try? db.read { db in
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
    func replaceProjectIndexFor(projectId: String, rows: [SidebarSnapshotProjectRow]) {
        try? db.write { db in
            try db.execute(
                sql: "DELETE FROM sidebar_snapshot_project WHERE project_id = ?",
                arguments: [projectId]
            )
            for row in rows where row.projectId == projectId {
                try row.insert(db)
            }
        }
    }
}
