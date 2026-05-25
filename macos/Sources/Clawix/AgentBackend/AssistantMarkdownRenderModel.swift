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

        if let cached = MarkdownParseCache.cachedResult(
            request.text,
            renderKey: request.renderKey,
            phase: request.phase
        ) {
            parseTask = nil
            result = cached
            fulfilledRequest = request
            markRenderReady(cached, request: request)
            logRenderTimingIfNeeded(cached, request: request)
            return true
        }

        parseTask = Task { [weak self, parser] in
            let parsed = await parser(request.text, request.renderKey, request.phase)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.latestRequest == request else { return }
                self.result = parsed
                self.fulfilledRequest = request
                self.markRenderReady(parsed, request: request)
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

    private func markRenderReady(
        _ parsed: MarkdownParseCache.Result,
        request: AssistantMarkdownRenderRequest
    ) {
        let summary = AssistantMarkdownRenderDocumentSummary(blocks: parsed.blocks)
        RenderProbe.markPassive(
            "AssistantMarkdownRenderReady",
            fields: [
                "annotateMs": String(format: "%.2f", parsed.annotateMs),
                "blocks": "\(parsed.blocks.count)",
                "cacheHit": "\(parsed.cacheHit)",
                "codeBlocks": "\(summary.codeBlocks)",
                "flowAtoms": "\(summary.flowAtoms)",
                "flowLines": "\(summary.flowLines)",
                "headingBlocks": "\(summary.headingBlocks)",
                "listBlocks": "\(summary.listBlocks)",
                "parseMs": String(format: "%.2f", parsed.parseMs),
                "paragraphBlocks": "\(summary.paragraphBlocks)",
                "phase": request.phase.renderProbeName,
                "renderKey": request.renderKey?.renderProbeName ?? "none",
                "reparsedChars": "\(parsed.reparsedCharacterCount)",
                "reusedBlocks": "\(parsed.reusedBlockCount)",
                "tableBlocks": "\(summary.tableBlocks)",
                "textChars": "\(request.text.count)"
            ]
        )
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

private struct AssistantMarkdownRenderDocumentSummary {
    var paragraphBlocks = 0
    var headingBlocks = 0
    var listBlocks = 0
    var codeBlocks = 0
    var tableBlocks = 0
    var flowLines = 0
    var flowAtoms = 0

    init(blocks: [IndexedAnnotatedBlock]) {
        for item in blocks {
            switch item.block {
            case .paragraph(let paragraph):
                paragraphBlocks += 1
                add(paragraph)
            case .heading(_, let line):
                headingBlocks += 1
                add(line)
            case .bulletList(let items), .numberedList(let items):
                listBlocks += 1
                addListItems(items)
            case .codeBlock:
                codeBlocks += 1
            case .table(let headers, let rows):
                tableBlocks += 1
                for line in headers {
                    add(line)
                }
                for row in rows {
                    for line in row {
                        add(line)
                    }
                }
            }
        }
    }

    private mutating func add(_ paragraph: AnnotatedParagraph) {
        for line in paragraph.lines {
            add(line)
        }
    }

    private mutating func add(_ line: AnnotatedLine) {
        flowLines += 1
        flowAtoms += line.atoms.count
    }

    private mutating func addListItems(_ items: [AnnotatedListItem]) {
        for item in items {
            add(item.paragraph)
            for child in item.children {
                switch child {
                case .bullet(let items), .numbered(let items):
                    addListItems(items)
                }
            }
        }
    }
}

private extension MarkdownParseCachePhase {
    var renderProbeName: String {
        switch self {
        case .streamingIntermediate:
            return "streamingIntermediate"
        case .settled:
            return "settled"
        }
    }
}

private extension AssistantMarkdownRenderKey {
    var renderProbeName: String {
        switch scope {
        case .message(let id):
            return "message:\(id.uuidString)"
        case .timeline(let id):
            return "timeline:\(id.uuidString)"
        case .custom(let value):
            return "custom:\(value)"
        }
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
