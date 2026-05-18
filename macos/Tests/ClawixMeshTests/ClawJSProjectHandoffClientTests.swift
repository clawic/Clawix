import Foundation
import XCTest
@testable import Clawix

@MainActor
final class ClawJSProjectHandoffClientTests: XCTestCase {
    func testAttachUsesPortableWorkspaceIdAndExplicitAcceptance() throws {
        var captured: [[String]] = []
        let client = ClawJSProjectHandoffClient(runner: .init { args in
            captured.append(args)
            return """
            {
              "ok": true,
              "data": {
                "accepted": true,
                "warnings": [],
                "manifest": {
                  "projectId": "res_project",
                  "name": "Project",
                  "title": "Project",
                  "attachment": { "state": "attached", "workspaceId": "workspace-main" }
                }
              }
            }
            """.data(using: .utf8)!
        })

        let project = Project(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                              resourceId: "res_project",
                              name: "Project",
                              path: "/tmp/project",
                              folderState: .active)
        let result = try client.attach(project: project, workspaceId: "workspace-main")

        XCTAssertEqual(result.accepted, true)
        XCTAssertEqual(result.manifest.projectId, "res_project")
        XCTAssertEqual(captured, [[
            "project", "attach", "/tmp/project",
            "--workspace-id", "workspace-main",
            "--project-id", "res_project",
            "--name", "Project",
            "--accept",
            "--json",
        ]])
        XCTAssertFalse(captured[0].contains { $0.hasPrefix("/Users/") && captured[0].contains("--workspace-id") })
    }

    func testInspectAndDetachDecodeCanonicalProjectState() throws {
        var captured: [[String]] = []
        let client = ClawJSProjectHandoffClient(runner: .init { args in
            captured.append(args)
            if args.contains("inspect") {
                return """
                {
                  "ok": true,
                  "data": {
                    "state": "duplicate",
                    "warnings": ["duplicate_project_id_attached_to_different_workspace"],
                    "manifest": {
                      "projectId": "copied",
                      "name": "Copied",
                      "title": "Copied",
                      "attachment": { "state": "attached", "workspaceId": "workspace-main" }
                    }
                  }
                }
                """.data(using: .utf8)!
            }
            return """
            {
              "ok": true,
              "data": {
                "manifest": {
                  "projectId": "copied",
                  "name": "Copied",
                  "title": "Copied",
                  "attachment": { "state": "detached", "detachedReason": "finder-copy" }
                }
              }
            }
            """.data(using: .utf8)!
        })

        let inspection = try client.inspect(path: "/tmp/copied", workspaceId: "workspace-other")
        let detached = try client.detach(path: "/tmp/copied", reason: "finder-copy")

        XCTAssertEqual(inspection.state, "duplicate")
        XCTAssertEqual(inspection.warnings, ["duplicate_project_id_attached_to_different_workspace"])
        XCTAssertEqual(detached.attachment.state, "detached")
        XCTAssertEqual(detached.attachment.detachedReason, "finder-copy")
        XCTAssertEqual(captured[0], ["project", "inspect", "/tmp/copied", "--workspace-id", "workspace-other", "--json"])
        XCTAssertEqual(captured[1], ["project", "detach", "/tmp/copied", "--reason", "finder-copy", "--json"])
    }

    func testImportHandoffUsesPreviewAcceptanceAndWorkspaceId() throws {
        var captured: [[String]] = []
        let client = ClawJSProjectHandoffClient(runner: .init { args in
            captured.append(args)
            return """
            {
              "ok": true,
              "data": {
                "accepted": true,
                "warnings": [],
                "handoffKind": "claw.project.handoff",
                "manifest": {
                  "projectId": "portable",
                  "name": "Portable",
                  "title": "Portable",
                  "attachment": { "state": "attached", "workspaceId": "workspace-other" }
                }
              }
            }
            """.data(using: .utf8)!
        })

        let result = try client.importHandoff(
            handoffPath: "/tmp/project.clawexport",
            projectPath: "/tmp/restored",
            workspaceId: "workspace-other",
            accept: true,
            replaceDuplicate: true
        )

        XCTAssertEqual(result.accepted, true)
        XCTAssertEqual(result.handoffKind, "claw.project.handoff")
        XCTAssertEqual(result.manifest.attachment.workspaceId, "workspace-other")
        XCTAssertEqual(captured, [[
            "project", "import", "/tmp/project.clawexport", "/tmp/restored",
            "--workspace-id", "workspace-other",
            "--json",
            "--accept",
            "--replace",
        ]])
    }
}
