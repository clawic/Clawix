import XCTest
@testable import Clawix

final class ClawJSRuntimeLensInventoryPresentationTests: XCTestCase {
    func testRuntimeLensSessionAndInventoryPresentations() async throws {
        let snapshot = try await ClawJSRuntimeLensTestFixtures.degradedRuntimePortalSnapshot()

        XCTAssertEqual(snapshot.domainData?.sessions?.session?.primaryTransport, "gateway")
        XCTAssertEqual(snapshot.domainData?.sessions?.session?.sessionPath, "/Users/tester/.hermes/sessions")
        let sessionDescriptorPresentation = ClawJSRuntimeLensSessionDescriptorPresentation.make(
            session: try XCTUnwrap(snapshot.domainData?.sessions?.session)
        )
        XCTAssertEqual(sessionDescriptorPresentation.primaryTransport, "gateway")
        XCTAssertEqual(sessionDescriptorPresentation.transportKind, "cli")
        XCTAssertEqual(sessionDescriptorPresentation.streaming, true)
        XCTAssertEqual(sessionDescriptorPresentation.streamingLabel, "hybrid")
        XCTAssertEqual(sessionDescriptorPresentation.persistence, "runtime")
        XCTAssertEqual(sessionDescriptorPresentation.fallbackTransport, "cli")
        XCTAssertEqual(sessionDescriptorPresentation.sessionPath, "/Users/tester/.hermes/sessions")
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
        XCTAssertEqual(overlayPresentation.runtimeId, "hermes")
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
            "runtime-session-store, runtime hermes, /Users/tester/.hermes/sessions/2026/05/21/runtime-session.jsonl"
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
                "runtime-lens-session-overlay-action-hermes-2026-05-21-runtime-session"
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
}
