import ClawHostKit
import XCTest
@testable import Clawix

@MainActor
final class NativeSystemSearchSourceBridgeTests: XCTestCase {
    func testShortcutsSnapshotUsesMacControlBrokerAndEmitsNativeSystemDocuments() {
        let runner = ShortcutListRunner(output: "Daily Plan\nInbox Review\n")
        let snapshot = NativeSystemSearchSourceBridge.shortcutsSnapshot(runner: runner)

        XCTAssertEqual(snapshot.source, "native.system")
        XCTAssertEqual(snapshot.domain, "native")
        XCTAssertEqual(snapshot.state, "enabled")
        XCTAssertEqual(snapshot.documents.map(\.id), [
            "native.system:shortcut:daily-plan",
            "native.system:shortcut:inbox-review",
        ])
        XCTAssertEqual(snapshot.documents.first?.source, "native.system")
        XCTAssertEqual(snapshot.documents.first?.domain, "native")
        XCTAssertEqual(snapshot.documents.first?.type, "shortcut")
        XCTAssertEqual(snapshot.documents.first?.actions.first?.hostBroker.system, "mac-control")
        XCTAssertEqual(snapshot.documents.first?.actions.first?.hostBroker.capabilityId, "mac.shortcut.run")
        XCTAssertEqual(snapshot.documents.first?.actions.first?.hostBroker.arguments["name"], "Daily Plan")
        XCTAssertEqual(runner.processCalls, [
            ShortcutListRunner.ProcessCall(executable: "/usr/bin/shortcuts", arguments: ["list"]),
        ])
    }

    func testShortcutsSnapshotFailsClosedWhenBrokerCannotReadShortcuts() {
        let runner = ShortcutListRunner(output: "", error: NativeSystemSearchSourceBridgeTestError.failed)
        let snapshot = NativeSystemSearchSourceBridge.shortcutsSnapshot(runner: runner)

        XCTAssertEqual(snapshot.state, "external_pending")
        XCTAssertTrue(snapshot.documents.isEmpty)
    }
}

private enum NativeSystemSearchSourceBridgeTestError: Error {
    case failed
}

private final class ShortcutListRunner: NativeMacActionCommandRunning {
    struct ProcessCall: Equatable {
        let executable: String
        let arguments: [String]
    }

    private let output: String
    private let error: Error?
    private(set) var processCalls: [ProcessCall] = []

    init(output: String, error: Error? = nil) {
        self.output = output
        self.error = error
    }

    func runProcess(_ executable: String, arguments: [String]) throws -> String {
        processCalls.append(ProcessCall(executable: executable, arguments: arguments))
        if let error {
            throw error
        }
        return output
    }

    func runAppleScript(_ source: String) throws -> String {
        ""
    }

    func runNative(_ action: String, arguments: [String]) throws -> String {
        ""
    }
}
