import Foundation

/// Compact descriptor of a collapsed tool group, derived once from the raw work
/// items so a collapsed row can draw "Worked for…" without retaining a full
/// `ToolTimelinePresentation` snapshot. The heavy presentation is materialized
/// lazily by `TimelineDetailProvider` only when the group renders/expands.
///
/// This is the rollout-side / tool-group mirror of the session-layer
/// `TimelineSummary` (`SessionPresentationModels.swift`): both are the cheap
/// "what the collapsed row needs" value; neither carries the full `[WorkItem]`
/// presentation.
struct WorkedForDescriptor: Equatable {
    /// True when the group has at least one tool item to summarize.
    let exists: Bool
    /// Number of tool items in the group.
    let toolCount: Int
    /// Bounded set of changed-file basenames (max 6) for the collapsed label.
    let fileNames: [String]
    /// Elapsed seconds of the group's work, if known.
    let elapsedSeconds: Int

    static let none = WorkedForDescriptor(
        exists: false,
        toolCount: 0,
        fileNames: [],
        elapsedSeconds: 0
    )

    /// Build the compact descriptor from a group's raw items. Lean by design:
    /// counts items and pulls a bounded set of changed-file basenames, nothing
    /// heavy (no presentation snapshot, no aggregate-row phrasing).
    static func make(items: [WorkItem], elapsedSeconds: Int = 0) -> WorkedForDescriptor {
        guard !items.isEmpty else { return .none }
        var fileNames: [String] = []
        var seen: Set<String> = []
        outer: for item in items {
            guard case .fileChange(let paths) = item.kind else { continue }
            for path in paths where !path.isEmpty {
                let name = (path as NSString).lastPathComponent
                guard !name.isEmpty, !seen.contains(name) else { continue }
                seen.insert(name)
                fileNames.append(name)
                if fileNames.count >= 6 { break outer }
            }
        }
        return WorkedForDescriptor(
            exists: true,
            toolCount: items.count,
            fileNames: fileNames,
            elapsedSeconds: elapsedSeconds
        )
    }
}

/// Centralized, bounded materializer for the heavy tool-group presentation.
///
/// Law #5 (cheap first frame, heavy lazy): hydration and the rollout file parse
/// no longer build a `ToolTimelinePresentation` snapshot per tool group. The
/// collapsed row draws from `WorkedForDescriptor`. When a group actually renders
/// or is expanded, `TimelineDetailProvider` builds the full presentation ONCE
/// and caches it keyed by the group's id, so re-mounting the same group (scroll
/// in/out, expand toggling) never rebuilds it.
///
/// A collapsed row can call `prewarm(groupID:items:)` when it appears to build
/// the first 8-item chunk's presentation off the main thread, so the first
/// expand has no main-thread hitch.
@MainActor
final class TimelineDetailProvider {
    static let shared = TimelineDetailProvider()

    /// First-expand chunk size. Matches the row's `timelineEntryPageSize` so the
    /// prewarm cost is bounded to one page of work.
    static let chunkSize = 8

    /// One cached build, tagged with a fingerprint of the items it was built
    /// from. The same group id can render with different item sets across
    /// collapsed/merged states, so a stale fingerprint forces a rebuild.
    private struct Entry {
        let fingerprint: Int
        let snapshot: ToolTimelinePresentationSnapshot
    }

    private var cache: [UUID: Entry] = [:]
    private var order: [UUID] = []
    private let limit = 512

    private init() {}

    /// The full presentation snapshot for a group, built once and cached. Built
    /// on the main actor (the build is cheap for a single group); the off-main
    /// path is `prewarm`, which fills this cache before the first expand.
    func presentation(groupID: UUID, items: [WorkItem]) -> ToolTimelinePresentationSnapshot {
        let fingerprint = Self.fingerprint(for: items)
        if let cached = cache[groupID], cached.fingerprint == fingerprint {
            PerfSignpost.uiChat.event("tool.snapshot.cache_hit", items.count)
            return cached.snapshot
        }
        let snapshot = ToolTimelinePresentation.snapshot(groupID: groupID, items: items)
        store(groupID: groupID, fingerprint: fingerprint, snapshot: snapshot)
        return snapshot
    }

    /// Off-main prewarm of the first chunk's presentation, so the first expand of
    /// a long collapsed group does not pay the build cost on the main thread.
    /// No-op when the group is already cached for the same items.
    func prewarm(groupID: UUID, items: [WorkItem]) {
        guard !items.isEmpty else { return }
        let fingerprint = Self.fingerprint(for: items)
        if let cached = cache[groupID], cached.fingerprint == fingerprint { return }
        let chunk = Array(items.prefix(Self.chunkSize))
        let chunkFingerprint = Self.fingerprint(for: chunk)
        Task.detached(priority: .utility) {
            let snapshot = ToolTimelinePresentation.snapshot(groupID: groupID, items: chunk)
            await MainActor.run {
                // Only seed the prewarm result if a build for these items hasn't
                // already landed; a real render of the full group supersedes it.
                if self.cache[groupID] != nil { return }
                self.store(groupID: groupID, fingerprint: chunkFingerprint, snapshot: snapshot)
            }
        }
    }

    /// Drop a group's cached presentation. The next `presentation` call rebuilds.
    func invalidate(groupID: UUID) {
        if cache.removeValue(forKey: groupID) != nil {
            order.removeAll { $0 == groupID }
        }
    }

    /// Cheap content fingerprint over the items' identity + status + count, so a
    /// changed group (item added, status flipped) misses the cache and rebuilds.
    private static func fingerprint(for items: [WorkItem]) -> Int {
        var hasher = Hasher()
        hasher.combine(items.count)
        for item in items {
            hasher.combine(item.id)
            hasher.combine(item.status)
        }
        return hasher.finalize()
    }

    private func store(
        groupID: UUID,
        fingerprint: Int,
        snapshot: ToolTimelinePresentationSnapshot
    ) {
        if cache[groupID] == nil {
            order.append(groupID)
        }
        cache[groupID] = Entry(fingerprint: fingerprint, snapshot: snapshot)
        guard order.count > limit else { return }
        let overflow = order.count - limit
        for oldID in order.prefix(overflow) {
            cache.removeValue(forKey: oldID)
        }
        order.removeFirst(overflow)
    }
}
