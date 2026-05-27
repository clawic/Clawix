import XCTest
import ClawixCore
@testable import Clawix

final class UserMessageAttachmentRenderingTests: XCTestCase {
    override func tearDown() {
        RolloutAttachmentRegistry.shared.resetForTests()
        RolloutCursorRegistry.shared.resetForTests()
        super.tearDown()
    }

    func testFilesMentionedWrapperRendersImagesAndCleanRequestText() {
        let first = "/tmp/screenshot-one.png"
        let second = "/tmp/screenshot-two.png"
        let raw = """
        # Files mentioned by the user:

        ## screenshot-one.png: \(first)

        ## screenshot-two.png: \(second)

        ## My request for Codex:
        Disable the workflow.

        Keep the repo quiet.
        """

        let parsed = UserBubbleContent.parse(raw)

        XCTAssertEqual(parsed.images.count, 2)
        XCTAssertEqual(parsed.files.count, 0)
        XCTAssertEqual(parsed.text, "Disable the workflow.\n\nKeep the repo quiet.")
        XCTAssertFalse(parsed.text.contains("Files mentioned by the user"))
        XCTAssertFalse(parsed.text.contains("My request for Codex"))
    }

    func testRolloutReaderUsesLocalImageRefsAndTaskDuration() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let imageURL = tmp.appendingPathComponent("mention.png")
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=")!
        try png.write(to: imageURL)

        let rollout = tmp.appendingPathComponent("rollout.jsonl")
        let userText = """
        # Files mentioned by the user:

        ## mention.png: \(imageURL.path)

        ## My request for Codex:
        Disable the workflow.
        """
        let lines = [
            #"{"timestamp":"2026-05-09T10:52:25.716Z","type":"session_meta","payload":{"id":"session-fixture","cwd":"/tmp"}}"#,
            jsonLine(timestamp: "2026-05-09T10:52:25.723Z", type: "event_msg", payload: [
                "type": "user_message",
                "message": userText,
                "local_images": [imageURL.path]
            ]),
            jsonLine(timestamp: "2026-05-09T10:52:43.925Z", type: "event_msg", payload: [
                "type": "agent_message",
                "message": "Working on it.",
                "phase": "commentary"
            ]),
            jsonLine(timestamp: "2026-05-09T10:54:33.629Z", type: "event_msg", payload: [
                "type": "agent_message",
                "message": "Done.",
                "phase": "final_answer"
            ]),
            jsonLine(timestamp: "2026-05-09T10:54:33.659Z", type: "event_msg", payload: [
                "type": "task_complete",
                "duration_ms": 129_980
            ])
        ]
        try (lines.joined(separator: "\n") + "\n").write(to: rollout, atomically: true, encoding: .utf8)

        let result = RolloutReader.readTailWithStatus(path: rollout, now: ISO8601DateFormatter().date(from: "2026-05-09T10:54:34Z")!)

        XCTAssertEqual(result.entries.count, 2)
        XCTAssertEqual(result.entries[0].attachments.count, 1)
        XCTAssertEqual(result.entries[0].attachments[0].filename, "mention.png")
        XCTAssertNil(result.entries[0].attachments[0].dataBase64)
        XCTAssertEqual(result.entries[0].attachments[0].byteSize, png.count)
        XCTAssertEqual(
            RolloutAttachmentRegistry.shared.bytes(for: result.entries[0].attachments[0].id)?.data,
            png
        )
        XCTAssertEqual(result.entries[1].workSummary?.elapsedSeconds(asOf: Date.distantFuture), 129)
    }

    func testRolloutReaderWindowReadsOlderMessagesBeforeCursor() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let rollout = tmp.appendingPathComponent("rollout.jsonl")
        var lines = [
            #"{"timestamp":"2026-05-09T10:00:00.000Z","type":"session_meta","payload":{"id":"session-fixture","cwd":"/tmp"}}"#
        ]
        for idx in 0..<8 {
            lines.append(jsonLine(timestamp: "2026-05-09T10:00:0\(idx).000Z", type: "event_msg", payload: [
                "type": "user_message",
                "message": "prompt \(idx)"
            ]))
        }
        try (lines.joined(separator: "\n") + "\n").write(to: rollout, atomically: true, encoding: .utf8)

        let tail = RolloutReader.readTailWithStatus(path: rollout, maxBytes: 260)
        XCTAssertTrue(tail.hasMoreBefore)
        XCTAssertEqual(tail.readMode, "tail")
        XCTAssertFalse(tail.readEntireFile)
        XCTAssertEqual(tail.requestedMaxBytes, 260)
        XCTAssertGreaterThan(tail.totalFileBytes, UInt64(tail.readBytes))
        XCTAssertGreaterThan(tail.parsedRecordCount, 0)
        let cursor = try XCTUnwrap(tail.entries.first?.id.uuidString)

        let page = RolloutReader.readWindowBefore(path: rollout, beforeMessageId: cursor, limit: 2, maxBytes: 512)

        XCTAssertEqual(page.entries.map(\.text), ["prompt 4", "prompt 5"])
        XCTAssertTrue(page.hasMoreBefore)
        XCTAssertEqual(page.readMode, "window-before")
        XCTAssertEqual(page.requestedMaxBytes, 512)
        XCTAssertGreaterThan(page.parsedRecordCount, 0)
    }

    func testRolloutReaderDoesNotExpandSparseTailToWholeFile() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let rollout = tmp.appendingPathComponent("rollout.jsonl")
        var lines = [
            #"{"timestamp":"2026-05-09T10:00:00.000Z","type":"session_meta","payload":{"id":"session-fixture","cwd":"/tmp"}}"#
        ]
        for idx in 0..<3_000 {
            lines.append(jsonLine(timestamp: "2026-05-09T10:00:01.000Z", type: "response_item", payload: [
                "type": "reasoning",
                "text": "background event \(idx) \(String(repeating: "x", count: 80))"
            ]))
        }
        lines.append(jsonLine(timestamp: "2026-05-09T10:00:02.000Z", type: "event_msg", payload: [
            "type": "user_message",
            "message": "latest prompt"
        ]))
        try (lines.joined(separator: "\n") + "\n").write(to: rollout, atomically: true, encoding: .utf8)

        let result = RolloutReader.readTailWithStatus(
            path: rollout,
            limit: bridgeInitialPageLimit,
            maxBytes: 128 * 1024
        )

        XCTAssertFalse(result.entries.isEmpty)
        XCTAssertTrue(result.hasMoreBefore)
        XCTAssertFalse(result.readEntireFile)
        XCTAssertLessThan(UInt64(result.readBytes), result.totalFileBytes)
    }

    func testRolloutReaderReadsWholeShortRolloutBeforeTailWindow() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let rollout = tmp.appendingPathComponent("rollout.jsonl")
        let largeOutput = String(repeating: "static audit output ", count: 18_000)
        let lines = [
            #"{"timestamp":"2026-05-26T20:55:00.000Z","type":"session_meta","payload":{"id":"session-fixture","cwd":"/tmp"}}"#,
            jsonLine(timestamp: "2026-05-26T20:55:01.000Z", type: "event_msg", payload: [
                "type": "user_message",
                "message": "Audit this project."
            ]),
            jsonLine(timestamp: "2026-05-26T20:55:02.000Z", type: "response_item", payload: [
                "type": "function_call_output",
                "call_id": "call-large",
                "output": largeOutput
            ]),
            jsonLine(timestamp: "2026-05-26T20:55:03.000Z", type: "event_msg", payload: [
                "type": "agent_message",
                "message": "Audit complete.",
                "phase": "final_answer"
            ])
        ]
        try (lines.joined(separator: "\n") + "\n").write(to: rollout, atomically: true, encoding: .utf8)

        XCTAssertGreaterThan(try Data(contentsOf: rollout).count, RolloutReader.initialTailBytes)

        let result = RolloutReader.readTailWithStatus(path: rollout)

        XCTAssertEqual(result.entries.map(\.text), ["Audit this project.", "Audit complete."])
        XCTAssertFalse(result.hasMoreBefore)
        XCTAssertTrue(result.readEntireFile)
    }

    func testRolloutChatMessagesAreSettledForHistoricalRendering() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let rollout = tmp.appendingPathComponent("rollout.jsonl")
        let lines = [
            #"{"timestamp":"2026-05-09T10:00:00.000Z","type":"session_meta","payload":{"id":"session-fixture","cwd":"/tmp"}}"#,
            jsonLine(timestamp: "2026-05-09T10:00:01.000Z", type: "event_msg", payload: [
                "type": "agent_message",
                "message": "Done.",
                "phase": "final_answer"
            ]),
            jsonLine(timestamp: "2026-05-09T10:00:02.000Z", type: "event_msg", payload: [
                "type": "task_complete",
                "duration_ms": 1_000
            ])
        ]
        try (lines.joined(separator: "\n") + "\n").write(to: rollout, atomically: true, encoding: .utf8)

        let result = RolloutReader.readTailWithStatus(path: rollout)
        let messages = rolloutChatMessages(from: result)
        let assistant = try XCTUnwrap(messages.first)

        XCTAssertEqual(assistant.role, .assistant)
        XCTAssertTrue(assistant.streamingFinished)
        XCTAssertTrue(assistant.streamCheckpoints.isEmpty)
        XCTAssertTrue(assistant.reasoningCheckpoints.isEmpty)
        XCTAssertTrue(assistant.streamPendingTail.isEmpty)
        XCTAssertTrue(assistant.reasoningPendingTails.isEmpty)
    }

    private func jsonLine(timestamp: String, type: String, payload: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [
            "timestamp": timestamp,
            "type": type,
            "payload": payload
        ], options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }
}
