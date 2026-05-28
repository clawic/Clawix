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

    func testAdjacentToolGroupsCoalesceLikeToolDisclosure() {
        let firstGroupID = UUID()
        let secondGroupID = UUID()
        let thirdGroupID = UUID()
        let fourthGroupID = UUID()
        let fifthGroupID = UUID()
        let firstGroup = [
            command("cmd-1"),
            command("cmd-2"),
            computerUse("cu-1")
        ]
        let secondGroup = [
            read("read-1"),
            command("cmd-3")
        ]
        let thirdGroup = (4...6).map { command("cmd-\($0)") }
        let fourthGroup = [command("cmd-7")]
        let fifthGroup = (8...10).map { command("cmd-\($0)") }
        let timeline: [AssistantTimelineEntry] = [
            .tools(
                id: firstGroupID,
                items: firstGroup,
                presentation: ToolTimelinePresentation.snapshot(groupID: firstGroupID, items: firstGroup)
            ),
            .tools(
                id: secondGroupID,
                items: secondGroup,
                presentation: ToolTimelinePresentation.snapshot(groupID: secondGroupID, items: secondGroup)
            ),
            .message(id: UUID(), text: "La segunda pasada caliente no generó eventos."),
            .tools(
                id: thirdGroupID,
                items: thirdGroup,
                presentation: ToolTimelinePresentation.snapshot(groupID: thirdGroupID, items: thirdGroup)
            ),
            .tools(
                id: fourthGroupID,
                items: fourthGroup,
                presentation: ToolTimelinePresentation.snapshot(groupID: fourthGroupID, items: fourthGroup)
            ),
            .tools(
                id: fifthGroupID,
                items: fifthGroup,
                presentation: ToolTimelinePresentation.snapshot(groupID: fifthGroupID, items: fifthGroup)
            ),
            .message(id: UUID(), text: "Hecho.")
        ]

        let visible = TimelineEntryWindow.visibleEntries(
            in: timeline,
            isStreaming: false,
            visibleLimit: timeline.count
        )

        XCTAssertEqual(visible.count, 4)
        XCTAssertEqual(toolTexts(in: visible), [
            "Explored 1 file, ran 3 commands, used Computer Use",
            "Ran 7 commands"
        ])
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

    func testWebLinksStayInlineWithoutTrailingPreviewCard() {
        let message = ChatMessage(
            role: .assistant,
            content: "Open https://example.com and [docs](https://example.com/docs).",
            streamingFinished: true
        )

        XCTAssertNil(AssistantWebLinkPreviewPolicy.url(for: message))
    }

    func testFileLinkPreviewIncludesImageLinks() {
        let message = ChatMessage(
            role: .assistant,
            content: """
            See [window](/tmp/codex-window-test.png), \
            [search](/tmp/codex-sidebar-search-cliclick-test.PNG), and \
            [page](/tmp/codex-page-down-test.webp).
            """,
            streamingFinished: true
        )

        let preview = FileLinkPreviewCache.shared.preview(for: message)

        XCTAssertEqual(preview.visiblePaths, [
            "/tmp/codex-window-test.png",
            "/tmp/codex-sidebar-search-cliclick-test.PNG",
            "/tmp/codex-page-down-test.webp"
        ])
        XCTAssertEqual(preview.remainingCount, 0)
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

    func testExpandedTimelineSuppressesDuplicatedCanonicalBody() {
        let finalId = UUID()
        let timeline: [AssistantTimelineEntry] = [
            .message(id: UUID(), text: "I checked the app."),
            .message(id: finalId, text: "Done.")
        ]

        XCTAssertFalse(TimelineEntryWindow.shouldShowCanonicalBody(
            in: timeline,
            content: "Done.",
            isStreaming: false,
            timelineExpanded: true
        ))
        XCTAssertTrue(TimelineEntryWindow.shouldShowCanonicalBody(
            in: timeline,
            content: "Done.",
            isStreaming: false,
            timelineExpanded: false
        ))
    }

    func testExpandedTimelineSuppressesCanonicalBodyWhenFinalIsInCombinedMessage() {
        let timeline: [AssistantTimelineEntry] = [
            .message(id: UUID(), text: "I checked the app.\n\nDone.")
        ]

        XCTAssertFalse(TimelineEntryWindow.shouldShowCanonicalBody(
            in: timeline,
            content: "Done.",
            isStreaming: false,
            timelineExpanded: true
        ))
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

    private func toolTexts(in entries: [AssistantTimelineEntry]) -> [String] {
        entries.compactMap { entry in
            guard case .tools(_, _, let presentation) = entry else { return nil }
            return presentation?.aggregateRows.map(\.text).joined(separator: " | ")
        }
    }

    private func command(_ id: String) -> WorkItem {
        WorkItem(id: id, kind: .command(text: "pwd", actions: []), status: .completed)
    }

    private func read(_ id: String) -> WorkItem {
        WorkItem(id: id, kind: .command(text: "sed -n '1p' README.md", actions: [.read]), status: .completed)
    }

    private func computerUse(_ id: String) -> WorkItem {
        WorkItem(id: id, kind: .mcpTool(server: "computer_use", tool: "click"), status: .completed)
    }
}
