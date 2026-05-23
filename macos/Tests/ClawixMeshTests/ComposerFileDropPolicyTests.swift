import XCTest
@testable import Clawix

@MainActor
final class ComposerFileDropPolicyTests: XCTestCase {
    func testDropPolicyStagesImageAndFileFixturesThroughComposerPath() throws {
        let state = AppState()
        let imageURL = try writeFixture(name: "dropped-image.png", data: Data("png".utf8))
        let fileURL = try writeFixture(name: "dropped-file.xyz", data: Data("file".utf8))

        XCTAssertTrue(ComposerFileDropPolicy.stageDroppedFiles([imageURL, fileURL, imageURL], into: state))

        XCTAssertEqual(
            state.composer.attachments.map { $0.url.standardizedFileURL.path },
            [
                imageURL.standardizedFileURL.path,
                fileURL.standardizedFileURL.path
            ]
        )
    }

    func testDropPolicyRejectsEmptyDropsWithoutComposerMutation() {
        let state = AppState()

        XCTAssertFalse(ComposerFileDropPolicy.stageDroppedFiles([], into: state))
        XCTAssertTrue(state.composer.attachments.isEmpty)
    }

    func testDropPolicyOnlyAcceptsComposerHostingRoutes() {
        let chatId = UUID()
        XCTAssertTrue(ComposerFileDropPolicy.accepts(route: .home))
        XCTAssertTrue(ComposerFileDropPolicy.accepts(route: .search))
        XCTAssertTrue(ComposerFileDropPolicy.accepts(route: .plugins))
        XCTAssertTrue(ComposerFileDropPolicy.accepts(route: .project))
        XCTAssertTrue(ComposerFileDropPolicy.accepts(route: .chat(chatId)))

        XCTAssertFalse(ComposerFileDropPolicy.accepts(route: .settings))
        XCTAssertFalse(ComposerFileDropPolicy.accepts(route: .automations))
        XCTAssertFalse(ComposerFileDropPolicy.accepts(route: .appsHome))
        XCTAssertFalse(ComposerFileDropPolicy.accepts(route: .app(UUID())))
        XCTAssertFalse(ComposerFileDropPolicy.accepts(route: .driveDocuments))
    }

    private func writeFixture(name: String, data: Data) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawix-composer-drop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return url
    }
}
