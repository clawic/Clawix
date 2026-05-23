import Foundation

struct ClawJSRemoteProjectionSnapshot: Equatable {
    var conformanceStatus: String?
    var requiredRoutes: [RequiredRoute]
    var contractsStatus: String?
    var contracts: [Contract]
    var pendingStatus: String?
    var pendingRequirements: [PendingRequirement]
    var externalValidationReadiness: ExternalValidationReadiness?
    var providerDeviceE2EPlan: ProviderDeviceE2EPlan?
    var sourceCommands: [String]

    var missingRouteIds: [String] {
        requiredRoutes.filter { !$0.registered }.map(\.routeId)
    }

    var externalPendingCount: Int {
        pendingRequirements.filter { $0.status == "external_pending" }.count
    }

    var writesDeclared: Bool {
        contracts.contains { $0.writes == true } ||
            pendingRequirements.contains { $0.writes == true } ||
            externalValidationReadiness?.writes == true ||
            providerDeviceE2EPlan?.writesDeclared == true
    }

    var closureBlockers: [String] {
        externalValidationReadiness?.closureGateBlockers ?? []
    }

    var externalReadinessStatus: String {
        externalValidationReadiness?.status ?? "unknown"
    }

    var closureBlockersSummary: String {
        closureBlockers.isEmpty ? "none" : closureBlockers.joined(separator: ", ")
    }

    var blockedExternalRequirementSummary: String {
        let blocked = externalValidationReadiness?.blockedExternalRequirementIds?.count ?? externalPendingCount
        return "\(blocked) blocked"
    }

    var providerDeviceE2ESummary: String {
        guard let plan = providerDeviceE2EPlan else { return "unknown" }
        return "\(plan.validationSteps.count) steps / \(plan.requiredDomains.count) domains"
    }

    struct RequiredRoute: Decodable, Equatable {
        let routeId: String
        let registered: Bool
    }

    struct Contract: Decodable, Equatable {
        let routeId: String
        let layer: String?
        let capability: String?
        let parityRequired: Bool?
        let parallelApiAllowed: Bool?
        let writes: Bool?
    }

    struct PendingRequirement: Decodable, Equatable {
        let requirementId: String
        let decisionId: String?
        let category: String?
        let status: String?
        let writes: Bool?
    }

    struct ExternalValidationReadiness: Decodable, Equatable {
        let status: String?
        let sourceQaReady: Bool?
        let sourceQaReviewStatus: String?
        let externalEvidenceReady: Bool?
        let externalValidationStatus: String?
        let evidenceCount: Int?
        let requiredEvidenceCount: Int?
        let missingEvidenceRequirementIds: [String]?
        let blockedExternalRequirementIds: [String]?
        let runbookReady: Bool?
        let checklistReady: Bool?
        let e2ePlanReady: Bool?
        let validationStepCount: Int?
        let externalRequirementCount: Int?
        let closureGateStatus: String?
        let closureGateBlockers: [String]
        let requiredCommands: [String]?
        let nextAction: String?
        let writes: Bool?
    }

    struct ProviderDeviceE2EPlan: Decodable, Equatable {
        let status: String?
        let requiredDomains: [String]
        let requiredTopologyTargets: [String]
        let requiredRouteIds: [String]
        let requiredExternalPendingIds: [String]
        let validationSteps: [ValidationStep]
        let evidenceRefs: [String]?
        let approvedPhysicalValidationRequired: Bool?
        let noPlaintextSecrets: Bool?
        let plaintextMaterialIncluded: Bool?
        let hostedSelfHostedParityRequired: Bool?
        let writes: Bool?

        var writesDeclared: Bool {
            writes == true || validationSteps.contains { $0.writes == true }
        }

        struct ValidationStep: Decodable, Equatable {
            let domain: String
            let requiredRouteIds: [String]
            let requiredExternalPendingIds: [String]
            let requiredArtifacts: [String]?
            let acceptanceCriteria: [String]?
            let status: String?
            let writes: Bool?
        }
    }
}

struct ClawJSRemoteProjectionClient {
    struct CommandResult {
        let data: Data
        let exitCode: Int32
    }

    struct CommandRunner {
        var run: ([String]) async throws -> CommandResult
    }

    enum Error: Swift.Error, LocalizedError, Equatable {
        case unavailable(String)
        case commandFailed(command: String, exitCode: Int32, message: String)
        case envelopeTooLarge(command: String)
        case unsafeWritesDeclared

        var errorDescription: String? {
            switch self {
            case .unavailable(let message):
                return message
            case .commandFailed(let command, let exitCode, let message):
                return "\(command) failed with exit \(exitCode): \(message)"
            case .envelopeTooLarge(let command):
                return "\(command) exceeded the remote projection decode budget"
            case .unsafeWritesDeclared:
                return "Remote projection unexpectedly declared writes."
            }
        }
    }

    private struct InspectRemoteEnvelope: Decodable {
        let ok: Bool?
        let data: InspectRemoteData
    }

    private struct InspectRemoteData: Decodable {
        let conformance: Conformance?
        let externalValidationReadiness: ClawJSRemoteProjectionSnapshot.ExternalValidationReadiness?
        let providerDeviceE2EPlan: ClawJSRemoteProjectionSnapshot.ProviderDeviceE2EPlan?

        struct Conformance: Decodable {
            let status: String?
            let requiredRoutes: [ClawJSRemoteProjectionSnapshot.RequiredRoute]?
        }
    }

    private struct ContractsEnvelope: Decodable {
        let ok: Bool?
        let data: ContractsData
    }

    private struct ContractsData: Decodable {
        let status: String?
        let contracts: [ClawJSRemoteProjectionSnapshot.Contract]
        let writes: Bool?
    }

    private struct PendingEnvelope: Decodable {
        let ok: Bool?
        let data: PendingData
    }

    private struct PendingData: Decodable {
        let status: String?
        let requirements: [ClawJSRemoteProjectionSnapshot.PendingRequirement]
        let writes: Bool?
    }

    private static let inspectRemoteCommand = ["inspect", "remote", "--json"]
    private static let contractsCommand = ["remote", "contracts", "--json"]
    private static let pendingCommand = ["remote", "pending", "--json"]
    private static let maxRemoteProjectionEnvelopeBytes = 1_048_576

    private let runner: CommandRunner

    init(runner: CommandRunner? = nil) {
        self.runner = runner ?? CommandRunner { args in
            try await Self.runClawJS(args: args)
        }
    }

    func load() async throws -> ClawJSRemoteProjectionSnapshot {
        let inspect: InspectRemoteEnvelope = try await run(Self.inspectRemoteCommand)
        let contracts: ContractsEnvelope = try await run(Self.contractsCommand)
        let pending: PendingEnvelope = try await run(Self.pendingCommand)

        let snapshot = ClawJSRemoteProjectionSnapshot(
            conformanceStatus: inspect.data.conformance?.status,
            requiredRoutes: inspect.data.conformance?.requiredRoutes ?? [],
            contractsStatus: contracts.data.status,
            contracts: contracts.data.contracts,
            pendingStatus: pending.data.status,
            pendingRequirements: pending.data.requirements,
            externalValidationReadiness: inspect.data.externalValidationReadiness,
            providerDeviceE2EPlan: inspect.data.providerDeviceE2EPlan,
            sourceCommands: [
                Self.inspectRemoteCommand.joined(separator: " "),
                Self.contractsCommand.joined(separator: " "),
                Self.pendingCommand.joined(separator: " "),
            ]
        )
        if snapshot.writesDeclared || contracts.data.writes == true || pending.data.writes == true {
            throw Error.unsafeWritesDeclared
        }
        return snapshot
    }

    private func run<T: Decodable>(_ args: [String]) async throws -> T {
        let command = args.joined(separator: " ")
        let result = try await runner.run(args)
        guard result.exitCode == 0 else {
            let message = String(data: result.data, encoding: .utf8) ?? "remote projection command failed"
            throw Error.commandFailed(
                command: command,
                exitCode: result.exitCode,
                message: message.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        guard result.data.count <= Self.maxRemoteProjectionEnvelopeBytes else {
            throw Error.envelopeTooLarge(command: command)
        }
        // hot-path-ok maxBytes=1048576 reason=remote projection CLI returns bounded JSON envelopes
        return try JSONDecoder().decode(T.self, from: result.data)
    }

    private static func runClawJS(args: [String]) async throws -> CommandResult {
        let context = await MainActor.run {
            RemoteProjectionProcessContext(
                executableURL: ClawJSRuntime.nodeBinaryURL,
                cliScriptURL: ClawJSRuntime.cliScriptURL,
                workspaceURL: ClawJSServiceManager.workspaceURL,
                environment: ClawJSServiceManager.cliEnvironment()
            )
        }
        guard ClawJSRuntime.isAvailable else {
            throw Error.unavailable("ClawJS bundle is not available in this build.")
        }
        let result = try await ClawJSAsyncProcessRunner.run(
            executable: context.executableURL.path,
            arguments: [context.cliScriptURL.path] + args,
            currentDirectoryURL: context.workspaceURL,
            environment: context.environment,
            timeoutNanoseconds: 3_000_000_000
        )
        return CommandResult(data: result.standardOutput, exitCode: result.terminationStatus)
    }
}

private struct RemoteProjectionProcessContext: Sendable {
    let executableURL: URL
    let cliScriptURL: URL
    let workspaceURL: URL
    let environment: [String: String]
}

@MainActor
final class ClawJSRemoteProjectionStore: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case available(ClawJSRemoteProjectionSnapshot)
        case unavailable(String)
    }

    @Published private(set) var state: State = .idle

    private let client: ClawJSRemoteProjectionClient
    private var task: Task<Void, Never>?

    init(client: ClawJSRemoteProjectionClient = ClawJSRemoteProjectionClient()) {
        self.client = client
    }

    deinit {
        task?.cancel()
    }

    func load() {
        task?.cancel()
        state = .loading
        task = Task { [client, weak self] in
            do {
                let snapshot = try await client.load()
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.state = .available(snapshot)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.state = .unavailable(error.localizedDescription)
                }
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if case .loading = state {
            state = .idle
        }
    }
}
