import Foundation
import GRDB

struct ClawJSAppStateOperation: Codable, Sendable {
    var kind: String
    var key: String?
    var value: String?
    var id: String?
    var resourceId: String?
    var name: String?
    var path: String?
    var sortOrder: Int64?
    var ids: [String]?
    var threadId: String?
    var threadIds: [String]?
    var title: String?
    var source: String?
    var chatUuid: String?
    var cwd: String?
    var projectId: String?
    var projectPath: String?
    var updatedAt: String?
    var archived: Bool?
    var pinned: Bool?
    var items: [ClawJSAppStateSidebarSnapshot]?
    var metadata: [String: String]?

    init(
        kind: String,
        key: String? = nil,
        value: String? = nil,
        id: String? = nil,
        resourceId: String? = nil,
        name: String? = nil,
        path: String? = nil,
        sortOrder: Int64? = nil,
        ids: [String]? = nil,
        threadId: String? = nil,
        threadIds: [String]? = nil,
        title: String? = nil,
        source: String? = nil,
        chatUuid: String? = nil,
        cwd: String? = nil,
        projectId: String? = nil,
        projectPath: String? = nil,
        updatedAt: String? = nil,
        archived: Bool? = nil,
        pinned: Bool? = nil,
        items: [ClawJSAppStateSidebarSnapshot]? = nil,
        metadata: [String: String]? = nil
    ) {
        self.kind = kind
        self.key = key
        self.value = value
        self.id = id
        self.resourceId = resourceId
        self.name = name
        self.path = path
        self.sortOrder = sortOrder
        self.ids = ids
        self.threadId = threadId
        self.threadIds = threadIds
        self.title = title
        self.source = source
        self.chatUuid = chatUuid
        self.cwd = cwd
        self.projectId = projectId
        self.projectPath = projectPath
        self.updatedAt = updatedAt
        self.archived = archived
        self.pinned = pinned
        self.items = items
        self.metadata = metadata
    }
}

struct ClawJSAppStateSyncStatus: Equatable, Sendable {
    var pending: Int
    var failed: Int
    var applied: Int
}

struct ClawJSAppStateApplyResponse: Decodable, Sendable {
    let receipt: ClawJSAppStateSyncReceipt
}

struct ClawJSAppStateSyncReceipt: Codable, Sendable {
    let receiptId: String
    let requestId: String
    let hostId: String
    let status: String
    let operationCount: Int
    let appliedAt: String
    let error: ClawJSAppStateReceiptError?
}

struct ClawJSAppStateReceiptError: Codable, Sendable {
    let code: String
    let message: String
}

@MainActor
final class ClawJSAppStateSyncCoordinator {
    static let shared = ClawJSAppStateSyncCoordinator()

    private let dbProvider: @Sendable () -> DatabaseQueue?
    private let sessionsClientProvider: @MainActor () -> ClawJSSessionsClient
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let autoFlush: Bool
    private var flushTask: Task<Void, Never>?

    init(db: DatabaseQueue, autoFlush: Bool = true) {
        self.dbProvider = { db }
        self.sessionsClientProvider = { ClawJSSessionsClient.local() }
        self.autoFlush = autoFlush
    }

    init(dbProvider: @escaping @Sendable () -> DatabaseQueue? = { LazyDatabaseProvider.shared.dbQueue },
         sessionsClientProvider: @escaping @MainActor () -> ClawJSSessionsClient = { ClawJSSessionsClient.local() },
         autoFlush: Bool = true) {
        self.dbProvider = dbProvider
        self.sessionsClientProvider = sessionsClientProvider
        self.autoFlush = autoFlush
    }

    func enqueue(_ operation: ClawJSAppStateOperation) {
        guard let operationData = try? encoder.encode(operation),
              let operationJson = String(data: operationData, encoding: .utf8) else {
            return
        }
        let now = Int64(Date().timeIntervalSince1970)
        let row = AppStateOutboxRow(
            id: UUID().uuidString,
            operationJson: operationJson,
            status: "pending",
            attemptCount: 0,
            lastError: nil,
            receiptJson: nil,
            createdAt: now,
            updatedAt: now,
            nextAttemptAt: now
        )
        if let db = dbProvider() {
            try? db.write { database in
                try row.insert(database)
            }
        }
        scheduleFlush()
    }

    func status() -> ClawJSAppStateSyncStatus {
        guard let db = dbProvider() else { return ClawJSAppStateSyncStatus(pending: 0, failed: 0, applied: 0) }
        return (try? db.read { database in
            let pending = try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM app_state_outbox WHERE status = 'pending'") ?? 0
            let failed = try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM app_state_outbox WHERE status = 'failed'") ?? 0
            let applied = try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM app_state_outbox WHERE status = 'applied'") ?? 0
            return ClawJSAppStateSyncStatus(pending: pending, failed: failed, applied: applied)
        }) ?? ClawJSAppStateSyncStatus(pending: 0, failed: 0, applied: 0)
    }

    func flushPending(limit: Int = 50, allowCLIFallback: Bool = true) async {
        guard let db = dbProvider() else { return }
        let now = Int64(Date().timeIntervalSince1970)
        let rows = (try? await db.read { database in
            try AppStateOutboxRow
                .filter(sql: "status IN ('pending', 'failed') AND next_attempt_at <= ?", arguments: [now])
                .order(Column("created_at"))
                .limit(limit)
                .fetchAll(database)
        }) ?? []
        guard !rows.isEmpty else { return }
        let operations = rows.compactMap { row -> ClawJSAppStateOperation? in
            guard let data = row.operationJson.data(using: .utf8) else { return nil }
            return try? decoder.decode(ClawJSAppStateOperation.self, from: data)
        }
        guard operations.count == rows.count else {
            markFailed(rows, message: "Could not decode appState outbox operation")
            return
        }
        do {
            let response = try await apply(operations: operations, allowCLIFallback: allowCLIFallback)
            try await db.write { database in
                let receiptJson = String(data: try self.encoder.encode(response.receipt), encoding: .utf8) ?? "{}"
                let recordedAt = Int64(Date().timeIntervalSince1970)
                for row in rows {
                    try database.execute(
                        sql: """
                            UPDATE app_state_outbox
                            SET status = 'applied', updated_at = ?, receipt_json = ?, last_error = NULL
                            WHERE id = ?
                        """,
                        arguments: [recordedAt, receiptJson, row.id]
                    )
                }
                try AppStateSyncReceiptRow(
                    receiptId: response.receipt.receiptId,
                    requestId: response.receipt.requestId,
                    hostId: response.receipt.hostId,
                    status: response.receipt.status,
                    operationCount: response.receipt.operationCount,
                    appliedAt: response.receipt.appliedAt,
                    errorJson: response.receipt.error.map { (try? String(data: self.encoder.encode($0), encoding: .utf8)) ?? "{}" },
                    rawJson: receiptJson,
                    recordedAt: recordedAt
                ).upsert(database)
            }
        } catch {
            markFailed(rows, message: error.localizedDescription)
        }
    }

    private func scheduleFlush() {
        guard autoFlush else { return }
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            guard let self else { return }
            await self.flushPending()
            self.flushTask = nil
        }
    }

    private func apply(operations: [ClawJSAppStateOperation], allowCLIFallback: Bool) async throws -> ClawJSAppStateApplyResponse {
        let requestId = "clawix-\(UUID().uuidString)"
        do {
            return try await sessionsClientProvider().applyAppStateOperations(
                operations,
                requestId: requestId,
                hostId: "clawix"
            )
        } catch {
            guard allowCLIFallback, ClawJSRuntime.isAvailable else { throw error }
        }
        let operationsData = try encoder.encode(operations)
        let operationsJson = String(data: operationsData, encoding: .utf8) ?? "[]"
        let data = try await runCLI([
            "host", "app-state", "apply",
            "--operations", operationsJson,
            "--request-id", requestId,
            "--host-id", "clawix",
            "--json",
        ])
        return try decoder.decode(CLIEnvelope<ClawJSAppStateApplyResponse>.self, from: data).data
    }

    func projection(allowCLIFallback: Bool = false) async throws -> ClawJSAppStateSnapshot {
        await flushPending(allowCLIFallback: allowCLIFallback)
        do {
            return try await sessionsClientProvider().appStateProjection()
        } catch {
            guard allowCLIFallback, ClawJSRuntime.isAvailable else { throw error }
            let data = try await runCLI(["host", "app-state", "projection", "--json"])
            return try decoder.decode(CLIEnvelope<ClawJSAppStateSnapshot>.self, from: data).data
        }
    }

    private func runCLI(_ args: [String]) async throws -> Data {
        let nodeURL = ClawJSRuntime.nodeBinaryURL
        let cliScriptPath = ClawJSRuntime.cliScriptURL.path
        let workspaceURL = ClawJSServiceManager.workspaceURL
        let environment = ClawJSServiceManager.cliEnvironment()
        return try await Task.detached(priority: .utility) {
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            process.executableURL = nodeURL
            process.arguments = [cliScriptPath] + args
            process.currentDirectoryURL = workspaceURL
            process.environment = environment
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()
            let outputTask = Task.detached(priority: .utility) {
                stdout.fileHandleForReading.readDataToEndOfFile()
            }
            let errorTask = Task.detached(priority: .utility) {
                stderr.fileHandleForReading.readDataToEndOfFile()
            }
            process.waitUntilExit()
            let output = await outputTask.value
            let errorOutput = await errorTask.value
            if process.terminationStatus != 0 {
                let errorText = String(
                    data: errorOutput,
                    encoding: .utf8
                ) ?? "claw host app-state failed"
                throw NSError(
                    domain: "ClawJSAppStateSyncCoordinator",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: errorText]
                )
            }
            return output
        }.value
    }

    private func markFailed(_ rows: [AppStateOutboxRow], message: String) {
        guard let db = dbProvider() else { return }
        let now = Int64(Date().timeIntervalSince1970)
        try? db.write { database in
            for row in rows {
                let attempts = row.attemptCount + 1
                let delay = min(300, max(5, attempts * attempts * 5))
                try database.execute(
                    sql: """
                        UPDATE app_state_outbox
                        SET status = 'failed', attempt_count = ?, last_error = ?, updated_at = ?, next_attempt_at = ?
                        WHERE id = ?
                    """,
                    arguments: [attempts, message, now, now + Int64(delay), row.id]
                )
            }
        }
    }

    private struct CLIEnvelope<T: Decodable>: Decodable {
        let data: T
    }
}
