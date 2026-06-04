import Foundation

// Draw-only value types for the session presentation layer.
//
// These are the chat-side mirror of `SidebarSnapshot`'s row models: a row
// receives an already-computed `MessageRowDisplayModel` and only draws it.
// ALL derivation (timestamp formatting, content segmentation, timeline
// coalescing, canonical-body normalization, work-summary descriptor) happens
// once in `SessionPresentationStore`, never inside a view body.
//
// Heavy detail (the full `[WorkItem]`, `ToolTimelinePresentation`, off-screen
// markdown parse) is intentionally NOT in `MessageRowDisplayModel`. The
// collapsed worked-for row carries only the compact `TimelineSummary`
// descriptor; the full timeline is materialized lazily on expand (P3's
// `TimelineDetailProvider`).

/// The streaming state of a row, reduced to a single small flag the render
/// layer can switch on without inspecting message internals.
enum MessageRowState: Equatable {
    case streaming
    case done
    case error
}

/// One renderable content block of an assistant message body, already
/// segmented (plan vs. text) in the compute layer so the row never calls
/// `PlanSegmenter.segments` in its body.
enum MessageContentBlock: Equatable, Identifiable {
    case text(id: String, body: String)
    case plan(id: String, body: String, completed: Bool)

    var id: String {
        switch self {
        case .text(let id, _): return id
        case .plan(let id, _, _): return id
        }
    }
}

/// Compact descriptor of a collapsed "Worked for…" group. Derived once from
/// `WorkSummary` so the collapsed row draws without retaining the full
/// `[WorkItem]` array or building a `ToolTimelinePresentation`.
struct TimelineSummary: Equatable {
    let workedForExists: Bool
    let fileNames: [String]
    let toolCount: Int
    let elapsedSeconds: Int

    static let none = TimelineSummary(
        workedForExists: false,
        fileNames: [],
        toolCount: 0,
        elapsedSeconds: 0
    )

    /// Build the compact descriptor from a message's work summary. Lean by
    /// design: counts the tool items and pulls a bounded set of changed-file
    /// basenames, nothing heavy. `asOf` lets the elapsed seconds settle to a
    /// stable value for finished turns (the store passes the turn's end).
    static func make(workSummary: WorkSummary?, asOf now: Date) -> TimelineSummary {
        guard let summary = workSummary else { return .none }
        var fileNames: [String] = []
        var seen: Set<String> = []
        for item in summary.items {
            guard case .fileChange(let paths) = item.kind else { continue }
            for path in paths where !path.isEmpty {
                let name = (path as NSString).lastPathComponent
                guard !name.isEmpty, !seen.contains(name) else { continue }
                seen.insert(name)
                fileNames.append(name)
                if fileNames.count >= 6 { break }
            }
            if fileNames.count >= 6 { break }
        }
        return TimelineSummary(
            workedForExists: true,
            fileNames: fileNames,
            toolCount: summary.items.count,
            elapsedSeconds: summary.elapsedSeconds(asOf: now)
        )
    }
}

/// Everything a single chat row needs to draw, precomputed. `Equatable` so a
/// `LazyVStack`/`ForEach` over these can skip rows whose display value did not
/// change: a delta on one message only re-derives that one model.
///
/// Note: `attachments`/`audioRef`/raw streaming checkpoints stay accessible to
/// the row through the model's source message reference (`message`) for the
/// pieces that still need them (image previews, fade checkpoints) WITHOUT the
/// body deriving anything. The precomputed fields below are the parts the body
/// previously derived inline (timestamp math, segmentation, timeline coalesce,
/// canonical-body normalize) and now must not.
struct MessageRowDisplayModel: Equatable, Identifiable {
    let id: UUID
    let role: ChatMessage.MessageRole
    /// Pre-segmented canonical body blocks. Empty when the row should not
    /// show the canonical body (streaming, or fully duplicated by timeline).
    let contentBlocks: [MessageContentBlock]
    /// Pre-formatted, locale-resolved timestamp string. The row prints it
    /// verbatim; no `Calendar`/`Date` math at render time.
    let formattedTimestamp: String
    /// Pre-formatted reasoning text (currently the raw reasoning string; the
    /// boundary lets the compute layer reshape it without touching the row).
    let formattedReasoning: String
    /// Compact collapsed worked-for descriptor.
    let timeline: TimelineSummary
    let state: MessageRowState

    var isUser: Bool { role == .user }
    var isError: Bool { state == .error }
    var isStreaming: Bool { state == .streaming }

    /// Derive the draw-only model from a message. This is THE single place the
    /// chat-side derivation lives; callers are the presentation store (and its
    /// tests). `showCanonicalBody`/segmentation mirror the previous row body so
    /// the visual result is unchanged, just moved off the render path.
    static func make(from message: ChatMessage, now: Date) -> MessageRowDisplayModel {
        let state: MessageRowState
        if message.isError {
            state = .error
        } else if message.role == .assistant && !message.streamingFinished {
            state = .streaming
        } else {
            state = .done
        }

        let blocks: [MessageContentBlock]
        if message.role == .assistant,
           state != .streaming,
           !message.content.isEmpty,
           Self.shouldShowCanonicalBody(message: message) {
            blocks = Self.segmentBlocks(message.content, idPrefix: message.id.uuidString)
        } else {
            blocks = []
        }

        let timestamp = SessionTimestampFormatter.formatted(message.timestamp, now: now)

        return MessageRowDisplayModel(
            id: message.id,
            role: message.role,
            contentBlocks: blocks,
            formattedTimestamp: timestamp,
            formattedReasoning: message.reasoningText,
            timeline: TimelineSummary.make(
                workSummary: message.workSummary,
                asOf: message.workSummary?.endedAt ?? now
            ),
            state: state
        )
    }

    private static func segmentBlocks(_ content: String, idPrefix: String) -> [MessageContentBlock] {
        PlanSegmenter.segments(from: content).enumerated().map { index, segment in
            switch segment {
            case .text(let body):
                return .text(id: "\(idPrefix):seg:\(index)", body: body)
            case .plan(let body, let completed):
                return .plan(id: "\(idPrefix):seg:\(index)", body: body, completed: completed)
            }
        }
    }

    /// The collapsed-state canonical-body rule, lifted out of the view. Mirrors
    /// `TimelineEntryWindow.shouldShowCanonicalBody` for the collapsed case:
    /// after a turn ends with the timeline collapsed, the bubble shows the
    /// canonical body. (The expanded interleave case stays in the detail layer.)
    private static func shouldShowCanonicalBody(message: ChatMessage) -> Bool {
        let canonical = message.content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !canonical.isEmpty
    }
}

/// One immutable window over the transcript ids the chat is currently
/// mounting, promoted from the previously-dead `TranscriptWindowModel` into a
/// wired, store-owned value type.
struct TranscriptWindow: Equatable {
    let orderedIds: [UUID]
    let model: TranscriptWindowModel

    static let empty = TranscriptWindow(orderedIds: [], model: .init(
        rows: [],
        totalCount: 0,
        visibleRange: 0..<0,
        hiddenBeforeCount: 0,
        hiddenAfterCount: 0,
        anchorId: nil,
        tailId: nil,
        overscanBefore: 0,
        overscanAfter: 0
    ))
}

/// Locale-resolved, cached timestamp formatting for the session row. Holds the
/// same formatter pool as the view used to, but the math runs in the compute
/// layer, not in `var body`.
enum SessionTimestampFormatter {
    static func formatted(_ timestamp: Date, now: Date) -> String {
        let cal = Calendar.current
        let fmts = TimestampFormatters.resolved()
        if cal.isDate(timestamp, inSameDayAs: now) {
            return fmts.time.string(from: timestamp)
        }
        let startOfMsg = cal.startOfDay(for: timestamp)
        let startOfToday = cal.startOfDay(for: now)
        let dayDiff = cal.dateComponents([.day], from: startOfMsg, to: startOfToday).day ?? 0
        if dayDiff >= 1 && dayDiff <= 6 {
            return "\(fmts.weekday.string(from: timestamp)), \(fmts.time.string(from: timestamp))"
        }
        let sameYear = cal.component(.year, from: timestamp) == cal.component(.year, from: now)
        let formatter = sameYear ? fmts.dateSameYear : fmts.dateOtherYear
        return formatter.string(from: timestamp)
    }
}
