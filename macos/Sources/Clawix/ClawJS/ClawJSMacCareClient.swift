import Foundation

struct ClawJSMacCareClient {
    struct CommandResult {
        let data: Data
        let exitCode: Int32
    }

    struct CommandRunner {
        var run: ([String]) async throws -> CommandResult
    }

    struct Report: Decodable, Equatable {
        let version: Int
        let status: String
        let routes: [Route]
        let groups: [CandidateGroup]
        let actionPlan: ActionPlan
        let safety: SafetyDecision
        let sidecar: Sidecar
        let executionPolicy: ExecutionPolicy
    }

    struct Route: Decodable, Equatable {
        let id: String
        let family: String
        let label: String
        let pathPattern: String
        let source: String
        let sensitivity: String
        let requiredPermissionIds: [String]
        let owner: String
        let evidenceLevel: String
        let mutability: String
        let consumerIntents: [String]
        let notes: String?
    }

    struct CandidateGroup: Codable, Equatable {
        let id: String
        let moduleId: String
        let title: String
        let routeIds: [String]
        let candidates: [Candidate]
    }

    struct Candidate: Codable, Equatable {
        let id: String
        let routeId: String
        let path: String
        let displayName: String
        let sizeBytes: Int?
        let action: String
        let selection: String
        let confidence: Double
        let evidence: [String]
        let warnings: [String]
    }

    struct ActionPlan: Codable, Equatable {
        let id: String
        let createdAt: String
        let groups: [CandidateGroup]
        let executionAuthority: String
        let requestedBy: String
    }

    struct SafetyDecision: Decodable, Equatable {
        let allowed: Bool
        let requiredAuthority: String
        let destructiveActions: [String]
        let reasons: [String]
    }

    struct Sidecar: Decodable, Equatable {
        let filename: String
        let surfaceId: String
        let path: String
    }

    struct ExecutionPolicy: Decodable, Equatable {
        let agentCanExecuteDestructiveActions: Bool
        let testCanExecuteDestructiveActions: Bool
        let destructiveExecutionAuthority: String
        let realFilesystemMutationInFoundationReport: Bool
    }

    struct ScanList: Decodable, Equatable {
        let version: Int
        let status: String
        let scans: [ScanSummary]
        let sidecar: Sidecar
    }

    struct ScanDetail: Decodable, Equatable {
        let version: Int
        let status: String
        let scan: ScanSummary
        let candidates: [PersistedCandidate]
        let actionPlan: ActionPlan?
        let safety: SafetyDecision?
        let sidecar: Sidecar
    }

    struct ScanSummary: Decodable, Equatable {
        let id: String
        let moduleId: String
        let status: String
        let startedAt: String
        let completedAt: String?
        let summary: ScanSummaryMetrics
        let metadata: ScanMetadata
        let candidateCount: Int
        let actionPlanCount: Int
    }

    struct ScanSummaryMetrics: Decodable, Equatable {
        let totalCandidates: Int?
        let totalSizeBytes: Int?
        let destructiveActions: Int?
    }

    struct ScanMetadata: Decodable, Equatable {
        let homeDir: String?
        let modules: [String]?
    }

    struct PersistedCandidate: Decodable, Equatable {
        let id: String
        let routeId: String
        let path: String
        let action: String
        let selection: String
        let confidence: Double
        let sizeBytes: Int?
        let evidence: [String]
        let warnings: [String]
        let metadata: PersistedCandidateMetadata
    }

    struct PersistedCandidateMetadata: Decodable, Equatable {
        let displayName: String?
        let groupId: String?
        let moduleId: String?
    }

    struct FinalizerPreview: Decodable, Equatable {
        let version: Int
        let status: String
        let createdAt: String
        let sourcePlanId: String
        let willExecute: Bool
        let receiptIssued: Bool
        let executionAuthority: String
        let actions: [FinalizerActionPreview]
        let summary: FinalizerPreviewSummary
        let safety: SafetyDecision
        let sidecar: Sidecar
        let executionPolicy: ExecutionPolicy
    }

    struct FinalizerActionPreview: Decodable, Equatable {
        let id: String
        let candidateId: String
        let routeId: String
        let path: String
        let displayName: String
        let action: String
        let selection: String
        let destructive: Bool
        let executionAuthority: String
        let requiresHumanConfirmation: Bool
        let blockedForAgents: Bool
        let rollback: FinalizerRollback
        let audit: FinalizerAudit
        let warnings: [String]
    }

    struct FinalizerRollback: Decodable, Equatable {
        let level: String
        let notes: String
    }

    struct FinalizerAudit: Decodable, Equatable {
        let event: String
        let receiptRequired: Bool
        let receiptStatus: String
    }

    struct FinalizerPreviewSummary: Decodable, Equatable {
        let totalCandidates: Int
        let destructiveCandidates: Int
        let blockedForAgents: Int
        let receiptsIssued: Int
    }

    private struct Envelope<T: Decodable>: Decodable {
        let data: T
    }

    private struct ProcessContext {
        let executableURL: URL
        let cliScriptURL: URL
        let workspaceURL: URL
        let environment: [String: String]
    }

    private static let maxReportEnvelopeBytes = 1_048_576

    private let runner: CommandRunner

    init(runner: CommandRunner? = nil) {
        self.runner = runner ?? CommandRunner { args in
            try await Self.runClawJS(args: args)
        }
    }

    func loadReport() async throws -> Report {
        let result = try await runner.run(["mac-care", "report", "--json"])
        return try Self.decode(result, fallbackMessage: "mac care report failed")
    }

    func listScans() async throws -> ScanList {
        let result = try await runner.run(["mac-care", "scans", "list", "--json"])
        return try Self.decode(result, fallbackMessage: "mac care scan history failed")
    }

    func loadScan(id: String) async throws -> ScanDetail {
        let result = try await runner.run(["mac-care", "scans", "show", id, "--json"])
        return try Self.decode(result, fallbackMessage: "mac care scan detail failed")
    }

    func previewFinalizer(actionPlan: ActionPlan) async throws -> FinalizerPreview {
        let planFileURL = try Self.writeTemporaryActionPlan(actionPlan)
        defer {
            try? FileManager.default.removeItem(at: planFileURL)
        }
        let result = try await runner.run(["mac-care", "finalizer", "preview", "--plan-file", planFileURL.path, "--json"])
        return try Self.decode(result, fallbackMessage: "mac care finalizer preview failed")
    }

    private static func decode<T: Decodable>(_ result: CommandResult, fallbackMessage: String) throws -> T {
        guard result.exitCode == 0 else {
            let message = String(data: result.data, encoding: .utf8) ?? fallbackMessage
            throw NSError(domain: "ClawJSMacCareClient", code: Int(result.exitCode), userInfo: [
                NSLocalizedDescriptionKey: message.trimmingCharacters(in: .whitespacesAndNewlines)
            ])
        }
        guard result.data.count <= Self.maxReportEnvelopeBytes else {
            throw NSError(domain: "ClawJSMacCareClient", code: 413, userInfo: [
                NSLocalizedDescriptionKey: "mac care report envelope exceeded the bounded decode budget"
            ])
        }
        // hot-path-ok maxBytes=1048576 reason=mac care commands return one bounded JSON envelope
        return try JSONDecoder().decode(Envelope<T>.self, from: result.data).data
    }

    private static func writeTemporaryActionPlan(_ actionPlan: ActionPlan) throws -> URL {
        let directoryURL = ClawJSMacCareRoutes.finalizerActionPlanDirectory()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = ClawJSMacCareRoutes.finalizerActionPlanURL()
        let data = try JSONEncoder().encode(actionPlan)
        try data.write(to: fileURL, options: [.atomic])
        return fileURL
    }

    private static func runClawJS(args: [String]) async throws -> CommandResult {
        let context = await MainActor.run {
            ProcessContext(
                executableURL: ClawJSRuntime.nodeBinaryURL,
                cliScriptURL: ClawJSRuntime.cliScriptURL,
                workspaceURL: ClawJSServiceManager.workspaceURL,
                environment: ClawJSServiceManager.cliEnvironment()
            )
        }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    continuation.resume(returning: try runClawJSSynchronously(args: args, context: context))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    nonisolated private static func runClawJSSynchronously(args: [String], context: ProcessContext) throws -> CommandResult {
        guard ClawJSRuntime.isAvailable else {
            throw NSError(domain: "ClawJSMacCareClient", code: 1, userInfo: [
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
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationStatus == 0 {
            return CommandResult(data: data, exitCode: 0)
        }
        return CommandResult(data: err.isEmpty ? data : err, exitCode: process.terminationStatus)
    }
}
