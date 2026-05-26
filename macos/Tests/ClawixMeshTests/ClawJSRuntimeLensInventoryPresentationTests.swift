import XCTest
@testable import Clawix

final class ClawJSRuntimeLensInventoryPresentationTests: XCTestCase {
    func testRuntimeResourceAliasDecodesAndMergesAttributes() throws {
        let data = Data("""
        {
          "id": "resource-1",
          "label": "Resource One",
          "status": "configured",
          "kind": "provider",
          "attributes": ["existing"],
          "metadata": {
            "string": "value",
            "object": { "nested": true },
            "array": ["one", "two"]
          },
          "auth": {
            "supportsOAuth": true,
            "supportsApiKey": false,
            "supportsEnv": true,
            "supportsToken": false
          }
        }
        """.utf8)
        let resource = try JSONDecoder().decode(ClawJSRuntimeLensSnapshot.RuntimeResource.self, from: data)
        let merged = resource.addingAttributes(["extra"])

        XCTAssertEqual(resource.id, "resource-1")
        XCTAssertEqual(resource.displayLabel, "Resource One")
        XCTAssertEqual(resource.providerAuth?.supportsOAuth, true)
        XCTAssertEqual(resource.providerAuth?.supportsApiKey, false)
        XCTAssertEqual(resource.metadata?.keys.sorted(), ["array", "object", "string"])
        XCTAssertEqual(merged.attributes, ["existing", "extra"])
    }

    func testRuntimeLensSessionAndInventoryPresentations() async throws {
        let snapshot = try await ClawJSRuntimeLensTestFixtures.degradedRuntimePortalSnapshot()

        XCTAssertEqual(snapshot.domainData?.sessions?.session?.primaryTransport, "gateway")
        XCTAssertEqual(snapshot.domainData?.sessions?.session?.sessionPath, "/Users/tester/.example/sessions")
        XCTAssertEqual(snapshot.domainData?.sessions?.session?.sessionStorageContract, "sqlite_with_gateway_transcripts")
        XCTAssertEqual(snapshot.domainData?.sessions?.session?.sessionDatabasePath, "/Users/tester/.example/state.db")
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
        XCTAssertEqual(sessionDescriptorPresentation.sessionStorageContract, "sqlite_with_gateway_transcripts")
        XCTAssertEqual(sessionDescriptorPresentation.sessionDatabasePath, "/Users/tester/.example/state.db")
        XCTAssertEqual(sessionDescriptorPresentation.sessionTranscriptPath, "/Users/tester/.example/sessions")
        XCTAssertEqual(sessionDescriptorPresentation.sessionIndexPath, "/Users/tester/.example/sessions/sessions.json")
        XCTAssertEqual(sessionDescriptorPresentation.storageDetailLines, [
            "storage: sqlite_with_gateway_transcripts",
            "database: /Users/tester/.example/state.db",
            "transcripts: /Users/tester/.example/sessions",
            "index: /Users/tester/.example/sessions/sessions.json"
        ])
        XCTAssertEqual(sessionDescriptorPresentation.transportPills, ["gateway", "hybrid", "runtime"])
        XCTAssertTrue(sessionDescriptorPresentation.hasFallback)
        XCTAssertTrue(sessionDescriptorPresentation.hasPath)
        XCTAssertTrue(sessionDescriptorPresentation.accessibilityLabel.contains("Runtime session descriptor"))
        XCTAssertTrue(sessionDescriptorPresentation.accessibilityLabel.contains("storage contract sqlite_with_gateway_transcripts"))
        XCTAssertTrue(sessionDescriptorPresentation.accessibilityLabel.contains("database /Users/tester/.example/state.db"))
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
        XCTAssertEqual(overlayPresentation.detailLines, [
            "authority clawix_local_overlay",
            "conflict policy no_silent_overwrite",
            "write back blocked_until_official_runtime_pin_api",
            "writes runtime false"
        ])
        XCTAssertEqual(overlayPresentation.conflictStatusLabel, "local_only 1")
        XCTAssertEqual(overlayPresentation.rows.first?.sessionLabel, "2026/05/21/runtime-session")
        XCTAssertEqual(overlayPresentation.rows.first?.detailLines, [
            "authority clawix_local_overlay",
            "writes runtime false",
            "local pinned true",
            "native found true",
            "native pinned false"
        ])
        XCTAssertTrue(overlayPresentation.rows.first?.accessibilityLabel.contains("writes runtime false") == true)
        XCTAssertTrue(overlayPresentation.rows.first?.accessibilityLabel.contains("native pinned false") == true)
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
    }

    func testHermesRuntimePortalFixtureFeedsInventoryAndSupportPresentations() async throws {
        let snapshot = try await ClawJSRuntimeLensTestFixtures.hermesRuntimePortalSnapshot()
        XCTAssertEqual(snapshot.domainData?.sessions?.session?.sessionStorageContract, "sqlite_with_gateway_transcripts")
        XCTAssertEqual(snapshot.domainData?.sessions?.session?.sessionDatabasePath, "/Users/tester/.hermes/state.db")

        let domainPresentation = ClawJSRuntimeLensDomainPresentation.make(domains: snapshot.domains)
        XCTAssertEqual(domainPresentation.domainCount, ClawJSRuntimeLensSnapshot.canonicalDomains.count)
        XCTAssertEqual(domainPresentation.rows.map(\.domain), ClawJSRuntimeLensSnapshot.canonicalDomains)
        XCTAssertTrue(domainPresentation.accessibilityLabel.contains("Runtime domains"))

        let supportContracts = ClawJSRuntimeLensSupportContractPresentation.make(snapshot: snapshot)
        XCTAssertEqual(supportContracts.contractDomainCount, ClawJSRuntimeLensSnapshot.canonicalDomains.count)
        XCTAssertEqual(supportContracts.rows.map(\.domain), ClawJSRuntimeLensSnapshot.canonicalDomains)
        XCTAssertEqual(supportContracts.writeBackAllowedCount, 0)
        XCTAssertEqual(supportContracts.blockedWriteBackCount, 10)
        XCTAssertEqual(supportContracts.externalPendingCount, 4)
        XCTAssertEqual(supportContracts.evidenceRequirementCount, 16)
        XCTAssertEqual(supportContracts.nativeCommandDomainCount, ClawJSRuntimeLensSnapshot.canonicalDomains.count)
        XCTAssertEqual(supportContracts.contractAuthorityDomainCount, ClawJSRuntimeLensSnapshot.canonicalDomains.count)
        XCTAssertEqual(supportContracts.provenanceDomainCount, ClawJSRuntimeLensSnapshot.canonicalDomains.count)
        XCTAssertEqual(supportContracts.rows.first { $0.domain == "channels" }?.externalPending, true)
        XCTAssertEqual(supportContracts.rows.first { $0.domain == "doctorCompat" }?.writeBackAllowed, false)
        XCTAssertTrue(supportContracts.rows.allSatisfy { $0.provenanceRuntimeId == "hermes" })
        XCTAssertTrue(supportContracts.accessibilityLabel.contains("Runtime support contracts"))

        let inventory = ClawJSRuntimeLensInventoryPresentation.make(snapshot: snapshot, rowLimit: 40)
        XCTAssertEqual(inventory.sectionCount, ClawJSRuntimeLensSnapshot.canonicalDomains.count)
        XCTAssertEqual(inventory.sections.map(\.domain), ClawJSRuntimeLensSnapshot.canonicalDomains)
        XCTAssertGreaterThanOrEqual(inventory.totalResourceCount, 70)
        XCTAssertTrue(inventory.accessibilityLabel.contains("Runtime inventory"))

        let missingInventoryDomains = ClawJSRuntimeLensSnapshot.canonicalDomains.filter { domain in
            !inventory.sections.contains { $0.domain == domain }
        }
        XCTAssertEqual(missingInventoryDomains, [])

        let sessionInventory = try XCTUnwrap(inventory.sections.first { $0.domain == "sessions" })
        XCTAssertEqual(sessionInventory.totalResourceCount, 1)
        XCTAssertEqual(sessionInventory.rows.first?.id, "hermes-sqlite-session")
        XCTAssertEqual(sessionInventory.rows.first?.displayLabel, "SQLite Session")
        XCTAssertEqual(sessionInventory.rows.first?.nativeIdentifierLabel, "native id: sessionId")
        XCTAssertEqual(
            sessionInventory.rows.first?.provenanceLabel,
            "runtime-session-sqlite, runtime hermes, /Users/tester/.hermes/state.db"
        )
        XCTAssertEqual(sessionInventory.rows.first?.path, "/Users/tester/.hermes/state.db")
        XCTAssertEqual(sessionInventory.rows.first?.enabledLabel, "enabled: true")
        XCTAssertTrue(sessionInventory.rows.first?.summaryLabel?.contains("content is not included by default") == true)
        XCTAssertEqual(sessionInventory.rows.first?.limitationsLabel, "write back: blocked_until_official_runtime_write_back_contract_fixture_and_round_trip_evidence, validation: fixture_required")
        XCTAssertEqual(sessionInventory.rows.first?.pinned, false)
        XCTAssertEqual(sessionInventory.rows.first?.attributeCount, 18)
        XCTAssertTrue(sessionInventory.rows.first?.attributes.contains("pin authority: none") == true)
        XCTAssertTrue(sessionInventory.rows.first?.attributes.contains("divergence: none") == true)
        XCTAssertTrue(sessionInventory.rows.first?.attributes.contains("overlay authority: clawix_local_overlay") == true)
        XCTAssertTrue(sessionInventory.rows.first?.attributes.contains("overlay writes runtime: false") == true)
        XCTAssertTrue(sessionInventory.rows.first?.attributes.contains("overlay pinned: false") == true)
        XCTAssertTrue(sessionInventory.rows.first?.attributes.contains("parent session: parent-session") == true)
        XCTAssertTrue(sessionInventory.rows.first?.attributes.contains("input tokens: 11") == true)
        XCTAssertTrue(sessionInventory.rows.first?.attributes.contains("output tokens: 23") == true)
        XCTAssertTrue(sessionInventory.rows.first?.attributes.contains("cache read tokens: 5") == true)
        XCTAssertTrue(sessionInventory.rows.first?.attributes.contains("cache write tokens: 7") == true)
        XCTAssertTrue(sessionInventory.rows.first?.attributes.contains("reasoning tokens: 13") == true)
        XCTAssertTrue(sessionInventory.rows.first?.attributes.contains("billing provider: openai") == true)
        XCTAssertTrue(sessionInventory.rows.first?.attributes.contains("billing mode: api_key") == true)
        XCTAssertTrue(sessionInventory.rows.first?.attributes.contains("estimated cost usd: 0.0123") == true)
        XCTAssertTrue(sessionInventory.rows.first?.attributes.contains("actual cost usd: 0.0101") == true)
        XCTAssertTrue(sessionInventory.rows.first?.attributes.contains("cost status: estimated") == true)
        XCTAssertTrue(sessionInventory.rows.first?.attributes.contains("api calls: 2") == true)
        XCTAssertTrue(sessionInventory.rows.first?.accessibilityLabel.contains("native identifier sessionId") == true)
        XCTAssertTrue(sessionInventory.rows.first?.accessibilityLabel.contains("provenance source runtime-session-sqlite") == true)
        XCTAssertTrue(sessionInventory.rows.first?.accessibilityLabel.contains("attributes 18") == true)
        XCTAssertTrue(sessionInventory.rows.first?.accessibilityLabel.contains("pin authority: none") == true)
        let hermesSessionResource = try XCTUnwrap(sessionInventory.rows.first?.resource)
        let hermesOverlayActionPresentation = ClawJSRuntimeLensSessionOverlayActionPresentation.make(
            snapshot: snapshot,
            resource: hermesSessionResource,
            inFlightKeys: []
        )
        XCTAssertEqual(hermesOverlayActionPresentation.action, "pin")
        XCTAssertEqual(hermesOverlayActionPresentation.buttonTitle, "Pin")
        XCTAssertEqual(hermesOverlayActionPresentation.systemImage, "pin")
        XCTAssertEqual(hermesOverlayActionPresentation.currentPinned, false)
        XCTAssertEqual(hermesOverlayActionPresentation.targetPinned, true)
        XCTAssertEqual(hermesOverlayActionPresentation.authority, "clawix_local_overlay")
        XCTAssertEqual(hermesOverlayActionPresentation.writesRuntime, false)
        XCTAssertFalse(hermesOverlayActionPresentation.disabled)
        XCTAssertTrue(hermesOverlayActionPresentation.accessibilityLabel.contains("runtime session overlay action pin"))
        XCTAssertTrue(hermesOverlayActionPresentation.accessibilityLabel.contains("target pinned true"))

        let skillsInventory = try XCTUnwrap(inventory.sections.first { $0.domain == "skills" })
        XCTAssertEqual(skillsInventory.totalResourceCount, 1)
        XCTAssertEqual(skillsInventory.rows.first?.id, "browser-helper")
        XCTAssertEqual(skillsInventory.rows.first?.nativeIdentifierLabel, "native id: skillId")
        XCTAssertEqual(
            skillsInventory.rows.first?.provenanceLabel,
            "hermes-runtime-adapter, runtime hermes, domain skills, /Users/tester/.hermes/skills/browser-helper"
        )
        XCTAssertEqual(skillsInventory.rows.first?.limitationsLabel, "write back: blocked_until_official_runtime_write_back_contract_fixture_and_round_trip_evidence, validation: snapshot_required")
        XCTAssertEqual(skillsInventory.rows.first?.attributesLabel, "scope: runtime")

        let memoryInventory = try XCTUnwrap(inventory.sections.first { $0.domain == "memory" })
        XCTAssertEqual(memoryInventory.totalResourceCount, 1)
        XCTAssertEqual(memoryInventory.rows.first?.id, "hermes-memory-profile")
        XCTAssertEqual(memoryInventory.rows.first?.nativeIdentifierLabel, "native id: memoryId")
        XCTAssertEqual(memoryInventory.rows.first?.provenanceSource, "hermes-runtime-adapter")
        XCTAssertEqual(memoryInventory.rows.first?.sizeLabel, "43 B")
        XCTAssertTrue(memoryInventory.rows.first?.summaryLabel?.contains("not exposed by default") == true)

        let modelInventory = try XCTUnwrap(inventory.sections.first { $0.domain == "models" })
        XCTAssertEqual(modelInventory.totalResourceCount, 2)
        XCTAssertEqual(modelInventory.rows.first { $0.id == "openai/gpt-4.1" }?.nativeIdentifierLabel, "native id: modelId")
        XCTAssertEqual(modelInventory.rows.first { $0.id == "openai/gpt-4.1" }?.provenanceSource, "hermes-runtime-adapter")
        XCTAssertEqual(modelInventory.rows.first { $0.id == "openai/gpt-4.1" }?.attributesLabel, "provider: openai, model id: openai/gpt-4.1, source: config, available: true")
        XCTAssertEqual(modelInventory.rows.first { $0.id == "anthropic/claude-3-5-sonnet" }?.attributesLabel, "provider: anthropic, model id: anthropic/claude-3-5-sonnet, source: config, available: true")

        let schedulerInventory = try XCTUnwrap(inventory.sections.first { $0.domain == "scheduler" })
        XCTAssertEqual(schedulerInventory.totalResourceCount, 1)
        XCTAssertEqual(schedulerInventory.rows.first?.id, "daily-summary")
        XCTAssertEqual(schedulerInventory.rows.first?.kindLabel, "kind: cron")
        XCTAssertEqual(schedulerInventory.rows.first?.nativeIdentifierLabel, "native id: schedulerId")
        XCTAssertEqual(schedulerInventory.rows.first?.provenanceSource, "hermes-runtime-adapter")

        let authInventory = try XCTUnwrap(inventory.sections.first { $0.domain == "auth" })
        XCTAssertEqual(authInventory.totalResourceCount, 29)
        XCTAssertEqual(authInventory.statusLabel, "configured 1, missing 26, projected 1, redacted 1")
        let openAIAuthRow = try XCTUnwrap(authInventory.rows.first { $0.id == "openai" })
        XCTAssertEqual(openAIAuthRow.statusLabel, "configured")
        XCTAssertEqual(openAIAuthRow.kindLabel, "kind: api_key")
        XCTAssertEqual(openAIAuthRow.summaryLabel, "********************7890")
        XCTAssertEqual(openAIAuthRow.nativeIdentifierLabel, "native id: authProviderId")
        XCTAssertEqual(openAIAuthRow.provenanceSource, "hermes-runtime-adapter")
        XCTAssertEqual(openAIAuthRow.attributesLabel, "source: config, subscription: false, api key: true, profile key: false")
        XCTAssertEqual(openAIAuthRow.limitationsLabel, "write back: blocked_until_official_runtime_write_back_contract_fixture_and_round_trip_evidence, validation: secret_guard_and_external_pending_live_credentials")
        let scalarAuthRow = try XCTUnwrap(authInventory.rows.first { $0.id == "tencent-tokenhub" })
        XCTAssertEqual(scalarAuthRow.statusLabel, "redacted")
        XCTAssertEqual(scalarAuthRow.summaryLabel, "Hermes auth state is redacted; no credential value is exposed.")
        XCTAssertEqual(scalarAuthRow.nativeIdentifierLabel, "native id: authProviderId")
        XCTAssertEqual(scalarAuthRow.provenanceSource, "hermes-runtime-adapter")
        XCTAssertEqual(scalarAuthRow.attributesLabel, "auth scalar: redacted_value")
        XCTAssertEqual(scalarAuthRow.enabledLabel, "enabled: false")
        XCTAssertTrue(authInventory.rows.first { $0.id == "anthropic" }?.summaryLabel?.contains("auth is missing") == true)
        XCTAssertTrue(authInventory.rows.contains { $0.id == "hermes-auth-secret-ref-policy" && $0.statusLabel == "projected" })

        let pluginInventory = try XCTUnwrap(inventory.sections.first { $0.domain == "plugins" })
        XCTAssertEqual(pluginInventory.totalResourceCount, 3)
        XCTAssertEqual(pluginInventory.rows.first { $0.id == "mcp-github" }?.nativeIdentifierLabel, "native id: pluginId")
        XCTAssertEqual(pluginInventory.rows.first { $0.id == "mcp-github" }?.provenanceSource, "hermes-runtime-adapter")
        XCTAssertTrue(pluginInventory.rows.contains { $0.id == "plugin-status" })

        let channelInventory = try XCTUnwrap(inventory.sections.first { $0.domain == "channels" })
        XCTAssertEqual(channelInventory.rows.first { $0.id == "slack" }?.nativeIdentifierLabel, "native id: channelId")
        XCTAssertEqual(channelInventory.rows.first { $0.id == "slack" }?.provenanceSource, "hermes-runtime-adapter")

        let gatewayInventory = try XCTUnwrap(inventory.sections.first { $0.domain == "gateway" })
        XCTAssertEqual(gatewayInventory.totalResourceCount, 2)
        XCTAssertEqual(gatewayInventory.rows.first?.id, "gateway-status")
        XCTAssertEqual(gatewayInventory.rows.first?.nativeIdentifierLabel, "native id: gatewayStatusId")
        XCTAssertEqual(gatewayInventory.rows.first?.path, "/Users/tester/.hermes/config.yaml")
        XCTAssertEqual(gatewayInventory.rows.first?.provenancePath, "/Users/tester/.hermes/config.yaml")
        XCTAssertEqual(gatewayInventory.rows.first?.summaryLabel, "Gateway endpoint unavailable or not configured.")
        XCTAssertEqual(gatewayInventory.rows.first?.limitationsLabel, "gateway_endpoint_unavailable_or_not_configured")
        XCTAssertEqual(gatewayInventory.rows.first?.attributeCount, 5)
        XCTAssertTrue(gatewayInventory.rows.first?.attributesLabel?.contains("primary transport: gateway") == true)
        XCTAssertTrue(gatewayInventory.rows.first?.attributesLabel?.contains("streaming mode: hybrid") == true)
        let gatewayPolicyRow = try XCTUnwrap(gatewayInventory.rows.first { $0.id == "tui-gateway-transport-policy" })
        XCTAssertEqual(gatewayPolicyRow.statusLabel, "blocked")
        XCTAssertEqual(gatewayPolicyRow.kindLabel, "kind: transport_lifecycle_policy")
        XCTAssertEqual(gatewayPolicyRow.nativeIdentifierLabel, "native id: transportPolicyId")
        XCTAssertEqual(gatewayPolicyRow.path, "/Users/tester/.hermes/config.yaml")
        XCTAssertEqual(gatewayPolicyRow.provenancePath, "/Users/tester/.hermes/config.yaml")
        XCTAssertTrue(gatewayPolicyRow.summaryLabel?.contains("Production TUI Gateway transport remains blocked") == true)
        XCTAssertTrue(gatewayPolicyRow.attributesLabel?.contains("protocol: tui_gateway_json_rpc") == true)
        XCTAssertTrue(gatewayPolicyRow.attributesLabel?.contains("production transport: blocked_until_production_transport_lifecycle_policy") == true)

        let doctorInventory = try XCTUnwrap(inventory.sections.first { $0.domain == "doctorCompat" })
        XCTAssertEqual(doctorInventory.totalResourceCount, 1)
        XCTAssertEqual(doctorInventory.rows.first?.id, "doctor-status")
        XCTAssertEqual(doctorInventory.rows.first?.nativeIdentifierLabel, "native id: doctorStatusId")
        XCTAssertEqual(doctorInventory.rows.first?.path, "/Users/tester/.hermes")
        XCTAssertEqual(doctorInventory.rows.first?.provenancePath, "/Users/tester/.hermes")
        XCTAssertEqual(doctorInventory.rows.first?.summaryLabel, "hermes CLI not found")
        XCTAssertEqual(doctorInventory.rows.first?.limitationsLabel, "runtime_cli_unavailable_or_not_configured")
        XCTAssertEqual(doctorInventory.rows.first?.attributeCount, 5)
        XCTAssertTrue(doctorInventory.rows.first?.attributesLabel?.contains("version available: false") == true)

        let sandboxInventory = try XCTUnwrap(inventory.sections.first { $0.domain == "sandboxPermissions" })
        XCTAssertEqual(sandboxInventory.totalResourceCount, 1)
        XCTAssertEqual(sandboxInventory.rows.first?.id, "sandbox-policy")
        XCTAssertEqual(sandboxInventory.rows.first?.nativeIdentifierLabel, "native id: sandboxPolicyId")
        XCTAssertEqual(sandboxInventory.rows.first?.path, "/tmp/workspace")
        XCTAssertEqual(sandboxInventory.rows.first?.provenancePath, "/tmp/workspace")
        XCTAssertEqual(sandboxInventory.rows.first?.summaryLabel, "No runtime or host permission is changed by the runtime lens.")
        XCTAssertTrue(sandboxInventory.rows.first?.attributesLabel?.contains("write policy: explicit_approval_only") == true)

        let configurationInventory = try XCTUnwrap(inventory.sections.first { $0.domain == "configuration" })
        XCTAssertEqual(configurationInventory.totalResourceCount, 15)
        XCTAssertGreaterThanOrEqual(configurationInventory.pathCount, 6)
        XCTAssertEqual(configurationInventory.statusLabel, "degraded 1, projected 11, ready 1, redacted 2")
        let configurationPolicyRow = try XCTUnwrap(configurationInventory.rows.first { $0.id == "hermes-configuration-redaction-policy" })
        XCTAssertEqual(configurationPolicyRow.nativeIdentifierLabel, "native id: policyId")
        let redactedSnapshotRow = try XCTUnwrap(configurationInventory.rows.first { $0.id == "configuration-redacted-snapshot" })
        XCTAssertEqual(redactedSnapshotRow.kindLabel, "kind: redacted_config_snapshot")
        XCTAssertTrue(redactedSnapshotRow.attributesLabel?.contains("value policy: keys_and_value_kinds_only_no_plaintext_values") == true)
        let secretKeyRow = try XCTUnwrap(configurationInventory.rows.first { $0.id == "configuration-key-providers-openai-api_key" })
        XCTAssertEqual(secretKeyRow.statusLabel, "redacted")
        XCTAssertEqual(secretKeyRow.summaryLabel, "Secret key presence only.")
        XCTAssertTrue(secretKeyRow.attributesLabel?.contains("redaction: secret_key_presence_only") == true)
        XCTAssertEqual(configurationInventory.rows.last?.id, "configuration-capability")
        XCTAssertEqual(configurationInventory.rows.last?.kindLabel, "kind: config")
        XCTAssertEqual(configurationInventory.rows.last?.attributeCount, 5)
        XCTAssertEqual(
            configurationInventory.rows.last?.attributesLabel,
            "supported: true, strategy: config, diagnostic source: config, probe: config"
        )
    }

    func testHermesPolicyFallbackResourcesRenderDomainProvenance() throws {
        struct RuntimeLensEnvelope: Decodable {
            let data: ClawJSRuntimeLensSnapshot
        }

        let data = Data("""
        {
          "data": {
            "runtimeId": "hermes",
            "runtimeName": "Hermes Agent",
            "status": {},
            "domains": [],
            "domainData": {
              "skills": {
                "skills": [{
                  "id": "hermes-skills-inventory-policy",
                  "label": "Hermes skills inventory",
                  "status": "degraded",
                  "kind": "native_skill_inventory",
                  "path": "/Users/tester/.hermes/skills",
                  "enabled": false,
                  "summary": "Native Hermes skills are inventoried read-only.",
                  "limitations": ["write back: blocked_until_fixture_coverage"],
                  "attributes": ["promotion path: explicit_claw_skill_promotion_only"],
                  "provenance": { "source": "runtime-ecosystem-manifest", "runtimeId": "hermes", "domain": "skills", "path": "/Users/tester/.hermes/skills" }
                }]
              },
              "memory": {
                "memory": [{
                  "id": "hermes-memory-sensitive-projection-policy",
                  "label": "Hermes memory sensitive projection",
                  "status": "degraded",
                  "kind": "sensitive_memory_projection",
                  "path": "/Users/tester/.hermes/MEMORY.md",
                  "enabled": false,
                  "summary": "Hermes memory is projected as metadata by default.",
                  "limitations": ["write back: blocked_until_policy"],
                  "attributes": ["content access: metadata_default_explicit_content_only"],
                  "provenance": { "source": "runtime-ecosystem-manifest", "runtimeId": "hermes", "domain": "memory", "path": "/Users/tester/.hermes/MEMORY.md" }
                }]
              },
              "models": {
                "models": [{
                  "id": "hermes-model-catalog-policy",
                  "label": "Hermes model catalog",
                  "status": "degraded",
                  "kind": "model_catalog_projection",
                  "enabled": false,
                  "summary": "Hermes model projection is read-only.",
                  "limitations": ["write back: blocked_until_fixture_coverage"],
                  "attributes": ["default model write-back: blocked_until_fixture_coverage"],
                  "provenance": { "source": "runtime-ecosystem-manifest", "runtimeId": "hermes", "domain": "models" }
                }]
              },
              "scheduler": {
                "schedulers": [{
                  "id": "hermes-scheduler-inventory-policy",
                  "label": "Hermes scheduler inventory",
                  "status": "degraded",
                  "kind": "scheduler_projection",
                  "path": "/Users/tester/.hermes/cron",
                  "enabled": false,
                  "summary": "Hermes scheduler jobs are inventoried read-only.",
                  "limitations": ["write back: blocked_until_fixture_coverage"],
                  "attributes": ["mutation policy: no_silent_scheduler_change"],
                  "provenance": { "source": "runtime-ecosystem-manifest", "runtimeId": "hermes", "domain": "scheduler", "path": "/Users/tester/.hermes/cron" }
                }]
              },
              "plugins": {
                "plugins": [{
                  "id": "hermes-plugins-tools-mcp-policy",
                  "label": "Hermes plugins, tools, and MCP inventory",
                  "status": "degraded",
                  "kind": "plugin_tool_mcp_inventory",
                  "path": "/Users/tester/.hermes/plugins",
                  "enabled": false,
                  "summary": "Hermes plugins, tools, toolsets, MCP, ACP, hooks, and Computer Use are inventoried read-only without auto-enable.",
                  "limitations": ["write back: blocked_until_fixture_coverage"],
                  "attributes": ["enable policy: no_auto_enable"],
                  "provenance": { "source": "runtime-ecosystem-manifest", "runtimeId": "hermes", "domain": "plugins", "path": "/Users/tester/.hermes/plugins" }
                }]
              }
            }
          }
        }
        """.utf8)

        let snapshot = try JSONDecoder().decode(RuntimeLensEnvelope.self, from: data).data
        let inventory = ClawJSRuntimeLensInventoryPresentation.make(snapshot: snapshot, rowLimit: 10)

        XCTAssertEqual(inventory.sectionCount, 5)
        XCTAssertEqual(inventory.totalResourceCount, 5)
        XCTAssertEqual(inventory.provenanceResourceCount, 5)
        XCTAssertEqual(inventory.limitationResourceCount, 5)
        XCTAssertEqual(inventory.attributeResourceCount, 5)
        XCTAssertEqual(inventory.sections.map(\.domain), ["skills", "memory", "models", "scheduler", "plugins"])

        let skillsRow = try XCTUnwrap(inventory.sections.first { $0.domain == "skills" }?.rows.first)
        XCTAssertEqual(skillsRow.id, "hermes-skills-inventory-policy")
        XCTAssertEqual(
            skillsRow.provenanceLabel,
            "runtime-ecosystem-manifest, runtime hermes, domain skills, /Users/tester/.hermes/skills"
        )
        XCTAssertTrue(skillsRow.accessibilityLabel.contains("provenance domain skills"))
        XCTAssertTrue(skillsRow.attributes.contains("promotion path: explicit_claw_skill_promotion_only"))
        XCTAssertEqual(skillsRow.statusLabel, "degraded")
        XCTAssertEqual(skillsRow.enabledLabel, "enabled: false")

        let memoryRow = try XCTUnwrap(inventory.sections.first { $0.domain == "memory" }?.rows.first)
        XCTAssertEqual(memoryRow.id, "hermes-memory-sensitive-projection-policy")
        XCTAssertTrue(memoryRow.provenanceLabel?.contains("domain memory") == true)
        XCTAssertTrue(memoryRow.attributes.contains("content access: metadata_default_explicit_content_only"))

        let modelRow = try XCTUnwrap(inventory.sections.first { $0.domain == "models" }?.rows.first)
        XCTAssertEqual(modelRow.id, "hermes-model-catalog-policy")
        XCTAssertEqual(modelRow.provenanceLabel, "runtime-ecosystem-manifest, runtime hermes, domain models")
        XCTAssertTrue(modelRow.attributes.contains("default model write-back: blocked_until_fixture_coverage"))

        let schedulerRow = try XCTUnwrap(inventory.sections.first { $0.domain == "scheduler" }?.rows.first)
        XCTAssertEqual(schedulerRow.id, "hermes-scheduler-inventory-policy")
        XCTAssertTrue(schedulerRow.provenanceLabel?.contains("domain scheduler") == true)
        XCTAssertTrue(schedulerRow.attributes.contains("mutation policy: no_silent_scheduler_change"))

        let pluginRow = try XCTUnwrap(inventory.sections.first { $0.domain == "plugins" }?.rows.first)
        XCTAssertEqual(pluginRow.id, "hermes-plugins-tools-mcp-policy")
        XCTAssertTrue(pluginRow.provenanceLabel?.contains("domain plugins") == true)
        XCTAssertTrue(pluginRow.attributes.contains("enable policy: no_auto_enable"))
    }
}
