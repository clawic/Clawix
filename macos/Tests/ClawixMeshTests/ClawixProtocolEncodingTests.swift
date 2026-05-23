import XCTest
@testable import Clawix

final class ClawixProtocolEncodingTests: XCTestCase {
    func testInitializeCapabilitiesUseStableLocalNameWithRuntimeWireKey() throws {
        let encoded = try JSONEncoder().encode(
            InitializeCapabilities(
                extensionFields: true,
                optOutNotificationMethods: nil
            )
        )
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]

        XCTAssertEqual(object?["experimentalApi"] as? Bool, true)
        XCTAssertNil(object?["extensionFields"])
    }

    func testThreadStartUsesStableLocalPersonalizationNameWithRuntimeWireKey() throws {
        let encoded = try JSONEncoder().encode(
            ThreadStartParams(
                cwd: "/tmp/project",
                model: "gpt-5.4",
                approvalPolicy: "never",
                sandbox: "danger-full-access",
                personalizationPreset: "pragmatic",
                serviceTier: "fast",
                activeSkills: nil,
                collaborationMode: nil
            )
        )
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]

        XCTAssertEqual(object?["personality"] as? String, "pragmatic")
        XCTAssertNil(object?["personalizationPreset"])
    }

    func testSidebarBootstrapResponseDecodesProjectsPinsAndRecentSessions() throws {
        let data = Data("""
        {
          "projects": [
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
          "pinned": [
            \(Self.sessionRecordJSON(id: "pin-1", title: "Pinned", pinned: true, archived: false))
          ],
          "recent": [
            \(Self.sessionRecordJSON(id: "recent-1", title: "Recent", pinned: false, archived: false))
          ],
          "totalActiveVisible": 2
        }
        """.utf8)

        let response = try JSONDecoder().decode(ClawJSSessionsClient.SidebarBootstrapResponse.self, from: data)

        XCTAssertEqual(response.projects.map(\.displayName), ["Project One"])
        XCTAssertEqual(response.pinned.map(\.id), ["pin-1"])
        XCTAssertEqual(response.recent.map(\.id), ["recent-1"])
        XCTAssertEqual(response.totalActiveVisible, 2)
    }

    func testQuickSwitchResponseCarriesHeaderOnlyContract() throws {
        let data = Data("""
        {
          "items": [
            \(Self.sessionRecordJSON(id: "quick-1", title: "Quick Match", pinned: true, archived: false))
          ],
          "total": 1,
          "query": "quick",
          "limit": 20,
          "offset": 0,
          "source": "sessions.quick_switch",
          "searchedMessageHistory": false
        }
        """.utf8)

        let response = try JSONDecoder().decode(ClawJSSessionsClient.QuickSwitchSessionsResponse.self, from: data)

        XCTAssertEqual(response.items.map(\.id), ["quick-1"])
        XCTAssertEqual(response.source, "sessions.quick_switch")
        XCTAssertFalse(response.searchedMessageHistory)
    }

    func testSessionsClientUsesSeparateQuickSwitchAndDeepSearchRoutes() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProtocolEncodingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let origin = try XCTUnwrap(URL(string: "http://sessions.test"))
        var observed: [(path: String, query: [String: String])] = []
        ProtocolEncodingURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            observed.append((
                path: components.path,
                query: Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            ))
            let body: String
            switch components.path {
            case "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/sidebar/quick-switch":
                body = """
                {
                  "items": [],
                  "total": 0,
                  "query": "\(components.queryItems?.first(where: { $0.name == "q" })?.value ?? "")",
                  "limit": 10,
                  "offset": 5,
                  "source": "sessions.quick_switch",
                  "searchedMessageHistory": false
                }
                """
            case "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/sessions/search":
                body = #"{"items":[]}"#
            default:
                XCTFail("Unexpected path: \(components.path)")
                body = #"{}"#
            }
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(body.utf8))
        }
        defer { ProtocolEncodingURLProtocol.handler = nil }
        let client = ClawJSSessionsClient(bearerToken: "test-token", origin: origin, session: session)

        _ = try await client.quickSwitchSessions(query: "deploy", projectId: "project-1", includeArchived: false, limit: 10, offset: 5)
        _ = try await client.searchMessages(query: "deploy", projectId: "project-1", limit: 25, offset: 50)

        XCTAssertEqual(observed.map(\.path), [
            "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/sidebar/quick-switch",
            "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/sessions/search"
        ])
        XCTAssertEqual(observed[0].query["q"], "deploy")
        XCTAssertEqual(observed[0].query["includeArchived"], "false")
        XCTAssertEqual(observed[0].query["offset"], "5")
        XCTAssertEqual(observed[1].query["q"], "deploy")
        XCTAssertEqual(observed[1].query["limit"], "25")
        XCTAssertEqual(observed[1].query["offset"], "50")
    }

    @MainActor
    func testAppStateQuickSwitchReadsHeadersWithoutHydratingMessages() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProtocolEncodingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let origin = try XCTUnwrap(URL(string: "http://sessions.test"))
        var observed: [(path: String, query: [String: String])] = []
        ProtocolEncodingURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            observed.append((
                path: components.path,
                query: Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            ))
            XCTAssertEqual(components.path, "\(ClawixPersistentSurfaceKeys.publicApiPrefix)/sidebar/quick-switch")
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let body = """
            {
              "items": [
                \(Self.sessionRecordJSON(id: "quick-thread-1", title: "Deploy Plan", pinned: false, archived: false))
              ],
              "total": 1,
              "query": "deploy",
              "limit": 9,
              "offset": 0,
              "source": "sessions.quick_switch",
              "searchedMessageHistory": false
            }
            """
            return (response, Data(body.utf8))
        }
        defer { ProtocolEncodingURLProtocol.handler = nil }
        let project = Project(id: UUID(), name: "Project One", path: "/tmp")
        let state = AppState()
        state.projects = [project]
        state.clawJSSessionsClientFactory = {
            ClawJSSessionsClient(bearerToken: "test-token", origin: origin, session: session)
        }

        let headers = await state.quickSwitchSessionHeaders(
            query: "deploy",
            scopedProject: project,
            limit: 9
        )

        XCTAssertEqual(headers.map(\.id), ["quick-thread-1"])
        XCTAssertEqual(headers.first?.title, "Deploy Plan")
        XCTAssertEqual(headers.first?.projectName, "Project One")
        XCTAssertTrue(state.chats.isEmpty)
        XCTAssertEqual(observed.first?.query["q"], "deploy")
        XCTAssertEqual(observed.first?.query["projectPath"], "/tmp")
        XCTAssertEqual(observed.first?.query["includeArchived"], "false")
        XCTAssertEqual(observed.first?.query["limit"], "9")
        XCTAssertEqual(observed.first?.query["offset"], "0")

        let header = try XCTUnwrap(headers.first)
        let opened = state.openQuickSwitchSession(header)
        XCTAssertTrue(opened)
        XCTAssertEqual(state.chats.first?.title, "Deploy Plan")
        XCTAssertEqual(state.chats.first?.messages, [])
        XCTAssertEqual(state.chats.first?.clawixThreadId, "quick-thread-1")
        XCTAssertEqual(state.currentRoute, .chat(try XCTUnwrap(state.chats.first?.id)))
    }

    private static func sessionRecordJSON(id: String, title: String, pinned: Bool, archived: Bool) -> String {
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
}

private final class ProtocolEncodingURLProtocol: URLProtocol {
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
