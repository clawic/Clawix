import Foundation

enum ClawJSRuntimeLensID: String, CaseIterable, Identifiable {
    case openclaw
    case hermes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .openclaw: return "OpenClaw"
        case .hermes: return "Hermes"
        }
    }
}

struct ClawJSRuntimeLensSnapshot: Decodable, Equatable {
    let runtimeId: String
    let runtimeName: String
    let support: Support?
    let status: Status
    let domains: [Domain]

    struct Support: Decodable, Equatable {
        let stability: String?
        let supportLevel: String?
        let recommended: Bool?
    }

    struct Status: Decodable, Equatable {
        let installed: Bool?
        let cliAvailable: Bool?
        let gatewayAvailable: Bool?
        let diagnostics: Diagnostics?

        struct Diagnostics: Decodable, Equatable {
            let lastError: String?
            let locations: Locations?
        }

        struct Locations: Decodable, Equatable {
            let homeDir: String?
            let workspacePath: String?
            let configPath: String?
            let authStorePath: String?
            let gatewayConfigPath: String?
        }
    }

    struct Domain: Decodable, Equatable, Identifiable {
        var id: String { domain }
        let domain: String
        let supported: Bool?
        let status: String?
        let strategy: String?
        let count: Int?
        let authority: String?
        let limitations: [String]?
    }
}

struct ClawJSRuntimeLensClient {
    struct CommandResult {
        let data: Data
        let exitCode: Int32
    }

    struct CommandRunner {
        var run: (ClawJSRuntimeLensID) async throws -> CommandResult
    }

    private struct Envelope: Decodable {
        let data: ClawJSRuntimeLensSnapshot
    }

    private static let maxRuntimeLensEnvelopeBytes = 1_048_576

    private let runner: CommandRunner

    init(runner: CommandRunner? = nil) {
        self.runner = runner ?? CommandRunner { runtime in
            try await Self.runClawJS(args: ["runtime", runtime.rawValue, "domains", "--json"])
        }
    }

    func load(runtime: ClawJSRuntimeLensID) async throws -> ClawJSRuntimeLensSnapshot {
        let result = try await runner.run(runtime)
        guard result.exitCode == 0 || result.exitCode == 2 else {
            let message = String(data: result.data, encoding: .utf8) ?? "runtime lens failed"
            throw NSError(domain: "ClawJSRuntimeLensClient", code: Int(result.exitCode), userInfo: [
                NSLocalizedDescriptionKey: message.trimmingCharacters(in: .whitespacesAndNewlines)
            ])
        }
        guard result.data.count <= Self.maxRuntimeLensEnvelopeBytes else {
            throw NSError(domain: "ClawJSRuntimeLensClient", code: 413, userInfo: [
                NSLocalizedDescriptionKey: "runtime lens envelope exceeded the bounded decode budget"
            ])
        }
        // hot-path-ok maxBytes=1048576 reason=runtime lens command returns one bounded domains envelope
        return try JSONDecoder().decode(Envelope.self, from: result.data).data
    }

    private static func runClawJS(args: [String]) async throws -> CommandResult {
        let context = await MainActor.run {
            RuntimeLensProcessContext(
                executableURL: ClawJSRuntime.nodeBinaryURL,
                cliScriptURL: ClawJSRuntime.cliScriptURL,
                workspaceURL: ClawJSServiceManager.workspaceURL,
                environment: ClawJSServiceManager.cliEnvironment()
            )
        }
        let cancellation = RuntimeLensProcessCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        continuation.resume(returning: try runClawJSSynchronously(
                            args: args,
                            context: context,
                            cancellation: cancellation
                        ))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    nonisolated private static func runClawJSSynchronously(
        args: [String],
        context: RuntimeLensProcessContext,
        cancellation: RuntimeLensProcessCancellation
    ) throws -> CommandResult {
        guard ClawJSRuntime.isAvailable else {
            throw NSError(domain: "ClawJSRuntimeLensClient", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "ClawJS bundle is not available in this build."
            ])
        }
        let process = Process()
        process.executableURL = context.executableURL
        process.arguments = [context.cliScriptURL.path] + args
        process.currentDirectoryURL = context.workspaceURL
        process.environment = context.environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        guard cancellation.attach(process) else { throw CancellationError() }
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if cancellation.isCancelled { throw CancellationError() }
        return CommandResult(data: data.isEmpty ? err : data, exitCode: process.terminationStatus)
    }
}

private struct RuntimeLensProcessContext: Sendable {
    let executableURL: URL
    let cliScriptURL: URL
    let workspaceURL: URL
    let environment: [String: String]
}

private final class RuntimeLensProcessCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func attach(_ process: Process) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !cancelled else { return false }
        self.process = process
        return true
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let process = self.process
        lock.unlock()
        process?.terminate()
    }
}
