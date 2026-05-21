import SwiftUI

struct AssistantMarkdownRenderRequest: Hashable {
    let text: String
    let renderKey: AssistantMarkdownRenderKey?
    let phase: MarkdownParseCachePhase
}

@MainActor
final class AssistantMarkdownRenderModel: ObservableObject {
    typealias Parser = (String, AssistantMarkdownRenderKey?, MarkdownParseCachePhase) async -> MarkdownParseCache.Result

    @Published private(set) var result: MarkdownParseCache.Result?

    private let parser: Parser
    private var latestRequest: AssistantMarkdownRenderRequest?
    private var fulfilledRequest: AssistantMarkdownRenderRequest?
    private var parseTask: Task<Void, Never>?

    init(parser: @escaping Parser = AssistantMarkdownRenderModel.parseInBackground) {
        self.parser = parser
    }

    deinit {
        parseTask?.cancel()
    }

    var blocks: [IndexedAnnotatedBlock] {
        result?.blocks ?? []
    }

    @discardableResult
    func request(_ request: AssistantMarkdownRenderRequest) -> Bool {
        if latestRequest == request {
            return fulfilledRequest == request || parseTask != nil ? false : startRequest(request)
        }

        return startRequest(request)
    }

    private func startRequest(_ request: AssistantMarkdownRenderRequest) -> Bool {
        latestRequest = request
        parseTask?.cancel()

        parseTask = Task { [weak self, parser] in
            let parsed = await parser(request.text, request.renderKey, request.phase)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.latestRequest == request else { return }
                self.result = parsed
                self.fulfilledRequest = request
                self.logRenderTimingIfNeeded(parsed, request: request)
            }
        }
        return true
    }

    func cancel() {
        parseTask?.cancel()
        parseTask = nil
        if fulfilledRequest != latestRequest {
            latestRequest = fulfilledRequest
        }
    }

    func waitForCurrentRenderForTesting() async {
        let task = parseTask
        await task?.value
    }

    private func logRenderTimingIfNeeded(
        _ parsed: MarkdownParseCache.Result,
        request: AssistantMarkdownRenderRequest
    ) {
        guard streamingPerfLogEnabled,
              !parsed.cacheHit,
              request.phase == .streamingIntermediate
        else { return }
        let line = String(
            format: "model parse=%.2fms annotate=%.2fms len=%d blocks=%d reused=%d reparsed=%d",
            parsed.parseMs,
            parsed.annotateMs,
            request.text.count,
            parsed.blocks.count,
            parsed.reusedBlockCount,
            parsed.reparsedCharacterCount
        )
        streamingPerfLog.log("\(line, privacy: .public)")
    }

    private static func parseInBackground(
        text: String,
        renderKey: AssistantMarkdownRenderKey?,
        phase: MarkdownParseCachePhase
    ) async -> MarkdownParseCache.Result {
        await Task.detached(priority: .utility) {
            // hot-path-ok maxBytes: 2097152 reason:=parse-runs-off-body-through-bounded-cache
            MarkdownParseCache.parse(text, renderKey: renderKey, phase: phase)
        }.value
    }
}

enum AssistantMarkdownAnimationSplit {
    static func splitStableAndAnimatedBlocks(
        _ blocks: [IndexedAnnotatedBlock],
        checkpoints: [StreamCheckpoint],
        now: Date
    ) -> (stable: [IndexedAnnotatedBlock], animated: [IndexedAnnotatedBlock]) {
        guard let animatedLowerBound = animatedSourceLowerBound(checkpoints: checkpoints, now: now) else {
            return (blocks, [])
        }
        var stable: [IndexedAnnotatedBlock] = []
        var animated: [IndexedAnnotatedBlock] = []
        for block in blocks {
            if block.sourceRange.upperBound <= animatedLowerBound {
                stable.append(block)
            } else {
                animated.append(block)
            }
        }
        return (stable, animated)
    }

    static func animatedSourceLowerBound(checkpoints: [StreamCheckpoint], now: Date) -> Int? {
        guard !checkpoints.isEmpty else { return nil }
        let activeIndex = checkpoints.firstIndex { checkpoint in
            checkpoint.addedAt.addingTimeInterval(StreamingFade.duration) >= now
        }
        guard let activeIndex else {
            return checkpoints.last?.prefixCount
        }
        if activeIndex == checkpoints.startIndex {
            return 0
        }
        return checkpoints[checkpoints.index(before: activeIndex)].prefixCount
    }
}
