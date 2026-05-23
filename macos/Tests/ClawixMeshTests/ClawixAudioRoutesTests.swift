import XCTest
@testable import Clawix

final class ClawixAudioRoutesTests: XCTestCase {
    func testAudioReplayTemporaryRouteIsCentralized() throws {
        let routesSource = try readSource("Audio/ClawixAudioRoutes.swift")
        let bubbleSource = try readSource("Audio/UserAudioBubble.swift")
        let temporaryDirectory = URL(fileURLWithPath: "/tmp", isDirectory: true)

        XCTAssertEqual(ClawixAudioRoutes.replayPrefix, "clawix-replay")
        XCTAssertEqual(
            ClawixAudioRoutes.replayFileURL(
                audioId: "voice-123",
                fileExtension: "m4a",
                temporaryDirectory: temporaryDirectory
            ).path,
            "/tmp/clawix-replay-voice-123.m4a"
        )

        XCTAssertTrue(routesSource.contains("ClawixTemporaryRoutes.systemTemporaryDirectory(fileManager: fileManager)"))
        XCTAssertFalse(routesSource.contains("fileManager.temporaryDirectory"))
        XCTAssertTrue(bubbleSource.contains("ClawixAudioRoutes.replayFileURL("))
        XCTAssertFalse(bubbleSource.contains("FileManager.default.temporaryDirectory"))
        XCTAssertFalse(bubbleSource.contains("clawix-replay-\\(self.audioRef.id).\\(ext)"))
    }

    func testAudioTemporaryRoutesSanitizePathComponents() {
        let temporaryDirectory = URL(fileURLWithPath: "/tmp", isDirectory: true)

        XCTAssertEqual(
            ClawixAudioRoutes.replayFileURL(
                audioId: "../voice/private",
                fileExtension: "m4a/../../secret",
                temporaryDirectory: temporaryDirectory
            ).path,
            "/tmp/clawix-replay-voice_private.m4a_______secret"
        )
        XCTAssertEqual(
            ClawixAudioRoutes.dictationSpoolFileURL(
                requestId: "../request/private",
                fileExtension: "wav/../../secret",
                temporaryDirectory: temporaryDirectory
            ).path,
            "/tmp/clawix-attachments/dictation/request_private.wav_______secret"
        )
    }

    func testDictationAudioSpoolTemporaryRouteIsCentralized() throws {
        let engineHostSource = try readSource("AppState/EngineHost.swift")
        let temporaryDirectory = URL(fileURLWithPath: "/tmp", isDirectory: true)

        XCTAssertEqual(ClawixAudioRoutes.attachmentsDirectoryName, "clawix-attachments")
        XCTAssertEqual(ClawixAudioRoutes.dictationDirectoryName, "dictation")
        XCTAssertEqual(
            ClawixAudioRoutes.dictationSpoolDirectoryURL(
                temporaryDirectory: temporaryDirectory
            ).path,
            "/tmp/clawix-attachments/dictation"
        )
        XCTAssertEqual(
            ClawixAudioRoutes.dictationSpoolFileURL(
                requestId: "request-123",
                fileExtension: "wav",
                temporaryDirectory: temporaryDirectory
            ).path,
            "/tmp/clawix-attachments/dictation/request-123.wav"
        )

        XCTAssertTrue(engineHostSource.contains("ClawixAudioRoutes.dictationSpoolFileURL("))
        XCTAssertFalse(engineHostSource.contains("NSTemporaryDirectory()"))
        XCTAssertFalse(engineHostSource.contains("\"clawix-attachments\""))
        XCTAssertFalse(engineHostSource.contains("\"dictation\""))
    }

    func testDictationSpoolFilesAreCleanedOnTranscriptionCompletionPaths() throws {
        let appStateHostSource = try readSource("AppState/EngineHost.swift")
        let daemonMainSource = try readHelperSource("main.swift")
        let daemonIngestSource = try readHelperSource("DaemonAudioIngest.swift")

        XCTAssertTrue(appStateHostSource.contains("defer { try? FileManager.default.removeItem(at: url) }"))
        XCTAssertTrue(daemonMainSource.contains("defer { try? FileManager.default.removeItem(at: url) }"))
        XCTAssertTrue(daemonIngestSource.contains("defer { try? FileManager.default.removeItem(at: tmpURL) }"))
        XCTAssertTrue(daemonIngestSource.contains("audio attachment decode failed"))
        XCTAssertFalse(daemonIngestSource.contains("audio attachment decode failed id="))
        XCTAssertTrue(daemonMainSource.contains("safeBridgeAudioPathComponent(requestId)"))
        XCTAssertTrue(daemonIngestSource.contains("safeBridgeAudioPathComponent(first.id)"))
    }

    func testDictationSoundsStorageRouteIsCentralized() throws {
        let soundManagerSource = try readSource("Audio/SoundManager.swift")
        let applicationSupportRoot = URL(fileURLWithPath: "/Users/demo/Library/Application Support", isDirectory: true)

        XCTAssertEqual(ClawixAudioRoutes.appSupportDirectoryName, "Clawix")
        XCTAssertEqual(ClawixAudioRoutes.dictationSoundsDirectoryName, "dictation-sounds")
        XCTAssertEqual(
            ClawixAudioRoutes.dictationSoundsDirectoryURL(applicationSupportRoot: applicationSupportRoot).path,
            "/Users/demo/Library/Application Support/Clawix/dictation-sounds"
        )

        XCTAssertTrue(soundManagerSource.contains("ClawixAudioRoutes.applicationSupportRoot(fileManager: fm)"))
        XCTAssertTrue(soundManagerSource.contains("ClawixAudioRoutes.dictationSoundsDirectoryURL(applicationSupportRoot: support)"))
        XCTAssertFalse(soundManagerSource.contains("for: .applicationSupportDirectory"))
        XCTAssertFalse(soundManagerSource.contains("ClawixPersistentSurfacePaths.components.dictationSounds"))
        XCTAssertFalse(soundManagerSource.contains("ClawixPersistentSurfacePaths.components.clawix, isDirectory: true"))
    }

    private func readSource(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.sources, isDirectory: true)
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.clawix, isDirectory: true)
        return try String(
            contentsOf: root.appendingPathComponent(relativePath, isDirectory: false),
            encoding: .utf8
        )
    }

    private func readHelperSource(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let macosRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let root = macosRoot
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("Bridged", isDirectory: true)
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("clawix-bridge", isDirectory: true)
        return try String(
            contentsOf: root.appendingPathComponent(relativePath, isDirectory: false),
            encoding: .utf8
        )
    }
}
