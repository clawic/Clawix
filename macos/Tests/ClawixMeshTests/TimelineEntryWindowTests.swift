import XCTest
@testable import Clawix

final class TimelineEntryWindowTests: XCTestCase {
    func testStreamingTimelineUnderLimitReturnsAllEntries() {
        let timeline = entries(count: 3)

        let visible = TimelineEntryWindow.visibleEntries(
            in: timeline,
            isStreaming: true,
            visibleLimit: 8
        )

        XCTAssertEqual(texts(in: visible), ["0", "1", "2"])
    }

    func testStreamingTimelineOverLimitReturnsLatestEntries() {
        let timeline = entries(count: 12)

        let visible = TimelineEntryWindow.visibleEntries(
            in: timeline,
            isStreaming: true,
            visibleLimit: 8
        )

        XCTAssertEqual(texts(in: visible), ["4", "5", "6", "7", "8", "9", "10", "11"])
    }

    func testCompletedTimelineUsesVisibleLimitAndExpandedLimit() {
        let timeline = entries(count: 12)

        let collapsed = TimelineEntryWindow.visibleEntries(
            in: timeline,
            isStreaming: false,
            visibleLimit: 8
        )
        let expanded = TimelineEntryWindow.visibleEntries(
            in: timeline,
            isStreaming: false,
            visibleLimit: 12
        )

        XCTAssertEqual(texts(in: collapsed), ["4", "5", "6", "7", "8", "9", "10", "11"])
        XCTAssertEqual(texts(in: expanded), (0..<12).map(String.init))
    }

    func testVisibleWindowRemainsBoundedWhenToolGroupContainsManyItems() {
        let tools = (0..<200).map { index in
            WorkItem(
                id: "cmd-\(index)",
                kind: .command(text: "pwd", actions: []),
                status: .completed
            )
        }
        let toolGroupID = UUID()
        let timeline = entries(count: 10) + [
            .tools(
                id: toolGroupID,
                items: tools,
                presentation: ToolTimelinePresentation.snapshot(groupID: toolGroupID, items: tools)
            )
        ]

        let visible = TimelineEntryWindow.visibleEntries(
            in: timeline,
            isStreaming: true,
            visibleLimit: 8
        )

        XCTAssertEqual(visible.count, 8)
        XCTAssertTrue(visible.contains { entry in
            if case .tools = entry { return true }
            return false
        })
    }

    func testFileLinkPreviewUsesOnlyAssistantMarkdownFileLinks() {
        let message = ChatMessage(
            role: .assistant,
            content: """
            See [one](/tmp/one.md), [two](/tmp/two.md), [duplicate](/tmp/one.md), \
            [three](/tmp/three.md), [four](/tmp/four.md), and [web](https://example.com).
            """,
            streamingFinished: true
        )

        let preview = FileLinkPreviewCache.shared.preview(for: message)

        XCTAssertEqual(preview.visiblePaths, ["/tmp/one.md", "/tmp/two.md", "/tmp/three.md"])
        XCTAssertEqual(preview.remainingCount, 1)
    }

    func testFileLinkPreviewSkipsSourceCodeLinks() {
        let message = ChatMessage(
            role: .assistant,
            content: """
            Updated [view](/tmp/ChatView+MessageRow.swift) and \
            [state](/tmp/ChatHydration.swift:42), see [doc](/tmp/notes.md).
            """,
            streamingFinished: true
        )

        let preview = FileLinkPreviewCache.shared.preview(for: message)

        XCTAssertEqual(preview.visiblePaths, ["/tmp/notes.md"])
        XCTAssertEqual(preview.remainingCount, 0)
    }

    func testFileLinkPreviewAcceptsMarkdownLinksWithLineSuffixes() {
        let message = ChatMessage(
            role: .assistant,
            content: """
            Updated [instructions](/Users/example/project/AGENTS.md:170), \
            [guide](/Users/example/project/docs/guide.markdown:12:4), and \
            [mdx](/Users/example/project/docs/page.mdx:9).
            """,
            streamingFinished: true
        )

        let preview = FileLinkPreviewCache.shared.preview(for: message)

        XCTAssertEqual(preview.visiblePaths, [
            "/Users/example/project/AGENTS.md",
            "/Users/example/project/docs/guide.markdown",
            "/Users/example/project/docs/page.mdx"
        ])
        XCTAssertEqual(preview.remainingCount, 0)
    }

    func testFileChangeTimelineDoesNotCreateTrailingFileLinkPreview() {
        let message = ChatMessage(
            role: .assistant,
            content: "Done.",
            streamingFinished: true,
            timeline: [
                .tools(
                    id: UUID(),
                    items: [
                        WorkItem(
                            id: "file-1",
                            kind: .fileChange(paths: ["README.md"]),
                            status: .completed
                        )
                    ]
                )
            ]
        )

        let preview = FileLinkPreviewCache.shared.preview(for: message)

        XCTAssertTrue(preview.isEmpty)
    }

    private func entries(count: Int) -> [AssistantTimelineEntry] {
        (0..<count).map { index in
            .message(id: UUID(), text: String(index))
        }
    }

    private func texts(in entries: [AssistantTimelineEntry]) -> [String] {
        entries.compactMap { entry in
            guard case .message(_, let text) = entry else { return nil }
            return text
        }
    }
}
