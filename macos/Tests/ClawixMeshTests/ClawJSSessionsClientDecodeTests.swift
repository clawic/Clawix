import Foundation
import XCTest
@testable import Clawix

final class ClawJSSessionsClientDecodeTests: XCTestCase {
    func testSessionsDecodeRunsOffMainThread() async throws {
        SessionsDecodeThreadProbe.reset()

        _ = try await ClawJSSessionsClient.decodeResponse(
            SessionsDecodeThreadProbe.self,
            from: Data(#"{"value":"ok"}"#.utf8)
        )

        XCTAssertEqual(SessionsDecodeThreadProbe.decodedValue(), "ok")
        XCTAssertEqual(SessionsDecodeThreadProbe.decodedOnMainThread(), false)
    }
}

private struct SessionsDecodeThreadProbe: Decodable, Sendable {
    let value: String

    private enum CodingKeys: String, CodingKey {
        case value
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var lastDecodedOnMainThread: Bool?
    nonisolated(unsafe) private static var lastDecodedValue: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decode(String.self, forKey: .value)
        Self.lock.lock()
        Self.lastDecodedOnMainThread = Thread.isMainThread
        Self.lastDecodedValue = value
        Self.lock.unlock()
    }

    static func reset() {
        lock.lock()
        lastDecodedOnMainThread = nil
        lastDecodedValue = nil
        lock.unlock()
    }

    static func decodedOnMainThread() -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        return lastDecodedOnMainThread
    }

    static func decodedValue() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return lastDecodedValue
    }
}
