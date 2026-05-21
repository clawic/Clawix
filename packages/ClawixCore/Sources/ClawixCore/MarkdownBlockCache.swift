import CryptoKit
import Foundation

public enum MarkdownBlockCacheDefaults {
    public static let countLimit = 64
    public static let totalCostLimit = 16 * 1024 * 1024
    public static let maxEntryCost = 1024 * 1024
    public static let blockCost = 384

    public static func cost(for source: String, blockCount: Int, blockCost: Int = blockCost) -> Int {
        source.utf8.count + blockCount * blockCost
    }
}

/// Process-wide cache for parsed markdown block lists, keyed by a
/// bounded source fingerprint instead of the full source string. Both
/// the iOS `AssistantMarkdownView` and the macOS
/// `AssistantMarkdownText` parse user-visible chunks of markdown at
/// body-evaluation time; both pay the same cost to reparse a settled
/// message every time SwiftUI re-runs an ancestor body. NSCache makes
/// the lookup O(1), the keys are byte-equal source fingerprints (so any
/// streaming delta on a *different* message is a no-op), and eviction
/// kicks in automatically under memory pressure.
///
/// Generic over the parsed block type because the two platforms use
/// different parsers and different block models — iOS emits its own
/// `AssistantBlock`, macOS emits `AnnotatedBlock` carrying streaming
/// fade offsets. The cache itself doesn't care: it stores whatever the
/// caller hands it, keyed by a SHA-256 + byte-count key. The stored box
/// keeps only a bounded prefix/suffix sample for collision control; it
/// does not retain the full source as the cache key.
///
/// Designed to live as a `static let` singleton on each platform's
/// renderer (NOT inside a `@StateObject`/`@State`). Per-view caches die
/// when the view unmounts, which is exactly what we don't want here:
/// closing and reopening a chat throws every parse away and the user
/// pays the reparse cost on every open.
public final class MarkdownBlockCache<Block>: @unchecked Sendable {
    /// `NSCache` only stores `AnyObject` values, so wrap whatever block
    /// list the caller hands us in a thin reference box. The box is
    /// `final` so `NSCache`'s internal accounting stays predictable.
    private final class Box {
        let value: Block
        let fingerprint: SourceFingerprint

        init(_ value: Block, fingerprint: SourceFingerprint) {
            self.value = value
            self.fingerprint = fingerprint
        }
    }

    private struct SourceFingerprint: Equatable {
        let key: String
        let prefix: String
        let suffix: String

        init(source: String) {
            let data = Data(source.utf8)
            let digest = SHA256.hash(data: data)
            let hash = digest.map { String(format: "%02x", $0) }.joined()
            key = "\(hash):\(data.count)"
            prefix = String(source.prefix(64))
            suffix = String(source.suffix(64))
        }
    }

    private let storage: NSCache<NSString, Box> = NSCache<NSString, Box>()
    private let lock = NSLock()
    private var order: [String] = []
    private var costs: [String: Int] = [:]
    private var currentCost = 0
    private let countLimit: Int
    private let totalCostLimit: Int
    private let maxEntryCost: Int
    private let blockCost: Int

    public init(
        countLimit: Int = MarkdownBlockCacheDefaults.countLimit,
        totalCostLimit: Int = MarkdownBlockCacheDefaults.totalCostLimit,
        maxEntryCost: Int = MarkdownBlockCacheDefaults.maxEntryCost,
        blockCost: Int = MarkdownBlockCacheDefaults.blockCost
    ) {
        self.countLimit = countLimit
        self.totalCostLimit = totalCostLimit
        self.maxEntryCost = maxEntryCost
        self.blockCost = blockCost
        storage.countLimit = countLimit
        storage.totalCostLimit = totalCostLimit
    }

    /// Retrieve a cached parse if one exists. `nil` means "miss, parse
    /// and call `set`."
    public func get(for source: String) -> Block? {
        let fingerprint = SourceFingerprint(source: source)
        let key = fingerprint.key as NSString
        guard let box = storage.object(forKey: key), box.fingerprint == fingerprint else {
            lock.lock()
            removeAccounting(for: fingerprint.key)
            lock.unlock()
            return nil
        }
        lock.lock()
        touch(fingerprint.key)
        lock.unlock()
        return box.value
    }

    /// Insert a parse result. Overwrites any previous entry for the
    /// same source. Entries whose estimated cost exceeds `maxEntryCost`
    /// are deliberately not cached.
    public func set(_ value: Block, for source: String, cost: Int? = nil) {
        let fingerprint = SourceFingerprint(source: source)
        let entryCost = cost ?? source.utf8.count
        guard entryCost <= maxEntryCost, entryCost <= totalCostLimit else {
            storage.removeObject(forKey: fingerprint.key as NSString)
            lock.lock()
            removeAccounting(for: fingerprint.key)
            lock.unlock()
            return
        }

        storage.setObject(Box(value, fingerprint: fingerprint), forKey: fingerprint.key as NSString, cost: entryCost)
        lock.lock()
        if let existing = costs[fingerprint.key] {
            currentCost -= existing
        }
        costs[fingerprint.key] = entryCost
        currentCost += entryCost
        touch(fingerprint.key)
        enforceLimits()
        lock.unlock()
    }

    public func estimatedCost(for source: String, blockCount: Int) -> Int {
        MarkdownBlockCacheDefaults.cost(for: source, blockCount: blockCount, blockCost: blockCost)
    }

    /// Convenience: cache-aware parse. The closure runs only on a miss
    /// and the result is memoized for future calls with the same source.
    public func parse(_ source: String, _ produce: (String) -> Block) -> Block {
        parse(source, cost: nil, produce: produce)
    }

    /// Convenience: cache-aware parse with caller-supplied cost after
    /// parsing, for block-aware memory accounting.
    public func parse(
        _ source: String,
        cost: ((String, Block) -> Int)?,
        produce: (String) -> Block
    ) -> Block {
        if let hit = get(for: source) { return hit }
        let value = produce(source)
        set(value, for: source, cost: cost?(source, value))
        return value
    }

    private func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private func enforceLimits() {
        while order.count > countLimit || currentCost > totalCostLimit {
            guard let key = order.first else { break }
            storage.removeObject(forKey: key as NSString)
            removeAccounting(for: key)
        }
    }

    private func removeAccounting(for key: String) {
        if let cost = costs.removeValue(forKey: key) {
            currentCost -= cost
        }
        order.removeAll { $0 == key }
    }
}
