import XCTest
@testable import ClawixCore
import BridgeProtocolFixtures

final class BridgeProtocolContractValidatorTests: XCTestCase {
    func testFixtureCatalogCoversCurrentFrameTags() throws {
        let expectedNames = [
            "auth",
            "listSessions",
            "openSession",
            "loadOlderMessages",
            "sendMessage",
            "newSession",
            "interruptTurn",
            "authOk",
            "authFailed",
            "versionMismatch",
            "sessionsSnapshot",
            "sessionUpdated",
            "messagesSnapshot",
            "messagesPage",
            "messageAppended",
            "messageStreaming",
            "errorEvent",
            "editPrompt",
            "archiveSession",
            "unarchiveSession",
            "pinSession",
            "unpinSession",
            "renameSession",
            "pairingStart",
            "listProjects",
            "readFile",
            "pairingPayload",
            "projectsSnapshot",
            "fileSnapshot",
            "transcribeAudio",
            "transcriptionResult",
            "requestAudio",
            "audioSnapshot",
            "requestGeneratedImage",
            "generatedImageSnapshot",
            "requestRolloutAttachment",
            "rolloutAttachmentSnapshot",
            "bridgeState",
            "requestRateLimits",
            "rateLimitsSnapshot",
            "rateLimitsUpdated",
            "requestClawJSServiceStatuses",
            "clawJSServiceStatusesSnapshot",
            "clawJSServiceStatusUpdated",
            "audioRegister",
            "audioAttachTranscript",
            "audioGet",
            "audioGetBytes",
            "audioList",
            "audioDelete",
            "audioRegisterResult",
            "audioAttachTranscriptResult",
            "audioGetResult",
            "audioBytesResult",
            "audioListResult",
            "audioDeleteResult",
        ]

        let fixtures = BridgeFixtures.all
        XCTAssertEqual(fixtures.map(\.name), expectedNames)
        XCTAssertEqual(Set(fixtures.map(\.name)).count, fixtures.count)
        XCTAssertEqual(Set(fixtures.map { $0.frame.body.typeTag }).count, fixtures.count)

        for fixture in fixtures {
            XCTAssertEqual(fixture.frame.schemaVersion, bridgeSchemaVersion, fixture.name)
            XCTAssertEqual(fixture.frame.body.typeTag, fixture.name, fixture.name)
        }
    }

    func testFixturesRoundTripAsFlatJson() throws {
        for fixture in BridgeFixtures.all {
            let data = try BridgeCoder.encode(fixture.frame)
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: data) as? [String: Any],
                fixture.name
            )

            XCTAssertEqual(object["schemaVersion"] as? Int, bridgeSchemaVersion, fixture.name)
            XCTAssertEqual(object["type"] as? String, fixture.name, fixture.name)
            XCTAssertNil(object["payload"], fixture.name)

            let decoded = try BridgeCoder.decode(data)
            XCTAssertEqual(decoded, fixture.frame, fixture.name)
        }
    }

    func testGeneratedBridgeV1FixtureCorpusDecodesAndRoundTrips() throws {
        struct Manifest: Decodable {
            struct Fixture: Decodable {
                let name: String
                let type: String
                let file: String
            }

            let contractId: String
            let bridgeSchemaVersion: Int
            let fixtureCount: Int
            let fixtures: [Fixture]
        }

        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureRoot = packageRoot
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("BridgeV1")
        let manifestData = try Data(contentsOf: fixtureRoot.appendingPathComponent("manifest.json"))
        let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)

        XCTAssertEqual(manifest.contractId, "clawix.protocol.bridge.v1")
        XCTAssertEqual(manifest.bridgeSchemaVersion, bridgeSchemaVersion)
        XCTAssertEqual(manifest.fixtureCount, manifest.fixtures.count)

        for fixture in manifest.fixtures {
            let data = try Data(contentsOf: fixtureRoot.appendingPathComponent(fixture.file))
            let decoded = try BridgeCoder.decode(data)
            XCTAssertEqual(decoded.schemaVersion, bridgeSchemaVersion, fixture.file)
            XCTAssertEqual(decoded.body.typeTag, fixture.type, fixture.file)
            XCTAssertEqual(fixture.name, fixture.type, fixture.file)

            let encoded = try BridgeCoder.encode(decoded)
            XCTAssertEqual(try BridgeCoder.decode(encoded), decoded, fixture.file)
        }
    }

    func testCompatibilityDefaultsRemainPinned() throws {
        let attachmentlessPrompt = #"{"schemaVersion":1,"type":"sendMessage","sessionId":"abc","text":"hello"}"#
            .data(using: .utf8)!
        XCTAssertEqual(
            try BridgeCoder.decode(attachmentlessPrompt).body,
            .sendMessage(sessionId: "abc", text: "hello", attachments: [])
        )

        let unpagedOpen = #"{"schemaVersion":1,"type":"openSession","sessionId":"abc"}"#
            .data(using: .utf8)!
        XCTAssertEqual(
            try BridgeCoder.decode(unpagedOpen).body,
            .openSession(sessionId: "abc", limit: nil)
        )

        let completeSnapshot = #"{"schemaVersion":1,"type":"messagesSnapshot","sessionId":"abc","messages":[]}"#
            .data(using: .utf8)!
        XCTAssertEqual(
            try BridgeCoder.decode(completeSnapshot).body,
            .messagesSnapshot(sessionId: "abc", messages: [], hasMore: nil)
        )

        let fileSnapshot = #"{"schemaVersion":1,"type":"fileSnapshot","path":"/tmp/readme.md"}"#
            .data(using: .utf8)!
        XCTAssertEqual(
            try BridgeCoder.decode(fileSnapshot).body,
            .fileSnapshot(path: "/tmp/readme.md", content: nil, isMarkdown: false, error: nil)
        )

        let rateLimits = #"{"schemaVersion":1,"type":"rateLimitsSnapshot"}"#
            .data(using: .utf8)!
        XCTAssertEqual(
            try BridgeCoder.decode(rateLimits).body,
            .rateLimitsSnapshot(snapshot: nil, byLimitId: [:])
        )
    }
}
