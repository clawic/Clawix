import XCTest
@testable import ClawixEngine

final class BridgeFileReaderTests: XCTestCase {
    func testDirectoryPathReturnsReadableListing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawix-bridge-file-reader-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("artifact-folder", isDirectory: true)
        let childFolder = folder.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: childFolder, withIntermediateDirectories: true)
        try "hello".write(to: folder.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let result = BridgeFileReader.load(path: folder.path)

        XCTAssertNil(result.error)
        XCTAssertFalse(result.isMarkdown)
        XCTAssertTrue(result.content?.contains("child/") == true)
        XCTAssertTrue(result.content?.contains("notes.txt") == true)
    }

    func testEmptyDirectoryPathReturnsReadablePlaceholder() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawix-bridge-empty-folder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let result = BridgeFileReader.load(path: root.path)

        XCTAssertNil(result.error)
        XCTAssertEqual(result.content, "(empty folder)")
    }

    func testMissingFileReturnsStableError() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).txt")

        let result = BridgeFileReader.load(path: missing.path)

        XCTAssertNil(result.content)
        XCTAssertFalse(result.isMarkdown)
        XCTAssertEqual(result.error, "File not found")
    }

    func testBinaryFileReturnsUnsupportedPreviewError() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("binary-\(UUID().uuidString).bin")
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = BridgeFileReader.load(path: url.path)

        XCTAssertNil(result.content)
        XCTAssertEqual(result.error, "Preview not available for binary files")
    }

    func testOversizedTextFileReturnsSizeLimitBeforeDecode() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("oversized-\(UUID().uuidString).txt")
        let data = Data(repeating: UInt8(ascii: "x"), count: BridgeFileReader.maxPreviewBytes + 1)
        try data.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = BridgeFileReader.load(path: url.path)

        XCTAssertNil(result.content)
        XCTAssertEqual(result.error, "File too large to preview")
    }

    func testUnreadableFileReturnsStableError() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("unreadable-\(UUID().uuidString).txt")
        try "private".write(to: url, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            try? FileManager.default.removeItem(at: url)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)

        let result = BridgeFileReader.load(path: url.path)

        if result.content == nil {
            XCTAssertEqual(result.error, "Couldn't read file")
        } else {
            throw XCTSkip("current runner can still read chmod 000 files")
        }
    }
}
