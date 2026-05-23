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

    func testRejectsOversizedFramesBeforeJsonDecode() throws {
        let data = Data(repeating: UInt8(ascii: " "), count: bridgeMaxFrameBytes + 1)

        XCTAssertThrowsError(try BridgeCoder.decode(data)) { error in
            guard case BridgeDecodingError.oversizedFrame(let actualBytes, let maxBytes) = error else {
                XCTFail("expected oversizedFrame, got \(error)")
                return
            }
            XCTAssertEqual(actualBytes, bridgeMaxFrameBytes + 1)
            XCTAssertEqual(maxBytes, bridgeMaxFrameBytes)
        }
    }

    func testRejectsUnsupportedAttachmentKindWithParseableError() throws {
        let data = """
        {"schemaVersion":1,"type":"sendMessage","sessionId":"abc","text":"hello","attachments":[{"id":"video-1","kind":"video","mimeType":"video/mp4","filename":"clip.mp4","dataBase64":"ZmFrZQ=="}]}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try BridgeCoder.decode(data)) { error in
            guard let bridgeError = error as? BridgeDecodingError else {
                XCTFail("expected BridgeDecodingError, got \(error)")
                return
            }
            XCTAssertEqual(bridgeError.code, "bridge.decode.invalidPayload")
            XCTAssertFalse(String(describing: bridgeError).contains("ZmFrZQ=="))
        }
    }

    func testRejectsMalformedJsonWithParseableError() throws {
        let data = #"{"schemaVersion":1,"type":"listSessions""#.data(using: .utf8)!

        XCTAssertThrowsError(try BridgeCoder.decode(data)) { error in
            guard let bridgeError = error as? BridgeDecodingError else {
                XCTFail("expected BridgeDecodingError, got \(error)")
                return
            }
            XCTAssertEqual(bridgeError.code, "bridge.decode.invalidJson")
        }
    }

    func testRejectsNonObjectFrames() throws {
        let data = #"["not","an","object"]"#.data(using: .utf8)!

        XCTAssertThrowsError(try BridgeCoder.decode(data)) { error in
            guard let bridgeError = error as? BridgeDecodingError else {
                XCTFail("expected BridgeDecodingError, got \(error)")
                return
            }
            XCTAssertEqual(bridgeError.code, "bridge.decode.nonObjectFrame")
            XCTAssertEqual(bridgeError, .nonObjectFrame)
        }
    }

    func testRejectsMissingRequiredEnvelopeFields() throws {
        let data = #"{"schemaVersion":1}"#.data(using: .utf8)!

        XCTAssertThrowsError(try BridgeCoder.decode(data)) { error in
            guard let bridgeError = error as? BridgeDecodingError else {
                XCTFail("expected BridgeDecodingError, got \(error)")
                return
            }
            XCTAssertEqual(bridgeError.code, "bridge.decode.missingField")
            XCTAssertEqual(bridgeError, .missingField("type"))
        }
    }

    func testRejectsUnknownSchemaVersionWithParseableError() throws {
        let data = #"{"schemaVersion":2,"type":"listSessions"}"#.data(using: .utf8)!

        XCTAssertThrowsError(try BridgeCoder.decode(data)) { error in
            guard let bridgeError = error as? BridgeDecodingError else {
                XCTFail("expected BridgeDecodingError, got \(error)")
                return
            }
            XCTAssertEqual(bridgeError.code, "bridge.decode.unknownSchemaVersion")
            XCTAssertEqual(bridgeError, .unknownSchemaVersion(2))
        }
    }

    func testRejectsExtraTopLevelPayloadFields() throws {
        let data = #"{"schemaVersion":1,"type":"listSessions","sessionId":"abc"}"#.data(using: .utf8)!

        XCTAssertThrowsError(try BridgeCoder.decode(data)) { error in
            guard case BridgeDecodingError.unknownField(let type, let field) = error else {
                XCTFail("expected unknownField, got \(error)")
                return
            }
            XCTAssertEqual(type, "listSessions")
            XCTAssertEqual(field, "sessionId")
        }
    }

    func testInvalidPayloadErrorsAreStableAndParseable() throws {
        let data = #"{"schemaVersion":1,"type":"auth","token":"abc","deviceName":"iPhone"}"#.data(using: .utf8)!

        XCTAssertThrowsError(try BridgeCoder.decode(data)) { error in
            guard let bridgeError = error as? BridgeDecodingError else {
                XCTFail("expected BridgeDecodingError, got \(error)")
                return
            }
            XCTAssertEqual(bridgeError.code, "bridge.decode.invalidPayload")
            if case BridgeDecodingError.invalidPayload(let type, let message) = bridgeError {
                XCTAssertEqual(type, "auth")
                XCTAssertTrue(message.contains("clientKind"), message)
            } else {
                XCTFail("expected invalidPayload, got \(bridgeError)")
            }
        }
    }
}
