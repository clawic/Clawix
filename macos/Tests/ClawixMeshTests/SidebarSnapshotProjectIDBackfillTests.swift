import GRDB
import XCTest
@testable import Clawix

final class SidebarSnapshotProjectIDBackfillTests: XCTestCase {
    func testV10MigrationAddsFastPathColumnsIndexesAndPendingBackfill() throws {
        let queue = try DatabaseQueue()
        try Database.migrator.migrate(queue, upTo: "v9_project_resource_ids")

        let projectId = UUID().uuidString
        let projectPath = "/tmp/clawix-backfill-project"
        try queue.write { db in
            try insertProject(id: projectId, path: projectPath, in: db)
            try insertLegacySidebarSnapshot(threadId: "thread-global", projectPath: projectPath, in: db)
            try insertLegacySidebarSnapshotProject(threadId: "thread-project", projectPath: projectPath, in: db)
        }

        try Database.migrator.migrate(queue)

        try queue.read { db in
            XCTAssertNil(try String.fetchOne(db, sql: "SELECT project_id FROM sidebar_snapshot WHERE thread_id = 'thread-global'"))
            XCTAssertNil(try String.fetchOne(db, sql: "SELECT project_id FROM sidebar_snapshot_project WHERE thread_id = 'thread-project'"))
            XCTAssertEqual(
                try MetaRow.fetchOne(db, key: SidebarSnapshotProjectIDBackfill.statusKey)?.value,
                SidebarSnapshotProjectIDBackfill.pendingStatus
            )

            let globalIndex = try String.fetchOne(
                db,
                sql: "SELECT sql FROM sqlite_master WHERE type = 'index' AND name = 'sidebar_snapshot_project_id_idx'"
            )
            let projectIndex = try String.fetchOne(
                db,
                sql: "SELECT sql FROM sqlite_master WHERE type = 'index' AND name = 'sidebar_snapshot_project_project_id_idx'"
            )
            XCTAssertTrue(globalIndex?.contains("WHERE project_id IS NOT NULL AND project_id <> ''") == true)
            XCTAssertTrue(projectIndex?.contains("WHERE project_id IS NOT NULL AND project_id <> ''") == true)
        }
    }

    func testBackfillBatchRespectsLimitPerTable() throws {
        let queue = try migratedQueue()
        let projectId = UUID().uuidString
        let projectPath = "/tmp/clawix-backfill-batch"
        try queue.write { db in
            try insertProject(id: projectId, path: projectPath, in: db)
            for index in 0..<2 {
                try insertCurrentSidebarSnapshot(threadId: "global-\(index)", projectPath: projectPath, in: db)
                try insertCurrentSidebarSnapshotProject(threadId: "project-\(index)", projectPath: projectPath, in: db)
            }
        }

        let backfill = SidebarSnapshotProjectIDBackfill(db: queue, batchSize: 1, pauseNanos: 0)
        let result = try backfill.runBatch()

        XCTAssertEqual(result, SidebarSnapshotProjectIDBackfillBatchResult(sidebarRows: 1, projectRows: 1))
        XCTAssertEqual(try filledCount(in: queue, table: "sidebar_snapshot"), 1)
        XCTAssertEqual(try filledCount(in: queue, table: "sidebar_snapshot_project"), 1)
        XCTAssertEqual(try backfill.currentStatus(), SidebarSnapshotProjectIDBackfill.pendingStatus)
    }

    func testBackfillRunsMultipleBatchesUntilComplete() async throws {
        let queue = try migratedQueue()
        let projectId = UUID().uuidString
        let projectPath = "/tmp/clawix-backfill-complete"
        try await queue.write { db in
            try self.insertProject(id: projectId, path: projectPath, in: db)
            for index in 0..<3 {
                try self.insertCurrentSidebarSnapshot(threadId: "global-\(index)", projectPath: projectPath, in: db)
                try self.insertCurrentSidebarSnapshotProject(threadId: "project-\(index)", projectPath: projectPath, in: db)
            }
        }

        let backfill = SidebarSnapshotProjectIDBackfill(db: queue, batchSize: 1, pauseNanos: 0)
        await backfill.runUntilComplete()

        XCTAssertEqual(try filledCount(in: queue, table: "sidebar_snapshot"), 3)
        XCTAssertEqual(try filledCount(in: queue, table: "sidebar_snapshot_project"), 3)
        XCTAssertEqual(try backfill.currentStatus(), SidebarSnapshotProjectIDBackfill.completeStatus)
    }

    func testBackfillCompletesWhenRowsAreNotMatchable() async throws {
        let queue = try migratedQueue()
        try await queue.write { db in
            try self.insertCurrentSidebarSnapshot(threadId: "global-unmatched", projectPath: "/tmp/missing", in: db)
            try self.insertCurrentSidebarSnapshotProject(threadId: "project-unmatched", projectPath: "/tmp/missing", in: db)
        }

        let backfill = SidebarSnapshotProjectIDBackfill(db: queue, batchSize: 1, pauseNanos: 0)
        await backfill.runUntilComplete()

        XCTAssertEqual(try filledCount(in: queue, table: "sidebar_snapshot"), 0)
        XCTAssertEqual(try filledCount(in: queue, table: "sidebar_snapshot_project"), 0)
        XCTAssertEqual(try backfill.currentStatus(), SidebarSnapshotProjectIDBackfill.completeStatus)
    }

    func testBackfillCanBeCancelledBetweenBatches() async throws {
        let queue = try migratedQueue()
        let projectId = UUID().uuidString
        let projectPath = "/tmp/clawix-backfill-cancel"
        try await queue.write { db in
            try self.insertProject(id: projectId, path: projectPath, in: db)
            for index in 0..<8 {
                try self.insertCurrentSidebarSnapshot(threadId: "global-\(index)", projectPath: projectPath, in: db)
                try self.insertCurrentSidebarSnapshotProject(threadId: "project-\(index)", projectPath: projectPath, in: db)
            }
        }

        let backfill = SidebarSnapshotProjectIDBackfill(db: queue, batchSize: 1, pauseNanos: 1_000_000_000)
        let task = Task { await backfill.runUntilComplete() }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        await task.value

        XCTAssertLessThan(try filledCount(in: queue, table: "sidebar_snapshot"), 8)
        XCTAssertLessThan(try filledCount(in: queue, table: "sidebar_snapshot_project"), 8)
    }

    func testLoadAllProjectIndexedIncludesRowsWithOnlyProjectPath() throws {
        let queue = try migratedQueue()
        let projectPath = "/tmp/clawix-backfill-readable"
        try queue.write { db in
            try insertCurrentSidebarSnapshotProject(threadId: "project-path-only", projectPath: projectPath, in: db)
        }

        let rows = SnapshotRepository(db: queue).loadAllProjectIndexed()

        XCTAssertEqual(rows.map(\.threadId), ["project-path-only"])
        XCTAssertNil(rows[0].projectId)
        XCTAssertEqual(rows[0].projectPath, projectPath)
    }

    func testLoadProjectIndexedPagesRowsByProjectIdInRecencyOrder() throws {
        let queue = try migratedQueue()
        let projectId = UUID().uuidString
        let otherProjectId = UUID().uuidString
        let projectPath = "/tmp/clawix-project-indexed-page"
        try queue.write { db in
            try insertCurrentSidebarSnapshotProject(
                threadId: "project-old",
                projectId: projectId,
                projectPath: projectPath,
                updatedAt: 10,
                in: db
            )
            try insertCurrentSidebarSnapshotProject(
                threadId: "project-fresh",
                projectId: projectId,
                projectPath: projectPath,
                updatedAt: 30,
                in: db
            )
            try insertCurrentSidebarSnapshotProject(
                threadId: "project-middle",
                projectId: projectId,
                projectPath: projectPath,
                updatedAt: 20,
                in: db
            )
            try insertCurrentSidebarSnapshotProject(
                threadId: "other-project",
                projectId: otherProjectId,
                projectPath: "/tmp/other",
                updatedAt: 40,
                in: db
            )
        }

        let rows = SnapshotRepository(db: queue).loadProjectIndexed(
            projectId: projectId,
            projectPath: projectPath,
            limit: 2,
            offset: 1
        )

        XCTAssertEqual(rows.map(\.threadId), ["project-middle", "project-old"])
    }

    func testLoadProjectIndexedFallsBackToLegacyProjectPathRows() throws {
        let queue = try migratedQueue()
        let projectId = UUID().uuidString
        let projectPath = "/tmp/clawix-project-indexed-legacy"
        try queue.write { db in
            try insertCurrentSidebarSnapshotProject(
                threadId: "stable-id-row",
                projectId: projectId,
                projectPath: projectPath,
                updatedAt: 20,
                in: db
            )
            try insertCurrentSidebarSnapshotProject(
                threadId: "legacy-path-row",
                projectPath: projectPath,
                in: db
            )
        }

        let rows = SnapshotRepository(db: queue).loadProjectIndexed(
            projectId: projectId,
            projectPath: projectPath,
            limit: 10
        )

        XCTAssertEqual(rows.map(\.threadId), ["stable-id-row", "legacy-path-row"])
        XCTAssertNil(rows.first { $0.threadId == "legacy-path-row" }?.projectId)
    }

    func testProjectIndexedQueryPlanUsesBothIndexesWithoutTempSort() throws {
        let queue = try migratedQueue()
        let details = try queue.read { db in
            try Row.fetchAll(db, sql: """
                EXPLAIN QUERY PLAN
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
            """, arguments: ["project-id", "/tmp/project", 10, 0])
            .map { row in row["detail"] as String }
        }

        XCTAssertTrue(details.contains { $0.contains("sidebar_snapshot_project_project_id_idx") })
        XCTAssertTrue(details.contains { $0.contains("sidebar_snapshot_project_path_idx") })
        XCTAssertFalse(details.contains { $0.contains("USE TEMP B-TREE") })
    }

    func testSnapshotProjectResolutionFallsBackToProjectPath() {
        let project = Project(id: UUID(), name: "Fallback", path: "/tmp/clawix-project-path-fallback")
        let row = SidebarSnapshotProjectRow(
            threadId: "thread",
            chatUuid: UUID().uuidString,
            title: "Thread",
            cwd: nil,
            projectId: nil,
            projectPath: project.path,
            updatedAt: 1,
            archived: 0,
            pinned: 0,
            capturedAt: 1
        )

        let resolved = AppState.resolveSnapshotProject(
            row,
            projectById: [:],
            projectByPath: [project.path: project]
        )

        XCTAssertEqual(resolved?.id, project.id)
    }

    private func migratedQueue() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try Database.migrator.migrate(queue)
        return queue
    }

    private func insertProject(id: String, path: String, in db: GRDB.Database) throws {
        try db.execute(
            sql: "INSERT INTO projects(id, name, path, created_at) VALUES (?, 'Project', ?, 1)",
            arguments: [id, path]
        )
    }

    private func insertLegacySidebarSnapshot(threadId: String, projectPath: String, in db: GRDB.Database) throws {
        try db.execute(sql: """
            INSERT INTO sidebar_snapshot(
                thread_id, chat_uuid, title, cwd, project_path, updated_at, archived, pinned, captured_at
            ) VALUES (?, ?, 'Thread', NULL, ?, 10, 0, 0, 10)
        """, arguments: [threadId, UUID().uuidString, projectPath])
    }

    private func insertLegacySidebarSnapshotProject(threadId: String, projectPath: String, in db: GRDB.Database) throws {
        try db.execute(sql: """
            INSERT INTO sidebar_snapshot_project(
                thread_id, chat_uuid, title, cwd, project_path, updated_at, archived, pinned, captured_at
            ) VALUES (?, ?, 'Thread', NULL, ?, 10, 0, 0, 10)
        """, arguments: [threadId, UUID().uuidString, projectPath])
    }

    private func insertCurrentSidebarSnapshot(threadId: String, projectPath: String, in db: GRDB.Database) throws {
        try db.execute(sql: """
            INSERT INTO sidebar_snapshot(
                thread_id, chat_uuid, title, cwd, project_id, project_path, updated_at, archived, pinned, captured_at
            ) VALUES (?, ?, 'Thread', NULL, NULL, ?, 10, 0, 0, 10)
        """, arguments: [threadId, UUID().uuidString, projectPath])
    }

    private func insertCurrentSidebarSnapshotProject(threadId: String, projectPath: String, in db: GRDB.Database) throws {
        try db.execute(sql: """
            INSERT INTO sidebar_snapshot_project(
                thread_id, chat_uuid, title, cwd, project_id, project_path, updated_at, archived, pinned, captured_at
            ) VALUES (?, ?, 'Thread', NULL, NULL, ?, 10, 0, 0, 10)
        """, arguments: [threadId, UUID().uuidString, projectPath])
    }

    private func insertCurrentSidebarSnapshotProject(
        threadId: String,
        projectId: String,
        projectPath: String,
        updatedAt: Int64,
        in db: GRDB.Database
    ) throws {
        try db.execute(sql: """
            INSERT INTO sidebar_snapshot_project(
                thread_id, chat_uuid, title, cwd, project_id, project_path, updated_at, archived, pinned, captured_at
            ) VALUES (?, ?, 'Thread', NULL, ?, ?, ?, 0, 0, 10)
        """, arguments: [threadId, UUID().uuidString, projectId, projectPath, updatedAt])
    }

    private func filledCount(in queue: DatabaseQueue, table: String) throws -> Int {
        try queue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM \(table) WHERE project_id IS NOT NULL AND project_id <> ''"
            ) ?? 0
        }
    }
}
