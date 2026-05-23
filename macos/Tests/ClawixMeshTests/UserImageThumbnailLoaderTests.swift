import AppKit
import ClawixCore
import XCTest
@testable import Clawix

final class UserImageThumbnailLoaderTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserImageThumbnailLoader.shared.resetForTests()
    }

    override func tearDown() {
        UserImageThumbnailLoader.shared.resetForTests()
        RolloutAttachmentRegistry.shared.resetForTests()
        super.tearDown()
    }

    func testLargeFileThumbnailIsDownsampled() async throws {
        let url = try Self.writeFixture(width: 1_200, height: 800)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await UserImageThumbnailLoader.shared.thumbnail(for: .file(url))
        let cgImage = try Self.cgImage(from: XCTUnwrap(result.image))

        XCTAssertFalse(result.cacheHit)
        XCTAssertLessThanOrEqual(cgImage.width, UserImageThumbnailLoader.defaultMaxPixelSize)
        XCTAssertLessThanOrEqual(cgImage.height, UserImageThumbnailLoader.defaultMaxPixelSize)
        XCTAssertEqual(result.decodedPixels, cgImage.width * cgImage.height)
        XCTAssertEqual(result.costBytes, cgImage.bytesPerRow * cgImage.height)
    }

    func testRepeatedFileLoadUsesCache() async throws {
        let url = try Self.writeFixture(width: 900, height: 600)
        defer { try? FileManager.default.removeItem(at: url) }

        let first = await UserImageThumbnailLoader.shared.thumbnail(for: .file(url))
        let second = await UserImageThumbnailLoader.shared.thumbnail(for: .file(url))

        XCTAssertNotNil(first.image)
        XCTAssertFalse(first.cacheHit)
        XCTAssertNotNil(second.image)
        XCTAssertTrue(second.cacheHit)
        XCTAssertEqual(second.decodedPixels, 0)
        XCTAssertEqual(second.costBytes, 0)
        XCTAssertEqual(first.cacheKey, second.cacheKey)
    }

    func testFileMetadataChangeInvalidatesCacheKey() async throws {
        let url = try Self.writeFixture(width: 900, height: 600)
        defer { try? FileManager.default.removeItem(at: url) }
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000)],
            ofItemAtPath: url.path
        )

        let first = await UserImageThumbnailLoader.shared.thumbnail(for: .file(url))
        try Self.overwriteFixture(url: url, width: 700, height: 500)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 2_000)],
            ofItemAtPath: url.path
        )
        let second = await UserImageThumbnailLoader.shared.thumbnail(for: .file(url))

        XCTAssertNotNil(first.image)
        XCTAssertNotNil(second.image)
        XCTAssertFalse(second.cacheHit)
        XCTAssertNotEqual(first.cacheKey, second.cacheKey)
    }

    func testAlreadyCancelledTaskDoesNotPopulateCache() async throws {
        let url = try Self.writeFixture(width: 900, height: 600)
        defer { try? FileManager.default.removeItem(at: url) }

        let cancelled = await Task { () -> UserImageThumbnailLoadResult in
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return await UserImageThumbnailLoader.shared.thumbnail(for: .file(url))
        }.value
        let loadedAfterCancellation = await UserImageThumbnailLoader.shared.thumbnail(for: .file(url))

        XCTAssertNil(cancelled.image)
        XCTAssertFalse(loadedAfterCancellation.cacheHit)
        XCTAssertNotNil(loadedAfterCancellation.image)
    }

    func testAttachmentThumbnailIsDownsampledAndCached() async throws {
        let data = try Self.fixtureData(width: 1_100, height: 700)
        let attachment = WireAttachment(
            id: "image-attachment",
            kind: .image,
            mimeType: "image/png",
            filename: "large.png",
            dataBase64: data.base64EncodedString()
        )

        let first = await UserImageThumbnailLoader.shared.thumbnail(for: .attachment(attachment))
        let second = await UserImageThumbnailLoader.shared.thumbnail(for: .attachment(attachment))
        let cgImage = try Self.cgImage(from: XCTUnwrap(first.image))

        XCTAssertEqual(first.sourceBytes, data.count)
        XCTAssertFalse(first.cacheHit)
        XCTAssertLessThanOrEqual(cgImage.width, UserImageThumbnailLoader.defaultMaxPixelSize)
        XCTAssertLessThanOrEqual(cgImage.height, UserImageThumbnailLoader.defaultMaxPixelSize)
        XCTAssertTrue(second.cacheHit)
        XCTAssertEqual(first.cacheKey, second.cacheKey)
    }

    func testRolloutAttachmentRefLoadsBytesOnDemand() async throws {
        let url = try Self.writeFixture(width: 1_100, height: 700)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try Data(contentsOf: url)
        RolloutAttachmentRegistry.shared.register(id: "rollout-ref", url: url, mimeType: "image/png")
        let attachment = WireAttachment(
            id: "rollout-ref",
            kind: .image,
            mimeType: "image/png",
            filename: "ref.png",
            dataBase64: nil,
            byteSize: data.count
        )

        let result = await UserImageThumbnailLoader.shared.thumbnail(for: .attachment(attachment))
        let cgImage = try Self.cgImage(from: XCTUnwrap(result.image))

        XCTAssertEqual(result.sourceBytes, data.count)
        XCTAssertLessThanOrEqual(cgImage.width, UserImageThumbnailLoader.defaultMaxPixelSize)
        XCTAssertLessThanOrEqual(cgImage.height, UserImageThumbnailLoader.defaultMaxPixelSize)
    }

    func testMissingRolloutAttachmentRefFailsGracefully() async throws {
        let attachment = WireAttachment(
            id: "missing-ref",
            kind: .image,
            mimeType: "image/png",
            filename: "missing.png",
            dataBase64: nil,
            byteSize: 0
        )

        let result = await UserImageThumbnailLoader.shared.thumbnail(for: .attachment(attachment))

        XCTAssertNil(result.image)
        XCTAssertEqual(result.sourceBytes, 0)
    }

    func testMissingFileThumbnailFailsWithoutCachingPlaceholder() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).png")

        let first = await UserImageThumbnailLoader.shared.thumbnail(for: .file(url))
        let second = await UserImageThumbnailLoader.shared.thumbnail(for: .file(url))

        XCTAssertNil(first.image)
        XCTAssertNil(second.image)
        XCTAssertFalse(first.cacheHit)
        XCTAssertFalse(second.cacheHit)
    }

    func testCorruptImagePreviewFailsGracefullyWithoutCacheHit() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("corrupt-\(UUID().uuidString).png")
        try Data("not an image".utf8).write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let first = await UserImageThumbnailLoader.shared.thumbnail(for: .file(url))
        let second = await UserImageThumbnailLoader.shared.thumbnail(for: .file(url))

        XCTAssertNil(first.image)
        XCTAssertNil(second.image)
        XCTAssertFalse(first.cacheHit)
        XCTAssertFalse(second.cacheHit)
    }

    private static func writeFixture(width: Int, height: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawix-thumbnail-\(UUID().uuidString).png")
        try overwriteFixture(url: url, width: width, height: height)
        return url
    }

    private static func overwriteFixture(url: URL, width: Int, height: Int) throws {
        let data = try fixtureData(width: width, height: height)
        try data.write(to: url, options: .atomic)
    }

    private static func fixtureData(width: Int, height: Int) throws -> Data {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let cgImage = try XCTUnwrap(context.makeImage())
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }

    private static func cgImage(from image: NSImage) throws -> CGImage {
        var rect = CGRect(origin: .zero, size: image.size)
        return try XCTUnwrap(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
    }
}
