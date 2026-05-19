import Foundation

struct RootSearchQueryResponse: Decodable, Equatable {
    let ok: Bool
    let data: RootSearchQueryData
}

struct RootSearchQueryData: Decodable, Equatable {
    let query: String
    let profile: String
    let results: [RootSearchResult]
    let omittedSources: [RootSearchOmittedSource]?
}

struct RootSearchResult: Decodable, Equatable, Identifiable {
    let id: String
    let source: String
    let domain: String
    let type: String
    let title: String
    let subtitle: String?
    let snippet: String?
    let score: Double?
    let actions: [RootSearchAction]?
}

struct RootSearchAction: Decodable, Equatable {
    let id: String
    let kind: String
    let label: String
    let requiresApproval: Bool?
    let grant: String?
}

struct RootSearchOmittedSource: Decodable, Equatable {
    let source: String
    let reason: String
    let message: String?
}

struct RootSearchActionPlanResponse: Decodable, Equatable {
    let ok: Bool
    let data: RootSearchActionPlanData
}

struct RootSearchActionPlanData: Decodable, Equatable {
    let plan: SearchHostActionExecutionPlan
}

enum RootSearchQueryBridgeError: Error, LocalizedError {
    case emptyQuery
    case commandFailed(String)
    case invalidResponse
    case invalidActionPlan

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            return "Root Search query is empty."
        case .commandFailed(let message):
            return message
        case .invalidResponse:
            return "Root Search returned an invalid response."
        case .invalidActionPlan:
            return "Root Search returned an invalid action plan."
        }
    }
}

@MainActor
enum RootSearchQueryBridge {
    struct ClawSearchCommandRunner {
        var run: ([String]) throws -> Data
    }

    static func query(
        _ rawQuery: String,
        profile: String = "framework",
        limit: Int = 12,
        runner: ClawSearchCommandRunner? = nil
    ) throws -> RootSearchQueryResponse {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw RootSearchQueryBridgeError.emptyQuery }

        var args = [
            "search", "query", query,
            "--profile", profile,
            "--limit", String(limit),
            "--json",
        ]
        if profile == "full" {
            args.append(contentsOf: ["--include-disabled-sources"])
        }

        let output = try (runner ?? defaultRunner()).run(args)
        let response = try JSONDecoder().decode(RootSearchQueryResponse.self, from: output)
        guard response.ok else { throw RootSearchQueryBridgeError.invalidResponse }
        return response
    }

    static func actionPlan(
        resultId: String,
        actionId: String,
        actor: String = "user:clawix.root-search",
        surface: String = "clawix.root_search",
        runner: ClawSearchCommandRunner? = nil
    ) throws -> SearchHostActionExecutionPlan {
        let resultId = resultId.trimmingCharacters(in: .whitespacesAndNewlines)
        let actionId = actionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resultId.isEmpty, !actionId.isEmpty else {
            throw RootSearchQueryBridgeError.invalidActionPlan
        }

        let args = [
            "search", "actions", "execute", resultId, actionId,
            "--dry-run",
            "--actor", actor,
            "--surface", surface,
            "--json",
        ]
        let output = try (runner ?? defaultRunner()).run(args)
        let response = try JSONDecoder().decode(RootSearchActionPlanResponse.self, from: output)
        guard response.ok else { throw RootSearchQueryBridgeError.invalidActionPlan }
        return response.data.plan
    }

    static func actionPlanData(
        resultId: String,
        actionId: String,
        actor: String = "user:clawix.root-search",
        surface: String = "clawix.root_search",
        runner: ClawSearchCommandRunner? = nil
    ) throws -> Data {
        let plan = try actionPlan(
            resultId: resultId,
            actionId: actionId,
            actor: actor,
            surface: surface,
            runner: runner
        )
        return try JSONEncoder().encode(plan)
    }

    private static func defaultRunner() -> ClawSearchCommandRunner {
        let workspaceURL = MainActor.assumeIsolated { ClawJSServiceManager.workspaceURL }
        let environment = MainActor.assumeIsolated { ClawJSServiceManager.cliEnvironment() }
        return ClawSearchCommandRunner { args in
            guard FileManager.default.fileExists(atPath: ClawJSRuntime.cliScriptURL.path) else {
                throw RootSearchQueryBridgeError.commandFailed("ClawJS Search CLI is unavailable.")
            }

            let process = Process()
            process.executableURL = ClawJSRuntime.nodeBinaryURL
            process.arguments = [ClawJSRuntime.cliScriptURL.path] + args
            process.currentDirectoryURL = workspaceURL
            process.environment = environment

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()
            process.waitUntilExit()

            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            if process.terminationStatus != 0 {
                let err = stderr.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: err.isEmpty ? data : err, encoding: .utf8)
                    ?? "Root Search query failed."
                throw RootSearchQueryBridgeError.commandFailed(message)
            }
            return data
        }
    }
}
