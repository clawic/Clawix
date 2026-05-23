import XCTest
@testable import Clawix

final class ProjectFolderStateTests: XCTestCase {
    func testProjectFolderInspectorReportsMissingDetachedDuplicateAndActive() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawix-project-state-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let missing = root.appendingPathComponent("missing", isDirectory: true)
        XCTAssertEqual(ProjectFolderInspector.state(for: missing.path), .missing)

        let active = root.appendingPathComponent("active", isDirectory: true)
        try FileManager.default.createDirectory(at: active, withIntermediateDirectories: true)
        XCTAssertEqual(ProjectFolderInspector.state(for: active.path), .active)

        let detached = root.appendingPathComponent("detached", isDirectory: true)
        try FileManager.default.createDirectory(at: detached, withIntermediateDirectories: true)
        try """
        {
          "schemaVersion": 1,
          "manifestKind": "claw.project",
          "projectId": "detached",
          "name": "detached",
          "title": "Detached",
          "attachment": { "state": "detached", "detachedReason": "finder-copy" }
        }
        """.data(using: .utf8)!.write(to: ProjectFolderPathResolver.manifestURL(folderURL: detached))
        XCTAssertEqual(ProjectFolderInspector.state(for: detached.path), .detached)

        let duplicate = root.appendingPathComponent("duplicate", isDirectory: true)
        try FileManager.default.createDirectory(at: duplicate, withIntermediateDirectories: true)
        try """
        {
          "schemaVersion": 1,
          "manifestKind": "claw.project",
          "projectId": "copied",
          "name": "copied",
          "title": "Copied",
          "attachment": { "state": "attached", "workspaceId": "workspace-main" }
        }
        """.data(using: .utf8)!.write(to: ProjectFolderPathResolver.manifestURL(folderURL: duplicate))
        XCTAssertEqual(ProjectFolderInspector.state(for: duplicate.path, currentWorkspaceId: "workspace-other"), .duplicate)
        XCTAssertEqual(ProjectFolderInspector.state(for: duplicate.path, currentWorkspaceId: "workspace-main"), .active)
    }

    func testProjectDefaultsFolderStateFromPathWithoutPersistingFolderAuthority() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawix-project-model-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let project = Project(name: "Local", path: root.path)
        XCTAssertEqual(project.folderState, .active)

        let encoded = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(Project.self, from: encoded)
        XCTAssertEqual(decoded.folderState, .active)
    }

    func testProjectFolderInspectorUsesCentralManifestRoute() throws {
        let modelsSource = try readSource("AppState/Models.swift")

        XCTAssertTrue(modelsSource.contains("ProjectFolderPathResolver.manifestURL("))
        XCTAssertFalse(modelsSource.contains("appendingPathComponent(\"claw.project.json\""))
    }

    func testDefaultProjectFolderResolverCreatesPrimaryFolderInsideWorkspace() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawix-project-workspace-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let first = try ProjectFolderPathResolver.createDefaultFolder(forName: "Client/API: Work", workspaceURL: workspace)
        let second = try ProjectFolderPathResolver.createDefaultFolder(forName: "Client/API: Work", workspaceURL: workspace)

        XCTAssertEqual(ProjectFolderPathResolver.manifestFileName, "claw.project.json")
        XCTAssertEqual(
            ProjectFolderPathResolver.manifestURL(folderURL: first).path,
            first.appendingPathComponent("claw.project.json").path
        )
        XCTAssertEqual(first.deletingLastPathComponent().lastPathComponent, "Projects")
        XCTAssertEqual(first.deletingLastPathComponent().deletingLastPathComponent().path, workspace.path)
        XCTAssertEqual(first.lastPathComponent, "Client-API- Work")
        XCTAssertEqual(second.lastPathComponent, "Client-API- Work 2")
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func testProjectEditorFolderPlaceholderUsesCentralRoute() throws {
        let modelsSource = try readSource("AppState/Models.swift")
        let editorSource = try readSource("ProjectEditorSheet.swift")

        XCTAssertEqual(ProjectFolderPathResolver.sampleProjectFolderDisplayPath, "/Users/me/code/foo")
        XCTAssertTrue(modelsSource.contains("sampleProjectFolderDisplayPath"))
        XCTAssertTrue(editorSource.contains("ProjectFolderPathResolver.sampleProjectFolderDisplayPath"))
        XCTAssertFalse(editorSource.contains("TextField(\"/Users/me/code/foo\""))
    }

    private func readSource(_ relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.sources, isDirectory: true)
            .appendingPathComponent(ClawixPersistentSurfacePaths.components.clawix, isDirectory: true)
        return try String(
            contentsOf: root.appendingPathComponent(relativePath, isDirectory: false),
            encoding: .utf8
        )
    }
}
