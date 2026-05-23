import XCTest
@testable import Clawix

final class ClawJSRuntimeLensClientTests: XCTestCase {
    func testRuntimeLensRefreshPlanScopesToSelectedRuntimeOnly() {
        let plan = ClawJSRuntimeLensRefreshPlan.scoped(to: .hermes)

        XCTAssertEqual(plan.runtimes, [.hermes])
        XCTAssertFalse(plan.runtimes.contains(.openclaw))

        let viewStatePresentation = ClawJSRuntimeLensViewStatePresentation.make(
            runtime: .hermes,
            isRefreshing: false,
            loadError: nil,
            actionError: nil,
            hasSnapshot: false
        )
        XCTAssertEqual(viewStatePresentation.runtimeId, "hermes")
        XCTAssertEqual(viewStatePresentation.runtimeLabel, "Hermes")
        XCTAssertEqual(viewStatePresentation.rowCount, 1)
        XCTAssertEqual(viewStatePresentation.rows.first?.kind, "empty")
        XCTAssertEqual(viewStatePresentation.rows.first?.message, "Hermes snapshot pending")
        XCTAssertTrue(viewStatePresentation.accessibilityLabel.contains("snapshot false"))

        let errorStatePresentation = ClawJSRuntimeLensViewStatePresentation.make(
            runtime: .openclaw,
            isRefreshing: true,
            loadError: " portal unavailable ",
            actionError: "local overlay failed",
            hasSnapshot: true
        )
        XCTAssertEqual(errorStatePresentation.rowCount, 3)
        XCTAssertEqual(errorStatePresentation.rows.map(\.kind), ["refreshing", "load_error", "action_error"])
        XCTAssertEqual(errorStatePresentation.rows.first { $0.kind == "load_error" }?.message, "portal unavailable")
        XCTAssertEqual(errorStatePresentation.rows.first { $0.kind == "action_error" }?.severity, "warning")
        XCTAssertTrue(errorStatePresentation.hasLoadError)
        XCTAssertTrue(errorStatePresentation.hasActionError)
        XCTAssertTrue(errorStatePresentation.accessibilityLabel.contains("Runtime lens view state"))
    }

    func testRuntimeLensStatusToneKeepsBlockedAndLocalStateSemanticsCentralized() {
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.sessionActionStatus("implemented"), .success)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.sessionActionStatus("local_overlay_only"), .info)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.sessionActionStatus("blocked"), .warning)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.sessionActionDisposition("would write"), .warning)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.commandDisposition("blocked write"), .warning)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.commandDisposition("no write"), .muted)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.overlayConflictStatus("native_and_local"), .success)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.overlayConflictStatus("local_only"), .warning)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.closureStatus("direct_blocker"), .danger)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.closureStatus("external_pending"), .warning)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.evidenceReentryStatus("approval_required"), .warning)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.ecosystemStage("native_parity"), .success)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.ecosystemStage("dev_only"), .warning)
        XCTAssertEqual(
            ClawJSRuntimeLensStatusTone.runtimeDomainStatus(status: "ready", supported: true),
            .success
        )
        XCTAssertEqual(
            ClawJSRuntimeLensStatusTone.runtimeDomainStatus(status: "unknown", supported: false),
            .muted
        )
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.supportClaim("operable"), .success)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.supportClaim("blocked"), .muted)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.evidenceBlockerClass("external_pending"), .warning)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.evidenceBlockerClass("pre_existing_dirty"), .muted)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.resourceStatus("configured"), .success)
        XCTAssertEqual(ClawJSRuntimeLensStatusTone.resourceStatus("failed"), .danger)
    }

    func testRuntimeLensRejectsOversizedEnvelopeBeforeDecode() async throws {
        let oversized = Data(repeating: UInt8(ascii: "x"), count: 1_048_577)
        let client = ClawJSRuntimeLensClient(runner: .init { _ in
            .init(data: oversized, exitCode: 0)
        })

        do {
            _ = try await client.load(runtime: .hermes)
            XCTFail("Expected oversized runtime lens payload to fail")
        } catch let error as NSError {
            XCTAssertEqual(error.domain, "ClawJSRuntimeLensClient")
            XCTAssertEqual(error.code, 413)
        }
    }

    func testRuntimeLensUsesTopLevelResourcesAsInventoryFallback() async throws {
        let client = ClawJSRuntimeLensClient(runner: .init { args in
            XCTAssertEqual(args, ["runtime", "hermes", "domains", "--json"])
            return .init(
                data: try ClawJSRuntimeLensTestFixtures.data(named: "top-level-resources-fallback"),
                exitCode: 0
            )
        })

        let snapshot = try await client.load(runtime: .hermes)
        let runtimeSummary = ClawJSRuntimeLensRuntimeSummaryPresentation.make(snapshot: snapshot)

        XCTAssertEqual(snapshot.session?.sessionPath, "/Users/tester/.example/sessions")
        XCTAssertEqual(snapshot.runtimeResources?.providers?.first?.id, "openai")
        XCTAssertEqual(snapshot.runtimeResources?.auth?["openai"]?.hasEnvKey, true)
        XCTAssertEqual(runtimeSummary.runtimeResourceAggregateDomainCount, 7)
        XCTAssertEqual(runtimeSummary.runtimeResourceCount, 7)
        XCTAssertEqual(
            runtimeSummary.runtimeResourcesLabel,
            "providers 1, models 1, auth 1, scheduler 1, memory 1, skills 1, channels 1"
        )
        XCTAssertTrue(runtimeSummary.accessibilityLabel.contains("runtime resource aggregate domains 7"))
        XCTAssertTrue(runtimeSummary.accessibilityLabel.contains("runtime resources 7"))
        XCTAssertEqual(snapshot.resources(for: "skills").first?.id, "example-skills")
        XCTAssertEqual(snapshot.resources(for: "memory").first?.path, "/Users/tester/.example/memories")
        XCTAssertEqual(snapshot.resources(for: "channels").first?.status, "configured")
        XCTAssertEqual(snapshot.resources(for: "providers").first?.envVars, ["OPENAI_API_KEY"])
        XCTAssertEqual(snapshot.resources(for: "providers").first?.attributes, [
            "api key auth: true",
            "env auth: true",
            "env vars: OPENAI_API_KEY"
        ])
        XCTAssertEqual(snapshot.resources(for: "auth").first?.id, "openai")
        XCTAssertEqual(snapshot.resources(for: "auth").first?.attributes, [
            "subscription: false",
            "api key: true",
            "profile key: false",
            "env key: true"
        ])
        XCTAssertEqual(snapshot.resources(for: "models").first?.id, "default-model")
        XCTAssertEqual(snapshot.resources(for: "models").first?.attributes, [
            "provider: openai",
            "model id: gpt-4.1",
            "default: true"
        ])
        XCTAssertEqual(snapshot.resources(for: "scheduler").first?.id, "example-scheduler")
        XCTAssertEqual(snapshot.resources(for: "configuration").first { $0.id == "SOUL" }?.path, "/tmp/workspace/SOUL.md")
        XCTAssertEqual(snapshot.resources(for: "configuration").first { $0.id == "managed-file-1" }?.path, "/tmp/workspace/AGENTS.md")
    }

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
        let runtimeSummaryPresentation = ClawJSRuntimeLensRuntimeSummaryPresentation.make(snapshot: snapshot)
        XCTAssertEqual(runtimeSummaryPresentation.runtimeId, "example")
        XCTAssertEqual(runtimeSummaryPresentation.runtimeName, "Example Agent")
        XCTAssertEqual(snapshot.status.adapter, "example")
        XCTAssertEqual(snapshot.status.version, "1.2.3")
        XCTAssertEqual(snapshot.status.capabilities?["conversationCli"], true)
        XCTAssertEqual(snapshot.status.capabilityMap?["runtime"]?.diagnostics?.source, "runtime")
        XCTAssertEqual(snapshot.status.capabilityMap?["channels"]?.limitations?.first, "Channel inventory is normalized from Example gateway capabilities.")
        XCTAssertEqual(snapshot.session?.sessionPath, "/Users/tester/.example/sessions")
        XCTAssertEqual(snapshot.session?.primaryTransport, "gateway")
        XCTAssertEqual(snapshot.workspace?.canonicalPaths?["SOUL"], "/tmp/workspace/SOUL.md")
        XCTAssertEqual(snapshot.workspace?.managedFiles?.count, 2)
        XCTAssertEqual(runtimeSummaryPresentation.adapter, "example")
        XCTAssertEqual(runtimeSummaryPresentation.version, "1.2.3")
        XCTAssertEqual(runtimeSummaryPresentation.installed, false)
        XCTAssertEqual(runtimeSummaryPresentation.installedLabel, "Not installed")
        XCTAssertEqual(runtimeSummaryPresentation.cliLabel, "Unavailable")
        XCTAssertEqual(runtimeSummaryPresentation.gatewayLabel, "Degraded")
        XCTAssertEqual(runtimeSummaryPresentation.homeDir, "/Users/tester/.example")
        XCTAssertEqual(runtimeSummaryPresentation.workspacePath, "/tmp/workspace")
        XCTAssertEqual(runtimeSummaryPresentation.configPath, "/Users/tester/.example/config.json")
        XCTAssertEqual(runtimeSummaryPresentation.authStorePath, "/Users/tester/.example/auth.json")
        XCTAssertEqual(runtimeSummaryPresentation.gatewayConfigPath, "/Users/tester/.example/gateway.json")
        XCTAssertEqual(runtimeSummaryPresentation.locationRows.map(\.id), ["home", "workspace", "config", "auth-store", "gateway-config"])
        XCTAssertEqual(runtimeSummaryPresentation.locationRows.first?.accessibilityLabel, "Home /Users/tester/.example")
        XCTAssertEqual(runtimeSummaryPresentation.locationCount, 5)
        XCTAssertEqual(runtimeSummaryPresentation.workspaceCanonicalPathCount, 3)
        XCTAssertEqual(runtimeSummaryPresentation.workspaceManagedFileCount, 2)
        XCTAssertEqual(runtimeSummaryPresentation.workspaceFilesLabel, "canonical SKILLS, SOUL, USER; managed 2")
        XCTAssertEqual(runtimeSummaryPresentation.lastError, "example CLI not found")
        XCTAssertEqual(runtimeSummaryPresentation.hasHomeDir, true)
        XCTAssertEqual(runtimeSummaryPresentation.hasLastError, true)
        XCTAssertEqual(runtimeSummaryPresentation.supportPresent, true)
        XCTAssertEqual(runtimeSummaryPresentation.supportAuditPresent, true)
        XCTAssertEqual(runtimeSummaryPresentation.rawCapabilityCount, 3)
        XCTAssertEqual(runtimeSummaryPresentation.rawCapabilityEnabledCount, 1)
        XCTAssertEqual(runtimeSummaryPresentation.capabilityCount, 4)
        XCTAssertEqual(runtimeSummaryPresentation.readyCapabilityCount, 1)
        XCTAssertEqual(runtimeSummaryPresentation.degradedCapabilityCount, 1)
        XCTAssertEqual(runtimeSummaryPresentation.errorCapabilityCount, 1)
        XCTAssertEqual(runtimeSummaryPresentation.unsupportedCapabilityCount, 1)
        XCTAssertEqual(runtimeSummaryPresentation.capabilityStatusLabel, "degraded 1, error 1, ready 1, unsupported 1")
        XCTAssertEqual(runtimeSummaryPresentation.capabilityRows.map(\.id), ["channels", "plugins", "runtime", "workspace"])
        XCTAssertEqual(runtimeSummaryPresentation.capabilityRows.first?.limitationsLabel, "Channel inventory is normalized from Example gateway capabilities.")
        XCTAssertTrue(runtimeSummaryPresentation.capabilityRows.first?.accessibilityLabel.contains("strategy native") == true)
        XCTAssertTrue(runtimeSummaryPresentation.accessibilityLabel.contains("Runtime summary"))
        XCTAssertTrue(runtimeSummaryPresentation.accessibilityLabel.contains("adapter example"))
        XCTAssertTrue(runtimeSummaryPresentation.accessibilityLabel.contains("version 1.2.3"))
        XCTAssertTrue(runtimeSummaryPresentation.accessibilityLabel.contains("workspace canonical paths 3"))
        XCTAssertTrue(runtimeSummaryPresentation.accessibilityLabel.contains("workspace files canonical SKILLS, SOUL, USER; managed 2"))
        XCTAssertTrue(runtimeSummaryPresentation.accessibilityLabel.contains("raw capabilities 3"))
        XCTAssertTrue(runtimeSummaryPresentation.accessibilityLabel.contains("capability status degraded 1, error 1, ready 1, unsupported 1"))
        XCTAssertTrue(runtimeSummaryPresentation.accessibilityLabel.contains("Workspace /tmp/workspace"))
        XCTAssertTrue(runtimeSummaryPresentation.accessibilityLabel.contains("Gateway config /Users/tester/.example/gateway.json"))
        XCTAssertTrue(runtimeSummaryPresentation.accessibilityLabel.contains("support audit true"))
        XCTAssertEqual(snapshot.support?.ecosystem?.evidenceRequirements?.first?.id, "example.channels.live_evidence")
        XCTAssertEqual(snapshot.support?.ecosystem?.evidenceRequirements?.first?.approvalRequired, true)
        XCTAssertEqual(snapshot.support?.ecosystem?.evidenceRequirements?.first?.evidenceDisposition, "external_pending_until_approved_redacted_live_receipt")
        XCTAssertEqual(snapshot.support?.ecosystem?.evidenceRequirements?.first?.currentBehavior, "read_only_projection_or_degraded_snapshot_only")
        XCTAssertEqual(snapshot.support?.ecosystem?.claimSource, "runtime-ecosystem-manifest")
        XCTAssertEqual(snapshot.support?.ecosystem?.provenance?.source, "runtime-ecosystem-manifest")
        XCTAssertEqual(snapshot.support?.ecosystem?.provenance?.runtimeId, "example")
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
        XCTAssertEqual(snapshot.supportAudit?.blockerSummary?.byBlockerClass?["direct_blocker"], 2)
        XCTAssertEqual(snapshot.supportAudit?.blockerSummary?.productBlockedRequirementCount, 2)
        XCTAssertEqual(snapshot.supportAudit?.blockerSummary?.externalPendingDomains, ["channels"])
        XCTAssertEqual(snapshot.supportAudit?.provenance?.source, "runtime-portal-support-audit")
        XCTAssertEqual(snapshot.supportAudit?.provenance?.runtimeId, "example")
        let supportAuditPresentation = ClawJSRuntimeLensSupportAuditPresentation.make(
            audit: try XCTUnwrap(snapshot.supportAudit)
        )
        XCTAssertEqual(supportAuditPresentation.closureState, "blocked")
        XCTAssertEqual(supportAuditPresentation.supportComplete, false)
        XCTAssertEqual(supportAuditPresentation.allDomainsAccountedFor, true)
        XCTAssertEqual(supportAuditPresentation.evidenceRequirementCount, 3)
        XCTAssertEqual(supportAuditPresentation.directBlockerCount, 2)
        XCTAssertEqual(supportAuditPresentation.externalPendingCount, 1)
        XCTAssertEqual(supportAuditPresentation.productBlockedRequirementCount, 2)
        XCTAssertEqual(supportAuditPresentation.supportStage, "dev_only")
        XCTAssertEqual(supportAuditPresentation.blockerClassLabel, "direct_blocker 2, external_pending 1")
        XCTAssertEqual(supportAuditPresentation.directBlockerDomainsLabel, "sessions")
        XCTAssertEqual(supportAuditPresentation.externalPendingDomainsLabel, "channels")
        XCTAssertEqual(supportAuditPresentation.blockedWriteBackDomainsLabel, "sessions")
        XCTAssertEqual(supportAuditPresentation.ecosystemExternalPendingDomainsLabel, "channels")
        XCTAssertEqual(supportAuditPresentation.provenanceSource, "runtime-portal-support-audit")
        XCTAssertEqual(supportAuditPresentation.provenanceRuntimeId, "example")
        XCTAssertEqual(supportAuditPresentation.provenanceLabel, "runtime-portal-support-audit, runtime example")
        XCTAssertTrue(supportAuditPresentation.accessibilityLabel.contains("Runtime support audit"))
        XCTAssertTrue(supportAuditPresentation.accessibilityLabel.contains("product blocked 2"))
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
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.totalRequirementCount, 3)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.approvalRequiredCount, 1)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.externalPendingCount, 1)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.upstreamContractBlockedCount, 1)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.productBlockedCount, 2)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.unresolvedNativeRequirementCount, 0)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.blockerClassCounts?["direct_blocker"], 1)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.safeDefaultCounts?["keep_unpromoted_and_do_not_synthesize_runtime_state"], 1)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.approvalRequiredRequirementIds?.contains("example.channels.live_evidence"), true)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.externalPendingRequirementIds?.contains("example.channels.live_evidence"), true)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.upstreamContractRequirementIds?.contains("example.sessions.create.action_contract"), true)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.productBlockedRequirementIds?.contains("example.sessions.pin.native_write_back_contract"), true)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReadinessSummary?.unresolvedNativeRequirementIds, [])
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
        XCTAssertEqual(readinessPresentation.totalRequirementCount, 3)
        XCTAssertEqual(readinessPresentation.approvalRequiredCount, 1)
        XCTAssertEqual(readinessPresentation.upstreamContractBlockedCount, 1)
        XCTAssertEqual(readinessPresentation.statusLabel, "approval_required 1, blocked_until_upstream_contract 1")
        XCTAssertEqual(readinessPresentation.blockerClassLabel, "direct_blocker 1, external_pending 1")
        XCTAssertEqual(readinessPresentation.safeDefaultLabel, "do_not_run_without_explicit_approval_and_redaction 1, keep_unpromoted_and_do_not_synthesize_runtime_state 1")
        XCTAssertEqual(readinessPresentation.approvalRequiredIdsLabel, "example.channels.live_evidence")
        XCTAssertEqual(readinessPresentation.externalPendingIdsLabel, "example.channels.live_evidence")
        XCTAssertEqual(readinessPresentation.upstreamContractIdsLabel, "example.sessions.create.action_contract")
        XCTAssertEqual(readinessPresentation.productBlockedIdsLabel, "example.sessions.create.action_contract, example.sessions.pin.native_write_back_contract")
        XCTAssertNil(readinessPresentation.unresolvedNativeIdsLabel)
        XCTAssertEqual(readinessPresentation.nextRequiredActionsLabel, "approved_redacted_live_evidence, official_runtime_native_contract_fixture")
        XCTAssertTrue(readinessPresentation.accessibilityLabel.contains("Runtime evidence readiness summary"))
        XCTAssertTrue(readinessPresentation.accessibilityLabel.contains("blocker classes direct_blocker 1"))
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
        XCTAssertEqual(validationSummary.evidenceReentryPacketCount, 2)
        XCTAssertEqual(validationSummary.projectedDomainCount, 2)
        XCTAssertEqual(validationSummary.unsupportedDomainCount, 0)
        XCTAssertEqual(validationSummary.productBlockedButProjectedDomainCount, 1)
        XCTAssertEqual(validationSummary.syncReadOnlyDomainCount, 2)
        XCTAssertEqual(validationSummary.syncLocalOverlayDomainCount, 1)
        XCTAssertEqual(validationSummary.syncWriteBackAllowedDomainCount, 0)
        XCTAssertEqual(validationSummary.syncFreshnessLabel, "degraded_snapshot 1, snapshot 1")
        XCTAssertEqual(validationSummary.evidenceApprovalRequiredCount, 1)
        XCTAssertEqual(validationSummary.evidenceUpstreamContractBlockedCount, 1)
        XCTAssertEqual(validationSummary.evidenceUnresolvedNativeRequirementCount, 0)
        XCTAssertTrue(validationSummary.accessibilityLabel.contains("projected domains 2"))
        XCTAssertTrue(validationSummary.accessibilityLabel.contains("product blocked but projected 1"))
        XCTAssertTrue(validationSummary.accessibilityLabel.contains("read only sync domains 2"))
        XCTAssertTrue(validationSummary.accessibilityLabel.contains("local overlay domains 1"))
        XCTAssertTrue(validationSummary.accessibilityLabel.contains("freshness degraded_snapshot 1, snapshot 1"))
        XCTAssertTrue(validationSummary.accessibilityLabel.contains("upstream contract blocked 1"))
        XCTAssertEqual(validationSummary.externalPendingRequirementCount, 1)
        XCTAssertEqual(validationSummary.productBlockedRequirementCount, 2)
        XCTAssertEqual(validationSummary.finalDecisionId, "keep_current_lowered_runtime_ecosystem_claim")
        XCTAssertFalse(validationSummary.recommended)
        XCTAssertFalse(validationSummary.production)
        XCTAssertEqual(validationSummary.uiParityClaim, "partial_template_only")
        XCTAssertEqual(validationSummary.uiParityDisposition, "partial_lens_validated_not_full_native_parity")
        XCTAssertEqual(validationSummary.blockedPromotionClaims, ["recommended", "production", "native_parity", "write_back"])
        XCTAssertEqual(validationSummary.finalDecisionBlockerClassesLabel, "external_pending, direct_blocker")
        XCTAssertEqual(
            validationSummary.finalDecisionProductBlockedIdsLabel,
            "example.sessions.create.action_contract, example.sessions.pin.native_write_back_contract"
        )
        XCTAssertEqual(validationSummary.finalDecisionExternalPendingIdsLabel, "example.channels.live_evidence")
        XCTAssertNil(validationSummary.finalDecisionUnresolvedNativeIdsLabel)
        XCTAssertEqual(
            validationSummary.finalDecisionPromotionEvidenceLabel,
            "approved_redacted_live_evidence, keep_lowered_claim_until_upstream_native_contracts_exist"
        )
        XCTAssertTrue(validationSummary.accessibilityLabel.contains("all domains accounted"))
        XCTAssertTrue(validationSummary.accessibilityLabel.contains("decision id keep_current_lowered_runtime_ecosystem_claim"))
        XCTAssertTrue(validationSummary.accessibilityLabel.contains("recommended false"))
        XCTAssertTrue(validationSummary.accessibilityLabel.contains("ui parity claim partial_template_only"))
        XCTAssertTrue(validationSummary.accessibilityLabel.contains("blocked claims recommended, production, native_parity, write_back"))
        XCTAssertTrue(validationSummary.accessibilityLabel.contains("final blocker classes external_pending, direct_blocker"))
        XCTAssertTrue(validationSummary.accessibilityLabel.contains("final promotion evidence approved_redacted_live_evidence"))
        XCTAssertEqual(snapshot.supportAudit?.finalPromotionReview?.status, "unpromoted")
        XCTAssertEqual(snapshot.supportAudit?.finalPromotionReview?.finalPromotionAllowed, false)
        XCTAssertEqual(snapshot.supportAudit?.finalPromotionReview?.claimDisposition, "unpromoted_external_pending")
        XCTAssertEqual(snapshot.supportAudit?.finalPromotionReview?.productBlockedByDecisionCount, 2)
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
        XCTAssertEqual(promotionReviewPresentation.claimDisposition, "unpromoted_external_pending")
        XCTAssertEqual(promotionReviewPresentation.productBlockedCount, 2)
        XCTAssertEqual(promotionReviewPresentation.externalPendingCount, 1)
        XCTAssertEqual(promotionReviewPresentation.unresolvedNativeRequirementCount, 0)
        XCTAssertEqual(
            promotionReviewPresentation.productBlockedIdsLabel,
            "example.sessions.create.action_contract, example.sessions.pin.native_write_back_contract"
        )
        XCTAssertEqual(promotionReviewPresentation.externalPendingIdsLabel, "example.channels.live_evidence")
        XCTAssertNil(promotionReviewPresentation.unresolvedNativeIdsLabel)
        XCTAssertEqual(
            promotionReviewPresentation.requiredForPromotionLabel,
            "approved_redacted_live_evidence, keep_lowered_claim_until_upstream_native_contracts_exist, ecosystem_production_claim, ecosystem_recommended_claim"
        )
        XCTAssertTrue(promotionReviewPresentation.accessibilityLabel.contains("Runtime final promotion review"))
        XCTAssertTrue(promotionReviewPresentation.accessibilityLabel.contains("product blocked 2"))
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
        XCTAssertEqual(finalDecisionPresentation.blockedPromotionClaimsLabel, "recommended, production, native_parity, write_back")
        XCTAssertEqual(finalDecisionPresentation.blockerClassesLabel, "external_pending, direct_blocker")
        XCTAssertEqual(
            finalDecisionPresentation.productBlockedIdsLabel,
            "example.sessions.create.action_contract, example.sessions.pin.native_write_back_contract"
        )
        XCTAssertEqual(finalDecisionPresentation.externalPendingIdsLabel, "example.channels.live_evidence")
        XCTAssertNil(finalDecisionPresentation.unresolvedNativeIdsLabel)
        XCTAssertEqual(
            finalDecisionPresentation.promotionEvidenceRequiredLabel,
            "approved_redacted_live_evidence, keep_lowered_claim_until_upstream_native_contracts_exist"
        )
        XCTAssertTrue(finalDecisionPresentation.accessibilityLabel.contains("Runtime final support claim decision"))
        XCTAssertTrue(finalDecisionPresentation.accessibilityLabel.contains("decision keep_current_lowered_runtime_ecosystem_claim"))
        XCTAssertTrue(finalDecisionPresentation.accessibilityLabel.contains("blocked claims recommended, production, native_parity, write_back"))
        XCTAssertTrue(finalDecisionPresentation.accessibilityLabel.contains("blocker classes external_pending, direct_blocker"))
        XCTAssertTrue(finalDecisionPresentation.accessibilityLabel.contains("promotion evidence approved_redacted_live_evidence"))
        XCTAssertTrue(finalDecisionPresentation.accessibilityLabel.contains("safe default keep_unpromoted_until_evidence_or_upstream_contract_changes"))
        XCTAssertEqual(snapshot.supportAudit?.evidenceReentryPackets?.first?.requirementId, "example.channels.live_evidence")
        XCTAssertEqual(snapshot.supportAudit?.evidenceReentryPackets?.first?.status, "approval_required")
        XCTAssertEqual(snapshot.supportAudit?.evidenceReentryPackets?.first?.safeDefault, "do_not_run_without_explicit_approval_and_redaction")
        XCTAssertEqual(snapshot.supportAudit?.evidenceReentryPackets?.first?.commandShape, "runtime example domain channels --json")
        XCTAssertEqual(snapshot.supportAudit?.evidenceReentryPackets?.first?.riskControls?.contains("read_only_first"), true)
        XCTAssertEqual(snapshot.supportAudit?.evidenceReentryPackets?.last?.status, "blocked_until_upstream_contract")
        XCTAssertEqual(snapshot.supportAudit?.evidenceReentryPackets?.last?.safeDefault, "keep_unpromoted_and_do_not_synthesize_runtime_state")
        let reentryPresentation = ClawJSRuntimeLensEvidenceReentryPresentation.make(
            packets: snapshot.supportAudit?.evidenceReentryPackets ?? []
        )
        XCTAssertEqual(reentryPresentation.totalLabel, "reentry 2")
        XCTAssertEqual(reentryPresentation.statusPills.map(\.label), [
            "approval_required 1",
            "blocked_until_upstream_contract 1"
        ])
        XCTAssertEqual(reentryPresentation.approvalRequiredCount, 1)
        XCTAssertEqual(reentryPresentation.rows.map(\.requirementId), [
            "example.channels.live_evidence",
            "example.sessions.create.action_contract"
        ])
        XCTAssertEqual(reentryPresentation.rows.first?.approvalRequired, true)
        XCTAssertEqual(reentryPresentation.rows.first?.expectedEvidenceCount, 2)
        XCTAssertEqual(reentryPresentation.rows.first?.expectedEvidenceLabel, "redacted_json_receipt, no_plaintext_secrets")
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
        XCTAssertTrue(reentryPresentation.rows.first?.accessibilityLabel.contains("expected evidence redacted_json_receipt") == true)
        XCTAssertTrue(reentryPresentation.rows.first?.accessibilityLabel.contains("support resolution external_pending_not_product_blocked") == true)
        XCTAssertTrue(reentryPresentation.rows.last?.accessibilityLabel.contains("product decision native_session_action_unsupported_until_official_runtime_contract") == true)
        XCTAssertTrue(reentryPresentation.accessibilityLabel.contains("approval required 1"))
        XCTAssertTrue(reentryPresentation.accessibilityLabel.contains("blocked_until_upstream_contract 1"))
        XCTAssertEqual(snapshot.commands?.authority, "runtime_adapter")
        XCTAssertEqual(snapshot.commands?.resourceDomains, ClawJSRuntimeLensSnapshot.canonicalDomains)
        XCTAssertEqual(snapshot.commands?.executableByClawCli?.first?.command, "runtime example sessions list")
        XCTAssertEqual(snapshot.commands?.executableByClawCli?.first?.args, ["sessions", "list"])
        XCTAssertEqual(snapshot.commands?.executableByClawCli?.first { $0.command.contains("inject") }?.delegatesTo, "blocked until native inject contract")
        XCTAssertEqual(snapshot.commands?.executableByClawCli?.first { $0.command.contains("inject") }?.args?.count, 7)
        XCTAssertEqual(snapshot.commands?.executableByClawCli?.first { $0.command.contains("create") }?.wouldWriteRuntime, true)
        XCTAssertEqual(snapshot.commands?.executableByClawCli?.first { $0.command.contains("create") }?.args?.last, "<title>")
        XCTAssertEqual(snapshot.commands?.mutationPolicy, "Runtime-owned actions must delegate to the runtime adapter or be marked unsupported.")
        let commandPresentation = ClawJSRuntimeLensCommandMatrixPresentation.make(
            commands: try XCTUnwrap(snapshot.commands)
        )
        XCTAssertEqual(commandPresentation.executableCount, 3)
        XCTAssertEqual(commandPresentation.writesRuntimeCount, 0)
        XCTAssertEqual(commandPresentation.wouldWriteRuntimeCount, 1)
        XCTAssertEqual(commandPresentation.readLocalCount, 2)
        XCTAssertEqual(commandPresentation.argumentCommandCount, 3)
        XCTAssertEqual(commandPresentation.argumentCount, 13)
        XCTAssertEqual(commandPresentation.resourceDomainCount, ClawJSRuntimeLensSnapshot.canonicalDomains.count)
        XCTAssertEqual(commandPresentation.resourceDomainsLabel, "sessions, skills, memory, channels, providers")
        XCTAssertEqual(commandPresentation.rows.first?.command, "runtime example sessions create --title <title>")
        XCTAssertEqual(commandPresentation.rows.first?.writeDisposition, "blocked write")
        XCTAssertEqual(commandPresentation.rows.first?.argumentCount, 4)
        XCTAssertEqual(commandPresentation.rows.first?.argsLabel, "sessions, create, --title, <title>")
        XCTAssertTrue(commandPresentation.rows.first?.accessibilityLabel.contains("blocked write") == true)
        XCTAssertTrue(commandPresentation.rows.first?.accessibilityLabel.contains("arguments 4") == true)
        XCTAssertTrue(commandPresentation.accessibilityLabel.contains("Runtime command matrix"))
        XCTAssertTrue(commandPresentation.accessibilityLabel.contains("would write runtime 1"))
        XCTAssertTrue(commandPresentation.accessibilityLabel.contains("argument commands 3"))
        XCTAssertEqual(snapshot.domains.map(\.domain), ClawJSRuntimeLensSnapshot.canonicalDomains)
        XCTAssertEqual(snapshot.missingCanonicalDomains, [])
        let missingDomainPresentation = ClawJSRuntimeLensMissingDomainPresentation.make(domains: snapshot.domains)
        XCTAssertEqual(missingDomainPresentation.coverageStatus, "all_domains_accounted")
        XCTAssertEqual(missingDomainPresentation.presentDomainCount, ClawJSRuntimeLensSnapshot.canonicalDomains.count)
        XCTAssertEqual(missingDomainPresentation.missingDomainCount, 0)
        XCTAssertFalse(missingDomainPresentation.hasMissingDomains)
        XCTAssertTrue(missingDomainPresentation.accessibilityLabel.contains("all_domains_accounted"))
        let incompleteMissingDomainPresentation = ClawJSRuntimeLensMissingDomainPresentation.make(
            domains: Array(snapshot.domains.dropLast())
        )
        XCTAssertEqual(incompleteMissingDomainPresentation.coverageStatus, "semantic_lens_incomplete")
        XCTAssertEqual(incompleteMissingDomainPresentation.missingDomainCount, 1)
        XCTAssertEqual(incompleteMissingDomainPresentation.rows.first?.domain, "configuration")
        XCTAssertEqual(incompleteMissingDomainPresentation.rows.first?.displayLabel, "Config")
        XCTAssertEqual(incompleteMissingDomainPresentation.missingDomainsLabel, "configuration")
        XCTAssertTrue(incompleteMissingDomainPresentation.accessibilityLabel.contains("missing domains configuration"))
        XCTAssertEqual(snapshot.domains.first { $0.domain == "channels" }?.count, 7)
        XCTAssertEqual(snapshot.domains.first { $0.domain == "channels" }?.claim, "inventoried")
        XCTAssertEqual(snapshot.domains.first { $0.domain == "channels" }?.writeBackPolicy, "external_pending_live_accounts")
        XCTAssertEqual(snapshot.domains.first { $0.domain == "channels" }?.externalPending, true)
        XCTAssertEqual(snapshot.domains.first { $0.domain == "channels" }?.officialCommands?.first, "example gateway")
        let domainCommandPresentation = ClawJSRuntimeLensDomainCommandPresentation.make(
            domain: "channels",
            commands: snapshot.domains.first { $0.domain == "channels" }?.officialCommands ?? [],
            limit: 2
        )
        XCTAssertEqual(domainCommandPresentation.domain, "channels")
        XCTAssertEqual(domainCommandPresentation.totalCommandCount, 3)
        XCTAssertEqual(domainCommandPresentation.visibleCommandCount, 2)
        XCTAssertEqual(domainCommandPresentation.hiddenCommandCount, 1)
        XCTAssertEqual(domainCommandPresentation.rows.first?.command, "example gateway")
        XCTAssertEqual(domainCommandPresentation.rows.first?.id, "example-gateway")
        XCTAssertTrue(domainCommandPresentation.hasCommands)
        XCTAssertTrue(domainCommandPresentation.rows.first?.accessibilityLabel.contains("runtime domain command 1") == true)
        XCTAssertTrue(domainCommandPresentation.accessibilityLabel.contains("Runtime domain commands"))
        XCTAssertEqual(snapshot.domains.first { $0.domain == "channels" }?.evidenceRequirements?.first?.blockerClass, "external_pending")
        XCTAssertEqual(snapshot.domains.first { $0.domain == "channels" }?.evidenceRequirements?.first?.commandShape, "runtime example domain channels --json")
        XCTAssertEqual(snapshot.domains.first { $0.domain == "sandboxPermissions" }?.displayLabel, "Sandbox")
        let domainPresentation = ClawJSRuntimeLensDomainPresentation.make(domains: snapshot.domains)
        XCTAssertEqual(domainPresentation.domainCount, ClawJSRuntimeLensSnapshot.canonicalDomains.count)
        XCTAssertEqual(domainPresentation.unsupportedCount, 0)
        XCTAssertEqual(domainPresentation.externalPendingCount, 1)
        XCTAssertEqual(domainPresentation.evidenceRequirementCount, 1)
        XCTAssertEqual(domainPresentation.nativeCommandDomainCount, 1)
        XCTAssertEqual(domainPresentation.limitationDomainCount, 1)
        XCTAssertEqual(domainPresentation.limitationCount, 1)
        XCTAssertEqual(domainPresentation.policyDomainCount, 2)
        XCTAssertEqual(domainPresentation.writeBackAllowedCount, 0)
        XCTAssertEqual(domainPresentation.provenanceDomainCount, 2)
        XCTAssertEqual(domainPresentation.strategyLabel, "cli 1, gateway 1, hosted 1, native 10")
        XCTAssertEqual(domainPresentation.persistenceLabel, "index_and_shadow_when_safe 1, secret_refs_only 1")
        XCTAssertEqual(domainPresentation.validationLabel, "external_pending_for_live_accounts 1, fixture_required 1")
        XCTAssertEqual(domainPresentation.provenanceSourceLabel, "runtime-ecosystem-manifest 2")
        XCTAssertTrue(domainPresentation.statusLabel?.contains("error 1") == true)
        XCTAssertEqual(domainPresentation.externalPendingDomainsLabel, "channels")
        XCTAssertEqual(domainPresentation.limitationDomainsLabel, "channels")
        let channelPresentation = try XCTUnwrap(domainPresentation.rows.first { $0.domain == "channels" })
        XCTAssertEqual(channelPresentation.displayLabel, "Channels")
        XCTAssertEqual(channelPresentation.status, "degraded")
        XCTAssertEqual(channelPresentation.strategy, "native")
        XCTAssertEqual(channelPresentation.claim, "inventoried")
        XCTAssertEqual(channelPresentation.count, 7)
        XCTAssertEqual(channelPresentation.nativeAuthority, "runtime")
        XCTAssertEqual(channelPresentation.persistence, "secret_refs_only")
        XCTAssertEqual(channelPresentation.relation, "gateway_projection")
        XCTAssertEqual(channelPresentation.lossPolicy, "secret_refs_only")
        XCTAssertEqual(channelPresentation.writeBackPolicy, "external_pending_live_accounts")
        XCTAssertEqual(channelPresentation.writeBackAllowed, false)
        XCTAssertEqual(channelPresentation.validation, "external_pending_for_live_accounts")
        XCTAssertEqual(channelPresentation.provenanceSource, "runtime-ecosystem-manifest")
        XCTAssertEqual(channelPresentation.provenanceRuntimeId, "example")
        XCTAssertEqual(channelPresentation.provenanceDomain, "channels")
        XCTAssertEqual(
            channelPresentation.policyLabel,
            "native runtime, persistence secret_refs_only, relation gateway_projection, loss secret_refs_only, validation external_pending_for_live_accounts, no runtime write-back"
        )
        XCTAssertEqual(
            channelPresentation.provenanceLabel,
            "runtime-ecosystem-manifest, runtime example, domain channels"
        )
        XCTAssertEqual(channelPresentation.commandCount, 3)
        XCTAssertEqual(channelPresentation.evidenceRequirementCount, 1)
        XCTAssertEqual(channelPresentation.limitationCount, 1)
        XCTAssertEqual(channelPresentation.limitationsLabel, "normalized")
        XCTAssertTrue(channelPresentation.accessibilityLabel.contains("external pending true"))
        XCTAssertTrue(channelPresentation.accessibilityLabel.contains("strategy native"))
        XCTAssertTrue(channelPresentation.accessibilityLabel.contains("native authority runtime"))
        XCTAssertTrue(channelPresentation.accessibilityLabel.contains("persistence secret_refs_only"))
        XCTAssertTrue(channelPresentation.accessibilityLabel.contains("write back allowed false"))
        XCTAssertTrue(channelPresentation.accessibilityLabel.contains("validation external_pending_for_live_accounts"))
        XCTAssertTrue(channelPresentation.accessibilityLabel.contains("limitations normalized"))
        XCTAssertTrue(channelPresentation.accessibilityLabel.contains("provenance source runtime-ecosystem-manifest"))
        XCTAssertTrue(channelPresentation.accessibilityLabel.contains("provenance runtime example"))
        XCTAssertTrue(channelPresentation.accessibilityLabel.contains("provenance domain channels"))
        XCTAssertTrue(domainPresentation.accessibilityLabel.contains("strategies cli 1, gateway 1, hosted 1, native 10"))
        XCTAssertTrue(domainPresentation.accessibilityLabel.contains("policy domains 2"))
        XCTAssertTrue(domainPresentation.accessibilityLabel.contains("provenance domains 2"))
        XCTAssertTrue(domainPresentation.accessibilityLabel.contains("persistence index_and_shadow_when_safe 1, secret_refs_only 1"))
        XCTAssertTrue(domainPresentation.accessibilityLabel.contains("validation external_pending_for_live_accounts 1, fixture_required 1"))
        XCTAssertTrue(domainPresentation.accessibilityLabel.contains("provenance sources runtime-ecosystem-manifest 2"))
        XCTAssertTrue(domainPresentation.accessibilityLabel.contains("limitation domains channels"))
        let domainEvidencePresentation = ClawJSRuntimeLensEvidenceRequirementPresentation.make(
            requirements: channelPresentation.evidenceRequirements,
            limit: 2
        )
        XCTAssertEqual(domainEvidencePresentation.totalRequirementCount, 1)
        XCTAssertEqual(domainEvidencePresentation.externalPendingCount, 1)
        XCTAssertEqual(domainEvidencePresentation.rows.first?.commandShape, "runtime example domain channels --json")
        XCTAssertTrue(domainEvidencePresentation.rows.first?.accessibilityLabel.contains("evidence requirement example.channels.live_evidence") == true)
        XCTAssertTrue(domainEvidencePresentation.accessibilityLabel.contains("Runtime evidence requirements"))
        XCTAssertTrue(domainPresentation.accessibilityLabel.contains("Runtime domains"))
        XCTAssertEqual(snapshot.domainData?.sessions?.session?.primaryTransport, "gateway")
        XCTAssertEqual(snapshot.domainData?.sessions?.session?.sessionPath, "/Users/tester/.example/sessions")
        let sessionDescriptorPresentation = ClawJSRuntimeLensSessionDescriptorPresentation.make(
            session: try XCTUnwrap(snapshot.domainData?.sessions?.session)
        )
        XCTAssertEqual(sessionDescriptorPresentation.primaryTransport, "gateway")
        XCTAssertEqual(sessionDescriptorPresentation.transportKind, "cli")
        XCTAssertEqual(sessionDescriptorPresentation.streaming, true)
        XCTAssertEqual(sessionDescriptorPresentation.streamingLabel, "hybrid")
        XCTAssertEqual(sessionDescriptorPresentation.persistence, "runtime")
        XCTAssertEqual(sessionDescriptorPresentation.fallbackTransport, "cli")
        XCTAssertEqual(sessionDescriptorPresentation.sessionPath, "/Users/tester/.example/sessions")
        XCTAssertEqual(sessionDescriptorPresentation.transportPills, ["gateway", "hybrid", "runtime"])
        XCTAssertTrue(sessionDescriptorPresentation.hasFallback)
        XCTAssertTrue(sessionDescriptorPresentation.hasPath)
        XCTAssertTrue(sessionDescriptorPresentation.accessibilityLabel.contains("Runtime session descriptor"))
        XCTAssertTrue(sessionDescriptorPresentation.accessibilityLabel.contains("fallback cli"))
        XCTAssertEqual(snapshot.domainData?.sessions?.sessions?.first?.id, "2026/05/21/runtime-session")
        XCTAssertEqual(snapshot.domainData?.sessions?.totalProjected, 1)
        XCTAssertEqual(snapshot.domainData?.sessions?.inventoryError, "OpenClaw unavailable in fixture")
        let sessionInventoryPresentation = ClawJSRuntimeLensSessionInventoryPresentation.make(
            bucket: try XCTUnwrap(snapshot.domainData?.sessions)
        )
        XCTAssertEqual(sessionInventoryPresentation.projectedCount, 1)
        XCTAssertEqual(sessionInventoryPresentation.visibleCount, 1)
        XCTAssertEqual(sessionInventoryPresentation.statusLabel, "degraded")
        XCTAssertEqual(sessionInventoryPresentation.detailLabel, "OpenClaw unavailable in fixture")
        XCTAssertTrue(sessionInventoryPresentation.accessibilityLabel.contains("Runtime session inventory"))
        XCTAssertTrue(sessionInventoryPresentation.accessibilityLabel.contains("inventory error true"))
        XCTAssertEqual(snapshot.domainData?.sessions?.overlayState?.writesRuntime, false)
        XCTAssertEqual(snapshot.domainData?.sessions?.overlayState?.writeBackStatus, "blocked_until_official_runtime_pin_api")
        XCTAssertEqual(snapshot.domainData?.sessions?.overlayState?.conflictPolicy, "no_silent_overwrite")
        XCTAssertEqual(snapshot.domainData?.sessions?.overlayState?.totalConflicts, 1)
        XCTAssertEqual(snapshot.domainData?.sessions?.overlayState?.overlays?.first?.sessionId, "2026/05/21/runtime-session")
        XCTAssertEqual(snapshot.domainData?.sessions?.overlayState?.overlays?.first?.conflictStatus, "local_only")
        XCTAssertEqual(snapshot.domainData?.sessions?.overlayState?.overlays?.first?.writesRuntime, false)
        let overlayPresentation = ClawJSRuntimeLensSessionOverlayPresentation.make(
            state: try XCTUnwrap(snapshot.domainData?.sessions?.overlayState)
        )
        XCTAssertEqual(overlayPresentation.runtimeId, "example")
        XCTAssertEqual(overlayPresentation.overlayAuthority, "clawix_local_overlay")
        XCTAssertEqual(overlayPresentation.writesRuntime, false)
        XCTAssertEqual(overlayPresentation.writeBackStatus, "blocked_until_official_runtime_pin_api")
        XCTAssertEqual(overlayPresentation.conflictPolicy, "no_silent_overwrite")
        XCTAssertEqual(overlayPresentation.totalOverlays, 1)
        XCTAssertEqual(overlayPresentation.totalConflicts, 1)
        XCTAssertEqual(overlayPresentation.detailLabel, "clawix_local_overlay, no_silent_overwrite, blocked_until_official_runtime_pin_api")
        XCTAssertEqual(overlayPresentation.conflictStatusLabel, "local_only 1")
        XCTAssertEqual(overlayPresentation.rows.first?.sessionLabel, "2026/05/21/runtime-session")
        XCTAssertTrue(overlayPresentation.rows.first?.accessibilityLabel.contains("writes runtime false") == true)
        XCTAssertTrue(overlayPresentation.accessibilityLabel.contains("Runtime session overlays"))
        XCTAssertTrue(overlayPresentation.accessibilityLabel.contains("conflict policy no_silent_overwrite"))
        XCTAssertEqual(snapshot.resources(for: "sessions").first?.updatedAt, "2026-05-21T17:40:00.000Z")
        XCTAssertEqual(snapshot.resources(for: "sessions").first?.pinned, true)
        let inventoryPresentation = ClawJSRuntimeLensInventoryPresentation.make(snapshot: snapshot)
        XCTAssertEqual(inventoryPresentation.sectionCount, 11)
        XCTAssertEqual(inventoryPresentation.totalResourceCount, 17)
        XCTAssertEqual(inventoryPresentation.visibleResourceCount, 17)
        XCTAssertEqual(inventoryPresentation.pinnedResourceCount, 1)
        XCTAssertEqual(inventoryPresentation.pathResourceCount, 5)
        XCTAssertEqual(inventoryPresentation.updatedResourceCount, 1)
        XCTAssertEqual(inventoryPresentation.kindResourceCount, 14)
        XCTAssertEqual(inventoryPresentation.summaryResourceCount, 3)
        XCTAssertEqual(inventoryPresentation.enabledResourceCount, 7)
        XCTAssertEqual(inventoryPresentation.sizedResourceCount, 1)
        XCTAssertEqual(inventoryPresentation.nativeIdentifierResourceCount, 1)
        XCTAssertEqual(inventoryPresentation.provenanceResourceCount, 1)
        XCTAssertEqual(inventoryPresentation.limitationResourceCount, 3)
        XCTAssertEqual(inventoryPresentation.limitationCount, 3)
        XCTAssertEqual(inventoryPresentation.attributeResourceCount, 10)
        XCTAssertEqual(inventoryPresentation.attributeCount, 36)
        XCTAssertEqual(inventoryPresentation.domainLabel, "sessions, skills, channels, providers, auth, models")
        XCTAssertTrue(inventoryPresentation.hasInventory)
        XCTAssertTrue(inventoryPresentation.accessibilityLabel.contains("Runtime inventory"))
        XCTAssertTrue(inventoryPresentation.accessibilityLabel.contains("limitation resources 3"))
        XCTAssertTrue(inventoryPresentation.accessibilityLabel.contains("attribute resources 10"))
        let sessionInventory = try XCTUnwrap(inventoryPresentation.sections.first { $0.domain == "sessions" })
        XCTAssertEqual(sessionInventory.totalResourceCount, 1)
        XCTAssertEqual(sessionInventory.pinnedCount, 1)
        XCTAssertEqual(sessionInventory.pathCount, 1)
        XCTAssertEqual(sessionInventory.updatedCount, 1)
        XCTAssertEqual(sessionInventory.statusLabel, "projected 1")
        XCTAssertEqual(sessionInventory.rows.first?.displayLabel, "runtime-session")
        XCTAssertEqual(sessionInventory.rows.first?.statusLabel, "projected")
        XCTAssertEqual(sessionInventory.rows.first?.pinned, true)
        XCTAssertEqual(sessionInventory.rows.first?.kindLabel, "kind: session")
        XCTAssertEqual(sessionInventory.rows.first?.sizeLabel, "128 B")
        XCTAssertEqual(sessionInventory.rows.first?.nativeIdentifierLabel, "native id: sessionPathId")
        XCTAssertEqual(
            sessionInventory.rows.first?.provenanceLabel,
            "runtime-session-store, runtime example, /Users/tester/.example/sessions/2026/05/21/runtime-session.jsonl"
        )
        XCTAssertTrue(sessionInventory.accessibilityLabel.contains("runtime inventory domain sessions"))
        XCTAssertTrue(sessionInventory.rows.first?.accessibilityLabel.contains("runtime inventory resource 2026/05/21/runtime-session") == true)
        XCTAssertTrue(sessionInventory.rows.first?.accessibilityLabel.contains("kind session") == true)
        XCTAssertTrue(sessionInventory.rows.first?.accessibilityLabel.contains("size bytes 128") == true)
        XCTAssertTrue(sessionInventory.rows.first?.accessibilityLabel.contains("native identifier sessionPathId") == true)
        XCTAssertTrue(sessionInventory.rows.first?.accessibilityLabel.contains("provenance source runtime-session-store") == true)
        XCTAssertEqual(
            sessionInventory.rows.first?.attributesLabel,
            "pin authority: clawix_local_overlay, divergence: local_pin_overlay, overlay authority: clawix_local_overlay, overlay writes runtime: false"
        )
        let skillInventory = try XCTUnwrap(inventoryPresentation.sections.first { $0.domain == "skills" })
        XCTAssertEqual(skillInventory.rows.first?.attributesLabel, "scope: runtime")
        let sessionResource = try XCTUnwrap(sessionInventory.rows.first?.resource)
        let sessionOverlayActionKey = ClawJSRuntimeLensSessionOverlayActionPresentation.actionKey(
            runtimeId: snapshot.runtimeId,
            sessionId: sessionResource.id
        )
        let sessionOverlayActionPresentation = ClawJSRuntimeLensSessionOverlayActionPresentation.make(
            snapshot: snapshot,
            resource: sessionResource,
            inFlightKeys: [sessionOverlayActionKey]
        )
        XCTAssertEqual(sessionOverlayActionPresentation.action, "unpin")
        XCTAssertEqual(sessionOverlayActionPresentation.buttonTitle, "Unpin")
        XCTAssertEqual(sessionOverlayActionPresentation.systemImage, "pin.slash")
        XCTAssertEqual(sessionOverlayActionPresentation.currentPinned, true)
        XCTAssertEqual(sessionOverlayActionPresentation.targetPinned, false)
        XCTAssertEqual(sessionOverlayActionPresentation.actionKey, sessionOverlayActionKey)
        XCTAssertEqual(sessionOverlayActionPresentation.authority, "clawix_local_overlay")
        XCTAssertEqual(sessionOverlayActionPresentation.writesRuntime, false)
        XCTAssertTrue(sessionOverlayActionPresentation.inFlight)
        XCTAssertTrue(sessionOverlayActionPresentation.disabled)
        XCTAssertTrue(
            sessionOverlayActionPresentation.accessibilityIdentifier.contains(
                "runtime-lens-session-overlay-action-example-2026-05-21-runtime-session"
            )
        )
        XCTAssertTrue(sessionOverlayActionPresentation.accessibilityLabel.contains("runtime session overlay action unpin"))
        XCTAssertTrue(sessionOverlayActionPresentation.accessibilityLabel.contains("writes runtime false"))
        let channelInventory = try XCTUnwrap(inventoryPresentation.sections.first { $0.domain == "channels" })
        XCTAssertEqual(channelInventory.totalResourceCount, 2)
        XCTAssertEqual(channelInventory.statusLabel, "configured 1, disconnected 1")
        XCTAssertTrue(channelInventory.accessibilityLabel.contains("runtime inventory domain channels"))
        XCTAssertEqual(
            channelInventory.rows.first { $0.id == "telegram" }?.attributesLabel,
            "provider: telegram, last error: channel disabled in fixture, metadata keys: knownChats, mode"
        )
        let providerInventory = try XCTUnwrap(inventoryPresentation.sections.first { $0.domain == "providers" })
        XCTAssertEqual(
            providerInventory.rows.first { $0.id == "openai" }?.attributesLabel,
            "api key auth: true, env auth: true, env vars: OPENAI_API_KEY"
        )
        let authInventory = try XCTUnwrap(inventoryPresentation.sections.first { $0.domain == "auth" })
        XCTAssertEqual(authInventory.statusLabel, "configured 1, missing 1")
        XCTAssertEqual(
            authInventory.rows.first { $0.id == "openai" }?.attributesLabel,
            "subscription: false, api key: true, profile key: false, env key: true"
        )
        XCTAssertEqual(authInventory.rows.first { $0.id == "openai" }?.attributeCount, 4)
        XCTAssertTrue(
            authInventory.rows.first { $0.id == "openai" }?.accessibilityLabel.contains(
                "attributes subscription: false, api key: true, profile key: false, env key: true"
            ) == true
        )
        XCTAssertEqual(
            authInventory.rows.first { $0.id == "anthropic" }?.attributesLabel,
            "subscription: false, api key: false, profile key: false, env key: false"
        )
        let modelInventory = try XCTUnwrap(inventoryPresentation.sections.first { $0.domain == "models" })
        XCTAssertEqual(modelInventory.totalResourceCount, 2)
        XCTAssertEqual(modelInventory.statusLabel, "default 1")
        XCTAssertEqual(modelInventory.rows.first { $0.id == "claude-3-haiku" }?.attributesLabel, "provider: anthropic, model id: claude-3-haiku, source: runtime, available: true")
        XCTAssertEqual(modelInventory.rows.first { $0.id == "claude-3-haiku" }?.attributeCount, 5)
        XCTAssertTrue(modelInventory.rows.first { $0.id == "claude-3-haiku" }?.accessibilityLabel.contains("attributes provider: anthropic, model id: claude-3-haiku, source: runtime, available: true") == true)
        XCTAssertEqual(modelInventory.rows.first { $0.id == "default-model" }?.displayLabel, "Claude Opus")
        XCTAssertEqual(modelInventory.rows.first { $0.id == "default-model" }?.kindLabel, "kind: default_model")
        XCTAssertEqual(modelInventory.rows.first { $0.id == "default-model" }?.attributesLabel, "provider: anthropic, model id: claude-3-opus, default: true")
        let pluginInventory = try XCTUnwrap(inventoryPresentation.sections.first { $0.domain == "plugins" })
        XCTAssertEqual(pluginInventory.totalResourceCount, 1)
        XCTAssertEqual(pluginInventory.statusLabel, "unsupported 1")
        XCTAssertEqual(pluginInventory.rows.first?.displayLabel, "Plugin status")
        XCTAssertEqual(pluginInventory.rows.first?.kindLabel, "kind: unsupported")
        XCTAssertEqual(pluginInventory.rows.first?.enabledLabel, "enabled: false")
        XCTAssertEqual(pluginInventory.rows.first?.limitationsLabel, "plugins unavailable in fixture")
        XCTAssertEqual(
            pluginInventory.rows.first?.attributesLabel,
            "supported: false, strategy: unsupported, diagnostic mode: managed, diagnostics: plugin CLI not available in fixture"
        )
        let gatewayInventory = try XCTUnwrap(inventoryPresentation.sections.first { $0.domain == "gateway" })
        XCTAssertEqual(gatewayInventory.rows.first?.limitationsLabel, "gateway unavailable in fixture")
        XCTAssertEqual(
            gatewayInventory.rows.first?.attributesLabel,
            "diagnostic source: runtime, probe: gateway, transport: gateway, inventory freshness: degraded_snapshot"
        )
        XCTAssertTrue(gatewayInventory.rows.first?.accessibilityLabel.contains("limitations gateway unavailable in fixture") == true)
        let sandboxInventory = try XCTUnwrap(inventoryPresentation.sections.first { $0.domain == "sandboxPermissions" })
        XCTAssertEqual(sandboxInventory.rows.first?.limitationsLabel, "host permission review required")
        let configurationInventory = try XCTUnwrap(inventoryPresentation.sections.first { $0.domain == "configuration" })
        XCTAssertEqual(configurationInventory.totalResourceCount, 4)
        XCTAssertEqual(configurationInventory.pathCount, 3)
        XCTAssertEqual(configurationInventory.summaryCount, 1)
        XCTAssertEqual(configurationInventory.statusLabel, "degraded 1, managed 1, projected 2")
        XCTAssertEqual(configurationInventory.rows.map(\.id), ["SOUL", "USER", "managed-file-1", "configuration-diagnostics"])
        XCTAssertEqual(configurationInventory.rows.first { $0.id == "managed-file-1" }?.kindLabel, "kind: managed_file")
        XCTAssertEqual(configurationInventory.rows.first { $0.id == "managed-file-1" }?.path, "/tmp/workspace/AGENTS.md")
        XCTAssertEqual(configurationInventory.rows.first { $0.id == "configuration-diagnostics" }?.statusLabel, "degraded")
        XCTAssertEqual(configurationInventory.rows.first { $0.id == "configuration-diagnostics" }?.summaryLabel, "config drift in fixture")
        XCTAssertTrue(configurationInventory.rows.first { $0.id == "configuration-diagnostics" }?.accessibilityLabel.contains("summary config drift in fixture") == true)
        XCTAssertEqual(authInventory.rows.first?.displayLabel, "anthropic")
        XCTAssertEqual(authInventory.rows.first?.kindLabel, "kind: auth")
        XCTAssertEqual(authInventory.rows.first?.enabledLabel, "enabled: false")
        XCTAssertEqual(authInventory.rows.first { $0.id == "openai" }?.summaryLabel, "****1234")
        XCTAssertEqual(snapshot.domainData?.sessions?.actionPolicy?.first?.action, "list")
        XCTAssertEqual(snapshot.domainData?.sessions?.actionPolicy?.first?.guardName, "bounded_scan_without_transcript_reads")
        XCTAssertEqual(snapshot.domainData?.sessions?.actionPolicy?.first { $0.action == "pin" }?.authority, "clawix_local_overlay")
        XCTAssertEqual(snapshot.domainData?.sessions?.actionPolicy?.first { $0.action == "pin" }?.writesRuntime, false)
        XCTAssertEqual(snapshot.domainData?.sessions?.actionPolicy?.first { $0.action == "create" }?.wouldWriteRuntime, true)
        XCTAssertEqual(snapshot.domainData?.sessions?.actionPolicy?.first { $0.action == "create" }?.requiredEvidence?.first, "official_create_command_or_api")
        XCTAssertEqual(snapshot.domainData?.sessions?.actionContracts?.map(\.action), ["list", "pin", "create"])
        XCTAssertEqual(snapshot.domainData?.sessions?.actionContracts?.first { $0.action == "list" }?.status, "degraded")
        XCTAssertEqual(snapshot.domainData?.sessions?.actionContracts?.first { $0.action == "create" }?.requiredEvidence?.count, 3)
        let sessionActionContractPresentation = ClawJSRuntimeLensSessionActionContractPresentation.make(
            contracts: try XCTUnwrap(snapshot.domainData?.sessions?.actionContracts),
            materializedPolicy: try XCTUnwrap(snapshot.domainData?.sessions?.actionPolicy)
        )
        XCTAssertEqual(sessionActionContractPresentation.contractCount, 3)
        XCTAssertEqual(sessionActionContractPresentation.materializedCount, 3)
        XCTAssertEqual(sessionActionContractPresentation.statusChangedCount, 1)
        XCTAssertEqual(sessionActionContractPresentation.contractOnlyCount, 0)
        XCTAssertEqual(sessionActionContractPresentation.materializedOnlyCount, 0)
        XCTAssertEqual(sessionActionContractPresentation.runtimeWriteContractCount, 0)
        XCTAssertEqual(sessionActionContractPresentation.wouldWriteRuntimeCount, 1)
        XCTAssertEqual(sessionActionContractPresentation.localOverlayContractCount, 1)
        XCTAssertEqual(sessionActionContractPresentation.requiredEvidenceCount, 3)
        XCTAssertEqual(sessionActionContractPresentation.statusChangedActionsLabel, "list")
        XCTAssertEqual(sessionActionContractPresentation.rows.first { $0.action == "list" }?.contractStatus, "degraded")
        XCTAssertEqual(sessionActionContractPresentation.rows.first { $0.action == "list" }?.materializedStatus, "implemented")
        XCTAssertTrue(sessionActionContractPresentation.rows.first { $0.action == "list" }?.statusChanged == true)
        XCTAssertEqual(sessionActionContractPresentation.rows.first { $0.action == "create" }?.contractWriteDisposition, "would write")
        XCTAssertTrue(sessionActionContractPresentation.accessibilityLabel.contains("Runtime session action contracts"))
        XCTAssertTrue(sessionActionContractPresentation.accessibilityLabel.contains("changed actions list"))
        let sessionActionPresentation = ClawJSRuntimeLensSessionActionPresentation.make(
            actions: try XCTUnwrap(snapshot.domainData?.sessions?.actionPolicy)
        )
        XCTAssertEqual(sessionActionPresentation.actionCount, 3)
        XCTAssertEqual(sessionActionPresentation.implementedCount, 1)
        XCTAssertEqual(sessionActionPresentation.blockedCount, 1)
        XCTAssertEqual(sessionActionPresentation.localOverlayCount, 1)
        XCTAssertEqual(sessionActionPresentation.noWriteCount, 3)
        XCTAssertEqual(sessionActionPresentation.wouldWriteRuntimeCount, 1)
        XCTAssertEqual(sessionActionPresentation.requiredEvidenceCount, 2)
        XCTAssertEqual(sessionActionPresentation.statusLabel, "blocked 1, implemented 1, local_overlay_only 1")
        XCTAssertEqual(sessionActionPresentation.localOverlayActionsLabel, "pin")
        XCTAssertEqual(sessionActionPresentation.blockedActionsLabel, "create")
        XCTAssertEqual(sessionActionPresentation.rows.first?.detailLabel, "runtime, metadata_only, bounded_scan_without_transcript_reads")
        XCTAssertEqual(sessionActionPresentation.rows.first { $0.action == "create" }?.writeDisposition, "would write")
        XCTAssertEqual(sessionActionPresentation.rows.first { $0.action == "create" }?.requiredEvidenceCount, 2)
        XCTAssertEqual(
            sessionActionPresentation.rows.first { $0.action == "create" }?.requiredEvidenceLabel,
            "official_create_command_or_api, non_destructive_fixture"
        )
        XCTAssertTrue(sessionActionPresentation.rows.first { $0.action == "create" }?.accessibilityLabel.contains("required evidence count 2") == true)
        XCTAssertTrue(sessionActionPresentation.rows.first { $0.action == "create" }?.accessibilityLabel.contains("required evidence official_create_command_or_api, non_destructive_fixture") == true)
        XCTAssertTrue(sessionActionPresentation.accessibilityLabel.contains("Runtime session actions"))
        XCTAssertTrue(sessionActionPresentation.accessibilityLabel.contains("local overlay actions pin"))
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
