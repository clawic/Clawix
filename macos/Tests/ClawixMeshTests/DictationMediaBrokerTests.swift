import Foundation
import XCTest
@testable import Clawix

@MainActor
final class DictationMediaBrokerTests: XCTestCase {
    func testMuteSkipsUserMutedOutputAndDoesNotUnmute() throws {
        let defaults = try makeDefaults()
        let runner = DictationMediaRecordingRunner(nativeOutputs: ["coreaudio.output_mute_status": ["muted"]])
        let controller = MediaController(defaults: defaults, runner: runner, auditURL: temporaryAuditURL())

        controller.muteIfNeeded()
        controller.unmuteImmediately()

        XCTAssertEqual(runner.nativeCalls, [
            DictationMediaRecordingRunner.NativeCall(action: "coreaudio.output_mute_status", arguments: []),
        ])
    }

    func testMuteAndImmediateUnmuteRouteThroughNativeActionBroker() throws {
        let defaults = try makeDefaults()
        let runner = DictationMediaRecordingRunner(nativeOutputs: ["coreaudio.output_mute_status": ["unmuted"]])
        let auditURL = temporaryAuditURL()
        let controller = MediaController(defaults: defaults, runner: runner, auditURL: auditURL)

        controller.muteIfNeeded()
        controller.unmuteImmediately()

        XCTAssertEqual(runner.nativeCalls, [
            DictationMediaRecordingRunner.NativeCall(action: "coreaudio.output_mute_status", arguments: []),
            DictationMediaRecordingRunner.NativeCall(action: "coreaudio.output_mute", arguments: ["true"]),
            DictationMediaRecordingRunner.NativeCall(action: "coreaudio.output_mute", arguments: ["false"]),
        ])
        let events = try readAuditEvents(auditURL)
        XCTAssertEqual(events.map(\.action), [
            "mac.audio.mute.set",
            "mac.audio.mute.set",
        ])
    }

    func testPlaybackPausesOnlyFirstPlayingApprovedBrokerTarget() throws {
        let defaults = try makeDefaults()
        defaults.set(true, forKey: PlaybackController.enabledKey)
        let runner = DictationMediaRecordingRunner(mediaStates: [
            "Music": "paused",
            "Podcasts": "playing",
            "TV": "playing",
        ])
        let controller = PlaybackController(defaults: defaults, runner: runner, auditURL: temporaryAuditURL())

        controller.pauseIfNeeded()

        XCTAssertEqual(runner.mediaStatusApps, ["Music", "Podcasts"])
        XCTAssertEqual(runner.mediaPauseApps, ["Podcasts"])
        XCTAssertEqual(runner.mediaResumeApps, [])
    }

    func testPlaybackResumeTargetsOnlyBrokerPausedApp() throws {
        let defaults = try makeDefaults()
        defaults.set(true, forKey: PlaybackController.enabledKey)
        defaults.set(0, forKey: PlaybackController.resumeDelayKey)
        let runner = DictationMediaRecordingRunner(mediaStates: ["Music": "playing"])
        let auditURL = temporaryAuditURL()
        let controller = PlaybackController(defaults: defaults, runner: runner, auditURL: auditURL)

        controller.pauseIfNeeded()
        controller.resumeAfterDelay()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(runner.mediaPauseApps, ["Music"])
        XCTAssertEqual(runner.mediaResumeApps, ["Music"])
        let events = try readAuditEvents(auditURL)
        XCTAssertEqual(events.map(\.action), [
            "mac.media.playback.pause",
            "mac.media.playback.resume",
        ])
    }

    func testPlaybackFailureDoesNotRecordPausedSession() throws {
        let defaults = try makeDefaults()
        defaults.set(true, forKey: PlaybackController.enabledKey)
        let runner = DictationMediaRecordingRunner(
            mediaStates: ["Music": "playing"],
            failingMediaCommands: ["pause"]
        )
        let controller = PlaybackController(defaults: defaults, runner: runner, auditURL: temporaryAuditURL())

        controller.pauseIfNeeded()
        controller.resumeAfterDelay()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(runner.mediaPauseApps, ["Music"])
        XCTAssertEqual(runner.mediaResumeApps, [])
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "DictationMediaBrokerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func temporaryAuditURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("dictation-media-broker-\(UUID().uuidString)")
            .appendingPathComponent(NativeMacActionPolicy.auditFilename)
    }

    private func readAuditEvents(_ url: URL) throws -> [NativeMacActionPolicy.AuditEvent] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
        return try lines.map { try decoder.decode(NativeMacActionPolicy.AuditEvent.self, from: Data($0.utf8)) }
    }
}

final class DictationMediaRecordingRunner: NativeMacActionCommandRunning {
    struct NativeCall: Equatable {
        var action: String
        var arguments: [String]
    }

    private(set) var nativeCalls: [NativeCall] = []
    private(set) var appleScriptCalls: [String] = []
    private(set) var mediaStatusApps: [String] = []
    private(set) var mediaPauseApps: [String] = []
    private(set) var mediaResumeApps: [String] = []

    private var nativeOutputs: [String: [String]]
    private let mediaStates: [String: String]
    private let failingMediaCommands: Set<String>

    init(
        nativeOutputs: [String: [String]] = [:],
        mediaStates: [String: String] = [:],
        failingMediaCommands: Set<String> = []
    ) {
        self.nativeOutputs = nativeOutputs
        self.mediaStates = mediaStates
        self.failingMediaCommands = failingMediaCommands
    }

    func runProcess(_ executable: String, arguments: [String]) throws -> String {
        "ok"
    }

    func runAppleScript(_ source: String) throws -> String {
        appleScriptCalls.append(source)
        if source.contains("player state") {
            let app = mediaApp(in: source)
            mediaStatusApps.append(app)
            return mediaStates[app] ?? "not_running"
        }
        if source.contains("\n    pause\n") {
            let app = mediaApp(in: source)
            mediaPauseApps.append(app)
            if failingMediaCommands.contains("pause") {
                throw NSError(domain: "DictationMediaRecordingRunner", code: 1)
            }
            return "ok"
        }
        if source.contains("\n    play\n") {
            let app = mediaApp(in: source)
            mediaResumeApps.append(app)
            if failingMediaCommands.contains("resume") {
                throw NSError(domain: "DictationMediaRecordingRunner", code: 2)
            }
            return "ok"
        }
        return "ok"
    }

    func runNative(_ action: String, arguments: [String]) throws -> String {
        nativeCalls.append(NativeCall(action: action, arguments: arguments))
        var outputs = nativeOutputs[action] ?? []
        if outputs.isEmpty { return "ok" }
        let output = outputs.removeFirst()
        nativeOutputs[action] = outputs
        return output
    }

    private func mediaApp(in source: String) -> String {
        for app in ["Music", "Podcasts", "TV"] where source.contains("\"\(app)\"") {
            return app
        }
        return "unknown"
    }
}
