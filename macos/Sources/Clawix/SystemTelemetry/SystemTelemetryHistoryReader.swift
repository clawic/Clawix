import CommanderCore
import Foundation

@MainActor
final class SystemTelemetryHistoryReader {
    struct CommandRunner {
        var run: @Sendable ([String]) async throws -> Data
    }

    private let runner: CommandRunner

    init(runner: CommandRunner? = nil) {
        self.runner = runner ?? Self.defaultRunner()
    }

    func historyPayload(metricKey: String, range: String = "1h") async throws -> CommanderCore.JSONValue {
        let data = try await runner.run([
            "system",
            "history",
            metricKey,
            "--range",
            range,
            "--json",
        ])
        return try Self.decodePayload(data)
    }

    static func decodePayload(_ data: Data) throws -> CommanderCore.JSONValue {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let payload = (json?["data"] as? [String: Any]) ?? json ?? [:]
        return CommanderCore.JSONValue.from(any: payload)
    }

    private static func defaultRunner() -> CommandRunner {
        let isAvailable = ClawJSRuntime.isAvailable
        let executableURL = ClawJSRuntime.nodeBinaryURL
        let argumentsPrefix = [ClawJSRuntime.cliScriptURL.path]
        let currentDirectoryURL = ClawJSServiceManager.workspaceURL
        let environment = ClawJSServiceManager.cliEnvironment()

        return CommandRunner { args in
            guard isAvailable else {
                throw NSError(domain: "SystemTelemetryHistoryReader", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "ClawJS bundle is not available in this build."
                ])
            }

            return try await runProcess(
                executableURL: executableURL,
                arguments: argumentsPrefix + args,
                currentDirectoryURL: currentDirectoryURL,
                environment: environment
            )
        }
    }

    private static func runProcess(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL,
        environment: [String: String]
    ) async throws -> Data {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectoryURL
            process.environment = environment

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            let err = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let message = String(data: err.isEmpty ? data : err, encoding: .utf8) ?? "system telemetry history failed"
                throw NSError(domain: "SystemTelemetryHistoryReader", code: Int(process.terminationStatus), userInfo: [
                    NSLocalizedDescriptionKey: message.trimmingCharacters(in: .whitespacesAndNewlines)
                ])
            }
            return data
        }.value
    }
}
