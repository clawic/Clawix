import XCTest
@testable import Clawix

@MainActor
final class ComposerAttachmentLifecycleTests: XCTestCase {
    override func setUp() {
        super.setUp()
        setenv("CLAWIX_DISABLE_BACKEND", "1", 1)
        setenv("CLAWIX_BRIDGE_DISABLE", "1", 1)
    }

    override func tearDown() {
        unsetenv("CLAWIX_DISABLE_BACKEND")
        unsetenv("CLAWIX_BRIDGE_DISABLE")
        super.tearDown()
    }

    func testAddRemoveDeduplicatesAndCancelsBeforeSend() throws {
        let state = AppState()
        let imageURL = try writeFixture(name: "fixture.png", data: Data("image".utf8))

        state.addComposerAttachments([imageURL, imageURL])
        XCTAssertEqual(state.composer.attachments.map(\.url), [imageURL])

        let id = try XCTUnwrap(state.composer.attachments.first?.id)
        state.removeComposerAttachment(id: id)

        XCTAssertTrue(state.composer.attachments.isEmpty)
        XCTAssertTrue(state.composer.text.isEmpty)
    }

    func testAttachmentOnlySendStaysLocalAndClearsComposerWhenRuntimeUnavailable() throws {
        let state = AppState()
        state.chats = []
        state.currentRoute = .home
        state.daemonBridgeClient = nil
        state.clawJSSessionsCanonicalActive = false
        state.rescueDecision = RescueSurvivalPolicy.evaluate(
            signals: [.bridgeRuntimeDown],
            availableRuntimeCount: 0
        )
        let imageURL = try writeFixture(name: "send-fixture.png", data: Data("image".utf8))
        state.addComposerAttachments([imageURL])

        state.sendMessage()

        XCTAssertTrue(state.composer.attachments.isEmpty)
        XCTAssertTrue(state.composer.text.isEmpty)
        let chat = try XCTUnwrap(state.chats.first)
        let messages = try XCTUnwrap(state.chatStore.transcript(for: chat.id)?.messages)
        XCTAssertEqual(messages.first?.role, .user)
        XCTAssertEqual(messages.first?.content, "@\(imageURL.path)")
        XCTAssertEqual(messages.last?.role, .assistant)
        XCTAssertTrue(messages.last?.content.contains("Diagnostics are available") == true)
        XCTAssertFalse(chat.hasActiveTurn)
    }

    func testWireAttachmentsIncludeOnlyImageBytesForSimulatedBridgeSend() throws {
        let state = AppState()
        let imageData = Data("image".utf8)
        let imageURL = try writeFixture(name: "wire.png", data: imageData)
        let unsupportedURL = try writeFixture(name: "archive.zip", data: Data("zip".utf8))

        let wire = state.wireAttachments(from: [
            ComposerAttachment(url: imageURL),
            ComposerAttachment(url: unsupportedURL)
        ])

        XCTAssertEqual(wire.count, 1)
        XCTAssertEqual(wire[0].kind, .image)
        XCTAssertEqual(wire[0].mimeType, "image/png")
        XCTAssertEqual(wire[0].filename, "wire.png")
        XCTAssertEqual(Data(base64Encoded: wire[0].dataBase64 ?? ""), imageData)
    }

    private func writeFixture(name: String, data: Data) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawix-composer-attachment-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return url
    }
}
