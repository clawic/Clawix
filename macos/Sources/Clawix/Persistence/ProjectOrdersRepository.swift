import Foundation
import GRDB

@MainActor
final class ProjectOrdersRepository {
    private let dbProvider: @Sendable () -> DatabaseQueue?
    private static let orderGap: Int64 = 1000

    init(db: DatabaseQueue) {
        self.dbProvider = { db }
    }

    init(dbProvider: @escaping @Sendable () -> DatabaseQueue? = { LazyDatabaseProvider.shared.dbQueue }) {
        self.dbProvider = dbProvider
    }

    func orderedIds() -> [UUID] {
        guard let db = dbProvider() else { return [] }
        let rows = (try? db.read {
            try ProjectSortOrderRow.order(Column("sort_order")).fetchAll($0)
        }) ?? []
        return rows.compactMap { UUID(uuidString: $0.projectId) }
    }

    func setOrder(_ projectIds: [UUID]) {
        Self.persist(projectIds, dbProvider: dbProvider)
        ClawJSAppStateClient.setProjectOrder(projectIds.map(\.uuidString))
    }

    /// Optimistic-UI variant: the caller has already reordered the in-memory
    /// list (the frame the user sees), so the SQLite write and the runtime
    /// patch are pushed off the main actor and never block project drag-drop.
    /// Mirrors the deferred ordering pattern used for pins.
    func setOrderDeferred(_ projectIds: [UUID]) {
        let provider = dbProvider
        let stringIds = projectIds.map(\.uuidString)
        Task.detached(priority: .utility) {
            Self.persist(projectIds, dbProvider: provider)
            await MainActor.run {
                ClawJSAppStateClient.setProjectOrder(stringIds)
            }
        }
    }

    nonisolated private static func persist(
        _ projectIds: [UUID],
        dbProvider: @Sendable () -> DatabaseQueue?
    ) {
        guard let db = dbProvider() else { return }
        try? db.write { db in
            try db.execute(sql: "DELETE FROM project_sort_order")
            for (idx, id) in projectIds.enumerated() {
                let row = ProjectSortOrderRow(projectId: id.uuidString,
                                              sortOrder: Int64(idx + 1) * Self.orderGap)
                try row.insert(db)
            }
        }
    }
}
