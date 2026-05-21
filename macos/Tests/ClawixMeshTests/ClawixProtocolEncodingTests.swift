import XCTest
@testable import Clawix

final class ClawixProtocolEncodingTests: XCTestCase {
    func testInitializeCapabilitiesUseStableLocalNameWithRuntimeWireKey() throws {
        let encoded = try JSONEncoder().encode(
            InitializeCapabilities(
                extensionFields: true,
                optOutNotificationMethods: nil
            )
        )
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]

        XCTAssertEqual(object?["experimentalApi"] as? Bool, true)
        XCTAssertNil(object?["extensionFields"])
    }

    func testThreadStartUsesStableLocalPersonalizationNameWithRuntimeWireKey() throws {
        let encoded = try JSONEncoder().encode(
            ThreadStartParams(
                cwd: "/tmp/project",
                model: "gpt-5.4",
                approvalPolicy: "never",
                sandbox: "danger-full-access",
                personalizationPreset: "pragmatic",
                serviceTier: "fast",
                activeSkills: nil,
                collaborationMode: nil
            )
        )
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]

        XCTAssertEqual(object?["personality"] as? String, "pragmatic")
        XCTAssertNil(object?["personalizationPreset"])
    }

    func testSidebarBootstrapResponseDecodesProjectsPinsAndRecentSessions() throws {
        let data = Data("""
        {
          "projects": [
            {
              "id": "project-1",
              "resourceId": "res_project_1",
              "displayName": "Project One",
              "path": "/tmp/project-one",
              "hidden": false,
              "archived": false,
              "sortRank": 0,
              "createdAt": 1710000000000,
              "updatedAt": 1710000000000
            }
          ],
          "pinned": [
            \(Self.sessionRecordJSON(id: "pin-1", title: "Pinned", pinned: true, archived: false))
          ],
          "recent": [
            \(Self.sessionRecordJSON(id: "recent-1", title: "Recent", pinned: false, archived: false))
          ],
          "totalActiveVisible": 2
        }
        """.utf8)

        let response = try JSONDecoder().decode(ClawJSSessionsClient.SidebarBootstrapResponse.self, from: data)

        XCTAssertEqual(response.projects.map(\.displayName), ["Project One"])
        XCTAssertEqual(response.pinned.map(\.id), ["pin-1"])
        XCTAssertEqual(response.recent.map(\.id), ["recent-1"])
        XCTAssertEqual(response.totalActiveVisible, 2)
    }

    private static func sessionRecordJSON(id: String, title: String, pinned: Bool, archived: Bool) -> String {
        """
        {
          "id": "\(id)",
          "agent": "codex",
          "runtime": null,
          "machine": null,
          "workspaceId": null,
          "projectId": null,
          "projectPath": "/tmp",
          "runtimeAdapter": null,
          "runtimeSessionId": null,
          "title": "\(title)",
          "createdAt": 1710000000000,
          "lastMessageAt": 1710000001000,
          "messageCount": 1,
          "pinned": \(pinned ? "true" : "false"),
          "archived": \(archived ? "true" : "false"),
          "sidebarVisible": true,
          "branch": null,
          "cwd": "/tmp",
          "status": "active",
          "customMetadata": null
        }
        """
    }
}
