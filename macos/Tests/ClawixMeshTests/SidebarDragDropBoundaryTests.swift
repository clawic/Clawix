import XCTest
@testable import Clawix

final class SidebarDragDropBoundaryTests: XCTestCase {
    func testToolReorderableListLivesInDedicatedSidebarToolFile() throws {
        let dragDropSource = try readSource("Sidebar/SidebarView+DragDrop.swift")
        let toolSource = try readSource("Sidebar/SidebarToolsReorderableList.swift")

        XCTAssertTrue(toolSource.contains("struct ToolsReorderableList: View"))
        XCTAssertTrue(toolSource.contains("struct ToolRowDropDelegate: DropDelegate"))
        XCTAssertTrue(toolSource.contains("struct ToolDragChipView: View"))
        XCTAssertFalse(dragDropSource.contains("struct ToolsReorderableList: View"))
        XCTAssertFalse(dragDropSource.contains("struct ToolDragChipView: View"))
    }

    private func readSource(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("Clawix")
            .appendingPathComponent(relativePath)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
