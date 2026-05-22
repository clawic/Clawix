import Foundation
import ClawixCore
import BridgeProtocolFixtures

private struct BridgeFixtureManifest: Encodable {
    struct Fixture: Encodable {
        let index: Int
        let name: String
        let type: String
        let direction: BridgeFixtureDirection
        let file: String
    }

    struct PlatformValidator: Encodable {
        let platform: String
        let path: String
    }

    let schemaVersion: Int
    let contractId: String
    let bridgeSchemaVersion: Int
    let source: String
    let fixtureCount: Int
    let fixtures: [Fixture]
    let platformValidators: [PlatformValidator]
}

@main
enum BridgeFixtureExporter {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fputs("usage: BridgeFixtureExporter <output-dir>\n", stderr)
            Foundation.exit(64)
        }

        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for url in try FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)
        where url.pathExtension == "json" {
            try FileManager.default.removeItem(at: url)
        }

        let fixtures = BridgeFixtures.all
        var manifestFixtures: [BridgeFixtureManifest.Fixture] = []
        for (index, fixture) in fixtures.enumerated() {
            let fileName = "\(String(format: "%03d", index + 1))-\(fixture.name).json"
            let data = try BridgeCoder.encode(fixture.frame)
            try data.write(to: output.appendingPathComponent(fileName), options: .atomic)
            manifestFixtures.append(BridgeFixtureManifest.Fixture(
                index: index + 1,
                name: fixture.name,
                type: fixture.name,
                direction: fixture.direction,
                file: fileName
            ))
        }

        let manifest = BridgeFixtureManifest(
            schemaVersion: 1,
            contractId: "clawix.protocol.bridge.v1",
            bridgeSchemaVersion: bridgeSchemaVersion,
            source: "packages/ClawixCore/Sources/BridgeProtocolFixtures/BridgeFixtures.swift",
            fixtureCount: fixtures.count,
            fixtures: manifestFixtures,
            platformValidators: [
                BridgeFixtureManifest.PlatformValidator(
                    platform: "swift",
                    path: "packages/ClawixCore/Tests/ClawixCoreTests/BridgeProtocolContractValidatorTests.swift"
                ),
                BridgeFixtureManifest.PlatformValidator(
                    platform: "web",
                    path: "web/tests/unit/wire.test.ts"
                ),
                BridgeFixtureManifest.PlatformValidator(
                    platform: "android",
                    path: "android/app/src/test/java/com/example/clawix/android/BridgeFrameRoundtripTest.kt"
                ),
                BridgeFixtureManifest.PlatformValidator(
                    platform: "windows",
                    path: "windows/Clawix.Tests/BridgeFixtureParityTests.cs"
                )
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(manifest)
            .write(to: output.appendingPathComponent("manifest.json"), options: .atomic)

        print("Wrote \(fixtures.count) bridge fixtures to \(output.path)")
    }
}
