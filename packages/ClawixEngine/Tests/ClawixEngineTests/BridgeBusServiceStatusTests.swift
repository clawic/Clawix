import XCTest
import Combine
@testable import ClawixCore
@testable import ClawixEngine

@MainActor
final class BridgeBusServiceStatusTests: XCTestCase {
    func testCurrentServiceStatusFrameUsesHostSnapshot() {
        let service = Self.serviceStatus(state: "readyFromDaemon")
        let host = ServiceStatusHost(services: [service])
        let bus = BridgeBus(host: host)

        XCTAssertEqual(
            bus.currentClawJSServiceStatusesFrame().body,
            .clawJSServiceStatusesSnapshot(services: [service])
        )
    }

    func testServiceStatusPublisherEmitsChangedServiceUpdates() {
        let initial = Self.serviceStatus(state: "starting")
        let updated = Self.serviceStatus(state: "readyFromDaemon")
        let host = ServiceStatusHost(services: [initial])
        let bus = BridgeBus(host: host)
        var emitted: [BridgeBody] = []

        bus.startObserving { frame in
            emitted.append(frame.body)
        }
        host.publish([updated])

        XCTAssertTrue(emitted.contains(.clawJSServiceStatusUpdated(service: updated)))
    }

    private static func serviceStatus(state: String) -> WireClawJSServiceSnapshot {
        WireClawJSServiceSnapshot(
            id: "database",
            state: state,
            port: 24_102,
            pid: 12_345,
            restartCount: 0,
            lastError: nil,
            updatedAtMs: 1_777_000_000_000,
            source: "daemon"
        )
    }
}

@MainActor
private final class ServiceStatusHost: EngineHost {
    private let chats = CurrentValueSubject<[BridgeChatSnapshot], Never>([])
    private let services: CurrentValueSubject<[WireClawJSServiceSnapshot], Never>

    init(services: [WireClawJSServiceSnapshot]) {
        self.services = CurrentValueSubject(services)
    }

    var bridgeChatsCurrent: [BridgeChatSnapshot] { chats.value }
    var bridgeChatsPublisher: AnyPublisher<[BridgeChatSnapshot], Never> {
        chats.eraseToAnyPublisher()
    }

    var clawJSServiceStatusesCurrent: [WireClawJSServiceSnapshot] { services.value }
    var clawJSServiceStatusesPublisher: AnyPublisher<[WireClawJSServiceSnapshot], Never> {
        services.eraseToAnyPublisher()
    }

    func publish(_ next: [WireClawJSServiceSnapshot]) {
        services.send(next)
    }

    func handleHydrateHistory(sessionId: UUID) {}
    func handleSendMessage(sessionId: UUID, text: String, attachments: [WireAttachment]) {}
}
