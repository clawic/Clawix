import XCTest
@testable import Clawix

enum ClawJSRuntimeLensTestFixtures {
    private struct RuntimeLensEnvelope: Decodable {
        let data: ClawJSRuntimeLensSnapshot
    }

    static func data(
        named name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: name,
                withExtension: "json",
                subdirectory: "Fixtures/ClawJSRuntimeLens"
            ),
            file: file,
            line: line
        )
        return try Data(contentsOf: url)
    }

    static func degradedRuntimePortalSnapshot(
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> ClawJSRuntimeLensSnapshot {
        let client = ClawJSRuntimeLensClient(runner: .init { args in
            XCTAssertEqual(args, ["runtime", "hermes", "domains", "--json"], file: file, line: line)
            return .init(
                data: try data(named: "degraded-runtime-portal-envelope", file: file, line: line),
                exitCode: 2
            )
        })
        return try await client.load(runtime: .hermes)
    }

    static func hermesRuntimePortalSnapshot(
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> ClawJSRuntimeLensSnapshot {
        let client = ClawJSRuntimeLensClient(runner: .init { args in
            XCTAssertEqual(args, ["runtime", "hermes", "domains", "--json"], file: file, line: line)
            return .init(
                data: try data(named: "hermes-runtime-portal-envelope", file: file, line: line),
                exitCode: 2
            )
        })
        return try await client.load(runtime: .hermes)
    }

    static func decodedRuntimePortalSnapshot(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> ClawJSRuntimeLensSnapshot {
        let envelope = try JSONDecoder().decode(
            RuntimeLensEnvelope.self,
            from: data(named: "degraded-runtime-portal-envelope", file: file, line: line)
        )
        return envelope.data
    }
}
