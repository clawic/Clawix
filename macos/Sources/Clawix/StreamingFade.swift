import SwiftUI
import os

// Streaming fade-in for assistant text. The unit of animation is the
// WORD: every word ramps from opacity 0 to 1 over `duration`. The fade
// starts when the word is appended to the renderable model. It must not
// queue words into the future, because live streaming has to reflect the
// backend stream instead of replaying a delayed visual backlog.

/// Toggle to surface streaming-pipeline timing in the dev log. Flip to
/// `false` once we've root-caused the perceived slowness; the logs are
/// noisy and shouldn't ship enabled.
let streamingPerfLogEnabled = false
let streamingPerfLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Clawix", category: "stream-perf")

enum StreamingFade {
    /// How long a word takes to ramp from invisible to fully opaque.
    static let duration: Double = 0.22

    /// Historical compatibility constant for callers/tests that refer to
    /// the old spacing knob. It is intentionally zero: opacity may smooth
    /// a word that is already in the model, but it cannot create a delayed
    /// word queue.
    static let stagger: Double = 0

    /// Opacity for the character at `offset` in the streamed string.
    /// Characters past the last scheduled word (i.e. a trailing partial
    /// word still waiting for its closing whitespace) read as fully
    /// transparent so they don't pop in mid-word.
    ///
    /// Checkpoints arrive sorted by `prefixCount` (the schedule writes
    /// them in append order with monotonically growing prefixes), so the
    /// "first prefixCount > offset" lookup is a binary search. Critical
    /// because this runs once per atom per animation frame: with 500
    /// atoms at 120Hz a linear scan over 500 checkpoints stalls the
    /// streaming pipeline.
    static func opacity(
        offset: Int,
        checkpoints: [StreamCheckpoint],
        now: Date
    ) -> Double {
        guard !checkpoints.isEmpty else { return 1.0 }
        var lo = 0
        var hi = checkpoints.count
        while lo < hi {
            let mid = (lo &+ hi) >> 1
            if checkpoints[mid].prefixCount > offset {
                hi = mid
            } else {
                lo = mid &+ 1
            }
        }
        guard lo < checkpoints.count else {
            // Past the last scheduled word → still pending, hide it.
            return 0.0
        }
        let stamp = checkpoints[lo].addedAt
        let elapsed = now.timeIntervalSince(stamp)
        if elapsed <= 0 { return 0.0 }
        if elapsed >= duration { return 1.0 }
        let t = elapsed / duration
        return 1.0 - pow(1.0 - t, 2.0)
    }

    /// Whether the renderer still has work to do this frame: either a
    /// scheduled word is mid-ramp, or the stream isn't finished yet so
    /// new deltas / new schedules may still land.
    static func isAnimating(
        checkpoints: [StreamCheckpoint],
        finished: Bool,
        now: Date
    ) -> Bool {
        if !finished { return !checkpoints.isEmpty }
        guard let last = checkpoints.last else { return false }
        return now.timeIntervalSince(last.addedAt) < duration
    }

    /// Seconds until every scheduled checkpoint is fully opaque. Future
    /// scheduled words include both their queued delay and fade duration.
    static func settlementDelay(
        checkpoints: [StreamCheckpoint],
        now: Date = Date()
    ) -> Double {
        guard let last = checkpoints.last else { return 0 }
        return max(0, last.addedAt.addingTimeInterval(duration).timeIntervalSince(now))
    }

    /// A single distant-past sentinel that means "everything through
    /// this prefix is already fully opaque". Keeping one marker avoids
    /// losing the scheduled-text boundary without retaining per-word
    /// history after the fade window.
    static func settledSentinel(prefixCount: Int) -> [StreamCheckpoint] {
        guard prefixCount > 0 else { return [] }
        return [StreamCheckpoint(prefixCount: prefixCount, addedAt: .distantPast)]
    }

    static func settledSentinel(checkpoints: [StreamCheckpoint]) -> [StreamCheckpoint] {
        guard let last = checkpoints.last else { return [] }
        return settledSentinel(prefixCount: last.prefixCount)
    }

    /// Final-state normalisation used after a stream is closed and the
    /// renderer no longer needs the active fade tail.
    static func settled(
        checkpoints: [StreamCheckpoint],
        fallbackPrefixCount: Int = 0
    ) -> [StreamCheckpoint] {
        if let last = checkpoints.last {
            return settledSentinel(prefixCount: last.prefixCount)
        }
        return settledSentinel(prefixCount: fallbackPrefixCount)
    }

    /// Bounds checkpoint history while preserving the active fade tail.
    /// Fully-settled prefixes collapse to one distant-past sentinel so
    /// opacity lookups still know where the scheduled text ends.
    static func compact(
        checkpoints: [StreamCheckpoint],
        now: Date = Date()
    ) -> [StreamCheckpoint] {
        guard !checkpoints.isEmpty else { return [] }
        let firstActive = checkpoints.firstIndex { checkpoint in
            checkpoint.addedAt.addingTimeInterval(duration) >= now
        }
        guard let firstActive else {
            guard let last = checkpoints.last else { return [] }
            return [
                StreamCheckpoint(prefixCount: last.prefixCount, addedAt: .distantPast)
            ]
        }
        guard firstActive > checkpoints.startIndex else {
            return checkpoints
        }
        let settled = checkpoints[checkpoints.index(before: firstActive)]
        return [
            StreamCheckpoint(prefixCount: settled.prefixCount, addedAt: .distantPast)
        ] + Array(checkpoints[firstActive...])
    }

    struct ScheduleResult {
        let newCheckpoints: [StreamCheckpoint]
        let pendingTail: String
    }

    /// Walks `pendingTail + delta` and emits one `StreamCheckpoint` per
    /// complete word (non-whitespace followed by whitespace). A burst
    /// of already-complete words gets the same `now` timestamp so the
    /// renderer never turns a fast stream into a delayed visual replay.
    /// The new pending tail (the trailing partial word, or `""` if
    /// nothing is outstanding) comes back so the caller can hand it to
    /// the next delta. This is O(pendingTail + delta) per call; the
    /// caller avoids the previous O(content) reparse on every token.
    static func ingest(
        delta: String,
        pendingTail: String,
        scheduledLength: Int,
        lastFadeStart _: Date,
        flush: Bool = false,
        now: Date = Date()
    ) -> ScheduleResult {
        PerfSignpost.renderStreaming.event("ingest", delta.count)
        let combined = pendingTail + delta
        var checkpoints: [StreamCheckpoint] = []
        var i = combined.startIndex
        var iCount = 0
        let endIdx = combined.endIndex

        while i < endIdx {
            var j = i
            var jCount = iCount
            // Leading whitespace (rare except at the very start) rides
            // with the next word.
            while j < endIdx, combined[j].isWhitespace {
                j = combined.index(after: j); jCount += 1
            }
            if j == endIdx {
                // Pure whitespace tail.
                if flush {
                    checkpoints.append(StreamCheckpoint(
                        prefixCount: scheduledLength + jCount, addedAt: now
                    ))
                    i = j; iCount = jCount
                }
                break
            }
            // Word body.
            while j < endIdx, !combined[j].isWhitespace {
                j = combined.index(after: j); jCount += 1
            }
            if j == endIdx {
                // No closing whitespace yet → defer the partial word.
                if flush {
                    checkpoints.append(StreamCheckpoint(
                        prefixCount: scheduledLength + jCount, addedAt: now
                    ))
                    i = j; iCount = jCount
                }
                break
            }
            // Trailing whitespace gets folded into the word so it owns
            // its own gap to the next word.
            while j < endIdx, combined[j].isWhitespace {
                j = combined.index(after: j); jCount += 1
            }
            checkpoints.append(StreamCheckpoint(
                prefixCount: scheduledLength + jCount, addedAt: now
            ))
            i = j; iCount = jCount
        }

        let newPendingTail = i < endIdx ? String(combined[i..<endIdx]) : ""
        return ScheduleResult(newCheckpoints: checkpoints, pendingTail: newPendingTail)
    }
}

// MARK: - Atom source-offset mapping

/// Walks the parsed markdown structure in render order and assigns each
/// atom an approximate offset into the original source string. The
/// renderer hands that offset to `StreamingFade` so per-word ramps stay
/// aligned with the deltas the user typed.
///
/// The mapping uses `String.range(of:)` against the source from a moving
/// cursor, so it's tolerant of stripped formatting markers (`**bold**`
/// produces `"bold"` as the atom; we still find it in the source after
/// the `**`). On a miss (truncated source mid-stream, escape edge cases)
/// the resolver falls back to the cursor's current position, which keeps
/// the ramp roughly correct rather than crashing.
struct AtomOffsetResolver {
    private let source: String
    private var cursor: String.Index

    init(source: String) {
        self.source = source
        self.cursor = source.startIndex
    }

    /// Returns the offset (Character count from the start) where
    /// `needle` starts in the source, advancing the cursor past it. If
    /// the needle is empty, returns the cursor's current offset without
    /// moving it.
    mutating func locate(_ needle: String) -> Int {
        if needle.isEmpty {
            return source.distance(from: source.startIndex, to: cursor)
        }
        if let range = source.range(of: needle, range: cursor..<source.endIndex) {
            let offset = source.distance(from: source.startIndex, to: range.lowerBound)
            cursor = range.upperBound
            return offset
        }
        return source.distance(from: source.startIndex, to: cursor)
    }
}
