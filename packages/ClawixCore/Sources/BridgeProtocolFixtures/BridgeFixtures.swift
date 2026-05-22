import Foundation
import ClawixCore

public enum BridgeFixtureDirection: String, Codable, Equatable, Sendable {
    case clientToDaemon
    case daemonToClient
}

public struct BridgeFixture: Equatable, Sendable {
    public let name: String
    public let direction: BridgeFixtureDirection
    public let frame: BridgeFrame

    public init(name: String, direction: BridgeFixtureDirection, frame: BridgeFrame) {
        self.name = name
        self.direction = direction
        self.frame = frame
    }
}

public enum BridgeFixtures {
    public static var all: [BridgeFixture] {
        let attachment = WireAttachment(
            id: "att-image-1",
            mimeType: "image/png",
            filename: "screen.png",
            dataBase64: "ZmFrZUltYWdl"
        )
        let audioAttachment = WireAttachment(
            id: "att-audio-1",
            kind: .audio,
            mimeType: "audio/m4a",
            filename: "voice.m4a",
            dataBase64: "ZmFrZUF1ZGlv"
        )
        let session = WireSession(
            id: "session-1",
            title: "Fixture session",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            isPinned: true,
            hasActiveTurn: true,
            lastMessageAt: Date(timeIntervalSince1970: 1_700_000_120),
            lastMessagePreview: "Done",
            branch: "main",
            cwd: "/tmp/clawix-fixture",
            threadId: "thread-1",
            agentId: "agent.default.primary"
        )
        let message = WireMessage(
            id: "message-1",
            role: .assistant,
            content: "Fixture response",
            reasoningText: "thinking",
            streamingFinished: true,
            timestamp: Date(timeIntervalSince1970: 1_700_000_030),
            timeline: [.tools(id: "tools-1", items: [
                WireWorkItem(id: "work-1", kind: "command", status: .completed, commandText: "pwd", commandActions: ["read"])
            ])],
            audioRef: WireAudioRef(id: "audio-1", mimeType: "audio/m4a", durationMs: 2_400)
        )
        let project = WireProject(
            id: "project-1",
            title: "Clawix",
            cwd: "/tmp/clawix-fixture",
            hasGitRepo: true,
            branch: "main",
            lastUsedAt: Date(timeIntervalSince1970: 1_700_000_200)
        )
        let rateLimit = WireRateLimitSnapshot(
            primary: WireRateLimitWindow(usedPercent: 14, resetsAt: 1_778_222_391, windowDurationMins: 300),
            secondary: nil,
            credits: WireCreditsSnapshot(hasCredits: true, unlimited: false, balance: "12.34"),
            limitId: "primary",
            limitName: nil
        )
        let audioAsset = sampleAudioAsset()
        let transcript = audioAsset.transcripts[0]
        let serviceStatus = WireClawJSServiceSnapshot(
            id: "database",
            state: "readyFromDaemon",
            port: 24_102,
            pid: 12_345,
            restartCount: 0,
            lastError: nil,
            updatedAtMs: 1_750_000_000_000,
            source: "daemon"
        )

        func outbound(_ name: String, _ body: BridgeBody) -> BridgeFixture {
            BridgeFixture(name: name, direction: .clientToDaemon, frame: BridgeFrame(body))
        }

        func inbound(_ name: String, _ body: BridgeBody) -> BridgeFixture {
            BridgeFixture(name: name, direction: .daemonToClient, frame: BridgeFrame(body))
        }

        return [
            outbound("auth", .auth(token: "token-abc", deviceName: "Windows", clientKind: .desktop, clientId: "client-win", installationId: "install-win", deviceId: "device-win")),
            outbound("listSessions", .listSessions),
            outbound("openSession", .openSession(sessionId: "session-1", limit: 60)),
            outbound("loadOlderMessages", .loadOlderMessages(sessionId: "session-1", beforeMessageId: "message-0", limit: 40)),
            outbound("sendMessage", .sendMessage(sessionId: "session-1", text: "hello", attachments: [attachment])),
            outbound("newSession", .newSession(sessionId: "session-2", text: "start", attachments: [audioAttachment])),
            outbound("interruptTurn", .interruptTurn(sessionId: "session-1")),
            inbound("authOk", .authOk(hostDisplayName: "Fixture Mac")),
            inbound("authFailed", .authFailed(reason: "bad-token")),
            inbound("versionMismatch", .versionMismatch(serverVersion: 2)),
            inbound("sessionsSnapshot", .sessionsSnapshot(sessions: [session])),
            inbound("sessionUpdated", .sessionUpdated(session: session)),
            inbound("messagesSnapshot", .messagesSnapshot(sessionId: "session-1", messages: [message], hasMore: false)),
            inbound("messagesPage", .messagesPage(sessionId: "session-1", messages: [message], hasMore: true)),
            inbound("messageAppended", .messageAppended(sessionId: "session-1", message: message)),
            inbound("messageStreaming", .messageStreaming(sessionId: "session-1", messageId: "message-1", content: "partial", reasoningText: "thinking", finished: false)),
            inbound("errorEvent", .errorEvent(code: "internal", message: "boom")),
            outbound("editPrompt", .editPrompt(sessionId: "session-1", messageId: "message-0", text: "rewrite")),
            outbound("archiveSession", .archiveSession(sessionId: "session-1")),
            outbound("unarchiveSession", .unarchiveSession(sessionId: "session-1")),
            outbound("pinSession", .pinSession(sessionId: "session-1")),
            outbound("unpinSession", .unpinSession(sessionId: "session-1")),
            outbound("renameSession", .renameSession(sessionId: "session-1", title: "Renamed")),
            outbound("pairingStart", .pairingStart),
            outbound("listProjects", .listProjects),
            outbound("readFile", .readFile(path: "/tmp/clawix-fixture/README.md")),
            inbound("pairingPayload", .pairingPayload(qrJson: #"{"v":1,"host":"127.0.0.1","port":24080,"token":"token-abc","shortCode":"ABC-234-XYZ","hostDisplayName":"Fixture Mac"}"#, token: "token-abc", shortCode: "ABC-234-XYZ")),
            inbound("projectsSnapshot", .projectsSnapshot(projects: [project])),
            inbound("fileSnapshot", .fileSnapshot(path: "/tmp/clawix-fixture/README.md", content: "# Fixture", isMarkdown: true, error: nil)),
            outbound("transcribeAudio", .transcribeAudio(requestId: "req-1", audioBase64: "ZmFrZUF1ZGlv", mimeType: "audio/m4a", language: "en")),
            inbound("transcriptionResult", .transcriptionResult(requestId: "req-1", text: "hello audio", errorMessage: nil)),
            outbound("requestAudio", .requestAudio(audioId: "audio-1")),
            inbound("audioSnapshot", .audioSnapshot(audioId: "audio-1", audioBase64: "ZmFrZUF1ZGlv", mimeType: "audio/m4a", errorMessage: nil)),
            outbound("requestGeneratedImage", .requestGeneratedImage(path: "/Users/demo/.clawix/generated_images/image.png")),
            inbound("generatedImageSnapshot", .generatedImageSnapshot(path: "/Users/demo/.clawix/generated_images/image.png", dataBase64: "ZmFrZUltYWdl", mimeType: "image/png", errorMessage: nil)),
            outbound("requestRolloutAttachment", .requestRolloutAttachment(attachmentId: "rollout-attachment-1")),
            inbound("rolloutAttachmentSnapshot", .rolloutAttachmentSnapshot(attachmentId: "rollout-attachment-1", dataBase64: "ZmFrZVJvbGxvdXQ=", mimeType: "image/png", errorMessage: nil)),
            inbound("bridgeState", .bridgeState(state: "ready", chatCount: 1, message: nil)),
            outbound("requestRateLimits", .requestRateLimits),
            inbound("rateLimitsSnapshot", .rateLimitsSnapshot(snapshot: rateLimit, byLimitId: ["primary": rateLimit])),
            inbound("rateLimitsUpdated", .rateLimitsUpdated(snapshot: rateLimit, byLimitId: [:])),
            outbound("requestClawJSServiceStatuses", .requestClawJSServiceStatuses),
            inbound("clawJSServiceStatusesSnapshot", .clawJSServiceStatusesSnapshot(services: [serviceStatus])),
            inbound("clawJSServiceStatusUpdated", .clawJSServiceStatusUpdated(service: serviceStatus)),
            outbound("audioRegister", .audioRegister(requestId: "req-audio-1", request: WireAudioRegisterRequest(kind: .user_message, appId: "clawix", originActor: .user, mimeType: "audio/m4a", bytesBase64: "ZmFrZUF1ZGlv", durationMs: 2_400, deviceId: "device-win", sessionId: "session-1", threadId: "thread-1", linkedMessageId: "message-1", metadataJson: #"{"source":"fixture"}"#, transcript: WireAudioRegisterTranscript(text: "hello audio", role: .transcription, provider: "whisper", language: "en")))),
            outbound("audioAttachTranscript", .audioAttachTranscript(requestId: "req-audio-2", audioId: "audio-1", transcript: WireAudioAttachTranscriptInput(text: "better transcript", role: .transcription, provider: "whisper-large", language: "en", markAsPrimary: true))),
            outbound("audioGet", .audioGet(requestId: "req-audio-3", audioId: "audio-1", appId: "clawix")),
            outbound("audioGetBytes", .audioGetBytes(requestId: "req-audio-4", audioId: "audio-1", appId: "clawix")),
            outbound("audioList", .audioList(requestId: "req-audio-5", filter: WireAudioListFilter(appId: "clawix", kind: .user_message, originActor: .user, deviceId: "device-win", sessionId: "session-1", threadId: "thread-1", linkedMessageId: "message-1", fromCreatedAt: 1_750_000_000_000, toCreatedAt: 1_750_000_100_000, limit: 50, offset: 0))),
            outbound("audioDelete", .audioDelete(requestId: "req-audio-6", audioId: "audio-1", appId: "clawix")),
            inbound("audioRegisterResult", .audioRegisterResult(requestId: "req-audio-1", asset: audioAsset, errorMessage: nil)),
            inbound("audioAttachTranscriptResult", .audioAttachTranscriptResult(requestId: "req-audio-2", transcript: transcript, errorMessage: nil)),
            inbound("audioGetResult", .audioGetResult(requestId: "req-audio-3", asset: audioAsset, errorMessage: nil)),
            inbound("audioBytesResult", .audioBytesResult(requestId: "req-audio-4", audioBase64: "ZmFrZUF1ZGlv", mimeType: "audio/m4a", durationMs: 2_400, errorMessage: nil)),
            inbound("audioListResult", .audioListResult(requestId: "req-audio-5", list: WireAudioListResult(items: [audioAsset], total: 1), errorMessage: nil)),
            inbound("audioDeleteResult", .audioDeleteResult(requestId: "req-audio-6", deleted: true, errorMessage: nil))
        ]
    }

    private static func sampleAudioAsset() -> WireAudioAssetWithTranscripts {
        let asset = WireAudioAsset(
            id: "audio-1",
            kind: .user_message,
            appId: "clawix",
            originActor: .user,
            mimeType: "audio/m4a",
            bytesRelPath: "clawix/audio-1.m4a",
            durationMs: 2_400,
            createdAt: 1_750_000_000_000,
            deviceId: "device-win",
            sessionId: "session-1",
            threadId: "thread-1",
            linkedMessageId: "message-1",
            metadataJson: #"{"source":"fixture"}"#
        )
        let transcript = WireAudioTranscript(
            id: "transcript-1",
            audioId: "audio-1",
            role: .transcription,
            text: "hello audio",
            provider: "whisper",
            language: "en",
            createdAt: 1_750_000_001_000,
            isPrimary: true
        )
        return WireAudioAssetWithTranscripts(asset: asset, transcripts: [transcript])
    }
}
