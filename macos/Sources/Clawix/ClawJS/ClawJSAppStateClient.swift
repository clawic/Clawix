import Foundation

struct ClawJSAppStateSidebarSnapshot: Codable, Sendable {
    let threadId: String
    let chatUuid: String
    let title: String
    let cwd: String?
    let projectId: String?
    let projectPath: String?
    let updatedAt: String
    let archived: Bool
    let pinned: Bool
}

struct ClawJSAppStateSnapshot: Decodable, Sendable {
    struct Project: Decodable, Sendable {
        let id: String
        let resourceId: String?
        let name: String
        let path: String
        let sortOrder: Int64?
    }

    struct PinnedThread: Decodable, Sendable {
        let threadId: String
        let sortOrder: Int64
        let pinnedAt: String?
    }

    struct Title: Decodable, Sendable {
        let threadId: String
        let title: String
        let source: String
        let updatedAt: String?
    }

    struct Archive: Decodable, Sendable {
        let threadId: String
        let archivedAt: String?
    }

    struct Sidebar: Decodable, Sendable {
        let threadId: String
        let chatUuid: String
        let title: String
        let cwd: String?
        let projectId: String?
        let projectPath: String?
        let updatedAt: String?
        let archived: Int
        let pinned: Int
    }

    struct TerminalTab: Decodable, Sendable {
        let id: String
        let title: String
        let cwd: String?
        let sortOrder: Int
        let createdAt: String?
        let metadata: [String: String]?
    }

    let projects: [Project]
    let pinnedThreads: [PinnedThread]
    let titles: [Title]
    let archives: [Archive]
    let sidebar: [Sidebar]
    let terminalTabs: [TerminalTab]
}

@MainActor
enum ClawJSAppStateClient {
    static func upsertProject(id: String, resourceId: String? = nil, name: String, path: String, sortOrder: Int64? = nil) {
        ClawJSAppStateSyncCoordinator.shared.enqueue(ClawJSAppStateOperation(
            kind: "project.upsert",
            id: id,
            resourceId: resourceId,
            name: name,
            path: path,
            sortOrder: sortOrder
        ))
    }

    static func registerProjectResource(id: String, path: String, label: String) {
        guard !id.isEmpty, !path.isEmpty else { return }
        runResourceBestEffort(["resources", "register", path, "--id", id, "--kind", "project", "--label", label, "--json"])
    }

    static func deleteProject(id: String) {
        ClawJSAppStateSyncCoordinator.shared.enqueue(ClawJSAppStateOperation(kind: "project.delete", id: id))
    }

    static func setProjectOrder(_ projectIds: [String]) {
        ClawJSAppStateSyncCoordinator.shared.enqueue(ClawJSAppStateOperation(kind: "project.order", ids: projectIds))
    }

    static func upsertPin(threadId: String, sortOrder: Int64) {
        ClawJSAppStateSyncCoordinator.shared.enqueue(ClawJSAppStateOperation(kind: "pin.upsert", sortOrder: sortOrder, threadId: threadId))
    }

    static func deletePin(threadId: String) {
        ClawJSAppStateSyncCoordinator.shared.enqueue(ClawJSAppStateOperation(kind: "pin.delete", threadId: threadId))
    }

    static func setPinOrder(_ threadIds: [String]) {
        ClawJSAppStateSyncCoordinator.shared.enqueue(ClawJSAppStateOperation(kind: "pin.order", threadIds: threadIds))
    }

    static func upsertTitle(threadId: String, title: String, source: String) {
        ClawJSAppStateSyncCoordinator.shared.enqueue(ClawJSAppStateOperation(
            kind: "title.upsert",
            threadId: threadId,
            title: title,
            source: source
        ))
    }

    static func archive(threadId: String) {
        ClawJSAppStateSyncCoordinator.shared.enqueue(ClawJSAppStateOperation(kind: "archive.set", threadId: threadId))
    }

    static func unarchive(threadId: String) {
        ClawJSAppStateSyncCoordinator.shared.enqueue(ClawJSAppStateOperation(kind: "archive.delete", threadId: threadId))
    }

    static func upsertSidebarSnapshot(
        threadId: String,
        chatUuid: String,
        title: String,
        cwd: String?,
        projectId: String?,
        projectPath: String?,
        updatedAt: Int64,
        archived: Bool,
        pinned: Bool
    ) {
        ClawJSAppStateSyncCoordinator.shared.enqueue(ClawJSAppStateOperation(
            kind: "sidebar.upsert",
            threadId: threadId,
            title: title,
            chatUuid: chatUuid,
            cwd: cwd,
            projectId: projectId,
            projectPath: projectPath,
            updatedAt: isoString(seconds: updatedAt),
            archived: archived,
            pinned: pinned
        ))
    }

    static func replaceSidebarSnapshots(_ snapshots: [ClawJSAppStateSidebarSnapshot]) {
        ClawJSAppStateSyncCoordinator.shared.enqueue(ClawJSAppStateOperation(kind: "sidebar.replace", items: snapshots))
    }

    static func upsertTerminalTab(
        id: String,
        title: String,
        cwd: String,
        sortOrder: Int,
        metadata: [String: String] = [:]
    ) {
        ClawJSAppStateSyncCoordinator.shared.enqueue(ClawJSAppStateOperation(
            kind: "terminal.upsert",
            id: id,
            sortOrder: Int64(sortOrder),
            title: title,
            cwd: cwd,
            metadata: metadata
        ))
    }

    static func deleteTerminalTab(id: String) {
        ClawJSAppStateSyncCoordinator.shared.enqueue(ClawJSAppStateOperation(kind: "terminal.delete", id: id))
    }

    static func snapshot(allowCLIFallback: Bool = false) async throws -> ClawJSAppStateSnapshot {
        try await ClawJSAppStateSyncCoordinator.shared.projection(allowCLIFallback: allowCLIFallback)
    }

    private static func runResourceBestEffort(_ args: [String]) {
        guard ClawJSRuntime.isAvailable else { return }
        let nodeURL = ClawJSRuntime.nodeBinaryURL
        let cliScriptPath = ClawJSRuntime.cliScriptURL.path
        let workspaceURL = ClawJSServiceManager.workspaceURL
        let environment = ClawJSServiceManager.cliEnvironment()
        Task.detached {
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
                // Local SQLite remains a disposable cache. Failed mirroring is
                // retried by the next user mutation or app-state refresh.
            }
        }
    }

    private static func isoString(seconds: Int64) -> String {
        ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
    }
}
