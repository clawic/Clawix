import Foundation

@MainActor
struct ClawJSProjectHandoffClient {
    struct CommandRunner {
        var run: ([String]) throws -> Data
    }

    struct Attachment: Decodable, Equatable {
        let state: String
        let workspaceId: String?
        let detachedReason: String?
    }

    struct Manifest: Decodable, Equatable {
        let projectId: String
        let name: String
        let title: String
        let attachment: Attachment
    }

    struct Inspection: Decodable, Equatable {
        let state: String
        let warnings: [String]
        let manifest: Manifest?
    }

    struct AttachPreview: Decodable, Equatable {
        let accepted: Bool
        let warnings: [String]
        let manifest: Manifest
    }

    struct ImportPreview: Decodable, Equatable {
        let accepted: Bool
        let warnings: [String]
        let manifest: Manifest
        let handoffKind: String
    }

    private struct Envelope<T: Decodable>: Decodable {
        let data: T
    }

    nonisolated static let defaultWorkspaceId = "clawix-local"

    static let shared = ClawJSProjectHandoffClient()

    private let runner: CommandRunner

    init(runner: CommandRunner? = nil) {
        self.runner = runner ?? CommandRunner { args in
            try Self.runClawJS(args: args)
        }
    }

    func inspect(path: String, workspaceId: String = Self.defaultWorkspaceId) throws -> Inspection {
        let data = try runner.run(["project", "inspect", path, "--workspace-id", workspaceId, "--json"])
        return try JSONDecoder().decode(Envelope<Inspection>.self, from: data).data
    }

    @discardableResult
    func attach(project: Project, workspaceId: String = Self.defaultWorkspaceId, replaceDuplicate: Bool = false) throws -> AttachPreview {
        var args = [
            "project", "attach", project.path,
            "--workspace-id", workspaceId,
            "--project-id", project.resourceId ?? project.id.uuidString,
            "--name", project.name,
            "--accept",
            "--json",
        ]
        if replaceDuplicate {
            args += ["--replace"]
        }
        let data = try runner.run(args)
        return try JSONDecoder().decode(Envelope<AttachPreview>.self, from: data).data
    }

    func detach(path: String, reason: String = "detached_by_clawix") throws -> Manifest {
        let data = try runner.run(["project", "detach", path, "--reason", reason, "--json"])
        return try JSONDecoder().decode(Envelope<DetachResponse>.self, from: data).data.manifest
    }

    func syncHandoff(path: String) throws {
        _ = try runner.run(["project", "sync-handoff", path, "--json"])
    }

    func export(path: String, outputPath: String) throws {
        _ = try runner.run(["project", "export", path, "--output", outputPath, "--json"])
    }

    @discardableResult
    func importHandoff(handoffPath: String, projectPath: String, workspaceId: String = Self.defaultWorkspaceId, accept: Bool = true, replaceDuplicate: Bool = false) throws -> ImportPreview {
        var args = [
            "project", "import", handoffPath, projectPath,
            "--workspace-id", workspaceId,
            "--json",
        ]
        if accept {
            args += ["--accept"]
        }
        if replaceDuplicate {
            args += ["--replace"]
        }
        let data = try runner.run(args)
        return try JSONDecoder().decode(Envelope<ImportPreview>.self, from: data).data
    }

    static func syncProjectFolderBestEffort(_ project: Project, workspaceId: String = defaultWorkspaceId) {
        guard !project.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard ClawJSRuntime.isAvailable else { return }
        let args = [
            "project", "attach", project.path,
            "--workspace-id", workspaceId,
            "--project-id", project.resourceId ?? project.id.uuidString,
            "--name", project.name,
            "--accept",
            "--json",
        ]
        let nodeURL = ClawJSRuntime.nodeBinaryURL
        let cliScriptPath = ClawJSRuntime.cliScriptURL.path
        let workspaceURL = ClawJSServiceManager.workspaceURL
        let environment = ClawJSServiceManager.cliEnvironment()
        Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = nodeURL
            process.arguments = [cliScriptPath] + args
            process.currentDirectoryURL = workspaceURL
            process.environment = environment
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                // The local project row remains the UI source of truth.
                // The next edit or explicit handoff action retries.
            }
        }
    }

    private struct DetachResponse: Decodable {
        let manifest: Manifest
    }

    @MainActor
    private static func runClawJS(args: [String]) throws -> Data {
        guard ClawJSRuntime.isAvailable else {
            throw NSError(domain: "ClawJSProjectHandoffClient", code: 1, userInfo: [
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
            let message = String(data: err.isEmpty ? data : err, encoding: .utf8) ?? "claw project handoff failed"
            throw NSError(domain: "ClawJSProjectHandoffClient", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: message.trimmingCharacters(in: .whitespacesAndNewlines)
            ])
        }
        return data
    }
}
