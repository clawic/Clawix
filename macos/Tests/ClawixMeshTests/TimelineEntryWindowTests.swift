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

    func testCompletedAssistantMessageExposesChangedFileCardsImmediately() {
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
                            kind: .fileChange(paths: ["README.md", "docs/notes.md", "README.md"]),
                            status: .completed
                        )
                    ]
                )
            ]
        )

        let paths = ChatTrailingCards.changedFilePaths(
            for: message,
            responseStreaming: false
        )

        XCTAssertEqual(paths, ["README.md", "docs/notes.md"])
    }

    func testStreamingAssistantMessageDefersChangedFileCards() {
        let message = ChatMessage(
            role: .assistant,
            content: "Working.",
            streamingFinished: false,
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

        let paths = ChatTrailingCards.changedFilePaths(
            for: message,
            responseStreaming: true
        )

        XCTAssertEqual(paths, [])
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
