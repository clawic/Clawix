import XCTest
@testable import Clawix

final class ClawJSRuntimeLensSessionActionTests: XCTestCase {
    func testHermesRuntimePortalSessionActionsCommandsAndOverlays() async throws {
        let snapshot = try await ClawJSRuntimeLensTestFixtures.hermesRuntimePortalSnapshot()
        let sessionBucket = try XCTUnwrap(snapshot.domainData?.sessions)

        XCTAssertEqual(sessionBucket.actionPolicy?.map(\.action), [
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
        XCTAssertEqual(sessionBucket.actionPolicy?.first { $0.action == "send" }?.status, "blocked")
        XCTAssertEqual(sessionBucket.actionPolicy?.first { $0.action == "send" }?.guardName, "blocked_until_tui_gateway_wrapper_fixture")
        XCTAssertEqual(sessionBucket.actionPolicy?.first { $0.action == "send" }?.officialMethod, "prompt.submit")
        XCTAssertEqual(sessionBucket.actionPolicy?.first { $0.action == "inject" }?.status, "blocked")
        XCTAssertEqual(sessionBucket.actionPolicy?.first { $0.action == "inject" }?.officialMethod, "session.steer")
        XCTAssertEqual(sessionBucket.actionPolicy?.first { $0.action == "abort" }?.status, "blocked")
        XCTAssertEqual(sessionBucket.actionPolicy?.first { $0.action == "abort" }?.officialMethod, "session.interrupt")
        XCTAssertEqual(sessionBucket.actionPolicy?.first { $0.action == "create" }?.wouldWriteRuntime, true)
        XCTAssertEqual(sessionBucket.actionPolicy?.first { $0.action == "create" }?.officialMethod, "session.create")
        XCTAssertEqual(sessionBucket.actionPolicy?.first { $0.action == "pin" }?.authority, "clawix_local_overlay")
        XCTAssertEqual(sessionBucket.actionPolicy?.first { $0.action == "pin" }?.writesRuntime, false)
        XCTAssertEqual(sessionBucket.actionPolicy?.first { $0.action == "unpin" }?.authority, "clawix_local_overlay")

        let actionPresentation = ClawJSRuntimeLensSessionActionPresentation.make(
            actions: try XCTUnwrap(sessionBucket.actionPolicy)
        )
        XCTAssertEqual(actionPresentation.actionCount, 11)
        XCTAssertEqual(actionPresentation.implementedCount, 5)
        XCTAssertEqual(actionPresentation.blockedCount, 4)
        XCTAssertEqual(actionPresentation.localOverlayCount, 2)
        XCTAssertEqual(actionPresentation.noWriteCount, 11)
        XCTAssertEqual(actionPresentation.wouldWriteRuntimeCount, 4)
        XCTAssertEqual(actionPresentation.requiredEvidenceCount, 16)
        XCTAssertEqual(actionPresentation.statusLabel, "blocked 4, implemented 5, local_overlay_only 2")
        XCTAssertEqual(actionPresentation.blockedActionsLabel, "send, inject, abort, create")
        XCTAssertEqual(actionPresentation.localOverlayActionsLabel, "pin, unpin")
        XCTAssertEqual(actionPresentation.rows.first { $0.action == "send" }?.writeDisposition, "would write")
        XCTAssertEqual(actionPresentation.rows.first { $0.action == "send" }?.requiredEvidenceCount, 4)
        XCTAssertEqual(
            actionPresentation.rows.first { $0.action == "send" }?.requiredEvidenceLabel,
            "tui_gateway_prompt_submit_fixture, non_destructive_fixture, confirmation_or_dry_run_policy, round_trip_native_visibility"
        )
        XCTAssertEqual(actionPresentation.rows.first { $0.action == "send" }?.delegatesTo, "tui_gateway.prompt.submit")
        XCTAssertEqual(actionPresentation.rows.first { $0.action == "send" }?.officialProtocol, "tui_gateway_json_rpc")
        XCTAssertEqual(actionPresentation.rows.first { $0.action == "send" }?.officialMethod, "prompt.submit")
        XCTAssertEqual(actionPresentation.rows.first { $0.action == "send" }?.transportPolicyId, "hermes.tui_gateway.transport_lifecycle_policy")
        XCTAssertEqual(actionPresentation.rows.first { $0.action == "send" }?.productionTransportStatus, "blocked_until_production_transport_lifecycle_policy")
        XCTAssertEqual(actionPresentation.rows.first { $0.action == "send" }?.lifecycleStatus, "external_user_managed_not_started_by_claw")
        XCTAssertEqual(
            actionPresentation.rows.first { $0.action == "send" }?.officialContractSource,
            "https://hermes-agent.nousresearch.com/docs/developer-guide/programmatic-integration"
        )
        XCTAssertTrue(actionPresentation.rows.first { $0.action == "send" }?.accessibilityLabel.contains("official protocol tui_gateway_json_rpc") == true)
        XCTAssertTrue(actionPresentation.rows.first { $0.action == "send" }?.accessibilityLabel.contains("transport policy hermes.tui_gateway.transport_lifecycle_policy") == true)
        XCTAssertTrue(actionPresentation.rows.first { $0.action == "send" }?.detailLabel?.hasPrefix("transport policy hermes.tui_gateway.transport_lifecycle_policy") == true)
        XCTAssertTrue(actionPresentation.rows.first { $0.action == "send" }?.detailLabel?.contains("production transport blocked_until_production_transport_lifecycle_policy") == true)
        XCTAssertTrue(actionPresentation.rows.first { $0.action == "send" }?.detailLabel?.contains("lifecycle external_user_managed_not_started_by_claw") == true)
        XCTAssertEqual(actionPresentation.rows.first { $0.action == "create" }?.writeDisposition, "would write")
        XCTAssertEqual(actionPresentation.rows.first { $0.action == "pin" }?.authority, "clawix_local_overlay")
        XCTAssertEqual(actionPresentation.rows.first { $0.action == "pin" }?.userVisibleContract, "local_overlay_only_until_official_runtime_pin_api_exists")
        XCTAssertEqual(actionPresentation.rows.first { $0.action == "pin" }?.claimEffect, "blocks_native_write_back_parity_not_local_overlay")
        XCTAssertTrue(actionPresentation.rows.first { $0.action == "pin" }?.accessibilityLabel.contains("user visible contract local_overlay_only_until_official_runtime_pin_api_exists") == true)
        XCTAssertTrue(actionPresentation.accessibilityLabel.contains("blocked actions send, inject, abort, create"))
        XCTAssertTrue(actionPresentation.accessibilityLabel.contains("local overlay actions pin, unpin"))

        let contractPresentation = ClawJSRuntimeLensSessionActionContractPresentation.make(
            contracts: try XCTUnwrap(sessionBucket.actionContracts),
            materializedPolicy: try XCTUnwrap(sessionBucket.actionPolicy)
        )
        XCTAssertEqual(contractPresentation.contractCount, 11)
        XCTAssertEqual(contractPresentation.materializedCount, 11)
        XCTAssertEqual(contractPresentation.statusChangedCount, 4)
        XCTAssertEqual(contractPresentation.runtimeWriteContractCount, 0)
        XCTAssertEqual(contractPresentation.wouldWriteRuntimeCount, 4)
        XCTAssertEqual(contractPresentation.localOverlayContractCount, 2)
        XCTAssertEqual(contractPresentation.nativeWriteBackBlockedCount, 2)
        XCTAssertEqual(contractPresentation.rows.first { $0.action == "history" }?.statusChanged, true)
        XCTAssertEqual(contractPresentation.rows.first { $0.action == "create" }?.contractWriteDisposition, "would write")
        XCTAssertEqual(contractPresentation.rows.first { $0.action == "create" }?.delegatesTo, "tui_gateway.session.create")
        XCTAssertEqual(contractPresentation.rows.first { $0.action == "create" }?.officialProtocol, "tui_gateway_json_rpc")
        XCTAssertEqual(contractPresentation.rows.first { $0.action == "create" }?.officialMethod, "session.create")
        XCTAssertEqual(contractPresentation.rows.first { $0.action == "create" }?.transportPolicyId, "hermes.tui_gateway.transport_lifecycle_policy")
        XCTAssertEqual(contractPresentation.rows.first { $0.action == "send" }?.transportPolicyId, "hermes.tui_gateway.transport_lifecycle_policy")
        XCTAssertEqual(contractPresentation.rows.first { $0.action == "send" }?.productionTransportStatus, "blocked_until_production_transport_lifecycle_policy")
        XCTAssertEqual(
            contractPresentation.rows.first { $0.action == "create" }?.officialContractSource,
            "https://hermes-agent.nousresearch.com/docs/developer-guide/programmatic-integration"
        )
        XCTAssertTrue(contractPresentation.rows.first { $0.action == "create" }?.accessibilityLabel.contains("official protocol tui_gateway_json_rpc") == true)
        XCTAssertEqual(contractPresentation.rows.first { $0.action == "pin" }?.authority, "clawix_local_overlay")
        XCTAssertEqual(contractPresentation.rows.first { $0.action == "pin" }?.nativeWriteBackStatus, "blocked_until_official_runtime_write_back_contract")
        XCTAssertEqual(contractPresentation.rows.first { $0.action == "pin" }?.nativeWriteBackSafeDefault, "keep_local_overlay_and_do_not_write_runtime_pin_state")
        XCTAssertEqual(contractPresentation.rows.first { $0.action == "pin" }?.evidenceRequirementId, "hermes.sessions.pin.native_write_back_contract")
        XCTAssertEqual(contractPresentation.rows.first { $0.action == "pin" }?.userVisibleContract, "local_overlay_only_until_official_runtime_pin_api_exists")
        XCTAssertEqual(contractPresentation.rows.first { $0.action == "pin" }?.claimEffect, "blocks_native_write_back_parity_not_local_overlay")
        XCTAssertTrue(contractPresentation.rows.first { $0.action == "pin" }?.accessibilityLabel.contains("claim effect blocks_native_write_back_parity_not_local_overlay") == true)
        XCTAssertTrue(contractPresentation.accessibilityLabel.contains("native write-back blocked 2"))

        let commandPresentation = ClawJSRuntimeLensCommandMatrixPresentation.make(
            commands: try XCTUnwrap(snapshot.commands)
        )
        XCTAssertEqual(commandPresentation.authority, "runtime_adapter")
        XCTAssertEqual(commandPresentation.executableCount, 22)
        XCTAssertEqual(commandPresentation.writesRuntimeCount, 0)
        XCTAssertEqual(commandPresentation.wouldWriteRuntimeCount, 4)
        XCTAssertEqual(commandPresentation.localOverlayCommandCount, 2)
        XCTAssertEqual(commandPresentation.nativeWriteBackBlockedCount, 6)
        XCTAssertEqual(commandPresentation.readLocalCount, 18)
        XCTAssertEqual(commandPresentation.argumentCommandCount, 4)
        XCTAssertEqual(commandPresentation.argumentCount, 6)
        XCTAssertEqual(commandPresentation.resourceDomainCount, ClawJSRuntimeLensSnapshot.canonicalDomains.count)
        XCTAssertEqual(commandPresentation.resourceDomainsLabel, "sessions, skills, memory, channels, providers")
        XCTAssertEqual(commandPresentation.rows.first?.command, "runtime hermes sessions send --session-key <id> --message <text> --confirm-runtime-write")
        XCTAssertEqual(commandPresentation.rows.first?.writeDisposition, "blocked write")
        XCTAssertEqual(commandPresentation.rows.first?.blockerClass, "direct_blocker")
        XCTAssertEqual(commandPresentation.rows.first?.nativeWriteBackStatus, "blocked_until_tui_gateway_wrapper_fixture")
        XCTAssertEqual(commandPresentation.rows.first?.nativeWriteBackBlockerClass, "direct_blocker")
        XCTAssertEqual(commandPresentation.rows.first?.nativeWriteBackFixtureRequired, true)
        XCTAssertEqual(commandPresentation.rows.first?.nativeWriteBackSafeDefault, "keep_unpromoted_and_do_not_synthesize_runtime_state")
        XCTAssertEqual(commandPresentation.rows.first?.safeDefault, "keep_unpromoted_and_do_not_synthesize_runtime_state")
        XCTAssertEqual(commandPresentation.rows.first?.userVisibleContract, "non_executable_until_tui_gateway_wrapper_fixture_exists")
        XCTAssertEqual(commandPresentation.rows.first?.claimEffect, "blocks_recommended_production_native_parity")
        XCTAssertEqual(commandPresentation.rows.first?.supportResolution, "explicitly_product_blocked_not_a_silent_gap")
        XCTAssertEqual(commandPresentation.rows.first?.evidenceRequirementId, "hermes.sessions.send.action_contract")
        XCTAssertEqual(commandPresentation.rows.first?.requiredEvidenceLabel, "tui_gateway_prompt_submit_fixture, non_destructive_fixture, confirmation_or_dry_run_policy, round_trip_native_visibility")
        XCTAssertEqual(commandPresentation.rows.first?.transportPolicyId, "hermes.tui_gateway.transport_lifecycle_policy")
        XCTAssertEqual(commandPresentation.rows.first?.configuredEndpointClass, "none")
        XCTAssertEqual(commandPresentation.rows.first?.productionTransportStatus, "blocked_until_production_transport_lifecycle_policy")
        XCTAssertEqual(commandPresentation.rows.first?.lifecycleStatus, "external_user_managed_not_started_by_claw")
        XCTAssertEqual(commandPresentation.rows.first?.productionTransportCommandShape, "blocked_until_approved_production_transport_lifecycle_policy_and_non_loopback_endpoint_approval")
        XCTAssertEqual(commandPresentation.rows.first?.doNotRunWithoutApproval, true)
        XCTAssertEqual(commandPresentation.rows.first?.claimBlockedUntil, "production_transport_lifecycle_policy_and_native_round_trip_evidence_attached")
        XCTAssertEqual(commandPresentation.rows.first?.requiredEndpoint, "loopback_http_json_rpc")
        XCTAssertTrue(commandPresentation.rows.first?.accessibilityLabel.contains("user visible contract non_executable_until_tui_gateway_wrapper_fixture_exists") == true)
        XCTAssertTrue(commandPresentation.rows.first?.accessibilityLabel.contains("required evidence tui_gateway_prompt_submit_fixture") == true)
        XCTAssertTrue(commandPresentation.rows.first?.accessibilityLabel.contains("transport policy hermes.tui_gateway.transport_lifecycle_policy") == true)
        XCTAssertTrue(commandPresentation.rows.first?.accessibilityLabel.contains("production command blocked_until_approved_production_transport_lifecycle_policy_and_non_loopback_endpoint_approval") == true)
        XCTAssertTrue(commandPresentation.rows.first?.accessibilityLabel.contains("do not run without approval") == true)
        XCTAssertTrue(commandPresentation.rows.contains { $0.command == "runtime hermes sessions conflicts" })
        XCTAssertTrue(commandPresentation.rows.contains { $0.command == "runtime hermes sessions send --session-key <id> --message <text> --confirm-runtime-write" })
        let pinCommandRow = try XCTUnwrap(commandPresentation.rows.first { $0.command == "runtime hermes sessions pin --session-key <id>" })
        XCTAssertEqual(pinCommandRow.writeDisposition, "local overlay, native blocked")
        XCTAssertEqual(pinCommandRow.nativeWriteBackStatus, "blocked_until_official_runtime_write_back_contract")
        XCTAssertEqual(pinCommandRow.nativeWriteBackSafeDefault, "keep_local_overlay_and_do_not_write_runtime_pin_state")
        XCTAssertEqual(pinCommandRow.evidenceRequirementId, "hermes.sessions.pin.native_write_back_contract")
        XCTAssertTrue(pinCommandRow.accessibilityLabel.contains("native write-back blocked_until_official_runtime_write_back_contract"))
        XCTAssertTrue(commandPresentation.accessibilityLabel.contains("would write runtime 4"))
        XCTAssertTrue(commandPresentation.accessibilityLabel.contains("local overlay 2"))
        XCTAssertTrue(commandPresentation.accessibilityLabel.contains("native write-back blocked 6"))
        XCTAssertTrue(commandPresentation.accessibilityLabel.contains("resource domains 13"))

        let overlayPresentation = ClawJSRuntimeLensSessionOverlayPresentation.make(
            state: try XCTUnwrap(sessionBucket.overlayState)
        )
        XCTAssertEqual(overlayPresentation.runtimeId, "hermes")
        XCTAssertEqual(overlayPresentation.overlayAuthority, "clawix_local_overlay")
        XCTAssertEqual(overlayPresentation.writesRuntime, false)
        XCTAssertEqual(overlayPresentation.writeBackStatus, "blocked_until_official_runtime_pin_api")
        XCTAssertEqual(overlayPresentation.conflictPolicy, ClawJSRuntimeLensSessionOverlayPresentation.noSilentOverwritePolicy)
        XCTAssertEqual(overlayPresentation.totalOverlays, 0)
        XCTAssertEqual(overlayPresentation.totalConflicts, 0)
        XCTAssertEqual(overlayPresentation.rows, [])
        XCTAssertTrue(overlayPresentation.accessibilityLabel.contains("writes runtime false"))
        XCTAssertTrue(overlayPresentation.accessibilityLabel.contains("authority clawix_local_overlay"))
    }

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
        XCTAssertEqual(sessionActionPresentation.rows.first?.detailLabel, "runtime, metadata_only, runtime session path metadata projection, bounded_scan_without_transcript_reads")
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
        XCTAssertEqual(result.wouldWriteRuntime, false)
        XCTAssertEqual(result.writesLocalOverlay, true)
        XCTAssertEqual(result.writeBackStatus, "blocked_until_official_runtime_write_back_contract")
        XCTAssertEqual(result.nativeWriteBackStatus, "blocked_until_official_runtime_write_back_contract")
        XCTAssertEqual(result.nativeWriteBackBlockerClass, "direct_blocker")
        XCTAssertEqual(result.officialRuntimeWriteBackContractRequired, true)
        XCTAssertEqual(result.officialRuntimeWriteBackContractKnown, false)
        XCTAssertEqual(result.nativeWriteBackFixtureRequired, true)
        XCTAssertEqual(result.nativeWriteBackSafeDefault, "keep_local_overlay_and_do_not_write_runtime_pin_state")
        XCTAssertEqual(result.userVisibleContract, "local_overlay_only_until_official_runtime_pin_api_exists")
        XCTAssertEqual(result.claimEffect, "blocks_native_write_back_parity_not_local_overlay")
        XCTAssertEqual(result.supportResolution, "explicitly_product_blocked_not_a_silent_gap")
        XCTAssertEqual(result.evidenceRequirementId, "hermes.sessions.pin.native_write_back_contract")
        XCTAssertEqual(result.riskControls?.contains("no_silent_runtime_write"), true)
        XCTAssertEqual(result.nativeWriteBackContract?.status, "blocked")
        XCTAssertEqual(result.nativeWriteBackContract?.writesRuntime, false)
        XCTAssertEqual(result.nativeWriteBackContract?.wouldWriteRuntime, false)
        XCTAssertEqual(result.nativeWriteBackContract?.officialContractRequired, true)
        XCTAssertEqual(result.nativeWriteBackContract?.officialContractKnown, false)
        XCTAssertEqual(result.nativeWriteBackContract?.fixtureRequired, true)
        XCTAssertEqual(result.nativeWriteBackContract?.safeDefault, "keep_local_overlay_and_do_not_write_runtime_pin_state")
        XCTAssertEqual(result.nativeWriteBackContract?.evidenceRequirementId, "hermes.sessions.pin.native_write_back_contract")
        XCTAssertEqual(result.result.overlayThreadId, "runtime:hermes:sessions:2026%2F05%2F21%2Fruntime-session")
        XCTAssertEqual(result.result.receipt?.hostId, "runtime-portal")
    }

    func testRuntimeLensClientRunsHermesGatewaySessionActionsWithExplicitConfirmation() async throws {
        var requested: [[String]] = []
        let client = ClawJSRuntimeLensClient(runner: .init { args in
            requested.append(args)
            return .init(
                data: """
                {
                  "data": {
                    "runtimeId": "hermes",
                    "domain": "sessions",
                    "action": "send",
                    "status": "ok",
                    "authority": "runtime",
                    "writesRuntime": true,
                    "wouldWriteRuntime": true,
                    "writesLocalOverlay": false,
                    "officialProtocol": "tui_gateway_json_rpc",
                    "officialMethod": "prompt.submit",
                    "officialContractSource": "https://hermes-agent.nousresearch.com/docs/developer-guide/programmatic-integration",
                    "result": {
                      "id": "2026/05/21/runtime-session",
                      "messagePreview": "fixture hello",
                      "nativeIdentifier": {"name": "session_id"},
                      "gatewayReceipt": {
                        "protocol": "tui_gateway_json_rpc",
                        "transport": "loopback_http_json_rpc_fixture",
                        "method": "prompt.submit",
                        "requestId": "fixture-rpc",
                        "endpoint": "http://127.0.0.1:18789"
                      }
                    }
                  }
                }
                """.data(using: .utf8)!,
                exitCode: 0
            )
        })

        let result = try await client.runSessionAction(
            runtime: .hermes,
            action: "send",
            sessionId: "2026/05/21/runtime-session",
            message: "fixture hello",
            gatewayURL: "http://127.0.0.1:18789",
            confirmRuntimeWrite: true
        )

        XCTAssertEqual(requested, [[
            "runtime",
            "hermes",
            "sessions",
            "send",
            "--session-key",
            "2026/05/21/runtime-session",
            "--message",
            "fixture hello",
            "--gateway-url",
            "http://127.0.0.1:18789",
            "--confirm-runtime-write",
            "--json"
        ]])
        XCTAssertEqual(result.status, "ok")
        XCTAssertEqual(result.writesRuntime, true)
        XCTAssertEqual(result.officialProtocol, "tui_gateway_json_rpc")
        XCTAssertEqual(result.officialMethod, "prompt.submit")
        XCTAssertEqual(result.result?.nativeIdentifier?.name, "session_id")
        XCTAssertEqual(result.result?.gatewayReceipt?.method, "prompt.submit")
        XCTAssertEqual(result.result?.gatewayReceipt?.transport, "loopback_http_json_rpc_fixture")
    }

    @MainActor
    func testRuntimeLensClientSurfacesHermesProductionEndpointPolicyBlock() async throws {
        var requested: [[String]] = []
        let client = ClawJSRuntimeLensClient(runner: .init { args in
            requested.append(args)
            return .init(
                data: """
                {
                  "data": {
                    "runtimeId": "hermes",
                    "domain": "sessions",
                    "action": "send",
                    "status": "blocked",
                    "authority": "runtime",
                    "writesRuntime": false,
                    "wouldWriteRuntime": true,
                    "writesLocalOverlay": false,
                    "reason": "Hermes TUI gateway writes are currently limited to explicit loopback fixture endpoints.",
                    "blockerClass": "direct_blocker",
                    "officialContractRequired": false,
                    "officialContractKnown": true,
                    "officialProtocol": "tui_gateway_json_rpc",
                    "officialMethod": "prompt.submit",
                    "officialContractSource": "https://hermes-agent.nousresearch.com/docs/developer-guide/programmatic-integration",
                    "integrationRequired": true,
                    "fixtureRequired": true,
                    "requiredEvidence": [
                      "tui_gateway_prompt_submit_fixture",
                      "non_destructive_fixture",
                      "confirmation_or_dry_run_policy",
                      "round_trip_native_visibility"
                    ],
                    "riskControls": [
                      "no_silent_runtime_write",
                      "no_direct_runtime_store_mutation",
                      "local_overlay_only_until_contract_exists"
                    ],
                    "writeBackStatus": "blocked_until_tui_gateway_wrapper_fixture",
                    "fallbackPolicy": "do_not_synthesize_native_runtime_action",
                    "supportResolution": "explicitly_product_blocked_not_a_silent_gap",
                    "productDecision": "production_gateway_transport_blocked_until_lifecycle_policy_and_approval",
                    "userVisibleContract": "non_loopback_gateway_endpoint_rejected_until_production_transport_lifecycle_policy",
                    "claimEffect": "blocks_recommended_production_native_parity",
                    "promotionGate": "session_action_claim_remains_blocked_until_production_transport_lifecycle_policy_and_native_round_trip_evidence_exist",
                    "safeDefault": "fixture_only_no_production_transport_contact",
                    "commandShape": "runtime hermes sessions send --session-key <id> --message <text> --confirm-runtime-write --json",
                    "evidenceRequirementId": "hermes.sessions.send.action_contract",
                    "evidenceReentryStatus": "blocked_until_tui_gateway_wrapper_fixture",
                    "transportPolicyId": "hermes.tui_gateway.transport_lifecycle_policy",
                    "transportPolicy": {
                      "id": "hermes.tui_gateway.transport_lifecycle_policy",
                      "protocol": "tui_gateway_json_rpc",
                      "fixtureTransport": "loopback_http_json_rpc_fixture",
                      "productionTransportStatus": "blocked_until_production_transport_lifecycle_policy",
                      "lifecycleStatus": "external_user_managed_not_started_by_claw",
                      "lifecycleOwner": "hermes_runtime_or_user",
                      "allowedEndpointClassesWithoutApproval": [
                        "loopback_http_json_rpc_fixture"
                      ],
                      "configuredEndpointClass": "non_loopback_endpoint_rejected",
                      "endpointConfigured": true,
                      "loopbackConfigured": false,
                      "confirmationPolicy": "requires_confirm_runtime_write",
                      "startupPolicy": "no_auto_start_stop_or_install_from_runtime_lens",
                      "mutationPolicy": "no_production_gateway_mutation_without_explicit_approval_and_contract",
                      "credentialPolicy": "no_credential_or_token_emission",
                      "safeDefault": "fixture_only_no_production_transport_contact",
                      "supportClaimEffect": "blocks_recommended_production_native_parity",
                      "requiredEvidence": [
                        "production_transport_lifecycle_policy",
                        "approved_native_round_trip_evidence",
                        "non_destructive_fixture",
                        "no_plaintext_credential_token_evidence"
                      ],
                      "reentryCondition": "attach_production_transport_lifecycle_policy_before_claim_promotion_or_non_loopback_gateway_use"
                    },
                    "productionTransportStatus": "blocked_until_production_transport_lifecycle_policy",
                    "lifecycleStatus": "external_user_managed_not_started_by_claw",
                    "requiredEndpoint": "loopback_http_json_rpc",
                    "endpointPolicy": "non_loopback_endpoint_rejected_until_production_transport_lifecycle_policy",
                    "approvalScope": "production_transport_lifecycle_policy_and_non_loopback_endpoint_approval",
                    "productionTransportCommandShape": "blocked_until_approved_production_transport_lifecycle_policy_and_non_loopback_endpoint_approval",
                    "doNotRunWithoutApproval": true,
                    "claimBlockedUntil": "production_transport_lifecycle_policy_and_native_round_trip_evidence_attached"
                  }
                }
                """.data(using: .utf8)!,
                exitCode: 2
            )
        })

        let result = try await client.runSessionAction(
            runtime: .hermes,
            action: "send",
            sessionId: "prod-session",
            message: "hi",
            gatewayURL: "http://198.51.100.10:8080",
            confirmRuntimeWrite: true
        )

        XCTAssertEqual(requested, [[
            "runtime",
            "hermes",
            "sessions",
            "send",
            "--session-key",
            "prod-session",
            "--message",
            "hi",
            "--gateway-url",
            "http://198.51.100.10:8080",
            "--confirm-runtime-write",
            "--json"
        ]])
        XCTAssertEqual(result.status, "blocked")
        XCTAssertEqual(result.writesRuntime, false)
        XCTAssertEqual(result.wouldWriteRuntime, true)
        XCTAssertEqual(result.endpointPolicy, "non_loopback_endpoint_rejected_until_production_transport_lifecycle_policy")
        XCTAssertEqual(result.approvalScope, "production_transport_lifecycle_policy_and_non_loopback_endpoint_approval")
        XCTAssertEqual(result.productionTransportCommandShape, "blocked_until_approved_production_transport_lifecycle_policy_and_non_loopback_endpoint_approval")
        XCTAssertEqual(result.safeDefault, "fixture_only_no_production_transport_contact")
        XCTAssertEqual(result.doNotRunWithoutApproval, true)
        XCTAssertEqual(result.claimBlockedUntil, "production_transport_lifecycle_policy_and_native_round_trip_evidence_attached")
        XCTAssertEqual(result.productDecision, "production_gateway_transport_blocked_until_lifecycle_policy_and_approval")
        XCTAssertEqual(result.userVisibleContract, "non_loopback_gateway_endpoint_rejected_until_production_transport_lifecycle_policy")
        XCTAssertEqual(result.transportPolicy?.configuredEndpointClass, "non_loopback_endpoint_rejected")

        let section = ClawJSRuntimeLensSection()
        XCTAssertEqual(section.runtimeLensSessionActionResultLabel(result), "send blocked prompt.submit")
        let details = section.runtimeLensSessionActionResultDetails(result)
        XCTAssertTrue(details.contains {
            $0.contains("endpoint policy non_loopback_endpoint_rejected_until_production_transport_lifecycle_policy")
                && $0.contains("approval scope production_transport_lifecycle_policy_and_non_loopback_endpoint_approval")
                && $0.contains("endpoint class non_loopback_endpoint_rejected")
                && $0.contains("safe default fixture_only_no_production_transport_contact")
                && $0.contains("do not run without approval true")
                && $0.contains("claim blocked until production_transport_lifecycle_policy_and_native_round_trip_evidence_attached")
                && $0.contains("user visible contract non_loopback_gateway_endpoint_rejected_until_production_transport_lifecycle_policy")
                && $0.contains("product decision production_gateway_transport_blocked_until_lifecycle_policy_and_approval")
        })
    }

    @MainActor
    func testRuntimeLensClientSurfacesHermesConfirmationRequiredWithoutGatewayContact() async throws {
        var requested: [[String]] = []
        let client = ClawJSRuntimeLensClient(runner: .init { args in
            requested.append(args)
            return .init(
                data: """
                {
                  "data": {
                    "runtimeId": "hermes",
                    "domain": "sessions",
                    "action": "create",
                    "status": "confirmation_required",
                    "authority": "runtime",
                    "writesRuntime": false,
                    "wouldWriteRuntime": true,
                    "writesLocalOverlay": false,
                    "requiredFlag": "--confirm-runtime-write",
                    "officialProtocol": "tui_gateway_json_rpc",
                    "officialMethod": "session.create",
                    "officialContractSource": "https://hermes-agent.nousresearch.com/docs/developer-guide/programmatic-integration"
                  }
                }
                """.data(using: .utf8)!,
                exitCode: 2
            )
        })

        let result = try await client.runSessionAction(
            runtime: .hermes,
            action: "create",
            title: "Draft Session",
            gatewayURL: "http://127.0.0.1:18789"
        )

        XCTAssertEqual(requested, [[
            "runtime",
            "hermes",
            "sessions",
            "create",
            "--title",
            "Draft Session",
            "--gateway-url",
            "http://127.0.0.1:18789",
            "--json"
        ]])
        XCTAssertEqual(result.status, "confirmation_required")
        XCTAssertEqual(result.requiredFlag, "--confirm-runtime-write")
        XCTAssertEqual(result.writesRuntime, false)
        XCTAssertEqual(result.wouldWriteRuntime, true)
        XCTAssertEqual(result.officialMethod, "session.create")

        let section = ClawJSRuntimeLensSection()
        XCTAssertEqual(section.runtimeLensSessionActionResultLabel(result), "create confirmation_required session.create")
        XCTAssertTrue(section.runtimeLensSessionActionResultDetails(result).contains(
            "action contract runtime hermes, domain sessions, authority runtime, writes runtime false, would write runtime true, writes local overlay false, required flag --confirm-runtime-write, protocol tui_gateway_json_rpc, method session.create"
        ))
    }

    @MainActor
    func testRuntimeLensClientSurfacesHermesMissingStoreReadDegradation() async throws {
        var requested: [[String]] = []
        let client = ClawJSRuntimeLensClient(runner: .init { args in
            requested.append(args)
            return .init(
                data: """
                {
                  "data": {
                    "runtimeId": "hermes",
                    "domain": "sessions",
                    "action": "history",
                    "status": "degraded",
                    "authority": "runtime",
                    "writesRuntime": false,
                    "degradedReason": "runtime_cli_unavailable_or_session_store_missing",
                    "safeDefault": "metadata_only_projection_until_official_runtime_session_store_or_cli_is_available",
                    "userVisibleContract": "session_history_is_degraded_until_native_store_or_cli_evidence_exists",
                    "claimEffect": "does_not_satisfy_native_session_history_parity",
                    "result": {
                      "id": "missing-session",
                      "found": false,
                      "writesRuntime": false,
                      "contentIncluded": false,
                      "messages": [],
                      "totalProjected": 0,
                      "nativeIdentifier": {
                        "name": "sessionPathId"
                      }
                    }
                  }
                }
                """.data(using: .utf8)!,
                exitCode: 2
            )
        })

        let result = try await client.runSessionAction(
            runtime: .hermes,
            action: "history",
            sessionId: "missing-session"
        )

        XCTAssertEqual(requested, [[
            "runtime",
            "hermes",
            "sessions",
            "history",
            "--session-key",
            "missing-session",
            "--json"
        ]])
        XCTAssertEqual(result.status, "degraded")
        XCTAssertEqual(result.degradedReason, "runtime_cli_unavailable_or_session_store_missing")
        XCTAssertEqual(result.writesRuntime, false)
        XCTAssertEqual(result.result?.found, false)
        XCTAssertEqual(result.result?.contentIncluded, false)
        XCTAssertEqual(result.result?.totalProjected, 0)
        XCTAssertEqual(result.safeDefault, "metadata_only_projection_until_official_runtime_session_store_or_cli_is_available")
        XCTAssertEqual(result.userVisibleContract, "session_history_is_degraded_until_native_store_or_cli_evidence_exists")
        XCTAssertEqual(result.claimEffect, "does_not_satisfy_native_session_history_parity")

        let section = ClawJSRuntimeLensSection()
        XCTAssertEqual(section.runtimeLensSessionActionResultLabel(result), "history degraded missing-session")
        let details = section.runtimeLensSessionActionResultDetails(result)
        XCTAssertTrue(details.contains {
            $0.contains("degraded reason runtime_cli_unavailable_or_session_store_missing")
                && $0.contains("writes runtime false")
        })
        XCTAssertTrue(details.contains {
            $0.contains("safe default metadata_only_projection_until_official_runtime_session_store_or_cli_is_available")
                && $0.contains("user visible contract session_history_is_degraded_until_native_store_or_cli_evidence_exists")
        })
        XCTAssertTrue(details.contains {
            $0.contains("found false")
                && $0.contains("content included false")
                && $0.contains("total projected 0")
        })
    }

    func testRuntimeLensClientDecodesHermesCreateRoundTripVerification() async throws {
        let client = ClawJSRuntimeLensClient(runner: .init { _ in
            .init(
                data: """
                {
                  "data": {
                    "runtimeId": "hermes",
                    "domain": "sessions",
                    "action": "create",
                    "status": "ok",
                    "authority": "runtime",
                    "writesRuntime": true,
                    "wouldWriteRuntime": true,
                    "writesLocalOverlay": false,
                    "officialProtocol": "tui_gateway_json_rpc",
                    "officialMethod": "session.create",
                    "officialContractSource": "https://hermes-agent.nousresearch.com/docs/developer-guide/programmatic-integration",
                    "result": {
                      "id": "created-tui-session",
                      "titleRequested": "Round Trip Fixture Session",
                      "titleApplied": true,
                      "nativeIdentifier": {"name": "session_id"},
                      "gatewayReceipt": {
                        "protocol": "tui_gateway_json_rpc",
                        "transport": "loopback_http_json_rpc_fixture",
                        "method": "session.create",
                        "requestId": "fixture-create",
                        "endpoint": "http://127.0.0.1:18789"
                      },
                      "titleGatewayReceipt": {
                        "protocol": "tui_gateway_json_rpc",
                        "transport": "loopback_http_json_rpc_fixture",
                        "method": "session.title",
                        "requestId": "fixture-title",
                        "endpoint": "http://127.0.0.1:18789"
                      },
                      "roundTripVerification": {
                        "status": "verified",
                        "id": "created-tui-session",
                        "title": "Round Trip Fixture Session",
                        "matchedBy": "sessionId",
                        "writesRuntime": false,
                        "nativeIdentifier": {"name": "sessionId"},
                        "provenance": {
                          "source": "runtime-session-sqlite",
                          "runtimeId": "hermes",
                          "path": "/Users/tester/.hermes/state.db",
                          "table": "sessions"
                        },
                        "checked": ["sessionId"]
                      }
                    }
                  }
                }
                """.data(using: .utf8)!,
                exitCode: 0
            )
        })

        let result = try await client.runSessionAction(
            runtime: .hermes,
            action: "create",
            title: "Round Trip Fixture Session",
            gatewayURL: "http://127.0.0.1:18789",
            confirmRuntimeWrite: true
        )

        XCTAssertEqual(result.status, "ok")
        XCTAssertEqual(result.result?.id, "created-tui-session")
        XCTAssertEqual(result.result?.roundTripVerification?.status, "verified")
        XCTAssertEqual(result.result?.roundTripVerification?.id, "created-tui-session")
        XCTAssertEqual(result.result?.roundTripVerification?.matchedBy, "sessionId")
        XCTAssertEqual(result.result?.roundTripVerification?.writesRuntime, false)
        XCTAssertEqual(result.result?.roundTripVerification?.nativeIdentifier?.name, "sessionId")
        XCTAssertEqual(result.result?.roundTripVerification?.provenance?.source, "runtime-session-sqlite")
        XCTAssertEqual(result.result?.roundTripVerification?.provenance?.table, "sessions")
        XCTAssertEqual(result.result?.roundTripVerification?.checked, ["sessionId"])
    }

    @MainActor
    func testRuntimeLensClientDecodesHermesAbortRoundTripVerification() async throws {
        let client = ClawJSRuntimeLensClient(runner: .init { _ in
            .init(
                data: """
                {
                  "data": {
                    "runtimeId": "hermes",
                    "domain": "sessions",
                    "action": "abort",
                    "status": "ok",
                    "authority": "runtime",
                    "writesRuntime": true,
                    "wouldWriteRuntime": true,
                    "writesLocalOverlay": false,
                    "officialProtocol": "tui_gateway_json_rpc",
                    "officialMethod": "session.interrupt",
                    "officialContractSource": "https://hermes-agent.nousresearch.com/docs/developer-guide/programmatic-integration",
                    "result": {
                      "id": "abort-roundtrip-session",
                      "nativeIdentifier": {"name": "session_id"},
                      "gatewayReceipt": {
                        "protocol": "tui_gateway_json_rpc",
                        "transport": "loopback_http_json_rpc_fixture",
                        "method": "session.interrupt",
                        "requestId": "fixture-abort",
                        "endpoint": "http://127.0.0.1:18789"
                      },
                      "roundTripVerification": {
                        "status": "verified",
                        "id": "abort-roundtrip-session",
                        "matchedBy": "sessionId",
                        "action": "abort",
                        "writesRuntime": false,
                        "endedAt": "2026-05-25T21:56:40.000Z",
                        "endReason": "interrupted",
                        "nativeIdentifier": {"name": "sessionId"},
                        "provenance": {
                          "source": "runtime-session-sqlite",
                          "runtimeId": "hermes",
                          "path": "/Users/tester/.hermes/state.db",
                          "table": "sessions"
                        },
                        "checked": ["sqlite_sessions_control_state"]
                      }
                    }
                  }
                }
                """.data(using: .utf8)!,
                exitCode: 0
            )
        })

        let result = try await client.runSessionAction(
            runtime: .hermes,
            action: "abort",
            sessionId: "abort-roundtrip-session",
            gatewayURL: "http://127.0.0.1:18789",
            confirmRuntimeWrite: true
        )

        XCTAssertEqual(result.status, "ok")
        XCTAssertEqual(result.result?.roundTripVerification?.status, "verified")
        XCTAssertEqual(result.result?.roundTripVerification?.action, "abort")
        XCTAssertEqual(result.result?.roundTripVerification?.endedAt, "2026-05-25T21:56:40.000Z")
        XCTAssertEqual(result.result?.roundTripVerification?.endReason, "interrupted")
        XCTAssertEqual(result.result?.roundTripVerification?.writesRuntime, false)
        XCTAssertEqual(result.result?.roundTripVerification?.provenance?.table, "sessions")
        XCTAssertEqual(result.result?.roundTripVerification?.checked, ["sqlite_sessions_control_state"])

        let section = ClawJSRuntimeLensSection()
        XCTAssertEqual(section.runtimeLensSessionActionResultLabel(result), "abort ok session.interrupt abort-roundtrip-session round-trip verified")
        XCTAssertTrue(section.runtimeLensSessionActionResultDetails(result).contains(
            "action contract runtime hermes, domain sessions, authority runtime, writes runtime true, would write runtime true, writes local overlay false, protocol tui_gateway_json_rpc, method session.interrupt"
        ))
        XCTAssertTrue(section.runtimeLensSessionActionResultDetails(result).contains(
            "round-trip status verified, action abort, matched by sessionId, id abort-roundtrip-session, ended at 2026-05-25T21:56:40.000Z, end reason interrupted, writes runtime false"
        ))
        XCTAssertTrue(section.runtimeLensSessionActionResultDetails(result).contains(
            "provenance runtime-session-sqlite, runtime hermes, table sessions, checked sqlite_sessions_control_state"
        ))
    }
}
