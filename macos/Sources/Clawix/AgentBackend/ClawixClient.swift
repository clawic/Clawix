import Foundation

// JSON-RPC 2.0 client over stdio for the backend app-server.
//
// Responsibilities:
//   - Spawn the binary, keep stdin/stdout/stderr pipes alive.
//   - Frame messages as one JSON object per line (LF delimited).
//   - Correlate request `id` with awaitable continuations.
//   - Forward server notifications and server-initiated requests as
//     AsyncStreams the service layer can consume.
//   - Auto-decline server-initiated approvals until UI prompt routing is
//     wired through the service layer.

enum ClawixClientError: Error, CustomStringConvertible {
    case binaryNotFound
    case processFailedToStart(String)
    case notRunning
    case rpcError(code: Int, message: String)
    case invalidResponse(String)
    case decodingError(String)
    case frameTooLarge(bytes: Int, maxBytes: Int)
    case eventBufferOverflow(limit: Int)

    var description: String {
        switch self {
        case .binaryNotFound:
            return "Backend binary not found. Set the path manually in Settings."
        case .processFailedToStart(let s):
            return "Backend app-server failed to start: \(s)"
        case .notRunning:
            return "Clawix backend is not running."
        case .rpcError(let code, let message):
            return "JSON-RPC error \(code): \(message)"
        case .invalidResponse(let s):
            return "Invalid response: \(s)"
        case .decodingError(let s):
            return "Decoding error: \(s)"
        case .frameTooLarge(let bytes, let maxBytes):
            return "Backend JSON-RPC frame too large: \(bytes) bytes exceeds \(maxBytes) bytes."
        case .eventBufferOverflow(let limit):
            return "Backend JSON-RPC event stream overflowed its \(limit)-event buffer."
        }
    }
}

/// Server-initiated message that the host app may want to react to.
enum ClawixServerEvent {
    case notification(ClawixServerNotification)
    case request(ClawixServerRequest)
}

actor ClawixClient {
    private let backendHomeEnvName = ["CO", "DEX_HOME"].joined()
    private let backendProcessName = ["co", "dex"].joined()

    private let binary: ClawixBinaryResolution
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdoutFramer = ClawixStdoutFramer()
    private let frameDecoder = ClawixFrameDecoder()
    private var eventCoalescer = ClawixServerEventCoalescer()
    private var stderrLogHandle: FileHandle?

    private var nextRequestId: Int = 1
    private var pending: [Int: PendingResponse] = [:]

    private var eventsContinuation: AsyncStream<ClawixServerEvent>.Continuation?
    nonisolated let events: AsyncStream<ClawixServerEvent>

    private let nonisolatedEventsContinuationBox: ContinuationBox

    init(binary: ClawixBinaryResolution) {
        self.binary = binary
        let box = ContinuationBox()
        var captured: AsyncStream<ClawixServerEvent>.Continuation!
        let stream = AsyncStream<ClawixServerEvent>(
            bufferingPolicy: .bufferingNewest(ClawixEventStreamLimits.eventBufferCount)
        ) { continuation in
            captured = continuation
            box.continuation = continuation
        }
        self.events = stream
        self.nonisolatedEventsContinuationBox = box
        self.eventsContinuation = captured
    }

    deinit {
        nonisolatedEventsContinuationBox.continuation?.finish()
    }

    // MARK: - Lifecycle

    func start() throws {
        guard process == nil else { return }

        let proc = Process()
        proc.executableURL = binary.path
        proc.arguments = ["app-server", "--listen", "stdio://"]
        var env = ProcessInfo.processInfo.environment
        // Dummy mode injects CLAWIX_BACKEND_HOME pointing at an
        // ephemeral directory wiped on each launch. Honour it as the
        // backend's home so rollouts and sessions land there instead
        // of the user's real config dir.
        if let override = env["CLAWIX_BACKEND_HOME"], !override.isEmpty {
            env[backendHomeEnvName] = override
        } else {
            env[backendHomeEnvName] = nil
        }
        // Share the user's existing backend auth, sessions, and config.
        proc.environment = env

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr
        self.stdinPipe = stdin
        self.stdoutPipe = stdout
        self.stderrPipe = stderr

        openStderrLog()
        attachStdoutReader(stdout)
        attachStderrReader(stderr)

        do {
            try proc.run()
        } catch {
            throw ClawixClientError.processFailedToStart(error.localizedDescription)
        }
        self.process = proc

        proc.terminationHandler = { [weak self] term in
            guard let self else { return }
            Task { await self.handleTermination(reason: term.terminationReason, status: term.terminationStatus) }
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        stdoutFramer.reset()
        eventCoalescer.reset()
        try? stderrLogHandle?.close()
        stderrLogHandle = nil
        // Fail any in-flight requests
        for response in pending.values { response.resume(throwing: ClawixClientError.notRunning) }
        pending.removeAll()
    }

    private func handleTermination(reason: Process.TerminationReason, status: Int32) {
        if let log = stderrLogHandle {
            let line = "[\(Date())] \(backendProcessName) app-server terminated. reason=\(reason.rawValue) status=\(status)\n"
            try? log.write(contentsOf: Data(line.utf8))
        }
        process = nil
        eventCoalescer.reset()
        for response in pending.values { response.resume(throwing: ClawixClientError.notRunning) }
        pending.removeAll()
    }

    // MARK: - Public requests

    func send<P: Encodable, R: Decodable>(method: String, params: P, expecting: R.Type) async throws -> R {
        guard process != nil else { throw ClawixClientError.notRunning }
        let id = nextRequestId
        nextRequestId += 1
        let req = ClawixOutgoingRequest(id: id, method: method, params: params)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<R, Error>) in
            pending[id] = PendingResponse(
                resumeFrame: { [frameDecoder] data in
                    do {
                        let result = try await frameDecoder.decodeResponse(data, expecting: R.self)
                        continuation.resume(returning: result)
                    } catch let error as ClawixClientError {
                        switch error {
                        case .rpcError:
                            continuation.resume(throwing: error)
                        default:
                            continuation.resume(throwing: ClawixClientError.decodingError("\(method): \(error)"))
                        }
                    } catch {
                        continuation.resume(throwing: ClawixClientError.decodingError("\(method): \(error)"))
                    }
                },
                resumeError: { error in
                    continuation.resume(throwing: error)
                }
            )
            do {
                try writeFrame(req)
            } catch {
                _ = pending.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }
    }

    func notify<P: Encodable>(method: String, params: P) throws {
        let n = ClawixOutgoingNotification(method: method, params: params)
        try writeFrame(n)
    }

    /// Resolve a server-initiated request (server -> client). v1 callers
    /// send `decline` for any approval to keep behaviour deterministic.
    func resolveServerRequest<R: Encodable>(id: ClawixRPCID, result: R) throws {
        let response = ClawixOutgoingResponse(id: id, result: result)
        try writeFrame(response)
    }

    func resolveServerRequestWithError(id: ClawixRPCID, code: Int, message: String) throws {
        let response = ClawixOutgoingErrorResponse(id: id, error: ClawixErrorBody(code: code, message: message, data: nil))
        try writeFrame(response)
    }

    // MARK: - Framing

    private func writeFrame<T: Encodable>(_ value: T) throws {
        guard let pipe = stdinPipe else { throw ClawixClientError.notRunning }
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        let data = try encoder.encode(value) + Data([0x0a]) // newline
        try pipe.fileHandleForWriting.write(contentsOf: data)
    }

    // MARK: - Stdout reader

    private func attachStdoutReader(_ pipe: Pipe) {
        let handle = pipe.fileHandleForReading
        let weakBox = WeakBox(self)
        handle.readabilityHandler = { fh in
            let data = fh.availableData
            if data.isEmpty {
                fh.readabilityHandler = nil
                return
            }
            Task { await weakBox.value?.appendStdout(data) }
        }
    }

    private func appendStdout(_ data: Data) async {
        let frames: [Data]
        do {
            frames = try stdoutFramer.append(data)
        } catch {
            failBackend(error)
            return
        }
        for frame in frames {
            await handleFrame(frame)
        }
        flushPendingServerEvents()
    }

    private func handleFrame(_ data: Data) async {
        emitFrameSizeSignposts(bytes: data.count)
        let header: ClawixFrameHeader
        do {
            header = try await frameDecoder.decodeHeader(data)
        } catch {
            PerfSignpost.ipcClient.event("decode.failed")
            // Not all server output is JSON-RPC: log it and move on.
            if let log = stderrLogHandle, let s = String(data: data, encoding: .utf8) {
                writeRedacted("[stdout-non-json] \(s)\n", to: log)
            }
            return
        }

        // Response to a request we made (id present, no method)
        if let id = header.id, header.method == nil {
            guard case .int(let intId) = id, let response = pending.removeValue(forKey: intId) else {
                return
            }
            await response.resume(with: data)
            return
        }

        // Server-initiated request (id and method present)
        if let id = header.id, let method = header.method {
            do {
                let request = try await frameDecoder.decodeRequest(id: id, method: method, data: data)
                handleServerRequest(request)
            } catch {
                PerfSignpost.ipcClient.event("decode.failed")
                try? resolveServerRequestWithError(
                    id: id,
                    code: -32600,
                    message: "Invalid request payload for \(method)"
                )
            }
            return
        }

        // Server notification (method present, no id)
        if let method = header.method {
            do {
                let notification = try await frameDecoder.decodeNotification(method: method, data: data)
                emitServerEvent(.notification(notification))
            } catch {
                PerfSignpost.ipcClient.event("decode.failed")
            }
            return
        }
    }

    private func emitFrameSizeSignposts(bytes: Int) {
        PerfSignpost.ipcClient.event("frame.bytes", bytes)
        if bytes > ClawixFrameLimits.warnBytes {
            PerfSignpost.ipcClient.event("frame.large.bytes", bytes)
        }
    }

    /// v1 default policy: refuse approvals automatically. Clawix is launched
    /// with `approval_policy=never` + `sandbox=workspace-write` so this
    /// branch should rarely trigger; it exists as defence in depth.
    ///
    /// `item/tool/requestUserInput` is the exception: that's how the runtime
    /// surfaces plan-mode questions, so we hand the request id to the
    /// service via `events` and let the UI resolve it after the user
    /// answers (or dismisses).
    private func handleServerRequest(_ request: ClawixServerRequest) {
        switch request {
        case .toolUserInput:
            emitServerEvent(.request(request))
        case let .approval(id, _):
            flushPendingServerEvents()
            try? resolveServerRequest(id: id, result: ApprovalDecisionResponse(decision: "decline"))
        case let .unknown(id, method):
            flushPendingServerEvents()
            // For unknown server requests we send a JSON-RPC method-not-found
            // error so the server doesn't deadlock waiting for us.
            try? resolveServerRequestWithError(
                id: id,
                code: -32601,
                message: "Method \(method) not handled by Clawix v1"
            )
        }
    }

    private func failBackend(_ error: Error) {
        if case ClawixClientError.frameTooLarge(let bytes, _) = error {
            PerfSignpost.ipcClient.event("frame.rejected.bytes", bytes)
        }
        if let log = stderrLogHandle {
            writeRedacted("[stdout-frame-error] \(String(describing: error))\n", to: log)
        }
        process?.terminate()
        process = nil
        stdoutFramer.reset()
        eventCoalescer.reset()
        for response in pending.values { response.resume(throwing: error) }
        pending.removeAll()
    }

    private func emitServerEvent(_ event: ClawixServerEvent) {
        emitServerEvents(eventCoalescer.ingest(event))
    }

    private func flushPendingServerEvents() {
        emitServerEvents(eventCoalescer.flush())
    }

    private func emitServerEvents(_ events: [ClawixServerEvent]) {
        guard let continuation = eventsContinuation else { return }
        for event in events {
            switch continuation.yield(event) {
            case .enqueued(_):
                continue
            case .dropped(_):
                PerfSignpost.ipcClient.event("event.buffer.dropped")
                failBackend(ClawixClientError.eventBufferOverflow(limit: ClawixEventStreamLimits.eventBufferCount))
                return
            case .terminated:
                PerfSignpost.ipcClient.event("event.buffer.dropped")
                failBackend(ClawixClientError.eventBufferOverflow(limit: ClawixEventStreamLimits.eventBufferCount))
                return
            @unknown default:
                PerfSignpost.ipcClient.event("event.buffer.dropped")
                failBackend(ClawixClientError.eventBufferOverflow(limit: ClawixEventStreamLimits.eventBufferCount))
                return
            }
        }
    }

    // MARK: - Stderr reader

    private func attachStderrReader(_ pipe: Pipe) {
        let handle = pipe.fileHandleForReading
        let weakBox = WeakBox(self)
        handle.readabilityHandler = { fh in
            let data = fh.availableData
            if data.isEmpty {
                fh.readabilityHandler = nil
                return
            }
            Task { await weakBox.value?.writeStderr(data) }
        }
    }

    private func writeStderr(_ data: Data) {
        guard let log = stderrLogHandle else { return }
        let text = String(decoding: data, as: UTF8.self)
        writeRedacted(text, to: log)
    }

    private func writeRedacted(_ text: String, to log: FileHandle) {
        let redacted = ClawixDiagnosticRedactor.redact(text)
        try? log.write(contentsOf: Data(redacted.utf8))
    }

    private func openStderrLog() {
        let logsDir = (try? ClawixPersistentSurfacePaths.logsRoot())
            ?? FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        let logURL = logsDir.appendingPathComponent("clawix-app-server.log")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        if let h = try? FileHandle(forWritingTo: logURL) {
            try? h.seekToEnd()
            try? h.write(contentsOf: Data("\n=== Clawix start \(Date()) ===\n".utf8))
            self.stderrLogHandle = h
        }
    }
}

// MARK: - helpers

private final class WeakBox<T: AnyObject> {
    weak var value: T?
    init(_ value: T) { self.value = value }
}

enum ClawixEventStreamLimits {
    static let eventBufferCount = 512
    static let maxCoalescedDeltaBytes = 64 * 1024
}

struct ClawixServerEventCoalescer {
    private let maxDeltaBytes: Int
    private var pendingDelta: PendingServerDelta?

    init(maxDeltaBytes: Int = ClawixEventStreamLimits.maxCoalescedDeltaBytes) {
        self.maxDeltaBytes = max(1, maxDeltaBytes)
    }

    mutating func ingest(_ event: ClawixServerEvent) -> [ClawixServerEvent] {
        guard let delta = PendingServerDelta(event: event) else {
            var emitted = flush()
            emitted.append(event)
            return emitted
        }

        var emitted: [ClawixServerEvent] = []
        for chunk in delta.chunks(maxBytes: maxDeltaBytes) {
            PerfSignpost.ipcClient.event("event.delta.bytes", chunk.byteCount)
            if let pendingDelta {
                if pendingDelta.canCoalesce(with: chunk),
                   pendingDelta.byteCount + chunk.byteCount <= maxDeltaBytes {
                    self.pendingDelta = pendingDelta.appending(chunk)
                    PerfSignpost.ipcClient.event("event.coalesced")
                } else {
                    emitted.append(pendingDelta.event)
                    self.pendingDelta = chunk
                }
            } else {
                self.pendingDelta = chunk
            }
        }
        return emitted
    }

    mutating func flush() -> [ClawixServerEvent] {
        guard let delta = pendingDelta else { return [] }
        pendingDelta = nil
        return [delta.event]
    }

    mutating func reset() {
        pendingDelta = nil
    }
}

private struct PendingServerDelta {
    enum Kind {
        case agentMessage
        case reasoningText
        case reasoningSummaryText
    }

    let kind: Kind
    let delta: String
    let itemId: String
    let threadId: String
    let turnId: String

    init?(event: ClawixServerEvent) {
        guard case let .notification(notification) = event else {
            return nil
        }
        switch notification {
        case let .agentMessageDelta(payload):
            self.kind = .agentMessage
            self.delta = payload.delta
            self.itemId = payload.itemId
            self.threadId = payload.threadId
            self.turnId = payload.turnId
        case let .reasoningTextDelta(payload):
            self.kind = .reasoningText
            self.delta = payload.delta
            self.itemId = payload.itemId
            self.threadId = payload.threadId
            self.turnId = payload.turnId
        case let .reasoningSummaryTextDelta(payload):
            self.kind = .reasoningSummaryText
            self.delta = payload.delta
            self.itemId = payload.itemId
            self.threadId = payload.threadId
            self.turnId = payload.turnId
        default:
            return nil
        }
    }

    private init(
        kind: Kind,
        delta: String,
        itemId: String,
        threadId: String,
        turnId: String
    ) {
        self.kind = kind
        self.delta = delta
        self.itemId = itemId
        self.threadId = threadId
        self.turnId = turnId
    }

    var byteCount: Int {
        delta.utf8.count
    }

    var event: ClawixServerEvent {
        switch kind {
        case .agentMessage:
            return .notification(.agentMessageDelta(AgentMessageDelta(
                delta: delta,
                itemId: itemId,
                threadId: threadId,
                turnId: turnId
            )))
        case .reasoningText:
            return .notification(.reasoningTextDelta(ReasoningTextDelta(
                delta: delta,
                itemId: itemId,
                threadId: threadId,
                turnId: turnId
            )))
        case .reasoningSummaryText:
            return .notification(.reasoningSummaryTextDelta(ReasoningTextDelta(
                delta: delta,
                itemId: itemId,
                threadId: threadId,
                turnId: turnId
            )))
        }
    }

    func canCoalesce(with other: PendingServerDelta) -> Bool {
        kind == other.kind
            && itemId == other.itemId
            && threadId == other.threadId
            && turnId == other.turnId
    }

    func appending(_ other: PendingServerDelta) -> PendingServerDelta {
        PendingServerDelta(
            kind: kind,
            delta: delta + other.delta,
            itemId: itemId,
            threadId: threadId,
            turnId: turnId
        )
    }

    func chunks(maxBytes: Int) -> [PendingServerDelta] {
        guard byteCount > maxBytes else { return [self] }
        var chunks: [PendingServerDelta] = []
        var start = delta.startIndex
        var index = start
        var bytes = 0

        while index < delta.endIndex {
            let next = delta.index(after: index)
            let charBytes = delta[index ..< next].utf8.count
            if bytes > 0, bytes + charBytes > maxBytes {
                chunks.append(copy(delta: String(delta[start ..< index])))
                start = index
                bytes = 0
            }
            bytes += charBytes
            index = next
        }

        if start < delta.endIndex {
            chunks.append(copy(delta: String(delta[start ..< delta.endIndex])))
        }
        return chunks
    }

    private func copy(delta: String) -> PendingServerDelta {
        PendingServerDelta(
            kind: kind,
            delta: delta,
            itemId: itemId,
            threadId: threadId,
            turnId: turnId
        )
    }
}

private struct PendingResponse {
    let resumeFrame: (Data) async -> Void
    let resumeError: (Error) -> Void

    func resume(with data: Data) async {
        await resumeFrame(data)
    }

    func resume(throwing error: Error) {
        resumeError(error)
    }
}

// `eventsContinuation` cannot be touched non-isolated, but `deinit` runs
// outside the actor, so we keep a separate non-isolated reference here.
private final class ContinuationBox: @unchecked Sendable {
    var continuation: AsyncStream<ClawixServerEvent>.Continuation?
}
