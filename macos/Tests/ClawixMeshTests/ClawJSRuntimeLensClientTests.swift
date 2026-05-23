import XCTest
@testable import Clawix

final class ClawJSRuntimeLensClientTests: XCTestCase {
    func testRuntimeLensAcceptsDegradedRuntimePortalEnvelope() async throws {
        var requested: [ClawJSRuntimeLensID] = []
        let client = ClawJSRuntimeLensClient(runner: .init { args in
            XCTAssertEqual(args, ["runtime", "hermes", "domains", "--json"])
            requested.append(.hermes)
            return .init(
                data: try ClawJSRuntimeLensTestFixtures.data(named: "degraded-runtime-portal-envelope"),
                exitCode: 2
            )
        })

        let snapshot = try await client.load(runtime: .hermes)

        XCTAssertEqual(requested, [.hermes])
        XCTAssertEqual(snapshot.runtimeId, "example")
        XCTAssertEqual(snapshot.status.cliAvailable, false)
        XCTAssertEqual(snapshot.status.diagnostics?.locations?.homeDir, "/Users/tester/.example")
        XCTAssertEqual(snapshot.domains.map(\.domain), ClawJSRuntimeLensSnapshot.canonicalDomains)
        XCTAssertEqual(snapshot.missingCanonicalDomains, [])
        XCTAssertEqual(snapshot.supportAudit?.closureState, "blocked")
        XCTAssertEqual(snapshot.resources(for: "sessions").first?.id, "2026/05/21/runtime-session")
    }
}
