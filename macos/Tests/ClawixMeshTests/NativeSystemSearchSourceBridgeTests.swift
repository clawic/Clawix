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

    func testRebuildShortcutsIndexFeedsSignedHostSnapshotToClawSearch() throws {
        let nativeRunner = ShortcutListRunner(output: "Daily Plan\nInbox Review\n")
        let clawRunner = RecordingClawSearchRunner(output: """
        {"ok":true,"data":{"rebuilt":true,"reindexed":2,"indexedBySource":{"native.system":2},"pendingSources":[]}}
        """)

        let result = try NativeSystemSearchSourceBridge.rebuildShortcutsIndex(
            actorId: "clawix.test",
            dataDir: "/tmp/claw-search-data",
            nativeRunner: nativeRunner,
            clawRunner: NativeSystemSearchSourceBridge.ClawSearchCommandRunner(run: clawRunner.run)
        )

        XCTAssertEqual(result.ok, true)
        XCTAssertEqual(result.data.reindexed, 2)
        XCTAssertEqual(result.data.indexedBySource["native.system"], 2)
        XCTAssertEqual(result.data.pendingSources, [])
        XCTAssertEqual(clawRunner.calls.count, 1)
        let args = try XCTUnwrap(clawRunner.calls.first)
        XCTAssertEqual(Array(args.prefix(6)), [
            "search", "rebuild",
            "--source", "native.system",
            "--profile", "full",
        ])
        XCTAssertTrue(args.contains("--native-system-snapshot-json"))
        XCTAssertTrue(args.contains("--actor"))
        XCTAssertTrue(args.contains("clawix.test"))
        XCTAssertTrue(args.contains("--surface"))
        XCTAssertTrue(args.contains("clawix.native_system_search"))
        XCTAssertTrue(args.contains("--data-dir"))
        XCTAssertTrue(args.contains("/tmp/claw-search-data"))

        let snapshotIndex = try XCTUnwrap(args.firstIndex(of: "--native-system-snapshot-json"))
        let snapshotJSON = args[snapshotIndex + 1]
        let snapshotData = try XCTUnwrap(snapshotJSON.data(using: .utf8))
        let snapshot = try JSONDecoder().decode(NativeSystemSearchSourceSnapshot.self, from: snapshotData)
        XCTAssertEqual(snapshot.source, "native.system")
        XCTAssertEqual(snapshot.state, "enabled")
        XCTAssertEqual(snapshot.documents.map(\.title), ["Daily Plan", "Inbox Review"])
        XCTAssertEqual(snapshot.documents.first?.actions.first?.hostBroker.capabilityId, "mac.shortcut.run")
    }

    func testRebuildShortcutsIndexPropagatesExternalPendingSnapshot() throws {
        let nativeRunner = ShortcutListRunner(output: "", error: NativeSystemSearchSourceBridgeTestError.failed)
        let clawRunner = RecordingClawSearchRunner(output: """
        {"ok":true,"data":{"rebuilt":true,"reindexed":0,"indexedBySource":{"native.system":0},"pendingSources":[]}}
        """)

        let result = try NativeSystemSearchSourceBridge.rebuildShortcutsIndex(
            nativeRunner: nativeRunner,
            clawRunner: NativeSystemSearchSourceBridge.ClawSearchCommandRunner(run: clawRunner.run)
        )

        XCTAssertEqual(result.data.reindexed, 0)
        let args = try XCTUnwrap(clawRunner.calls.first)
        let snapshotIndex = try XCTUnwrap(args.firstIndex(of: "--native-system-snapshot-json"))
        let snapshotJSON = args[snapshotIndex + 1]
        let snapshotData = try XCTUnwrap(snapshotJSON.data(using: .utf8))
        let snapshot = try JSONDecoder().decode(NativeSystemSearchSourceSnapshot.self, from: snapshotData)
        XCTAssertEqual(snapshot.state, "external_pending")
        XCTAssertEqual(snapshot.documents, [])
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

private final class RecordingClawSearchRunner {
    private let output: String
    private(set) var calls: [[String]] = []

    init(output: String) {
        self.output = output
    }

    func run(_ arguments: [String]) throws -> Data {
        calls.append(arguments)
        return Data(output.utf8)
    }
}
