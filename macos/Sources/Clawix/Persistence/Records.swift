import Foundation
import GRDB

struct ProjectRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "projects"
    var id: String
    var resourceId: String?
    var name: String
    var path: String
    var createdAt: Int64

    enum CodingKeys: String, CodingKey {
        case id, name, path
        case resourceId = "resource_id"
        case createdAt = "created_at"
    }
}

struct ProjectSortOrderRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "project_sort_order"
    var projectId: String
    var sortOrder: Int64

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case sortOrder = "sort_order"
    }
}

struct PinnedThreadRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "pinned_threads"
    var threadId: String
    var sortOrder: Int64
    var pinnedAt: Int64

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case sortOrder = "sort_order"
        case pinnedAt = "pinned_at"
    }
}

struct ChatProjectOverrideRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "chat_project_overrides"
    var threadId: String
    var projectPath: String

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case projectPath = "project_path"
    }
}

struct ProjectlessThreadRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "projectless_threads"
    var threadId: String

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
    }
}

struct SessionTitleRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "session_titles"
    var threadId: String
    var title: String
    var updatedAt: Int64
    var source: String

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case title
        case updatedAt = "updated_at"
        case source
    }
}

struct MetaRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "meta"
    var key: String
    var value: String
}

struct LocalArchiveRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "local_archives"
    var threadId: String
    var archivedAt: Int64

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case archivedAt = "archived_at"
    }
}

struct HiddenRootRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "hidden_codex_roots"
    var path: String
    var hiddenAt: Int64

    enum CodingKeys: String, CodingKey {
        case path
        case hiddenAt = "hidden_at"
    }
}

struct SidebarSnapshotRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "sidebar_snapshot"
    var threadId: String
    var chatUuid: String
    var title: String
    var cwd: String?
    var projectId: String?
    var projectPath: String?
    var updatedAt: Int64
    var archived: Int64
    var pinned: Int64
    var capturedAt: Int64

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case chatUuid = "chat_uuid"
        case title
        case cwd
        case projectId = "project_id"
        case projectPath = "project_path"
        case updatedAt = "updated_at"
        case archived
        case pinned
        case capturedAt = "captured_at"
    }
}

// Per-project mirror of `SidebarSnapshotRow`. `projectId` is the stable
// identity; `projectPath` remains as a mutable locator/fallback. Rows live
// in `sidebar_snapshot_project` only when a chat's project is resolved.
// Feeds the per-project accordion's
// first paint so opening any folder is instant.
struct SidebarSnapshotProjectRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "sidebar_snapshot_project"
    var threadId: String
    var chatUuid: String
    var title: String
    var cwd: String?
    var projectId: String
    var projectPath: String
    var updatedAt: Int64
    var archived: Int64
    var pinned: Int64
    var capturedAt: Int64

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case chatUuid = "chat_uuid"
        case title
        case cwd
        case projectId = "project_id"
        case projectPath = "project_path"
        case updatedAt = "updated_at"
        case archived
        case pinned
        case capturedAt = "captured_at"
    }
}

struct AppStateOutboxRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "app_state_outbox"

    var id: String
    var operationJson: String
    var status: String
    var attemptCount: Int
    var lastError: String?
    var receiptJson: String?
    var createdAt: Int64
    var updatedAt: Int64
    var nextAttemptAt: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case operationJson = "operation_json"
        case status
        case attemptCount = "attempt_count"
        case lastError = "last_error"
        case receiptJson = "receipt_json"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case nextAttemptAt = "next_attempt_at"
    }
}

struct AppStateSyncReceiptRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "app_state_sync_receipts"

    var receiptId: String
    var requestId: String
    var hostId: String
    var status: String
    var operationCount: Int
    var appliedAt: String
    var errorJson: String?
    var rawJson: String
    var recordedAt: Int64

    enum CodingKeys: String, CodingKey {
        case receiptId = "receipt_id"
        case requestId = "request_id"
        case hostId = "host_id"
        case status
        case operationCount = "operation_count"
        case appliedAt = "applied_at"
        case errorJson = "error_json"
        case rawJson = "raw_json"
        case recordedAt = "recorded_at"
    }
}
