import XCTest
@testable import ClawixCore

final class AttachmentSpoolerTests: XCTestCase {
    override func tearDown() {
        AttachmentSpooler.cleanup(scope: Self.scope)
        AttachmentSpooler.cleanup(scope: Self.unsafeScope)
        super.tearDown()
    }

    func testWritesAttachmentToSanitizedScopedTempDirectory() throws {
        let data = Data("fake image bytes".utf8)
        let attachment = WireAttachment(
            id: "image/../../private",
            mimeType: "image/png",
            filename: "screenshot.png",
            dataBase64: data.base64EncodedString()
        )

        let paths = AttachmentSpooler.write(attachments: [attachment], scope: Self.unsafeScope)

        let path = try XCTUnwrap(paths.first)
        XCTAssertEqual(paths.count, 1)
        XCTAssertTrue(path.hasPrefix(AttachmentSpooler.scopedDirectory(scope: Self.unsafeScope).path))
        XCTAssertFalse(path.contains(".."))
        XCTAssertFalse(path.contains("private/screenshot.png"))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), data)
    }

    func testInvalidAttachmentIsSkippedWithoutPrivateLogMaterial() {
        let attachment = WireAttachment(
            id: "private-id",
            mimeType: "image/png",
            filename: "private-photo.png",
            dataBase64: "not base64"
        )
        var logs: [String] = []

        let paths = AttachmentSpooler.write(
            attachments: [attachment],
            scope: Self.scope,
            log: { logs.append($0) }
        )

        XCTAssertTrue(paths.isEmpty)
        XCTAssertEqual(logs, ["attachment decode failed"])
        XCTAssertFalse(logs.joined().contains("private-photo.png"))
        XCTAssertFalse(logs.joined().contains("private-id"))
        XCTAssertFalse(logs.joined().contains("not base64"))
    }

    func testCleanupRemovesScopedTemporaryFiles() throws {
        let data = Data("fake image bytes".utf8)
        let attachment = WireAttachment(
            id: "image-1",
            mimeType: "image/jpeg",
            filename: "image.jpg",
            dataBase64: data.base64EncodedString()
        )
        let path = try XCTUnwrap(AttachmentSpooler.write(attachments: [attachment], scope: Self.scope).first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))

        XCTAssertTrue(AttachmentSpooler.cleanup(scope: Self.scope))

        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        XCTAssertTrue(AttachmentSpooler.cleanup(scope: Self.scope))
    }

    private static let scope = "attachment-spooler-tests"
    private static let unsafeScope = "scope/../escape"
}
