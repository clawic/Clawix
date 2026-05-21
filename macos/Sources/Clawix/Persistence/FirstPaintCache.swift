import Foundation

enum FirstPaintCache {
    struct Payload: Codable, Equatable {
        var version: Int
        var projects: [ProjectItem]
        var chats: [ChatItem]
        var pinnedThreadIds: [String]
        var projectPathHints: [String]
    }

    struct ProjectItem: Codable, Equatable {
        var id: String
        var resourceId: String?
        var name: String
        var path: String
    }

    struct ChatItem: Codable, Equatable {
        var threadId: String
        var chatUuid: String
        var title: String
        var cwd: String?
        var projectId: String?
        var projectPath: String?
        var updatedAt: Int64
        var pinned: Bool
    }

    private static let version = 1
    private static let fileName = "first-paint-cache.json"
    private static let maxChats = 500
    private static let maxProjectHints = 500

    static var fileURLOverride: URL?

    static func load() -> Payload? {
        load(from: fileURL())
    }

    static func load(from url: URL?) -> Payload? {
        guard let url,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.version == version
        else { return nil }
        return payload
    }

    static func save(chats: [Chat], projects: [Project], pinnedOrder: [UUID]) {
        let projectsById = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        let threadByChatId = Dictionary(uniqueKeysWithValues: chats.compactMap { chat in
            chat.clawixThreadId.map { (chat.id, $0) }
        })
        let pinnedThreadIds = pinnedOrder.compactMap { threadByChatId[$0] }
        let activeChats = chats
            .filter { !$0.isArchived && $0.clawixThreadId != nil }
            .sorted { ($0.lastMessageAt ?? $0.createdAt) > ($1.lastMessageAt ?? $1.createdAt) }
            .prefix(maxChats)
        let chatItems = activeChats.compactMap { chat -> ChatItem? in
            guard let threadId = chat.clawixThreadId else { return nil }
            let project = chat.projectId.flatMap { projectsById[$0] }
            return ChatItem(
                threadId: threadId,
                chatUuid: chat.id.uuidString,
                title: chat.title,
                cwd: chat.cwd,
                projectId: chat.projectId?.uuidString,
                projectPath: project?.path,
                updatedAt: Int64((chat.lastMessageAt ?? chat.createdAt).timeIntervalSince1970),
                pinned: chat.isPinned
            )
        }
        let hints = Array(Set(chatItems.compactMap(\.projectPath)).sorted().prefix(maxProjectHints))
        let payload = Payload(
            version: version,
            projects: projects.map(ProjectItem.init(project:)),
            chats: chatItems,
            pinnedThreadIds: pinnedThreadIds,
            projectPathHints: hints
        )
        save(payload)
    }

    static func save(snapshot: ClawJSAppStateSnapshot) {
        let pinnedThreadIds = snapshot.pinnedThreads
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(\.threadId)
        let chatItems = snapshot.sidebar
            .filter { $0.archived == 0 }
            .sorted { epoch($0.updatedAt) > epoch($1.updatedAt) }
            .prefix(maxChats)
            .map { row in
                ChatItem(
                    threadId: row.threadId,
                    chatUuid: row.chatUuid,
                    title: row.title,
                    cwd: row.cwd,
                    projectId: row.projectId,
                    projectPath: row.projectPath,
                    updatedAt: epoch(row.updatedAt),
                    pinned: row.pinned != 0
                )
            }
        let hints = Array(Set(chatItems.compactMap(\.projectPath)).sorted().prefix(maxProjectHints))
        save(Payload(
            version: version,
            projects: snapshot.projects.map(ProjectItem.init(project:)),
            chats: chatItems,
            pinnedThreadIds: pinnedThreadIds,
            projectPathHints: hints
        ))
    }

    static func save(_ payload: Payload) {
        guard let url = fileURL(),
              let data = try? JSONEncoder().encode(payload)
        else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let tmp = url.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .atomic)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } catch {
            try? FileManager.default.removeItem(at: url.appendingPathExtension("tmp"))
        }
    }

    private static func fileURL() -> URL? {
        if let fileURLOverride { return fileURLOverride }
        return try? ClawixPersistentSurfacePaths.applicationSupportRoot()
            .appendingPathComponent(fileName, isDirectory: false)
    }

    private static func epoch(_ iso: String?) -> Int64 {
        guard let iso,
              let date = ISO8601DateFormatter().date(from: iso) else {
            return Int64(Date().timeIntervalSince1970)
        }
        return Int64(date.timeIntervalSince1970)
    }
}

private extension FirstPaintCache.ProjectItem {
    init(project: Project) {
        self.init(
            id: project.id.uuidString,
            resourceId: project.resourceId,
            name: project.name,
            path: project.path
        )
    }

    init(project: ClawJSAppStateSnapshot.Project) {
        self.init(
            id: project.id,
            resourceId: project.resourceId,
            name: project.name,
            path: project.path
        )
    }
}
