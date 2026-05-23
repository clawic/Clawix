import Foundation

/// Rebuildable cache for backend metadata that is useful at launch but
/// should not block first paint. It intentionally stores only non-secret
/// model names and rate-limit snapshots.
struct BackendMetadataCache {
    struct Snapshot: Codable, Equatable {
        var schemaVersion: Int
        var updatedAt: Date
        var models: [ClawixService.ModelEntry]
        var rateLimits: RateLimitSnapshot?
        var rateLimitsByLimitId: [String: RateLimitSnapshot]

        init(
            schemaVersion: Int = BackendMetadataCache.schemaVersion,
            updatedAt: Date,
            models: [ClawixService.ModelEntry],
            rateLimits: RateLimitSnapshot?,
            rateLimitsByLimitId: [String: RateLimitSnapshot]
        ) {
            self.schemaVersion = schemaVersion
            self.updatedAt = updatedAt
            self.models = models
            self.rateLimits = rateLimits
            self.rateLimitsByLimitId = rateLimitsByLimitId
        }
    }

    static let schemaVersion = 1

    private let fileURL: URL
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    init(directory: URL? = nil) {
        let root = directory ?? Self.defaultDirectory()
        self.fileURL = root.appendingPathComponent("backend-metadata.json", isDirectory: false)
    }

    func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? decoder.decode(Snapshot.self, from: data),
              snapshot.schemaVersion == Self.schemaVersion else {
            return nil
        }
        return snapshot
    }

    func write(_ snapshot: Snapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Cache writes must never affect startup or chat dispatch.
        }
    }

    func isFresh(_ snapshot: Snapshot, maxAge: TimeInterval, now: Date = Date()) -> Bool {
        now.timeIntervalSince(snapshot.updatedAt) <= maxAge
    }

    private static func defaultDirectory() -> URL {
        ClawixCacheRoutes.backendMetadataDirectory()
    }
}
