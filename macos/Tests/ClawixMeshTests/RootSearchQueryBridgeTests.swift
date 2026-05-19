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
