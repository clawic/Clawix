import GRDB
import XCTest
@testable import Clawix

@MainActor
final class AppStateSyncCoordinatorTests: XCTestCase {
    func testEnqueuePersistsDurablePendingOutboxAndReportsStatus() throws {
        let queue = try DatabaseQueue()
        try Database.migrator.migrate(queue)
        let coordinator = ClawJSAppStateSyncCoordinator(db: queue, autoFlush: false)

        coordinator.enqueue(ClawJSAppStateOperation(
            kind: "project.upsert",
            id: "proj-1",
            resourceId: "res_project1",
            name: "Project",
            path: "/tmp/project"
        ))

        let rows = try queue.read { database in
            try AppStateOutboxRow.fetchAll(database)
        }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].status, "pending")
        XCTAssertTrue(rows[0].operationJson.contains("project.upsert"))
        XCTAssertEqual(coordinator.status(), ClawJSAppStateSyncStatus(pending: 1, failed: 0, applied: 0))
    }

    func testRefreshSkipsProjectionWhenOutboxHasFailedRows() throws {
        let queue = try DatabaseQueue()
        try Database.migrator.migrate(queue)
        let now = Int64(Date().timeIntervalSince1970)
        try queue.write { database in
            try AppStateOutboxRow(
                id: "outbox-1",
                operationJson: #"{"kind":"pin.upsert","threadId":"thread-1","sortOrder":1000}"#,
                status: "failed",
                attemptCount: 1,
                lastError: "runtime unavailable",
                receiptJson: nil,
                createdAt: now,
                updatedAt: now,
                nextAttemptAt: now + 60
            ).insert(database)
        }
        let coordinator = ClawJSAppStateSyncCoordinator(db: queue, autoFlush: false)
        XCTAssertEqual(coordinator.status(), ClawJSAppStateSyncStatus(pending: 0, failed: 1, applied: 0))
    }
}
