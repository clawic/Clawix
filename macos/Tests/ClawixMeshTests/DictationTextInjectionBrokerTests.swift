import Foundation
import XCTest
@testable import Clawix

@MainActor
final class DictationTextInjectionBrokerTests: XCTestCase {
    func testRoutesDictationTextThroughNativeActionBroker() throws {
        let runner = DictationTextInjectionRecordingRunner()

        try TextInjector.inject(
            text: "brokered dictation payload",
            restorePrevious: true,
            autoSendKey: .shiftEnter,
            restoreAfter: 0.25,
            addSpaceBefore: true,
            runner: runner,
            auditURL: temporaryAuditURL(),
            permissionStatus: .granted
        )

        XCTAssertEqual(runner.nativeCalls, [
            DictationTextInjectionRecordingRunner.NativeCall(
                action: "text.inject",
                arguments: [
                    "brokered dictation payload",
                    "true",
                    "shift_enter",
                    "0.25",
                    "true",
                ]
            ),
        ])
        XCTAssertTrue(runner.processCalls.isEmpty)
        XCTAssertTrue(runner.appleScriptCalls.isEmpty)
    }

    func testEmptyTranscriptIsBlockedBeforeBrokerExecution() {
        let runner = DictationTextInjectionRecordingRunner()

        XCTAssertThrowsError(
            try TextInjector.inject(
                text: "  \n\t",
                runner: runner,
                permissionStatus: .granted
            )
        ) { error in
            XCTAssertEqual(error.localizedDescription, "Empty transcript")
        }
        XCTAssertTrue(runner.nativeCalls.isEmpty)
        XCTAssertTrue(runner.processCalls.isEmpty)
        XCTAssertTrue(runner.appleScriptCalls.isEmpty)
    }

    func testMissingAccessibilityIsBlockedBeforeBrokerExecution() {
        let runner = DictationTextInjectionRecordingRunner()

        XCTAssertThrowsError(
            try TextInjector.inject(
                text: "brokered dictation payload",
                runner: runner,
                permissionStatus: .denied
            )
        ) { error in
            XCTAssertEqual(error.localizedDescription, "Allow Clawix in Accessibility to paste transcripts")
        }
        XCTAssertTrue(runner.nativeCalls.isEmpty)
        XCTAssertTrue(runner.processCalls.isEmpty)
        XCTAssertTrue(runner.appleScriptCalls.isEmpty)
    }

    func testBrokerFailureDoesNotEchoTranscriptPayload() {
        let runner = DictationTextInjectionRecordingRunner(failingNativeActions: ["text.inject"])

        XCTAssertThrowsError(
            try TextInjector.inject(
                text: "secret dictated payload",
                runner: runner,
                auditURL: temporaryAuditURL(),
                permissionStatus: .granted
            )
        ) { error in
            XCTAssertFalse(error.localizedDescription.contains("secret dictated payload"))
        }
        XCTAssertEqual(runner.nativeCalls.map(\.action), ["text.inject"])
    }

    private func temporaryAuditURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("dictation-text-injection-broker-\(UUID().uuidString)")
            .appendingPathComponent(NativeMacActionPolicy.auditFilename)
    }
}

final class DictationTextInjectionRecordingRunner: NativeMacActionCommandRunning {
    struct NativeCall: Equatable {
        var action: String
        var arguments: [String]
    }

    private(set) var nativeCalls: [NativeCall] = []
    private(set) var processCalls: [(String, [String])] = []
    private(set) var appleScriptCalls: [String] = []
    private let failingNativeActions: Set<String>

    init(failingNativeActions: Set<String> = []) {
        self.failingNativeActions = failingNativeActions
    }

    func runProcess(_ executable: String, arguments: [String]) throws -> String {
        processCalls.append((executable, arguments))
        return "ok"
    }

    func runAppleScript(_ source: String) throws -> String {
        appleScriptCalls.append(source)
        return "ok"
    }

    func runNative(_ action: String, arguments: [String]) throws -> String {
        nativeCalls.append(NativeCall(action: action, arguments: arguments))
        if failingNativeActions.contains(action) {
            throw NSError(domain: "DictationTextInjectionRecordingRunner", code: 1)
        }
        return "ok"
    }
}
