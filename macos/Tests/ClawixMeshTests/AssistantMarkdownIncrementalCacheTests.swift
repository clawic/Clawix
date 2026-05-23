import XCTest
@testable import Clawix

final class AssistantMarkdownIncrementalCacheTests: XCTestCase {
    @MainActor
    func testRenderModelSkipsIdenticalRequest() async {
        let counter = RenderModelParseCounter()
        let model = AssistantMarkdownRenderModel { text, renderKey, phase in
            await counter.increment()
            return MarkdownParseCache.parse(text, renderKey: renderKey, phase: phase)
        }
        let request = AssistantMarkdownRenderRequest(
            text: "Stable paragraph.",
            renderKey: .custom(UUID().uuidString),
            phase: .settled
        )

        XCTAssertTrue(model.request(request))
        XCTAssertFalse(model.request(request))
        await model.waitForCurrentRenderForTesting()

        let parseCount = await counter.value()
        XCTAssertEqual(parseCount, 1)
        XCTAssertEqual(model.result?.document.text, request.text)
    }

    @MainActor
    func testRenderModelIgnoresStaleResultAfterNewerRequest() async {
        let model = AssistantMarkdownRenderModel { text, renderKey, phase in
            if text == "slow" {
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
            return MarkdownParseCache.parse(text, renderKey: renderKey, phase: phase)
        }
        let key = AssistantMarkdownRenderKey.custom(UUID().uuidString)

        XCTAssertTrue(model.request(AssistantMarkdownRenderRequest(text: "slow", renderKey: key, phase: .settled)))
        XCTAssertTrue(model.request(AssistantMarkdownRenderRequest(text: "fast", renderKey: key, phase: .settled)))
        await model.waitForCurrentRenderForTesting()
        try? await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertEqual(model.result?.document.text, "fast")
    }

    @MainActor
    func testRenderModelRestartsSameRequestAfterCancellationBeforeResult() async {
        let counter = RenderModelParseCounter()
        let model = AssistantMarkdownRenderModel { text, renderKey, phase in
            await counter.increment()
            if text == "pending" {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            return MarkdownParseCache.parse(text, renderKey: renderKey, phase: phase)
        }
        let request = AssistantMarkdownRenderRequest(
            text: "pending",
            renderKey: .custom(UUID().uuidString),
            phase: .settled
        )

        XCTAssertTrue(model.request(request))
        await Task.yield()
        model.cancel()
        XCTAssertTrue(model.request(request))
        await model.waitForCurrentRenderForTesting()

        let parseCount = await counter.value()
        XCTAssertGreaterThanOrEqual(parseCount, 1)
        XCTAssertEqual(model.result?.document.text, "pending")
    }

    func testAnimatedSplitKeepsSettledBlocksOutsideTimelineTail() {
        let now = Date()
        let blocks = [
            testIndexedBlock(id: "stable", range: 0..<12),
            testIndexedBlock(id: "animated", range: 12..<30)
        ]
        let checkpoints = [
            StreamCheckpoint(prefixCount: 12, addedAt: now.addingTimeInterval(-StreamingFade.duration - 1)),
            StreamCheckpoint(prefixCount: 30, addedAt: now.addingTimeInterval(-StreamingFade.duration / 2))
        ]

        let split = AssistantMarkdownAnimationSplit.splitStableAndAnimatedBlocks(
            blocks,
            checkpoints: checkpoints,
            now: now
        )

        XCTAssertEqual(split.stable.map(\.id), ["stable"])
        XCTAssertEqual(split.animated.map(\.id), ["animated"])
    }

    func testSettledRenderKeyReusesGlobalPrewarmCache() {
        let text = """
        # Prewarm \(UUID().uuidString)

        | Shape | Count |
        | --- | ---: |
        | table | 1 |

        ```swift
        let cached = true
        ```
        """

        let warmed = MarkdownParseCache.parse(text)
        XCTAssertFalse(warmed.cacheHit)

        let keyed = MarkdownParseCache.parse(
            text,
            renderKey: .custom("message:\(UUID().uuidString)"),
            phase: .settled
        )

        XCTAssertTrue(keyed.cacheHit)
        XCTAssertEqual(keyed.blocks.map(\.id), warmed.blocks.map(\.id))
    }

    func testAppendOnlyTextReusesStableBlockIds() {
        let key = AssistantMarkdownRenderKey.custom(UUID().uuidString)
        let first = "First paragraph.\n\nSecond paragraph."
        let second = first + "\n\nThird paragraph."

        let initial = MarkdownParseCache.parse(first, renderKey: key)
        let updated = MarkdownParseCache.parse(second, renderKey: key)

        let stableIds = initial.blocks.dropLast().map(\.id)
        XCTAssertFalse(stableIds.isEmpty)
        XCTAssertEqual(Array(updated.blocks.prefix(stableIds.count)).map(\.id), stableIds)
        XCTAssertGreaterThan(updated.reusedBlockCount, 0)
        XCTAssertLessThan(updated.reparsedCharacterCount, second.count)
    }

    func testNonPrefixReplacementResetsIncrementalCache() {
        let key = AssistantMarkdownRenderKey.custom(UUID().uuidString)

        _ = MarkdownParseCache.parse("Original paragraph.\n\nTail paragraph.", renderKey: key)
        let replaced = MarkdownParseCache.parse("Replacement paragraph.", renderKey: key)

        XCTAssertEqual(replaced.reusedBlockCount, 0)
        XCTAssertEqual(replaced.reparsedCharacterCount, "Replacement paragraph.".count)
    }

    func testIncrementalOutputMatchesFullParseForMarkdownShapes() {
        let key = AssistantMarkdownRenderKey.custom(UUID().uuidString)
        let prefix = """
        # Heading

        - one
        - two

        | Name | Value |
        | --- | --- |
        | a | `1` |
        """
        let fullText = prefix + """

        ```swift
        let value = 1
        ```

        A [link](https://example.com) and **bold** text.
        """

        _ = MarkdownParseCache.parse(prefix, renderKey: key)
        let incremental = MarkdownParseCache.parse(fullText, renderKey: key)
        let full = MarkdownParseCache.parse(fullText)

        XCTAssertEqual(blockSignatures(incremental.blocks), blockSignatures(full.blocks))
        XCTAssertGreaterThan(incremental.reusedBlockCount, 0)
    }

    func testCodeBlockOrdinalsRemainStableAfterAppend() {
        let key = AssistantMarkdownRenderKey.custom(UUID().uuidString)
        let first = """
        ```swift
        let a = 1
        ```
        """
        let second = first + """

        Text between.

        ```bash
        echo ok
        ```
        """

        _ = MarkdownParseCache.parse(first, renderKey: key)
        let updated = MarkdownParseCache.parse(second, renderKey: key)

        XCTAssertEqual(codeBlockOrdinals(updated.blocks), [1, 2])
    }

    func testRepeatedParagraphAppendKeepsReparseWorkBoundedToTail() {
        let key = AssistantMarkdownRenderKey.custom(UUID().uuidString)
        var text = (0..<60)
            .map { "Paragraph \($0) has stable content." }
            .joined(separator: "\n\n")
        _ = MarkdownParseCache.parse(text, renderKey: key)

        var last = MarkdownParseCache.parse(text, renderKey: key)
        for idx in 0..<20 {
            text += "\n\nAppended paragraph \(idx)."
            last = MarkdownParseCache.parse(text, renderKey: key)
        }

        XCTAssertGreaterThan(last.reusedBlockCount, 50)
        XCTAssertLessThan(last.reparsedCharacterCount, text.count / 4)
    }

    func testStreamingIntermediateAppendReusesStableBlocksWithinLimit() {
        let key = AssistantMarkdownRenderKey.custom(UUID().uuidString)
        let first = "First paragraph.\n\nSecond paragraph."
        let second = first + "\n\nStreaming tail."

        let initial = MarkdownParseCache.parse(first, renderKey: key, phase: .streamingIntermediate)
        let updated = MarkdownParseCache.parse(second, renderKey: key, phase: .streamingIntermediate)

        let stableIds = initial.blocks.dropLast().map(\.id)
        XCTAssertEqual(Array(updated.blocks.prefix(stableIds.count)).map(\.id), stableIds)
        XCTAssertGreaterThan(updated.reusedBlockCount, 0)
    }

    func testOversizedStreamingIntermediateIsNotRetained() {
        let cache = AssistantMarkdownIncrementalCache(
            countLimit: 4,
            totalCostLimit: 20,
            maxEntryCost: 20,
            blockCost: 0
        )
        let key = AssistantMarkdownRenderKey.custom(UUID().uuidString)
        var buildCount = 0

        _ = document(
            from: cache,
            text: String(repeating: "x", count: 21),
            key: key,
            phase: .streamingIntermediate,
            buildCount: &buildCount
        )
        let second = document(
            from: cache,
            text: String(repeating: "x", count: 21),
            key: key,
            phase: .streamingIntermediate,
            buildCount: &buildCount
        )

        XCTAssertFalse(second.cacheHit)
        XCTAssertEqual(buildCount, 2)
    }

    func testSettledDocumentIsCachedWhenItFits() {
        let cache = AssistantMarkdownIncrementalCache(
            countLimit: 4,
            totalCostLimit: 64,
            maxEntryCost: 64,
            blockCost: 0
        )
        let key = AssistantMarkdownRenderKey.custom(UUID().uuidString)
        var buildCount = 0

        _ = document(from: cache, text: "fits", key: key, phase: .settled, buildCount: &buildCount)
        let second = document(from: cache, text: "fits", key: key, phase: .settled, buildCount: &buildCount)

        XCTAssertTrue(second.cacheHit)
        XCTAssertEqual(buildCount, 1)
    }

    func testCostLimitEvictsEvenUnderCountLimit() {
        let cache = AssistantMarkdownIncrementalCache(
            countLimit: 10,
            totalCostLimit: 20,
            maxEntryCost: 20,
            blockCost: 0
        )
        let firstKey = AssistantMarkdownRenderKey.custom(UUID().uuidString)
        let secondKey = AssistantMarkdownRenderKey.custom(UUID().uuidString)
        var firstBuildCount = 0
        var secondBuildCount = 0

        _ = document(from: cache, text: "aaaaaaaaaaaa", key: firstKey, phase: .settled, buildCount: &firstBuildCount)
        _ = document(from: cache, text: "bbbbbbbbbbbb", key: secondKey, phase: .settled, buildCount: &secondBuildCount)
        let firstAgain = document(from: cache, text: "aaaaaaaaaaaa", key: firstKey, phase: .settled, buildCount: &firstBuildCount)

        XCTAssertFalse(firstAgain.cacheHit)
        XCTAssertEqual(firstBuildCount, 2)
        XCTAssertEqual(secondBuildCount, 1)
    }

    func testGeneratedHeavyTableExceedsLazyRenderingThreshold() {
        let rows = (0..<(AssistantTableView.largeTableRowThreshold + 1))
            .map { "| row\($0) | value\($0) |" }
            .joined(separator: "\n")
        let markdown = """
        | Name | Value |
        | --- | --- |
        \(rows)
        """

        let parsed = MarkdownParseCache.parse(markdown)
        guard case .table(_, let tableRows) = parsed.blocks.first?.block else {
            return XCTFail("Expected generated markdown to parse as one table")
        }
        XCTAssertGreaterThan(tableRows.count, AssistantTableView.largeTableRowThreshold)
    }

    func testNestedListsPreserveHierarchyInBlockSignature() {
        let markdown = """
        - parent
          - child
            1. numbered child
        - sibling
        """

        let parsed = MarkdownParseCache.parse(markdown)

        XCTAssertEqual(blockSignatures(parsed.blocks), [
            "ul:parent[ul:child[ol:numbered child]]|sibling"
        ])
    }

    func testLongComplexMarkdownCachesAndKeepsAllHeavyShapes() {
        let nonce = UUID().uuidString
        let longBody = (0..<120)
            .map { "Paragraph \($0) \(nonce) keeps enough prose to exercise the long markdown path with **bold** and `inline` atoms." }
            .joined(separator: "\n\n")
        let markdown = """
        # Heavy response \(nonce)

        \(longBody)

        ```swift
        struct Fixture {
            let value: String
        }
        ```

        - parent
          - child
            1. numbered child

        | Name | Value |
        | --- | --- |
        | cache | hit |
        | timeline | window |
        """

        let first = MarkdownParseCache.parse(markdown)
        let second = MarkdownParseCache.parse(markdown)

        XCTAssertFalse(first.cacheHit)
        XCTAssertTrue(second.cacheHit)
        XCTAssertGreaterThan(first.blocks.count, 100)
        XCTAssertTrue(first.blocks.contains { if case .codeBlock = $0.block { return true }; return false })
        XCTAssertTrue(first.blocks.contains { if case .table = $0.block { return true }; return false })
        XCTAssertTrue(first.blocks.contains { blockContainsNestedList($0.block) })
    }

    func testAppendOnlyLongMarkdownReusesStableComplexBlocks() {
        let key = AssistantMarkdownRenderKey.custom(UUID().uuidString)
        let prefix = """
        # Heavy streaming response

        \(Array(0..<80).map { "Stable paragraph \($0)." }.joined(separator: "\n\n"))

        ```bash
        echo stable
        ```

        | Name | Value |
        | --- | --- |
        | before | append |
        """
        let appended = prefix + """

        - appended
          - nested

        Final paragraph.
        """

        _ = MarkdownParseCache.parse(prefix, renderKey: key, phase: .streamingIntermediate)
        let updated = MarkdownParseCache.parse(appended, renderKey: key, phase: .streamingIntermediate)

        XCTAssertGreaterThan(updated.reusedBlockCount, 70)
        XCTAssertLessThan(updated.reparsedCharacterCount, appended.count / 3)
        XCTAssertTrue(updated.blocks.contains { if case .codeBlock = $0.block { return true }; return false })
        XCTAssertTrue(updated.blocks.contains { if case .table = $0.block { return true }; return false })
        XCTAssertTrue(updated.blocks.contains { blockContainsNestedList($0.block) })
    }

    private func blockSignatures(_ blocks: [IndexedAnnotatedBlock]) -> [String] {
        blocks.map { item in
            switch item.block {
            case .paragraph(let paragraph):
                return "p:\(paragraph.lines.map(lineText).joined(separator: "|"))"
            case .heading(let level, let line):
                return "h\(level):\(lineText(line))"
            case .bulletList(let items):
                return "ul:\(items.map(listItemText).joined(separator: "|"))"
            case .numberedList(let items):
                return "ol:\(items.map(listItemText).joined(separator: "|"))"
            case .codeBlock(let language, let code):
                return "code:\(language):\(code)"
            case .table(let headers, let rows):
                let header = headers.map(lineText).joined(separator: "|")
                let body = rows.map { $0.map(lineText).joined(separator: "|") }.joined(separator: ";")
                return "table:\(header):\(body)"
            }
        }
    }

    private func codeBlockOrdinals(_ blocks: [IndexedAnnotatedBlock]) -> [Int] {
        blocks.compactMap { item in
            if case .codeBlock = item.block {
                return item.codeBlockOrdinal
            }
            return nil
        }
    }

    private func paragraphText(_ paragraph: AnnotatedParagraph) -> String {
        paragraph.lines.map(lineText).joined(separator: "\n")
    }

    private func blockContainsNestedList(_ block: AnnotatedBlock) -> Bool {
        switch block {
        case .bulletList(let items), .numberedList(let items):
            return items.contains { !$0.children.isEmpty }
        default:
            return false
        }
    }

    private func listItemText(_ item: AnnotatedListItem) -> String {
        let childText = item.children.map(nestedListText).joined()
        return paragraphText(item.paragraph) + childText
    }

    private func nestedListText(_ list: AnnotatedNestedList) -> String {
        switch list {
        case .bullet(let items):
            return "[ul:\(items.map(listItemText).joined(separator: "|"))]"
        case .numbered(let items):
            return "[ol:\(items.map(listItemText).joined(separator: "|"))]"
        }
    }

    private func lineText(_ line: AnnotatedLine) -> String {
        line.atoms.map(atomText).joined()
    }

    private func atomText(_ annotated: AnnotatedAtom) -> String {
        switch annotated.atom {
        case .word(let text), .bold(let text), .italic(let text), .code(let text):
            return text
        case .link(let label, let url, let isBareUrl):
            return "\(label)<\(url.absoluteString)>\(isBareUrl)"
        }
    }

    private func document(
        from cache: AssistantMarkdownIncrementalCache,
        text: String,
        key: AssistantMarkdownRenderKey,
        phase: MarkdownParseCachePhase,
        buildCount: inout Int
    ) -> AssistantMarkdownDocument {
        cache.document(
            for: text,
            key: key,
            phase: phase,
            buildFull: { source, idPrefix in
                buildCount += 1
                return testDocument(text: source, idPrefix: idPrefix)
            },
            buildTail: { fullText, _, _, _, _, idPrefix, stableBlocks in
                buildCount += 1
                var document = testDocument(text: fullText, idPrefix: idPrefix)
                document = AssistantMarkdownDocument(
                    text: document.text,
                    blocks: stableBlocks + document.blocks.dropFirst(stableBlocks.count),
                    cacheHit: document.cacheHit,
                    parseMs: document.parseMs,
                    annotateMs: document.annotateMs,
                    reusedBlockCount: stableBlocks.count,
                    reparsedCharacterCount: fullText.count
                )
                return document
            }
        )
    }

    private func testDocument(text: String, idPrefix: String) -> AssistantMarkdownDocument {
        let block = testIndexedBlock(id: "\(idPrefix):0:0", range: 0..<text.count)
        return AssistantMarkdownDocument(
            text: text,
            blocks: [block],
            cacheHit: false,
            parseMs: 0,
            annotateMs: 0,
            reusedBlockCount: 0,
            reparsedCharacterCount: text.count
        )
    }

    private func testIndexedBlock(id: String, range: Range<Int>) -> IndexedAnnotatedBlock {
        IndexedAnnotatedBlock(
            id: id,
            block: .paragraph(AnnotatedParagraph(lines: [])),
            sourceRange: range,
            codeBlockOrdinal: 0
        )
    }
}

private actor RenderModelParseCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}
