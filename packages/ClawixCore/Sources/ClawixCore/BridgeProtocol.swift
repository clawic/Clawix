import Foundation

/// Wire-format version exchanged in every frame. Clients refuse to talk to a
/// peer reporting a different `schemaVersion` and surface an "update Clawix"
/// empty state.
public let bridgeSchemaVersion: Int = 1

/// Maximum accepted bridge WebSocket text frame size. The bridge still carries
/// v1 inline audio/image bytes when needed, but rejects oversized frames before
/// decoding so invalid peers cannot force unbounded JSON work.
public let bridgeMaxFrameBytes: Int = 8 * 1024 * 1024

/// Default count of trailing messages the server returns on
/// `openSession(limit:)` when the client opts into pagination. 60 covers
/// the last ~6-10 turns including their tool-call timelines and inline
/// attachments without burning the first paint on a big chat. Earlier
/// pages stream in via `loadOlderMessages` as the user scrolls up.
public let bridgeInitialPageLimit: Int = 60

/// Page size for each `loadOlderMessages` request fired by the client
/// after the user scrolls near the top of the transcript. Smaller than
/// the initial batch because (a) the user already saw the recent
/// turns, (b) earlier history is the long tail and we want each pull to
/// stay under ~300ms over LAN even when turns carry heavy timelines.
public let bridgeOlderPageLimit: Int = 40

/// Kind of client speaking on a session. Affects which frame types the
/// server is willing to dispatch:
///
/// - `.companion` is the read-mostly companion role: list/open sessions
///   and send messages, but not the session-mutation grab-bag.
/// - `.desktop` is the macOS GUI talking to the LaunchAgent daemon. It
///   gets the full surface (edit, archive, pin, branch switch, project
///   selection, pairing token issuance, auth coordinator, etc.).
///
/// Clients send `clientKind` as a role, not as a platform identifier.
public enum ClientKind: String, Codable, Equatable, Sendable {
    case companion
    case desktop
}

public struct BridgeFrame: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let body: BridgeBody

    public init(_ body: BridgeBody, schemaVersion: Int = bridgeSchemaVersion) {
        self.schemaVersion = schemaVersion
        self.body = body
    }
}

/// All discriminated frame bodies. Wire format is flat: every frame
/// carries `schemaVersion`, `type`, and the payload fields at the top
/// level (no `payload` envelope) so log lines stay readable.
public enum BridgeBody: Equatable, Sendable {
    // MARK: - Outbound (iPhone -> Mac)
    case auth(
        token: String,
        deviceName: String?,
        clientKind: ClientKind,
        clientId: String,
        installationId: String,
        deviceId: String
    )
    case listSessions
    /// Open a chat for streaming. `limit` is optional: when set, the
    /// server replies with the trailing N messages and a `hasMore`
    /// flag so the client can lazily fetch earlier history via
    /// `loadOlderMessages`. `limit == nil` is the current v1 request
    /// for the whole transcript.
    case openSession(sessionId: String, limit: Int?)
    /// Pull a window of earlier messages anchored at the oldest message
    /// the client currently holds. `beforeMessageId` is exclusive
    /// (clients have it already), `limit` is how many earlier rows to
    /// fetch. Server replies with `messagesPage`.
    case loadOlderMessages(sessionId: String, beforeMessageId: String, limit: Int)
    /// Carries optional inline attachments alongside the prompt. The
    /// daemon writes each one to a turn-scoped temp file and forwards
    /// the resulting paths to Codex as `localImage` user input items.
    /// Empty attachment lists may omit the field; attachment entries
    /// themselves must carry an explicit `kind`.
    case sendMessage(sessionId: String, text: String, attachments: [WireAttachment])
    /// New conversation kicked off from the iPhone FAB. The client
    /// pre-mints the UUID so it can route to the chat detail screen
    /// before the round trip lands; the Mac creates a chat with that
    /// exact id, appends the user message, and runs the turn. The bus
    /// auto-subscribes the new id so streaming deltas flow back without
    /// an extra `openSession`.
    case newSession(sessionId: String, text: String, attachments: [WireAttachment])
    /// Stop the active turn for `sessionId` if any. Mirrors the macOS
    /// composer's stop button: marks the turn interrupted, clears
    /// `hasActiveTurn` on the chat, and asks the backend to cancel.
    /// No-op when the chat has no in-flight turn.
    case interruptTurn(sessionId: String)

    // MARK: - Inbound (Mac -> iPhone)
    case authOk(hostDisplayName: String?)
    case authFailed(reason: String)
    case versionMismatch(serverVersion: Int)
    case sessionsSnapshot(sessions: [WireSession])
    case sessionUpdated(session: WireSession)
    /// Replace the client's view of a chat with the server's. `hasMore`
    /// is optional: `nil` means this snapshot is the complete transcript.
    /// When the client receives this it MUST reset its pagination state
    /// for `sessionId` because every snapshot is the new baseline.
    case messagesSnapshot(sessionId: String, messages: [WireMessage], hasMore: Bool?)
    /// Reply to `loadOlderMessages`. `messages` is the slice prior to
    /// the cursor (chronological order, oldest first); `hasMore` is
    /// `false` when the slice reaches the start of the chat.
    case messagesPage(sessionId: String, messages: [WireMessage], hasMore: Bool)
    case messageAppended(sessionId: String, message: WireMessage)
    /// Carries the full current state of the message (content +
    /// reasoning) every tick, not deltas. The iPhone replaces. Trades
    /// a few extra KB on LAN for no append/delta correctness bugs.
    case messageStreaming(
        sessionId: String,
        messageId: String,
        content: String,
        reasoningText: String,
        finished: Bool
    )
    case errorEvent(code: String, message: String)

    // MARK: - Desktop control outbound (desktop client -> daemon)
    /// Edit a prompt in place and re-run the turn. `sessionId` is the
    /// chat, `messageId` is the user message being rewritten, `text`
    /// is the new content. Daemon truncates the rollout at this turn,
    /// applies the new prompt, and re-streams.
    case editPrompt(sessionId: String, messageId: String, text: String)
    /// Toggle the archived flag. Sticks across relaunches because the
    /// archive state lives in the GRDB database the daemon owns.
    case archiveSession(sessionId: String)
    case unarchiveSession(sessionId: String)
    /// Toggle the pinned flag.
    case pinSession(sessionId: String)
    case unpinSession(sessionId: String)
    /// Rename a chat. Daemon writes the new name to the runtime
    /// (`thread/name/set` JSON-RPC against Codex) and echoes the
    /// updated `WireSession` back via `sessionUpdated` so every other
    /// connected client sees the new title.
    case renameSession(sessionId: String, title: String)
    /// Ask the daemon for a fresh pairing payload (token + QR JSON).
    /// Used by `PairWindowView` in the GUI.
    case pairingStart
    /// Ask the daemon for the current list of projects derived from
    /// sessions + manual additions. Reply is `projectsSnapshot`.
    case listProjects
    /// Ask the daemon to read a text file off disk and ship its
    /// contents back so the iPhone can render the same Markdown / raw
    /// preview the Mac panel offers when tapping a changed-file pill.
    /// Path is resolved as an absolute filesystem path on the Mac.
    /// Reply is `fileSnapshot`.
    case readFile(path: String)

    // MARK: - Desktop control inbound (daemon -> desktop client)
    /// Reply to `pairingStart`. The QR is what the iPhone scans; the
    /// token is what the daemon will accept on the next `auth` frame
    /// from a fresh iPhone.
    case pairingPayload(qrJson: String, token: String, shortCode: String)
    /// Reply to `listProjects`.
    case projectsSnapshot(projects: [WireProject])
    /// Reply to `readFile`. Either `content` is set with the UTF-8
    /// text of the file (and `isMarkdown` says how to render it), or
    /// `error` carries a short reason string suitable for display
    /// ("File not found", "Couldn't decode file as text", etc.).
    case fileSnapshot(path: String, content: String?, isMarkdown: Bool, error: String?)

    /// Voice-to-text request from the iPhone companion. The audio blob
    /// travels base64-encoded inline (same shape as `WireAttachment`)
    /// because the bridge transport is text-only WebSocket frames; for a
    /// few seconds of compressed audio (m4a/AAC) it stays well under any
    /// practical size. `requestId` is a client-minted correlation token
    /// so the iPhone can match the answer to the right pending request
    /// without needing a per-chat queue. `language` is an optional
    /// Whisper language code (e.g. "en", "es"); `nil` means auto-detect.
    case transcribeAudio(requestId: String, audioBase64: String, mimeType: String, language: String?)
    /// Reply to `transcribeAudio`. On success `text` is the transcript
    /// and `errorMessage` is nil. On failure (decode error, no model
    /// downloaded, transcription crash) `text` is empty and
    /// `errorMessage` carries a short reason for display.
    case transcriptionResult(requestId: String, text: String, errorMessage: String?)

    /// Ask the daemon for the bytes of a previously-stored voice clip.
    /// `audioId` is the value the daemon put into the user message's
    /// `audioRef.id`. Reply is `audioSnapshot`. Clients are expected to
    /// cache the answer locally; the daemon's storage is the canonical
    /// copy but the round trip is wasteful on every replay.
    case requestAudio(audioId: String)
    /// Reply to `requestAudio`. On success `audioBase64` carries the
    /// raw bytes (m4a/AAC unless the user uploaded something else) and
    /// `errorMessage` is nil. On failure (no longer on disk, never
    /// existed) `audioBase64` is nil and `errorMessage` is a short
    /// reason like "Audio no longer available".
    case audioSnapshot(audioId: String, audioBase64: String?, mimeType: String?, errorMessage: String?)

    /// Ask the daemon for the bytes of a generated image written by
    /// Codex's `imagegen` tool (or any image the assistant referenced
    /// by absolute path inside `~/.codex/generated_images`). The daemon
    /// validates the path stays under that root and rejects anything
    /// else with a "denied" error. `path` is the absolute filesystem
    /// path on the Mac. Reply is `generatedImageSnapshot`.
    case requestGeneratedImage(path: String)
    /// Reply to `requestGeneratedImage`. On success `dataBase64` carries
    /// the raw PNG (or whatever the file actually is, declared via
    /// `mimeType`) and `errorMessage` is nil. On failure (file missing,
    /// path outside the sandbox, decode error) `dataBase64` is nil and
    /// `errorMessage` is a short reason for display.
    case generatedImageSnapshot(path: String, dataBase64: String?, mimeType: String?, errorMessage: String?)

    /// Ask the host for bytes behind a rollout-hydrated attachment ref.
    /// The id must come from a `WireMessage.attachments` entry; hosts reject
    /// unknown ids instead of resolving arbitrary client-supplied paths.
    case requestRolloutAttachment(attachmentId: String)
    /// Reply to `requestRolloutAttachment`. On success `dataBase64` carries
    /// the referenced bytes and `mimeType` repeats the declared type from the
    /// ref. Missing files or unknown ids return nil bytes plus `errorMessage`.
    case rolloutAttachmentSnapshot(attachmentId: String, dataBase64: String?, mimeType: String?, errorMessage: String?)

    /// Host-side runtime state. `state` is one of `booting`, `idle`,
    /// `syncing`, `ready`, `error`. `idle` means the bridge is healthy
    /// and paired but the agent runtime has not been launched yet.
    /// `chatCount` is the size of the sessions list as the host currently
    /// knows it (useful while in `ready` to confirm the snapshot is
    /// non-empty by design, not by race). `message` carries a short reason
    /// when state is `error`, or a hint for `syncing` (e.g. "loading
    /// rollouts"); nil otherwise.
    /// Sent immediately after `authOk` and again whenever the host
    /// transitions, so a peer that connected during boot sees the
    /// `syncing → ready` flip without polling.
    case bridgeState(state: String, chatCount: Int, message: String?)

    // MARK: - Rate limits outbound (desktop client -> daemon)
    /// Ask the daemon for the current rate-limits snapshot. Reply is
    /// `rateLimitsSnapshot`. The macOS GUI sends this once after
    /// `authOk` so the "Remaining usage limits" widget hydrates as
    /// soon as the desktop client connects to the daemon. iPhone
    /// clients never emit it.
    case requestRateLimits

    // MARK: - ClawJS service status outbound (desktop client -> daemon)
    /// Ask the daemon for the current ClawJS sidecar service status
    /// snapshot. Reply is `clawJSServiceStatusesSnapshot`; subsequent
    /// changes may arrive as `clawJSServiceStatusUpdated` pushes.
    case requestClawJSServiceStatuses

    // MARK: - Rate limits inbound (daemon -> desktop client)
    /// Reply to `requestRateLimits` and also the shape of the push
    /// the daemon sends when Codex emits `account/rateLimits/updated`.
    /// `snapshot` is the general-account view (the same field Codex
    /// returns at `rateLimits` top level); `byLimitId` is the
    /// per-bucket map keyed by metered `limit_id` (e.g. `"codex"`,
    /// `"codex_<model>"`). Both are optional: `snapshot` is nil while
    /// the daemon is still booting and hasn't pulled the first read,
    /// `byLimitId` is empty when the backend doesn't surface
    /// per-bucket data.
    case rateLimitsSnapshot(snapshot: WireRateLimitSnapshot?, byLimitId: [String: WireRateLimitSnapshot])
    /// Push from the daemon every time Codex notifies a fresh
    /// `account/rateLimits/updated`. Same shape as `rateLimitsSnapshot`
    /// so clients can apply both through the same code path.
    case rateLimitsUpdated(snapshot: WireRateLimitSnapshot?, byLimitId: [String: WireRateLimitSnapshot])

    // MARK: - ClawJS service status inbound (daemon -> desktop client)
    /// Current service-status snapshot for all ClawJS sidecars the host
    /// knows about. Empty means the connected daemon does not own or expose
    /// any sidecar status yet.
    case clawJSServiceStatusesSnapshot(services: [WireClawJSServiceSnapshot])
    /// Push emitted when one ClawJS sidecar service changes state.
    case clawJSServiceStatusUpdated(service: WireClawJSServiceSnapshot)

    // MARK: - Audio catalog outbound (client -> daemon)
    /// Register a new audio asset in the framework's audio catalog and
    /// optionally attach a primary transcript in the same round trip.
    /// Reply is `audioRegisterResult` carrying the inserted asset and
    /// any transcripts the framework wrote.
    case audioRegister(requestId: String, request: WireAudioRegisterRequest)
    /// Attach a transcript to an existing audio asset. Used to back the
    /// re-transcription flow (e.g. retry with a larger Whisper model)
    /// without losing the prior transcripts. `markAsPrimary` flips the
    /// primary atomically.
    case audioAttachTranscript(requestId: String, audioId: String, transcript: WireAudioAttachTranscriptInput)
    /// Pull an asset record plus all its transcripts. Bytes are NOT
    /// included; use `audioGetBytes` for the base64 payload.
    case audioGet(requestId: String, audioId: String, appId: String)
    /// Pull the raw bytes of an asset. Carried inline as base64 in the
    /// reply (`audioBytesResult`). Current v1 uses inline base64; a
    /// future same-machine optimization can add a path+token handoff.
    case audioGetBytes(requestId: String, audioId: String, appId: String)
    /// List assets matching the filter. `appId` is required so apps
    /// don't accidentally see each other's audio.
    case audioList(requestId: String, filter: WireAudioListFilter)
    /// Delete an asset by id, scoped by `appId`. Cascades transcripts
    /// and unlinks the blob from disk.
    case audioDelete(requestId: String, audioId: String, appId: String)

    // MARK: - Audio catalog inbound (daemon -> client)
    case audioRegisterResult(requestId: String, asset: WireAudioAssetWithTranscripts?, errorMessage: String?)
    case audioAttachTranscriptResult(requestId: String, transcript: WireAudioTranscript?, errorMessage: String?)
    case audioGetResult(requestId: String, asset: WireAudioAssetWithTranscripts?, errorMessage: String?)
    case audioBytesResult(requestId: String, audioBase64: String?, mimeType: String?, durationMs: Int?, errorMessage: String?)
    case audioListResult(requestId: String, list: WireAudioListResult?, errorMessage: String?)
    case audioDeleteResult(requestId: String, deleted: Bool, errorMessage: String?)
}

public enum BridgeDecodingError: Error, Equatable {
    case oversizedFrame(actualBytes: Int, maxBytes: Int)
    case invalidJSON(String)
    case nonObjectFrame
    case missingField(String)
    case invalidField(String)
    case unknownSchemaVersion(Int)
    case unknownType(String)
    case unknownField(type: String, field: String)
    case invalidPayload(type: String, message: String)
}

extension BridgeDecodingError: CustomStringConvertible {
    public var code: String {
        switch self {
        case .oversizedFrame:
            return "bridge.decode.oversizedFrame"
        case .invalidJSON:
            return "bridge.decode.invalidJson"
        case .nonObjectFrame:
            return "bridge.decode.nonObjectFrame"
        case .missingField:
            return "bridge.decode.missingField"
        case .invalidField:
            return "bridge.decode.invalidField"
        case .unknownSchemaVersion:
            return "bridge.decode.unknownSchemaVersion"
        case .unknownType:
            return "bridge.decode.unknownType"
        case .unknownField:
            return "bridge.decode.unknownField"
        case .invalidPayload:
            return "bridge.decode.invalidPayload"
        }
    }

    public var description: String {
        switch self {
        case .oversizedFrame(let actualBytes, let maxBytes):
            return "frame is \(actualBytes) bytes; maximum is \(maxBytes)"
        case .invalidJSON(let reason):
            return "invalid JSON: \(reason)"
        case .nonObjectFrame:
            return "bridge frame must be a JSON object"
        case .missingField(let field):
            return "missing required field: \(field)"
        case .invalidField(let field):
            return "invalid field: \(field)"
        case .unknownSchemaVersion(let version):
            return "unsupported schemaVersion: \(version)"
        case .unknownType(let type):
            return "unknown frame type: \(type)"
        case .unknownField(let type, let field):
            return "unexpected field for \(type): \(field)"
        case .invalidPayload(let type, let message):
            return "invalid payload for \(type): \(message)"
        }
    }
}

/// Runtime state of the host that drives a `BridgeServer`. The daemon starts
/// at `.idle` after pairing and health surfaces are available, then flips
/// through `idle → syncing → ready` only after a real agent request wakes the
/// backend. The in-process GUI server sits permanently at `.ready` because it
/// shares process state with the chat steward.
public enum BridgeRuntimeState: Equatable, Sendable {
    /// Daemon process started, host wired up, but the Codex backend
    /// subprocess hasn't been launched yet.
    case booting
    /// Bridge pairing, health and transport are available, but no agent
    /// runtime has been launched yet.
    case idle
    /// Codex backend running and `initialize` succeeded; we're now
    /// pulling the chat list / hydrating any cached state.
    case syncing
    /// First chat snapshot has been published to the bus. Subsequent
    /// snapshots flow through the throttled chat publisher; clients
    /// are expected to render the sessions list now.
    case ready
    /// Bootstrap failed. The string is short and user-facing
    /// (surfaced as the "fail" line in `clawix up` and as an error
    /// banner on iOS). Hosts may transition back to `.syncing` after
    /// a retry.
    case error(String)

    public var wireTag: String {
        switch self {
        case .booting: return "booting"
        case .idle:    return "idle"
        case .syncing: return "syncing"
        case .ready:   return "ready"
        case .error:   return "error"
        }
    }

    public var errorMessage: String? {
        if case .error(let message) = self { return message }
        return nil
    }
}
