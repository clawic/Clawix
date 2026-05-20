import Foundation

struct SystemTelemetryMonitorRecordResult: Equatable {
    enum Status: String {
        case recorded
        case skipped
        case unavailable
        case failed
    }

    var status: Status
    var sampleCount: Int
    var rollupCount: Int
    var incidentCount: Int
    var dbPath: String?
    var reason: String?
}

@MainActor
final class SystemTelemetryMonitorRecorder {
    struct CommandRunner {
        var run: @Sendable ([String]) async throws -> Data
    }

    private let runner: CommandRunner
    private let hostCommandProvider: @MainActor () -> String?
    private let minimumInterval: TimeInterval
    private var lastAttemptAt: Date?

    init(
        runner: CommandRunner? = nil,
        hostCommandProvider: @escaping @MainActor () -> String? = SystemTelemetryMonitorRecorder.defaultHostCommand,
        minimumInterval: TimeInterval = 60
    ) {
        self.runner = runner ?? Self.defaultRunner()
        self.hostCommandProvider = hostCommandProvider
        self.minimumInterval = minimumInterval
    }

    func recordIfDue(now: Date = Date()) async -> SystemTelemetryMonitorRecordResult {
        if let lastAttemptAt, now.timeIntervalSince(lastAttemptAt) < minimumInterval {
            return SystemTelemetryMonitorRecordResult(
                status: .skipped,
                sampleCount: 0,
                rollupCount: 0,
                incidentCount: 0,
                dbPath: nil,
                reason: "minimum_interval"
            )
        }
        lastAttemptAt = now

        guard let hostCommand = hostCommandProvider(), !hostCommand.isEmpty else {
            return SystemTelemetryMonitorRecordResult(
                status: .unavailable,
                sampleCount: 0,
                rollupCount: 0,
                incidentCount: 0,
                dbPath: nil,
                reason: "host_command_unavailable"
            )
        }

        do {
            let data = try await runner.run([
                "system",
                "snapshot",
                "--source",
                "host",
                "--host-command",
                hostCommand,
                "--record",
                "true",
                "--json",
            ])
            return try Self.decodeRecordResult(data)
        } catch {
            return SystemTelemetryMonitorRecordResult(
                status: .failed,
                sampleCount: 0,
                rollupCount: 0,
                incidentCount: 0,
                dbPath: nil,
                reason: error.localizedDescription
            )
        }
    }

    static func decodeRecordResult(_ data: Data) throws -> SystemTelemetryMonitorRecordResult {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let payload = (json?["data"] as? [String: Any]) ?? json ?? [:]
        let recorded = payload["recorded"] as? [String: Any] ?? [:]
        return SystemTelemetryMonitorRecordResult(
            status: .recorded,
            sampleCount: int(from: recorded["sampleCount"]) ?? int(from: recorded["sample_count"]) ?? 0,
            rollupCount: int(from: recorded["rollupCount"]) ?? int(from: recorded["rollup_count"]) ?? 0,
            incidentCount: int(from: recorded["incidentCount"]) ?? int(from: recorded["incident_count"]) ?? 0,
            dbPath: recorded["dbPath"] as? String ?? recorded["db_path"] as? String,
            reason: nil
        )
    }

    private static func defaultHostCommand() -> String? {
        if let configured = ProcessInfo.processInfo.environment[ClawixPersistentSurfaceKeys.systemTelemetryHostCommandEnv],
           !configured.isEmpty {
            return configured
        }

        let executableDirectory = URL(fileURLWithPath: CommandLine.arguments.first ?? "")
            .deletingLastPathComponent()
        let candidates = [
            executableDirectory.appendingPathComponent("claw-host"),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents/MacOS", isDirectory: true)
                .appendingPathComponent("claw-host"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/debug/claw-host"),
        ]

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }?.path
    }

    private static func defaultRunner() -> CommandRunner {
        let isAvailable = ClawJSRuntime.isAvailable
        let executableURL = ClawJSRuntime.nodeBinaryURL
        let argumentsPrefix = [ClawJSRuntime.cliScriptURL.path]
        let currentDirectoryURL = ClawJSServiceManager.workspaceURL
        let environment = ClawJSServiceManager.cliEnvironment()

        return CommandRunner { args in
            guard isAvailable else {
                throw NSError(domain: "SystemTelemetryMonitorRecorder", code: 1, userInfo: [
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
                let message = String(data: err.isEmpty ? data : err, encoding: .utf8) ?? "system telemetry monitor record failed"
                throw NSError(domain: "SystemTelemetryMonitorRecorder", code: Int(process.terminationStatus), userInfo: [
                    NSLocalizedDescriptionKey: message.trimmingCharacters(in: .whitespacesAndNewlines)
                ])
            }
            return data
        }.value
    }

    private static func int(from value: Any?) -> Int? {
        switch value {
        case let value as Int:
            return value
        case let value as Double:
            return Int(value)
        case let value as NSNumber:
            return value.intValue
        default:
            return nil
        }
    }
}
