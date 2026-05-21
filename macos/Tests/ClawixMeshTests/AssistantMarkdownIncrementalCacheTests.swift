import XCTest
@testable import Clawix

final class AssistantMarkdownIncrementalCacheTests: XCTestCase {
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

    private func blockSignatures(_ blocks: [IndexedAnnotatedBlock]) -> [String] {
        blocks.map { item in
            switch item.block {
            case .paragraph(let paragraph):
                return "p:\(paragraph.lines.map(lineText).joined(separator: "|"))"
            case .heading(let level, let line):
                return "h\(level):\(lineText(line))"
            case .bulletList(let items):
                return "ul:\(items.map(paragraphText).joined(separator: "|"))"
            case .numberedList(let items):
                return "ol:\(items.map(paragraphText).joined(separator: "|"))"
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
}
