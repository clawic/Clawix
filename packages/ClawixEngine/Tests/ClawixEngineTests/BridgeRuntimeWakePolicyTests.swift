import XCTest
@testable import ClawixCore
@testable import ClawixEngine

@MainActor
final class BridgeRuntimeWakePolicyTests: XCTestCase {
    func testPassiveFramesDoNotWakeRuntime() {
        let passive: [BridgeBody] = [
            .pairingStart,
            .requestRateLimits,
            .requestClawJSServiceStatuses,
            .listProjects,
            .auth(
                token: "token",
                deviceName: "desktop",
                clientKind: .desktop,
                clientId: "client",
                installationId: "install",
                deviceId: "device"
            )
        ]

        for body in passive {
            XCTAssertNil(BridgeRuntimeWakePolicy.reason(for: body, clientKind: .desktop), "\(body) should stay passive")
        }
    }

    func testCompanionListSessionsDoesNotWakeRuntime() {
        XCTAssertNil(BridgeRuntimeWakePolicy.reason(for: .listSessions, clientKind: .companion))
    }

    func testDesktopListSessionsWakesRuntime() {
        XCTAssertEqual(BridgeRuntimeWakePolicy.reason(for: .listSessions, clientKind: .desktop), "listSessions")
    }

    func testRealChatFramesWakeRuntime() {
        let real: [(BridgeBody, String)] = [
            (.openSession(sessionId: UUID().uuidString, limit: nil), "openSession"),
            (.newSession(sessionId: UUID().uuidString, text: "hello", attachments: []), "newSession"),
            (.sendMessage(sessionId: UUID().uuidString, text: "hello", attachments: []), "sendMessage"),
            (.interruptTurn(sessionId: UUID().uuidString), "interruptTurn"),
            (.editPrompt(sessionId: UUID().uuidString, messageId: UUID().uuidString, text: "again"), "editPrompt"),
            (.archiveSession(sessionId: UUID().uuidString), "archiveSession"),
            (.unarchiveSession(sessionId: UUID().uuidString), "archiveSession"),
            (.renameSession(sessionId: UUID().uuidString, title: "Renamed"), "renameSession")
        ]

        for (body, reason) in real {
            XCTAssertEqual(BridgeRuntimeWakePolicy.reason(for: body, clientKind: .companion), reason)
        }
    }
}
