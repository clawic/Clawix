import CoreGraphics
import Foundation

struct TranscriptWindowModel: Equatable {
    struct Row: Equatable, Identifiable {
        enum Role: Equatable {
            case user
            case assistant
        }

        let id: UUID
        let role: Role
        let estimatedHeight: CGFloat
        let isStreaming: Bool
        let hasWorkSummary: Bool
    }

    let rows: [Row]
    let totalCount: Int
    let visibleRange: Range<Int>
    let hiddenBeforeCount: Int
    let hiddenAfterCount: Int
    let anchorId: UUID?
    let tailId: UUID?
    let overscanBefore: Int
    let overscanAfter: Int

    var mountedRowCount: Int { rows.count }
    var windowComplete: Bool {
        guard totalCount == 0 else {
            return !rows.isEmpty
                && visibleRange.lowerBound >= 0
                && visibleRange.upperBound <= totalCount
                && rows.count == visibleRange.count
        }
        return rows.isEmpty && visibleRange.isEmpty
    }

    var isTailWindow: Bool {
        hiddenAfterCount == 0 && rows.last?.id == tailId
    }

    static func latestWindow(
        messages: [ChatMessage],
        visibleLimit: Int,
        overscanBefore: Int,
        overscanAfter: Int = 0,
        estimatedRowHeight: CGFloat
    ) -> TranscriptWindowModel {
        window(
            messages: messages,
            endOffset: 0,
            visibleLimit: visibleLimit,
            overscanBefore: overscanBefore,
            overscanAfter: overscanAfter,
            anchorId: messages.last?.id,
            estimatedRowHeight: estimatedRowHeight
        )
    }

    static func window(
        messages: [ChatMessage],
        endOffset: Int,
        visibleLimit: Int,
        overscanBefore: Int,
        overscanAfter: Int,
        anchorId: UUID?,
        estimatedRowHeight: CGFloat
    ) -> TranscriptWindowModel {
        let total = messages.count
        guard total > 0 else {
            return TranscriptWindowModel(
                rows: [],
                totalCount: 0,
                visibleRange: 0..<0,
                hiddenBeforeCount: 0,
                hiddenAfterCount: 0,
                anchorId: nil,
                tailId: nil,
                overscanBefore: max(0, overscanBefore),
                overscanAfter: max(0, overscanAfter)
            )
        }

        let clampedEndOffset = min(max(0, endOffset), total)
        let requestedVisible = max(1, visibleLimit)
        let endIndex = max(0, total - clampedEndOffset)
        let visibleStart = max(0, endIndex - requestedVisible)
        let start = max(0, visibleStart - max(0, overscanBefore))
        let end = min(total, endIndex + max(0, overscanAfter))
        let range = start..<end
        let rows = messages[range].map { message in
            Row(
                id: message.id,
                role: message.role == .user ? .user : .assistant,
                estimatedHeight: estimatedHeight(for: message, fallback: estimatedRowHeight),
                isStreaming: message.role == .assistant && !message.streamingFinished,
                hasWorkSummary: message.workSummary != nil
            )
        }

        return TranscriptWindowModel(
            rows: rows,
            totalCount: total,
            visibleRange: range,
            hiddenBeforeCount: start,
            hiddenAfterCount: total - end,
            anchorId: anchorId,
            tailId: messages.last?.id,
            overscanBefore: max(0, overscanBefore),
            overscanAfter: max(0, overscanAfter)
        )
    }

    private static func estimatedHeight(for message: ChatMessage, fallback: CGFloat) -> CGFloat {
        let base = max(96, fallback)
        let contentLines = CGFloat(max(1, message.content.count / 88))
        let timelineRows = CGFloat(min(message.timeline.count, 8))
        let summary = message.workSummary == nil ? CGFloat(0) : CGFloat(32)
        return max(base, 56 + contentLines * 18 + timelineRows * 28 + summary)
    }
}

struct TranscriptAnchorSnapshot: Equatable {
    let messageId: UUID
    let minYInScrollView: CGFloat
    let scrollY: CGFloat
    let documentHeight: CGFloat
    let visibleHeight: CGFloat
}

struct TranscriptAnchorCorrection: Equatable {
    let messageId: UUID
    let deltaY: CGFloat
    let targetScrollY: CGFloat
    let correctedDeltaY: CGFloat
    let isWithinTolerance: Bool
}

enum NativeTranscriptAnchorCoordinator {
    static let defaultTolerancePx: CGFloat = 2

    static func correction(
        before: TranscriptAnchorSnapshot,
        afterMinYInScrollView: CGFloat,
        afterDocumentHeight: CGFloat,
        tolerancePx: CGFloat = defaultTolerancePx
    ) -> TranscriptAnchorCorrection {
        let delta = afterMinYInScrollView - before.minYInScrollView
        let maxY = max(0, afterDocumentHeight - before.visibleHeight)
        let targetY = min(max(before.scrollY + delta, 0), maxY)
        let appliedDelta = targetY - before.scrollY
        let correctedDelta = delta - appliedDelta
        return TranscriptAnchorCorrection(
            messageId: before.messageId,
            deltaY: delta,
            targetScrollY: targetY,
            correctedDeltaY: correctedDelta,
            isWithinTolerance: abs(correctedDelta) <= tolerancePx
        )
    }
}
