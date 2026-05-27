import AppKit
import SwiftUI
import ClawixCore

struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 0
    var verticalSpacing: CGFloat = 4

    struct Cache {
        var sizes: [CGSize] = []
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(sizes: subviews.map { $0.sizeThatFits(.unspecified) })
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let maxWidth = resolvedMaxWidth(proposal.width)
        var totalWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        for size in cache.sizes {
            if lineWidth + size.width > maxWidth, lineWidth > 0 {
                totalWidth = max(totalWidth, lineWidth)
                totalHeight += lineHeight + verticalSpacing
                lineWidth = 0
                lineHeight = 0
            }
            lineWidth += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }
        totalWidth = max(totalWidth, lineWidth)
        totalHeight += lineHeight
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let maxWidth = resolvedMaxWidth(bounds.width)
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0
        for (index, sub) in subviews.enumerated() {
            let size = index < cache.sizes.count ? cache.sizes[index] : sub.sizeThatFits(.unspecified)
            if x - bounds.minX + size.width > maxWidth, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + verticalSpacing
                lineHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }
    }

    private func resolvedMaxWidth(_ proposed: CGFloat?) -> CGFloat {
        guard let proposed, proposed.isFinite, proposed > 0 else {
            return chatRailMaxWidth
        }
        return proposed
    }
}

enum AssistantMarkdown {
    enum Block {
        case paragraph(Paragraph)
        case heading(level: Int, Line)
        case bulletList(items: [ListItem])
        case numberedList(items: [ListItem])
        case codeBlock(language: String, code: String)
        case table(headers: [Line], rows: [[Line]])
    }

    struct Paragraph {
        let lines: [Line]
    }

    struct Line {
        let atoms: [Atom]
    }

    struct ListItem {
        let paragraph: Paragraph
        let children: [NestedList]
    }

    enum NestedList {
        case bullet(items: [ListItem])
        case numbered(items: [ListItem])
    }

    struct BlockSlice {
        let block: Block
        let sourceRange: Range<Int>
    }

    enum Atom: Equatable {
        case word(String)        // plain token + trailing whitespace
        case bold(String)        // **strong** token + trailing whitespace
        case italic(String)      // *em* / _em_ token + trailing whitespace
        case code(String)
        case link(label: String, url: URL, isBareUrl: Bool)
    }

    /// Block-level parser. Walks the source line by line and groups
    /// contiguous lines into structural blocks. Inline parsing (links,
    /// code, bold, italic) runs once per produced line.
    static func parseBlocks(_ text: String) -> [Block] {
        parseBlockSlices(text).map(\.block)
    }

    /// Block-level parser with source ranges in character offsets over the
    /// normalized source. The renderer uses these ranges to preserve stable
    /// blocks while a streaming tail is still changing.
    static func parseBlockSlices(_ text: String) -> [BlockSlice] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = lineSlices(in: normalized)
        var blocks: [BlockSlice] = []
        var i = 0
        while i < lines.count {
            let line = lines[i].text
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Fenced code block: ``` [language]
            if trimmed.hasPrefix("```") {
                let start = lines[i].start
                let language = String(trimmed.dropFirst(3))
                    .trimmingCharacters(in: .whitespaces)
                var collected: [String] = []
                i += 1
                while i < lines.count {
                    if lines[i].text.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1
                        break
                    }
                    collected.append(lines[i].text)
                    i += 1
                }
                let end = i > 0 ? lines[i - 1].endIncludingNewline : normalized.count
                blocks.append(BlockSlice(
                    block: .codeBlock(language: language,
                                      code: collected.joined(separator: "\n")),
                    sourceRange: start..<end
                ))
                continue
            }

            // ATX heading
            if let level = headingLevel(for: trimmed) {
                let body = String(trimmed.dropFirst(level))
                    .trimmingCharacters(in: .whitespaces)
                blocks.append(BlockSlice(
                    block: .heading(level: level,
                                    Line(atoms: parseAtoms(in: body))),
                    sourceRange: lines[i].start..<lines[i].endIncludingNewline
                ))
                i += 1
                continue
            }

            // Pipe table: header row + alignment row + 0..N data rows
            if let (headers, rows, consumed) = parseTable(at: i, lines: lines) {
                let start = lines[i].start
                let end = lines[i + consumed - 1].endIncludingNewline
                blocks.append(BlockSlice(
                    block: .table(headers: headers, rows: rows),
                    sourceRange: start..<end
                ))
                i += consumed
                continue
            }

            if let (listBlock, consumed) = parseListBlock(at: i, lines: lines) {
                let start = lines[i].start
                let end = lines[i + consumed - 1].endIncludingNewline
                blocks.append(BlockSlice(block: listBlock, sourceRange: start..<end))
                i += consumed
                continue
            }

            // Paragraph: gather contiguous non-blank lines until the next
            // structural break.
            let start = lines[i].start
            var paragraphLines: [Line] = [Line(atoms: parseAtoms(in: line))]
            i += 1
            while i < lines.count {
                let next = lines[i].text
                let nt = next.trimmingCharacters(in: .whitespaces)
                if nt.isEmpty
                    || headingLevel(for: nt) != nil
                    || nt.hasPrefix("```")
                    || listMarker(in: next) != nil
                    || isTableHeaderCandidate(nt, nextTrimmed: i + 1 < lines.count ? lines[i + 1].text.trimmingCharacters(in: .whitespaces) : nil) {
                    break
                }
                paragraphLines.append(Line(atoms: parseAtoms(in: next)))
                i += 1
            }
            let nonEmpty = paragraphLines.filter { !$0.atoms.isEmpty }
            if !nonEmpty.isEmpty {
                let end = i > 0 ? lines[i - 1].endIncludingNewline : start
                blocks.append(BlockSlice(
                    block: .paragraph(Paragraph(lines: nonEmpty)),
                    sourceRange: start..<end
                ))
            }
        }
        return blocks
    }

    // MARK: - Block helpers

    private static func headingLevel(for trimmed: String) -> Int? {
        guard trimmed.hasPrefix("#") else { return nil }
        var hashes = 0
        for ch in trimmed {
            if ch == "#" { hashes += 1 } else { break }
        }
        guard (1...6).contains(hashes),
              trimmed.count > hashes,
              trimmed[trimmed.index(trimmed.startIndex, offsetBy: hashes)] == " "
        else { return nil }
        return hashes
    }

    private static func isBulletPrefix(_ trimmed: String) -> Bool {
        trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ")
    }

    private static func numberedRange(in trimmed: String) -> Range<String.Index>? {
        trimmed.range(of: #"^\d+[.)]\s"#, options: .regularExpression)
    }

    private enum ListKind: Equatable {
        case bullet
        case numbered
    }

    private struct ListMarker {
        let kind: ListKind
        let indent: Int
        let body: String
    }

    private static func parseListBlock(at start: Int, lines: [SourceLine]) -> (Block, Int)? {
        guard let marker = listMarker(in: lines[start].text) else { return nil }
        var index = start
        let items = parseListItems(
            lines: lines,
            index: &index,
            baseIndent: marker.indent,
            kind: marker.kind
        )
        guard !items.isEmpty else { return nil }
        switch marker.kind {
        case .bullet:
            return (.bulletList(items: items), index - start)
        case .numbered:
            return (.numberedList(items: items), index - start)
        }
    }

    private static func parseListItems(
        lines: [SourceLine],
        index: inout Int,
        baseIndent: Int,
        kind: ListKind
    ) -> [ListItem] {
        var items: [ListItem] = []
        while index < lines.count {
            guard let marker = listMarker(in: lines[index].text) else { break }
            if marker.indent < baseIndent { break }
            if marker.indent > baseIndent {
                break
            }
            guard marker.kind == kind else { break }

            index += 1
            var children: [NestedList] = []
            while index < lines.count,
                  let childMarker = listMarker(in: lines[index].text),
                  childMarker.indent > baseIndent {
                let childIndent = childMarker.indent
                let childKind = childMarker.kind
                let childItems = parseListItems(
                    lines: lines,
                    index: &index,
                    baseIndent: childIndent,
                    kind: childKind
                )
                guard !childItems.isEmpty else { break }
                switch childKind {
                case .bullet:
                    children.append(.bullet(items: childItems))
                case .numbered:
                    children.append(.numbered(items: childItems))
                }
            }

            items.append(ListItem(
                paragraph: Paragraph(lines: [Line(atoms: parseAtoms(in: marker.body))]),
                children: children
            ))
        }
        return items
    }

    private static func listMarker(in raw: String) -> ListMarker? {
        let indent = leadingIndent(in: raw)
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if isBulletPrefix(trimmed) {
            return ListMarker(kind: .bullet, indent: indent, body: String(trimmed.dropFirst(2)))
        }
        if let range = numberedRange(in: trimmed) {
            return ListMarker(kind: .numbered, indent: indent, body: String(trimmed[range.upperBound...]))
        }
        return nil
    }

    private static func leadingIndent(in raw: String) -> Int {
        var count = 0
        for character in raw {
            if character == " " {
                count += 1
            } else if character == "\t" {
                count += 4
            } else {
                break
            }
        }
        return count
    }

    private struct SourceLine {
        let text: String
        let start: Int
        let end: Int
        let endIncludingNewline: Int
    }

    private static func lineSlices(in source: String) -> [SourceLine] {
        let parts = source.components(separatedBy: "\n")
        var lines: [SourceLine] = []
        lines.reserveCapacity(parts.count)
        var offset = 0
        for (idx, part) in parts.enumerated() {
            let end = offset + part.count
            let next = end + (idx < parts.count - 1 ? 1 : 0)
            lines.append(SourceLine(
                text: part,
                start: offset,
                end: end,
                endIncludingNewline: next
            ))
            offset = next
        }
        return lines
    }

    /// Quick check used while gathering paragraph lines so we don't
    /// swallow the start of a table into a preceding paragraph.
    private static func isTableHeaderCandidate(_ trimmed: String, nextTrimmed: String?) -> Bool {
        guard trimmed.hasPrefix("|"), trimmed.contains("|"),
              let next = nextTrimmed else { return false }
        return isTableAlignmentRow(next)
    }

    /// Returns the parsed headers/rows of a pipe table starting at
    /// `start`, or `nil` if the lines at that position are not a table.
    private static func parseTable(at start: Int, lines: [SourceLine]) -> (headers: [Line], rows: [[Line]], consumed: Int)? {
        guard start + 1 < lines.count else { return nil }
        let header = lines[start].text.trimmingCharacters(in: .whitespaces)
        let alignment = lines[start + 1].text.trimmingCharacters(in: .whitespaces)
        guard header.contains("|"), isTableAlignmentRow(alignment) else { return nil }
        let headerCells = splitTableRow(header)
        guard !headerCells.isEmpty else { return nil }

        var rows: [[Line]] = []
        var i = start + 2
        while i < lines.count {
            let raw = lines[i].text.trimmingCharacters(in: .whitespaces)
            if raw.isEmpty || !raw.contains("|") { break }
            // Stop if we hit a non-pipe-leading line that is clearly another block.
            let cells = splitTableRow(raw)
            if cells.isEmpty { break }
            rows.append(cells.map { Line(atoms: parseAtoms(in: $0)) })
            i += 1
        }
        let headerLines = headerCells.map { Line(atoms: parseAtoms(in: $0)) }
        return (headerLines, rows, i - start)
    }

    private static func isTableAlignmentRow(_ trimmed: String) -> Bool {
        guard trimmed.contains("|"), trimmed.contains("-") else { return false }
        let cells = splitTableRow(trimmed)
        guard !cells.isEmpty else { return false }
        let pattern = #"^:?-{1,}:?$"#
        for cell in cells {
            let t = cell.trimmingCharacters(in: .whitespaces)
            if t.range(of: pattern, options: .regularExpression) == nil { return false }
        }
        return true
    }

    /// Split a pipe-table row into its cells, stripping the optional
    /// leading and trailing pipes so " | a | b | " yields ["a", "b"].
    private static func splitTableRow(_ trimmed: String) -> [String] {
        var s = trimmed
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        return s.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    // MARK: - Inline parsing

    /// Tokenise one line into atoms. Plain prose is split into word atoms
    /// (each carries its trailing space) so the FlowLayout can wrap mid
    /// paragraph; links, code chips and bold/italic spans become their
    /// own atoms so they keep per-element styling and hover/tap handling.
    static func parseAtoms(in input: String) -> [Atom] {
        var atoms: [Atom] = []
        var pending = ""
        var i = input.startIndex

        func flushWords() {
            guard !pending.isEmpty else { return }
            atoms.append(contentsOf: splitIntoWords(pending, style: .plain))
            pending = ""
        }

        while i < input.endIndex {
            let ch = input[i]

            // Bold: **text**
            if ch == "*",
               input.index(after: i) < input.endIndex,
               input[input.index(after: i)] == "*" {
                let openEnd = input.index(i, offsetBy: 2)
                if let closeStart = findRange(of: "**", in: input, from: openEnd) {
                    flushWords()
                    let body = String(input[openEnd..<closeStart])
                    atoms.append(contentsOf: splitIntoWords(body, style: .bold))
                    i = input.index(closeStart, offsetBy: 2)
                    continue
                }
            }

            // Italic: *text* (single asterisk, not part of a **)
            if ch == "*" {
                let openEnd = input.index(after: i)
                if openEnd < input.endIndex, input[openEnd] != "*",
                   let closeStart = findSingleAsterisk(in: input, from: openEnd) {
                    flushWords()
                    let body = String(input[openEnd..<closeStart])
                    atoms.append(contentsOf: splitIntoWords(body, style: .italic))
                    i = input.index(after: closeStart)
                    continue
                }
            }

            // Italic: _text_
            if ch == "_" {
                let openEnd = input.index(after: i)
                if openEnd < input.endIndex,
                   let closeStart = input[openEnd...].firstIndex(of: "_") {
                    let body = String(input[openEnd..<closeStart])
                    if !body.contains(" ") || body.trimmingCharacters(in: .whitespaces) == body {
                        flushWords()
                        atoms.append(contentsOf: splitIntoWords(body, style: .italic))
                        i = input.index(after: closeStart)
                        continue
                    }
                }
            }

            // Markdown link: [label](url)
            if ch == "[" {
                if let close = input[i...].firstIndex(of: "]"),
                   input.index(after: close) < input.endIndex,
                   input[input.index(after: close)] == "(" {
                    let labelStart = input.index(after: i)
                    let urlOpen = input.index(after: close)
                    if let urlClose = input[urlOpen...].firstIndex(of: ")") {
                        let label = String(input[labelStart..<close])
                        let rawURLStr = String(input[input.index(after: urlOpen)..<urlClose])
                        let urlStr = Self.unwrapMarkdownLinkDestination(rawURLStr)
                        // Local agents write files as bare absolute paths
                        // inside markdown links (`[label](/abs/path.md)`).
                        // Promote those to file:// URLs so the renderer can
                        // tell them apart from web links and the tap routes
                        // to the in-app file viewer instead of the browser.
                        let url: URL? = urlStr.hasPrefix("/")
                            ? URL(fileURLWithPath: urlStr)
                            : URL(string: urlStr)
                        if let url {
                            flushWords()
                            atoms.append(.link(
                                label: label,
                                url: url,
                                isBareUrl: label == urlStr
                            ))
                            i = input.index(after: urlClose)
                            continue
                        }
                    }
                }
            }

            // Bare URL: http(s)://... — promote to a link atom so the
            // user gets the same chip / hover / right-click treatment as
            // a markdown link, even when the model emitted a raw URL.
            if ch == "h" {
                let suffix = input[i...]
                let scheme: String?
                if suffix.hasPrefix("https://") {
                    scheme = "https://"
                } else if suffix.hasPrefix("http://") {
                    scheme = "http://"
                } else {
                    scheme = nil
                }
                let atBoundary = pending.isEmpty
                    || pending.last.map { $0.isWhitespace || "([{<".contains($0) } ?? true
                if let scheme, atBoundary {
                    var end = input.index(i, offsetBy: scheme.count)
                    while end < input.endIndex {
                        let c = input[end]
                        if c.isWhitespace || c == "\n" { break }
                        end = input.index(after: end)
                    }
                    let trailers: Set<Character> = [
                        ".", ",", ";", ":", "!", "?", "·",
                        ")", "]", "}", ">", "'", "\""
                    ]
                    let bodyStart = input.index(i, offsetBy: scheme.count)
                    while end > bodyStart {
                        let prev = input.index(before: end)
                        if trailers.contains(input[prev]) {
                            end = prev
                        } else {
                            break
                        }
                    }
                    if end > bodyStart {
                        let urlStr = String(input[i..<end])
                        if let url = URL(string: urlStr) {
                            flushWords()
                            atoms.append(.link(
                                label: urlStr,
                                url: url,
                                isBareUrl: true
                            ))
                            i = end
                            continue
                        }
                    }
                }
            }

            // Inline code: `code`
            if ch == "`" {
                let afterTick = input.index(after: i)
                if afterTick < input.endIndex,
                   let close = input[afterTick...].firstIndex(of: "`") {
                    flushWords()
                    atoms.append(.code(String(input[afterTick..<close])))
                    i = input.index(after: close)
                    continue
                }
            }

            pending.append(ch)
            i = input.index(after: i)
        }
        flushWords()
        return atoms
    }

    private enum InlineStyle { case plain, bold, italic }

    /// Find the next occurrence of `needle` starting at `from`, scanning
    /// for either a multi-character delimiter (`**`) or a marker we want
    /// to anchor on a non-asterisk neighbour.
    private static func findRange(of needle: String, in source: String, from: String.Index) -> String.Index? {
        return source.range(of: needle, range: from..<source.endIndex)?.lowerBound
    }

    /// Locate the closing single-asterisk for an italic span, skipping
    /// any `**` pairs that appear inside the candidate region so we don't
    /// confuse italic with a half-open bold.
    private static func findSingleAsterisk(in source: String, from: String.Index) -> String.Index? {
        var i = from
        while i < source.endIndex {
            if source[i] == "*" {
                // Skip if this is actually `**` (start of a new bold).
                let next = source.index(after: i)
                if next < source.endIndex, source[next] == "*" {
                    i = source.index(after: next)
                    continue
                }
                return i
            }
            i = source.index(after: i)
        }
        return nil
    }

    /// Split prose into atoms, attaching trailing whitespace to each
    /// token so FlowLayout has a natural break point between them.
    private static func splitIntoWords(_ s: String, style: InlineStyle) -> [Atom] {
        var out: [Atom] = []
        var current = ""
        var inWhitespaceTail = false

        func emit(_ token: String) {
            switch style {
            case .plain:  out.append(.word(token))
            case .bold:   out.append(.bold(token))
            case .italic: out.append(.italic(token))
            }
        }

        for ch in s {
            if ch == " " || ch == "\t" {
                current.append(ch)
                inWhitespaceTail = true
            } else {
                if inWhitespaceTail, !current.isEmpty {
                    emit(current)
                    current = ""
                    inWhitespaceTail = false
                }
                current.append(ch)
            }
        }
        if !current.isEmpty {
            emit(current)
        }
        return out
    }

    private static func unwrapMarkdownLinkDestination(_ raw: String) -> String {
        guard raw.hasPrefix("<"), raw.hasSuffix(">"), raw.count >= 2 else {
            return raw
        }
        return String(raw.dropFirst().dropLast())
    }

    /// Walk every block in the source and return the URLs of every link
    /// atom. Used by callers that want to surface the assistant's links
    /// outside the prose flow (e.g. the trailing "Website" card).
    static func extractLinkURLs(in text: String) -> [URL] {
        var urls: [URL] = []
        for block in parseBlocks(text) {
            visitLines(in: block) { line in
                for atom in line.atoms {
                    if case .link(_, let url, _) = atom {
                        urls.append(url)
                    }
                }
            }
        }
        return urls
    }

    private static func visitLines(in block: Block, body: (Line) -> Void) {
        switch block {
        case .paragraph(let p):
            p.lines.forEach(body)
        case .heading(_, let line):
            body(line)
        case .bulletList(let items), .numberedList(let items):
            for item in items {
                visitLines(in: item, body: body)
            }
        case .table(let headers, let rows):
            headers.forEach(body)
            for row in rows { row.forEach(body) }
        case .codeBlock:
            break
        }
    }

    private static func visitLines(in item: ListItem, body: (Line) -> Void) {
        item.paragraph.lines.forEach(body)
        for child in item.children {
            switch child {
            case .bullet(let items), .numbered(let items):
                for childItem in items {
                    visitLines(in: childItem, body: body)
                }
            }
        }
    }
}
