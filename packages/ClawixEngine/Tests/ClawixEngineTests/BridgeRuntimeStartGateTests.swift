import XCTest
@testable import ClawixEngine

@MainActor
final class BridgeRuntimeStartGateTests: XCTestCase {
    func testConcurrentStartsRunOnce() async throws {
        let gate = BridgeRuntimeStartGate()
        var starts = 0

        async let first: Void = gate.ensureStarted(reason: "sendMessage") { _ in
            starts += 1
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        async let second: Void = gate.ensureStarted(reason: "openSession") { _ in
            starts += 1
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        _ = try await (first, second)
        try await gate.ensureStarted(reason: "renameSession") { _ in
            starts += 1
        }

        XCTAssertEqual(starts, 1)
    }

    func testFailureAllowsRetryAndReportsErrorState() async {
        enum TestError: Error { case boom }

        let gate = BridgeRuntimeStartGate()
        var starts = 0

        do {
            try await gate.ensureStarted(reason: "sendMessage") { _ in
                starts += 1
                throw TestError.boom
            }
            XCTFail("expected start failure")
        } catch {
            XCTAssertEqual(starts, 1)
        }

        do {
            try await gate.ensureStarted(reason: "sendMessage") { _ in
                starts += 1
            }
        } catch {
            XCTFail("retry should succeed: \(error)")
        }

        XCTAssertEqual(starts, 2)
    }
}
