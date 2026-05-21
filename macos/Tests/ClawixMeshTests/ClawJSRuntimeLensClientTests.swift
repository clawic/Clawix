import XCTest
@testable import Clawix

final class ClawJSRuntimeLensClientTests: XCTestCase {
    func testRuntimeLensAcceptsDegradedRuntimePortalEnvelope() async throws {
        var requested: [ClawJSRuntimeLensID] = []
        let client = ClawJSRuntimeLensClient(runner: .init { runtime in
            requested.append(runtime)
            return .init(data: Data("""
            {
              "ok": true,
              "data": {
                "runtimeId": "hermes",
                "runtimeName": "Hermes Agent",
                "support": {
                  "stability": "dev-only",
                  "supportLevel": "dev-only",
                  "recommended": false
                },
                "status": {
                  "installed": false,
                  "cliAvailable": false,
                  "gatewayAvailable": false,
                  "diagnostics": {
                    "lastError": "hermes CLI not found",
                    "locations": {
                      "homeDir": "/Users/test/.hermes",
                      "workspacePath": "/tmp/workspace"
                    }
                  }
                },
                "domains": [
                  {
                    "domain": "runtime",
                    "supported": true,
                    "status": "error",
                    "strategy": "cli",
                    "authority": "runtime_adapter",
                    "limitations": []
                  },
                  {
                    "domain": "channels",
                    "supported": true,
                    "status": "degraded",
                    "strategy": "native",
                    "count": 7,
                    "authority": "runtime_adapter",
                    "limitations": ["normalized"]
                  }
                ]
              }
            }
            """.utf8), exitCode: 2)
        })

        let snapshot = try await client.load(runtime: .hermes)

        XCTAssertEqual(requested, [.hermes])
        XCTAssertEqual(snapshot.runtimeId, "hermes")
        XCTAssertEqual(snapshot.status.cliAvailable, false)
        XCTAssertEqual(snapshot.status.diagnostics?.locations?.homeDir, "/Users/test/.hermes")
        XCTAssertEqual(snapshot.domains.first { $0.domain == "channels" }?.count, 7)
    }
}
