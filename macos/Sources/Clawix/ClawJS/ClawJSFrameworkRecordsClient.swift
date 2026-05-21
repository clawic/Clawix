import Foundation

@MainActor
struct ClawJSFrameworkRecordsClient {
    struct CommandRunner {
        var run: ([String]) throws -> Data
    }

    struct AsyncCommandRunner {
        var run: ([String]) async throws -> Data
    }

    struct SnippetRecord: Decodable, Equatable {
        let id: String
        let slug: String
        let kind: String
        let title: String
        let body: String
        let shortcut: String?
        let metadata: [String: String]?
    }

    struct ProviderRoute: Decodable, Equatable {
        let id: String
        let feature: String
        let capability: String
        let provider: String
        let model: String?
        let accountRef: String?
    }

    struct ProviderSetting: Decodable, Equatable {
        let id: String
        let provider: String
        let enabled: Bool

        private enum CodingKeys: String, CodingKey {
            case id
            case provider
            case enabled
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            provider = try container.decode(String.self, forKey: .provider)
            if let bool = try? container.decode(Bool.self, forKey: .enabled) {
                enabled = bool
            } else {
                let intValue = (try? container.decode(Int.self, forKey: .enabled)) ?? 1
                enabled = intValue != 0
            }
        }
    }

    struct SkillRecord: Decodable, Equatable {
        let id: String
        let slug: String
        let kind: String
        let name: String
        let body: String
        let metadata: [String: SkillJSONValue]?
    }

    private struct ListResponse<T: Decodable>: Decodable {
        let items: [T]
    }

    private struct Envelope<T: Decodable>: Decodable {
        let data: T
    }

    static let shared = ClawJSFrameworkRecordsClient()

    private let runner: CommandRunner
    private let asyncRunner: AsyncCommandRunner

    init(runner: CommandRunner? = nil, asyncRunner: AsyncCommandRunner? = nil) {
        let resolvedRunner = runner ?? CommandRunner { args in
            try Self.runClawJS(args: args)
        }
        self.runner = resolvedRunner
        self.asyncRunner = asyncRunner ?? AsyncCommandRunner { args in
            if runner != nil {
                return try resolvedRunner.run(args)
            }
            return try await Self.runClawJSAsync(args: args)
        }
    }

    func listSnippets(kind: String) throws -> [SnippetRecord] {
        let data = try runner.run(["snippets", "list", "--kind", kind, "--json"])
        return try JSONDecoder().decode(Envelope<ListResponse<SnippetRecord>>.self, from: data).data.items
    }

    func upsertSnippet(
        id: String,
        slug: String,
        kind: String,
        title: String,
        body: String,
        shortcut: String? = nil,
        metadata: [String: String] = [:]
    ) throws {
        var args = [
            "snippets", "upsert", slug,
            "--id", id,
            "--kind", kind,
            "--title", title,
            "--body", body,
            "--json",
        ]
        if let shortcut, !shortcut.isEmpty {
            args += ["--shortcut", shortcut]
        }
        if !metadata.isEmpty,
           let data = try? JSONEncoder().encode(metadata),
           let json = String(data: data, encoding: .utf8) {
            args += ["--metadata", json]
        }
        _ = try runner.run(args)
    }

    func deleteSnippet(slug: String) throws {
        _ = try runner.run(["snippets", "delete", slug, "--json"])
    }

    func listSkillRecords(kind: String? = nil) throws -> [SkillRecord] {
        var args = ["skills", "list", "--json"]
        if let kind, !kind.isEmpty {
            args += ["--kind", kind]
        }
        let data = try runner.run(args)
        return try Self.decoder.decode(Envelope<ListResponse<SkillRecord>>.self, from: data).data.items
    }

    func getSkillRecord(slug: String) throws -> SkillRecord? {
        let data = try runner.run(["skills", "get", slug, "--json"])
        return try Self.decoder.decode(Envelope<SkillRecord?>.self, from: data).data
    }

    func upsertSkillRecord(
        slug: String,
        name: String,
        kind: String,
        body: String,
        metadata: [String: SkillJSONValue] = [:]
    ) throws {
        var args = [
            "skills", "upsert", slug,
            "--name", name,
            "--kind", kind,
            "--body", body,
            "--json",
        ]
        if !metadata.isEmpty {
            args += ["--metadata", try Self.json(metadata)]
        }
        _ = try runner.run(args)
    }

    func deleteSkillRecord(slug: String) throws {
        _ = try runner.run(["skills", "delete", slug, "--json"])
    }

    func listAgents() throws -> [Agent] {
        let data = try runner.run(["agents", "list", "--for-host", "true", "--json"])
        return try Self.decoder.decode(Envelope<ListResponse<Agent>>.self, from: data).data.items
    }

    func listAgentsAsync() async throws -> [Agent] {
        let data = try await asyncRunner.run(["agents", "list", "--for-host", "true", "--json"])
        return try Self.decoder.decode(Envelope<ListResponse<Agent>>.self, from: data).data.items
    }

    func getSkillRecordAsync(slug: String) async throws -> SkillRecord? {
        let data = try await asyncRunner.run(["skills", "get", slug, "--json"])
        return try Self.decoder.decode(Envelope<SkillRecord?>.self, from: data).data
    }

    func upsertAgent(_ agent: Agent) throws {
        _ = try runner.run(["agents", "upsert", agent.id, "--record", try Self.json(agent), "--for-host", "true", "--json"])
    }

    func upsertAgentAsync(_ agent: Agent) async throws {
        _ = try await asyncRunner.run(["agents", "upsert", agent.id, "--record", try Self.json(agent), "--for-host", "true", "--json"])
    }

    func deleteAgent(id: String) throws {
        _ = try runner.run(["agents", "delete", id, "--for-host", "true", "--json"])
    }

    func deleteAgentAsync(id: String) async throws {
        _ = try await asyncRunner.run(["agents", "delete", id, "--for-host", "true", "--json"])
    }

    func listPersonalities() throws -> [AgentPersonality] {
        let data = try runner.run(["personalities", "list", "--for-host", "true", "--json"])
        return try Self.decoder.decode(Envelope<ListResponse<AgentPersonality>>.self, from: data).data.items
    }

    func listPersonalitiesAsync() async throws -> [AgentPersonality] {
        let data = try await asyncRunner.run(["personalities", "list", "--for-host", "true", "--json"])
        return try Self.decoder.decode(Envelope<ListResponse<AgentPersonality>>.self, from: data).data.items
    }

    func upsertPersonality(_ personality: AgentPersonality) throws {
        _ = try runner.run(["personalities", "upsert", personality.id, "--record", try Self.json(personality), "--for-host", "true", "--json"])
    }

    func upsertPersonalityAsync(_ personality: AgentPersonality) async throws {
        _ = try await asyncRunner.run(["personalities", "upsert", personality.id, "--record", try Self.json(personality), "--for-host", "true", "--json"])
    }

    func deletePersonality(id: String) throws {
        _ = try runner.run(["personalities", "delete", id, "--for-host", "true", "--json"])
    }

    func deletePersonalityAsync(id: String) async throws {
        _ = try await asyncRunner.run(["personalities", "delete", id, "--for-host", "true", "--json"])
    }

    func listSkillCollections() throws -> [SkillCollection] {
        let data = try runner.run(["skill-collections", "list", "--for-host", "true", "--json"])
        return try Self.decoder.decode(Envelope<ListResponse<SkillCollection>>.self, from: data).data.items
    }

    func listSkillCollectionsAsync() async throws -> [SkillCollection] {
        let data = try await asyncRunner.run(["skill-collections", "list", "--for-host", "true", "--json"])
        return try Self.decoder.decode(Envelope<ListResponse<SkillCollection>>.self, from: data).data.items
    }

    func upsertSkillCollection(_ collection: SkillCollection) throws {
        _ = try runner.run(["skill-collections", "upsert", collection.id, "--record", try Self.json(collection), "--for-host", "true", "--json"])
    }

    func upsertSkillCollectionAsync(_ collection: SkillCollection) async throws {
        _ = try await asyncRunner.run(["skill-collections", "upsert", collection.id, "--record", try Self.json(collection), "--for-host", "true", "--json"])
    }

    func deleteSkillCollection(id: String) throws {
        _ = try runner.run(["skill-collections", "delete", id, "--for-host", "true", "--json"])
    }

    func deleteSkillCollectionAsync(id: String) async throws {
        _ = try await asyncRunner.run(["skill-collections", "delete", id, "--for-host", "true", "--json"])
    }

    func listConnections() throws -> [Connection] {
        let data = try runner.run(["connections", "list", "--for-host", "true", "--json"])
        return try Self.decoder.decode(Envelope<ListResponse<Connection>>.self, from: data).data.items
    }

    func listConnectionsAsync() async throws -> [Connection] {
        let data = try await asyncRunner.run(["connections", "list", "--for-host", "true", "--json"])
        return try Self.decoder.decode(Envelope<ListResponse<Connection>>.self, from: data).data.items
    }

    func upsertConnection(_ connection: Connection, secretRef: String? = nil) throws {
        _ = try runner.run(["connections", "upsert", connection.id, "--record", try Self.connectionJson(connection, secretRef: secretRef), "--for-host", "true", "--json"])
    }

    func upsertConnectionAsync(_ connection: Connection, secretRef: String? = nil) async throws {
        _ = try await asyncRunner.run(["connections", "upsert", connection.id, "--record", try Self.connectionJson(connection, secretRef: secretRef), "--for-host", "true", "--json"])
    }

    func deleteConnection(id: String) throws {
        _ = try runner.run(["connections", "delete", id, "--for-host", "true", "--json"])
    }

    func deleteConnectionAsync(id: String) async throws {
        _ = try await asyncRunner.run(["connections", "delete", id, "--for-host", "true", "--json"])
    }

    func listProviderRoutes() throws -> [ProviderRoute] {
        let data = try runner.run(["providers", "routing", "list", "--json"])
        return try JSONDecoder().decode(Envelope<ListResponse<ProviderRoute>>.self, from: data).data.items
    }

    func setProviderRoute(
        feature: String,
        capability: String,
        provider: String,
        model: String,
        accountRef: String
    ) throws {
        _ = try runner.run([
            "providers", "routing", "set", feature,
            "--capability", capability,
            "--provider", provider,
            "--model", model,
            "--account-ref", accountRef,
            "--json",
        ])
    }

    func deleteProviderRoute(feature: String, capability: String) throws {
        _ = try runner.run([
            "providers", "routing", "delete", feature,
            "--capability", capability,
            "--json",
        ])
    }

    func listProviderSettings() throws -> [ProviderSetting] {
        let data = try runner.run(["providers", "settings", "list", "--json"])
        return try JSONDecoder().decode(Envelope<ListResponse<ProviderSetting>>.self, from: data).data.items
    }

    func setProviderEnabled(_ provider: String, enabled: Bool) throws {
        _ = try runner.run([
            "providers", "settings", "set", provider,
            "--enabled", enabled ? "true" : "false",
            "--json",
        ])
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static func json<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func connectionJson(_ connection: Connection, secretRef: String?) throws -> String {
        let data = try encoder.encode(connection)
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8) ?? "{}"
        }
        if let secretRef {
            object["secretRef"] = secretRef
        }
        let merged = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: merged, encoding: .utf8) ?? "{}"
    }

    @MainActor
    private static func runClawJS(args: [String]) throws -> Data {
        guard ClawJSRuntime.isAvailable else {
            throw NSError(domain: "ClawJSFrameworkRecordsClient", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "ClawJS bundle is not available in this build."
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
            let message = String(data: err.isEmpty ? data : err, encoding: .utf8) ?? "claw framework records failed"
            throw NSError(domain: "ClawJSFrameworkRecordsClient", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: message.trimmingCharacters(in: .whitespacesAndNewlines)
            ])
        }
        return data
    }

    private static func runClawJSAsync(args: [String]) async throws -> Data {
        let context = await MainActor.run {
            FrameworkRecordsProcessContext(
                executableURL: ClawJSRuntime.nodeBinaryURL,
                cliScriptURL: ClawJSRuntime.cliScriptURL,
                workspaceURL: ClawJSServiceManager.workspaceURL,
                environment: ClawJSServiceManager.cliEnvironment()
            )
        }
        let cancellation = FrameworkRecordsProcessCancellation()
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
        context: FrameworkRecordsProcessContext,
        cancellation: FrameworkRecordsProcessCancellation
    ) throws -> Data {
        guard ClawJSRuntime.isAvailable else {
            throw NSError(domain: "ClawJSFrameworkRecordsClient", code: 1, userInfo: [
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
        guard cancellation.attach(process) else {
            throw CancellationError()
        }
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if cancellation.isCancelled {
            throw CancellationError()
        }
        guard process.terminationStatus == 0 else {
            let message = String(data: err.isEmpty ? data : err, encoding: .utf8) ?? "claw framework records failed"
            throw NSError(domain: "ClawJSFrameworkRecordsClient", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: message.trimmingCharacters(in: .whitespacesAndNewlines)
            ])
        }
        return data
    }
}

private struct FrameworkRecordsProcessContext: Sendable {
    let executableURL: URL
    let cliScriptURL: URL
    let workspaceURL: URL
    let environment: [String: String]
}

private final class FrameworkRecordsProcessCancellation: @unchecked Sendable {
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
        let process = process
        lock.unlock()
        process?.terminate()
    }
}
