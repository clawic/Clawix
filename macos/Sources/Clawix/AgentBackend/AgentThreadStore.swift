import Foundation
import ClawixCore

struct AgentThreadSummary: Codable, Identifiable, Hashable {
    let id: String
    let cwd: String?
    let name: String?
    let preview: String
    let path: String?
    let createdAt: Int64
    let updatedAt: Int64
    var archived: Bool

    enum CodingKeys: String, CodingKey {
        case id, cwd, name, preview, path, createdAt, updatedAt, archived
    }

    fileprivate enum DecodeKeys: String, CodingKey {
        case id, cwd, name, title, threadName = "thread_name", preview, path, createdAt, updatedAt, archived
    }

    init(
        id: String,
        cwd: String?,
        name: String?,
        preview: String,
        path: String?,
        createdAt: Int64,
        updatedAt: Int64,
        archived: Bool = false
    ) {
        self.id = id
        self.cwd = cwd
        self.name = name
        self.preview = preview
        self.path = path
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archived = archived
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DecodeKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        self.name = try c.decodeFirstNonEmptyString(forKeys: [.name, .title, .threadName])
        self.preview = try c.decodeIfPresent(String.self, forKey: .preview) ?? ""
        self.path = try c.decodeIfPresent(String.self, forKey: .path)
        self.createdAt = Self.decodeInt64IfPresent(c, forKey: .createdAt) ?? 0
        self.updatedAt = Self.decodeInt64IfPresent(c, forKey: .updatedAt) ?? self.createdAt
        self.archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
    }

    private static func decodeInt64IfPresent(
        _ c: KeyedDecodingContainer<DecodeKeys>,
        forKey key: DecodeKeys
    ) -> Int64? {
        if let value = try? c.decodeIfPresent(Int64.self, forKey: key) {
            return value
        }
        if let value = try? c.decodeIfPresent(Double.self, forKey: key) {
            return Int64(value)
        }
        if let value = try? c.decodeIfPresent(String.self, forKey: key) {
            if let int = Int64(value) { return int }
            if let double = Double(value) { return Int64(double) }
        }
        return nil
    }

    var createdDate: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt))
    }

    var updatedDate: Date {
        Date(timeIntervalSince1970: TimeInterval(updatedAt))
    }
}

private extension KeyedDecodingContainer where Key == AgentThreadSummary.DecodeKeys {
    func decodeFirstNonEmptyString(forKeys keys: [Key]) throws -> String? {
        for key in keys {
            guard let value = try decodeIfPresent(String.self, forKey: key)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !value.isEmpty else {
                continue
            }
            return value
        }
        return nil
    }
}

enum AgentThreadStore {
    private struct CodexSessionIndexRecord: Decodable {
        let id: String
        let threadName: String?
        let updatedAt: String?
        let createdAt: String?
        let cwd: String?

        enum CodingKeys: String, CodingKey {
            case id
            case threadName = "thread_name"
            case updatedAt = "updated_at"
            case createdAt = "created_at"
            case cwd
        }
    }

    private struct CodexTimestampParser {
        private let fractional: ISO8601DateFormatter
        private let standard: ISO8601DateFormatter

        init() {
            fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
        }

        func parse(_ value: String?) -> Int64? {
            guard let value, !value.isEmpty else { return nil }
            if let date = fractional.date(from: value) {
                return Int64(date.timeIntervalSince1970)
            }
            return standard.date(from: value).map { Int64($0.timeIntervalSince1970) }
        }
    }

    static func fixtureThreads() -> [AgentThreadSummary]? {
        guard
            let raw = ClawixEnv.value(ClawixEnv.threadFixture),
            !raw.isEmpty
        else { return nil }
        let url = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([AgentThreadSummary].self, from: data)) ?? []
    }

    static func fixturePinnedThreadIds() -> [String] {
        guard
            let raw = ClawixEnv.value(ClawixEnv.threadPinFixture),
            !raw.isEmpty
        else { return [] }
        let url = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
        guard let data = try? Data(contentsOf: url),
              let ids = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        var seen: Set<String> = []
        return ids.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func codexSessionIndexThreads(
        indexURL: URL = ClawixAgentBackendRoutes.codexDirectory()
            .appendingPathComponent("session_index.jsonl", isDirectory: false),
        limit: Int,
        includeThreadIds: [String] = []
    ) -> [AgentThreadSummary] {
        guard limit > 0,
              let raw = try? String(contentsOf: indexURL, encoding: .utf8)
        else { return [] }

        let decoder = JSONDecoder()
        let timestampParser = CodexTimestampParser()
        let records = raw.split(whereSeparator: \.isNewline).compactMap { line -> AgentThreadSummary? in
            guard let data = String(line).data(using: .utf8),
                  let record = try? decoder.decode(CodexSessionIndexRecord.self, from: data),
                  !record.id.isEmpty
            else { return nil }
            let updatedAt = timestampParser.parse(record.updatedAt)
                ?? timestampParser.parse(record.createdAt)
                ?? 0
            return AgentThreadSummary(
                id: record.id,
                cwd: record.cwd,
                name: record.threadName,
                preview: "",
                path: nil,
                createdAt: updatedAt,
                updatedAt: updatedAt,
                archived: false
            )
        }

        var latestById: [String: AgentThreadSummary] = [:]
        for record in records {
            guard let existing = latestById[record.id] else {
                latestById[record.id] = record
                continue
            }
            if record.updatedAt >= existing.updatedAt {
                latestById[record.id] = record
            }
        }

        var selected = Array(latestById.values.sorted { $0.updatedAt > $1.updatedAt }.prefix(limit))
        var selectedIds = Set(selected.map(\.id))
        for threadId in includeThreadIds where !selectedIds.contains(threadId) {
            guard let thread = latestById[threadId] else { continue }
            selected.append(thread)
            selectedIds.insert(threadId)
        }
        return selected
    }

    static func codexSessionIndexThreadsAsync(
        indexURL: URL = ClawixAgentBackendRoutes.codexDirectory()
            .appendingPathComponent("session_index.jsonl", isDirectory: false),
        limit: Int,
        includeThreadIds: [String] = []
    ) async -> [AgentThreadSummary] {
        await Task.detached(priority: .utility) {
            codexSessionIndexThreads(
                indexURL: indexURL,
                limit: limit,
                includeThreadIds: includeThreadIds
            )
        }.value
    }

    static func codexPinnedThreadIds(
        globalStateURL: URL = ClawixAgentBackendRoutes.codexDirectory()
            .appendingPathComponent(".codex-global-state.json", isDirectory: false)
    ) -> [String] {
        guard let data = try? Data(contentsOf: globalStateURL),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let ids = dictionary["pinned-thread-ids"] as? [String]
        else { return [] }
        var seen: Set<String> = []
        return ids.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

}
