#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = new Set(process.argv.slice(2));
const requireClawJSSibling = args.has("--require-clawjs") || process.env.CLAWJS_SDK_FIRST_REQUIRE_CLAWJS === "1";
const errors = [];

function fail(message) {
  errors.push(message);
}

function assert(condition, message) {
  if (!condition) fail(message);
}

function read(relativePath) {
  return fs.readFileSync(path.join(rootDir, relativePath), "utf8");
}

function readFrom(baseDir, relativePath) {
  return fs.readFileSync(path.join(baseDir, relativePath), "utf8");
}

function requireSnippet(relativePath, snippet) {
  const text = read(relativePath);
  assert(text.includes(snippet), `${relativePath}: missing ${JSON.stringify(snippet)}`);
}

function forbidSnippet(relativePath, snippet) {
  const text = read(relativePath);
  assert(!text.includes(snippet), `${relativePath}: must not contain ${JSON.stringify(snippet)}`);
}

function requireSiblingSnippet(siblingRoot, relativePath, snippet) {
  const text = readFrom(siblingRoot, relativePath);
  assert(text.includes(snippet), `clawjs:${relativePath}: missing ${JSON.stringify(snippet)}`);
}

function assertCompletionAudit() {
  const text = read("docs/governance/sdk-first-custom-surfaces/completion.md");
  for (const snippet of [
    "Source conversation: `019e403c-3837-7f02-9b78-532c43cdd997`",
    "Status: `active_goal_not_complete`",
    "private source session path is",
    "also inspects",
    "private source-session verifier has re-read",
    "24 decision prompt ids",
    "three interrupted unanswered ids",
    "docs/governance/sdk-first-custom-surfaces/external-pending.md",
    "scripts/validate-sdk-first-custom-surfaces-external-evidence.mjs",
    "The Clawix verifier inspects sibling ClawJS evidence when that checkout is present.",
    "The Network Control Plane now adds a typed executable route-family example",
    "Clawix `NetworkControlBridge` projection through `system/network`",
    "Clawix now mirrors the ClawJS `system.telemetry.snapshot` and `system.telemetry.history` local-wide read contracts",
    "Clawix `window.clawix.capabilities` now mirrors the ClawJS SDK facade shape",
    "`list`, `get`, `riskMap`, and `source`",
    "complete resolved surface bindings across SDK, CLI, service API, MCP, Relay, and host bridge projections",
    "exact reviewed custom-app capability ID set",
    "exact reviewed risk partition sets",
    "exact reviewed dispatch mode partitions",
    "exact reviewed blocked and metadata-only surface partitions",
    "no `pending` status, no future-facade SDK refs, no unknown dispatch modes, no source-level unknown dispatch fallback, no conditional placeholder refs",
    "no source-level unknown dispatch fallback",
    "local-only/custom-app Relay coverage as `relay.remote.custom_app_sdk` metadata-only projection",
    "`window.clawix.system.telemetry`",
    "`SystemTelemetryBridge.localStatusBridge`",
    "Clawix exposes `resources.list` as its own local-wide registered-resource catalog read",
    "Clawix now exposes `jobs.list`, `jobs.get`, and `jobs.events` through `window.clawix.jobs.{list,get,events}()`",
    "Clawix now exposes `jobs.stream`, `jobs.start`, and `jobs.cancel` through runtime jobs contracts",
    "Sibling ClawJS runtime now has local authenticated backend routes for `runtime/jobs/start`",
    "`window.clawix.jobs.stream/start/cancel`",
    "`window.clawix.mac.planAction()`",
    "dry-run-only Mac Control planner",
    "`window.clawix.iot.invokeAction()`",
    "`iot.device.action.invoke` host-bridge operation",
    "`window.clawix.actions.invoke()`",
    "`window.clawix.secrets.broker()`",
    "no-runner/no-plaintext-broker dispatch reasons",
    "| CLX-SDK-001 | ADR, scope, decision-map, and discoverability routing",
    "| CLX-SDK-002 | Shared capability catalog and SDK/CLI/API/MCP/Relay/host-bridge parity",
    "| CLX-SDK-003 | Web custom apps use code plus manifest and `window.clawix`",
    "| CLX-SDK-004 | High-risk actions interrupt only",
    "| CLX-SDK-005 | Imported/marketplace apps require origin/capability/risk ficha",
    "host-local `app-package-trust-roots.json` policy",
    "signature key/trust-source provenance",
    "| CLX-SDK-006 | Protected routes and variants keep secrets",
    "docs/sdk-first-custom-surfaces-installed-app-smoke.md",
    "verified a local `database/tasks` variant default rendered as `User`",
    "| CLX-SDK-007 | Swift custom surfaces are native but isolated",
    "verified the signed bundled helper, valid stdout `render` output",
    "main Clawix PID unchanged",
    "| CLX-SDK-008 | Clawix shell remains modular and nonblocking",
    "docs/sdk-first-custom-surfaces-installed-performance-smoke.md",
    "docs/sdk-first-custom-surfaces-performance-closure-summary.md",
    "launched `/Applications/Clawix.app` under Instruments",
    "rescue reachability, and a deliberately delayed-heavy-surface Web fixture reaching route-local timeout",
    "Newer host-liveness and all-process captures confirmed the installed Clawix process stayed alive after capture",
    "redacted stack attribution separated Clawix host SwiftUI/route/render work from WebKit WebContent and GPU work",
    "Raw trace artifacts stay private because they contain local environment details and all-process metadata",
    "Performance governance now routes whole-computer resource classification",
    "scripts/performance_governance_check.mjs",
    "design governance rather than measured UI evidence",
    "Signed-app UI/Instruments performance evidence still needs an approved baseline and explicit review decision",
    "Complete real signed-app UI/Instruments performance evidence is missing.",
    "| CLX-SDK-009 | Unanswered `data_access_lock`, `custom_collections`, and `cli_escape_hatch`",
    "| CLX-SDK-010 | Final decision-by-decision source-session audit",
    "VALIDATED PRIVATE",
    "Do not call `update_goal`",
  ]) {
    assert(text.includes(snippet), `docs/governance/sdk-first-custom-surfaces/completion.md: missing ${JSON.stringify(snippet)}`);
  }
  const rowIds = text.match(/\| CLX-SDK-\d{3} \|/g) ?? [];
  assert(rowIds.length === 10, "docs/governance/sdk-first-custom-surfaces/completion.md: must contain exactly CLX-SDK-001 through CLX-SDK-010");
  assert(!text.includes("/Users/"), "docs/governance/sdk-first-custom-surfaces/completion.md: must not publish private filesystem paths");
  for (const [rowId, status] of [
    ["CLX-SDK-002", "VALIDATED LOCAL"],
    ["CLX-SDK-004", "EXTERNAL PENDING"],
    ["CLX-SDK-005", "VALIDATED LOCAL"],
    ["CLX-SDK-006", "VALIDATED LOCAL"],
    ["CLX-SDK-007", "VALIDATED LOCAL"],
    ["CLX-SDK-008", "EXTERNAL PENDING"],
    ["CLX-SDK-010", "VALIDATED PRIVATE"],
  ]) {
    const pattern = new RegExp(`\\|\\s*${rowId}\\s*\\|[^\\n]*\\|\\s*${status}\\s*\\|`);
    assert(pattern.test(text), `docs/governance/sdk-first-custom-surfaces/completion.md: ${rowId} must remain ${status}`);
  }
}

function assertPublicRouting() {
  for (const [relativePath, snippets] of Object.entries({
    "docs/adr/0019-sdk-first-custom-surfaces-and-nonblocking-shell.md": [
      "SDK-first custom surfaces and nonblocking shell mirror",
      "`clawix.capabilities.contracts()` is a metadata-only contract catalog",
      "`executionBoundary`",
      "`window.clawix`",
    ],
    "docs/governance/sdk-first-custom-surfaces/plan.md": [
      "metadata-only `executionBoundary`",
      "`clawix.capabilities.contracts()` exposes `executionBoundary`",
      "`window.clawix.capabilities` mirrors the shared SDK facade shape",
      "stdout `render` message",
      "Direct SQLite is not exposed as a custom-app action surface.",
      "Installed-app smoke verified that a local `database/tasks` variant default",
      "Installed-app smoke verified the signed bundled Swift surface runner",
      "Installed-app Time Profiler smoke",
      "signed app launch and attach capture paths",
      "deliberately delayed-heavy-surface Web fixture reaching route-local timeout",
      "newer host-liveness and all-process captures confirmed post-capture app",
      "baseline remains the closure blocker",
      "docs/sdk-first-custom-surfaces-performance-closure-summary.md",
      "delayed-heavy-surface",
      "`system.telemetry.snapshot` and `system.telemetry.history` are mirrored as",
      "`resources.list` and `resources.read` are separate local-wide capabilities",
      "`jobs.list`, `jobs.get`, and `jobs.events` are exposed to Web custom apps",
      "`jobs.stream` is exposed through the runtime jobs event stream contract",
      "`jobs.start` and `jobs.cancel` are approval-gated runtime job mutations",
      "Sibling ClawJS runtime now has local authenticated backend routes",
      "`window.clawix.jobs.stream/start/cancel`",
      "`mac.action.plan` is exposed to Web custom apps through",
      "`iot.device.action.invoke` is exposed to Web custom apps through",
      "`actions.invoke` and `secrets.broker` are exposed to Web custom apps through",
      "docs/governance/sdk-first-custom-surfaces/external-pending.md",
      "scripts/validate-sdk-first-custom-surfaces-external-evidence.mjs",
    ],
    "docs/governance/sdk-first-custom-surfaces/external-pending.md": [
      "Status: `active_goal_not_complete`",
      "Rows marked `EXTERNAL PENDING` are blockers",
      "CLX-SDK-EXT-001",
      "Signed-host/native high-risk execution from custom apps",
      "CLX-SDK-EXT-002",
      "Live IoT/provider action execution from custom apps",
      "CLX-SDK-EXT-003",
      "Approved signed-app performance baseline",
      "CLX-SDK-EXT-004",
      "Live marketplace trust validation",
      "scripts/validate-sdk-first-custom-surfaces-external-evidence.mjs",
    ],
    "docs/governance/sdk-first-custom-surfaces/external-validation-runbook.md": [
      "Status: `active_goal_not_complete`",
      "This runbook defines the only accepted way",
      "CLX-SDK-EXT-001 signed-host/native execution",
      "CLX-SDK-EXT-002 live IoT/provider action",
      "CLX-SDK-EXT-003 approved performance baseline",
      "CLX-SDK-EXT-004 live marketplace trust",
      "Required Critical Performance Flows",
      "installed_app_launch",
      "sidebar_hover_click_expand",
      "rescue_reachability",
      "private source-session verifier",
    ],
    "docs/governance/sdk-first-custom-surfaces/external-evidence.schema.json": [
      "\"title\": \"Clawix SDK-first custom surfaces external evidence packet\"",
      "\"CLX-SDK-EXT-001\"",
      "\"CLX-SDK-EXT-002\"",
      "\"CLX-SDK-EXT-003\"",
      "\"CLX-SDK-EXT-004\"",
      "\"containsPrivatePaths\"",
      "\"containsRawTrace\"",
      "\"requiresFinalSourceReread\"",
    ],
    "docs/governance/sdk-first-custom-surfaces/external-evidence.fixtures.json": [
      "\"status\": \"synthetic_templates_not_evidence\"",
      "\"validSyntheticPackets\"",
      "\"invalidSyntheticPackets\"",
      "\"rejects missing signed-host native grant\"",
      "\"rejects performance baseline missing required flow\"",
      "\"rejects private paths in public packet\"",
      "\"rejects marketplace trust without ficha receipt\"",
    ],
    "docs/sdk-first-custom-surfaces-installed-app-smoke.md": [
      "Bundle id: `com.clawix.app`",
      "`codex-variant-smoke-tasks`",
      "`User default variant for database/tasks`",
      "`clawix-app://codex-variant-smoke-tasks/index.html`",
      "`/Applications/Clawix.app/Contents/Helpers/ClawixSwiftSurfaceRunner`",
      "`codex-swift-runner-smoke`",
      "`Rendered by the installed Swift surface runner.`",
      "The Clawix app process stayed alive with the same PID",
      "This smoke does not validate signed-host native permissions",
    ],
    "docs/sdk-first-custom-surfaces-installed-performance-smoke.md": [
      "Status: `partial_local_evidence`",
      "Do not publish the raw trace",
      "`/Applications/Clawix.app/Contents/MacOS/Clawix`",
      "`Time Profiler`",
      "`macos/artifacts/traces/20260520T122426Z-installed-shell-time-profiler.trace`",
      "`macos/artifacts/traces/20260520T123248Z-installed-launch-time-profiler.trace`",
      "`macos/artifacts/traces/20260520T161127Z-clean-rescue-delayed-heavy-time-profiler.trace`",
      "`macos/artifacts/traces/20260520T183831Z-liveness-rescue-delayed-heavy-time-profiler.trace`",
      "`macos/artifacts/traces/20260520T184057Z-allprocess-rescue-delayed-heavy-time-profiler.trace`",
      "`codex-delayed-heavy-surface` under the framework apps directory",
      "The installed app launched under Instruments for a 30 second Time Profiler",
      "A local Web custom app route opened through the sidebar.",
      "A local Swift declarative app route opened through the sidebar.",
      "A focused rescue route was opened through `clawix://rescue`",
      "The local `codex-delayed-heavy-surface` Web app was opened from the sidebar",
      "A host-only liveness rerun repeated the rescue and delayed-heavy route",
      "A final all-process Time Profiler rerun repeated the same route",
      "`SidebarView.makeSnapshot` stayed around 2.65-2.80 ms",
      "`SidebarView.makeSnapshot` around 2.40 ms in the startup window",
      "The delayed-heavy fixture produced the expected route-local unavailable",
      "`SidebarView.makeSnapshot` stayed below 6.30 ms",
      "installed Clawix process was still alive after",
      "WebContent samples in WebCore/JSC `performance.now`",
      "WebKit GPU remote graphics work",
      "first rescue plus delayed-heavy capture did not leave enough evidence",
      "Later host-liveness and all-process reruns did confirm post-capture app",
      "approved performance baseline",
      "raw trace and exported Instruments table of contents include local",
      "all-process trace includes unrelated local process metadata",
      "A custom surface timeout appeared after a route/scroll transition.",
      "`CLX-SDK-008` remains `EXTERNAL PENDING`",
    ],
    "docs/sdk-first-custom-surfaces-performance-closure-summary.md": [
      "Status: `external_pending_baseline`",
      "This is the reviewable public closure summary for the `CLX-SDK-008`",
      "## Required Flow Coverage",
      "Installed app launch",
      "Sidebar interaction",
      "Chat basics",
      "Rescue path",
      "Web custom surface load",
      "Swift custom surface load",
      "Host liveness",
      "Failure-domain attribution",
      "Confirmed:",
      "Probable:",
      "Discarded for this scenario:",
      "Partial:",
      "approved baseline bundle",
      "`CLX-SDK-008` remains `EXTERNAL PENDING`",
    ],
    "docs/decision-map.md": [
      "docs/governance/sdk-first-custom-surfaces/completion.md",
      "docs/governance/sdk-first-custom-surfaces/external-pending.md",
      "scripts/verify-sdk-first-custom-surfaces-goal.mjs",
      "scripts/validate-sdk-first-custom-surfaces-external-evidence.mjs",
      "`window.clawix` host bridge",
      "Generic `actions.invoke` and `secrets.broker` are explicit approval-gated no-runner/no-plaintext-broker gaps",
      "accepted explicit gaps, not an unstated executor blocker",
    ],
    "docs/discoverability.registry.json": [
      "docs/governance/sdk-first-custom-surfaces/completion.md",
      "docs/governance/sdk-first-custom-surfaces/external-pending.md",
      "docs/governance/sdk-first-custom-surfaces/external-evidence.schema.json",
      "docs/governance/sdk-first-custom-surfaces/external-evidence.fixtures.json",
      "scripts/verify-sdk-first-custom-surfaces-goal.mjs",
      "custom app SDK executionBoundary",
    ],
    "docs/discoverability.md": [
      "sdk-first-custom-surfaces-completion-audit",
      "sdk-first-custom-surfaces-external-pending",
      "sdk-first-custom-surfaces-external-evidence-schema",
      "verify-sdk-first-custom-surfaces-goal",
    ],
  })) {
    for (const snippet of snippets) requireSnippet(relativePath, snippet);
  }

  forbidSnippet("docs/decision-map.md", "backend executor");
}

function assertRuntimeArtifacts() {
  for (const [relativePath, snippets] of Object.entries({
    "macos/Package.swift": [
      "ClawixSwiftSurfaceRunner",
      "Sources/ClawixSwiftSurfaceRunner",
    ],
    "macos/Sources/Clawix/Apps/AppCapabilityCatalog.swift": [
      "static var executionBoundaryBridgeValue",
      "\"metadata_only_contract_catalog\"",
      "\"hostBridgeImplementation\": \"window.clawix\"",
      "\"approvalRequiredNoPlaintextBroker\"",
      "\"mode\": \"unclassifiedBlocked\"",
      "\"EXTERNAL PENDING\"",
      "systemTelemetrySnapshotSchemaRef",
      "system.telemetry.snapshot",
      "system.telemetry.history",
      "resourcesListSchemaRef",
      "resources.list",
      "jobsListSchemaRef",
      "jobs.list",
      "jobsGetSchemaRef",
      "jobs.get",
      "jobsEventsSchemaRef",
      "jobs.events",
      "jobs.stream",
      "jobs.start",
      "jobs.cancel",
      "\"blocked\"",
      "static let canonicalSurfaceNames",
      "static func surfaceBindingsBridgeValue(for descriptor",
      "private static func surfaceRef(for descriptor",
      "window.clawix.jobs.list",
      "mcp.custom_app_sdk metadata-only contract projection",
      "relay.remote.custom_app_sdk metadata-only contract projection",
      "statuses[\"cli\"] = \"blocked\"",
      "statuses[\"mcp\"] = \"blocked\"",
    ],
    "macos/Sources/Clawix/Apps/AppBridgeQueryDSL.swift": [
      "case invalidCollection(String)",
      "case unsupportedQueryKey(String)",
      "sqlite_",
    ],
    "macos/Sources/Clawix/Apps/AppBridgeMessageHandler.swift": [
      "capabilities.contracts",
      "AppCapabilityCatalog.contractsBridgeValue",
      "highRiskActionDispatcher.dispatch",
      "\"actions.invoke\"",
      "\"secrets.broker\"",
      "\"jobs.list\"",
      "\"jobs.get\"",
      "\"jobs.events\"",
      "jobBridgeValue",
      "jobDetailBridgeValue",
      "jobEventBridgeValues",
      "\"mac.action.plan\"",
      "\"iot.device.action.invoke\"",
      "macActionPlanTool",
      "handleSystemTelemetrySnapshot",
      "systemTelemetrySnapshotBridgeValue",
      "SystemTelemetryBridge",
    ],
    "macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift": [
      "localStatusBridge",
      "telemetry",
      "history",
    ],
    "macos/Sources/Clawix/Apps/AppSwiftSurfaceActionBridge.swift": [
      "AppSwiftSurfaceActionBridge",
      "handleHighRiskAction",
      "AppHighRiskActionAudit.append",
      "highRiskActionDispatcher.dispatch",
      "Swift surface read action accepted",
      "executeResourceRead",
      "executeDBQuery",
      "executeSearchQuery",
      "AppBridgeQueryDSL.dbQuery",
      "AppBridgeQueryDSL.searchQuery",
      "resources.read",
    ],
    "macos/Sources/Clawix/Apps/ClawixAppsSDK.swift": [
      "capabilities",
      "get: function (id) { return send('capabilities.get'",
      "contracts: function () { return send('capabilities.contracts'); }",
      "source: function () { return send('capabilities.source'); }",
      "actions.invoke",
      "secrets.broker",
      "ttlSeconds",
      "search.query",
      "db.query",
      "resources.list",
      "jobs.list",
      "jobs.get",
      "jobs.events",
      "mac.action.plan",
      "planAction",
      "iot.device.action.invoke",
      "invokeAction",
      "system.telemetry.snapshot",
      "system.telemetry.history",
    ],
    "macos/Sources/Clawix/Apps/AppSwiftSurfaceContract.swift": [
      "AppSwiftSurfaceRunnerSupervisor",
      "AppSwiftSurfaceProcessExecutor",
      "AppSwiftSurfaceRunnerRenderMessage",
      "runnerBundledExecutablePath",
      "Contents/Helpers/\\(runnerExecutableName)",
      "renderManifest(",
      "runnerCapabilityNotAllowed",
      "AppSwiftSurfaceRenderPresentation",
      "AppSwiftSurfaceRenderedNode",
      "Swift surface runner must be out-of-process.",
      "highRiskRead",
    ],
    "macos/Sources/ClawixSwiftSurfaceRunner/main.swift": [
      "RunnerRenderMessage",
      "--manifest",
      "--protocol-version",
      "\"render\"",
    ],
    "macos/scripts/dev.sh": [
      "swift build --target ClawixSwiftSurfaceRunner",
      "Contents/Helpers/ClawixSwiftSurfaceRunner",
      "swift-surface-runner",
    ],
    "macos/scripts/build_release_app.sh": [
      "swift build -c release --target ClawixSwiftSurfaceRunner",
      "Contents/Helpers/ClawixSwiftSurfaceRunner",
      "swift-surface-runner",
    ],
    "macos/scripts/build_app.sh": [
      "swift build -c release --target ClawixSwiftSurfaceRunner",
      "Contents/Helpers/ClawixSwiftSurfaceRunner",
      "swift-surface-runner",
    ],
    "macos/Sources/Clawix/Apps/AppPackageImportValidator.swift": [
      "validatePackageContents",
      "AppSwiftSurfaceContract.manifestFilename",
      "contentDigestSHA256",
      "package-signature.json",
      "signatureEvaluation",
      "Curve25519.Signing.PublicKey",
      "signaturePayload",
      "AppPackageSignatureManifest",
    ],
    "macos/Sources/Clawix/Apps/AppPackageTrustPolicy.swift": [
      "app-package-trust-roots.json",
      "TrustedSignatureKey",
      "trustSource",
      "ed25519",
    ],
    "macos/Sources/Clawix/Apps/AppRecord.swift": [
      "signatureKeyId",
      "signatureTrustSource",
    ],
    "macos/Sources/Clawix/Apps/AppTrustAudit.swift": [
      "signatureKeyId",
      "signatureTrustSource",
    ],
    "macos/Sources/Clawix/Apps/AGENT_CONTRACT.md": [
      "app-package-trust-roots.json",
      "signatureKeyId",
      "signatureTrustSource",
    ],
    "macos/Sources/Clawix/Apps/AppVariantDefaultsStore.swift": [
      "case workspace",
      "case user",
      "protectedRouteViolations",
    ],
    "macos/Sources/Clawix/NetworkControl/NetworkControlBridge.swift": [
      "NetworkControlBridge",
      "resource: \"network\"",
      "action: \"routes\"",
      "NetworkControlRouteDecision",
      "detail_opt_in",
    ],
  })) {
    for (const snippet of snippets) requireSnippet(relativePath, snippet);
  }

  forbidSnippet("macos/Sources/Clawix/Apps/AppCapabilityCatalog.swift", '"mode": "unknown"');
  forbidSnippet(
    "macos/Sources/Clawix/Apps/AppCapabilityCatalog.swift",
    '"reason": "No custom-app dispatcher is registered for this capability."',
  );
}

function assertExternalValidationArtifacts() {
  const result = spawnSync(process.execPath, ["scripts/validate-sdk-first-custom-surfaces-external-evidence.mjs", "--self-test"], {
    cwd: rootDir,
    encoding: "utf8",
  });
  if (result.status !== 0) {
    fail(`scripts/validate-sdk-first-custom-surfaces-external-evidence.mjs --self-test failed:\n${result.stderr || result.stdout}`);
  }
}

function assertTests() {
  const appSurfaceTestText = [
    "macos/Tests/ClawixMeshTests/AppCustomSurfaceCapabilityTests.swift",
    "macos/Tests/ClawixMeshTests/AppCustomSurfaceCapabilityCatalogTests.swift",
    "macos/Tests/ClawixMeshTests/AppCustomSurfaceResourceQueryTests.swift",
    "macos/Tests/ClawixMeshTests/AppCustomSurfaceSDKBridgeTests.swift",
    "macos/Tests/ClawixMeshTests/AppCustomSurfaceTrustPolicyTests.swift",
    "macos/Tests/ClawixMeshTests/AppHighRiskActionDispatcherTests.swift",
    "macos/Tests/ClawixMeshTests/AppSwiftSurfaceActionBridgeTests.swift",
    "macos/Tests/ClawixMeshTests/AppSwiftSurfaceContractTests.swift",
    "macos/Tests/ClawixMeshTests/AppVariantDefaultsTests.swift",
  ].map((relativePath) => read(relativePath)).join("\n");
  for (const snippet of [
    "testHostBridgeExposesCustomAppSDKContractPayload",
    "testHostBridgeSurfaceBindingsAreCompleteAndResolvedWhenPublished",
    "testRegisteredCapabilitiesDoNotFallBackToUnknownDispatch",
    "expectedCustomAppCapabilityIds",
    "expectedOrdinaryAccessCapabilityIds",
    "expectedApprovalRequiredCapabilityIds",
    "expectedCliBlockedSurfaceCapabilityIds",
    "expectedMcpBlockedSurfaceCapabilityIds",
    "expectedApprovalDispatchCapabilityIds",
    "expectedNoPlaintextBrokerDispatchCapabilityIds",
    "XCTAssertEqual(AppCapabilityCatalog.descriptors.map(\\.id).sorted(), expectedCustomAppCapabilityIds)",
    "XCTAssertEqual(riskMap.highRisk.sorted(), expectedApprovalRequiredCapabilityIds)",
    "testDispatchModesKeepReviewedPartitions",
    "XCTAssertEqual(approvalDispatch.sorted(), expectedApprovalDispatchCapabilityIds)",
    "testSurfaceBindingsKeepReviewedBlockedPartitions",
    "XCTAssertEqual(cliBlocked.sorted(), expectedCliBlockedSurfaceCapabilityIds)",
    "XCTAssertNotEqual(dispatch[\"mode\"] as? String, \"unknown\"",
    "XCTAssertEqual(checkedSurfaceGroups, capabilities.count)",
    "XCTAssertNotNil(surface[\"ref\"]",
    "XCTAssertNil(jobsListSurfaces.first { $0[\"surface\"] == \"cli\" }?[\"ref\"])",
    "XCTAssertEqual(jobsListSurfaces.first { $0[\"surface\"] == \"sdk\" }?[\"ref\"], \"window.clawix.jobs.list\")",
    "testSwiftSurfaceResourceListExecutesThroughRegisteredResources",
    "testInjectedAppsSdkExposesMacPlanOnlyFacade",
    "testInjectedAppsSdkExposesIoTActionFacade",
    "testInjectedAppsSdkExposesActionsAndSecretsBrokerFacades",
    "testInjectedAppsSdkExposesJobsListFacade",
    "testJobsListBridgeValueRedactsRunMetadataThroughSharedPolicy",
    "testFrameworkHighRiskActionDispatcherKeepsGenericActionsAndSecretsUnavailable",
    "capabilities.get",
    "capabilities.source",
    "testDBQueryDSLRejectsCollectionEscapesAndDDLKeys",
    "testBridgeOperationPolicyDoesNotExposeEscapeHatches",
    "testActivationReviewPresentationIncludesPackageProvenance",
    "testAppsSettingsVariantDefaultPresentationAllowsUserAndWorkspaceManagement",
    "testSwiftSurfaceRunnerSupervisorRejectsInProcessPlans",
    "testSwiftSurfaceProcessExecutorTerminatesProcessWhenTaskIsCancelled",
    "testSwiftSurfaceRenderPresentationBuildsDeclarativeTree",
    "testSwiftSurfaceRunnerRenderMessageOverridesHostManifestThroughIPC",
    "testSwiftSurfaceRunnerIPCRejectsCapabilitiesOutsideLaunchPlan",
    "testSwiftSurfaceRunnerExecutablePathFallsBackToBundledHelper",
    "testSwiftSurfaceReadActionDoesNotRequestInterruptiveApproval",
    "testSwiftSurfaceResourceReadExecutesThroughRegisteredResources",
    "testSwiftSurfaceDBQueryExecutesThroughDatabaseManager",
    "testSwiftSurfaceSearchQueryExecutesThroughDatabaseManager",
    "testSwiftSurfaceHighRiskActionUsesApprovalDispatcherAndAudit",
    "testSystemTelemetryBridgeValuesMatchSdkContracts",
    "Signature key",
    "Trust source",
  ]) {
    assert(appSurfaceTestText.includes(snippet), `macos/Tests/ClawixMeshTests/AppCustomSurface*Tests.swift: missing ${JSON.stringify(snippet)}`);
  }

  for (const [relativePath, snippets] of Object.entries({
    "macos/Tests/ClawixMeshTests/AppsStoreCancellationTests.swift": [
      "testImportAppVerifiesSignedPackageDigestWithHostTrustPolicy",
      "AppPackageTrustPolicy.defaultURL",
      "signatureTrustSource",
      "testImportAppMarksPackageSignatureFailedWhenDigestChanges",
    ],
    "macos/Tests/ClawixMeshTests/SurfaceShellPerformanceTests.swift": [
      "testCriticalShellStartFastPathStaysBoundedWithAllHeavyDependenciesUnavailable",
      "testExtensionSurfaceStartMeasurementRemainsRouteLocalUnderUnavailableDependencies",
    ],
    "macos/Tests/ClawixMeshTests/SurfaceRouteSupervisorTests.swift": [
      "SurfaceRouteSupervisor",
      "cancel",
    ],
    "macos/Tests/ClawixMeshTests/NetworkControlBridgeTests.swift": [
      "testDecodesGatewayRouteDecision",
      "testBridgeUsesSystemNetworkResourceWithoutNativeMutation",
      "network.adapter.gateway",
      "external_pending",
    ],
  })) {
    for (const snippet of snippets) requireSnippet(relativePath, snippet);
  }
}

function assertSiblingClawJSArtifacts() {
  const siblingRoot = process.env.CLAWJS_SDK_FIRST_ROOT
    ? path.resolve(process.env.CLAWJS_SDK_FIRST_ROOT)
    : path.resolve(rootDir, "..", "..", "clawjs");
  if (!fs.existsSync(siblingRoot)) {
    if (requireClawJSSibling) fail(`missing sibling ClawJS checkout at ${siblingRoot}`);
    return;
  }

  for (const [relativePath, snippets] of Object.entries({
    "docs/adr/0032-sdk-first-custom-surfaces-and-nonblocking-shell.md": [
      "The shared custom-app SDK inspection payload includes an `executionBoundary`",
      "MCP `clawjs.custom_app_sdk`",
      "Relay `/v1/remote/custom-app-sdk` are metadata-only contract projections",
    ],
    "docs/governance/sdk-first-custom-surfaces/plan.md": [
      "Expose `executionBoundary` in the shared custom-app SDK inspection payload",
      "Custom-app SDK inspection exposes `executionBoundary` across CLI/API/MCP/",
      "Sibling Clawix mirrors the ClawJS capability facade shape",
      "Sibling Clawix exposes `mac.action.plan` through",
      "Sibling Clawix exposes `iot.device.action.invoke` through",
      "Sibling Clawix exposes `actions.invoke` and `secrets.broker` through",
      "ClawJS and sibling Clawix expose `jobs.list`, `jobs.get`, and `jobs.events`",
      "ClawJS and sibling Clawix expose `jobs.stream` through the runtime jobs event",
      "ClawJS and sibling Clawix expose `jobs.start` and `jobs.cancel` as",
      "ClawJS runtime has local authenticated backend routes",
      "Public CLI job mutation",
      "docs/governance/sdk-first-custom-surfaces/external-pending.md",
      "scripts/validate-sdk-first-custom-surfaces-external-evidence.mjs",
    ],
    "docs/decision-map.md": [
      "packages/clawjs-core/src/custom-app-sdk-inspection.ts",
      "scripts/validate-sdk-first-custom-surfaces-external-evidence.mjs",
      "metadata-only projection boundaries",
    ],
    "packages/clawjs-core/src/custom-app-sdk-inspection.ts": [
      "CUSTOM_APP_SDK_EXECUTION_BOUNDARY",
      "metadata_only_contract_catalog",
      "relay.remote.custom_app_sdk",
    ],
    "packages/clawjs-core/src/capability-catalog.ts": [
      "id: \"system.telemetry.snapshot\"",
      "id: \"system.telemetry.history\"",
      "id: \"resources.list\"",
      "id: \"jobs.list\"",
      "id: \"jobs.get\"",
      "id: \"jobs.events\"",
      "id: \"jobs.start\"",
      "id: \"jobs.cancel\"",
      "@clawjs/claw:system.telemetry.snapshot",
      "@clawjs/claw:system.telemetry.history",
      "@clawjs/claw:capabilities metadata + claw.search.query.v1 schema",
      "@clawjs/claw:capabilities metadata + claw.db.query.v1 schema",
      "@clawjs/claw:capabilities metadata + claw.actions.invoke.v1 schema",
      "@clawjs/claw:capabilities metadata + claw.mac.actionRequest.v1 schema",
      "const customAppSDKRelayMetadataProjection = \"relay.remote.custom_app_sdk metadata-only contract projection\";",
      "\"unclassifiedBlocked\"",
    ],
    "packages/clawjs-core/src/capability-catalog.test.ts": [
      "EXPECTED_CUSTOM_APP_CAPABILITY_IDS",
      "EXPECTED_ORDINARY_ACCESS_CAPABILITY_IDS",
      "EXPECTED_APPROVAL_REQUIRED_CAPABILITY_IDS",
      "EXPECTED_CLI_BLOCKED_CAPABILITY_IDS",
      "EXPECTED_LOCAL_WIDE_DISPATCH_CAPABILITY_IDS",
      "EXPECTED_APPROVAL_DISPATCH_CAPABILITY_IDS",
      "EXPECTED_NO_PLAINTEXT_BROKER_DISPATCH_CAPABILITY_IDS",
      "EXPECTED_MCP_METADATA_PROJECTION_CAPABILITY_IDS",
      "EXPECTED_RELAY_METADATA_PROJECTION_CAPABILITY_IDS",
      "assert.deepEqual(ids, EXPECTED_CUSTOM_APP_CAPABILITY_IDS)",
      "assert.deepEqual(sorted(riskMap.ordinaryAccess), EXPECTED_ORDINARY_ACCESS_CAPABILITY_IDS)",
      "assert.deepEqual(sorted(payload.riskMap.highRisk), EXPECTED_APPROVAL_REQUIRED_CAPABILITY_IDS)",
      "registered custom-app dispatch modes preserve reviewed partitions",
      "assert.deepEqual(idsForDispatchMode(\"approvalRequiredDispatch\"), EXPECTED_APPROVAL_DISPATCH_CAPABILITY_IDS)",
      "published capability surfaces preserve reviewed blocked and metadata-only partitions",
      "idsForSurfaceRef(\"relay\", \"relay.remote.custom_app_sdk metadata-only contract projection\")",
      "available SDK surface bindings do not advertise future facades",
      "available surface refs are concrete rather than conditional placeholders",
      "conditionalRefPattern",
      "registered custom-app dispatch modes are explicit",
      "assert.notEqual(capability.dispatch.mode, \"unknown\"",
      "custom-app SDK inspection payload exposes dispatch availability and gaps",
      "custom-app SDK inspection payload exposes complete resolved surfaces",
      "assert.equal(Boolean(surface.ref), true",
      "assert.equal(surface.ref, undefined",
      "payload.executionBoundary.executesCapabilityCalls",
      "custom-app DB query schema rejects collection creation",
      "system.telemetry.snapshot",
      "system.telemetry.history",
      "resources.list",
      "jobs.list",
      "jobs.get",
      "jobs.events",
      "jobs.start",
      "jobs.cancel",
      "custom-app Relay coverage is metadata-only for local host execution",
      "relay.remote.custom_app_sdk metadata-only contract projection",
    ],
    "packages/clawjs/src/inspect-cli.test.ts": [
      "runCli exposes custom app SDK read contracts through inspect",
      "custom-app-sdk",
      "payload.executionBoundary.executesCapabilityCalls",
      "assertCompleteResolvedSurfaces(payload.capabilities)",
    ],
    "packages/clawjs-mcp/src/custom-app-sdk-contract.test.ts": [
      "MCP custom app SDK contract boundary",
      "clawjs.custom_app_sdk",
      "payload.executionBoundary.executesCapabilityCalls",
      "assertCompleteResolvedSurfaces(payload.capabilities)",
      "assertCompleteResolvedSurfaces(rpc.json().result.content.capabilities)",
    ],
    "runtime/tests/e2e/runtime.e2e.test.ts": [
      "runtime service API exposes custom app SDK contracts as read-only metadata",
      "runtime custom app SDK contract route does not execute DB or Search calls",
      "contracts/custom-app-sdk",
      "assertCompleteResolvedSurfaces(payload.capabilities)",
      "jobs start, events, detail, and cancel contracts round-trip through runtime API",
      "ctx.runtimeClient.startJob",
      "ctx.runtimeClient.cancelJob",
    ],
    "packages/clawjs-runtime/src/app.ts": [
      "runtime/jobs/start",
      "runtime/jobs/:id/cancel",
      "runtime/jobs/events",
    ],
    "packages/clawjs-runtime/src/store.ts": [
      "runtime_job_events",
      "recordJobEvent",
      "cancelJob",
    ],
    "packages/clawjs-runtime/src/client.ts": [
      "startJob(input: RuntimeJobStartInput)",
      "cancelJob(id: string",
      "listJobEvents",
    ],
    "relay/src/server/remote-sync-routes.test.ts": [
      "relay exposes custom app SDK dispatch metadata as remote-safe contract projection",
      "/v1/remote/custom-app-sdk",
      "relay.remote.custom_app_sdk",
      "assertCompleteResolvedSurfaces(payload.capabilities)",
    ],
    "packages/clawjs-core/src/network-control-plane.ts": [
      "networkPolicyEvaluationSchema",
      "evaluateGatewayNetworkAccess",
      "createNetworkEvent",
      "createNetworkRuleSuggestion",
    ],
    "packages/clawjs-core/src/network-control-plane.test.ts": [
      "Network policy evaluation matches gateway routes and redacts by default",
      "Network events and rule suggestions keep detailed fields opt-in",
      "Network access manifests and CLI registry expose the framework portal",
    ],
    "packages/clawjs/src/cli-network-command.test.ts": [
      "network CLI records Monitor-backed events and keeps details redacted unless opted in",
      "network CLI applies rules to Gateway route explanations and suggestions never auto-apply",
    ],
  })) {
    for (const snippet of snippets) requireSiblingSnippet(siblingRoot, relativePath, snippet);
  }

  const siblingCatalog = readFrom(siblingRoot, "packages/clawjs-core/src/capability-catalog.ts");
  for (const snippet of [
    "future search facade",
    "future db facade",
    "future actions facade",
    "future mac facade",
    "remote-safe when classified",
    "remote-safe only when classified",
    "local-only unless explicitly classified",
    "MCP tools when policy grants allow",
  ]) {
    assert(!siblingCatalog.includes(snippet), `clawjs:packages/clawjs-core/src/capability-catalog.ts must not contain ${JSON.stringify(snippet)}`);
  }
  assert(
    !siblingCatalog.includes('mode: capability.customAppAccess === "blocked" ? "blocked" : "unknown"'),
    "clawjs:packages/clawjs-core/src/capability-catalog.ts must not contain stale unknown dispatch fallback",
  );
  assert(
    !siblingCatalog.includes('reason: "No custom-app dispatcher is registered for this capability."'),
    "clawjs:packages/clawjs-core/src/capability-catalog.ts must not contain stale unclassified dispatch reason",
  );
}

assertCompletionAudit();
assertPublicRouting();
assertExternalValidationArtifacts();
assertRuntimeArtifacts();
assertTests();
assertSiblingClawJSArtifacts();

if (errors.length > 0) {
  console.error(`SDK-first custom surfaces verifier failed with ${errors.length} issue(s):`);
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("SDK-first custom surfaces verifier passed; goal remains active until closure blockers are resolved.");
