import SwiftUI
import AppKit
import ClawixCore

// [QUICKASK<->CHAT PARITY]
//
// Shared assistant markdown renderer. Used by TWO surfaces that render
// the same `ChatMessage`:
//
//   - main chat: `MessageRow` in Sources/Clawix/ChatView.swift
//   - HUD QuickAsk: `QuickAskMessageBubble` in
//     Sources/Clawix/QuickAsk/QuickAskView.swift
//
// Any change to parsing, atom layout, streaming fade, link rendering,
// code-block chrome or table layout flows to BOTH surfaces. If you need
// surface-specific behaviour, parameterize via the `AssistantMarkdownText`
// init (current params: text, weight, color, checkpoints, streamingFinished).
// Do not fork the renderer.
//
// `AssistantMarkdownText` reads `AppState` through `@EnvironmentObject`
// (link routing into the right-sidebar browser, code-block word-wrap
// toggle). The main chat gets it from the `WindowGroup` environment
// automatically; QuickAsk lives outside that group, so its bubble must
// inject `.environmentObject(appState)` explicitly at the call site.
//
// File previously inlined inside `ChatView.swift`; extracted here so
// QuickAsk can reuse the same parser/cache/layout without duplicating
// the streaming fade contract. The block-level `enum AssistantMarkdown`
// stays in `ChatView.swift` because other code paths there consume it
// directly; `FlowLayout` likewise stays in `ChatView.swift` (other
// callers in the file).

// MARK: - Annotated blocks (renderer-internal mirror of AssistantMarkdown)

/// Atom + the offset of its first character inside the original streamed
/// source. The renderer hands that offset to `StreamingFade` so each
/// character ramps from 0→1 opacity in step with the delta that brought
/// it in.
struct AnnotatedAtom: Equatable {
    let atom: AssistantMarkdown.Atom
    let offset: Int
}

struct AnnotatedLine: Equatable {
    let atoms: [AnnotatedAtom]
}

struct AnnotatedParagraph: Equatable {
    let lines: [AnnotatedLine]
}

enum AnnotatedBlock {
    case paragraph(AnnotatedParagraph)
    case heading(level: Int, line: AnnotatedLine)
    case bulletList(items: [AnnotatedParagraph])
    case numberedList(items: [AnnotatedParagraph])
    case codeBlock(language: String, code: String)
    case table(headers: [AnnotatedLine], rows: [[AnnotatedLine]])
}

func annotateBlocks(_ blocks: [AssistantMarkdown.Block], source: String, baseOffset: Int = 0) -> [AnnotatedBlock] {
    var resolver = AtomOffsetResolver(source: source)
    return blocks.map { annotate($0, with: &resolver, baseOffset: baseOffset) }
}

func annotate(_ block: AssistantMarkdown.Block, with resolver: inout AtomOffsetResolver, baseOffset: Int = 0) -> AnnotatedBlock {
    switch block {
    case .paragraph(let p):
        return .paragraph(annotate(p, with: &resolver, baseOffset: baseOffset))
    case .heading(let level, let line):
        return .heading(level: level, line: annotate(line, with: &resolver, baseOffset: baseOffset))
    case .bulletList(let items):
        return .bulletList(items: items.map { annotate($0, with: &resolver, baseOffset: baseOffset) })
    case .numberedList(let items):
        return .numberedList(items: items.map { annotate($0, with: &resolver, baseOffset: baseOffset) })
    case .codeBlock(let language, let code):
        // The fenced body is rendered as a static block; we still walk the
        // resolver past it so subsequent atoms keep their offsets aligned.
        _ = resolver.locate(code)
        return .codeBlock(language: language, code: code)
    case .table(let headers, let rows):
        let hs = headers.map { annotate($0, with: &resolver, baseOffset: baseOffset) }
        let rs = rows.map { row in row.map { annotate($0, with: &resolver, baseOffset: baseOffset) } }
        return .table(headers: hs, rows: rs)
    }
}

func annotate(_ paragraph: AssistantMarkdown.Paragraph, with resolver: inout AtomOffsetResolver, baseOffset: Int = 0) -> AnnotatedParagraph {
    AnnotatedParagraph(lines: paragraph.lines.map { annotate($0, with: &resolver, baseOffset: baseOffset) })
}

func annotate(_ line: AssistantMarkdown.Line, with resolver: inout AtomOffsetResolver, baseOffset: Int = 0) -> AnnotatedLine {
    var atoms: [AnnotatedAtom] = []
    atoms.reserveCapacity(line.atoms.count)
    for atom in line.atoms {
        let needle: String
        switch atom {
        case .word(let s):              needle = s
        case .bold(let s):              needle = s
        case .italic(let s):            needle = s
        case .code(let s):              needle = s
        case .link(let label, _, _):    needle = label
        }
        let offset = resolver.locate(needle) + baseOffset
        atoms.append(AnnotatedAtom(atom: atom, offset: offset))
    }
    return AnnotatedLine(atoms: atoms)
}

// MARK: - Parse cache

struct AssistantMarkdownRenderKey: Hashable, Sendable {
    enum Scope: Hashable, Sendable {
        case message(UUID)
        case timeline(UUID)
        case custom(String)
    }

    let scope: Scope

    static func message(_ id: UUID) -> AssistantMarkdownRenderKey {
        AssistantMarkdownRenderKey(scope: .message(id))
    }

    static func timeline(_ id: UUID) -> AssistantMarkdownRenderKey {
        AssistantMarkdownRenderKey(scope: .timeline(id))
    }

    static func custom(_ value: String) -> AssistantMarkdownRenderKey {
        AssistantMarkdownRenderKey(scope: .custom(value))
    }

    var idPrefix: String {
        switch scope {
        case .message(let id): return "message:\(id.uuidString)"
        case .timeline(let id): return "timeline:\(id.uuidString)"
        case .custom(let value): return "custom:\(value)"
        }
    }
}

struct AssistantMarkdownDocument {
    let text: String
    let blocks: [IndexedAnnotatedBlock]
    let cacheHit: Bool
    let parseMs: Double
    let annotateMs: Double
    let reusedBlockCount: Int
    let reparsedCharacterCount: Int

    var blockCount: Int { blocks.count }

    func markingCacheHit() -> AssistantMarkdownDocument {
        AssistantMarkdownDocument(
            text: text,
            blocks: blocks,
            cacheHit: true,
            parseMs: 0,
            annotateMs: 0,
            reusedBlockCount: blocks.count,
            reparsedCharacterCount: 0
        )
    }
}

enum MarkdownParseCachePhase: Hashable {
    case streamingIntermediate
    case settled
}

final class AssistantMarkdownIncrementalCache: @unchecked Sendable {
    private struct Entry {
        let document: AssistantMarkdownDocument
        let cost: Int
    }

    private let lock = NSLock()
    private var values: [AssistantMarkdownRenderKey: Entry] = [:]
    private var order: [AssistantMarkdownRenderKey] = []
    private var currentCost = 0
    private let countLimit: Int
    private let totalCostLimit: Int
    private let maxEntryCost: Int
    private let blockCost: Int

    init(
        countLimit: Int,
        totalCostLimit: Int,
        maxEntryCost: Int,
        blockCost: Int = MarkdownBlockCacheDefaults.blockCost
    ) {
        self.countLimit = countLimit
        self.totalCostLimit = totalCostLimit
        self.maxEntryCost = maxEntryCost
        self.blockCost = blockCost
    }

    func document(
        for text: String,
        key: AssistantMarkdownRenderKey,
        phase: MarkdownParseCachePhase = .settled,
        buildFull: (String, String) -> AssistantMarkdownDocument,
        buildTail: (String, String, Int, Int, Int, String, [IndexedAnnotatedBlock]) -> AssistantMarkdownDocument
    ) -> AssistantMarkdownDocument {
        lock.lock()
        let prior = values[key]?.document
        lock.unlock()

        let document: AssistantMarkdownDocument
        if let prior, prior.text == text {
            return prior.markingCacheHit()
        } else if let prior, text.hasPrefix(prior.text), !prior.blocks.isEmpty {
            let stableBlocks = Self.stableBlocks(from: prior)
            let stablePrefixEnd = stableBlocks.last?.sourceRange.upperBound ?? 0
            let startingCodeOrdinal = stableBlocks.reduce(0) { total, item in
                if case .codeBlock = item.block { return max(total, item.codeBlockOrdinal) }
                return total
            }
            let tail = String(text.dropFirst(stablePrefixEnd))
            document = buildTail(
                text,
                tail,
                stablePrefixEnd,
                stableBlocks.count,
                startingCodeOrdinal,
                key.idPrefix,
                stableBlocks
            )
        } else {
            document = buildFull(text, key.idPrefix)
        }

        lock.lock()
        store(document, for: key, phase: phase)
        lock.unlock()
        return document
    }

    static func estimatedCost(for document: AssistantMarkdownDocument, blockCost: Int = MarkdownBlockCacheDefaults.blockCost) -> Int {
        MarkdownBlockCacheDefaults.cost(for: document.text, blockCount: document.blocks.count, blockCost: blockCost)
    }

    private static func stableBlocks(from prior: AssistantMarkdownDocument) -> [IndexedAnnotatedBlock] {
        guard prior.blocks.count > 1 else { return [] }
        return Array(prior.blocks.dropLast())
    }

    private func store(_ document: AssistantMarkdownDocument, for key: AssistantMarkdownRenderKey, phase: MarkdownParseCachePhase) {
        let cost = Self.estimatedCost(for: document, blockCost: blockCost)
        guard cost <= maxEntryCost, cost <= totalCostLimit else {
            remove(key)
            PerfSignpost.renderMarkdown.event(
                phase == .streamingIntermediate ? "parse.incremental.streaming_skipped_cost" : "parse.incremental.skipped_cost",
                cost
            )
            return
        }
        if let existing = values[key] {
            currentCost -= existing.cost
        }
        values[key] = Entry(document: document, cost: cost)
        currentCost += cost
        touch(key)
        enforceLimit()
    }

    private func touch(_ key: AssistantMarkdownRenderKey) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private func enforceLimit() {
        while order.count > countLimit || currentCost > totalCostLimit {
            guard let key = order.first else { break }
            remove(key)
        }
    }

    private func remove(_ key: AssistantMarkdownRenderKey) {
        if let existing = values.removeValue(forKey: key) {
            currentCost -= existing.cost
        }
        order.removeAll { $0 == key }
    }
}

/// Process-wide cache for `parseBlocks` + `annotateBlocks`. Lives as a
/// `static let` over the shared `MarkdownBlockCache` so closing and
/// reopening a chat keeps the parses warm — a per-instance / per-view
/// cache used to die on unmount and force a full reparse of every
/// message on the next chat open. Every delta to ANY message still
/// publishes `AppState.chats`, which invalidates every
/// `AssistantMarkdownText` body in the chat; the bounded source
/// fingerprint means the body short-circuits when `text` is identical
/// to a recent parse, including across mount/unmount cycles.
///
/// For the message that's currently streaming, the incremental cache
/// keeps only bounded per-render-key state. It can reuse stable blocks
/// while text grows, but oversized intermediates are returned without
/// being retained.
enum MarkdownParseCache {
    private static let maxRenderableSourceBytes = 2_097_152
    fileprivate static let cache = MarkdownBlockCache<AssistantMarkdownDocument>(
        countLimit: 512,
        totalCostLimit: 32 * 1024 * 1024,
        maxEntryCost: 2 * 1024 * 1024
    )
    fileprivate static let incrementalCache = AssistantMarkdownIncrementalCache(
        countLimit: 128,
        totalCostLimit: 24 * 1024 * 1024,
        maxEntryCost: 2 * 1024 * 1024
    )

    struct Result {
        let document: AssistantMarkdownDocument
        let cacheHit: Bool
        let parseMs: Double
        let annotateMs: Double
        let reusedBlockCount: Int
        let reparsedCharacterCount: Int

        var blocks: [IndexedAnnotatedBlock] { document.blocks }
    }

    /// Pre-warm hook for callers that want to pay the parse cost off
    /// the main thread (e.g. when hydrating a chat from the on-disk
    /// snapshot before its `ChatView` mounts). Safe to call from any
    /// thread; the underlying NSCache is thread-safe.
    static func prewarm(_ text: String) {
        _ = parse(text)
    }

    static func parse(
        _ text: String,
        renderKey: AssistantMarkdownRenderKey? = nil,
        phase: MarkdownParseCachePhase = .settled
    ) -> Result {
        guard text.utf8.count <= maxRenderableSourceBytes else {
            let document = buildFullDocument(String(text.prefix(8_192)), idPrefix: "bounded")
            return Result(
                document: document,
                cacheHit: false,
                parseMs: 0,
                annotateMs: 0,
                reusedBlockCount: 0,
                reparsedCharacterCount: 0
            )
        }
        if let renderKey {
            let document = incrementalCache.document(
                for: text,
                key: renderKey,
                phase: phase,
                buildFull: { source, idPrefix in
                    buildFullDocument(source, idPrefix: idPrefix)
                },
                buildTail: { fullText, tail, sourceOffset, blockOrdinal, codeOrdinal, idPrefix, stableBlocks in
                    buildTailDocument(
                        fullText,
                        tail,
                        sourceOffset: sourceOffset,
                        startingBlockOrdinal: blockOrdinal,
                        startingCodeBlockOrdinal: codeOrdinal,
                        idPrefix: idPrefix,
                        stableBlocks: stableBlocks
                    )
                }
            )
            if document.cacheHit {
                PerfSignpost.renderMarkdown.event("parse.cache_hit.bytes", text.utf8.count)
            } else if document.reusedBlockCount > 0 {
                PerfSignpost.renderMarkdown.event("parse.incremental.reused_blocks", document.reusedBlockCount)
                PerfSignpost.renderMarkdown.event("parse.incremental.tail_chars", document.reparsedCharacterCount)
            }
            return Result(
                document: document,
                cacheHit: document.cacheHit,
                parseMs: document.parseMs,
                annotateMs: document.annotateMs,
                reusedBlockCount: document.reusedBlockCount,
                reparsedCharacterCount: document.reparsedCharacterCount
            )
        }

        if let cached = cache.get(for: text) {
            PerfSignpost.renderMarkdown.event("parse.cache_hit.bytes", text.utf8.count)
            let hit = cached.markingCacheHit()
            return Result(
                document: hit,
                cacheHit: true,
                parseMs: 0,
                annotateMs: 0,
                reusedBlockCount: hit.reusedBlockCount,
                reparsedCharacterCount: 0
            )
        }
        PerfSignpost.renderMarkdown.event("parse.cache_miss.bytes", text.utf8.count)
        let document = buildFullDocument(text, idPrefix: "full")
        cache.set(document, for: text, cost: documentCacheCost(document))
        return Result(
            document: document,
            cacheHit: false,
            parseMs: document.parseMs,
            annotateMs: document.annotateMs,
            reusedBlockCount: 0,
            reparsedCharacterCount: text.count
        )
    }

    private static func documentCacheCost(_ document: AssistantMarkdownDocument) -> Int {
        MarkdownBlockCacheDefaults.cost(for: document.text, blockCount: document.blocks.count)
    }

    private static func buildFullDocument(_ text: String, idPrefix: String) -> AssistantMarkdownDocument {
        buildDocument(
            text: text,
            sourceOffset: 0,
            startingBlockOrdinal: 0,
            startingCodeBlockOrdinal: 0,
            idPrefix: idPrefix,
            stableBlocks: []
        )
    }

    private static func buildTailDocument(
        _ fullText: String,
        _ text: String,
        sourceOffset: Int,
        startingBlockOrdinal: Int,
        startingCodeBlockOrdinal: Int,
        idPrefix: String,
        stableBlocks: [IndexedAnnotatedBlock]
    ) -> AssistantMarkdownDocument {
        buildDocument(
            fullText: fullText,
            text: text,
            sourceOffset: sourceOffset,
            startingBlockOrdinal: startingBlockOrdinal,
            startingCodeBlockOrdinal: startingCodeBlockOrdinal,
            idPrefix: idPrefix,
            stableBlocks: stableBlocks
        )
    }

    private static func buildDocument(
        fullText: String? = nil,
        text: String,
        sourceOffset: Int,
        startingBlockOrdinal: Int,
        startingCodeBlockOrdinal: Int,
        idPrefix: String,
        stableBlocks: [IndexedAnnotatedBlock]
    ) -> AssistantMarkdownDocument {
        PerfSignpost.renderMarkdown.event("parse.cache_miss.bytes", text.utf8.count)
        return PerfSignpost.renderMarkdown.interval("parse") {
            let parseT0 = streamingPerfLogEnabled ? CFAbsoluteTimeGetCurrent() : 0
            // hot-path-ok maxBytes=2097152 reason=macOS assistant markdown parser rejects oversized sources before parse
            let slices = AssistantMarkdown.parseBlockSlices(text)
            let parseT1 = streamingPerfLogEnabled ? CFAbsoluteTimeGetCurrent() : 0
            let annotated = annotateBlocks(
                slices.map(\.block),
                source: text,
                baseOffset: sourceOffset
            )
            let parseT2 = streamingPerfLogEnabled ? CFAbsoluteTimeGetCurrent() : 0
            var codeBlockCount = startingCodeBlockOrdinal
            var indexed: [IndexedAnnotatedBlock] = []
            indexed.reserveCapacity(stableBlocks.count + annotated.count)
            indexed.append(contentsOf: stableBlocks)
            for (idx, pair) in zip(slices, annotated).enumerated() {
                let slice = pair.0
                let block = pair.1
                if case .codeBlock = block {
                    codeBlockCount += 1
                }
                let sourceRange = (slice.sourceRange.lowerBound + sourceOffset)..<(slice.sourceRange.upperBound + sourceOffset)
                let blockOrdinal = startingBlockOrdinal + idx
                indexed.append(IndexedAnnotatedBlock(
                    id: "\(idPrefix):\(sourceRange.lowerBound):\(blockOrdinal)",
                    block: block,
                    sourceRange: sourceRange,
                    codeBlockOrdinal: codeBlockCount
                ))
            }
            PerfSignpost.renderMarkdown.event("parse.blocks", indexed.count)
            return AssistantMarkdownDocument(
                text: fullText ?? text,
                blocks: indexed,
                cacheHit: false,
                parseMs: (parseT1 - parseT0) * 1000,
                annotateMs: (parseT2 - parseT1) * 1000,
                reusedBlockCount: stableBlocks.count,
                reparsedCharacterCount: text.count
            )
        }
    }
}

// MARK: - AssistantMarkdownText

/// Renders assistant prose with the markdown subset Clawix emits:
/// paragraphs, ATX headings, bullet/numbered lists, GitHub-style tables,
/// fenced code blocks, plus inline `**bold**`, `*italic*`, `` `code` ``,
/// and `[label](url)` links. Each link is its own hoverable atom inside
/// a flow layout so tap routes to the sidebar browser and a dotted hover
/// underline tells the user it is interactive.
///
/// While the body is still streaming (or just finished and the trailing
/// fade hasn't completed yet) the renderer wraps only the active tail in
/// `TimelineView` and applies a per-character opacity ramp from
/// `StreamingFade`, so newly arrived characters glide in while older
/// blocks stay settled outside the ticking subtree.
struct AssistantMarkdownText: View {
    let text: String
    var renderKey: AssistantMarkdownRenderKey? = nil
    let weight: Font.Weight
    let color: Color
    var checkpoints: [StreamCheckpoint] = []
    var streamingFinished: Bool = true
    /// Substring to highlight (case-insensitive). Empty disables the
    /// AttributedString path so steady-state rendering pays nothing.
    /// Wired from `AppState.findQuery` while the in-page find bar is
    /// open and stays empty otherwise; `Equatable` on `ParagraphFlow` /
    /// `AtomView` includes it so toggling the bar invalidates the
    /// cached views.
    var findQuery: String = ""
    @EnvironmentObject var appState: AppState
    @StateObject private var renderModel = AssistantMarkdownRenderModel()
    /// Bumped when the trailing fade window closes, so the body
    /// re-evaluates and tears down the `TimelineView` once nothing is
    /// animating any more.
    @State private var animationTick: Int = 0

    init(
        text: String,
        renderKey: AssistantMarkdownRenderKey? = nil,
        weight: Font.Weight,
        color: Color,
        checkpoints: [StreamCheckpoint] = [],
        streamingFinished: Bool = true,
        findQuery: String = ""
    ) {
        self.text = text
        self.renderKey = renderKey
        self.weight = weight
        self.color = color
        self.checkpoints = checkpoints
        self.streamingFinished = streamingFinished
        self.findQuery = findQuery
    }

    var body: some View {
        let now = Date()
        let animating = StreamingFade.isAnimating(
            checkpoints: checkpoints,
            finished: streamingFinished,
            now: now
        )

        let renderCheckpoints = animating ? checkpoints : []
        blocksView(renderModel.blocks, checkpoints: renderCheckpoints, now: now)
        .task(id: renderRequest) {
            renderModel.request(renderRequest)
        }
        .task(id: TickKey(timestamp: checkpoints.last?.addedAt, finished: streamingFinished)) {
            await scheduleSettle()
        }
        .onDisappear {
            renderModel.cancel()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityPlainText))
    }

    private var renderRequest: AssistantMarkdownRenderRequest {
        AssistantMarkdownRenderRequest(
            text: text,
            renderKey: renderKey,
            phase: streamingFinished ? .settled : .streamingIntermediate
        )
    }

    private var accessibilityPlainText: String {
        AccessibilityText.clipped(
            text,
            emptyFallback: String(localized: "Assistant message", bundle: AppLocale.bundle, locale: AppLocale.current)
        )
    }

    private func scheduleSettle() async {
        guard let last = checkpoints.last else { return }
        let remaining = StreamingFade.duration - Date().timeIntervalSince(last.addedAt)
        if remaining > 0 {
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        }
        animationTick &+= 1
    }

    private struct TickKey: Hashable {
        let timestamp: Date?
        let finished: Bool
    }

    @ViewBuilder
    private func blocksView(_ blocks: [IndexedAnnotatedBlock], checkpoints: [StreamCheckpoint], now: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if checkpoints.isEmpty {
                ForEach(blocks) { item in
                    blockView(
                        item.block,
                        checkpoints: checkpoints,
                        now: now,
                        codeBlockOrdinal: item.codeBlockOrdinal
                    )
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                let split = AssistantMarkdownAnimationSplit.splitStableAndAnimatedBlocks(
                    blocks,
                    checkpoints: checkpoints,
                    now: now
                )
                ForEach(split.stable) { item in
                    blockView(
                        item.block,
                        checkpoints: [],
                        now: now,
                        codeBlockOrdinal: item.codeBlockOrdinal
                    )
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !split.animated.isEmpty {
                    TimelineView(.animation) { ctx in
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(split.animated) { item in
                                blockView(
                                    item.block,
                                    checkpoints: checkpoints,
                                    now: ctx.date,
                                    codeBlockOrdinal: item.codeBlockOrdinal
                                )
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func blockView(
        _ block: AnnotatedBlock,
        checkpoints: [StreamCheckpoint],
        now: Date,
        codeBlockOrdinal: Int
    ) -> some View {
        switch block {
        case .paragraph(let p):
            ParagraphFlow(paragraph: p, weight: weight, color: color, checkpoints: checkpoints, now: now, findQuery: findQuery) { url in
                appState.openLinkInBrowser(url)
            }
            .equatable()
            .fixedSize(horizontal: false, vertical: true)

        case .heading(let level, let line):
            ParagraphFlow(
                paragraph: AnnotatedParagraph(lines: [line]),
                weight: .semibold,
                color: color,
                fontSize: headingFontSize(level),
                checkpoints: checkpoints,
                now: now,
                findQuery: findQuery
            ) { url in
                appState.openLinkInBrowser(url)
            }
            .equatable()
            .fixedSize(horizontal: false, vertical: true)

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Circle()
                            .fill(color)
                            .frame(width: 5, height: 5)
                            .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 4 }
                            .frame(width: 10, alignment: .leading)
                        ParagraphFlow(paragraph: item, weight: weight, color: color, checkpoints: checkpoints, now: now, findQuery: findQuery) { url in
                            appState.openLinkInBrowser(url)
                        }
                        .equatable()
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

        case .numberedList(let items):
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: "\(idx + 1).")
                            .font(BodyFont.system(size: 13.5, wght: assistantWght(for: weight)))
                            .foregroundColor(color)
                            .fixedSize()
                        ParagraphFlow(paragraph: item, weight: weight, color: color, checkpoints: checkpoints, now: now, findQuery: findQuery) { url in
                            appState.openLinkInBrowser(url)
                        }
                        .equatable()
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

        case .table(let headers, let rows):
            AssistantTableView(
                headers: headers,
                rows: rows,
                weight: weight,
                color: color,
                checkpoints: checkpoints,
                now: now
            ) { url in
                appState.openLinkInBrowser(url)
            }

        case .codeBlock(let language, let code):
            AssistantCodeBlockView(language: language, code: code, ordinal: codeBlockOrdinal)
        }
    }

    private func headingFontSize(_ level: Int) -> CGFloat {
        switch level {
        case 1:  return 20
        case 2:  return 17
        case 3:  return 15
        default: return 14
        }
    }
}

struct IndexedAnnotatedBlock: Identifiable {
    let id: String
    let block: AnnotatedBlock
    let sourceRange: Range<Int>
    let codeBlockOrdinal: Int
}

// MARK: - Table

/// Table block rendered with the same look as the reference UI: column
/// headers in semibold weight, hairline horizontal divider after every
/// row, leading-aligned cells with generous vertical padding and no
/// vertical separators. Columns size by intrinsic content via `Grid`.
struct AssistantTableView: View {
    let headers: [AnnotatedLine]
    let rows: [[AnnotatedLine]]
    let weight: Font.Weight
    let color: Color
    var checkpoints: [StreamCheckpoint] = []
    var now: Date = .distantPast
    let onLinkTap: (URL) -> Void

    private let divider = Color.white.opacity(0.14)
    private let dividerThickness: CGFloat = 0.75
    private let cellVPad: CGFloat = 7
    private let cellHPad: CGFloat = 32
    static let largeTableRowThreshold = 80

    var body: some View {
        let columnCount = max(headers.count, rows.map { $0.count }.max() ?? 0)
        if rows.count > Self.largeTableRowThreshold {
            lazyTable(columnCount: columnCount)
        } else {
            gridTable(columnCount: columnCount)
        }
    }

    @ViewBuilder
    private func gridTable(columnCount: Int) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(headers.enumerated()), id: \.offset) { idx, cell in
                    cellView(cell, weight: .semibold)
                        .padding(.leading, idx == 0 ? 0 : cellHPad)
                        .gridColumnAlignment(.leading)
                }
            }
            .padding(.vertical, cellVPad)

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Rectangle()
                    .fill(divider)
                    .frame(height: dividerThickness)
                    .gridCellColumns(columnCount)
                GridRow {
                    ForEach(0..<columnCount, id: \.self) { idx in
                        cellView(idx < row.count ? row[idx] : AnnotatedLine(atoms: []), weight: weight)
                            .padding(.leading, idx == 0 ? 0 : cellHPad)
                            .gridColumnAlignment(.leading)
                    }
                }
                .padding(.vertical, cellVPad)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func lazyTable(columnCount: Int) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            tableRow(headers, columnCount: columnCount, weight: .semibold)
            Rectangle()
                .fill(divider)
                .frame(height: dividerThickness)

            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                tableRow(row, columnCount: columnCount, weight: weight)
                    .id("row\(rowIndex)")
                Rectangle()
                    .fill(divider)
                    .frame(height: dividerThickness)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func tableRow(_ row: [AnnotatedLine], columnCount: Int, weight: Font.Weight) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: cellHPad) {
            ForEach(0..<max(columnCount, 1), id: \.self) { idx in
                cellView(idx < row.count ? row[idx] : AnnotatedLine(atoms: []), weight: weight)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, cellVPad)
    }

    @ViewBuilder
    private func cellView(_ line: AnnotatedLine, weight: Font.Weight) -> some View {
        ParagraphFlow(
            paragraph: AnnotatedParagraph(lines: [line]),
            weight: weight,
            color: color,
            checkpoints: checkpoints,
            now: now
        ) { url in
            onLinkTap(url)
        }
        .equatable()
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Code block

/// Fenced code block rendered with a header row showing the language
/// label and a copy affordance, matching the file-preview code block
/// style so multi-line snippets feel consistent across the app.
struct AssistantCodeBlockView: View {
    let language: String
    let code: String
    let ordinal: Int

    @EnvironmentObject var appState: AppState
    @State private var copied = false
    @State private var hoverCopy = false
    @State private var hoverWrap = false

    private var wrapStateProgress: CGFloat {
        appState.chatCodeBlockWordWrap ? 0 : 1
    }
    private var displayProgress: CGFloat {
        hoverWrap ? (1 - wrapStateProgress) : wrapStateProgress
    }
    private var wrapForegroundColor: Color {
        let on = appState.chatCodeBlockWordWrap
        if hoverWrap { return Color(white: on ? 0.94 : 0.85) }
        return Color(white: on ? 0.78 : 0.45)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(verbatim: language.isEmpty ? "code" : language)
                    .font(BodyFont.system(size: 11.5, wght: 500))
                    .foregroundColor(Color(white: 0.55))
                Spacer(minLength: 8)
                Button(action: toggleWrap) {
                    WordWrapToggleIcon(
                        progress: displayProgress,
                        rightBarOpacity: hoverWrap ? 0.35 : 1,
                        color: wrapForegroundColor,
                        lineWidth: 1.1
                    )
                    .frame(width: 13, height: 13)
                    .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .onHover { hoverWrap = $0 }
                .animation(.easeInOut(duration: 0.22), value: hoverWrap)
                .animation(.easeInOut(duration: 0.22), value: appState.chatCodeBlockWordWrap)
                .help(appState.chatCodeBlockWordWrap ? "Disable word wrap" : "Enable word wrap")
                .accessibilityLabel(Text(verbatim: appState.chatCodeBlockWordWrap ? "Disable word wrap" : "Enable word wrap"))
                Button(action: copyCode) {
                    Group {
                        if copied {
                            CheckIcon(size: 11)
                                .foregroundColor(Color(white: hoverCopy ? 0.94 : 0.78))
                        } else {
                            CopyIconViewSquircle(
                                color: Color(white: hoverCopy ? 0.88 : 0.55),
                                lineWidth: 0.85
                            )
                            .frame(width: 14, height: 14)
                        }
                    }
                    .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .onHover { hoverCopy = $0 }
                .accessibilityLabel(Text(verbatim: "Copy code block \(ordinal)"))
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            codeBody
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(white: 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var codeBody: some View {
        if appState.chatCodeBlockWordWrap {
            Text(verbatim: code)
                .font(BodyFont.system(size: 12.5, design: .monospaced))
                .foregroundColor(Palette.textPrimary.opacity(0.94))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .textSelection(.enabled)
        } else {
            ScrollView(.horizontal, showsIndicators: true) {
                Text(verbatim: code)
                    .font(BodyFont.system(size: 12.5, design: .monospaced))
                    .foregroundColor(Palette.textPrimary.opacity(0.94))
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .textSelection(.enabled)
            }
            .thinScrollers()
        }
    }

    private func toggleWrap() {
        appState.chatCodeBlockWordWrap.toggle()
    }

    private func copyCode() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(code, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            copied = false
        }
    }
}

// MARK: - Paragraph flow

/// One paragraph laid out as a vertical stack of "lines" (split on `\n`).
/// Each line is a wrapping flow of word / code / link atoms. Splitting by
/// word lets the link atoms participate in line wrapping while letting us
/// attach per-link `.onHover` and `.onTapGesture` modifiers.
struct ParagraphFlow: View, Equatable {
    let paragraph: AnnotatedParagraph
    let weight: Font.Weight
    let color: Color
    var fontSize: CGFloat = 13.5
    var checkpoints: [StreamCheckpoint] = []
    var now: Date = .distantPast
    var findQuery: String = ""
    let onLinkTap: (URL) -> Void

    /// Skip body re-evaluation when the rendered output cannot have
    /// changed. Two `ParagraphFlow`s render identically when their
    /// content/styling matches AND either there's no fade in flight
    /// (checkpoints empty, or all settled at both `now`s) or `now` is
    /// the same instant. The closure is excluded by design: its
    /// behaviour is constant for the message lifetime, but a fresh
    /// closure value lands on every parent body re-render.
    static func == (lhs: ParagraphFlow, rhs: ParagraphFlow) -> Bool {
        guard lhs.paragraph == rhs.paragraph,
              lhs.weight == rhs.weight,
              lhs.color == rhs.color,
              lhs.fontSize == rhs.fontSize,
              lhs.findQuery == rhs.findQuery,
              lhs.checkpoints == rhs.checkpoints else { return false }
        guard let last = lhs.checkpoints.last else { return true }
        let settledBy = last.addedAt.addingTimeInterval(StreamingFade.duration)
        if settledBy < lhs.now && settledBy < rhs.now { return true }
        return lhs.now == rhs.now
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(paragraph.lines.enumerated()), id: \.offset) { _, line in
                if let plain = stablePlainText(for: line) {
                    Text(verbatim: plain)
                        .font(BodyFont.system(size: fontSize, wght: assistantWght(for: weight)))
                        .foregroundColor(color)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    FlowLayout(horizontalSpacing: 0, verticalSpacing: 6) {
                        ForEach(Array(line.atoms.enumerated()), id: \.offset) { _, annotated in
                            AtomView(
                                atom: annotated.atom,
                                opacity: opacityFor(offset: annotated.offset),
                                weight: weight,
                                color: color,
                                fontSize: fontSize,
                                findQuery: findQuery,
                                onLinkTap: onLinkTap
                            )
                            .equatable()
                        }
                    }
                }
            }
        }
    }

    private func stablePlainText(for line: AnnotatedLine) -> String? {
        guard checkpoints.isEmpty, findQuery.isEmpty else { return nil }
        var text = ""
        text.reserveCapacity(line.atoms.reduce(0) { total, annotated in
            if case .word(let s) = annotated.atom { return total + s.count }
            return total
        })
        for annotated in line.atoms {
            guard case .word(let s) = annotated.atom else { return nil }
            text.append(s)
        }
        return text
    }

    /// Hoists the per-atom opacity calculation out of `AtomView`. With
    /// `.equatable()` the leaf only re-evaluates body when its `opacity`
    /// (or atom content) actually changes, so the hundreds of settled
    /// atoms above the trailing fade window stop re-rendering at every
    /// `TimelineView` tick.
    private func opacityFor(offset: Int) -> Double {
        guard !checkpoints.isEmpty else { return 1.0 }
        return StreamingFade.opacity(
            offset: offset,
            checkpoints: checkpoints,
            now: now
        )
    }
}

// Drops the rendered Manrope weight one named-instance step below what
// `BodyFont.system(size:weight:)` would emit (light/regular → 500,
// medium → 600, semibold+ → 700), so assistant prose reads a touch
// lighter without losing the bold/regular contrast.
func assistantWght(for weight: Font.Weight) -> CGFloat {
    switch weight {
    case .ultraLight, .thin, .light, .regular: return 500
    case .medium: return 600
    case .semibold, .bold, .heavy, .black: return 700
    default: return 500
    }
}

// MARK: - Atom

/// Leaf renderer for a single styled token. Equatable on its visible
/// inputs so SwiftUI can skip body re-evaluation when only the parent
/// re-ran (e.g. the streaming `TimelineView` ticked but this atom is
/// already fully faded in). The `onLinkTap` closure is intentionally
/// excluded from `==`: its identity changes on every parent body
/// re-render, but the behaviour is constant for the message lifetime.
struct AtomView: View, Equatable {
    let atom: AssistantMarkdown.Atom
    let opacity: Double
    let weight: Font.Weight
    let color: Color
    var fontSize: CGFloat = 13.5
    var findQuery: String = ""
    let onLinkTap: (URL) -> Void

    static func == (lhs: AtomView, rhs: AtomView) -> Bool {
        lhs.opacity == rhs.opacity
            && lhs.atom == rhs.atom
            && lhs.weight == rhs.weight
            && lhs.color == rhs.color
            && lhs.fontSize == rhs.fontSize
            && lhs.findQuery == rhs.findQuery
    }

    /// Returns `Text(s)` when no find is active or this atom doesn't
    /// match; otherwise returns `Text(AttributedString)` with a yellow
    /// background painted over each match. Hot path stays free of
    /// AttributedString construction so steady-state rendering keeps
    /// the existing budget.
    private func styledText(_ s: String) -> Text {
        if substringMatches(s, query: findQuery) {
            return Text(highlightedAttributed(s, query: findQuery))
        }
        return Text(verbatim: s)
    }

    var body: some View {
        switch atom {
        case .word(let s):
            styledText(s)
                .font(BodyFont.system(size: fontSize, wght: assistantWght(for: weight)))
                .foregroundColor(color)
                .opacity(opacity)
        case .bold(let s):
            styledText(s)
                .font(BodyFont.system(size: fontSize, wght: assistantWght(for: .semibold)))
                .foregroundColor(color)
                .opacity(opacity)
        case .italic(let s):
            styledText(s)
                .font(BodyFont.system(size: fontSize, wght: assistantWght(for: weight)).italic())
                .foregroundColor(color)
                .opacity(opacity)
        case .code(let s):
            styledText(s)
                .font(BodyFont.system(size: fontSize - 1.5, weight: .regular, design: .monospaced))
                .foregroundColor(Color(white: 0.94))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.09))
                )
                .padding(.horizontal, 2)
                .offset(y: -3)
                .opacity(opacity)
        case .link(let label, let url, let isBareUrl):
            LinkAtom(label: label, url: url, isBareUrl: isBareUrl, weight: weight, onTap: onLinkTap)
                .opacity(opacity)
        }
    }
}

// MARK: - Link

/// Inline link with hover affordance: cursor flips to a pointing hand and
/// a subtle dotted underline appears so the user can tell it is tappable.
/// Tap routes through `onTap` (wired to `AppState.openLinkInBrowser`,
/// which itself dispatches `file://` URLs to the file viewer) so the
/// destination always lands in the right-sidebar panel instead of the
/// system browser. The leading icon picks `FileChipIcon` for `file://`
/// links and `GlobeIcon` for everything else, so a `[abrir markdown]
/// (/abs/path.md)` chip reads as a document and a `[clawix.com]
/// (https://…)` chip reads as a web link.
struct LinkAtom: View {
    let label: String
    let url: URL
    let isBareUrl: Bool
    let weight: Font.Weight
    let onTap: (URL) -> Void

    @State private var hovered = false
    private let linkColor = Color(red: 0.42, green: 0.72, blue: 1.0)

    var body: some View {
        Button(action: { onTap(url) }) {
            HStack(alignment: .center, spacing: 4) {
                Group {
                    if url.isFileURL {
                        FileChipIcon(size: 15)
                    } else {
                        GlobeIcon(size: 15)
                    }
                }
                .foregroundColor(linkColor.opacity(hovered ? 0.78 : 1))
                Text(verbatim: label)
                    .font(BodyFont.system(size: 14, wght: 600))
                    .foregroundColor(linkColor.opacity(hovered ? 0.78 : 1))
                    .underline(hovered, pattern: .dot, color: linkColor.opacity(0.85))
            }
            .padding(.horizontal, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onContinuousHover { phase in
            switch phase {
            case .active:
                hovered = true
                NSCursor.pointingHand.set()
            case .ended:
                hovered = false
            }
        }
        .hoverHint(url.isFileURL ? url.path : url.absoluteString)
        .contextMenu {
            if url.isFileURL {
                Button("Open") { onTap(url) }
                Button("Open with default app") {
                    NSWorkspace.shared.open(url)
                }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                Divider()
                Button("Copy path") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(url.path, forType: .string)
                }
            } else {
                Button("Open in browser") { onTap(url) }
                Button("Open in external browser") {
                    NSWorkspace.shared.open(url)
                }
                Divider()
                Button("Copy link") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(url.absoluteString, forType: .string)
                }
            }
        }
        .accessibilityAddTraits(.isLink)
    }
}
