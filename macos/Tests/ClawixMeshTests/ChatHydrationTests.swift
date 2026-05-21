import XCTest
@testable import Clawix

@MainActor
final class ChatHydrationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        setenv("CLAWIX_DISABLE_BACKEND", "1", 1)
        setenv("CLAWIX_BRIDGE_DISABLE", "1", 1)
        setenv("CLAWIX_DUMMY_MODE", "1", 1)
    }

    override func tearDown() {
        SessionsHistoryURLProtocol.handler = nil
        unsetenv("CLAWIX_DISABLE_BACKEND")
        unsetenv("CLAWIX_BRIDGE_DISABLE")
        unsetenv("CLAWIX_DUMMY_MODE")
        super.tearDown()
    }

    func testClawJSSessionHistoryRetriesWhileSessionsServiceStarts() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SessionsHistoryURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let origin = try XCTUnwrap(URL(string: "http://sessions.test"))
        var attempts = 0
        SessionsHistoryURLProtocol.handler = { request in
            attempts += 1
            if attempts < 3 {
                throw URLError(.cannotConnectToHost)
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = Data("""
            {
              "items": [
                {
                  "id": "msg-1",
                  "sessionId": "thread-1",
                  "role": "assistant",
                  "contentText": "Recovered history",
                  "timestamp": 1710000000000,
                  "streamingState": "finished"
                }
              ]
            }
            """.utf8)
            return (response, body)
        }

        let state = AppState()
        let chatId = UUID()
        state.currentRoute = .chat(chatId)
        state.chats = [
            Chat(
                id: chatId,
                title: "Thread",
                messages: [],
                createdAt: Date(),
                clawixThreadId: "thread-1",
                historyHydrated: false
            )
        ]
        state.sessionHistoryHydrationAttempts = 4
        state.sessionHistoryHydrationInitialDelayNanos = 1_000_000
        state.clawJSSessionsClientFactory = {
            ClawJSSessionsClient(bearerToken: "test-token", origin: origin, session: session)
        }

        state.hydrateHistoryIfNeeded(chatId: chatId)

        try await waitUntil {
            state.chats.first?.historyHydrated == true
        }

        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(state.chats.first?.messages.map(\.content), ["Recovered history"])
    }

    func testEmptyClawJSSessionHistoryFallsBackToCodexRollout() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SessionsHistoryURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let origin = try XCTUnwrap(URL(string: "http://sessions.test"))
        SessionsHistoryURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"{"items":[]}"#.utf8))
        }

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawix-chat-hydration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let rollout = tmp.appendingPathComponent("rollout-thread-1.jsonl")
        let lines = [
            #"{"timestamp":"2026-05-20T10:00:00.000Z","type":"session_meta","payload":{"id":"thread-1","cwd":"/tmp"}}"#,
            #"{"timestamp":"2026-05-20T10:00:01.000Z","type":"event_msg","payload":{"type":"user_message","message":"Original prompt"}}"#,
            #"{"timestamp":"2026-05-20T10:00:02.000Z","type":"event_msg","payload":{"type":"agent_message","message":"Fallback history","phase":"final_answer"}}"#
        ]
        try (lines.joined(separator: "\n") + "\n").write(to: rollout, atomically: true, encoding: .utf8)

        let state = AppState()
        let chatId = UUID()
        state.currentRoute = .chat(chatId)
        state.chats = [
            Chat(
                id: chatId,
                title: "Thread",
                messages: [],
                createdAt: Date(),
                clawixThreadId: "thread-1",
                historyHydrated: false
            )
        ]
        state.sessionHistoryHydrationInitialDelayNanos = 1_000_000
        state.clawJSSessionsClientFactory = {
            ClawJSSessionsClient(bearerToken: "test-token", origin: origin, session: session)
        }
        state.codexRolloutLocator = { threadId in
            threadId == "thread-1" ? rollout : nil
        }

        state.hydrateHistoryIfNeeded(chatId: chatId)

        try await waitUntil {
            state.chats.first?.historyHydrated == true
        }

        XCTAssertEqual(state.chats.first?.messages.map(\.content), ["Original prompt", "Fallback history"])
        XCTAssertEqual(state.chats.first?.rolloutPath, rollout)
    }

    func testClawJSSessionsStartupLoadsOnlyBoundedPinnedAndRecentSessions() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SessionsHistoryURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let origin = try XCTUnwrap(URL(string: "http://sessions.test"))
        var requests: [URLRequest] = []
        SessionsHistoryURLProtocol.handler = { request in
            requests.append(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            switch request.url?.path {
            case "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/health":
                return (response, Data(#"{"ok":true,"service":"sessions","host":"127.0.0.1","port":1}"#.utf8))
            case "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/sessions":
                let query = Self.queryItems(for: request)
                let isPinned = query["pinned"] == "true"
                let body = """
                {
                  "items": [
                    \(Self.sessionRecordJSON(
                        id: isPinned ? "pinned-thread" : "recent-thread",
                        title: isPinned ? "Pinned" : "Recent",
                        pinned: isPinned,
                        archived: false
                    ))
                  ],
                  "total": 1
                }
                """
                return (response, Data(body.utf8))
            default:
                let notFound = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
                return (notFound, Data(#"{"error":"unexpected"}"#.utf8))
            }
        }

        let state = AppState()
        state.clawJSSessionsClientFactory = {
            ClawJSSessionsClient(bearerToken: "test-token", origin: origin, session: session)
        }

        await state.loadThreadsFromRuntime()

        let projectRequests = requests.filter { $0.url?.path == "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/projects" }
        let sessionRequests = requests.filter { $0.url?.path == "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/sessions" }
        let bootstrapRequests = requests.filter { $0.url?.path == "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/sidebar/bootstrap" }
        let importRequests = requests.filter { $0.url?.path == "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/sessions/import/codex" }
        let archivedRequests = sessionRequests.filter { Self.queryItems(for: $0)["archived"] == "true" }
        XCTAssertTrue(projectRequests.isEmpty)
        XCTAssertTrue(importRequests.isEmpty)
        XCTAssertTrue(bootstrapRequests.isEmpty)
        XCTAssertTrue(archivedRequests.isEmpty)
        XCTAssertEqual(sessionRequests.count, 2)
        XCTAssertTrue(sessionRequests.contains { request in
            let query = Self.queryItems(for: request)
            return query["pinned"] == "true"
                && query["archived"] == "false"
                && query["sidebarVisible"] == "true"
                && query["limit"] == "\(AppState.startupPinnedSessionLimit)"
        })
        XCTAssertTrue(sessionRequests.contains { request in
            let query = Self.queryItems(for: request)
            return query["pinned"] == "false"
                && query["archived"] == "false"
                && query["sidebarVisible"] == "true"
                && query["limit"] == "\(AppState.startupRecentSessionLimit)"
        })
        XCTAssertEqual(state.chats.map(\.clawixThreadId), ["pinned-thread", "recent-thread"])
        XCTAssertEqual(state.pinnedOrder.compactMap { id in state.chats.first(where: { $0.id == id })?.clawixThreadId }, ["pinned-thread"])
    }

    func testDeferredCodexImportUsesBudgetAndRefreshesBoundedSessionsAfterChanges() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SessionsHistoryURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let origin = try XCTUnwrap(URL(string: "http://sessions.test"))
        var requests: [URLRequest] = []
        var importBodies: [String] = []
        var cacheRefreshCount = 0
        SessionsHistoryURLProtocol.handler = { request in
            requests.append(request)
            if request.url?.path == "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/sessions/import/codex" {
                importBodies.append(Self.bodyString(from: request))
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            switch request.url?.path {
            case "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/sessions/import/codex":
                return (response, Data(#"{"scanned":2,"imported":[],"skipped":1,"budgetExhausted":false,"changedFiles":1}"#.utf8))
            case "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/health":
                return (response, Data(#"{"ok":true,"service":"sessions","host":"127.0.0.1","port":1}"#.utf8))
            case "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/sessions":
                let query = Self.queryItems(for: request)
                let isPinned = query["pinned"] == "true"
                let body = """
                {
                  "items": [
                    \(Self.sessionRecordJSON(
                        id: isPinned ? "pinned-thread" : "recent-thread",
                        title: isPinned ? "Pinned" : "Recent",
                        pinned: isPinned,
                        archived: false
                    ))
                  ],
                  "total": 1
                }
                """
                return (response, Data(body.utf8))
            default:
                let notFound = HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!
                return (notFound, Data(#"{"error":"unexpected"}"#.utf8))
            }
        }

        let state = AppState()
        state.chats = []
        state.clawJSAppStateCacheRefresh = {
            cacheRefreshCount += 1
        }
        state.clawJSSessionsClientFactory = {
            ClawJSSessionsClient(bearerToken: "test-token", origin: origin, session: session)
        }

        await state.runDeferredCodexImport()

        let importRequest = try XCTUnwrap(requests.first { $0.url?.path == "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/sessions/import/codex" })
        XCTAssertEqual(importRequest.httpMethod, "POST")
        let importBody = try XCTUnwrap(importBodies.first)
        XCTAssertTrue(importBody.contains(#""budgetMs":400"#))
        XCTAssertTrue(importBody.contains(#""maxFiles":64"#))
        XCTAssertTrue(importBody.contains(#""mode":"incremental""#))
        XCTAssertEqual(cacheRefreshCount, 1)
        XCTAssertTrue(requests.filter { $0.url?.path == "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/sidebar/bootstrap" }.isEmpty)
        let sessionRequests = requests.filter { $0.url?.path == "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/sessions" }
        XCTAssertEqual(sessionRequests.count, 2)
        XCTAssertTrue(sessionRequests.contains { request in
            let query = Self.queryItems(for: request)
            return query["pinned"] == "true" && query["limit"] == "\(AppState.startupPinnedSessionLimit)"
        })
        XCTAssertTrue(sessionRequests.contains { request in
            let query = Self.queryItems(for: request)
            return query["pinned"] == "false" && query["limit"] == "\(AppState.startupRecentSessionLimit)"
        })
        XCTAssertEqual(state.chats.map(\.clawixThreadId), ["pinned-thread", "recent-thread"])
    }

    func testLegacyRuntimeFallbackLoadsOnlyOneRecentPage() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SessionsHistoryURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let origin = try XCTUnwrap(URL(string: "http://sessions.test"))
        SessionsHistoryURLProtocol.handler = { _ in
            throw URLError(.cannotConnectToHost)
        }

        let state = AppState()
        state.clawJSSessionsClientFactory = {
            ClawJSSessionsClient(bearerToken: "test-token", origin: origin, session: session)
        }
        var legacyRequests: [(cursor: String?, limit: Int)] = []
        state.runtimeThreadPageLoader = { cursor, limit in
            legacyRequests.append((cursor, limit))
            return ClawixService.ThreadListPage(
                threads: [
                    AgentThreadSummary(
                        id: "recent-thread",
                        cwd: "/tmp",
                        name: "Recent",
                        preview: "",
                        path: nil,
                        createdAt: 1_710_000_000,
                        updatedAt: 1_710_000_001,
                        archived: false
                    )
                ],
                nextCursor: "older"
            )
        }

        await state.loadThreadsFromRuntime()

        XCTAssertEqual(legacyRequests.count, 1)
        XCTAssertNil(legacyRequests.first?.cursor)
        XCTAssertEqual(legacyRequests.first?.limit, AppState.sidebarBootstrapRecentLimit)
        XCTAssertEqual(state.chats.map(\.clawixThreadId), ["recent-thread"])
    }

    func testArchivedChatsLoadFromClawJSSessionsOnDemand() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SessionsHistoryURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let origin = try XCTUnwrap(URL(string: "http://sessions.test"))
        var requests: [URLRequest] = []
        SessionsHistoryURLProtocol.handler = { request in
            requests.append(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = """
            {
              "items": [
                \(Self.sessionRecordJSON(id: "archived-thread", title: "Archived", pinned: false, archived: true))
              ],
              "total": 1
            }
            """
            return (response, Data(body.utf8))
        }

        let state = AppState()
        state.clawJSSessionsCanonicalActive = true
        state.clawJSSessionsClientFactory = {
            ClawJSSessionsClient(bearerToken: "test-token", origin: origin, session: session)
        }

        await state.loadArchivedChats()

        let sessionRequests = requests.filter { $0.url?.path == "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/sessions" }
        XCTAssertEqual(sessionRequests.count, 1)
        let archivedRequest = try XCTUnwrap(sessionRequests.first)
        let query = Self.queryItems(for: archivedRequest)
        XCTAssertEqual(query["archived"], "true")
        XCTAssertEqual(query["limit"], "\(AppState.archivedSidebarLimit)")
        XCTAssertEqual(state.archivedChats.map(\.clawixThreadId), ["archived-thread"])
        XCTAssertTrue(state.archivedLoaded)
    }

    func testCanonicalProjectsLoadOnlyOnDemandWithPaginationParameters() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SessionsHistoryURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let origin = try XCTUnwrap(URL(string: "http://sessions.test"))
        var requests: [URLRequest] = []
        SessionsHistoryURLProtocol.handler = { request in
            requests.append(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = """
            {
              "items": [
                {
                  "id": "project-1",
                  "resourceId": "res_project_1",
                  "displayName": "Project One",
                  "path": "/tmp/project-one",
                  "hidden": false,
                  "archived": false,
                  "sortRank": 0,
                  "createdAt": 1710000000000,
                  "updatedAt": 1710000000000
                }
              ],
              "total": 1
            }
            """
            return (response, Data(body.utf8))
        }

        let state = AppState()
        state.clawJSSessionsCanonicalActive = true
        state.clawJSSessionsClientFactory = {
            ClawJSSessionsClient(bearerToken: "test-token", origin: origin, session: session)
        }

        await state.loadCanonicalProjectsIfNeeded()

        let projectRequests = requests.filter { $0.url?.path == "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/projects" }
        XCTAssertEqual(projectRequests.count, 1)
        let projectRequest = try XCTUnwrap(projectRequests.first)
        let query = Self.queryItems(for: projectRequest)
        XCTAssertEqual(query["hidden"], "false")
        XCTAssertEqual(query["archived"], "false")
        XCTAssertEqual(query["limit"], "500")
        XCTAssertEqual(query["offset"], "0")
        XCTAssertEqual(state.projects.map(\.name), ["Project One"])
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition(), file: file, line: line)
    }

    nonisolated private static func queryItems(for request: URLRequest) -> [String: String] {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
    }

    nonisolated private static func sessionRecordJSON(id: String, title: String, pinned: Bool, archived: Bool) -> String {
        """
        {
          "id": "\(id)",
          "agent": "codex",
          "runtime": null,
          "machine": null,
          "workspaceId": null,
          "projectId": null,
          "projectPath": "/tmp",
          "runtimeAdapter": null,
          "runtimeSessionId": null,
          "title": "\(title)",
          "createdAt": 1710000000000,
          "lastMessageAt": 1710000001000,
          "messageCount": 1,
          "pinned": \(pinned ? "true" : "false"),
          "archived": \(archived ? "true" : "false"),
          "sidebarVisible": true,
          "branch": null,
          "cwd": "/tmp",
          "status": "active",
          "customMetadata": null
        }
        """
    }

    nonisolated private static func bodyString(from request: URLRequest) -> String {
        if let body = request.httpBody {
            return String(data: body, encoding: .utf8) ?? ""
        }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private final class SessionsHistoryURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
