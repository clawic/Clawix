import XCTest
@testable import Clawix

final class ClawJSMacCareClientTests: XCTestCase {
    func testLoadReportUsesReadOnlyMacCareCli() async throws {
        var calls: [[String]] = []
        let client = ClawJSMacCareClient(runner: .init { args in
            calls.append(args)
            return .init(data: Self.reportFixture, exitCode: 0)
        })

        let report = try await client.loadReport()

        XCTAssertEqual(calls, [["mac-care", "report", "--json"]])
        XCTAssertEqual(report.status, "read_only_foundation")
        XCTAssertEqual(report.sidecar.filename, "mac_care.sqlite")
        XCTAssertEqual(report.sidecar.surfaceId, "claw.database.macCare")
        XCTAssertEqual(report.sidecar.path, "~/.claw/data/mac_care.sqlite")
        XCTAssertEqual(report.routes.first?.id, "mac_care.route.user_caches")
        XCTAssertEqual(report.actionPlan.executionAuthority, "agent_plan_only")
        XCTAssertEqual(report.actionPlan.requestedBy, "agent")
        XCTAssertTrue(report.safety.allowed)
        XCTAssertEqual(report.safety.requiredAuthority, "none")
        XCTAssertFalse(report.executionPolicy.agentCanExecuteDestructiveActions)
        XCTAssertFalse(report.executionPolicy.testCanExecuteDestructiveActions)
        XCTAssertEqual(report.executionPolicy.destructiveExecutionAuthority, "signed_host_human_confirmed")
        XCTAssertFalse(report.executionPolicy.realFilesystemMutationInFoundationReport)
    }

    func testListScansUsesReadOnlyHistoryCli() async throws {
        var calls: [[String]] = []
        let client = ClawJSMacCareClient(runner: .init { args in
            calls.append(args)
            return .init(data: Self.scanListFixture, exitCode: 0)
        })

        let list = try await client.listScans()

        XCTAssertEqual(calls, [["mac-care", "scans", "list", "--json"]])
        XCTAssertEqual(list.status, "read_only_scan_history")
        XCTAssertEqual(list.sidecar.filename, "mac_care.sqlite")
        XCTAssertEqual(list.scans.first?.id, "mac-care-scan-1")
        XCTAssertEqual(list.scans.first?.candidateCount, 2)
        XCTAssertEqual(list.scans.first?.actionPlanCount, 1)
        XCTAssertEqual(list.scans.first?.summary.destructiveActions, 0)
        XCTAssertEqual(list.scans.first?.metadata.modules?.first, "mac_care.module.user_caches")
    }

    func testLoadScanUsesReadOnlyDetailCli() async throws {
        var calls: [[String]] = []
        let client = ClawJSMacCareClient(runner: .init { args in
            calls.append(args)
            return .init(data: Self.scanDetailFixture, exitCode: 0)
        })

        let detail = try await client.loadScan(id: "mac-care-scan-1")

        XCTAssertEqual(calls, [["mac-care", "scans", "show", "mac-care-scan-1", "--json"]])
        XCTAssertEqual(detail.status, "read_only_scan_detail")
        XCTAssertEqual(detail.scan.id, "mac-care-scan-1")
        XCTAssertEqual(detail.candidates.count, 1)
        XCTAssertEqual(detail.candidates.first?.action, "review")
        XCTAssertEqual(detail.candidates.first?.selection, "unselected")
        XCTAssertEqual(detail.candidates.first?.metadata.displayName, "blob")
        XCTAssertEqual(detail.actionPlan?.executionAuthority, "agent_plan_only")
        XCTAssertEqual(detail.safety?.requiredAuthority, "none")
        XCTAssertEqual(detail.safety?.destructiveActions, [])
    }

    func testPreviewFinalizerWritesPlanFileAndUsesPlanOnlyCli() async throws {
        var calls: [[String]] = []
        var encodedPlan: String?
        let client = ClawJSMacCareClient(runner: .init { args in
            calls.append(args)
            if let planFileIndex = args.firstIndex(of: "--plan-file"), args.indices.contains(planFileIndex + 1) {
                encodedPlan = try String(contentsOfFile: args[planFileIndex + 1], encoding: .utf8)
            }
            return .init(data: Self.finalizerPreviewFixture, exitCode: 0)
        })

        let preview = try await client.previewFinalizer(actionPlan: Self.finalizerActionPlan)

        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].prefix(3), ["mac-care", "finalizer", "preview"])
        XCTAssertTrue(calls[0].contains("--plan-file"))
        XCTAssertTrue(calls[0].contains("--json"))
        XCTAssertTrue(encodedPlan?.contains("\"id\":\"mac-care-finalizer-plan\"") == true)
        XCTAssertTrue(encodedPlan?.contains("\"action\":\"move_to_trash\"") == true)
        XCTAssertEqual(preview.status, "finalizer_preview")
        XCTAssertFalse(preview.willExecute)
        XCTAssertFalse(preview.receiptIssued)
        XCTAssertEqual(preview.executionAuthority, "signed_host_human_confirmed")
        XCTAssertEqual(preview.actions.count, 1)
        XCTAssertEqual(preview.actions.first?.candidateId, "candidate-trash")
        XCTAssertEqual(preview.actions.first?.rollback.level, "best_effort")
        XCTAssertTrue(preview.actions.first?.audit.receiptRequired == true)
        XCTAssertEqual(preview.actions.first?.audit.receiptStatus, "not_issued")
        XCTAssertEqual(preview.summary.destructiveCandidates, 1)
        XCTAssertEqual(preview.summary.receiptsIssued, 0)
        XCTAssertFalse(preview.safety.allowed)
        XCTAssertEqual(preview.safety.requiredAuthority, "signed_host_human_confirmed")
    }

    func testLoadReportRejectsFailedCliResult() async throws {
        let client = ClawJSMacCareClient(runner: .init { _ in
            .init(data: Data("nope".utf8), exitCode: 2)
        })

        do {
            _ = try await client.loadReport()
            XCTFail("Expected loadReport to throw")
        } catch {
            XCTAssertEqual((error as NSError).domain, "ClawJSMacCareClient")
            XCTAssertEqual((error as NSError).code, 2)
        }
    }

    func testLoadReportRejectsOversizedEnvelope() async throws {
        let oversized = Data(repeating: 0x20, count: 1_048_577)
        let client = ClawJSMacCareClient(runner: .init { _ in
            .init(data: oversized, exitCode: 0)
        })

        do {
            _ = try await client.loadReport()
            XCTFail("Expected loadReport to throw")
        } catch {
            XCTAssertEqual((error as NSError).domain, "ClawJSMacCareClient")
            XCTAssertEqual((error as NSError).code, 413)
        }
    }

    private static let reportFixture = Data("""
    {
      "ok": true,
      "data": {
        "version": 1,
        "status": "read_only_foundation",
        "routes": [
          {
            "id": "mac_care.route.user_caches",
            "family": "user_cache",
            "label": "User caches",
            "pathPattern": "{home}/Library/Caches",
            "source": "home",
            "sensitivity": "user_data",
            "requiredPermissionIds": ["mac.permission.files_desktop_documents_downloads"],
            "owner": "application",
            "evidenceLevel": "macos_convention",
            "mutability": "review_required",
            "consumerIntents": ["cleanup", "index", "performance"]
          }
        ],
        "groups": [],
        "actionPlan": {
          "id": "mac-care-read-only-foundation-report",
          "createdAt": "2026-05-21T00:00:00.000Z",
          "executionAuthority": "agent_plan_only",
          "requestedBy": "agent",
          "groups": []
        },
        "safety": {
          "allowed": true,
          "requiredAuthority": "none",
          "destructiveActions": [],
          "reasons": []
        },
        "sidecar": {
          "filename": "mac_care.sqlite",
          "surfaceId": "claw.database.macCare",
          "path": "~/.claw/data/mac_care.sqlite"
        },
        "executionPolicy": {
          "agentCanExecuteDestructiveActions": false,
          "testCanExecuteDestructiveActions": false,
          "destructiveExecutionAuthority": "signed_host_human_confirmed",
          "realFilesystemMutationInFoundationReport": false
        }
      }
    }
    """.utf8)

    private static let scanListFixture = Data("""
    {
      "ok": true,
      "data": {
        "version": 1,
        "status": "read_only_scan_history",
        "scans": [
          {
            "id": "mac-care-scan-1",
            "moduleId": "mac_care.scan.wave_1",
            "status": "completed",
            "startedAt": "2026-05-21T00:00:00.000Z",
            "completedAt": "2026-05-21T00:00:00.000Z",
            "summary": {
              "totalCandidates": 2,
              "totalSizeBytes": 42,
              "destructiveActions": 0
            },
            "metadata": {
              "homeDir": "/tmp/home",
              "modules": ["mac_care.module.user_caches"]
            },
            "candidateCount": 2,
            "actionPlanCount": 1
          }
        ],
        "sidecar": {
          "filename": "mac_care.sqlite",
          "surfaceId": "claw.database.macCare",
          "path": "~/.claw/data/mac_care.sqlite"
        }
      }
    }
    """.utf8)

    private static let scanDetailFixture = Data("""
    {
      "ok": true,
      "data": {
        "version": 1,
        "status": "read_only_scan_detail",
        "scan": {
          "id": "mac-care-scan-1",
          "moduleId": "mac_care.scan.wave_1",
          "status": "completed",
          "startedAt": "2026-05-21T00:00:00.000Z",
          "completedAt": "2026-05-21T00:00:00.000Z",
          "summary": {
            "totalCandidates": 1,
            "totalSizeBytes": 42,
            "destructiveActions": 0
          },
          "metadata": {
            "homeDir": "/tmp/home",
            "modules": ["mac_care.module.user_caches"]
          },
          "candidateCount": 1,
          "actionPlanCount": 1
        },
        "candidates": [
          {
            "id": "mac-care-candidate-1",
            "routeId": "mac_care.route.user_caches",
            "path": "/tmp/home/Library/Caches/blob",
            "action": "review",
            "selection": "unselected",
            "confidence": 0.85,
            "sizeBytes": 42,
            "evidence": ["read_only_file_stat"],
            "warnings": ["large_file"],
            "metadata": {
              "displayName": "blob",
              "groupId": "mac_care.group.user_caches",
              "moduleId": "mac_care.module.user_caches"
            }
          }
        ],
        "actionPlan": {
          "id": "mac-care-scan-1-plan",
          "createdAt": "2026-05-21T00:00:00.000Z",
          "executionAuthority": "agent_plan_only",
          "requestedBy": "agent",
          "groups": [
            {
              "id": "mac_care.group.user_caches",
              "moduleId": "mac_care.module.user_caches",
              "title": "User cache inventory",
              "routeIds": ["mac_care.route.user_caches"],
              "candidates": [
                {
                  "id": "mac-care-candidate-1",
                  "routeId": "mac_care.route.user_caches",
                  "path": "/tmp/home/Library/Caches/blob",
                  "displayName": "blob",
                  "sizeBytes": 42,
                  "action": "review",
                  "selection": "unselected",
                  "confidence": 0.85,
                  "evidence": ["read_only_file_stat"],
                  "warnings": ["large_file"]
                }
              ]
            }
          ]
        },
        "safety": {
          "allowed": true,
          "requiredAuthority": "none",
          "destructiveActions": [],
          "reasons": []
        },
        "sidecar": {
          "filename": "mac_care.sqlite",
          "surfaceId": "claw.database.macCare",
          "path": "~/.claw/data/mac_care.sqlite"
        }
      }
    }
    """.utf8)

    private static let finalizerActionPlan = ClawJSMacCareClient.ActionPlan(
        id: "mac-care-finalizer-plan",
        createdAt: "2026-05-21T00:00:00.000Z",
        groups: [
            .init(
                id: "mac_care.group.downloads",
                moduleId: "mac_care.module.downloads",
                title: "Downloads",
                routeIds: ["mac_care.route.downloads"],
                candidates: [
                    .init(
                        id: "candidate-trash",
                        routeId: "mac_care.route.downloads",
                        path: "/tmp/home/Downloads/old.dmg",
                        displayName: "old.dmg",
                        sizeBytes: 42,
                        action: "move_to_trash",
                        selection: "blocked",
                        confidence: 0.8,
                        evidence: ["fixture"],
                        warnings: ["large_file"]
                    )
                ]
            )
        ],
        executionAuthority: "agent_plan_only",
        requestedBy: "agent"
    )

    private static let finalizerPreviewFixture = Data("""
    {
      "ok": true,
      "data": {
        "version": 1,
        "status": "finalizer_preview",
        "createdAt": "2026-05-21T00:00:00.000Z",
        "sourcePlanId": "mac-care-finalizer-plan",
        "willExecute": false,
        "receiptIssued": false,
        "executionAuthority": "signed_host_human_confirmed",
        "actions": [
          {
            "id": "finalizer-preview:candidate-trash",
            "candidateId": "candidate-trash",
            "routeId": "mac_care.route.downloads",
            "path": "/tmp/home/Downloads/old.dmg",
            "displayName": "old.dmg",
            "action": "move_to_trash",
            "selection": "blocked",
            "destructive": true,
            "executionAuthority": "signed_host_human_confirmed",
            "requiresHumanConfirmation": true,
            "blockedForAgents": true,
            "rollback": {
              "level": "best_effort",
              "notes": "Signed host may attempt restore from Trash while the item remains available."
            },
            "audit": {
              "event": "mac_care.finalizer.move_to_trash.request",
              "receiptRequired": true,
              "receiptStatus": "not_issued"
            },
            "warnings": ["preview_only_no_execution"]
          }
        ],
        "summary": {
          "totalCandidates": 1,
          "destructiveCandidates": 1,
          "blockedForAgents": 1,
          "receiptsIssued": 0
        },
        "safety": {
          "allowed": false,
          "requiredAuthority": "signed_host_human_confirmed",
          "destructiveActions": ["move_to_trash"],
          "reasons": ["Agents and tests may prepare Mac Care action plans only; destructive execution requires signed host UI confirmation."]
        },
        "sidecar": {
          "filename": "mac_care.sqlite",
          "surfaceId": "claw.database.macCare",
          "path": "~/.claw/data/mac_care.sqlite"
        },
        "executionPolicy": {
          "agentCanExecuteDestructiveActions": false,
          "testCanExecuteDestructiveActions": false,
          "destructiveExecutionAuthority": "signed_host_human_confirmed",
          "realFilesystemMutationInFoundationReport": false
        }
      }
    }
    """.utf8)
}
