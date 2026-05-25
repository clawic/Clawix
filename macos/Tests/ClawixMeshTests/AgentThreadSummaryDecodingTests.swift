import XCTest
@testable import Clawix

final class AgentThreadSummaryDecodingTests: XCTestCase {
    func testDecodesCodexTitleFieldAsName() throws {
        let data = Data("""
        {
          "id": "thread-1",
          "cwd": "/tmp/project",
          "title": "Codex generated title",
          "preview": "First user message",
          "path": "/tmp/rollout.jsonl",
          "createdAt": 1710000000,
          "updatedAt": 1710000100,
          "archived": false
        }
        """.utf8)

        let thread = try JSONDecoder().decode(AgentThreadSummary.self, from: data)

        XCTAssertEqual(thread.name, "Codex generated title")
        XCTAssertEqual(thread.preview, "First user message")
    }

    func testNameWinsOverTitleField() throws {
        let data = Data("""
        {
          "id": "thread-1",
          "name": "Manual name",
          "title": "Codex generated title",
          "preview": "First user message",
          "createdAt": 1710000000,
          "updatedAt": 1710000100
        }
        """.utf8)

        let thread = try JSONDecoder().decode(AgentThreadSummary.self, from: data)

        XCTAssertEqual(thread.name, "Manual name")
    }

    func testLoadsCodexSessionIndexAsRecentThreads() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawix-session-index-\(UUID().uuidString).jsonl")
        try """
        {"id":"older","thread_name":"Older thread","updated_at":"2026-05-23T10:00:00.000000Z"}
        {"id":"newer","thread_name":"Newer thread","updated_at":"2026-05-23T11:00:00.000000Z","cwd":"/tmp/project"}
        {"id":"older","thread_name":"Older thread renamed","updated_at":"2026-05-23T12:00:00.000000Z"}
        {"id":"","thread_name":"Invalid","updated_at":"2026-05-23T12:00:00.000000Z"}
        """.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let threads = AgentThreadStore.codexSessionIndexThreads(
            indexURL: tmp,
            limit: 2,
            includeThreadIds: ["newer"]
        )

        XCTAssertEqual(threads.map(\.id), ["older", "newer"])
        XCTAssertEqual(threads.first?.name, "Older thread renamed")
        XCTAssertEqual(threads.last?.cwd, "/tmp/project")
        XCTAssertEqual(threads.first?.archived, false)
    }

    func testLoadsCodexPinnedThreadIdsFromGlobalState() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawix-global-state-\(UUID().uuidString).json")
        try """
        {
          "pinned-thread-ids": ["pin-1", "pin-2", "pin-1", ""],
          "project-order": ["project-1"]
        }
        """.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let ids = AgentThreadStore.codexPinnedThreadIds(globalStateURL: tmp)

        XCTAssertEqual(ids, ["pin-1", "pin-2"])
    }
}
