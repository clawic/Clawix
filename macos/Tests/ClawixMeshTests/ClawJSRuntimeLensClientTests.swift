import XCTest
@testable import Clawix

final class ClawJSRuntimeLensClientTests: XCTestCase {
    func testRuntimeLensAcceptsDegradedRuntimePortalEnvelope() async throws {
        var requested: [ClawJSRuntimeLensID] = []
        let client = ClawJSRuntimeLensClient(runner: .init { args in
            XCTAssertEqual(args, ["runtime", "hermes", "domains", "--json"])
            requested.append(.hermes)
            return .init(
                data: try ClawJSRuntimeLensTestFixtures.data(named: "degraded-runtime-portal-envelope"),
                exitCode: 2
            )
        })

        let snapshot = try await client.load(runtime: .hermes)

        XCTAssertEqual(requested, [.hermes])
        XCTAssertEqual(snapshot.runtimeId, "example")
        XCTAssertEqual(snapshot.status.cliAvailable, false)
        XCTAssertEqual(snapshot.status.diagnostics?.locations?.homeDir, "/Users/tester/.example")
        XCTAssertEqual(snapshot.domains.map(\.domain), ClawJSRuntimeLensSnapshot.canonicalDomains)
        XCTAssertEqual(snapshot.missingCanonicalDomains, [])
        XCTAssertEqual(snapshot.supportAudit?.closureState, "blocked")
        XCTAssertEqual(snapshot.resources(for: "sessions").first?.id, "2026/05/21/runtime-session")
    }

    func testRuntimeLensDecodesHermesRuntimePortalEnvelope() async throws {
        let snapshot = try await ClawJSRuntimeLensTestFixtures.hermesRuntimePortalSnapshot()

        XCTAssertEqual(snapshot.runtimeId, "hermes")
        XCTAssertEqual(snapshot.officialSnapshot?.capturedAt, "2026-05-26")
        XCTAssertEqual(snapshot.officialSnapshot?.sourceSnapshotDate, "2026-05-26")
        XCTAssertEqual(snapshot.officialSnapshot?.sourceType, "official_docs")
        XCTAssertEqual(snapshot.officialSnapshot?.sources?.count, 8)
        XCTAssertEqual(snapshot.officialSnapshot?.driftPolicy, "hermes_operable_non_default_until_final_production_recommended_policy")
        XCTAssertEqual(snapshot.officialSnapshot?.manifestSource, "docs/runtime-ecosystem-integration.manifest.json")
        XCTAssertEqual(snapshot.domains.map(\.domain), ClawJSRuntimeLensSnapshot.canonicalDomains)
        let hermesSessionsDomain = try XCTUnwrap(snapshot.domains.first { $0.domain == "sessions" })
        XCTAssertEqual(hermesSessionsDomain.status, "error")
        XCTAssertEqual(hermesSessionsDomain.runtimeCapabilityStatus, "error")
        XCTAssertEqual(hermesSessionsDomain.runtimeCapabilitySupported, true)
        XCTAssertEqual(hermesSessionsDomain.runtimeCapabilityStrategy, "cli")
        XCTAssertEqual(hermesSessionsDomain.readProjectionStatus, "projected")
        let hermesDomainPresentation = ClawJSRuntimeLensDomainPresentation.make(domains: snapshot.domains)
        let hermesSessionsRow = try XCTUnwrap(hermesDomainPresentation.rows.first { $0.domain == "sessions" })
        XCTAssertEqual(hermesSessionsRow.status, "error")
        XCTAssertEqual(hermesSessionsRow.runtimeCapabilityStatus, "error")
        XCTAssertEqual(hermesSessionsRow.readProjectionStatus, "projected")
        XCTAssertTrue(hermesSessionsRow.detailLabel?.contains("read projected") == true)
        XCTAssertTrue(hermesSessionsRow.accessibilityLabel.contains("runtime capability status error"))
        XCTAssertTrue(hermesSessionsRow.accessibilityLabel.contains("read projection projected"))
        XCTAssertEqual(snapshot.commands?.resourceDomains, ClawJSRuntimeLensSnapshot.canonicalDomains)
        XCTAssertEqual(snapshot.commands?.jsonPortalCommandSet?.status, "guarded")
        XCTAssertEqual(snapshot.commands?.jsonPortalCommandSet?.totalCommandCount, 44)
        XCTAssertEqual(snapshot.commands?.jsonPortalCommandSet?.domainCommandCount, 13)
        XCTAssertEqual(snapshot.commands?.jsonPortalCommandSet?.resourceCommandCount, 13)
        XCTAssertEqual(snapshot.commands?.jsonPortalCommandSet?.sessionActionCommandCount, 11)
        XCTAssertEqual(snapshot.commands?.jsonPortalCommandSet?.executableMatrixCommandCount, 22)
        XCTAssertEqual(snapshot.commands?.jsonPortalCommandSet?.promotionSignal, false)
        XCTAssertEqual(snapshot.commands?.jsonPortalCommandSet?.supportClaim, "partial_runtime_lens")
        XCTAssertEqual(snapshot.commands?.jsonPortalCommandSet?.supportStage, "operable")
        XCTAssertEqual(snapshot.commands?.jsonPortalCommandSet?.safeDefault, "guarded_command_coverage_does_not_promote_support")
        XCTAssertEqual(snapshot.commands?.jsonPortalCommandSet?.sessionActions?.last, "conflicts")
        let hermesSendCommand = try XCTUnwrap(snapshot.commands?.executableByClawCli?.first { $0.command == "runtime hermes sessions send --session-key <id> --message <text> --confirm-runtime-write" })
        XCTAssertEqual(hermesSendCommand.writesRuntime, false)
        XCTAssertEqual(hermesSendCommand.wouldWriteRuntime, true)
        XCTAssertEqual(hermesSendCommand.nativeWriteBackStatus, "blocked_until_tui_gateway_wrapper_fixture")
        XCTAssertEqual(hermesSendCommand.nativeWriteBackBlockerClass, "direct_blocker")
        XCTAssertEqual(hermesSendCommand.officialRuntimeWriteBackContractKnown, true)
        XCTAssertEqual(hermesSendCommand.nativeWriteBackFixtureRequired, true)
        XCTAssertEqual(hermesSendCommand.nativeWriteBackSafeDefault, "keep_unpromoted_and_do_not_synthesize_runtime_state")
        XCTAssertEqual(hermesSendCommand.safeDefault, "keep_unpromoted_and_do_not_synthesize_runtime_state")
        XCTAssertEqual(hermesSendCommand.userVisibleContract, "non_executable_until_tui_gateway_wrapper_fixture_exists")
        XCTAssertEqual(hermesSendCommand.claimEffect, "blocks_recommended_production_native_parity")
        XCTAssertEqual(hermesSendCommand.supportResolution, "explicitly_product_blocked_not_a_silent_gap")
        XCTAssertEqual(hermesSendCommand.evidenceRequirementId, "hermes.sessions.send.action_contract")
        XCTAssertEqual(hermesSendCommand.requiredEvidence?.first, "tui_gateway_prompt_submit_fixture")
        XCTAssertEqual(hermesSendCommand.nativeWriteBackContract?.fixtureRequired, true)
        XCTAssertEqual(hermesSendCommand.nativeWriteBackContract?.safeDefault, "keep_unpromoted_and_do_not_synthesize_runtime_state")
        let hermesPinCommand = try XCTUnwrap(snapshot.commands?.executableByClawCli?.first { $0.command == "runtime hermes sessions pin --session-key <id>" })
        XCTAssertEqual(hermesPinCommand.writesRuntime, false)
        XCTAssertEqual(hermesPinCommand.writesLocalOverlay, true)
        XCTAssertEqual(hermesPinCommand.nativeWriteBackStatus, "blocked_until_official_runtime_write_back_contract")
        XCTAssertEqual(hermesPinCommand.nativeWriteBackSafeDefault, "keep_local_overlay_and_do_not_write_runtime_pin_state")
        XCTAssertEqual(hermesPinCommand.evidenceRequirementId, "hermes.sessions.pin.native_write_back_contract")
        XCTAssertEqual(hermesPinCommand.nativeWriteBackContract?.status, "blocked")
        XCTAssertEqual(hermesPinCommand.nativeWriteBackContract?.writesRuntime, false)
        XCTAssertEqual(hermesPinCommand.nativeWriteBackContract?.officialContractRequired, true)
        XCTAssertEqual(hermesPinCommand.nativeWriteBackContract?.officialContractKnown, false)
        XCTAssertEqual(hermesPinCommand.nativeWriteBackContract?.safeDefault, "keep_local_overlay_and_do_not_write_runtime_pin_state")
        let hermesUnpinCommand = try XCTUnwrap(snapshot.commands?.executableByClawCli?.first { $0.command == "runtime hermes sessions unpin --session-key <id>" })
        XCTAssertEqual(hermesUnpinCommand.writesLocalOverlay, true)
        XCTAssertEqual(hermesUnpinCommand.nativeWriteBackStatus, "blocked_until_official_runtime_write_back_contract")
        XCTAssertEqual(hermesUnpinCommand.evidenceRequirementId, "hermes.sessions.unpin.native_write_back_contract")
        XCTAssertEqual(hermesUnpinCommand.nativeWriteBackContract?.officialContractRequired, true)
        XCTAssertEqual(snapshot.support?.ecosystem?.supportStage, "operable")
        XCTAssertEqual(snapshot.support?.ecosystem?.uiParityClaim, "partial_runtime_lens")
        XCTAssertEqual(snapshot.support?.ecosystem?.summary?.contains("operable non-default runtime lens"), true)
        XCTAssertEqual(snapshot.support?.ecosystem?.summary?.contains("adapter support is production-grade"), true)
        XCTAssertEqual(snapshot.support?.ecosystem?.summary?.contains("recommended/production ecosystem claims remain false"), true)
        XCTAssertEqual(snapshot.support?.ecosystem?.blockingReasons?.contains("native_write_back_pending"), true)
        XCTAssertEqual(snapshot.support?.ecosystem?.blockingReasons?.contains("approval_gate_fixture_pending"), true)
        XCTAssertEqual(snapshot.support?.ecosystem?.blockingReasons?.contains("tui_gateway_round_trip_evidence_pending"), true)
        XCTAssertEqual(snapshot.support?.ecosystem?.blockingReasons?.contains("production_transport_policy_pending"), true)
        XCTAssertEqual(snapshot.support?.ecosystem?.blockingReasons?.contains("live_auth_evidence_pending"), true)
        XCTAssertEqual(snapshot.support?.ecosystem?.blockingReasons?.contains("live_model_evidence_pending"), true)
        XCTAssertEqual(snapshot.support?.ecosystem?.officialSnapshot?.capturedAt, "2026-05-26")
        XCTAssertEqual(snapshot.support?.ecosystem?.officialSnapshot?.sources?.contains("https://hermes-agent.nousresearch.com/docs/user-guide/security"), true)
        XCTAssertEqual(snapshot.supportAudit?.officialSnapshot?.capturedAt, "2026-05-26")
        XCTAssertEqual(snapshot.supportAudit?.provenance?.officialSnapshotSource, "docs/runtime-ecosystem-integration.manifest.json")
        XCTAssertEqual(snapshot.supportAudit?.provenance?.sourceSnapshotDate, "2026-05-26")
        XCTAssertEqual(snapshot.supportAudit?.commandCoverageSummary?.status, "guarded")
        XCTAssertEqual(snapshot.supportAudit?.commandCoverageSummary?.totalCommandCount, 44)
        XCTAssertEqual(snapshot.supportAudit?.commandCoverageSummary?.sessionActionCommandCount, 11)
        XCTAssertEqual(snapshot.supportAudit?.commandCoverageSummary?.executableMatrixCommandCount, 22)
        XCTAssertEqual(snapshot.supportAudit?.commandCoverageSummary?.promotionSignal, false)
        XCTAssertEqual(snapshot.supportAudit?.commandCoverageSummary?.supportClaim, "partial_runtime_lens")
        XCTAssertEqual(snapshot.supportAudit?.commandCoverageSummary?.supportStage, "operable")
        XCTAssertEqual(snapshot.supportAudit?.commandCoverageSummary?.supportImpact, "guarded_command_coverage_does_not_promote_support")
        XCTAssertEqual(snapshot.supportAudit?.commandCoverageSummary?.safeDefault, "guarded_command_coverage_does_not_promote_support")
        XCTAssertEqual(snapshot.supportAudit?.commandCoverageSummary?.exactCommand, "claw runtime hermes commands --json")
        let hermesSupportOverview = ClawJSRuntimeLensSupportOverviewPresentation.make(support: try XCTUnwrap(snapshot.support))
        XCTAssertEqual(hermesSupportOverview.blockingReasonCount, 8)
        XCTAssertEqual(hermesSupportOverview.officialSnapshotCapturedAt, "2026-05-26")
        XCTAssertEqual(hermesSupportOverview.officialSnapshotSourceSnapshotDate, "2026-05-26")
        XCTAssertEqual(hermesSupportOverview.officialSnapshotSourceCount, 8)
        XCTAssertEqual(hermesSupportOverview.officialSnapshotLabel, "captured 2026-05-26, source snapshot 2026-05-26, sources 8")
        XCTAssertEqual(hermesSupportOverview.officialSnapshotDriftPolicy, "hermes_operable_non_default_until_final_production_recommended_policy")
        XCTAssertTrue(hermesSupportOverview.accessibilityLabel.contains("official snapshot 2026-05-26"))
        XCTAssertTrue(hermesSupportOverview.blockingReasonsLabel?.contains("native_write_back_pending") == true)
        XCTAssertTrue(hermesSupportOverview.blockingReasonsLabel?.contains("approval_gate_fixture_pending") == true)
        XCTAssertTrue(hermesSupportOverview.blockingReasonsLabel?.contains("tui_gateway_round_trip_evidence_pending") == true)
        XCTAssertTrue(hermesSupportOverview.blockingReasonsLabel?.contains("production_transport_policy_pending") == true)
        XCTAssertTrue(hermesSupportOverview.blockingReasonsLabel?.contains("live_auth_evidence_pending") == true)
        XCTAssertTrue(hermesSupportOverview.blockingReasonsLabel?.contains("live_model_evidence_pending") == true)
        XCTAssertTrue(hermesSupportOverview.summary?.contains("operable non-default runtime lens") == true)
        XCTAssertTrue(hermesSupportOverview.summary?.contains("adapter support is production-grade") == true)
        XCTAssertTrue(hermesSupportOverview.summary?.contains("recommended/production ecosystem claims remain false") == true)
        XCTAssertEqual(snapshot.supportAudit?.finalSupportClaimDecision?.effectiveSupportStage, "operable")
        XCTAssertEqual(snapshot.supportAudit?.finalSupportClaimDecision?.uiParityClaim, "partial_runtime_lens")
        XCTAssertEqual(snapshot.supportAudit?.finalPromotionReview?.commandCoverageSummary?.totalCommandCount, 44)
        XCTAssertEqual(snapshot.supportAudit?.finalPromotionReview?.commandCoverageSummary?.promotionSignal, false)
        XCTAssertEqual(snapshot.supportAudit?.finalSupportClaimDecision?.commandCoverageSummary?.totalCommandCount, 44)
        XCTAssertEqual(snapshot.supportAudit?.finalSupportClaimDecision?.commandCoverageSummary?.promotionSignal, false)
        XCTAssertEqual(snapshot.supportAudit?.finalSupportClaimDecision?.commandCoverageSummary?.safeDefault, "guarded_command_coverage_does_not_promote_support")
        XCTAssertEqual(snapshot.supportAudit?.finalSupportClaimDecision?.recommended, false)
        XCTAssertEqual(snapshot.supportAudit?.finalSupportClaimDecision?.production, false)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.upstreamContractBlockedCount, 15)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.statusCounts?["blocked_until_tui_gateway_wrapper_fixture"], 4)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.statusCounts?["blocked_until_upstream_contract"], 15)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.approvalGateBlockedCount, 2)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.tuiGatewayBlockedCount, 4)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.tuiGatewayWrapperBlockedCount, 4)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.tuiGatewayFixtureBackedCount, 0)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.productionTransportBlockedCount, 4)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.writeBackContractBlockedCount, 12)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.safeDefaultCounts?["keep_read_projection_only_until_official_runtime_write_back_contract_exists"], 10)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.safeDefaultCounts?["do_not_run_without_explicit_approval_and_redaction"], 4)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.safeDefaultCounts?["do_not_run_without_approval_gate_fixture"], 2)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.safeDefaultCounts?["keep_unpromoted_and_do_not_synthesize_runtime_state"], 7)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.safeDefaultCounts?["keep_local_overlay_and_do_not_write_runtime_pin_state"], 2)
        let hermesWriteBackPolicy = "blocked_until_official_runtime_write_back_contract_fixture_and_round_trip_evidence"
        XCTAssertEqual(snapshot.supportAudit?.syncPolicySummary?.writeBackPolicyCounts?[hermesWriteBackPolicy], 10)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.approvalGateRequirementIds, [
            "hermes.doctorCompat.approval_gate_evidence",
            "hermes.sandboxPermissions.approval_gate_evidence"
        ])
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.tuiGatewayRequirementIds, [
            "hermes.sessions.send.action_contract",
            "hermes.sessions.inject.action_contract",
            "hermes.sessions.abort.action_contract",
            "hermes.sessions.create.action_contract"
        ])
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.tuiGatewayWrapperRequirementIds, [
            "hermes.sessions.send.action_contract",
            "hermes.sessions.inject.action_contract",
            "hermes.sessions.abort.action_contract",
            "hermes.sessions.create.action_contract"
        ])
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.tuiGatewayFixtureBackedRequirementIds, [])
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.productionTransportRequirementIds, [
            "hermes.sessions.send.action_contract",
            "hermes.sessions.inject.action_contract",
            "hermes.sessions.abort.action_contract",
            "hermes.sessions.create.action_contract"
        ])
        let hermesGatewayReentryPackets = snapshot.supportAudit?.evidenceReentryPackets?.filter {
            $0.requirementId?.hasPrefix("hermes.sessions.") == true
                && $0.requirementId?.hasSuffix(".action_contract") == true
                && $0.transportPolicyId == "hermes.tui_gateway.transport_lifecycle_policy"
        } ?? []
        XCTAssertEqual(hermesGatewayReentryPackets.map { $0.requirementId }, [
            "hermes.sessions.send.action_contract",
            "hermes.sessions.inject.action_contract",
            "hermes.sessions.abort.action_contract",
            "hermes.sessions.create.action_contract"
        ])
        XCTAssertTrue(hermesGatewayReentryPackets.allSatisfy {
            $0.claimBlockedUntil == "tui_gateway_wrapper_fixture_production_transport_lifecycle_policy_and_native_round_trip_evidence_attached"
        })
        XCTAssertTrue(hermesGatewayReentryPackets.allSatisfy {
            $0.productionTransportCommandShape == "blocked_until_approved_production_transport_lifecycle_policy_and_non_loopback_endpoint_approval"
        })
        XCTAssertTrue(hermesGatewayReentryPackets.allSatisfy {
            $0.officialTransportSurface == "stdio_or_websocket_json_rpc"
        })
        XCTAssertTrue(hermesGatewayReentryPackets.allSatisfy {
            $0.officialTransportClasses == ["stdio_json_rpc", "websocket_json_rpc"]
        })
        XCTAssertTrue(hermesGatewayReentryPackets.allSatisfy {
            $0.officialTransportSource == "https://hermes-agent.nousresearch.com/docs/developer-guide/programmatic-integration"
        })
        XCTAssertTrue(hermesGatewayReentryPackets.allSatisfy {
            $0.productionTransportBlocker == "approval_required_for_non_loopback_endpoint_and_lifecycle_management"
        })
        XCTAssertTrue(hermesGatewayReentryPackets.allSatisfy { $0.doNotRunWithoutApproval == true })
        let hermesReentryPresentation = ClawJSRuntimeLensEvidenceReentryPresentation.make(
            packets: try XCTUnwrap(snapshot.supportAudit?.evidenceReentryPackets)
        )
        let hermesSendReentryRow = hermesReentryPresentation.rows.first {
            $0.requirementId == "hermes.sessions.send.action_contract"
        }
        XCTAssertEqual(hermesSendReentryRow?.officialTransportSurface, "stdio_or_websocket_json_rpc")
        XCTAssertEqual(hermesSendReentryRow?.officialTransportClassesLabel, "stdio_json_rpc, websocket_json_rpc")
        XCTAssertEqual(hermesSendReentryRow?.productionTransportBlocker, "approval_required_for_non_loopback_endpoint_and_lifecycle_management")
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.writeBackContractRequirementIds?.contains("hermes.sessions.pin.native_write_back_contract"), true)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.writeBackContractRequirementIds?.contains("hermes.sessions.unpin.native_write_back_contract"), true)
        XCTAssertEqual(snapshot.status.capabilityMap?["memory"]?.status, "degraded")
        XCTAssertEqual(snapshot.domains.first { $0.domain == "memory" }?.status, "degraded")
        XCTAssertEqual(snapshot.status.capabilityMap?["doctor"]?.status, "degraded")
        XCTAssertEqual(snapshot.status.capabilityMap?["compat"]?.status, "degraded")
        XCTAssertEqual(snapshot.domainData?.doctorCompat?.capability?.status, "degraded")
        XCTAssertEqual(snapshot.status.capabilityMap?["configuration"]?.status, "ready")
        XCTAssertEqual(snapshot.domainData?.configuration?.capability?.strategy, "config")
        XCTAssertEqual(snapshot.domainData?.configuration?.redactedConfigSnapshot?.valuePolicy, "keys_and_value_kinds_only_no_plaintext_values")
        XCTAssertEqual(snapshot.domainData?.configuration?.redactedConfigSnapshot?.secretEntryCount, 2)
        XCTAssertEqual(snapshot.domainData?.configuration?.redactedConfigSnapshot?.entries?.first { $0.key == "providers.openai.api_key" }?.redaction, "secret_key_presence_only")
        XCTAssertEqual(snapshot.resources(for: "configuration").contains { $0.id == "configuration-redacted-snapshot" }, true)
        XCTAssertEqual(snapshot.resources(for: "configuration").contains { $0.id == "configuration-key-providers-openai-api_key" && $0.status == "redacted" }, true)
        XCTAssertEqual(snapshot.resources(for: "configuration").last?.id, "configuration-capability")
        XCTAssertEqual(snapshot.session?.sessionStorageContract, "sqlite_with_gateway_transcripts")
        XCTAssertEqual(snapshot.session?.sessionDatabasePath, "/Users/tester/.hermes/state.db")
        XCTAssertEqual(snapshot.domainData?.sessions?.session?.sessionStorageContract, "sqlite_with_gateway_transcripts")
        XCTAssertEqual(snapshot.domainData?.sessions?.session?.sessionIndexPath, "/Users/tester/.hermes/sessions/sessions.json")
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
        XCTAssertEqual(snapshot.domainData?.sessions?.actionPolicy?.first { $0.action == "resolve" }?.status, "implemented")
        XCTAssertEqual(snapshot.domainData?.sessions?.actionPolicy?.first { $0.action == "history" }?.status, "implemented")
        XCTAssertEqual(snapshot.domainData?.sessions?.actionPolicy?.first { $0.action == "send" }?.status, "blocked")
        XCTAssertEqual(snapshot.domainData?.sessions?.actionPolicy?.first { $0.action == "send" }?.transportPolicy?.id, "hermes.tui_gateway.transport_lifecycle_policy")
        XCTAssertEqual(snapshot.domainData?.sessions?.actionPolicy?.first { $0.action == "send" }?.productionTransportStatus, "blocked_until_production_transport_lifecycle_policy")
        XCTAssertEqual(snapshot.domainData?.sessions?.actionPolicy?.first { $0.action == "send" }?.lifecycleStatus, "external_user_managed_not_started_by_claw")
        XCTAssertEqual(snapshot.domainData?.sessions?.actionPolicy?.first { $0.action == "pin" }?.authority, "clawix_local_overlay")
        XCTAssertEqual(snapshot.domainData?.sessions?.actionContracts?.first { $0.action == "pin" }?.nativeWriteBackStatus, "blocked_until_official_runtime_write_back_contract")
        XCTAssertEqual(snapshot.domainData?.sessions?.actionContracts?.first { $0.action == "pin" }?.officialRuntimeWriteBackContractRequired, true)
        XCTAssertEqual(snapshot.domainData?.sessions?.actionContracts?.first { $0.action == "pin" }?.officialRuntimeWriteBackContractKnown, false)
        XCTAssertEqual(snapshot.domainData?.sessions?.actionContracts?.first { $0.action == "pin" }?.nativeWriteBackSafeDefault, "keep_local_overlay_and_do_not_write_runtime_pin_state")
        XCTAssertEqual(snapshot.domainData?.sessions?.actionContracts?.first { $0.action == "pin" }?.userVisibleContract, "local_overlay_only_until_official_runtime_pin_api_exists")
        XCTAssertEqual(snapshot.domainData?.sessions?.actionContracts?.first { $0.action == "pin" }?.claimEffect, "blocks_native_write_back_parity_not_local_overlay")
        XCTAssertEqual(snapshot.domainData?.sessions?.actionContracts?.first { $0.action == "pin" }?.evidenceRequirementId, "hermes.sessions.pin.native_write_back_contract")
        XCTAssertEqual(snapshot.domainData?.sessions?.actionPolicy?.first { $0.action == "unpin" }?.nativeWriteBackStatus, "blocked_until_official_runtime_write_back_contract")
        XCTAssertEqual(snapshot.domainData?.sessions?.actionPolicy?.first { $0.action == "unpin" }?.evidenceRequirementId, "hermes.sessions.unpin.native_write_back_contract")
        XCTAssertEqual(snapshot.domainData?.sessions?.overlayState?.writesRuntime, false)
        let hermesSessionResource = try XCTUnwrap(snapshot.resources(for: "sessions").first)
        XCTAssertEqual(hermesSessionResource.pinned, false)
        XCTAssertEqual(hermesSessionResource.pinAuthority, "none")
        XCTAssertEqual(hermesSessionResource.divergence, "none")
        XCTAssertEqual(hermesSessionResource.localOverlay?.pinned, false)
        XCTAssertEqual(hermesSessionResource.localOverlay?.authority, "clawix_local_overlay")
        XCTAssertEqual(hermesSessionResource.localOverlay?.writesRuntime, false)
        XCTAssertEqual(snapshot.domainData?.gateway?.tuiGatewayTransportPolicy?.id, "hermes.tui_gateway.transport_lifecycle_policy")
        XCTAssertEqual(snapshot.domainData?.gateway?.tuiGatewayTransportPolicy?.protocolName, "tui_gateway_json_rpc")
        XCTAssertEqual(snapshot.domainData?.gateway?.tuiGatewayTransportPolicy?.officialTransportSurface, "stdio_or_websocket_json_rpc")
        XCTAssertEqual(snapshot.domainData?.gateway?.tuiGatewayTransportPolicy?.officialTransportClasses, ["stdio_json_rpc", "websocket_json_rpc"])
        XCTAssertEqual(snapshot.domainData?.gateway?.tuiGatewayTransportPolicy?.officialTransportSource, "https://hermes-agent.nousresearch.com/docs/developer-guide/programmatic-integration")
        XCTAssertEqual(snapshot.domainData?.gateway?.tuiGatewayTransportPolicy?.productionTransportStatus, "blocked_until_production_transport_lifecycle_policy")
        XCTAssertEqual(snapshot.domainData?.gateway?.tuiGatewayTransportPolicy?.productionTransportBlocker, "approval_required_for_non_loopback_endpoint_and_lifecycle_management")
        XCTAssertEqual(snapshot.domainData?.gateway?.tuiGatewayTransportPolicy?.credentialPolicy, "no_credential_or_token_emission")
        XCTAssertEqual(hermesSessionResource.id, "hermes-sqlite-session")
        XCTAssertEqual(hermesSessionResource.nativeIdentifier?.name, "sessionId")
        XCTAssertEqual(hermesSessionResource.provenance?.source, "runtime-session-sqlite")
        XCTAssertEqual(hermesSessionResource.parentSessionId, "parent-session")
        XCTAssertEqual(hermesSessionResource.inputTokens, 11)
        XCTAssertEqual(hermesSessionResource.outputTokens, 23)
        XCTAssertEqual(hermesSessionResource.cacheReadTokens, 5)
        XCTAssertEqual(hermesSessionResource.cacheWriteTokens, 7)
        XCTAssertEqual(hermesSessionResource.reasoningTokens, 13)
        XCTAssertEqual(hermesSessionResource.billingProvider, "openai")
        XCTAssertEqual(hermesSessionResource.billingMode, "api_key")
        XCTAssertEqual(hermesSessionResource.estimatedCostUsd, 0.0123)
        XCTAssertEqual(hermesSessionResource.actualCostUsd, 0.0101)
        XCTAssertEqual(hermesSessionResource.costStatus, "estimated")
        XCTAssertEqual(hermesSessionResource.apiCallCount, 2)
        XCTAssertEqual(snapshot.resources(for: "plugins").map(\.id).sorted(), ["mcp-github", "memory-provider", "plugin-status"])
        let scalarAuthResource = try XCTUnwrap(snapshot.resources(for: "auth").first { $0.id == "tencent-tokenhub" })
        XCTAssertEqual(scalarAuthResource.status, "redacted")
        XCTAssertEqual(scalarAuthResource.kind, "redacted_auth_state")
        XCTAssertEqual(scalarAuthResource.summary, "Hermes auth state is redacted; no credential value is exposed.")
        XCTAssertEqual(scalarAuthResource.attributes?.contains("auth scalar: redacted_value"), true)

        let sessionActionPresentation = ClawJSRuntimeLensSessionActionPresentation.make(
            actions: try XCTUnwrap(snapshot.domainData?.sessions?.actionPolicy)
        )
        XCTAssertEqual(sessionActionPresentation.statusLabel, "blocked 4, implemented 5, local_overlay_only 2")
        XCTAssertEqual(sessionActionPresentation.localOverlayActionsLabel, "pin, unpin")
        XCTAssertEqual(sessionActionPresentation.blockedActionsLabel, "send, inject, abort, create")
        XCTAssertTrue(sessionActionPresentation.accessibilityLabel.contains("Runtime session actions"))
    }

    func testRuntimeLensSupportOverviewFallsBackToTopLevelOfficialSnapshot() async throws {
        let fixtureData = try ClawJSRuntimeLensTestFixtures.data(named: "hermes-runtime-portal-envelope")
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: fixtureData) as? [String: Any])
        var payload = try XCTUnwrap(envelope["data"] as? [String: Any])
        var support = try XCTUnwrap(payload["support"] as? [String: Any])
        var ecosystem = try XCTUnwrap(support["ecosystem"] as? [String: Any])
        ecosystem.removeValue(forKey: "officialSnapshot")
        support["ecosystem"] = ecosystem
        payload["support"] = support
        envelope["data"] = payload
        let modifiedData = try JSONSerialization.data(withJSONObject: envelope)

        let client = ClawJSRuntimeLensClient(runner: .init { args in
            XCTAssertEqual(args, ["runtime", "hermes", "domains", "--json"])
            return .init(data: modifiedData, exitCode: 2)
        })
        let snapshot = try await client.load(runtime: .hermes)
        let presentation = ClawJSRuntimeLensSupportOverviewPresentation.make(
            support: try XCTUnwrap(snapshot.support),
            officialSnapshot: snapshot.officialSnapshot
        )

        XCTAssertNil(snapshot.support?.ecosystem?.officialSnapshot)
        XCTAssertEqual(snapshot.officialSnapshot?.capturedAt, "2026-05-26")
        XCTAssertEqual(presentation.officialSnapshotLabel, "captured 2026-05-26, source snapshot 2026-05-26, sources 8")
        XCTAssertEqual(presentation.officialSnapshotDriftPolicy, "hermes_operable_non_default_until_final_production_recommended_policy")
        XCTAssertTrue(presentation.accessibilityLabel.contains("official snapshot 2026-05-26"))
    }

    func testRuntimeLensDecodesApprovalGateFixtureReceipts() async throws {
        let data = Self.hermesFixtureDataWithApprovalGateReceipt()
        let client = ClawJSRuntimeLensClient(runner: .init { args in
            XCTAssertEqual(args, ["runtime", "hermes", "domains", "--json"])
            return .init(data: data, exitCode: 2)
        })

        let snapshot = try await client.load(runtime: .hermes)
        let contract = try XCTUnwrap(snapshot.domainData?.doctorCompat?.supportContract)
        XCTAssertEqual(contract.writeBackPolicy, "approval_gated_repair")
        XCTAssertEqual(snapshot.domains.first { $0.domain == "doctorCompat" }?.approvalGateFixtureStatus, "attached")
        XCTAssertEqual(snapshot.domains.first { $0.domain == "doctorCompat" }?.approvalGateFixtureReceipt?.receiptId, "fixture-doctor-denial")
        XCTAssertEqual(snapshot.domains.first { $0.domain == "doctorCompat" }?.approvalGateFixtureReceipt?.redacted, true)
        XCTAssertEqual(snapshot.domains.first { $0.domain == "doctorCompat" }?.approvalGateFixtureReceipt?.mutationWithoutApproval, false)
        XCTAssertEqual(snapshot.domains.first { $0.domain == "doctorCompat" }?.approvalGateFixtureReceipt?.plaintextSecretLeak, false)
        XCTAssertEqual(snapshot.supportAudit?.domains?.first { $0.domain == "doctorCompat" }?.writeBackApprovalGated, true)
        XCTAssertEqual(snapshot.supportAudit?.domains?.first { $0.domain == "doctorCompat" }?.approvalGateFixtureStatus, "attached")
        XCTAssertEqual(snapshot.supportAudit?.domains?.first { $0.domain == "doctorCompat" }?.approvalGateFixtureReceipt?.receiptId, "fixture-doctor-denial")

        let supportContracts = ClawJSRuntimeLensSupportContractPresentation.make(snapshot: snapshot)
        let row = try XCTUnwrap(supportContracts.rows.first { $0.domain == "doctorCompat" })
        XCTAssertEqual(row.approvalGateFixtureLabel, "attached, receipt fixture-doctor-denial, status denied_without_approval, redacted true")
        XCTAssertTrue(row.accessibilityLabel.contains("receipt fixture-doctor-denial"))
    }

    func testRuntimeLensDecodesLiveEvidenceFixtureReceipts() async throws {
        let data = Self.hermesFixtureDataWithLiveEvidenceReceipt()
        let client = ClawJSRuntimeLensClient(runner: .init { args in
            XCTAssertEqual(args, ["runtime", "hermes", "domains", "--json"])
            return .init(data: data, exitCode: 2)
        })

        let snapshot = try await client.load(runtime: .hermes)
        let contract = try XCTUnwrap(snapshot.domainData?.channels?.supportContract)
        XCTAssertEqual(contract.liveEvidenceFixtureStatus, "attached")
        XCTAssertEqual(contract.liveEvidenceFixtureReceipt?.receiptId, "fixture-channels-live-evidence")
        XCTAssertEqual(contract.liveEvidenceFixtureReceipt?.readOnly, true)
        XCTAssertEqual(contract.liveEvidenceFixtureReceipt?.supportContractMatchesManifest, true)
        XCTAssertEqual(snapshot.domains.first { $0.domain == "channels" }?.liveEvidenceFixtureStatus, "attached")
        XCTAssertEqual(snapshot.domains.first { $0.domain == "channels" }?.liveEvidenceFixtureReceipt?.plaintextSecretLeak, false)
        XCTAssertEqual(snapshot.supportAudit?.domains?.first { $0.domain == "channels" }?.liveEvidenceFixtureStatus, "attached")
        XCTAssertEqual(snapshot.supportAudit?.domains?.first { $0.domain == "channels" }?.liveEvidenceFixtureReceipt?.source, "live-evidence-fixture")

        let supportContracts = ClawJSRuntimeLensSupportContractPresentation.make(snapshot: snapshot)
        let row = try XCTUnwrap(supportContracts.rows.first { $0.domain == "channels" })
        XCTAssertEqual(row.liveEvidenceFixtureLabel, "attached, receipt fixture-channels-live-evidence, status approved_redacted_live_evidence, redacted true, read only true")
        XCTAssertTrue(row.accessibilityLabel.contains("live evidence receipt attached"))
    }

    func testRuntimeLensDecodesOfficialContractFixtureReceipts() async throws {
        let data = Self.hermesFixtureDataWithWriteBackContractReceipt()
        let client = ClawJSRuntimeLensClient(runner: .init { args in
            XCTAssertEqual(args, ["runtime", "hermes", "domains", "--json"])
            return .init(data: data, exitCode: 2)
        })

        let snapshot = try await client.load(runtime: .hermes)
        let contract = try XCTUnwrap(snapshot.domainData?.sessions?.supportContract)
        XCTAssertEqual(contract.writeBackContractFixtureStatus, "attached")
        XCTAssertEqual(contract.writeBackContractFixtureReceipt?.receiptId, "fixture-sessions-write-back-contract")
        XCTAssertEqual(contract.writeBackContractFixtureReceipt?.roundTripNativeVisibility, true)
        XCTAssertEqual(snapshot.domains.first { $0.domain == "sessions" }?.writeBackContractFixtureStatus, "attached")
        XCTAssertEqual(snapshot.supportAudit?.domains?.first { $0.domain == "sessions" }?.writeBackContractFixtureStatus, "attached")

        let supportContracts = ClawJSRuntimeLensSupportContractPresentation.make(snapshot: snapshot)
        let row = try XCTUnwrap(supportContracts.rows.first { $0.domain == "sessions" })
        XCTAssertEqual(row.writeBackContractFixtureLabel, "attached, receipt fixture-sessions-write-back-contract, status official_write_back_contract_verified, redacted true, round trip true")
        XCTAssertTrue(row.accessibilityLabel.contains("write back contract receipt attached"))
    }

    func testRuntimeLensPresentationsExposeParityEvidenceAndClosureState() async throws {
        let snapshot = try await ClawJSRuntimeLensTestFixtures.degradedRuntimePortalSnapshot()
        let audit = try XCTUnwrap(snapshot.supportAudit)

        XCTAssertEqual(snapshot.commands?.resourceDomains, ClawJSRuntimeLensSnapshot.canonicalDomains)
        let runtimeSummaryPresentation = ClawJSRuntimeLensRuntimeSummaryPresentation.make(snapshot: snapshot)
        let runtimeSummary = runtimeSummaryPresentation
        XCTAssertTrue(runtimeSummaryPresentation.accessibilityLabel.contains("Runtime summary"))
        XCTAssertEqual(runtimeSummaryPresentation.capabilityStatusLabel, "degraded 1, error 1, ready 1, unsupported 1")
        XCTAssertEqual(runtimeSummaryPresentation.capabilityRows.count, 4)
        XCTAssertEqual(runtimeSummary.runtimeResourceAggregateDomainCount, 0)
        XCTAssertNil(runtimeSummary.runtimeResourcesLabel)

        let supportOverviewPresentation = ClawJSRuntimeLensSupportOverviewPresentation.make(
            support: try XCTUnwrap(snapshot.support)
        )
        XCTAssertTrue(supportOverviewPresentation.accessibilityLabel.contains("Runtime support overview"))
        XCTAssertEqual(supportOverviewPresentation.sourceLabel, "runtime-ecosystem-manifest, runtime example")

        let viewStatePresentation = ClawJSRuntimeLensViewStatePresentation.make(
            runtime: .hermes,
            isRefreshing: false,
            loadError: nil,
            actionError: nil,
            hasSnapshot: true
        )
        XCTAssertTrue(viewStatePresentation.accessibilityLabel.contains("Runtime lens view state"))

        let commandPresentation = ClawJSRuntimeLensCommandMatrixPresentation.make(
            commands: try XCTUnwrap(snapshot.commands)
        )
        XCTAssertTrue(commandPresentation.accessibilityLabel.contains("Runtime command matrix"))
        XCTAssertEqual(commandPresentation.jsonPortalCommandCount, 44)
        XCTAssertEqual(commandPresentation.jsonPortalStatus, "guarded")
        XCTAssertEqual(commandPresentation.jsonPortalPromotionSignal, false)
        XCTAssertEqual(commandPresentation.jsonPortalSupportClaim, "partial_runtime_lens")
        XCTAssertEqual(commandPresentation.jsonPortalSupportStage, "dev_only")
        XCTAssertEqual(commandPresentation.jsonPortalSafeDefault, "guarded_command_coverage_does_not_promote_support")
        XCTAssertEqual(commandPresentation.jsonPortalSessionActionsLabel, "list, preview, resolve, history, send, inject, abort, create, pin, unpin, conflicts")
        XCTAssertTrue(commandPresentation.accessibilityLabel.contains("json portal commands 44"))
        XCTAssertTrue(commandPresentation.accessibilityLabel.contains("promotion signal false"))
        XCTAssertEqual(commandPresentation.resourceDomainCount, 13)
        XCTAssertEqual(commandPresentation.rows.first?.writeDisposition, "blocked write")
        XCTAssertEqual(commandPresentation.localOverlayCommandCount, 0)
        XCTAssertEqual(commandPresentation.nativeWriteBackBlockedCount, 0)

        XCTAssertEqual(snapshot.supportAudit?.closureState, "blocked")
        let supportAuditPresentation = ClawJSRuntimeLensSupportAuditPresentation.make(audit: audit)
        XCTAssertTrue(supportAuditPresentation.accessibilityLabel.contains("Runtime support audit"))
        XCTAssertEqual(supportAuditPresentation.blockerClassLabel, "direct_blocker 3, external_pending 1")
        XCTAssertEqual(snapshot.supportAudit?.evidenceRequirements?.first?.fallbackPolicy, "do_not_synthesize_native_runtime_action")
        XCTAssertEqual(snapshot.supportAudit?.evidenceRequirements?.first?.supportResolution, "explicitly_product_blocked_not_a_silent_gap")
        XCTAssertEqual(snapshot.supportAudit?.finalPromotionReview?.claimDisposition, "unpromoted_product_blocked_and_external_pending")
        XCTAssertEqual(snapshot.supportAudit?.finalSupportClaimDecision?.claimDisposition, "unpromoted_product_blocked_and_external_pending")
        XCTAssertEqual(snapshot.supportAudit?.finalPromotionReview?.productBlockedRequirementIds?.count, 3)
        XCTAssertEqual(snapshot.supportAudit?.finalPromotionReview?.externalPendingRequirementIds, ["example.channels.live_evidence"])
        XCTAssertEqual(snapshot.supportAudit?.finalSupportClaimDecision?.safeDefault, "keep_unpromoted_until_evidence_or_upstream_contract_changes")
        XCTAssertEqual(snapshot.supportAudit?.finalSupportClaimDecision?.blockerClasses, ["external_pending", "direct_blocker"])
        XCTAssertEqual(snapshot.supportAudit?.finalSupportClaimDecision?.promotionEvidenceRequired?.first, "approved_redacted_live_evidence")

        let promotionReviewPresentation = ClawJSRuntimeLensSupportDecisionPresentation.make(
            review: try XCTUnwrap(audit.finalPromotionReview)
        )
        XCTAssertTrue(promotionReviewPresentation.accessibilityLabel.contains("Runtime final promotion review"))
        let finalDecisionPresentation = ClawJSRuntimeLensSupportDecisionPresentation.make(
            decision: try XCTUnwrap(audit.finalSupportClaimDecision)
        )
        XCTAssertEqual(finalDecisionPresentation.blockerClassesLabel, "external_pending, direct_blocker")
        XCTAssertEqual(finalDecisionPresentation.promotionEvidenceRequiredLabel, "approved_redacted_live_evidence, approval_gate_fixture_and_redacted_receipt, tui_gateway_wrapper_fixture_and_round_trip_evidence, production_transport_lifecycle_policy_and_native_round_trip_evidence, keep_lowered_claim_until_upstream_native_contracts_exist")
        XCTAssertTrue(finalDecisionPresentation.accessibilityLabel.contains("Runtime final support claim decision"))

        let projectionPresentation = ClawJSRuntimeLensSupportSummaryPresentation.make(
            projection: try XCTUnwrap(snapshot.supportAudit?.projectionSummary)
        )
        let syncPresentation = ClawJSRuntimeLensSupportSummaryPresentation.make(
            sync: try XCTUnwrap(snapshot.supportAudit?.syncPolicySummary)
        )
        let readinessPresentation = ClawJSRuntimeLensSupportSummaryPresentation.make(
            evidenceReadiness: try XCTUnwrap(snapshot.supportAudit?.evidenceReadinessSummary)
        )
        XCTAssertTrue(projectionPresentation.accessibilityLabel.contains("Runtime projection summary"))
        XCTAssertTrue(syncPresentation.accessibilityLabel.contains("Runtime sync policy summary"))
        XCTAssertTrue(readinessPresentation.accessibilityLabel.contains("Runtime evidence readiness summary"))
        XCTAssertEqual(snapshot.supportAudit?.syncPolicySummary?.readOnlyProjectionDomains, ["sessions", "channels"])
        XCTAssertEqual(snapshot.supportAudit?.syncPolicySummary?.canonicalAuthorityCounts?["runtime"], 1)
        XCTAssertEqual(snapshot.supportAudit?.syncPolicySummary?.nativeAuthorityCounts?["runtime"], 2)
        XCTAssertEqual(snapshot.supportAudit?.syncPolicySummary?.persistenceCounts?["index_and_shadow_when_safe"], 1)
        XCTAssertEqual(snapshot.supportAudit?.syncPolicySummary?.relationCounts?["native_projection"], 1)
        XCTAssertEqual(snapshot.supportAudit?.syncPolicySummary?.writeBackPolicyCounts?["blocked_until_fixture_coverage"], 1)
        XCTAssertEqual(snapshot.supportAudit?.syncPolicySummary?.lossPolicyCounts?["preserve_when_safe"], 1)
        XCTAssertEqual(snapshot.supportAudit?.syncPolicySummary?.localOverlayDomains, ["sessions"])
        XCTAssertEqual(snapshot.supportAudit?.syncPolicySummary?.freshnessCounts?["snapshot"], 1)

        let validationSummary = ClawJSRuntimeLensValidationSummary.make(snapshot: snapshot)
        XCTAssertEqual(validationSummary.syncFreshnessLabel, "degraded_snapshot 1, snapshot 1")
        XCTAssertEqual(validationSummary.finalDecisionBlockerClassesLabel, "external_pending, direct_blocker")
        XCTAssertEqual(validationSummary.finalDecisionPromotionEvidenceLabel, "approved_redacted_live_evidence, approval_gate_fixture_and_redacted_receipt, tui_gateway_wrapper_fixture_and_round_trip_evidence, production_transport_lifecycle_policy_and_native_round_trip_evidence, keep_lowered_claim_until_upstream_native_contracts_exist")
        XCTAssertTrue(validationSummary.accessibilityLabel.contains("Runtime lens validation"))

        XCTAssertEqual(snapshot.supportAudit?.closureChecklist?.first?.readProjectionStatus, "projected")
        XCTAssertEqual(snapshot.supportAudit?.closureChecklist?.first?.projectionDisposition, "read_projection_available_write_back_blocked")
        XCTAssertEqual(snapshot.supportAudit?.closureChecklist?.first?.implementedFacets?.contains("session_list_action"), true)
        XCTAssertEqual(snapshot.supportAudit?.closureChecklist?.first?.blockingFacets?.contains("native_write_back_contract"), true)
        XCTAssertEqual(snapshot.supportAudit?.closureChecklistSummary?["external_pending"], 1)
        XCTAssertEqual(snapshot.supportAudit?.projectionSummary?.projectedDomainCount, 2)
        XCTAssertEqual(snapshot.supportAudit?.projectionSummary?.productBlockedButProjectedDomainCount, 1)
        XCTAssertEqual(snapshot.supportAudit?.projectionSummary?.implementedFacetCounts?["manifest_domain_contract"], 2)
        XCTAssertEqual(snapshot.supportAudit?.projectionSummary?.blockingFacetCounts?["approved_live_evidence"], 1)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.approvalRequiredCount, 1)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.upstreamContractBlockedCount, 1)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.approvalGateBlockedCount, 1)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.tuiGatewayBlockedCount, 1)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.tuiGatewayWrapperBlockedCount, nil)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.tuiGatewayFixtureBackedCount, nil)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.productionTransportBlockedCount, 1)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.writeBackContractBlockedCount, 1)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.blockerClassCounts?["external_pending"], 1)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.approvalGateRequirementIds, ["example.sandboxPermissions.approval_gate_evidence"])
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.tuiGatewayRequirementIds, ["example.sessions.create.action_contract"])
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.tuiGatewayWrapperRequirementIds, nil)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.tuiGatewayFixtureBackedRequirementIds, nil)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.productionTransportRequirementIds, ["example.sessions.create.action_contract"])
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.writeBackContractRequirementIds, ["example.sessions.pin.native_write_back_contract"])
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.safeDefaultCounts?["keep_unpromoted_and_do_not_synthesize_runtime_state"], 1)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.externalPendingRequirementIds, ["example.channels.live_evidence"])
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.productBlockedRequirementIds?.count, 3)
        XCTAssertEqual(readinessPresentation.blockerClassLabel, "direct_blocker 1, external_pending 1")
        XCTAssertTrue(readinessPresentation.productBlockedIdsLabel?.contains("example.sessions.create.action_contract") == true)

        let closurePresentation = ClawJSRuntimeLensClosureChecklistPresentation.make(
            checklist: try XCTUnwrap(snapshot.supportAudit?.closureChecklist),
            summary: snapshot.supportAudit?.closureChecklistSummary
        )
        XCTAssertTrue(closurePresentation.accessibilityLabel.contains("Runtime closure checklist"))
        XCTAssertEqual(closurePresentation.rows.first?.writeBackPolicy, "blocked_until_fixture_coverage")
        XCTAssertEqual(closurePresentation.rows.first?.evidenceRequirementIdsLabel, "example.sessions.create.action_contract, example.sessions.pin.native_write_back_contract")
        XCTAssertEqual(closurePresentation.rows.first?.supportResolutionsLabel, "explicitly_product_blocked_not_a_silent_gap")

        XCTAssertEqual(snapshot.supportAudit?.evidenceReentryPackets?.first?.safeDefault, "do_not_run_without_explicit_approval_and_redaction")
        let reentryPresentation = ClawJSRuntimeLensEvidenceReentryPresentation.make(
            packets: try XCTUnwrap(snapshot.supportAudit?.evidenceReentryPackets)
        )
        XCTAssertEqual(reentryPresentation.rows.first?.exactCommand, "claw runtime example domain channels --json")
        XCTAssertEqual(reentryPresentation.rows.first?.expectedEvidenceLabel, "redacted_json_receipt, no_plaintext_secrets")
        XCTAssertEqual(reentryPresentation.rows.first?.expectedRedactedEvidenceLabel, "redacted_json_receipt_for_exact_command, no_plaintext_secrets_or_credentials, support_contract_matches_manifest")
        XCTAssertEqual(reentryPresentation.rows.first?.evidenceSafetyPolicy, "redacted_values_only_in_commands_outputs_and_evidence")
        XCTAssertEqual(reentryPresentation.rows.first?.claimBlockedUntil, "approved_redacted_live_evidence_attached")
        XCTAssertEqual(reentryPresentation.rows.first?.supportResolution, "external_pending_not_product_blocked")
        XCTAssertEqual(reentryPresentation.rows.first?.productDecision, "external_live_claim_not_supported_without_approved_redacted_evidence")
        XCTAssertEqual(reentryPresentation.rows.first?.userVisibleContract, "read_only_degraded_projection_until_live_evidence_is_approved")
        XCTAssertEqual(reentryPresentation.rows.last?.officialTransportSurface, "stdio_or_websocket_json_rpc")
        XCTAssertEqual(reentryPresentation.rows.last?.officialTransportClassesLabel, "stdio_json_rpc, websocket_json_rpc")
        XCTAssertEqual(reentryPresentation.rows.last?.officialTransportSource, "https://hermes-agent.nousresearch.com/docs/developer-guide/programmatic-integration")
        XCTAssertEqual(reentryPresentation.rows.last?.productionTransportBlocker, "approval_required_for_non_loopback_endpoint_and_lifecycle_management")
    }

    func testRuntimeLensSessionDomainAndInventoryPresentationsExposeAllControlSurfaces() async throws {
        let snapshot = try await ClawJSRuntimeLensTestFixtures.degradedRuntimePortalSnapshot()

        XCTAssertNotNil(snapshot.domainData?.sessions?.overlayState)
        XCTAssertEqual(snapshot.domainData?.sessions?.inventoryError, "OpenClaw unavailable in fixture")
        let sessionInventory = ClawJSRuntimeLensSessionInventoryPresentation.make(
            bucket: try XCTUnwrap(snapshot.domainData?.sessions)
        )
        XCTAssertTrue(sessionInventory.accessibilityLabel.contains("Runtime session inventory"))
        let sessionDescriptorPresentation = ClawJSRuntimeLensSessionDescriptorPresentation.make(
            session: try XCTUnwrap(snapshot.domainData?.sessions?.session)
        )
        XCTAssertTrue(sessionDescriptorPresentation.accessibilityLabel.contains("Runtime session descriptor"))
        let overlayPresentation = ClawJSRuntimeLensSessionOverlayPresentation.make(
            state: try XCTUnwrap(snapshot.domainData?.sessions?.overlayState)
        )
        XCTAssertTrue(overlayPresentation.accessibilityLabel.contains("Runtime session overlays"))
        let sessionOverlayActionPresentation = ClawJSRuntimeLensSessionOverlayActionPresentation.make(
            snapshot: snapshot,
            resource: try XCTUnwrap(snapshot.resources(for: "sessions").first),
            inFlightKeys: []
        )
        XCTAssertTrue(sessionOverlayActionPresentation.accessibilityLabel.contains("runtime session overlay action"))
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.sessionActionStatus("blocked"), .warning)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.resourceStatus("ready"), .success)

        XCTAssertEqual(snapshot.domainData?.sessions?.actionContracts?.count, 11)
        let sessionActionContractPresentation = ClawJSRuntimeLensSessionActionContractPresentation.make(
            contracts: try XCTUnwrap(snapshot.domainData?.sessions?.actionContracts),
            materializedPolicy: try XCTUnwrap(snapshot.domainData?.sessions?.actionPolicy)
        )
        XCTAssertTrue(sessionActionContractPresentation.accessibilityLabel.contains("Runtime session action contracts"))
        XCTAssertEqual(snapshot.domainData?.sessions?.actionPolicy?.count, 11)
        let sessionActionPresentation = ClawJSRuntimeLensSessionActionPresentation.make(
            actions: try XCTUnwrap(snapshot.domainData?.sessions?.actionPolicy)
        )
        XCTAssertTrue(sessionActionPresentation.accessibilityLabel.contains("Runtime session actions"))
        XCTAssertEqual(snapshot.domainData?.sessions?.supportContract?.evidenceRequirements?.first?.id, "example.sessions.write_back_contract")

        let ecosystemEvidencePresentation = ClawJSRuntimeLensEvidenceRequirementPresentation.make(
            requirements: try XCTUnwrap(snapshot.support?.ecosystem?.evidenceRequirements),
            limit: 3
        )
        let auditEvidencePresentation = ClawJSRuntimeLensEvidenceRequirementPresentation.make(
            requirements: try XCTUnwrap(snapshot.supportAudit?.evidenceRequirements),
            limit: 3
        )
        let domainEvidencePresentation = ClawJSRuntimeLensEvidenceRequirementPresentation.make(
            requirements: try XCTUnwrap(snapshot.domains.first { $0.domain == "channels" }?.evidenceRequirements),
            limit: 3
        )
        XCTAssertTrue(ecosystemEvidencePresentation.accessibilityLabel.contains("Runtime evidence requirements"))
        XCTAssertTrue(auditEvidencePresentation.accessibilityLabel.contains("Runtime evidence requirements"))
        XCTAssertTrue(domainEvidencePresentation.accessibilityLabel.contains("Runtime evidence requirements"))

        let domainPresentation = ClawJSRuntimeLensDomainPresentation.make(domains: snapshot.domains)
        let domainCommandPresentation = ClawJSRuntimeLensDomainCommandPresentation.make(
            domain: "channels",
            commands: try XCTUnwrap(snapshot.domains.first { $0.domain == "channels" }?.officialCommands)
        )
        let missingDomainPresentation = ClawJSRuntimeLensMissingDomainPresentation.make(domains: snapshot.domains)
        XCTAssertTrue(domainCommandPresentation.accessibilityLabel.contains("Runtime domain commands"))
        XCTAssertTrue(missingDomainPresentation.accessibilityLabel.contains("Runtime missing domains"))
        XCTAssertTrue(domainPresentation.accessibilityLabel.contains("Runtime domains"))

        let supportContractPresentation = ClawJSRuntimeLensSupportContractPresentation.make(snapshot: snapshot)
        XCTAssertTrue(supportContractPresentation.accessibilityLabel.contains("Runtime support contracts"))
        let inventoryPresentation = ClawJSRuntimeLensInventoryPresentation.make(snapshot: snapshot)
        XCTAssertTrue(inventoryPresentation.accessibilityLabel.contains("Runtime inventory"))
        XCTAssertGreaterThan(inventoryPresentation.attributeResourceCount, 0)
        let authInventory = try XCTUnwrap(inventoryPresentation.sections.first { $0.domain == "auth" })
        let modelInventory = try XCTUnwrap(inventoryPresentation.sections.first { $0.domain == "models" })
        let pluginInventory = try XCTUnwrap(inventoryPresentation.sections.first { $0.domain == "plugins" })
        let skillInventory = try XCTUnwrap(inventoryPresentation.sections.first { $0.domain == "skills" })
        let channelInventory = try XCTUnwrap(inventoryPresentation.sections.first { $0.domain == "channels" })
        let providerInventory = try XCTUnwrap(inventoryPresentation.sections.first { $0.domain == "providers" })
        let configurationInventory = try XCTUnwrap(inventoryPresentation.sections.first { $0.domain == "configuration" })
        XCTAssertEqual(authInventory.rows.first { $0.id == "openai" }?.attributesLabel, "subscription: false, api key: true, profile key: false, env key: true")
        XCTAssertEqual(modelInventory.rows.first { $0.id == "default-model" }?.attributesLabel, "provider: anthropic, model id: claude-3-opus, default: true")
        XCTAssertNotNil(pluginInventory.rows.first?.attributesLabel)
        XCTAssertEqual(skillInventory.rows.first?.attributesLabel, "scope: runtime")
        XCTAssertTrue(channelInventory.rows.first { $0.id == "telegram" }?.attributesLabel?.contains("metadata keys: knownChats, mode") == true)
        XCTAssertEqual(providerInventory.rows.first { $0.id == "openai" }?.attributesLabel, "api key auth: true, env auth: true, env vars: OPENAI_API_KEY")
        XCTAssertTrue(sessionInventory.accessibilityLabel.contains("Runtime session inventory"))
        XCTAssertEqual(channelInventory.statusLabel, "configured 1, disconnected 1")
        XCTAssertEqual(configurationInventory.statusLabel, "degraded 1, managed 1, projected 2")
        XCTAssertEqual(snapshot.resources(for: "configuration").first { $0.id == "managed-file-1" }?.path, "/tmp/workspace/AGENTS.md")
        XCTAssertEqual(snapshot.resources(for: "configuration").first { $0.id == "configuration-diagnostics" }?.summary, "config drift in fixture")
        XCTAssertEqual(snapshot.resources(for: "auth").first { $0.id == "openai" }?.status, "configured")
        XCTAssertEqual(snapshot.resources(for: "gateway").first?.status, "degraded")
        XCTAssertEqual(snapshot.resources(for: "doctorCompat").first?.status, "ready")
        XCTAssertEqual(snapshot.resources(for: "sandboxPermissions").first?.status, "degraded")
    }
}

private extension ClawJSRuntimeLensClientTests {
    static func hermesFixtureDataWithApprovalGateReceipt() -> Data {
        Data(
            """
            {
              "data": {
                "runtimeId": "hermes",
                "runtimeName": "Hermes Agent",
                "status": {},
                "domains": [
                  {
                    "domain": "doctorCompat",
                    "writeBackPolicy": "approval_gated_repair",
                    "writeBackApprovalGated": true,
                    "approvalGateFixtureStatus": "attached",
                    "approvalGateFixtureReceipt": {
                      "domain": "doctorCompat",
                      "receiptId": "fixture-doctor-denial",
                      "receiptType": "approval_gate_fixture_receipt",
                      "status": "denied_without_approval",
                      "command": "hermes doctor --fix --dry-run",
                      "approved": false,
                      "mutationPerformed": false,
                      "mutationWithoutApproval": false,
                      "plaintextSecretLeak": false,
                      "redacted": true,
                      "evidenceSafetyPolicy": "redacted_values_only_in_commands_outputs_and_evidence",
                      "source": "approval-gate-fixture"
                    }
                  }
                ],
                "domainData": {
                  "doctorCompat": {
                    "supportContract": {
                      "claim": "dev_only",
                      "authority": "runtime_adapter",
                      "writeBackPolicy": "approval_gated_repair",
                      "writeBackAllowed": false,
                      "writeBackApprovalGated": true,
                      "approvalGateFixtureStatus": "attached",
                      "approvalGateFixtureReceipt": {
                        "domain": "doctorCompat",
                        "receiptId": "fixture-doctor-denial",
                        "receiptType": "approval_gate_fixture_receipt",
                        "status": "denied_without_approval",
                        "command": "hermes doctor --fix --dry-run",
                        "approved": false,
                        "mutationPerformed": false,
                        "mutationWithoutApproval": false,
                        "plaintextSecretLeak": false,
                        "redacted": true,
                        "evidenceSafetyPolicy": "redacted_values_only_in_commands_outputs_and_evidence",
                        "source": "approval-gate-fixture"
                      },
                      "validation": "fixture_required",
                      "externalPending": false
                    }
                  }
                },
                "supportAudit": {
                  "domains": [
                    {
                      "domain": "doctorCompat",
                      "writeBackPolicy": "approval_gated_repair",
                      "writeBackApprovalGated": true,
                      "approvalGateFixtureStatus": "attached",
                      "approvalGateFixtureReceipt": {
                        "domain": "doctorCompat",
                        "receiptId": "fixture-doctor-denial",
                        "receiptType": "approval_gate_fixture_receipt",
                        "status": "denied_without_approval",
                        "command": "hermes doctor --fix --dry-run",
                        "approved": false,
                        "mutationPerformed": false,
                        "mutationWithoutApproval": false,
                        "plaintextSecretLeak": false,
                        "redacted": true,
                        "evidenceSafetyPolicy": "redacted_values_only_in_commands_outputs_and_evidence",
                        "source": "approval-gate-fixture"
                      }
                    }
                  ]
                }
              }
            }
            """.utf8
        )
    }

    static func hermesFixtureDataWithLiveEvidenceReceipt() -> Data {
        Data(
            """
            {
              "data": {
                "runtimeId": "hermes",
                "runtimeName": "Hermes Agent",
                "status": {},
                "domains": [
                  {
                    "domain": "channels",
                    "liveEvidenceFixtureStatus": "attached",
                    "liveEvidenceFixtureReceipt": {
                      "domain": "channels",
                      "receiptId": "fixture-channels-live-evidence",
                      "receiptType": "external_live_evidence_receipt",
                      "status": "approved_redacted_live_evidence",
                      "command": "claw runtime hermes domain channels --json",
                      "approved": true,
                      "readOnly": true,
                      "mutationPerformed": false,
                      "plaintextSecretLeak": false,
                      "redacted": true,
                      "supportContractMatchesManifest": true,
                      "evidenceSafetyPolicy": "redacted_values_only_in_commands_outputs_and_evidence",
                      "source": "live-evidence-fixture"
                    }
                  }
                ],
                "domainData": {
                  "channels": {
                    "supportContract": {
                      "claim": "dev_only",
                      "authority": "runtime_adapter",
                      "writeBackPolicy": "blocked_until_live_channel_evidence",
                      "writeBackAllowed": false,
                      "liveEvidenceFixtureStatus": "attached",
                      "liveEvidenceFixtureReceipt": {
                        "domain": "channels",
                        "receiptId": "fixture-channels-live-evidence",
                        "receiptType": "external_live_evidence_receipt",
                        "status": "approved_redacted_live_evidence",
                        "command": "claw runtime hermes domain channels --json",
                        "approved": true,
                        "readOnly": true,
                        "mutationPerformed": false,
                        "plaintextSecretLeak": false,
                        "redacted": true,
                        "supportContractMatchesManifest": true,
                        "evidenceSafetyPolicy": "redacted_values_only_in_commands_outputs_and_evidence",
                        "source": "live-evidence-fixture"
                      },
                      "validation": "external_pending",
                      "externalPending": true
                    }
                  }
                },
                "supportAudit": {
                  "domains": [
                    {
                      "domain": "channels",
                      "liveEvidenceFixtureStatus": "attached",
                      "liveEvidenceFixtureReceipt": {
                        "domain": "channels",
                        "receiptId": "fixture-channels-live-evidence",
                        "receiptType": "external_live_evidence_receipt",
                        "status": "approved_redacted_live_evidence",
                        "command": "claw runtime hermes domain channels --json",
                        "approved": true,
                        "readOnly": true,
                        "mutationPerformed": false,
                        "plaintextSecretLeak": false,
                        "redacted": true,
                        "supportContractMatchesManifest": true,
                        "evidenceSafetyPolicy": "redacted_values_only_in_commands_outputs_and_evidence",
                        "source": "live-evidence-fixture"
                      }
                    }
                  ]
                }
              }
            }
            """.utf8
        )
    }

    static func hermesFixtureDataWithWriteBackContractReceipt() -> Data {
        Data(
            """
            {
              "data": {
                "runtimeId": "hermes",
                "runtimeName": "Hermes Agent",
                "status": {},
                "domains": [
                  {
                    "domain": "sessions",
                    "writeBackContractFixtureStatus": "attached",
                    "writeBackContractFixtureReceipt": {
                      "domain": "sessions",
                      "receiptId": "fixture-sessions-write-back-contract",
                      "receiptType": "official_runtime_write_back_contract_receipt",
                      "status": "official_write_back_contract_verified",
                      "approved": true,
                      "redacted": true,
                      "plaintextSecretLeak": false,
                      "officialContractKnown": true,
                      "nonDestructiveFixture": true,
                      "roundTripNativeVisibility": true,
                      "noSilentWriteBack": true,
                      "supportContractMatchesManifest": true,
                      "evidenceSafetyPolicy": "redacted_values_only_in_commands_outputs_and_evidence",
                      "source": "write-back-contract-fixture"
                    }
                  }
                ],
                "domainData": {
                  "sessions": {
                    "supportContract": {
                      "claim": "dev_only",
                      "authority": "runtime_adapter",
                      "writeBackPolicy": "blocked_until_official_runtime_write_back_contract_fixture_and_round_trip_evidence",
                      "writeBackAllowed": false,
                      "writeBackContractFixtureStatus": "attached",
                      "writeBackContractFixtureReceipt": {
                        "domain": "sessions",
                        "receiptId": "fixture-sessions-write-back-contract",
                        "receiptType": "official_runtime_write_back_contract_receipt",
                        "status": "official_write_back_contract_verified",
                        "approved": true,
                        "redacted": true,
                        "plaintextSecretLeak": false,
                        "officialContractKnown": true,
                        "nonDestructiveFixture": true,
                        "roundTripNativeVisibility": true,
                        "noSilentWriteBack": true,
                        "supportContractMatchesManifest": true,
                        "evidenceSafetyPolicy": "redacted_values_only_in_commands_outputs_and_evidence",
                        "source": "write-back-contract-fixture"
                      },
                      "validation": "fixture_required",
                      "externalPending": false
                    }
                  }
                },
                "supportAudit": {
                  "domains": [
                    {
                      "domain": "sessions",
                      "writeBackContractFixtureStatus": "attached",
                      "writeBackContractFixtureReceipt": {
                        "domain": "sessions",
                        "receiptId": "fixture-sessions-write-back-contract",
                        "receiptType": "official_runtime_write_back_contract_receipt",
                        "status": "official_write_back_contract_verified",
                        "approved": true,
                        "redacted": true,
                        "plaintextSecretLeak": false,
                        "officialContractKnown": true,
                        "nonDestructiveFixture": true,
                        "roundTripNativeVisibility": true,
                        "noSilentWriteBack": true,
                        "supportContractMatchesManifest": true,
                        "evidenceSafetyPolicy": "redacted_values_only_in_commands_outputs_and_evidence",
                        "source": "write-back-contract-fixture"
                      }
                    }
                  ]
                }
              }
            }
            """.utf8
        )
    }
}
