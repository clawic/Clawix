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
