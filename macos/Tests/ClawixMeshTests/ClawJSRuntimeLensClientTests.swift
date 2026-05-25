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
        XCTAssertEqual(snapshot.domains.map(\.domain), ClawJSRuntimeLensSnapshot.canonicalDomains)
        XCTAssertEqual(snapshot.commands?.resourceDomains, ClawJSRuntimeLensSnapshot.canonicalDomains)
        XCTAssertEqual(snapshot.support?.ecosystem?.supportStage, "dev_only")
        XCTAssertEqual(snapshot.support?.ecosystem?.uiParityClaim, "partial_runtime_lens")
        XCTAssertEqual(snapshot.supportAudit?.finalSupportClaimDecision?.effectiveSupportStage, "dev_only")
        XCTAssertEqual(snapshot.supportAudit?.finalSupportClaimDecision?.uiParityClaim, "partial_runtime_lens")
        XCTAssertEqual(snapshot.supportAudit?.finalSupportClaimDecision?.recommended, false)
        XCTAssertEqual(snapshot.supportAudit?.finalSupportClaimDecision?.production, false)
        XCTAssertEqual(snapshot.status.capabilityMap?["configuration"]?.status, "ready")
        XCTAssertEqual(snapshot.domainData?.configuration?.capability?.strategy, "config")
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
        XCTAssertEqual(snapshot.domainData?.sessions?.actionPolicy?.first { $0.action == "pin" }?.authority, "clawix_local_overlay")
        XCTAssertEqual(snapshot.domainData?.sessions?.overlayState?.writesRuntime, false)
        XCTAssertEqual(snapshot.resources(for: "sessions").first?.id, "2026/05/21/runtime-session")
        XCTAssertEqual(snapshot.resources(for: "plugins").map(\.id).sorted(), ["mcp-github", "memory-provider", "plugin-status"])
        let scalarAuthResource = try XCTUnwrap(snapshot.resources(for: "auth").first { $0.id == "tencent-tokenhub" })
        XCTAssertEqual(scalarAuthResource.status, "redacted")
        XCTAssertEqual(scalarAuthResource.kind, "redacted_auth_state")
        XCTAssertNil(scalarAuthResource.summary)
        XCTAssertEqual(scalarAuthResource.attributes?.contains("auth scalar: redacted_value"), true)

        let sessionActionPresentation = ClawJSRuntimeLensSessionActionPresentation.make(
            actions: try XCTUnwrap(snapshot.domainData?.sessions?.actionPolicy)
        )
        XCTAssertEqual(sessionActionPresentation.statusLabel, "blocked 4, implemented 5, local_overlay_only 2")
        XCTAssertEqual(sessionActionPresentation.localOverlayActionsLabel, "pin, unpin")
        XCTAssertEqual(sessionActionPresentation.blockedActionsLabel, "send, inject, abort, create")
        XCTAssertTrue(sessionActionPresentation.accessibilityLabel.contains("Runtime session actions"))
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
        XCTAssertEqual(commandPresentation.resourceDomainCount, 13)
        XCTAssertEqual(commandPresentation.rows.first?.writeDisposition, "blocked write")

        XCTAssertEqual(snapshot.supportAudit?.closureState, "blocked")
        let supportAuditPresentation = ClawJSRuntimeLensSupportAuditPresentation.make(audit: audit)
        XCTAssertTrue(supportAuditPresentation.accessibilityLabel.contains("Runtime support audit"))
        XCTAssertEqual(supportAuditPresentation.blockerClassLabel, "direct_blocker 2, external_pending 1")
        XCTAssertEqual(snapshot.supportAudit?.evidenceRequirements?.first?.fallbackPolicy, "do_not_synthesize_native_runtime_action")
        XCTAssertEqual(snapshot.supportAudit?.evidenceRequirements?.first?.supportResolution, "explicitly_product_blocked_not_a_silent_gap")
        XCTAssertEqual(snapshot.supportAudit?.finalPromotionReview?.claimDisposition, "unpromoted_external_pending")
        XCTAssertEqual(snapshot.supportAudit?.finalPromotionReview?.productBlockedRequirementIds?.count, 2)
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
        XCTAssertEqual(finalDecisionPresentation.promotionEvidenceRequiredLabel, "approved_redacted_live_evidence, keep_lowered_claim_until_upstream_native_contracts_exist")
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
        XCTAssertEqual(validationSummary.finalDecisionPromotionEvidenceLabel, "approved_redacted_live_evidence, keep_lowered_claim_until_upstream_native_contracts_exist")
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
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.blockerClassCounts?["external_pending"], 1)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.safeDefaultCounts?["keep_unpromoted_and_do_not_synthesize_runtime_state"], 1)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.externalPendingRequirementIds, ["example.channels.live_evidence"])
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.productBlockedRequirementIds?.count, 2)
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
        XCTAssertEqual(reentryPresentation.rows.first?.expectedEvidenceLabel, "redacted_json_receipt, no_plaintext_secrets")
        XCTAssertEqual(reentryPresentation.rows.first?.supportResolution, "external_pending_not_product_blocked")
        XCTAssertEqual(reentryPresentation.rows.first?.productDecision, "external_live_claim_not_supported_without_approved_redacted_evidence")
        XCTAssertEqual(reentryPresentation.rows.first?.userVisibleContract, "read_only_degraded_projection_until_live_evidence_is_approved")
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
