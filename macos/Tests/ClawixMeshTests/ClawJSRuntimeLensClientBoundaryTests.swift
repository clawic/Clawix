import XCTest
@testable import Clawix

final class ClawJSRuntimeLensClientBoundaryTests: XCTestCase {
    func testRuntimeLensRejectsOversizedEnvelopeBeforeDecode() async throws {
        let oversized = Data(repeating: UInt8(ascii: "x"), count: 1_048_577)
        let client = ClawJSRuntimeLensClient(runner: .init { _ in
            .init(data: oversized, exitCode: 0)
        })

        do {
            _ = try await client.load(runtime: .hermes)
            XCTFail("Expected oversized runtime lens payload to fail")
        } catch let error as NSError {
            XCTAssertEqual(error.domain, "ClawJSRuntimeLensClient")
            XCTAssertEqual(error.code, 413)
        }
    }

    func testRuntimeLensUsesTopLevelResourcesAsInventoryFallback() async throws {
        let client = ClawJSRuntimeLensClient(runner: .init { args in
            XCTAssertEqual(args, ["runtime", "hermes", "domains", "--json"])
            return .init(
                data: try ClawJSRuntimeLensTestFixtures.data(named: "top-level-resources-fallback"),
                exitCode: 0
            )
        })

        let snapshot = try await client.load(runtime: .hermes)
        let runtimeSummary = ClawJSRuntimeLensRuntimeSummaryPresentation.make(snapshot: snapshot)

        XCTAssertEqual(snapshot.session?.sessionPath, "/Users/tester/.example/sessions")
        XCTAssertEqual(snapshot.session?.sessionStorageContract, "sqlite_with_gateway_transcripts")
        XCTAssertEqual(snapshot.session?.sessionDatabasePath, "/Users/tester/.example/state.db")
        XCTAssertEqual(snapshot.runtimeResources?.providers?.first?.id, "openai")
        XCTAssertEqual(snapshot.runtimeResources?.auth?["openai"]?.hasEnvKey, true)
        XCTAssertEqual(runtimeSummary.runtimeResourceAggregateDomainCount, 7)
        XCTAssertEqual(runtimeSummary.runtimeResourceCount, 7)
        XCTAssertEqual(
            runtimeSummary.runtimeResourcesLabel,
            "providers 1, models 1, auth 1, scheduler 1, memory 1, skills 1, channels 1"
        )
        XCTAssertTrue(runtimeSummary.accessibilityLabel.contains("runtime resource aggregate domains 7"))
        XCTAssertTrue(runtimeSummary.accessibilityLabel.contains("runtime resources 7"))
        XCTAssertEqual(snapshot.resources(for: "skills").first?.id, "example-skills")
        XCTAssertEqual(snapshot.resources(for: "memory").first?.path, "/Users/tester/.example/memories")
        XCTAssertEqual(snapshot.resources(for: "channels").first?.status, "configured")
        XCTAssertEqual(snapshot.resources(for: "providers").first?.envVars, ["OPENAI_API_KEY"])
        XCTAssertEqual(snapshot.resources(for: "providers").first?.attributes, [
            "api key auth: true",
            "env auth: true",
            "env vars: OPENAI_API_KEY"
        ])
        XCTAssertEqual(snapshot.resources(for: "auth").first?.id, "openai")
        XCTAssertEqual(snapshot.resources(for: "auth").first?.attributes, [
            "subscription: false",
            "api key: true",
            "profile key: false",
            "env key: true"
        ])
        XCTAssertEqual(snapshot.resources(for: "models").first?.id, "default-model")
        XCTAssertEqual(snapshot.resources(for: "models").first?.attributes, [
            "provider: openai",
            "model id: gpt-4.1",
            "default: true"
        ])
        XCTAssertEqual(snapshot.resources(for: "scheduler").first?.id, "example-scheduler")
        XCTAssertEqual(snapshot.resources(for: "configuration").first { $0.id == "SOUL" }?.path, "/tmp/workspace/SOUL.md")
        XCTAssertEqual(snapshot.resources(for: "configuration").first { $0.id == "managed-file-1" }?.path, "/tmp/workspace/AGENTS.md")
    }

    func testRuntimeLensPassesScopeOverridesToDomainsCommand() async throws {
        let client = ClawJSRuntimeLensClient(runner: .init { args in
            XCTAssertEqual(args, [
                "runtime",
                "hermes",
                "domains",
                "--home-dir",
                "/tmp/hermes-home",
                "--runtime-workspace",
                "/tmp/hermes-workspace",
                "--config-path",
                "/tmp/hermes-config.yaml",
                "--auth-store",
                "/tmp/hermes-auth.json",
                "--gateway-url",
                "http://127.0.0.1:18789",
                "--json"
            ])
            return .init(
                data: try ClawJSRuntimeLensTestFixtures.data(named: "degraded-runtime-portal-envelope"),
                exitCode: 2
            )
        })

        let snapshot = try await client.load(
            runtime: .hermes,
            homeDir: "/tmp/hermes-home",
            runtimeWorkspace: "/tmp/hermes-workspace",
            configPath: "/tmp/hermes-config.yaml",
            authStore: "/tmp/hermes-auth.json",
            gatewayURL: "http://127.0.0.1:18789"
        )

        XCTAssertEqual(snapshot.runtimeId, "example")
    }
}
