import XCTest
@testable import Clawix

@MainActor
final class RootSearchQueryBridgeTests: XCTestCase {
    func testRootSearchQueryCallsFrameworkProfileAndDecodesResults() throws {
        let runner = RecordingRootSearchRunner(output: """
        {
          "ok": true,
          "data": {
            "query": "commands",
            "profile": "framework",
            "results": [
              {
                "id": "commands:search",
                "source": "commands",
                "domain": "commands",
                "type": "command",
                "title": "search",
                "subtitle": "canonical",
                "snippet": "Search framework records.",
                "score": 10.5,
                "actions": [
                  {
                    "id": "open",
                    "kind": "open",
                    "label": "Open",
                    "requiresApproval": true,
                    "grant": "search.commands.open"
                  }
                ]
              }
            ],
            "omittedSources": []
          }
        }
        """)

        let response = try RootSearchQueryBridge.query(
            " commands ",
            runner: RootSearchQueryBridge.ClawSearchCommandRunner(run: runner.run)
        )

        XCTAssertEqual(runner.calls, [[
            "search", "query", "commands",
            "--profile", "framework",
            "--limit", "12",
            "--json",
        ]])
        XCTAssertEqual(response.data.results.first?.id, "commands:search")
        XCTAssertEqual(response.data.results.first?.actions?.first?.grant, "search.commands.open")
    }

    func testRootSearchFullProfileIncludesDisabledSourceContext() throws {
        let runner = RecordingRootSearchRunner(output: """
        {"ok":true,"data":{"query":"shortcut","profile":"full","results":[],"omittedSources":[{"source":"native.system","reason":"disabled","message":"native.system is external_pending"}]}}
        """)

        let response = try RootSearchQueryBridge.query(
            "shortcut",
            profile: "full",
            runner: RootSearchQueryBridge.ClawSearchCommandRunner(run: runner.run)
        )

        XCTAssertEqual(runner.calls.first, [
            "search", "query", "shortcut",
            "--profile", "full",
            "--limit", "12",
            "--json",
            "--include-disabled-sources",
        ])
        XCTAssertEqual(response.data.omittedSources?.first?.source, "native.system")
    }

    func testRootSearchActionPlanUsesDryRunAndDecodesHostRequest() throws {
        let runner = RecordingRootSearchRunner(output: """
        {
          "ok": true,
          "data": {
            "plan": {
              "id": "search-action:native.system:shortcut:daily-plan:run",
              "resultId": "native.system:shortcut:daily-plan",
              "actionId": "run",
              "risk": "system",
              "requiresApproval": true,
              "status": "planned",
              "hostRequest": {
                "system": "mac-control",
                "schemaVersion": 1,
                "requestId": "searchreq_daily_plan",
                "capabilityId": "mac.shortcut.run",
                "actor": {
                  "kind": "user_ui",
                  "id": "user:clawix.root-search",
                  "role": "owner"
                },
                "target": {
                  "kind": "shortcut",
                  "name": "Daily Plan",
                  "selector": {
                    "source": "native.system"
                  }
                },
                "arguments": {
                  "name": "Daily Plan",
                  "resultId": "native.system:shortcut:daily-plan",
                  "actionId": "run",
                  "source": "native.system",
                  "domain": "native"
                },
                "dryRun": true,
                "reason": "Run native Shortcut from Search result",
                "approved": false,
                "command": {
                  "resource": "mac",
                  "action": "plan",
                  "requestJsonFlag": "request-json"
                }
              }
            }
          }
        }
        """)

        let planData = try RootSearchQueryBridge.actionPlanData(
            resultId: "native.system:shortcut:daily-plan",
            actionId: "run",
            runner: RootSearchQueryBridge.ClawSearchCommandRunner(run: runner.run)
        )
        let nativeRequest = try SearchHostActionBridge.nativeRequest(
            from: planData,
            host: NativeMacActionWireHost(hostId: "host_test", bundleId: "com.clawix.app")
        )

        XCTAssertEqual(runner.calls, [[
            "search", "actions", "execute",
            "native.system:shortcut:daily-plan", "run",
            "--dry-run",
            "--actor", "user:clawix.root-search",
            "--surface", "clawix.root_search",
            "--json",
        ]])
        XCTAssertEqual(nativeRequest.capabilityId, "mac.shortcut.run")
        XCTAssertEqual(nativeRequest.actor.kind, "user_ui")
        XCTAssertEqual(nativeRequest.target?.name, "Daily Plan")
        XCTAssertEqual(nativeRequest.dryRun, true)
    }
}

private final class RecordingRootSearchRunner {
    private let output: String
    private(set) var calls: [[String]] = []

    init(output: String) {
        self.output = output
    }

    func run(_ arguments: [String]) throws -> Data {
        calls.append(arguments)
        return Data(output.utf8)
    }
}
