import XCTest
@testable import Clawix

final class ClawixIPCDecodeTests: XCTestCase {
    func testKnownNotificationDecodesTypedPayload() async throws {
        let decoder = ClawixFrameDecoder()
        let data = Data("""
        {
          "jsonrpc": "2.0",
          "method": "item/agentMessage/delta",
          "params": {
            "delta": "hello",
            "itemId": "item-1",
            "threadId": "thread-1",
            "turnId": "turn-1"
          }
        }
        """.utf8)

        let header = try await decoder.decodeHeader(data)
        XCTAssertEqual(header.method, ClawixMethod.nAgentMsgDelta)

        let notification = try await decoder.decodeNotification(method: ClawixMethod.nAgentMsgDelta, data: data)
        guard case let .agentMessageDelta(payload) = notification else {
            return XCTFail("Expected agentMessageDelta")
        }
        XCTAssertEqual(payload.delta, "hello")
        XCTAssertEqual(payload.itemId, "item-1")
        XCTAssertEqual(payload.threadId, "thread-1")
        XCTAssertEqual(payload.turnId, "turn-1")
    }

    func testTypedResponseDecodesResultDirectly() async throws {
        let decoder = ClawixFrameDecoder()
        let data = Data("""
        {
          "jsonrpc": "2.0",
          "id": 3,
          "result": {
            "turn": { "id": "turn-typed" }
          }
        }
        """.utf8)

        let result = try await decoder.decodeResponse(data, expecting: TurnStartResult.self)
        XCTAssertEqual(result.turn.id, "turn-typed")
    }

    func testIgnoredResponseAcceptsNullResult() async throws {
        let decoder = ClawixFrameDecoder()
        let data = Data("""
        { "jsonrpc": "2.0", "id": 4, "result": null }
        """.utf8)

        _ = try await decoder.decodeResponse(data, expecting: ClawixIgnoredResponse.self)
    }

    func testUnknownNotificationDoesNotDecodePayloadTree() async throws {
        let decoder = ClawixFrameDecoder()
        let data = Data("""
        {
          "jsonrpc": "2.0",
          "method": "unknown/event",
          "params": {
            "large": ["payload", "that", "should", "be", "ignored"]
          }
        }
        """.utf8)

        let header = try await decoder.decodeHeader(data)
        XCTAssertEqual(header.method, "unknown/event")

        let notification = try await decoder.decodeNotification(method: "unknown/event", data: data)
        guard case let .unknown(method) = notification else {
            return XCTFail("Expected unknown notification")
        }
        XCTAssertEqual(method, "unknown/event")
    }

    func testEventCoalescerEmitsCompatibleDeltasImmediately() {
        var coalescer = ClawixServerEventCoalescer()

        let first = coalescer.ingest(.notification(.agentMessageDelta(Self.agentDelta("hel"))))
        let second = coalescer.ingest(.notification(.agentMessageDelta(Self.agentDelta("lo"))))

        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(Self.agentDeltaText(first[0]), "hel")
        XCTAssertEqual(Self.agentDeltaText(second[0]), "lo")
        XCTAssertTrue(coalescer.flush().isEmpty)
    }

    func testEventCoalescerDoesNotDelayDeltaUntilNonDeltaEvent() {
        var coalescer = ClawixServerEventCoalescer()
        let delta = coalescer.ingest(.notification(.agentMessageDelta(Self.agentDelta("hello"))))
        XCTAssertEqual(delta.count, 1)
        XCTAssertEqual(Self.agentDeltaText(delta[0]), "hello")

        let emitted = coalescer.ingest(.notification(.turnCompleted(TurnEnvelope(
            threadId: "thread-1",
            turn: TurnPayload(id: "turn-1", status: "completed", error: nil)
        ))))

        XCTAssertEqual(emitted.count, 1)
        guard case .notification(.turnCompleted) = emitted[0] else {
            return XCTFail("Expected turnCompleted")
        }
    }

    func testEventCoalescerEmitsDifferentItemsImmediately() {
        var coalescer = ClawixServerEventCoalescer()
        let first = coalescer.ingest(.notification(.agentMessageDelta(Self.agentDelta("first", itemId: "item-1"))))
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(Self.agentDeltaText(first[0]), "first")

        let emitted = coalescer.ingest(.notification(.agentMessageDelta(Self.agentDelta("second", itemId: "item-2"))))
        XCTAssertEqual(emitted.count, 1)
        XCTAssertEqual(Self.agentDeltaText(emitted[0]), "second")
        XCTAssertTrue(coalescer.flush().isEmpty)
    }

    func testEventCoalescerEmitsDifferentDeltaTypesImmediately() {
        var coalescer = ClawixServerEventCoalescer()
        let answer = coalescer.ingest(.notification(.agentMessageDelta(Self.agentDelta("answer"))))
        XCTAssertEqual(answer.count, 1)
        XCTAssertEqual(Self.agentDeltaText(answer[0]), "answer")

        let emitted = coalescer.ingest(.notification(.reasoningTextDelta(Self.reasoningDelta("thinking"))))
        XCTAssertEqual(emitted.count, 1)
        XCTAssertEqual(Self.reasoningDeltaText(emitted[0]), "thinking")
        XCTAssertTrue(coalescer.flush().isEmpty)
    }

    func testEventCoalescerCapsIndividualDeltaBytes() {
        var coalescer = ClawixServerEventCoalescer(maxDeltaBytes: 5)
        let emitted = coalescer.ingest(.notification(.agentMessageDelta(Self.agentDelta("abcdefghijkl"))))
        let tail = coalescer.flush()
        let chunks = (emitted + tail).compactMap(Self.agentDeltaText)

        XCTAssertEqual(chunks.joined(), "abcdefghijkl")
        XCTAssertFalse(chunks.isEmpty)
        XCTAssertTrue(chunks.allSatisfy { $0.utf8.count <= 5 })
    }

    func testCompleteOversizeFrameFailsSafely() {
        var framer = ClawixStdoutFramer()
        let frame = Data(repeating: 0x7b, count: ClawixFrameLimits.maxBytes + 1) + Data([0x0a])

        XCTAssertThrowsError(try framer.append(frame)) { error in
            guard case let ClawixClientError.frameTooLarge(bytes, maxBytes) = error else {
                return XCTFail("Expected frameTooLarge")
            }
            XCTAssertEqual(bytes, ClawixFrameLimits.maxBytes + 1)
            XCTAssertEqual(maxBytes, ClawixFrameLimits.maxBytes)
        }
    }

    func testUnterminatedOversizeFrameFailsSafelyAndClearsBuffer() {
        var framer = ClawixStdoutFramer()
        let frame = Data(repeating: 0x7b, count: ClawixFrameLimits.maxBytes + 1)

        XCTAssertThrowsError(try framer.append(frame)) { error in
            guard case let ClawixClientError.frameTooLarge(bytes, maxBytes) = error else {
                return XCTFail("Expected frameTooLarge")
            }
            XCTAssertEqual(bytes, ClawixFrameLimits.maxBytes + 1)
            XCTAssertEqual(maxBytes, ClawixFrameLimits.maxBytes)
        }
        XCTAssertNoThrow(try framer.append(Data("{\"method\":\"ok\"}\n".utf8)))
    }

    private static func agentDelta(
        _ delta: String,
        itemId: String = "item-1",
        threadId: String = "thread-1",
        turnId: String = "turn-1"
    ) -> AgentMessageDelta {
        AgentMessageDelta(
            delta: delta,
            itemId: itemId,
            threadId: threadId,
            turnId: turnId
        )
    }

    private static func reasoningDelta(
        _ delta: String,
        itemId: String = "item-1",
        threadId: String = "thread-1",
        turnId: String = "turn-1"
    ) -> ReasoningTextDelta {
        ReasoningTextDelta(
            delta: delta,
            itemId: itemId,
            threadId: threadId,
            turnId: turnId
        )
    }

    private static func agentDeltaText(_ event: ClawixServerEvent) -> String? {
        guard case let .notification(.agentMessageDelta(payload)) = event else {
            return nil
        }
        return payload.delta
    }

    private static func reasoningDeltaText(_ event: ClawixServerEvent) -> String? {
        guard case let .notification(.reasoningTextDelta(payload)) = event else {
            return nil
        }
        return payload.delta
    }
}
