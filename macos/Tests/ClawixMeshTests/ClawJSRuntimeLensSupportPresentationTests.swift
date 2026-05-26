import XCTest
@testable import Clawix

final class ClawJSRuntimeLensSupportPresentationTests: XCTestCase {
    func testEvidenceReadinessPresentationMarksTruncatedRequirementIds() {
        let summary = ClawJSRuntimeLensSnapshot.SupportAudit.EvidenceReadinessSummary(
            statusCounts: nil,
            blockerClassCounts: nil,
            safeDefaultCounts: nil,
            totalRequirementCount: 16,
            approvalRequiredCount: 0,
            externalPendingCount: 0,
            upstreamContractBlockedCount: 0,
            approvalGateBlockedCount: 0,
            tuiGatewayBlockedCount: 4,
            productionTransportBlockedCount: 4,
            writeBackContractBlockedCount: 8,
            productBlockedCount: 16,
            unresolvedNativeRequirementCount: 0,
            approvalRequiredRequirementIds: nil,
            externalPendingRequirementIds: nil,
            upstreamContractRequirementIds: nil,
            approvalGateRequirementIds: nil,
            tuiGatewayRequirementIds: [
                "hermes.sessions.send.action_contract",
                "hermes.sessions.inject.action_contract",
                "hermes.sessions.abort.action_contract",
                "hermes.sessions.create.action_contract"
            ],
            productionTransportRequirementIds: [
                "hermes.sessions.send.action_contract",
                "hermes.sessions.inject.action_contract",
                "hermes.sessions.abort.action_contract",
                "hermes.sessions.create.action_contract"
            ],
            writeBackContractRequirementIds: [
                "hermes.sessions.pin.native_write_back_contract",
                "hermes.sessions.unpin.native_write_back_contract",
                "hermes.skills.write_back_contract",
                "hermes.configuration.write_back_contract"
            ],
            productBlockedRequirementIds: [
                "hermes.sessions.send.action_contract",
                "hermes.sessions.inject.action_contract",
                "hermes.sessions.abort.action_contract",
                "hermes.sessions.create.action_contract"
            ],
            unresolvedNativeRequirementIds: [],
            nextRequiredActions: [
                "approved_redacted_live_evidence",
                "approval_gate_fixture_and_redacted_receipt",
                "tui_gateway_wrapper_fixture_and_round_trip_evidence",
                "production_transport_lifecycle_policy_and_native_round_trip_evidence",
                "official_runtime_write_back_contract_fixture",
                "official_runtime_native_contract_fixture",
                "approved_native_pin_api"
            ],
            reentryPolicy: "use_evidence_reentry_packets_before_claim_promotion",
            safeDefault: "keep_unpromoted_and_follow_exact_reentry_packets"
        )

        let presentation = ClawJSRuntimeLensSupportSummaryPresentation.make(
            evidenceReadiness: summary
        )

        XCTAssertEqual(
            presentation.tuiGatewayIdsLabel,
            "hermes.sessions.send.action_contract, hermes.sessions.inject.action_contract, hermes.sessions.abort.action_contract, +1 more"
        )
        XCTAssertEqual(
            presentation.productionTransportIdsLabel,
            "hermes.sessions.send.action_contract, hermes.sessions.inject.action_contract, hermes.sessions.abort.action_contract, +1 more"
        )
        XCTAssertEqual(
            presentation.writeBackContractIdsLabel,
            "hermes.sessions.pin.native_write_back_contract, hermes.sessions.unpin.native_write_back_contract, hermes.skills.write_back_contract, +1 more"
        )
        XCTAssertEqual(
            presentation.productBlockedIdsLabel,
            "hermes.sessions.send.action_contract, hermes.sessions.inject.action_contract, hermes.sessions.abort.action_contract, +1 more"
        )
        XCTAssertEqual(
            presentation.nextRequiredActionsLabel,
            "approved_redacted_live_evidence, approval_gate_fixture_and_redacted_receipt, tui_gateway_wrapper_fixture_and_round_trip_evidence, production_transport_lifecycle_policy_and_native_round_trip_evidence, official_runtime_write_back_contract_fixture, official_runtime_native_contract_fixture, +1 more"
        )
        XCTAssertTrue(presentation.accessibilityLabel.contains("+1 more"))
    }

    func testRuntimeLensSupportAuditEvidenceAndPromotionPresentations() async throws {
        let snapshot = try await ClawJSRuntimeLensTestFixtures.degradedRuntimePortalSnapshot()

        let supportOverviewPresentation = ClawJSRuntimeLensSupportOverviewPresentation.make(
            support: try XCTUnwrap(snapshot.support)
        )
        XCTAssertEqual(supportOverviewPresentation.adapterSupportLevel, "dev-only")
        XCTAssertEqual(supportOverviewPresentation.adapterStability, "dev-only")
        XCTAssertEqual(supportOverviewPresentation.ecosystemSupportStage, "dev_only")
        XCTAssertEqual(supportOverviewPresentation.ecosystemRecommended, false)
        XCTAssertEqual(supportOverviewPresentation.ecosystemProduction, false)
        XCTAssertEqual(supportOverviewPresentation.notPromoted, true)
        XCTAssertEqual(supportOverviewPresentation.blockingReasonCount, 0)
        XCTAssertEqual(supportOverviewPresentation.evidenceRequirementCount, 1)
        XCTAssertEqual(supportOverviewPresentation.hasSummary, true)
        XCTAssertEqual(supportOverviewPresentation.claimSource, "runtime-ecosystem-manifest")
        XCTAssertEqual(supportOverviewPresentation.provenanceSource, "runtime-ecosystem-manifest")
        XCTAssertEqual(supportOverviewPresentation.provenanceRuntimeId, "example")
        XCTAssertEqual(supportOverviewPresentation.sourceLabel, "runtime-ecosystem-manifest, runtime example")
        XCTAssertTrue(supportOverviewPresentation.accessibilityLabel.contains("Runtime support overview"))
        XCTAssertTrue(supportOverviewPresentation.accessibilityLabel.contains("not promoted true"))
        XCTAssertTrue(supportOverviewPresentation.accessibilityLabel.contains("claim source runtime-ecosystem-manifest"))
        XCTAssertTrue(supportOverviewPresentation.accessibilityLabel.contains("provenance runtime example"))
        XCTAssertEqual(snapshot.supportAudit?.closureState, "blocked")
        XCTAssertEqual(snapshot.supportAudit?.supportComplete, false)
        XCTAssertEqual(snapshot.supportAudit?.allDomainsAccountedFor, true)
        XCTAssertEqual(snapshot.supportAudit?.blockerSummary?.byBlockerClass?["direct_blocker"], 3)
        XCTAssertEqual(snapshot.supportAudit?.blockerSummary?.productBlockedRequirementCount, 3)
        XCTAssertEqual(snapshot.supportAudit?.blockerSummary?.externalPendingDomains, ["channels"])
        XCTAssertEqual(snapshot.supportAudit?.provenance?.source, "runtime-portal-support-audit")
        XCTAssertEqual(snapshot.supportAudit?.provenance?.runtimeId, "example")
        let supportAuditPresentation = ClawJSRuntimeLensSupportAuditPresentation.make(
            audit: try XCTUnwrap(snapshot.supportAudit)
        )
        XCTAssertEqual(supportAuditPresentation.closureState, "blocked")
        XCTAssertEqual(supportAuditPresentation.supportComplete, false)
        XCTAssertEqual(supportAuditPresentation.allDomainsAccountedFor, true)
        XCTAssertEqual(supportAuditPresentation.evidenceRequirementCount, 4)
        XCTAssertEqual(supportAuditPresentation.directBlockerCount, 3)
        XCTAssertEqual(supportAuditPresentation.externalPendingCount, 1)
        XCTAssertEqual(supportAuditPresentation.productBlockedRequirementCount, 3)
        XCTAssertEqual(supportAuditPresentation.supportStage, "dev_only")
        XCTAssertEqual(supportAuditPresentation.blockerClassLabel, "direct_blocker 3, external_pending 1")
        XCTAssertEqual(supportAuditPresentation.directBlockerDomainsLabel, "sessions")
        XCTAssertEqual(supportAuditPresentation.externalPendingDomainsLabel, "channels")
        XCTAssertEqual(supportAuditPresentation.blockedWriteBackDomainsLabel, "sessions")
        XCTAssertEqual(supportAuditPresentation.ecosystemExternalPendingDomainsLabel, "channels")
        XCTAssertEqual(supportAuditPresentation.provenanceSource, "runtime-portal-support-audit")
        XCTAssertEqual(supportAuditPresentation.provenanceRuntimeId, "example")
        XCTAssertEqual(supportAuditPresentation.provenanceLabel, "runtime-portal-support-audit, runtime example")
        XCTAssertTrue(supportAuditPresentation.accessibilityLabel.contains("Runtime support audit"))
        XCTAssertTrue(supportAuditPresentation.accessibilityLabel.contains("product blocked 3"))
        XCTAssertTrue(supportAuditPresentation.accessibilityLabel.contains("blocked write back domains sessions"))
        XCTAssertTrue(supportAuditPresentation.accessibilityLabel.contains("promotion gate support_claim_remains_unpromoted"))
        XCTAssertTrue(supportAuditPresentation.accessibilityLabel.contains("provenance source runtime-portal-support-audit"))
        let ecosystemEvidencePresentation = ClawJSRuntimeLensEvidenceRequirementPresentation.make(
            requirements: snapshot.support?.ecosystem?.evidenceRequirements ?? [],
            limit: 3
        )
        XCTAssertEqual(ecosystemEvidencePresentation.totalRequirementCount, 1)
        XCTAssertEqual(ecosystemEvidencePresentation.approvalRequiredCount, 1)
        XCTAssertEqual(ecosystemEvidencePresentation.externalPendingCount, 1)
        XCTAssertEqual(ecosystemEvidencePresentation.commandShapeCount, 1)
        XCTAssertEqual(ecosystemEvidencePresentation.blockerClassLabel, "external_pending 1")
        XCTAssertEqual(ecosystemEvidencePresentation.rows.first?.id, "example.channels.live_evidence")
        XCTAssertEqual(ecosystemEvidencePresentation.rows.first?.expectedEvidenceCount, 2)
        XCTAssertEqual(ecosystemEvidencePresentation.rows.first?.riskControlCount, 1)
        XCTAssertTrue(ecosystemEvidencePresentation.rows.first?.accessibilityLabel.contains("approval required true") == true)
        XCTAssertTrue(ecosystemEvidencePresentation.accessibilityLabel.contains("Runtime evidence requirements"))
        XCTAssertEqual(snapshot.supportAudit?.evidenceRequirements?.first?.id, "example.sessions.create.action_contract")
        XCTAssertEqual(snapshot.supportAudit?.evidenceRequirements?.first?.fallbackPolicy, "do_not_synthesize_native_runtime_action")
        XCTAssertEqual(snapshot.supportAudit?.evidenceRequirements?.first?.supportResolution, "explicitly_product_blocked_not_a_silent_gap")
        XCTAssertEqual(snapshot.supportAudit?.evidenceRequirements?.first?.productDecision, "native_session_action_unsupported_until_official_runtime_contract")
        let auditEvidencePresentation = ClawJSRuntimeLensEvidenceRequirementPresentation.make(
            requirements: snapshot.supportAudit?.evidenceRequirements ?? [],
            limit: 3
        )
        XCTAssertEqual(auditEvidencePresentation.totalRequirementCount, 1)
        XCTAssertEqual(auditEvidencePresentation.directBlockerCount, 1)
        XCTAssertEqual(auditEvidencePresentation.productBlockedCount, 1)
        XCTAssertEqual(auditEvidencePresentation.rows.first?.resolutionLabel, "explicitly_product_blocked_not_a_silent_gap, native_session_action_unsupported_until_official_runtime_contract")
        XCTAssertTrue(auditEvidencePresentation.accessibilityLabel.contains("direct blockers 1"))
        XCTAssertEqual(snapshot.supportAudit?.domains?.first { $0.domain == "sessions" }?.evidenceRequirementIds?.contains("example.sessions.create.action_contract"), true)
        XCTAssertEqual(snapshot.supportAudit?.domains?.first { $0.domain == "sessions" }?.evidenceDispositions?.contains("blocked_until_official_runtime_action_contract"), true)
        XCTAssertEqual(snapshot.supportAudit?.domains?.first { $0.domain == "sessions" }?.supportResolutions?.contains("explicitly_product_blocked_not_a_silent_gap"), true)
        XCTAssertEqual(snapshot.supportAudit?.promotionGate, "support_claim_remains_unpromoted_until_all_evidence_requirements_are_closed_or_explicitly_product_blocked")
        XCTAssertEqual(snapshot.supportAudit?.closureChecklist?.first { $0.domain == "sessions" }?.closureStatus, "product_blocked")
        XCTAssertEqual(snapshot.supportAudit?.closureChecklist?.first { $0.domain == "sessions" }?.readProjectionStatus, "projected")
        XCTAssertEqual(snapshot.supportAudit?.closureChecklist?.first { $0.domain == "sessions" }?.implementedFacets?.contains("session_list_action"), true)
        XCTAssertEqual(snapshot.supportAudit?.closureChecklist?.first { $0.domain == "sessions" }?.blockingFacets?.contains("native_action_contract"), true)
        XCTAssertEqual(snapshot.supportAudit?.closureChecklist?.first { $0.domain == "sessions" }?.projectionDisposition, "read_projection_available_write_back_blocked")
        XCTAssertEqual(snapshot.supportAudit?.closureChecklist?.first { $0.domain == "sessions" }?.safeDefault, "keep_lowered_claim_until_upstream_native_contract_exists")
        XCTAssertEqual(snapshot.supportAudit?.closureChecklist?.first { $0.domain == "channels" }?.closureStatus, "external_pending")
        XCTAssertEqual(snapshot.supportAudit?.closureChecklist?.first { $0.domain == "channels" }?.projectionDisposition, "read_projection_available_live_evidence_pending")
        XCTAssertEqual(snapshot.supportAudit?.closureChecklist?.first { $0.domain == "channels" }?.nextAction, "use_matching_evidenceReentryPacket_after_explicit_approval")
        XCTAssertEqual(snapshot.supportAudit?.closureChecklistSummary?["external_pending"], 1)
        XCTAssertEqual(snapshot.supportAudit?.projectionSummary?.projectedDomainCount, 2)
        XCTAssertEqual(snapshot.supportAudit?.projectionSummary?.unsupportedDomainCount, 0)
        XCTAssertEqual(snapshot.supportAudit?.projectionSummary?.productBlockedButProjectedDomainCount, 1)
        XCTAssertEqual(snapshot.supportAudit?.projectionSummary?.byReadProjectionStatus?["projected"], 1)
        XCTAssertEqual(snapshot.supportAudit?.projectionSummary?.implementedFacetCounts?["session_list_action"], 1)
        XCTAssertEqual(snapshot.supportAudit?.projectionSummary?.blockingFacetCounts?["native_action_contract"], 1)
        XCTAssertEqual(snapshot.supportAudit?.syncPolicySummary?.domainCount, 2)
        XCTAssertEqual(snapshot.supportAudit?.syncPolicySummary?.canonicalAuthorityCounts?["runtime"], 1)
        XCTAssertEqual(snapshot.supportAudit?.syncPolicySummary?.nativeAuthorityCounts?["runtime"], 2)
        XCTAssertEqual(snapshot.supportAudit?.syncPolicySummary?.persistenceCounts?["index_and_shadow_when_safe"], 1)
        XCTAssertEqual(snapshot.supportAudit?.syncPolicySummary?.relationCounts?["native_projection"], 1)
        XCTAssertEqual(snapshot.supportAudit?.syncPolicySummary?.writeBackPolicyCounts?["blocked_until_fixture_coverage"], 1)
        XCTAssertEqual(snapshot.supportAudit?.syncPolicySummary?.lossPolicyCounts?["preserve_when_safe"], 1)
        XCTAssertEqual(snapshot.supportAudit?.syncPolicySummary?.readOnlyProjectionDomains, ["sessions", "channels"])
        XCTAssertEqual(snapshot.supportAudit?.syncPolicySummary?.blockedWriteBackDomains, ["sessions"])
        XCTAssertEqual(snapshot.supportAudit?.syncPolicySummary?.externalPendingDomains, ["channels"])
        XCTAssertEqual(snapshot.supportAudit?.syncPolicySummary?.localOverlayDomains, ["sessions"])
        XCTAssertEqual(snapshot.supportAudit?.syncPolicySummary?.localOverlayActions, ["pin", "unpin"])
        XCTAssertEqual(snapshot.supportAudit?.syncPolicySummary?.freshnessCounts?["snapshot"], 1)
        XCTAssertEqual(snapshot.supportAudit?.syncPolicySummary?.freshnessCounts?["degraded_snapshot"], 1)
        XCTAssertEqual(snapshot.supportAudit?.syncPolicySummary?.noSilentOverwrite, true)
        XCTAssertEqual(snapshot.supportAudit?.syncPolicySummary?.defaultSyncMode, "read_projection_first_no_silent_write_back")
        XCTAssertEqual(snapshot.supportAudit?.syncPolicySummary?.safeDefault, "project_runtime_state_do_not_sync_or_write_back_without_official_contract")
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.totalRequirementCount, 4)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.approvalRequiredCount, 1)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.externalPendingCount, 1)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.upstreamContractBlockedCount, 1)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.approvalGateBlockedCount, 1)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.tuiGatewayBlockedCount, 1)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.productionTransportBlockedCount, 1)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.writeBackContractBlockedCount, 1)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.productBlockedCount, 3)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.unresolvedNativeRequirementCount, 0)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.blockerClassCounts?["direct_blocker"], 1)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.safeDefaultCounts?["do_not_run_without_approval_gate_fixture"], 1)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.safeDefaultCounts?["keep_unpromoted_and_do_not_synthesize_runtime_state"], 1)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.approvalRequiredRequirementIds?.contains("example.channels.live_evidence"), true)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.externalPendingRequirementIds?.contains("example.channels.live_evidence"), true)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.upstreamContractRequirementIds?.contains("example.sessions.create.action_contract"), true)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.approvalGateRequirementIds?.contains("example.sandboxPermissions.approval_gate_evidence"), true)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.tuiGatewayRequirementIds, ["example.sessions.create.action_contract"])
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.productionTransportRequirementIds, ["example.sessions.create.action_contract"])
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.writeBackContractRequirementIds, ["example.sessions.pin.native_write_back_contract"])
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.productBlockedRequirementIds?.contains("example.sessions.pin.native_write_back_contract"), true)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.unresolvedNativeRequirementIds, [])
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.nextRequiredActions?.contains("approval_gate_fixture_and_redacted_receipt"), true)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.nextRequiredActions?.contains("tui_gateway_wrapper_fixture_and_round_trip_evidence"), true)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.nextRequiredActions?.contains("production_transport_lifecycle_policy_and_native_round_trip_evidence"), true)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.nextRequiredActions?.contains("official_runtime_write_back_contract_fixture"), true)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.nextRequiredActions?.contains("official_runtime_native_contract_fixture"), true)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.reentryPolicy, "use_evidence_reentry_packets_before_claim_promotion")
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.safeDefault, "keep_unpromoted_and_follow_exact_reentry_packets")
        let projectionPresentation = ClawJSRuntimeLensSupportSummaryPresentation.make(
            projection: try XCTUnwrap(snapshot.supportAudit?.projectionSummary)
        )
        XCTAssertEqual(projectionPresentation.projectedDomainCount, 2)
        XCTAssertEqual(projectionPresentation.unsupportedDomainCount, 0)
        XCTAssertEqual(projectionPresentation.productBlockedButProjectedDomainCount, 1)
        XCTAssertEqual(projectionPresentation.readStatusLabel, "degraded_projection 1, projected 1")
        XCTAssertEqual(projectionPresentation.implementedFacetLabel, "manifest_domain_contract 2, session_list_action 1")
        XCTAssertEqual(projectionPresentation.blockingFacetLabel, "approved_live_evidence 1, native_action_contract 1")
        XCTAssertTrue(projectionPresentation.accessibilityLabel.contains("Runtime projection summary"))
        XCTAssertTrue(projectionPresentation.accessibilityLabel.contains("product blocked but projected 1"))
        XCTAssertTrue(projectionPresentation.accessibilityLabel.contains("implemented facets manifest_domain_contract 2"))
        XCTAssertTrue(projectionPresentation.accessibilityLabel.contains("blocking facets approved_live_evidence 1"))
        let syncPresentation = ClawJSRuntimeLensSupportSummaryPresentation.make(
            sync: try XCTUnwrap(snapshot.supportAudit?.syncPolicySummary)
        )
        XCTAssertEqual(syncPresentation.domainCount, 2)
        XCTAssertEqual(syncPresentation.readOnlyDomainCount, 2)
        XCTAssertEqual(syncPresentation.localOverlayDomainCount, 1)
        XCTAssertEqual(syncPresentation.blockedWriteBackLabel, "sessions")
        XCTAssertEqual(syncPresentation.canonicalAuthorityLabel, "claw_registry_with_runtime_binding 1, runtime 1")
        XCTAssertEqual(syncPresentation.nativeAuthorityLabel, "runtime 2")
        XCTAssertEqual(syncPresentation.persistenceLabel, "index_and_shadow_when_safe 1, secret_refs_only 1")
        XCTAssertEqual(syncPresentation.relationLabel, "gateway_projection 1, native_projection 1")
        XCTAssertEqual(syncPresentation.writeBackPolicyLabel, "blocked_until_fixture_coverage 1, external_pending_live_accounts 1")
        XCTAssertEqual(syncPresentation.lossPolicyLabel, "preserve_when_safe 1, secret_refs_only 1")
        XCTAssertEqual(syncPresentation.freshnessLabel, "degraded_snapshot 1, snapshot 1")
        XCTAssertTrue(syncPresentation.accessibilityLabel.contains("Runtime sync policy summary"))
        XCTAssertTrue(syncPresentation.accessibilityLabel.contains("canonical authority claw_registry_with_runtime_binding 1"))
        XCTAssertTrue(syncPresentation.accessibilityLabel.contains("write back policy blocked_until_fixture_coverage 1"))
        XCTAssertTrue(syncPresentation.accessibilityLabel.contains("no silent overwrite true"))
        let readinessPresentation = ClawJSRuntimeLensSupportSummaryPresentation.make(
            evidenceReadiness: try XCTUnwrap(snapshot.supportAudit?.evidenceReadinessSummary)
        )
        XCTAssertEqual(readinessPresentation.totalRequirementCount, 4)
        XCTAssertEqual(readinessPresentation.approvalRequiredCount, 1)
        XCTAssertEqual(readinessPresentation.upstreamContractBlockedCount, 1)
        XCTAssertEqual(readinessPresentation.approvalGateBlockedCount, 1)
        XCTAssertEqual(readinessPresentation.tuiGatewayBlockedCount, 1)
        XCTAssertEqual(readinessPresentation.productionTransportBlockedCount, 1)
        XCTAssertEqual(readinessPresentation.writeBackContractBlockedCount, 1)
        XCTAssertEqual(readinessPresentation.statusLabel, "approval_required 1, blocked_until_approval_gate_fixture 1, blocked_until_upstream_contract 1")
        XCTAssertEqual(readinessPresentation.blockerClassLabel, "direct_blocker 1, external_pending 1")
        XCTAssertEqual(readinessPresentation.safeDefaultLabel, "do_not_run_without_approval_gate_fixture 1, do_not_run_without_explicit_approval_and_redaction 1, keep_unpromoted_and_do_not_synthesize_runtime_state 1")
        XCTAssertEqual(readinessPresentation.approvalRequiredIdsLabel, "example.channels.live_evidence")
        XCTAssertEqual(readinessPresentation.externalPendingIdsLabel, "example.channels.live_evidence")
        XCTAssertEqual(readinessPresentation.upstreamContractIdsLabel, "example.sessions.create.action_contract")
        XCTAssertEqual(readinessPresentation.approvalGateIdsLabel, "example.sandboxPermissions.approval_gate_evidence")
        XCTAssertEqual(readinessPresentation.tuiGatewayIdsLabel, "example.sessions.create.action_contract")
        XCTAssertEqual(readinessPresentation.productionTransportIdsLabel, "example.sessions.create.action_contract")
        XCTAssertEqual(readinessPresentation.writeBackContractIdsLabel, "example.sessions.pin.native_write_back_contract")
        XCTAssertEqual(readinessPresentation.productBlockedIdsLabel, "example.sessions.create.action_contract, example.sessions.pin.native_write_back_contract, example.sandboxPermissions.approval_gate_evidence")
        XCTAssertNil(readinessPresentation.unresolvedNativeIdsLabel)
        XCTAssertEqual(readinessPresentation.nextRequiredActionsLabel, "approved_redacted_live_evidence, approval_gate_fixture_and_redacted_receipt, tui_gateway_wrapper_fixture_and_round_trip_evidence, production_transport_lifecycle_policy_and_native_round_trip_evidence, official_runtime_write_back_contract_fixture, official_runtime_native_contract_fixture")
        XCTAssertTrue(readinessPresentation.accessibilityLabel.contains("Runtime evidence readiness summary"))
        XCTAssertTrue(readinessPresentation.accessibilityLabel.contains("approval gate blocked 1"))
        XCTAssertTrue(readinessPresentation.accessibilityLabel.contains("tui gateway blocked 1"))
        XCTAssertTrue(readinessPresentation.accessibilityLabel.contains("production transport blocked 1"))
        XCTAssertTrue(readinessPresentation.accessibilityLabel.contains("write back contract blocked 1"))
        XCTAssertTrue(readinessPresentation.accessibilityLabel.contains("blocker classes direct_blocker 1"))
        XCTAssertTrue(readinessPresentation.accessibilityLabel.contains("approval gate ids example.sandboxPermissions.approval_gate_evidence"))
        XCTAssertTrue(readinessPresentation.accessibilityLabel.contains("tui gateway ids example.sessions.create.action_contract"))
        XCTAssertTrue(readinessPresentation.accessibilityLabel.contains("production transport ids example.sessions.create.action_contract"))
        XCTAssertTrue(readinessPresentation.accessibilityLabel.contains("write back contract ids example.sessions.pin.native_write_back_contract"))
        XCTAssertTrue(readinessPresentation.accessibilityLabel.contains("product blocked ids example.sessions.create.action_contract"))
        XCTAssertTrue(readinessPresentation.accessibilityLabel.contains("safe default keep_unpromoted_and_follow_exact_reentry_packets"))
        let closurePresentation = ClawJSRuntimeLensClosureChecklistPresentation.make(
            checklist: snapshot.supportAudit?.closureChecklist ?? [],
            summary: snapshot.supportAudit?.closureChecklistSummary
        )
        XCTAssertEqual(closurePresentation.totalLabel, "closure 2")
        XCTAssertEqual(closurePresentation.statusPills.map(\.label), ["external_pending 1", "product_blocked 1"])
        XCTAssertEqual(closurePresentation.rows.map(\.domain), ["sessions", "channels"])
        XCTAssertEqual(closurePresentation.rows.first?.evidenceCount, 2)
        XCTAssertEqual(closurePresentation.rows.first?.evidenceRequirementIdsLabel, "example.sessions.create.action_contract, example.sessions.pin.native_write_back_contract")
        XCTAssertEqual(closurePresentation.rows.first?.readProjectionStatus, "projected")
        XCTAssertEqual(closurePresentation.rows.first?.implementedFacetCount, 3)
        XCTAssertEqual(closurePresentation.rows.first?.blockingFacetCount, 3)
        XCTAssertEqual(closurePresentation.rows.first?.claim, "inventoried")
        XCTAssertEqual(closurePresentation.rows.first?.runtimeStatus, "error")
        XCTAssertEqual(closurePresentation.rows.first?.writeBackPolicy, "blocked_until_fixture_coverage")
        XCTAssertEqual(closurePresentation.rows.first?.validation, "fixture_required")
        XCTAssertEqual(closurePresentation.rows.first?.blockerClassesLabel, "direct_blocker")
        XCTAssertEqual(closurePresentation.rows.first?.supportResolutionsLabel, "explicitly_product_blocked_not_a_silent_gap")
        XCTAssertTrue(closurePresentation.accessibilityLabel.contains("sessions product_blocked"))
        XCTAssertTrue(closurePresentation.rows.first?.accessibilityLabel.contains("read projection projected") == true)
        XCTAssertTrue(closurePresentation.rows.first?.accessibilityLabel.contains("write back blocked_until_fixture_coverage") == true)
        XCTAssertTrue(closurePresentation.rows.first?.accessibilityLabel.contains("evidence ids example.sessions.create.action_contract") == true)
        XCTAssertTrue(closurePresentation.rows.last?.accessibilityLabel.contains("blocker classes external_pending") == true)
        XCTAssertTrue(closurePresentation.rows.last?.accessibilityLabel.contains("support resolutions external_pending_not_product_blocked") == true)
        let validationSummary = ClawJSRuntimeLensValidationSummary.make(snapshot: snapshot)
        XCTAssertEqual(validationSummary.coverageStatus, "semantic_lens_covered")
        XCTAssertTrue(validationSummary.isSemanticallyCovered)
        XCTAssertEqual(validationSummary.checklistTotal, 2)
        XCTAssertEqual(validationSummary.evidenceReentryPacketCount, 3)
        XCTAssertEqual(validationSummary.evidenceApprovalGateBlockedCount, 1)
        XCTAssertEqual(validationSummary.projectedDomainCount, 2)
        XCTAssertEqual(validationSummary.unsupportedDomainCount, 0)
        XCTAssertEqual(validationSummary.productBlockedButProjectedDomainCount, 1)
        XCTAssertEqual(validationSummary.syncReadOnlyDomainCount, 2)
        XCTAssertEqual(validationSummary.syncLocalOverlayDomainCount, 1)
        XCTAssertEqual(validationSummary.syncWriteBackAllowedDomainCount, 0)
        XCTAssertEqual(validationSummary.syncFreshnessLabel, "degraded_snapshot 1, snapshot 1")
        XCTAssertEqual(validationSummary.evidenceApprovalRequiredCount, 1)
        XCTAssertEqual(validationSummary.evidenceUpstreamContractBlockedCount, 1)
        XCTAssertEqual(validationSummary.evidenceApprovalGateBlockedCount, 1)
        XCTAssertEqual(validationSummary.evidenceTuiGatewayBlockedCount, 1)
        XCTAssertEqual(validationSummary.evidenceProductionTransportBlockedCount, 1)
        XCTAssertEqual(validationSummary.evidenceWriteBackContractBlockedCount, 1)
        XCTAssertEqual(validationSummary.evidenceUnresolvedNativeRequirementCount, 0)
        XCTAssertTrue(validationSummary.accessibilityLabel.contains("projected domains 2"))
        XCTAssertTrue(validationSummary.accessibilityLabel.contains("product blocked but projected 1"))
        XCTAssertTrue(validationSummary.accessibilityLabel.contains("read only sync domains 2"))
        XCTAssertTrue(validationSummary.accessibilityLabel.contains("local overlay domains 1"))
        XCTAssertTrue(validationSummary.accessibilityLabel.contains("freshness degraded_snapshot 1, snapshot 1"))
        XCTAssertTrue(validationSummary.accessibilityLabel.contains("upstream contract blocked 1"))
        XCTAssertTrue(validationSummary.accessibilityLabel.contains("tui gateway blocked 1"))
        XCTAssertTrue(validationSummary.accessibilityLabel.contains("production transport blocked 1"))
        XCTAssertTrue(validationSummary.accessibilityLabel.contains("write back contract blocked 1"))
        XCTAssertEqual(validationSummary.externalPendingRequirementCount, 1)
        XCTAssertEqual(validationSummary.productBlockedRequirementCount, 3)
        XCTAssertEqual(validationSummary.finalDecisionId, "keep_current_lowered_runtime_ecosystem_claim")
        XCTAssertFalse(validationSummary.recommended)
        XCTAssertFalse(validationSummary.production)
        XCTAssertEqual(validationSummary.uiParityClaim, "partial_template_only")
        XCTAssertEqual(validationSummary.uiParityDisposition, "partial_lens_validated_not_full_native_parity")
        XCTAssertEqual(validationSummary.blockedPromotionClaims, ["recommended", "production", "native_parity", "write_back", "approval_gate_fixture", "tui_gateway_wrapper_fixture", "production_transport_lifecycle"])
        XCTAssertEqual(validationSummary.finalDecisionBlockerClassesLabel, "external_pending, direct_blocker")
        XCTAssertEqual(
            validationSummary.finalDecisionProductBlockedIdsLabel,
            "example.sessions.create.action_contract, example.sessions.pin.native_write_back_contract, example.sandboxPermissions.approval_gate_evidence"
        )
        XCTAssertEqual(validationSummary.finalDecisionExternalPendingIdsLabel, "example.channels.live_evidence")
        XCTAssertNil(validationSummary.finalDecisionUnresolvedNativeIdsLabel)
        XCTAssertEqual(
            validationSummary.finalDecisionPromotionEvidenceLabel,
            "approved_redacted_live_evidence, approval_gate_fixture_and_redacted_receipt, tui_gateway_wrapper_fixture_and_round_trip_evidence, production_transport_lifecycle_policy_and_native_round_trip_evidence, keep_lowered_claim_until_upstream_native_contracts_exist"
        )
        XCTAssertTrue(validationSummary.accessibilityLabel.contains("all domains accounted"))
        XCTAssertTrue(validationSummary.accessibilityLabel.contains("decision id keep_current_lowered_runtime_ecosystem_claim"))
        XCTAssertTrue(validationSummary.accessibilityLabel.contains("recommended false"))
        XCTAssertTrue(validationSummary.accessibilityLabel.contains("ui parity claim partial_template_only"))
        XCTAssertTrue(validationSummary.accessibilityLabel.contains("blocked claims recommended, production, native_parity, write_back, approval_gate_fixture, tui_gateway_wrapper_fixture, production_transport_lifecycle"))
        XCTAssertTrue(validationSummary.accessibilityLabel.contains("final blocker classes external_pending, direct_blocker"))
        XCTAssertTrue(validationSummary.accessibilityLabel.contains("final promotion evidence approved_redacted_live_evidence"))
        XCTAssertEqual(snapshot.supportAudit?.finalPromotionReview?.status, "unpromoted")
        XCTAssertEqual(snapshot.supportAudit?.finalPromotionReview?.finalPromotionAllowed, false)
        XCTAssertEqual(snapshot.supportAudit?.finalPromotionReview?.claimDisposition, "unpromoted_product_blocked_and_external_pending")
        XCTAssertEqual(snapshot.supportAudit?.finalPromotionReview?.productBlockedByDecisionCount, 3)
        XCTAssertEqual(snapshot.supportAudit?.finalPromotionReview?.externalPendingRequirementIds?.contains("example.channels.live_evidence"), true)
        XCTAssertEqual(snapshot.supportAudit?.finalPromotionReview?.productBlockedRequirementIds?.contains("example.sessions.create.action_contract"), true)
        XCTAssertEqual(snapshot.supportAudit?.finalPromotionReview?.unresolvedNativeRequirementCount, 0)
        XCTAssertEqual(snapshot.supportAudit?.finalPromotionReview?.unresolvedNativeRequirementIds, [])
        XCTAssertEqual(snapshot.supportAudit?.finalPromotionReview?.requiredForPromotion?.contains("approved_redacted_live_evidence"), true)
        XCTAssertEqual(snapshot.supportAudit?.finalPromotionReview?.userVisibleStatus, "runtime_ecosystem_available_with_product_blocked_or_external_pending_claims")
        let promotionReviewPresentation = ClawJSRuntimeLensSupportDecisionPresentation.make(
            review: try XCTUnwrap(snapshot.supportAudit?.finalPromotionReview)
        )
        XCTAssertEqual(promotionReviewPresentation.status, "unpromoted")
        XCTAssertEqual(promotionReviewPresentation.claimDisposition, "unpromoted_product_blocked_and_external_pending")
        XCTAssertEqual(promotionReviewPresentation.productBlockedCount, 3)
        XCTAssertEqual(promotionReviewPresentation.externalPendingCount, 1)
        XCTAssertEqual(promotionReviewPresentation.unresolvedNativeRequirementCount, 0)
        XCTAssertEqual(
            promotionReviewPresentation.productBlockedIdsLabel,
            "example.sessions.create.action_contract, example.sessions.pin.native_write_back_contract, example.sandboxPermissions.approval_gate_evidence"
        )
        XCTAssertEqual(promotionReviewPresentation.externalPendingIdsLabel, "example.channels.live_evidence")
        XCTAssertNil(promotionReviewPresentation.unresolvedNativeIdsLabel)
        XCTAssertEqual(
            promotionReviewPresentation.requiredForPromotionLabel,
            "approved_redacted_live_evidence, approval_gate_fixture_and_redacted_receipt, tui_gateway_wrapper_fixture_and_round_trip_evidence, production_transport_lifecycle_policy_and_native_round_trip_evidence, keep_lowered_claim_until_upstream_native_contracts_exist"
        )
        XCTAssertTrue(promotionReviewPresentation.accessibilityLabel.contains("Runtime final promotion review"))
        XCTAssertTrue(promotionReviewPresentation.accessibilityLabel.contains("product blocked 3"))
        XCTAssertTrue(promotionReviewPresentation.accessibilityLabel.contains("external pending 1"))
        XCTAssertTrue(promotionReviewPresentation.accessibilityLabel.contains("product blocked ids example.sessions.create.action_contract"))
        XCTAssertEqual(snapshot.supportAudit?.finalSupportClaimDecision?.status, "not_promoted")
        XCTAssertEqual(snapshot.supportAudit?.finalSupportClaimDecision?.decision, "keep_current_lowered_runtime_ecosystem_claim")
        XCTAssertEqual(snapshot.supportAudit?.finalSupportClaimDecision?.effectiveSupportStage, "dev_only")
        XCTAssertEqual(snapshot.supportAudit?.finalSupportClaimDecision?.recommended, false)
        XCTAssertEqual(snapshot.supportAudit?.finalSupportClaimDecision?.production, false)
        XCTAssertEqual(snapshot.supportAudit?.finalSupportClaimDecision?.uiParityDisposition, "partial_lens_validated_not_full_native_parity")
        XCTAssertEqual(snapshot.supportAudit?.finalSupportClaimDecision?.blockedPromotionClaims?.contains("native_parity"), true)
        XCTAssertEqual(snapshot.supportAudit?.finalSupportClaimDecision?.blockedPromotionClaims?.contains("write_back"), true)
        XCTAssertEqual(snapshot.supportAudit?.finalSupportClaimDecision?.blockerClasses, ["external_pending", "direct_blocker"])
        XCTAssertEqual(snapshot.supportAudit?.finalSupportClaimDecision?.productBlockedRequirementIds?.contains("example.sessions.pin.native_write_back_contract"), true)
        XCTAssertEqual(snapshot.supportAudit?.finalSupportClaimDecision?.externalPendingRequirementIds?.contains("example.channels.live_evidence"), true)
        XCTAssertEqual(snapshot.supportAudit?.finalSupportClaimDecision?.unresolvedNativeRequirementIds, [])
        XCTAssertEqual(snapshot.supportAudit?.finalSupportClaimDecision?.promotionEvidenceRequired?.contains("approved_redacted_live_evidence"), true)
        XCTAssertEqual(snapshot.supportAudit?.finalSupportClaimDecision?.reentryPolicy, "use_evidenceReentryPackets_exactly_before_revisiting_claim")
        XCTAssertEqual(snapshot.supportAudit?.finalSupportClaimDecision?.safeDefault, "keep_unpromoted_until_evidence_or_upstream_contract_changes")
        let finalDecisionPresentation = ClawJSRuntimeLensSupportDecisionPresentation.make(
            decision: try XCTUnwrap(snapshot.supportAudit?.finalSupportClaimDecision)
        )
        XCTAssertEqual(finalDecisionPresentation.status, "not_promoted")
        XCTAssertEqual(finalDecisionPresentation.decision, "keep_current_lowered_runtime_ecosystem_claim")
        XCTAssertEqual(finalDecisionPresentation.effectiveSupportStage, "dev_only")
        XCTAssertFalse(finalDecisionPresentation.recommended)
        XCTAssertFalse(finalDecisionPresentation.production)
        XCTAssertEqual(finalDecisionPresentation.uiParityClaim, "partial_template_only")
        XCTAssertEqual(finalDecisionPresentation.uiParityDisposition, "partial_lens_validated_not_full_native_parity")
        XCTAssertEqual(finalDecisionPresentation.claimDisposition, "unpromoted_product_blocked_and_external_pending")
        XCTAssertEqual(finalDecisionPresentation.blockedPromotionClaimsLabel, "recommended, production, native_parity, write_back, approval_gate_fixture, tui_gateway_wrapper_fixture, production_transport_lifecycle")
        XCTAssertEqual(finalDecisionPresentation.blockerClassesLabel, "external_pending, direct_blocker")
        XCTAssertEqual(
            finalDecisionPresentation.productBlockedIdsLabel,
            "example.sessions.create.action_contract, example.sessions.pin.native_write_back_contract, example.sandboxPermissions.approval_gate_evidence"
        )
        XCTAssertEqual(finalDecisionPresentation.externalPendingIdsLabel, "example.channels.live_evidence")
        XCTAssertNil(finalDecisionPresentation.unresolvedNativeIdsLabel)
        XCTAssertEqual(
            finalDecisionPresentation.promotionEvidenceRequiredLabel,
            "approved_redacted_live_evidence, approval_gate_fixture_and_redacted_receipt, tui_gateway_wrapper_fixture_and_round_trip_evidence, production_transport_lifecycle_policy_and_native_round_trip_evidence, keep_lowered_claim_until_upstream_native_contracts_exist"
        )
        XCTAssertTrue(finalDecisionPresentation.accessibilityLabel.contains("Runtime final support claim decision"))
        XCTAssertTrue(finalDecisionPresentation.accessibilityLabel.contains("decision keep_current_lowered_runtime_ecosystem_claim"))
        XCTAssertTrue(finalDecisionPresentation.accessibilityLabel.contains("blocked claims recommended, production, native_parity, write_back, approval_gate_fixture, tui_gateway_wrapper_fixture, production_transport_lifecycle"))
        XCTAssertTrue(finalDecisionPresentation.accessibilityLabel.contains("blocker classes external_pending, direct_blocker"))
        XCTAssertTrue(finalDecisionPresentation.accessibilityLabel.contains("promotion evidence approved_redacted_live_evidence"))
        XCTAssertTrue(finalDecisionPresentation.accessibilityLabel.contains("safe default keep_unpromoted_until_evidence_or_upstream_contract_changes"))
        XCTAssertEqual(snapshot.supportAudit?.evidenceReentryPackets?.first?.requirementId, "example.channels.live_evidence")
        XCTAssertEqual(snapshot.supportAudit?.evidenceReentryPackets?.first?.status, "approval_required")
        XCTAssertEqual(snapshot.supportAudit?.evidenceReentryPackets?.first?.safeDefault, "do_not_run_without_explicit_approval_and_redaction")
        XCTAssertEqual(snapshot.supportAudit?.evidenceReentryPackets?.first?.commandShape, "runtime example domain channels --json")
        XCTAssertEqual(snapshot.supportAudit?.evidenceReentryPackets?.first?.exactCommand, "claw runtime example domain channels --json")
        XCTAssertEqual(snapshot.supportAudit?.evidenceReentryPackets?.first?.preflightCommand, "claw runtime example support --json")
        XCTAssertEqual(snapshot.supportAudit?.evidenceReentryPackets?.first?.approvalScope, "read_only_redacted_live_domain_evidence_only")
        XCTAssertEqual(snapshot.supportAudit?.evidenceReentryPackets?.first?.evidenceSafetyPolicy, "redacted_values_only_in_commands_outputs_and_evidence")
        XCTAssertEqual(snapshot.supportAudit?.evidenceReentryPackets?.first?.expectedRedactedEvidence?.contains("no_plaintext_secrets_or_credentials"), true)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReentryPackets?.first?.claimBlockedUntil, "approved_redacted_live_evidence_attached")
        XCTAssertEqual(snapshot.supportAudit?.evidenceReentryPackets?.first?.doNotRunWithoutApproval, true)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReentryPackets?.first?.riskControls?.contains("read_only_first"), true)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReentryPackets?.last?.status, "blocked_until_upstream_contract")
        XCTAssertEqual(snapshot.supportAudit?.evidenceReentryPackets?.last?.safeDefault, "keep_unpromoted_and_do_not_synthesize_runtime_state")
        XCTAssertEqual(snapshot.supportAudit?.evidenceReentryPackets?.last?.exactCommand, "claw runtime example sessions create --title <approved-title> --confirm-runtime-write --gateway-url <approved-loopback-fixture-url> --json")
        XCTAssertEqual(snapshot.supportAudit?.evidenceReentryPackets?.last?.productionTransportStatus, "blocked_until_production_transport_lifecycle_policy")
        XCTAssertEqual(snapshot.supportAudit?.evidenceReentryPackets?.last?.productionTransportCommandShape, "blocked_until_approved_production_transport_lifecycle_policy_and_non_loopback_endpoint_approval")
        XCTAssertEqual(snapshot.supportAudit?.evidenceReentryPackets?[1].status, "blocked_until_approval_gate_fixture")
        XCTAssertEqual(snapshot.supportAudit?.evidenceReentryPackets?[1].safeDefault, "do_not_run_without_approval_gate_fixture")
        XCTAssertEqual(snapshot.supportAudit?.evidenceReentryPackets?[1].expectedRedactedEvidence?.contains("approval_gate_fixture_receipt"), true)
        let reentryPresentation = ClawJSRuntimeLensEvidenceReentryPresentation.make(
            packets: snapshot.supportAudit?.evidenceReentryPackets ?? []
        )
        XCTAssertEqual(reentryPresentation.totalLabel, "reentry 3")
        XCTAssertEqual(reentryPresentation.statusPills.map(\.label), [
            "approval_required 1",
            "blocked_until_approval_gate_fixture 1",
            "blocked_until_upstream_contract 1"
        ])
        XCTAssertEqual(reentryPresentation.approvalRequiredCount, 2)
        XCTAssertEqual(reentryPresentation.rows.map(\.requirementId), [
            "example.channels.live_evidence",
            "example.sandboxPermissions.approval_gate_evidence",
            "example.sessions.create.action_contract"
        ])
        XCTAssertEqual(reentryPresentation.rows.first?.approvalRequired, true)
        XCTAssertEqual(reentryPresentation.rows.first?.expectedEvidenceCount, 2)
        XCTAssertEqual(reentryPresentation.rows.first?.expectedEvidenceLabel, "redacted_json_receipt, no_plaintext_secrets")
        XCTAssertEqual(reentryPresentation.rows.first?.exactCommand, "claw runtime example domain channels --json")
        XCTAssertEqual(reentryPresentation.rows.first?.preflightCommand, "claw runtime example support --json")
        XCTAssertEqual(reentryPresentation.rows.first?.approvalScope, "read_only_redacted_live_domain_evidence_only")
        XCTAssertEqual(reentryPresentation.rows.first?.evidenceSafetyPolicy, "redacted_values_only_in_commands_outputs_and_evidence")
        XCTAssertEqual(reentryPresentation.rows.first?.expectedRedactedEvidenceCount, 3)
        XCTAssertEqual(reentryPresentation.rows.first?.expectedRedactedEvidenceLabel, "redacted_json_receipt_for_exact_command, no_plaintext_secrets_or_credentials, support_contract_matches_manifest")
        XCTAssertEqual(reentryPresentation.rows.first?.claimBlockedUntil, "approved_redacted_live_evidence_attached")
        XCTAssertEqual(reentryPresentation.rows.first?.doNotRunWithoutApproval, true)
        XCTAssertEqual(reentryPresentation.rows.first?.riskControlCount, 1)
        XCTAssertEqual(reentryPresentation.rows.first?.riskControlsLabel, "read_only_first")
        XCTAssertEqual(reentryPresentation.rows.first?.claimEffect, "blocks_recommended_production_native_parity")
        XCTAssertEqual(reentryPresentation.rows.first?.supportResolution, "external_pending_not_product_blocked")
        XCTAssertEqual(
            reentryPresentation.rows.first?.productDecision,
            "external_live_claim_not_supported_without_approved_redacted_evidence"
        )
        XCTAssertEqual(
            reentryPresentation.rows.first?.userVisibleContract,
            "read_only_degraded_projection_until_live_evidence_is_approved"
        )
        XCTAssertTrue(reentryPresentation.rows.first?.accessibilityLabel.contains("approval required") == true)
        XCTAssertTrue(reentryPresentation.rows.first?.accessibilityLabel.contains("exact command claw runtime example domain channels --json") == true)
        XCTAssertTrue(reentryPresentation.rows.first?.accessibilityLabel.contains("do not run without approval") == true)
        XCTAssertTrue(reentryPresentation.rows.first?.accessibilityLabel.contains("expected evidence redacted_json_receipt") == true)
        XCTAssertTrue(reentryPresentation.rows.first?.accessibilityLabel.contains("support resolution external_pending_not_product_blocked") == true)
        XCTAssertEqual(reentryPresentation.rows[1].status, "blocked_until_approval_gate_fixture")
        XCTAssertEqual(reentryPresentation.rows[1].safeDefault, "do_not_run_without_approval_gate_fixture")
        XCTAssertEqual(reentryPresentation.rows[1].expectedRedactedEvidenceLabel, "approval_gate_fixture_receipt, non_destructive_dry_run_or_denial_receipt, no_plaintext_secrets_or_permission_tokens")
        XCTAssertTrue(reentryPresentation.rows[1].accessibilityLabel.contains("claim blocked until approval_gate_fixture_and_redacted_receipt_attached") == true)
        XCTAssertEqual(reentryPresentation.rows.last?.officialMethod, "session.create")
        XCTAssertEqual(reentryPresentation.rows.last?.productionTransportStatus, "blocked_until_production_transport_lifecycle_policy")
        XCTAssertEqual(reentryPresentation.rows.last?.productionTransportCommandShape, "blocked_until_approved_production_transport_lifecycle_policy_and_non_loopback_endpoint_approval")
        XCTAssertTrue(reentryPresentation.rows.last?.accessibilityLabel.contains("product decision native_session_action_unsupported_until_official_runtime_contract") == true)
        XCTAssertTrue(reentryPresentation.accessibilityLabel.contains("approval required 2"))
        XCTAssertTrue(reentryPresentation.accessibilityLabel.contains("blocked_until_approval_gate_fixture 1"))
        XCTAssertTrue(reentryPresentation.accessibilityLabel.contains("blocked_until_upstream_contract 1"))
    }
}
