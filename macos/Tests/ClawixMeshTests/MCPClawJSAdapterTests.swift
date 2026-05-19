import XCTest
@testable import Clawix

@MainActor
final class MCPClawJSAdapterTests: XCTestCase {
    func testStoreLoadsAndPersistsThroughInjectedClawJSPersistence() async {
        let persistence = FakeMCPPersistence(servers: [
            MCPServerConfig(name: "browser", command: "npx")
        ])
        let store = MCPServersStore(persistence: persistence, autoLoad: false)
        await store.refresh()

        XCTAssertEqual(store.servers.map(\.name), ["browser"])

        store.upsert(MCPServerConfig(name: "notes", command: "node"))
        await persistence.waitForSave()
        XCTAssertEqual(persistence.savedServers.map(\.tomlIdentifier), ["browser", "notes"])
    }

    func testStoreCancelSuppressesLateMCPReload() async {
        let loadStarted = expectation(description: "MCP load started")
        let loadReturned = expectation(description: "MCP load returned after teardown")
        let persistence = FakeMCPPersistence(servers: [
            MCPServerConfig(name: "stale", command: "node")
        ])
        persistence.onLoad = {
            loadStarted.fulfill()
            try? await Task.sleep(nanoseconds: 50_000_000)
            loadReturned.fulfill()
        }
        let store = MCPServersStore(persistence: persistence, autoLoad: false)

        let task = Task { await store.refresh() }
        await fulfillment(of: [loadStarted], timeout: 1)
        store.cancelSurfaceWork()

        await fulfillment(of: [loadReturned], timeout: 1)
        await task.value
        XCTAssertTrue(store.servers.isEmpty)
        XCTAssertFalse(store.isLoading)
        XCTAssertNil(store.lastError)
    }

    func testSecondMCPReloadSuppressesFirstStaleResult() async {
        let staleStarted = expectation(description: "Stale MCP load started")
        let staleReturned = expectation(description: "Stale MCP load returned")
        let freshReturned = expectation(description: "Fresh MCP load returned")
        let persistence = SequencedMCPPersistence { call in
            if call == 1 {
                staleStarted.fulfill()
                try? await Task.sleep(nanoseconds: 100_000_000)
                staleReturned.fulfill()
                return [MCPServerConfig(name: "stale", command: "node")]
            }
            freshReturned.fulfill()
            return [MCPServerConfig(name: "fresh", command: "node")]
        }
        let store = MCPServersStore(persistence: persistence, autoLoad: false)

        let first = Task { await store.refresh() }
        await fulfillment(of: [staleStarted], timeout: 1)
        let second = Task { await store.refresh() }

        await fulfillment(of: [freshReturned, staleReturned], timeout: 1)
        await first.value
        await second.value
        XCTAssertEqual(store.servers.map(\.name), ["fresh"])
        XCTAssertFalse(store.isLoading)
        XCTAssertNil(store.lastError)
    }

    func testClawJSMCPClientMapsListAndSaveToJsonCommands() async throws {
        var calls: [[String]] = []
        let client = ClawJSMCPClient(runner: .init { args in
            calls.append(args)
            if args == ["mcp", "list", "--json"] {
                return Data("""
                {
                  "items": [
                    {
                      "id": "browser",
                      "command": "npx",
                      "args": ["@modelcontextprotocol/server-browser"],
                      "enabled": true
                    }
                  ]
                }
                """.utf8)
            }
            if args == ["mcp", "config-path", "--scope", "user", "--json"] {
                return Data(#"{"configPath":"/tmp/config.toml","exists":true}"#.utf8)
            }
            return Data("{}".utf8)
        })

        let loaded = try await client.loadServers()
        XCTAssertEqual(loaded.first?.tomlIdentifier, "browser")
        XCTAssertEqual(loaded.first?.arguments.map(\.value), ["@modelcontextprotocol/server-browser"])

        try await client.saveServers([
            MCPServerConfig(
                name: "api",
                transport: .http,
                enabled: false,
                url: "https://example.invalid/mcp",
                bearerTokenEnvVar: "API_TOKEN",
                headers: [MCPKeyValueEntry(key: "X-Test", value: "1")]
            )
        ])

        XCTAssertTrue(calls.contains(["mcp", "delete", "browser", "--json"]))
        XCTAssertTrue(calls.contains { call in
            call.starts(with: ["mcp", "upsert", "api", "--json"])
                && call.contains("--url")
                && call.contains("https://example.invalid/mcp")
                && call.contains("--bearer-token-env-var")
                && call.contains("API_TOKEN")
                && call.contains("--enabled")
                && call.contains("false")
        })

        let configPath = try await client.configPath(scope: "user", projectPath: nil)
        XCTAssertEqual(configPath.configPath, "/tmp/config.toml")
        XCTAssertEqual(configPath.exists, true)
        XCTAssertTrue(calls.contains(["mcp", "config-path", "--scope", "user", "--json"]))
        assertClawJSMCPCommandsOnly(calls)
    }

    private func assertClawJSMCPCommandsOnly(_ calls: [[String]], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(calls.isEmpty, file: file, line: line)
        for call in calls {
            XCTAssertEqual(call.first, "mcp", file: file, line: line)
            XCTAssertTrue(call.contains("--json"), file: file, line: line)

            let commandLine = call.joined(separator: " ")
            for forbidden in [".codex", "config.toml", "mcp_servers", "[mcp_servers"] {
                XCTAssertFalse(commandLine.contains(forbidden), file: file, line: line)
            }
        }
    }
}

private final class FakeMCPPersistence: MCPServersPersistence {
    private var current: [MCPServerConfig]
    private(set) var savedServers: [MCPServerConfig] = []
    var onLoad: (() async -> Void)?
    private var saveContinuation: CheckedContinuation<Void, Never>?

    init(servers: [MCPServerConfig]) {
        current = servers
    }

    func loadServers() async throws -> [MCPServerConfig] {
        await onLoad?()
        return current
    }

    func saveServers(_ servers: [MCPServerConfig]) async throws {
        savedServers = servers
        current = servers
        saveContinuation?.resume()
        saveContinuation = nil
    }

    func waitForSave() async {
        if !savedServers.isEmpty { return }
        await withCheckedContinuation { continuation in
            saveContinuation = continuation
        }
    }
}

private final class SequencedMCPPersistence: MCPServersPersistence {
    private var calls = 0
    private let loader: (Int) async throws -> [MCPServerConfig]

    init(loader: @escaping (Int) async throws -> [MCPServerConfig]) {
        self.loader = loader
    }

    func loadServers() async throws -> [MCPServerConfig] {
        calls += 1
        return try await loader(calls)
    }

    func saveServers(_ servers: [MCPServerConfig]) async throws {
        _ = servers
    }
}
