import Foundation

struct RescueRuntimeHealthSnapshot: Codable, Equatable {
    var processCpuPercent: Double? = nil
    var residentBytes: UInt64? = nil
    var footprintBytes: UInt64? = nil
    var bridgeReachable: Bool? = nil
    var runtimeCount: Int? = nil
    var startupElapsedSeconds: TimeInterval? = nil
    var mainThreadStallMs: Double? = nil
    var recentCrashCount: Int? = nil

    var hasResourceMetrics: Bool {
        processCpuPercent != nil || residentBytes != nil || footprintBytes != nil
    }
}

struct RescueDiagnosticReference: Codable, Equatable, Identifiable {
    var id: String { name }
    var name: String
    var kind: String
}

struct RescueRepairContextPackage: Codable, Equatable {
    struct Redaction: Codable, Equatable {
        var privacy: String
        var promptsIncluded: Bool
        var secretsIncluded: Bool
        var fullLocalPathsIncluded: Bool
        var externalSubmission: String
    }

    var schemaVersion: Int
    var mode: RescueMode
    var canLaunch: Bool
    var canChat: Bool
    var canRunAgent: Bool
    var preservedCapabilities: [RescueCapability]
    var disabledCapabilities: [RescueCapability]
    var pendingRepairSignals: [RescueFailureSignal]
    var circuitBreakers: [RescueFailureSignal]
    var diagnosticReferences: [RescueDiagnosticReference]
    var runtimeHealth: RescueRuntimeHealthSnapshot?
    var evolutionStatus: String
    var migrationLabStatus: String?
    var safeActions: [RescueRepairAction]
    var approvalRequiredActions: [RescueRepairAction]
    var suggestedPatch: RescueRepairPatch?
    var receipt: RescueRepairReceipt?
    var redaction: Redaction
    var agentInstructions: [String]
}

struct RescueRepairAction: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var command: String?
    var reason: String
}

struct RescueRepairPatch: Codable, Equatable {
    var format: String
    var status: String
    var redacted: Bool
    var diff: String
}

struct RescueRepairReceipt: Codable, Equatable {
    var receiptId: String
    var status: String
}

struct RescueRepairContextExport: Equatable {
    var url: URL
    var package: RescueRepairContextPackage
}

enum RescueRepairContextBuilder {
    static func build(
        decision: RescueSurvivalDecision,
        evolutionEnvelopeData: Data?,
        diagnosticFiles: [URL] = [],
        runtimeHealth: RescueRuntimeHealthSnapshot? = nil
    ) -> RescueRepairContextPackage {
        let evolution = evolutionEnvelopeData.flatMap { try? JSONDecoder().decode(RescueEvolutionEnvelope.self, from: $0) }
        let report = evolution?.data.repairReport
        let diagnostics = report?.diagnostics
        let redaction = report?.redaction

        return RescueRepairContextPackage(
            schemaVersion: 1,
            mode: decision.mode,
            canLaunch: decision.canLaunch,
            canChat: decision.canChat,
            canRunAgent: decision.preservedCapabilities.contains(.agentExecution),
            preservedCapabilities: decision.preservedCapabilities,
            disabledCapabilities: decision.disabledCapabilities,
            pendingRepairSignals: decision.pendingRepairSignals,
            circuitBreakers: decision.circuitBreakers,
            diagnosticReferences: diagnosticFiles.map(safeDiagnosticReference(for:)),
            runtimeHealth: runtimeHealth,
            evolutionStatus: report?.status ?? evolution?.data.status ?? "offline_unavailable",
            migrationLabStatus: diagnostics?.migrationLabStatus,
            safeActions: report?.safeActions ?? offlineSafeActions(),
            approvalRequiredActions: mergeApprovalActions(
                report?.approvalRequiredActions ?? [],
                decisionRequiresApproval: decision.requiresApprovalForRiskyRepair
            ),
            suggestedPatch: report?.patch.map { patch in
                RescueRepairPatch(
                    format: patch.format,
                    status: patch.status,
                    redacted: patch.redacted,
                    diff: redact(patch.diff)
                )
            },
            receipt: report?.receipt.map { receipt in
                RescueRepairReceipt(receiptId: receipt.receiptId, status: receipt.status)
            },
            redaction: RescueRepairContextPackage.Redaction(
                privacy: redaction?.privacy ?? "redacted",
                promptsIncluded: false,
                secretsIncluded: false,
                fullLocalPathsIncluded: false,
                externalSubmission: redaction?.externalSubmission ?? "explicit_approval_only"
            ),
            agentInstructions: agentInstructions(for: decision, hasEvolutionReport: report != nil)
        )
    }

    private static func safeDiagnosticReference(for url: URL) -> RescueDiagnosticReference {
        let name = url.lastPathComponent.isEmpty ? "diagnostic" : url.lastPathComponent
        return RescueDiagnosticReference(name: redact(name), kind: diagnosticKind(for: name))
    }

    private static func diagnosticKind(for name: String) -> String {
        if name.contains("resource") { return "resource" }
        if name.contains("receipt") { return "receipt" }
        if name.contains("log") { return "log" }
        return "diagnostic"
    }

    private static func offlineSafeActions() -> [RescueRepairAction] {
        [
            RescueRepairAction(
                id: "open_diagnostics",
                title: "Open local diagnostics",
                command: nil,
                reason: "Use local logs and resource samples when the bundled evolution CLI cannot run."
            ),
            RescueRepairAction(
                id: "preserve_ephemeral_chat",
                title: "Preserve ephemeral chat",
                command: nil,
                reason: "Keep the user able to talk to the agent even when history or storage is unavailable."
            )
        ]
    }

    private static func mergeApprovalActions(
        _ actions: [RescueRepairAction],
        decisionRequiresApproval: Bool
    ) -> [RescueRepairAction] {
        var merged = actions
        if decisionRequiresApproval && !merged.contains(where: { $0.id == "risky_repair_requires_approval" }) {
            merged.append(RescueRepairAction(
                id: "risky_repair_requires_approval",
                title: "Approve risky repair",
                command: nil,
                reason: "State mutation, rollback, external submission, or large backup must remain explicit."
            ))
        }
        return merged
    }

    private static func agentInstructions(
        for decision: RescueSurvivalDecision,
        hasEvolutionReport: Bool
    ) -> [String] {
        var instructions = [
            "Keep launch, chat, and repair available before optional UI, history, indexes, or project lists.",
            "Use safe diagnostic actions first; ask for approval before mutating local state, rolling back, copying external data, or submitting reports.",
            "Do not include prompts, secrets, or full local paths in receipts or support reports."
        ]
        if decision.mode == .ephemeralChat {
            instructions.append("Assume persistent history may be unavailable; use ephemeral chat and repair context as the working surface.")
        }
        if decision.mode == .diagnosticsOnly {
            instructions.append("No runtime is available; collect diagnostics and guide the user without pretending chat execution can run.")
        }
        if !hasEvolutionReport {
            instructions.append("The evolution CLI report is unavailable; rely on local diagnostics and rerun claw evolution doctor/repair when the bundle is restored.")
        }
        return instructions
    }

    private static func redact(_ text: String) -> String {
        var redacted = text.replacingOccurrences(
            of: #"/Users/[^\s"'`]+"#,
            with: "[redacted_path]",
            options: .regularExpression
        )
        redacted = redacted.replacingOccurrences(
            of: #"\b(?:sk|pk|rk|ghp|github_pat|xox[baprs])-[A-Za-z0-9_\-]{8,}\b"#,
            with: "[redacted_secret]",
            options: .regularExpression
        )
        redacted = redacted.replacingOccurrences(
            of: #"\b(prompt|input|message)\s*[:=]\s*("[^"]*"|'[^']*'|[^\n\r;]+)"#,
            with: "$1: [redacted_prompt]",
            options: .regularExpression
        )
        return redacted
    }
}

@MainActor
struct RescueEvolutionCommandClient {
    struct CommandRunner {
        var run: ([String]) throws -> Data
    }

    private let runner: CommandRunner

    init(runner: CommandRunner? = nil) {
        self.runner = runner ?? CommandRunner { args in
            try Self.runBundledClawJS(args: args)
        }
    }

    // Public rescue contract: `claw evolution repair --json` provides the agent-readable plan.
    func repairReport(fromVersion: String? = nil, toVersion: String? = nil) throws -> Data {
        var args = ["evolution", "repair", "--json"]
        if let fromVersion, !fromVersion.isEmpty {
            args += ["--from", fromVersion]
        }
        if let toVersion, !toVersion.isEmpty {
            args += ["--to", toVersion]
        }
        return try runner.run(args)
    }

    func doctor() throws -> Data {
        try runner.run(["evolution", "doctor", "--json"])
    }

    func dryRun(fromVersion: String? = nil, toVersion: String? = nil) throws -> Data {
        var args = ["evolution", "dry-run", "--json"]
        if let fromVersion, !fromVersion.isEmpty {
            args += ["--from", fromVersion]
        }
        if let toVersion, !toVersion.isEmpty {
            args += ["--to", toVersion]
        }
        return try runner.run(args)
    }

    private static func runBundledClawJS(args: [String]) throws -> Data {
        guard ClawJSRuntime.isAvailable else {
            throw NSError(domain: "RescueEvolutionCommandClient", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "ClawJS bundle is not available for rescue diagnostics."
            ])
        }
        let process = Process()
        process.executableURL = ClawJSRuntime.nodeBinaryURL
        process.arguments = [ClawJSRuntime.cliScriptURL.path] + args
        process.currentDirectoryURL = ClawJSServiceManager.workspaceURL
        process.environment = ClawJSServiceManager.cliEnvironment()

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: err.isEmpty ? data : err, encoding: .utf8) ?? "claw evolution failed"
            throw NSError(domain: "RescueEvolutionCommandClient", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: message.trimmingCharacters(in: .whitespacesAndNewlines)
            ])
        }
        return data
    }
}

@MainActor
enum RescueRepairContextExporter {
    static func writeCurrentRescueContext() throws -> RescueRepairContextExport {
        ResourceSampler.persistLastSample()
        guard let destinationURL = ResourceSampler.diagnosticsFileURL(named: "rescue-context.json") else {
            throw NSError(domain: "RescueRepairContextExporter", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Rescue diagnostics folder is unavailable."
            ])
        }

        let lastResourcesURL = ResourceSampler.diagnosticsFileURL(named: ResourceSampler.lastResourcesFileName)
        let evolutionData = try? RescueEvolutionCommandClient().repairReport()
        let runtimeAvailable = ClawJSRuntime.isAvailable
        let liveHealth = ResourceSampler.latestHealthSnapshot(
            bridgeReachable: runtimeAvailable,
            runtimeCount: runtimeAvailable ? 1 : 0
        )
        let persistedHealth = ResourceSampler.persistedHealthSnapshot(
            from: lastResourcesURL,
            bridgeReachable: runtimeAvailable,
            runtimeCount: runtimeAvailable ? 1 : 0
        )
        let runtimeHealth = liveHealth?.hasResourceMetrics == true ? liveHealth : (persistedHealth ?? liveHealth)
        let decision = RescueRuntimeSignalMapper.decision(
            backendStatus: runtimeAvailable ? .ready : .error("ClawJS runtime is unavailable"),
            runtimeHealth: runtimeHealth
        )
        return try write(
            decision: decision,
            evolutionEnvelopeData: evolutionData,
            diagnosticFiles: [lastResourcesURL].compactMap { $0 }.filter { FileManager.default.fileExists(atPath: $0.path) },
            runtimeHealth: runtimeHealth,
            destinationURL: destinationURL
        )
    }

    static func write(
        decision: RescueSurvivalDecision,
        evolutionEnvelopeData: Data?,
        diagnosticFiles: [URL],
        runtimeHealth: RescueRuntimeHealthSnapshot?,
        destinationURL: URL
    ) throws -> RescueRepairContextExport {
        let package = RescueRepairContextBuilder.build(
            decision: decision,
            evolutionEnvelopeData: evolutionEnvelopeData,
            diagnosticFiles: diagnosticFiles,
            runtimeHealth: runtimeHealth
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(package)
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destinationURL, options: .atomic)
        return RescueRepairContextExport(url: destinationURL, package: package)
    }
}

private struct RescueEvolutionEnvelope: Decodable {
    struct Payload: Decodable {
        var status: String?
        var repairReport: Report?
    }

    struct Report: Decodable {
        struct Diagnostics: Decodable {
            var migrationLabStatus: String?
        }

        struct Redaction: Decodable {
            var privacy: String
            var promptsIncluded: Bool
            var secretsIncluded: Bool
            var fullLocalPathsIncluded: Bool
            var externalSubmission: String
        }

        var status: String
        var diagnostics: Diagnostics
        var safeActions: [RescueRepairAction]
        var approvalRequiredActions: [RescueRepairAction]
        var patch: RescueRepairPatch?
        var receipt: RescueRepairReceipt?
        var redaction: Redaction
    }

    var ok: Bool
    var data: Payload
}
