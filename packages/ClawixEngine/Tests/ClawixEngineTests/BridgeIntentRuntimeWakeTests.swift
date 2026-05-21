import XCTest
#if canImport(Combine)
import Combine
#else
import OpenCombine
#endif
@testable import ClawixCore
@testable import ClawixEngine

@MainActor
final class BridgeIntentRuntimeWakeTests: XCTestCase {
    func testDesktopListSessionsStartsRuntimeBeforeReplying() async {
        let host = IntentWakeHost()
        let bus = BridgeBus(host: host)
        var sent: [BridgeFrame] = []

        await BridgeIntent.dispatch(
            body: .listSessions,
            host: host,
            bus: bus,
            clientKind: .desktop,
            send: { sent.append($0) }
        )

        XCTAssertEqual(host.runtimeStartReasons, ["listSessions"])
        XCTAssertEqual(sent.count, 1)
        guard case .sessionsSnapshot(let sessions) = sent.first?.body else {
            XCTFail("expected sessionsSnapshot")
            return
        }
        XCTAssertEqual(sessions, [host.session])
    }

    func testCompanionListSessionsRepliesWithoutStartingRuntime() async {
        let host = IntentWakeHost()
        let bus = BridgeBus(host: host)
        var sent: [BridgeFrame] = []

        await BridgeIntent.dispatch(
            body: .listSessions,
            host: host,
            bus: bus,
            clientKind: .companion,
            send: { sent.append($0) }
        )

        XCTAssertTrue(host.runtimeStartReasons.isEmpty)
        XCTAssertEqual(sent.count, 1)
        guard case .sessionsSnapshot(let sessions) = sent.first?.body else {
            XCTFail("expected sessionsSnapshot")
            return
        }
        XCTAssertEqual(sessions, [host.session])
    }
}

@MainActor
private final class IntentWakeHost: EngineHost {
    let session = WireSession(
        id: UUID().uuidString,
        title: "Cached session",
        createdAt: Date(timeIntervalSince1970: 0)
    )
    var runtimeStartReasons: [String] = []

    var bridgeChatsCurrent: [BridgeChatSnapshot] {
        [BridgeChatSnapshot(chat: session, messages: [])]
    }

    var bridgeChatsPublisher: AnyPublisher<[BridgeChatSnapshot], Never> {
        Just(bridgeChatsCurrent).eraseToAnyPublisher()
    }

    func ensureRuntimeStarted(reason: String) async throws {
        runtimeStartReasons.append(reason)
    }

    func handleHydrateHistory(sessionId: UUID) {}

    func handleSendMessage(sessionId: UUID, text: String, attachments: [WireAttachment]) {}
}
