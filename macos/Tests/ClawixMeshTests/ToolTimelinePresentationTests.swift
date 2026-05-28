import XCTest
@testable import Clawix

final class ToolTimelinePresentationTests: XCTestCase {
    func testIncrementalAppendAdvancesVersionAndMatchesFullSnapshot() {
        let groupID = UUID()
        let first = WorkItem(
            id: "cmd-1",
            kind: .command(text: "sed -n '1p' README.md", actions: [.read]),
            status: .completed
        )
        let second = WorkItem(
            id: "cmd-2",
            kind: .command(text: "rg timeline", actions: [.search]),
            status: .completed
        )

        let seed = ToolTimelinePresentation.snapshot(groupID: groupID, items: [first])
        let updated = ToolTimelinePresentation.updatedSnapshot(
            groupID: groupID,
            previousItems: [first],
            currentSnapshot: seed,
            applying: second
        )

        XCTAssertEqual(updated.version, seed.version + 1)
        XCTAssertEqual(updated.aggregateRows, ToolTimelinePresentation.aggregateRows(for: [first, second]))
    }

    func testIncrementalStatusTransitionMovesCommandOutOfRunningRows() {
        let groupID = UUID()
        let running = WorkItem(
            id: "cmd-1",
            kind: .command(text: "swift test", actions: []),
            status: .inProgress
        )
        let completed = WorkItem(
            id: "cmd-1",
            kind: .command(text: "swift test", actions: []),
            status: .completed
        )

        let seed = ToolTimelinePresentation.snapshot(groupID: groupID, items: [running])
        XCTAssertEqual(seed.runningCommands, [running])
        XCTAssertEqual(seed.aggregateRows, [])

        let updated = ToolTimelinePresentation.updatedSnapshot(
            groupID: groupID,
            previousItems: [running],
            currentSnapshot: seed,
            applying: completed
        )

        XCTAssertEqual(updated.runningCommands, [])
        XCTAssertEqual(updated.aggregateRows, ToolTimelinePresentation.aggregateRows(for: [completed]))
    }

    func testIncrementalFileChangeRowsMatchFullSnapshotPhrasing() {
        let groupID = UUID()
        let command = WorkItem(
            id: "cmd-1",
            kind: .command(text: "swift test", actions: []),
            status: .completed
        )
        let edit = WorkItem(
            id: "edit-1",
            kind: .fileChange(paths: ["Sources/App.swift"]),
            status: .completed
        )

        let seed = ToolTimelinePresentation.snapshot(groupID: groupID, items: [command])
        let updated = ToolTimelinePresentation.updatedSnapshot(
            groupID: groupID,
            previousItems: [command],
            currentSnapshot: seed,
            applying: edit
        )

        XCTAssertEqual(updated.aggregateRows, ToolTimelinePresentation.aggregateRows(for: [command, edit]))
        XCTAssertEqual(updated.aggregateRows.first?.text, "Edited 1 file, ran 1 command")
    }

    func testSameFamilyCommandGroupUsesVersionedAggregate() {
        let groupID = UUID()
        var items: [WorkItem] = [
            WorkItem(id: "cmd-0", kind: .command(text: "pwd", actions: []), status: .completed)
        ]
        var snapshot = ToolTimelinePresentation.snapshot(groupID: groupID, items: items)

        for index in 1..<50 {
            let item = WorkItem(
                id: "cmd-\(index)",
                kind: .command(text: "pwd", actions: []),
                status: .completed
            )
            snapshot = ToolTimelinePresentation.updatedSnapshot(
                groupID: groupID,
                previousItems: items,
                currentSnapshot: snapshot,
                applying: item
            )
            items.append(item)
        }

        XCTAssertEqual(snapshot.version, 49)
        XCTAssertEqual(snapshot.aggregateRows, ToolTimelinePresentation.aggregateRows(for: items))
    }

    func testSeededSnapshotMatchesHydratedFullRows() {
        let items = [
            WorkItem(id: "web-1", kind: .webSearch, status: .completed),
            WorkItem(id: "js-1", kind: .jsCall(title: "Inspect page", flavor: .browser), status: .completed),
            WorkItem(id: "img-1", kind: .imageView, status: .completed)
        ]

        let snapshot = ToolTimelinePresentation.snapshot(groupID: UUID(), items: items)

        XCTAssertEqual(snapshot.aggregateRows, ToolTimelinePresentation.aggregateRows(for: items))
    }

    func testPathBackedViewedImagesRenderAsPreviewsInsteadOfTextRows() {
        let items = [
            WorkItem(
                id: "cmd-1",
                kind: .command(text: "screencapture -x -R 20,39,1200,900 window.png", actions: []),
                status: .completed
            ),
            WorkItem(
                id: "img-1",
                kind: .imageView,
                status: .completed,
                generatedImagePath: "/tmp/window.png"
            )
        ]

        XCTAssertEqual(ToolTimelinePresentation.aggregateRows(for: items), [
            ToolTimelineRow(id: "exec", icon: "clawix.terminal", text: "Ran 1 command")
        ])

        let previews = ToolTimelinePresentation.previewImageRows(for: items)
        XCTAssertEqual(previews.map(\.id), ["img-1"])
        XCTAssertEqual(previews.map(\.previewImagePath), ["/tmp/window.png"])
    }

    func testSeededPathBackedViewedImagesMatchFullSnapshot() {
        let items = [
            WorkItem(
                id: "cmd-1",
                kind: .command(text: "screencapture -x -R 20,39,1200,900 window.png", actions: []),
                status: .completed
            ),
            WorkItem(
                id: "img-1",
                kind: .imageView,
                status: .completed,
                generatedImagePath: "/tmp/window.png"
            )
        ]

        let seeded = ToolTimelinePresentation.snapshot(groupID: UUID(), items: items)
        let full = ToolTimelinePresentation.snapshot(for: items)

        XCTAssertEqual(seeded.aggregateRows, full.aggregateRows)
        XCTAssertFalse(seeded.aggregateRows.contains { $0.id == "imgView" })
    }

    func testUnresolvedViewedImagesKeepTextSummary() {
        let rows = ToolTimelinePresentation.aggregateRows(for: [
            WorkItem(id: "img-1", kind: .imageView, status: .completed)
        ])

        XCTAssertEqual(rows, [
            ToolTimelineRow(id: "imgView", icon: "eye", text: "Viewed 1 image")
        ])
        XCTAssertTrue(ToolTimelinePresentation.previewImageRows(for: [
            WorkItem(id: "img-1", kind: .imageView, status: .completed)
        ]).isEmpty)
    }

    func testDetailRowsPreserveEveryCompletedCommandText() {
        let rows = ToolTimelinePresentation.detailRows(for: [
            WorkItem(
                id: "cmd-1",
                kind: .command(text: "sed -n '1p' README.md", actions: [.read]),
                status: .completed
            ),
            WorkItem(
                id: "cmd-2",
                kind: .command(text: "rg timeline", actions: [.search]),
                status: .completed
            )
        ])

        XCTAssertEqual(rows.map(\.id), ["cmd-1", "cmd-2"])
        XCTAssertEqual(rows.map(\.text), [
            "Read README.md",
            "Searched timeline"
        ])
    }

    func testAggregateDetailRowsExposeCompletedRowsForDisclosure() {
        let items = [
            WorkItem(
                id: "read-1",
                kind: .command(text: "sed -n '1,90p' /tmp/agent-commit-scope.mjs", actions: [.read]),
                status: .completed
            ),
            WorkItem(
                id: "cmd-1",
                kind: .command(text: "git status --short", actions: []),
                status: .completed
            ),
            WorkItem(id: "web-1", kind: .webSearch, status: .completed)
        ]

        let rows = ToolTimelinePresentation.detailRows(for: items, aggregateRowID: "exec")

        XCTAssertEqual(rows.map(\.text), [
            "Read agent-commit-scope.mjs",
            "Ran git status --short",
            "Searched web"
        ])
    }

    func testDetailRowsKeepRepeatedMcpCallsSeparate() {
        let rows = ToolTimelinePresentation.detailRows(for: [
            WorkItem(id: "cu-1", kind: .mcpTool(server: "clawjs-mcp", tool: "computer_use.click"), status: .completed),
            WorkItem(id: "cu-2", kind: .mcpTool(server: "clawjs-mcp", tool: "computer_use.type_text"), status: .completed)
        ])

        XCTAssertEqual(rows.map(\.id), ["cu-1", "cu-2"])
        XCTAssertEqual(rows.map(\.icon), ["clawix.computerUse", "clawix.computerUse"])
        XCTAssertEqual(rows.map(\.text), [
            L10n.usedTool("Computer Use"),
            L10n.usedTool("Computer Use")
        ])
    }

    func testAggregateRowsFoldEditedFilesIntoActivityLine() {
        let rows = ToolTimelinePresentation.aggregateRows(for: [
            WorkItem(
                id: "edit-1",
                kind: .fileChange(paths: ["README.md", "README.md"]),
                status: .completed
            ),
            WorkItem(
                id: "read-1",
                kind: .command(text: "sed -n '1p' README.md", actions: [.read]),
                status: .completed
            ),
            WorkItem(
                id: "cmd-1",
                kind: .command(text: "swift test", actions: []),
                status: .completed
            )
        ])

        XCTAssertEqual(rows, [
            ToolTimelineRow(
                id: "exec",
                icon: "clawix.terminal",
                text: "Edited 1 file, explored 1 file, ran 1 command"
            )
        ])
    }

    func testAggregateRowsUseSearchIconForEditedExplorationWithoutCommands() {
        let rows = ToolTimelinePresentation.aggregateRows(for: [
            WorkItem(
                id: "edit-1",
                kind: .fileChange(paths: ["AGENTS.md"]),
                status: .completed
            ),
            WorkItem(
                id: "read-1",
                kind: .command(text: "sed -n '1p' AGENTS.md", actions: [.read]),
                status: .completed
            ),
            WorkItem(
                id: "search-1",
                kind: .command(text: "rg \"Desktop Control\" AGENTS.md", actions: [.search]),
                status: .completed
            )
        ])

        XCTAssertEqual(rows, [
            ToolTimelineRow(
                id: "exec",
                icon: "magnifyingglass",
                text: "Edited 1 file, explored 1 file, 1 search"
            )
        ])
    }

    func testAggregateRowsUsePackageIconForReadOnlyExploration() {
        let rows = ToolTimelinePresentation.aggregateRows(for: [
            WorkItem(
                id: "read-1",
                kind: .command(text: "sed -n '1p' AGENTS.md", actions: [.read]),
                status: .completed
            )
        ])

        XCTAssertEqual(rows, [
            ToolTimelineRow(
                id: "exec",
                icon: "clawix.package",
                text: "Explored 1 file"
            )
        ])
    }

    func testAggregateRowsUseCodexListPhrasingWithoutCounts() {
        let rows = ToolTimelinePresentation.aggregateRows(for: [
            WorkItem(
                id: "list-1",
                kind: .command(text: "ls", actions: [.listFiles]),
                status: .completed
            ),
            WorkItem(
                id: "list-2",
                kind: .command(text: "find . -maxdepth 1", actions: [.listFiles]),
                status: .completed
            )
        ])

        XCTAssertEqual(rows, [
            ToolTimelineRow(
                id: "exec",
                icon: "clawix.folderStack",
                text: "Listed files"
            )
        ])
    }

    func testAggregateRowsInlineWebSearchesWithLocalSearchesLikeCodex() {
        let rows = ToolTimelinePresentation.aggregateRows(for: [
            WorkItem(
                id: "search-1",
                kind: .command(text: "rg url .", actions: [.search]),
                status: .completed
            ),
            WorkItem(
                id: "search-2",
                kind: .command(text: "find . -name '*.tsx'", actions: [.search]),
                status: .completed
            ),
            WorkItem(id: "web-1", kind: .webSearch, status: .completed),
            WorkItem(id: "web-2", kind: .webSearch, status: .completed)
        ])

        XCTAssertEqual(rows, [
            ToolTimelineRow(
                id: "exec",
                icon: "magnifyingglass",
                text: "Explored 2 searches, searched web 2 times"
            )
        ])
    }

    func testAggregateRowsUseCodexWebSearchPhrasing() {
        let rows = ToolTimelinePresentation.aggregateRows(for: [
            WorkItem(id: "web-1", kind: .webSearch, status: .completed),
            WorkItem(id: "web-2", kind: .webSearch, status: .completed),
            WorkItem(id: "web-3", kind: .webSearch, status: .completed)
        ])

        XCTAssertEqual(rows, [
            ToolTimelineRow(
                id: "webSearch",
                icon: "clawix.globe",
                text: "Searched web 3 times"
            )
        ])
    }

    func testComputerUseMcpServerGetsCanonicalRow() {
        let rows = ToolTimelinePresentation.aggregateRows(for: [
            WorkItem(
                id: "computer-1",
                kind: .mcpTool(server: "computer_use", tool: "get_app_state"),
                status: .completed
            )
        ])

        XCTAssertEqual(rows, [
            ToolTimelineRow(
                id: "mcp0",
                icon: "clawix.computerUse",
                text: L10n.usedTool("Computer Use")
            )
        ])
    }

    func testComputerUseListAppsUsesCodexActionTitle() {
        let rows = ToolTimelinePresentation.aggregateRows(for: [
            WorkItem(
                id: "computer-1",
                kind: .mcpTool(server: "computer-use", tool: "list_apps"),
                status: .completed
            )
        ])

        XCTAssertEqual(rows, [
            ToolTimelineRow(
                id: "mcp0",
                icon: "command",
                text: "List Mac apps"
            )
        ])
    }

    func testComputerUseNamespaceAliasGetsCanonicalName() {
        XCTAssertEqual(prettyMcpServer("mcp__computer_use__"), "Computer Use")
        XCTAssertTrue(isComputerUseMcpServer("computer-use@openai-bundled"))
    }

    func testComputerUsePrefixedToolsOnAnyServerBucketAsComputerUse() {
        // Tools exposed as computer_use.* on the ClawJS MCP server must still
        // render as Computer Use, collapsed into one canonical row.
        let rows = ToolTimelinePresentation.aggregateRows(for: [
            WorkItem(id: "cu-1", kind: .mcpTool(server: "clawjs-mcp", tool: "computer_use.get_app_state"), status: .completed),
            WorkItem(id: "cu-2", kind: .mcpTool(server: "clawjs-mcp", tool: "computer_use.click"), status: .completed),
            WorkItem(id: "cu-3", kind: .mcpTool(server: "computer_use", tool: "type_text"), status: .completed)
        ])

        XCTAssertEqual(rows, [
            ToolTimelineRow(
                id: "mcp0",
                icon: "clawix.computerUse",
                text: L10n.usedToolTimes("Computer Use", 3)
            )
        ])
    }

    func testIncrementalComputerUsePrefixedToolMatchesFullSnapshot() {
        let groupID = UUID()
        let first = WorkItem(id: "cu-a", kind: .mcpTool(server: "clawjs-mcp", tool: "computer_use.click"), status: .completed)
        let second = WorkItem(id: "cu-b", kind: .mcpTool(server: "clawjs-mcp", tool: "computer_use.type_text"), status: .completed)
        let seed = ToolTimelinePresentation.snapshot(groupID: groupID, items: [first])
        let updated = ToolTimelinePresentation.updatedSnapshot(
            groupID: groupID,
            previousItems: [first],
            currentSnapshot: seed,
            applying: second
        )
        XCTAssertEqual(updated.aggregateRows, ToolTimelinePresentation.aggregateRows(for: [first, second]))
        XCTAssertEqual(updated.aggregateRows.first?.icon, "clawix.computerUse")
    }

    func testComputerUseActionVerbsMatchSpecPhrasing() {
        XCTAssertEqual(computerUseActionVerb(tool: "computer_use.get_app_state", active: true), "Looking")
        XCTAssertEqual(computerUseActionVerb(tool: "computer_use.get_app_state", active: false), "Looked")
        XCTAssertEqual(computerUseActionVerb(tool: "click", active: true), "Clicking")
        XCTAssertEqual(computerUseActionVerb(tool: "computer_use.type_text", active: false), "Typed text")
        XCTAssertEqual(computerUseActionVerb(tool: "press_key", active: true), "Pressing")
    }
}
