import XCTest
@testable import Clawix

final class ClawJSRuntimeLensSessionActionTests: XCTestCase {
    func testRuntimeLensSessionActionsContractsAndSupportContracts() async throws {
        let snapshot = try await ClawJSRuntimeLensTestFixtures.degradedRuntimePortalSnapshot()

        XCTAssertEqual(snapshot.domainData?.sessions?.actionPolicy?.first?.action, "list")
        XCTAssertEqual(snapshot.domainData?.sessions?.actionPolicy?.first?.guardName, "bounded_scan_without_transcript_reads")
        XCTAssertEqual(snapshot.domainData?.sessions?.actionPolicy?.first { $0.action == "pin" }?.authority, "clawix_local_overlay")
        XCTAssertEqual(snapshot.domainData?.sessions?.actionPolicy?.first { $0.action == "pin" }?.writesRuntime, false)
        XCTAssertEqual(snapshot.domainData?.sessions?.actionPolicy?.first { $0.action == "create" }?.wouldWriteRuntime, true)
        XCTAssertEqual(snapshot.domainData?.sessions?.actionPolicy?.first { $0.action == "create" }?.requiredEvidence?.first, "official_create_command_or_api")
        XCTAssertEqual(snapshot.domainData?.sessions?.actionContracts?.map(\.action), [
            "list",
            "preview",
            "resolve",
            "history",
            "send",
            "inject",
            "abort",
            "create",
            "pin",
            "unpin",
            "conflicts"
        ])
        XCTAssertEqual(snapshot.domainData?.sessions?.actionContracts?.first { $0.action == "list" }?.status, "degraded")
        XCTAssertEqual(snapshot.domainData?.sessions?.actionContracts?.first { $0.action == "create" }?.requiredEvidence?.count, 4)
        let sessionActionContractPresentation = ClawJSRuntimeLensSessionActionContractPresentation.make(
            contracts: try XCTUnwrap(snapshot.domainData?.sessions?.actionContracts),
            materializedPolicy: try XCTUnwrap(snapshot.domainData?.sessions?.actionPolicy)
        )
        XCTAssertEqual(sessionActionContractPresentation.contractCount, 11)
        XCTAssertEqual(sessionActionContractPresentation.materializedCount, 11)
        XCTAssertEqual(sessionActionContractPresentation.statusChangedCount, 4)
        XCTAssertEqual(sessionActionContractPresentation.contractOnlyCount, 0)
        XCTAssertEqual(sessionActionContractPresentation.materializedOnlyCount, 0)
        XCTAssertEqual(sessionActionContractPresentation.runtimeWriteContractCount, 0)
        XCTAssertEqual(sessionActionContractPresentation.wouldWriteRuntimeCount, 1)
        XCTAssertEqual(sessionActionContractPresentation.localOverlayContractCount, 2)
        XCTAssertEqual(sessionActionContractPresentation.requiredEvidenceCount, 4)
        XCTAssertEqual(sessionActionContractPresentation.statusChangedActionsLabel, "history, list, preview, resolve")
        XCTAssertEqual(sessionActionContractPresentation.rows.first { $0.action == "list" }?.contractStatus, "degraded")
        XCTAssertEqual(sessionActionContractPresentation.rows.first { $0.action == "list" }?.materializedStatus, "implemented")
        XCTAssertTrue(sessionActionContractPresentation.rows.first { $0.action == "list" }?.statusChanged == true)
        XCTAssertEqual(sessionActionContractPresentation.rows.first { $0.action == "history" }?.materializedStatus, "implemented")
        XCTAssertEqual(sessionActionContractPresentation.rows.first { $0.action == "unpin" }?.authority, "clawix_local_overlay")
        XCTAssertEqual(sessionActionContractPresentation.rows.first { $0.action == "create" }?.contractWriteDisposition, "would write")
        XCTAssertTrue(sessionActionContractPresentation.accessibilityLabel.contains("Runtime session action contracts"))
        XCTAssertTrue(sessionActionContractPresentation.accessibilityLabel.contains("changed actions history, list, preview, resolve"))
        let sessionActionPresentation = ClawJSRuntimeLensSessionActionPresentation.make(
            actions: try XCTUnwrap(snapshot.domainData?.sessions?.actionPolicy)
        )
        XCTAssertEqual(sessionActionPresentation.actionCount, 11)
        XCTAssertEqual(sessionActionPresentation.implementedCount, 5)
        XCTAssertEqual(sessionActionPresentation.blockedCount, 4)
        XCTAssertEqual(sessionActionPresentation.localOverlayCount, 2)
        XCTAssertEqual(sessionActionPresentation.noWriteCount, 11)
        XCTAssertEqual(sessionActionPresentation.wouldWriteRuntimeCount, 1)
        XCTAssertEqual(sessionActionPresentation.requiredEvidenceCount, 4)
        XCTAssertEqual(sessionActionPresentation.statusLabel, "blocked 4, implemented 5, local_overlay_only 2")
        XCTAssertEqual(sessionActionPresentation.localOverlayActionsLabel, "pin, unpin")
        XCTAssertEqual(sessionActionPresentation.blockedActionsLabel, "send, inject, abort, create")
        XCTAssertEqual(sessionActionPresentation.rows.first?.detailLabel, "runtime, metadata_only, bounded_scan_without_transcript_reads")
        XCTAssertEqual(sessionActionPresentation.rows.first { $0.action == "create" }?.writeDisposition, "would write")
        XCTAssertEqual(sessionActionPresentation.rows.first { $0.action == "create" }?.requiredEvidenceCount, 4)
        XCTAssertEqual(
            sessionActionPresentation.rows.first { $0.action == "create" }?.requiredEvidenceLabel,
            "official_create_command_or_api, non_destructive_fixture, confirmation_or_dry_run_policy, round_trip_native_list_evidence"
        )
        XCTAssertTrue(sessionActionPresentation.rows.first { $0.action == "create" }?.accessibilityLabel.contains("required evidence count 4") == true)
        XCTAssertTrue(sessionActionPresentation.rows.first { $0.action == "create" }?.accessibilityLabel.contains("round_trip_native_list_evidence") == true)
        XCTAssertTrue(sessionActionPresentation.accessibilityLabel.contains("Runtime session actions"))
        XCTAssertTrue(sessionActionPresentation.accessibilityLabel.contains("local overlay actions pin, unpin"))
        XCTAssertEqual(snapshot.domainData?.sessions?.supportContract?.validation, "fixture_required")
        XCTAssertEqual(snapshot.domainData?.sessions?.supportContract?.authority, "runtime_adapter")
        XCTAssertEqual(snapshot.domainData?.sessions?.supportContract?.provenance?.source, "runtime-ecosystem-manifest")
        XCTAssertEqual(snapshot.domainData?.sessions?.supportContract?.provenance?.runtimeId, "example")
        XCTAssertEqual(snapshot.domainData?.sessions?.supportContract?.provenance?.domain, "sessions")
        XCTAssertEqual(snapshot.domainData?.sessions?.supportContract?.evidenceRequirements?.first?.id, "example.sessions.write_back_contract")
        XCTAssertEqual(snapshot.domainData?.sessions?.supportContract?.evidenceRequirements?.first?.blockerClass, "direct_blocker")
        XCTAssertEqual(snapshot.domainData?.sessions?.supportContract?.evidenceRequirements?.first?.fallbackPolicy, "do_not_synthesize_native_write_back")
        let supportContractPresentation = ClawJSRuntimeLensSupportContractPresentation.make(snapshot: snapshot)
        XCTAssertEqual(supportContractPresentation.contractDomainCount, 8)
        XCTAssertEqual(supportContractPresentation.writeBackAllowedCount, 0)
        XCTAssertEqual(supportContractPresentation.blockedWriteBackCount, 3)
        XCTAssertEqual(supportContractPresentation.externalPendingCount, 1)
        XCTAssertEqual(supportContractPresentation.evidenceRequirementCount, 2)
        XCTAssertEqual(supportContractPresentation.nativeCommandDomainCount, 0)
        XCTAssertEqual(supportContractPresentation.contractAuthorityDomainCount, 8)
        XCTAssertEqual(supportContractPresentation.provenanceDomainCount, 8)
        XCTAssertEqual(
            supportContractPresentation.validationLabel,
            "config_fixture_required 1, external_pending_for_live_accounts 1, fixture_required 2, model_fixture_required 1, plugin_fixture_required 1, secret_guard 1, snapshot_required 1"
        )
        XCTAssertEqual(
            supportContractPresentation.writeBackPolicyLabel,
            "blocked_until_fixture_coverage 3, external_pending_live_accounts 1"
        )
        XCTAssertEqual(
            supportContractPresentation.contractAuthorityLabel,
            "runtime_adapter 6, runtime_and_host_by_action 1, runtime_config_with_claw_workspace_projection 1"
        )
        XCTAssertEqual(supportContractPresentation.provenanceSourceLabel, "runtime-ecosystem-manifest 8")
        XCTAssertEqual(supportContractPresentation.externalPendingDomainsLabel, "channels")
        XCTAssertTrue(supportContractPresentation.accessibilityLabel.contains("Runtime support contracts"))
        XCTAssertTrue(supportContractPresentation.accessibilityLabel.contains("blocked write back 3"))
        XCTAssertTrue(supportContractPresentation.accessibilityLabel.contains("contract authority domains 8"))
        XCTAssertTrue(supportContractPresentation.accessibilityLabel.contains("provenance domains 8"))
        XCTAssertEqual(supportContractPresentation.rows.first?.domain, "sessions")
        XCTAssertEqual(supportContractPresentation.rows.first?.contractAuthorityLabel, "contract authority: runtime_adapter")
        XCTAssertEqual(supportContractPresentation.rows.first?.provenanceLabel, "runtime-ecosystem-manifest, runtime example, domain sessions")
        XCTAssertEqual(supportContractPresentation.rows.first?.evidenceRequirementCount, 1)
        XCTAssertEqual(supportContractPresentation.rows.first { $0.domain == "channels" }?.externalPending, true)
        XCTAssertEqual(supportContractPresentation.rows.first { $0.domain == "channels" }?.evidenceRequirementCount, 1)
        XCTAssertTrue(supportContractPresentation.rows.first { $0.domain == "channels" }?.accessibilityLabel.contains("contract authority runtime_adapter") == true)
        XCTAssertTrue(supportContractPresentation.rows.first { $0.domain == "channels" }?.accessibilityLabel.contains("provenance domain channels") == true)
        XCTAssertTrue(supportContractPresentation.rows.first { $0.domain == "auth" }?.accessibilityLabel.contains("validation secret_guard") == true)
        XCTAssertEqual(snapshot.resources(for: "skills").first?.path, "/Users/tester/.example/skills")
        XCTAssertEqual(snapshot.domainData?.skills?.supportContract?.validation, "snapshot_required")
        XCTAssertEqual(snapshot.resources(for: "channels").map(\.displayLabel), ["Channel A", "Channel B"])
        XCTAssertEqual(snapshot.domainData?.channels?.supportContract?.evidenceRequirements?.first?.expectedEvidence?.last, "no_plaintext_secrets")
        XCTAssertEqual(snapshot.domainData?.channels?.supportContract?.evidenceRequirements?.first?.reentryCondition, "approve_and_run_runtime_example_domain_channels_read_only_evidence")
        XCTAssertEqual(snapshot.resources(for: "providers").first?.id, "openai")
        XCTAssertEqual(snapshot.resources(for: "auth").map(\.id), ["anthropic", "openai"])
        XCTAssertEqual(snapshot.resources(for: "auth").first { $0.id == "openai" }?.status, "configured")
        XCTAssertEqual(snapshot.resources(for: "auth").first { $0.id == "openai" }?.kind, "env")
        XCTAssertEqual(snapshot.resources(for: "gateway").first?.status, "degraded")
        XCTAssertEqual(snapshot.resources(for: "doctorCompat").first?.summary, "example CLI not found")
        XCTAssertEqual(snapshot.resources(for: "sandboxPermissions").first?.kind, "hosted")
        XCTAssertEqual(snapshot.resources(for: "configuration").map(\.id), ["SOUL", "USER", "managed-file-1", "configuration-diagnostics"])
        XCTAssertEqual(snapshot.resources(for: "configuration").first?.status, "projected")
        XCTAssertEqual(snapshot.resources(for: "configuration").first { $0.id == "managed-file-1" }?.path, "/tmp/workspace/AGENTS.md")
        XCTAssertEqual(snapshot.resources(for: "configuration").first { $0.id == "configuration-diagnostics" }?.summary, "config drift in fixture")
    }

    func testRuntimeLensClientAppliesRuntimeSessionLocalOverlayActions() async throws {
        var requested: [[String]] = []
        let client = ClawJSRuntimeLensClient(runner: .init { args in
            requested.append(args)
            return .init(
                data: try ClawJSRuntimeLensTestFixtures.data(named: "session-local-overlay-action"),
                exitCode: 0
            )
        })

        let result = try await client.setSessionPinned(
            runtime: .hermes,
            sessionId: "2026/05/21/runtime-session",
            pinned: true
        )

        XCTAssertEqual(requested, [[
            "runtime",
            "hermes",
            "sessions",
            "pin",
            "--session-key",
            "2026/05/21/runtime-session",
            "--json"
        ]])
        XCTAssertEqual(result.status, "local_overlay_applied")
        XCTAssertEqual(result.writesRuntime, false)
        XCTAssertEqual(result.writesLocalOverlay, true)
        XCTAssertEqual(result.result.overlayThreadId, "runtime:hermes:sessions:2026%2F05%2F21%2Fruntime-session")
        XCTAssertEqual(result.result.receipt?.hostId, "runtime-portal")
    }
}
