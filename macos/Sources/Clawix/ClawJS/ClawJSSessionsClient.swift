import Foundation

struct ClawJSSessionsClient {

    enum Error: Swift.Error, LocalizedError {
        case serviceNotReady
        case invalidURL
        case http(status: Int, body: String?)
        case decoding(Swift.Error)
        case encoding(Swift.Error)
        case transport(Swift.Error)

        var errorDescription: String? {
            switch self {
            case .serviceNotReady: return "ClawJS sessions service is not running."
            case .invalidURL: return "Could not build a URL for the sessions service."
            case .http(let status, let body): return "Sessions returned HTTP \(status)" + (body.map { ": \($0)" } ?? "")
            case .decoding(let error): return "Could not decode sessions response: \(error.localizedDescription)"
            case .encoding(let error): return "Could not encode sessions request: \(error.localizedDescription)"
            case .transport(let error): return "Could not reach sessions service: \(error.localizedDescription)"
            }
        }
    }

    var bearerToken: String?
    let origin: URL
    let session: URLSession

    init(
        bearerToken: String? = nil,
        origin: URL = URL(string: "http://127.0.0.1:\(ClawJSService.sessions.port)")!,
        session: URLSession = .shared
    ) {
        self.bearerToken = bearerToken
        self.origin = origin
        self.session = session
    }

    @MainActor
    static func local() -> ClawJSSessionsClient {
        let token = ClawJSServiceManager.shared.adminTokenIfSpawned(for: .sessions)
            ?? (try? ClawJSServiceManager.adminTokenFromTokenFile(for: .sessions))
        return ClawJSSessionsClient(bearerToken: token)
    }

    struct HealthResponse: Decodable, Equatable {
        let ok: Bool
        let service: String
        let host: String
        let port: Int
    }

    struct Project: Codable, Identifiable, Equatable, Hashable {
        let id: String
        let resourceId: String?
        let displayName: String
        let path: String
        let hidden: Bool
        let archived: Bool
        let sortRank: Int
        let createdAt: Int64
        let updatedAt: Int64
    }

    struct SessionRecord: Codable, Identifiable, Equatable {
        let id: String
        let agent: String
        let runtime: String?
        let machine: String?
        let workspaceId: String?
        let projectId: String?
        let projectPath: String?
        let runtimeAdapter: String?
        let runtimeSessionId: String?
        let title: String
        let createdAt: Int64
        let lastMessageAt: Int64?
        let messageCount: Int
        let pinned: Bool
        let archived: Bool
        let sidebarVisible: Bool
        let branch: String?
        let cwd: String?
        let status: String
        let customMetadata: AnyJSON?
    }

    struct MessageRecord: Codable, Identifiable, Equatable {
        let id: String
        let sessionId: String
        let role: String
        let contentText: String
        let contentBlocks: [AnyJSON]?
        let timestamp: Int64
        let toolCalls: [AnyJSON]?
        let timeline: [AnyJSON]?
        let workSummary: AnyJSON?
        let streamingState: String?
        let audioRef: AudioRef?
        let attachments: [AnyJSON]?
        let sourceNativeId: String?
    }

    struct AudioRef: Codable, Equatable, Hashable {
        let id: String
        let mimeType: String
        let durationMs: Int
    }

    struct ListProjectsResponse: Decodable {
        let items: [Project]
        let total: Int
    }

    struct ListSessionsResponse: Decodable {
        let items: [SessionRecord]
        let total: Int
    }

    struct SidebarBootstrapResponse: Decodable, Equatable {
        let projects: [Project]
        let pinned: [SessionRecord]
        let recent: [SessionRecord]
        let totalActiveVisible: Int
    }

    struct MessagesResponse: Decodable {
        let items: [MessageRecord]
    }

    struct SearchResponse: Decodable {
        let items: [SearchHit]
    }

    struct SearchHit: Decodable, Equatable {
        let session: SessionRecord
        let message: MessageRecord
        let snippet: String
        let rank: Double
    }

    struct SessionWithMessages: Decodable {
        let session: SessionRecord
        let messages: [MessageRecord]
    }

    struct SessionTurnSummaryRecord: Decodable, Equatable {
        let sessionId: String
        let turnId: String
    }

    struct SessionProjectionMetaRecord: Decodable, Equatable {
        let sessionId: String
        let projectionStatus: String
    }

    struct SessionDynamicToolRecord: Decodable, Equatable {
        let sessionId: String
        let position: Int
        let name: String
        let namespace: String?
        let description: String
        let inputSchemaJson: AnyJSON?
        let schemaHash: String
        let deferLoading: Bool
        let source: String?
        let createdAt: Int64
        let updatedAt: Int64
    }

    struct HydratedSessionResult: Decodable, Equatable {
        let session: SessionRecord
        let messages: [MessageRecord]
        let messageOffset: Int
        let messageLimit: Int
        let hasOlderMessages: Bool
        let hasNewerMessages: Bool
        let turnSummaries: [SessionTurnSummaryRecord]
        let projectionMeta: SessionProjectionMetaRecord?
        let dynamicTools: [SessionDynamicToolRecord]
        let events: [AnyJSON]?
        let eventsLoaded: Bool
        let fallbackRequired: Bool
    }

    struct TurnResponse: Decodable {
        let session: SessionRecord?
        let userMessage: MessageRecord
        let assistantMessage: MessageRecord?
    }

    struct InterruptResponse: Decodable {
        let interrupted: Bool
        let session: SessionRecord
    }

    struct ImportCodexResponse: Decodable {
        struct Item: Decodable {
            let filePath: String
            let sessionId: String?
            let messagesImported: Int
            let skipped: Bool?
            let reason: String?
        }

        let scanned: Int
        let imported: [Item]
        let skipped: Int?
        let budgetExhausted: Bool?
        let changedFiles: Int?
    }

    enum CodexImportMode: String {
        case incremental
        case full
    }

    struct CreateProjectRequest: Encodable {
        let id: String?
        let resourceId: String?
        let displayName: String?
        let path: String
        let hidden: Bool?
        let archived: Bool?
        let sortRank: Int?
    }

    struct CreateSessionRequest: Encodable {
        let id: String?
        let agent: String
        let runtime: String?
        let runtimeAdapter: String?
        let runtimeSessionId: String?
        let projectId: String?
        let projectPath: String?
        let title: String?
        let cwd: String?
        let branch: String?
    }

    struct StartTurnRequest: Encodable {
        let prompt: String
        let projectId: String?
        let projectPath: String?
        let cwd: String?
        let title: String?
        let attachments: [AnyJSON]?
        let audioRef: AudioRef?
        let fixtureReply: String?
    }

    func probeHealth() async throws -> HealthResponse {
        try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/health", method: "GET", authenticated: false)
    }

    func listProjects(
        hidden: Bool? = nil,
        archived: Bool? = nil,
        limit: Int? = nil,
        offset: Int? = nil
    ) async throws -> [Project] {
        var items: [URLQueryItem] = []
        if let hidden { items.append(URLQueryItem(name: "hidden", value: hidden ? "true" : "false")) }
        if let archived { items.append(URLQueryItem(name: "archived", value: archived ? "true" : "false")) }
        if let limit { items.append(URLQueryItem(name: "limit", value: "\(limit)")) }
        if let offset { items.append(URLQueryItem(name: "offset", value: "\(offset)")) }
        let response: ListProjectsResponse = try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/projects", queryItems: items)
        return response.items
    }

    @discardableResult
    func createProject(_ input: CreateProjectRequest) async throws -> Project {
        try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/projects", method: "POST", body: input)
    }

    @discardableResult
    func updateProject(id: String, patch: [String: AnyJSON]) async throws -> Project {
        try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/projects/\(id)", method: "PATCH", body: patch)
    }

    func deleteProject(id: String) async throws {
        let _: EmptyResponse = try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/projects/\(id)", method: "DELETE")
    }

    func listSessions(
        projectId: String? = nil,
        projectPath: String? = nil,
        pinned: Bool? = nil,
        archived: Bool? = nil,
        sidebarVisible: Bool? = nil,
        limit: Int? = nil,
        offset: Int? = nil
    ) async throws -> [SessionRecord] {
        var items: [URLQueryItem] = []
        if let projectId { items.append(URLQueryItem(name: "projectId", value: projectId)) }
        if let projectPath { items.append(URLQueryItem(name: "projectPath", value: projectPath)) }
        if let pinned { items.append(URLQueryItem(name: "pinned", value: pinned ? "true" : "false")) }
        if let archived { items.append(URLQueryItem(name: "archived", value: archived ? "true" : "false")) }
        if let sidebarVisible { items.append(URLQueryItem(name: "sidebarVisible", value: sidebarVisible ? "true" : "false")) }
        if let limit { items.append(URLQueryItem(name: "limit", value: "\(limit)")) }
        if let offset { items.append(URLQueryItem(name: "offset", value: "\(offset)")) }
        let response: ListSessionsResponse = try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/sessions", queryItems: items)
        return response.items
    }

    func sidebarBootstrap(recentLimit: Int = 200) async throws -> SidebarBootstrapResponse {
        let response: SidebarBootstrapResponse = try await request(
            "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/sidebar/bootstrap",
            queryItems: [URLQueryItem(name: "recentLimit", value: "\(recentLimit)")]
        )
        return response
    }

    func getSession(id: String, includeMessages: Bool = false) async throws -> SessionWithMessages {
        let query = includeMessages ? [URLQueryItem(name: "includeMessages", value: "true")] : []
        if includeMessages {
            return try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/sessions/\(id)", queryItems: query)
        }
        let session: SessionRecord = try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/sessions/\(id)")
        return SessionWithMessages(session: session, messages: [])
    }

    func hydrateSession(
        id: String,
        messageLimit: Int? = nil,
        messageOffset: Int? = nil,
        recent: Bool? = true,
        summaryLimit: Int? = nil,
        includeEvents: Bool? = nil
    ) async throws -> HydratedSessionResult {
        var items: [URLQueryItem] = []
        if let messageLimit { items.append(URLQueryItem(name: "messageLimit", value: "\(messageLimit)")) }
        if let messageOffset { items.append(URLQueryItem(name: "messageOffset", value: "\(messageOffset)")) }
        if let recent { items.append(URLQueryItem(name: "recent", value: recent ? "true" : "false")) }
        if let summaryLimit { items.append(URLQueryItem(name: "summaryLimit", value: "\(summaryLimit)")) }
        if let includeEvents { items.append(URLQueryItem(name: "includeEvents", value: includeEvents ? "true" : "false")) }
        return try await request(
            "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/sessions/\(id)/hydrate",
            queryItems: items
        )
    }

    @discardableResult
    func createSession(_ input: CreateSessionRequest) async throws -> SessionRecord {
        try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/sessions", method: "POST", body: input)
    }

    @discardableResult
    func updateSession(id: String, patch: [String: AnyJSON]) async throws -> SessionRecord {
        try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/sessions/\(id)", method: "PATCH", body: patch)
    }

    func listMessages(sessionId: String, limit: Int? = nil, offset: Int? = nil) async throws -> [MessageRecord] {
        var items: [URLQueryItem] = []
        if let limit { items.append(URLQueryItem(name: "limit", value: "\(limit)")) }
        if let offset { items.append(URLQueryItem(name: "offset", value: "\(offset)")) }
        let response: MessagesResponse = try await request(
            "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/sessions/\(sessionId)/messages",
            queryItems: items
        )
        return response.items
    }

    func searchMessages(
        query: String,
        projectId: String? = nil,
        projectPath: String? = nil,
        limit: Int = 50
    ) async throws -> [SearchHit] {
        var items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        if let projectId { items.append(URLQueryItem(name: "projectId", value: projectId)) }
        if let projectPath { items.append(URLQueryItem(name: "projectPath", value: projectPath)) }
        let response: SearchResponse = try await request(
            "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/sessions/search",
            queryItems: items
        )
        return response.items
    }

    @discardableResult
    func importCodex(
        forceReimport: Bool = false,
        budgetMs: Int? = nil,
        maxFiles: Int? = nil,
        mode: CodexImportMode? = nil
    ) async throws -> ImportCodexResponse {
        struct Body: Encodable {
            let forceReimport: Bool?
            let budgetMs: Int?
            let maxFiles: Int?
            let mode: String?
        }
        return try await request(
            "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/sessions/import/codex",
            method: "POST",
            body: Body(
                forceReimport: forceReimport ? true : nil,
                budgetMs: budgetMs,
                maxFiles: maxFiles,
                mode: mode?.rawValue
            )
        )
    }

    @discardableResult
    func startTurn(sessionId: String, input: StartTurnRequest) async throws -> TurnResponse {
        try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/sessions/\(sessionId)/turns", method: "POST", body: input)
    }

    @discardableResult
    func interrupt(sessionId: String) async throws -> InterruptResponse {
        try await request("\(ClawixPersistentSurfaceKeys.publicApiPrefix)/sessions/\(sessionId)/interrupt", method: "POST", body: EmptyRequest())
    }

    func appStateProjection(limit: Int = 200, receiptLimit: Int = 20) async throws -> ClawJSAppStateSnapshot {
        try await request(
            "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/host/app-state/projection",
            queryItems: [
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "receiptLimit", value: String(receiptLimit)),
            ]
        )
    }

    @discardableResult
    func applyAppStateOperations(
        _ operations: [ClawJSAppStateOperation],
        requestId: String,
        hostId: String = "clawix"
    ) async throws -> ClawJSAppStateApplyResponse {
        try await request(
            "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/host/app-state/apply",
            method: "POST",
            body: AppStateApplyRequest(
                operations: operations,
                requestId: requestId,
                hostId: hostId
            )
        )
    }

    private func request<T: Decodable>(
        _ path: String,
        queryItems: [URLQueryItem] = [],
        method: String = "GET",
        body: Encodable? = nil,
        authenticated: Bool = true
    ) async throws -> T {
        guard let baseURL = URL(string: path, relativeTo: origin)?.absoluteURL,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw Error.invalidURL
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else { throw Error.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated {
            guard let bearerToken else { throw Error.serviceNotReady }
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            do {
                request.httpBody = try JSONEncoder().encode(AnyEncodable(body))
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            } catch {
                throw Error.encoding(error)
            }
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Error.transport(error)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Error.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw Error.decoding(error)
        }
    }

    private struct EmptyRequest: Encodable {}
    private struct EmptyResponse: Decodable {}

    private struct AppStateApplyRequest: Encodable {
        let operations: [ClawJSAppStateOperation]
        let requestId: String
        let hostId: String
    }
}

private struct AnyEncodable: Encodable {
    private let encodeBlock: (Encoder) throws -> Void

    init(_ value: Encodable) {
        self.encodeBlock = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeBlock(encoder)
    }
}
