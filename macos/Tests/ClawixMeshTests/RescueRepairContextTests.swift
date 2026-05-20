import XCTest
@testable import Clawix

final class RescueRepairContextTests: XCTestCase {
    func testBuildsAgentRepairContextFromEvolutionRepairReport() throws {
        let decision = RescueSurvivalPolicy.evaluate(
            signals: [.migrationFailure, .storageUnavailable],
            availableRuntimeCount: 1
        )
        let package = RescueRepairContextBuilder.build(
            decision: decision,
            evolutionEnvelopeData: Self.fixtureRepairEnvelope,
            diagnosticFiles: [
                URL(fileURLWithPath: "/Users/private/Library/Application Support/com.clawix.app/Diagnostics/\(ResourceSampler.lastResourcesFileName)"),
                URL(fileURLWithPath: "/Users/private/Library/Application Support/com.clawix.app/Diagnostics/repair-receipt.json")
            ],
            runtimeHealth: RescueRuntimeHealthSnapshot(
                processCpuPercent: 28,
                residentBytes: 100_000,
                footprintBytes: 120_000,
                bridgeReachable: false,
                runtimeCount: 1
            )
        )

        XCTAssertEqual(package.schemaVersion, 1)
        XCTAssertEqual(package.mode, .ephemeralChat)
        XCTAssertTrue(package.canLaunch)
        XCTAssertTrue(package.canChat)
        XCTAssertTrue(package.canRunAgent)
        XCTAssertEqual(package.evolutionStatus, "needs_approval")
        XCTAssertEqual(package.migrationLabStatus, "pass")
        XCTAssertTrue(package.safeActions.contains { $0.command == "claw evolution doctor --json" })
        XCTAssertTrue(package.approvalRequiredActions.contains { $0.id == "mutate_local_state" })
        XCTAssertTrue(package.approvalRequiredActions.contains { $0.id == "risky_repair_requires_approval" })
        XCTAssertEqual(package.suggestedPatch?.format, "unified_diff")
        XCTAssertEqual(package.suggestedPatch?.redacted, true)
        XCTAssertFalse(package.suggestedPatch?.diff.contains("/Users/") ?? true)
        XCTAssertFalse(package.suggestedPatch?.diff.contains("sk-") ?? true)
        XCTAssertEqual(package.receipt?.receiptId, "evo_receipt_test")
        XCTAssertEqual(package.redaction.externalSubmission, "explicit_approval_only")
        XCTAssertFalse(package.redaction.promptsIncluded)
        XCTAssertFalse(package.redaction.secretsIncluded)
        XCTAssertFalse(package.redaction.fullLocalPathsIncluded)
        XCTAssertEqual(package.diagnosticReferences.map(\.name), [ResourceSampler.lastResourcesFileName, "repair-receipt.json"])
        XCTAssertTrue(package.agentInstructions.contains { $0.contains("ephemeral chat") })
    }

    func testBuildsOfflineDiagnosticsOnlyContextWhenEvolutionCliUnavailable() {
        let decision = RescueSurvivalPolicy.evaluate(
            signals: [.bridgeRuntimeDown],
            availableRuntimeCount: 0
        )
        let package = RescueRepairContextBuilder.build(
            decision: decision,
            evolutionEnvelopeData: nil,
            diagnosticFiles: [URL(fileURLWithPath: "/Users/private/Library/Application Support/com.clawix.app/Diagnostics/app.log")]
        )

        XCTAssertEqual(package.mode, .diagnosticsOnly)
        XCTAssertTrue(package.canLaunch)
        XCTAssertFalse(package.canChat)
        XCTAssertFalse(package.canRunAgent)
        XCTAssertEqual(package.evolutionStatus, "offline_unavailable")
        XCTAssertNil(package.suggestedPatch)
        XCTAssertNil(package.receipt)
        XCTAssertTrue(package.safeActions.contains { $0.id == "open_diagnostics" })
        XCTAssertTrue(package.safeActions.contains { $0.id == "preserve_ephemeral_chat" })
        XCTAssertTrue(package.approvalRequiredActions.contains { $0.id == "risky_repair_requires_approval" })
        XCTAssertEqual(package.diagnosticReferences.first?.name, "app.log")
        XCTAssertTrue(package.agentInstructions.contains { $0.contains("evolution CLI report is unavailable") })
    }

    @MainActor
    func testEvolutionCommandClientUsesRepairDoctorAndDryRunCommands() throws {
        var seen: [[String]] = []
        let client = RescueEvolutionCommandClient(runner: .init { args in
            seen.append(args)
            return Data(#"{"ok":true,"data":{"status":"ok"}}"#.utf8)
        })

        _ = try client.repairReport(fromVersion: "v1", toVersion: "current")
        _ = try client.doctor()
        _ = try client.dryRun(fromVersion: "v1", toVersion: "current")

        XCTAssertEqual(seen[0], ["evolution", "repair", "--json", "--from", "v1", "--to", "current"])
        XCTAssertEqual(seen[1], ["evolution", "doctor", "--json"])
        XCTAssertEqual(seen[2], ["evolution", "dry-run", "--json", "--from", "v1", "--to", "current"])
    }

    @MainActor
    func testExporterWritesRedactedRescueContextJson() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("RescueRepairContextTests-\(UUID().uuidString)", isDirectory: true)
        let destination = tempDir.appendingPathComponent("rescue-context.json")
        let decision = RescueSurvivalPolicy.evaluate(signals: [.migrationFailure], availableRuntimeCount: 1)

        let export = try RescueRepairContextExporter.write(
            decision: decision,
            evolutionEnvelopeData: Self.fixtureRepairEnvelope,
            diagnosticFiles: [URL(fileURLWithPath: "/Users/private/Library/Application Support/com.clawix.app/Diagnostics/\(ResourceSampler.lastResourcesFileName)")],
            runtimeHealth: RescueRuntimeHealthSnapshot(
                processCpuPercent: 95,
                residentBytes: 1_024,
                footprintBytes: 2_048,
                bridgeReachable: true,
                runtimeCount: 1
            ),
            destinationURL: destination
        )

        XCTAssertEqual(export.url, destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        let data = try Data(contentsOf: destination)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("/Users/"))
        XCTAssertFalse(text.contains("sk-"))
        XCTAssertTrue(text.contains("explicit_approval_only"))

        let decoded = try JSONDecoder().decode(RescueRepairContextPackage.self, from: data)
        XCTAssertEqual(decoded.mode, .ephemeralChat)
        XCTAssertEqual(decoded.evolutionStatus, "needs_approval")
        XCTAssertEqual(decoded.diagnosticReferences.map(\.name), [ResourceSampler.lastResourcesFileName])
        XCTAssertEqual(decoded.suggestedPatch?.redacted, true)

        try? FileManager.default.removeItem(at: tempDir)
    }

    func testResourceSamplerBuildsPostMortemHealthSnapshotFromPersistedDiagnostics() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("RescueResourceSamplerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let sampleURL = tempDir.appendingPathComponent(ResourceSampler.lastResourcesFileName)
        try Data("""
        {
          "timestamp": 1779123456,
          "residentBytes": 2048,
          "footprintBytes": 4096,
          "processCpuPercent": 87.5,
          "appVersion": "1.0",
          "buildNumber": "100"
        }
        """.utf8).write(to: sampleURL)

        let snapshot = try XCTUnwrap(ResourceSampler.persistedHealthSnapshot(
            from: sampleURL,
            bridgeReachable: false,
            runtimeCount: 1
        ))

        XCTAssertTrue(snapshot.hasResourceMetrics)
        XCTAssertEqual(snapshot.processCpuPercent, 87.5)
        XCTAssertEqual(snapshot.residentBytes, 2_048)
        XCTAssertEqual(snapshot.footprintBytes, 4_096)
        XCTAssertEqual(snapshot.bridgeReachable, false)
        XCTAssertEqual(snapshot.runtimeCount, 1)

        try? FileManager.default.removeItem(at: tempDir)
    }

    private static let fixtureRepairEnvelope = Data("""
    {
      "ok": true,
      "data": {
        "status": "approval_gated_plan",
        "repairReport": {
          "status": "needs_approval",
          "diagnostics": {
            "migrationLabStatus": "pass"
          },
          "safeActions": [
            {
              "id": "run_doctor",
              "title": "Run evolution doctor",
              "command": "claw evolution doctor --json",
              "reason": "Collect a current compatibility snapshot without mutating state."
            }
          ],
          "approvalRequiredActions": [
            {
              "id": "mutate_local_state",
              "title": "Mutate local state",
              "reason": "Repair can change files or databases and needs explicit approval."
            }
          ],
          "patch": {
            "format": "unified_diff",
            "status": "suggested",
            "redacted": true,
            "diff": "diff --git a/docs/evolution/REPAIR_REPORT.md b/docs/evolution/REPAIR_REPORT.md\\n+prompt: fix /Users/private/app with sk-1234567890abcdef"
          },
          "receipt": {
            "receiptId": "evo_receipt_test",
            "status": "planned"
          },
          "redaction": {
            "privacy": "redacted",
            "promptsIncluded": false,
            "secretsIncluded": false,
            "fullLocalPathsIncluded": false,
            "externalSubmission": "explicit_approval_only"
          }
        }
      }
    }
    """.utf8)
}
