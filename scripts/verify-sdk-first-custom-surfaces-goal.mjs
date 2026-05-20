#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

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

function requireSiblingSnippet(siblingRoot, relativePath, snippet) {
  const text = readFrom(siblingRoot, relativePath);
  assert(text.includes(snippet), `clawjs:${relativePath}: missing ${JSON.stringify(snippet)}`);
}

function assertCompletionAudit() {
  const text = read("docs/sdk-first-custom-surfaces-completion-audit.md");
  for (const snippet of [
    "Source conversation: `019e403c-3837-7f02-9b78-532c43cdd997`",
    "Status: `active_goal_not_complete`",
    "private source session path is",
    "also inspects",
    "private source-session verifier has re-read",
    "24 decision prompt ids",
    "three interrupted unanswered ids",
    "The Clawix verifier inspects sibling ClawJS evidence when that checkout is present.",
    "The Network Control Plane now adds a typed executable route-family example",
    "Clawix `NetworkControlBridge` projection through `system/network`",
    "Clawix now mirrors the ClawJS `system.telemetry.snapshot` and `system.telemetry.history` local-wide read contracts",
    "Clawix `window.clawix.capabilities` now mirrors the ClawJS SDK facade shape",
    "`list`, `get`, `riskMap`, and `source`",
    "`window.clawix.system.telemetry`",
    "`SystemTelemetryBridge.localStatusBridge`",
    "Clawix exposes `resources.list` as its own local-wide registered-resource catalog read",
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
    "launched `/Applications/Clawix.app` under Instruments",
    "raw trace artifacts private because they contain local environment details",
    "Complete real signed-app UI/Instruments performance evidence is missing.",
    "| CLX-SDK-009 | Unanswered `data_access_lock`, `custom_collections`, and `cli_escape_hatch`",
    "| CLX-SDK-010 | Final decision-by-decision source-session audit",
    "VALIDATED PRIVATE",
    "Do not call `update_goal`",
  ]) {
    assert(text.includes(snippet), `docs/sdk-first-custom-surfaces-completion-audit.md: missing ${JSON.stringify(snippet)}`);
  }
  const rowIds = text.match(/\| CLX-SDK-\d{3} \|/g) ?? [];
  assert(rowIds.length === 10, "docs/sdk-first-custom-surfaces-completion-audit.md: must contain exactly CLX-SDK-001 through CLX-SDK-010");
  assert(!text.includes("/Users/"), "docs/sdk-first-custom-surfaces-completion-audit.md: must not publish private filesystem paths");
  for (const [rowId, status] of [
    ["CLX-SDK-004", "EXTERNAL PENDING"],
    ["CLX-SDK-005", "VALIDATED LOCAL"],
    ["CLX-SDK-006", "VALIDATED LOCAL"],
    ["CLX-SDK-007", "VALIDATED LOCAL"],
    ["CLX-SDK-008", "EXTERNAL PENDING"],
    ["CLX-SDK-010", "VALIDATED PRIVATE"],
  ]) {
    const pattern = new RegExp(`\\|\\s*${rowId}\\s*\\|[^\\n]*\\|\\s*${status}\\s*\\|`);
    assert(pattern.test(text), `docs/sdk-first-custom-surfaces-completion-audit.md: ${rowId} must remain ${status}`);
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
    "docs/sdk-first-custom-surfaces-plan.md": [
      "metadata-only `executionBoundary`",
      "`clawix.capabilities.contracts()` exposes `executionBoundary`",
      "`window.clawix.capabilities` mirrors the shared SDK facade shape",
      "stdout `render` message",
      "Direct SQLite is not exposed as a custom-app action surface.",
      "Installed-app smoke verified that a local `database/tasks` variant default",
      "Installed-app smoke verified the signed bundled Swift surface runner",
      "Installed-app Time Profiler smoke",
      "signed app launch and attach capture paths",
      "delayed-heavy-surface",
      "`system.telemetry.snapshot` and `system.telemetry.history` are mirrored as",
      "`resources.list` and `resources.read` are separate local-wide capabilities",
      "`mac.action.plan` is exposed to Web custom apps through",
      "`iot.device.action.invoke` is exposed to Web custom apps through",
      "`actions.invoke` and `secrets.broker` are exposed to Web custom apps through",
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
      "The installed app launched under Instruments for a 30 second Time Profiler",
      "A local Web custom app route opened through the sidebar.",
      "A local Swift declarative app route opened through the sidebar.",
      "`SidebarView.makeSnapshot` stayed around 2.65-2.80 ms",
      "`SidebarView.makeSnapshot` around 2.40 ms in the startup window",
      "A custom surface timeout appeared after a route/scroll transition.",
      "`CLX-SDK-008` remains `EXTERNAL PENDING`",
    ],
    "docs/decision-map.md": [
      "docs/sdk-first-custom-surfaces-completion-audit.md",
      "scripts/verify-sdk-first-custom-surfaces-goal.mjs",
      "`window.clawix` host bridge",
    ],
    "docs/discoverability.registry.json": [
      "docs/sdk-first-custom-surfaces-completion-audit.md",
      "scripts/verify-sdk-first-custom-surfaces-goal.mjs",
      "custom app SDK executionBoundary",
    ],
    "docs/discoverability.md": [
      "sdk-first-custom-surfaces-completion-audit",
      "verify-sdk-first-custom-surfaces-goal",
    ],
  })) {
    for (const snippet of snippets) requireSnippet(relativePath, snippet);
  }
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
      "\"EXTERNAL PENDING\"",
      "systemTelemetrySnapshotSchemaRef",
      "system.telemetry.snapshot",
      "system.telemetry.history",
      "resourcesListSchemaRef",
      "resources.list",
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
}

function assertTests() {
  for (const [relativePath, snippets] of Object.entries({
    "macos/Tests/ClawixMeshTests/AppCustomSurfaceCapabilityTests.swift": [
      "testHostBridgeExposesCustomAppSDKContractPayload",
      "testSwiftSurfaceResourceListExecutesThroughRegisteredResources",
      "testInjectedAppsSdkExposesMacPlanOnlyFacade",
      "testInjectedAppsSdkExposesIoTActionFacade",
      "testInjectedAppsSdkExposesActionsAndSecretsBrokerFacades",
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
    ],
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
    "docs/sdk-first-custom-surfaces-plan.md": [
      "Expose `executionBoundary` in the shared custom-app SDK inspection payload",
      "Custom-app SDK inspection exposes `executionBoundary` across CLI/API/MCP/",
      "Sibling Clawix mirrors the ClawJS capability facade shape",
      "Sibling Clawix exposes `mac.action.plan` through",
      "Sibling Clawix exposes `iot.device.action.invoke` through",
      "Sibling Clawix exposes `actions.invoke` and `secrets.broker` through",
    ],
    "docs/decision-map.md": [
      "packages/clawjs-core/src/custom-app-sdk-inspection.ts",
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
      "@clawjs/claw:system.telemetry.snapshot",
      "@clawjs/claw:system.telemetry.history",
    ],
    "packages/clawjs-core/src/capability-catalog.test.ts": [
      "custom-app SDK inspection payload exposes dispatch availability and gaps",
      "payload.executionBoundary.executesCapabilityCalls",
      "custom-app DB query schema rejects collection creation",
      "system.telemetry.snapshot",
      "system.telemetry.history",
      "resources.list",
    ],
    "packages/clawjs-mcp/src/custom-app-sdk-contract.test.ts": [
      "MCP custom app SDK contract boundary",
      "clawjs.custom_app_sdk",
      "payload.executionBoundary.executesCapabilityCalls",
    ],
    "runtime/tests/e2e/runtime.e2e.test.ts": [
      "runtime service API exposes custom app SDK contracts as read-only metadata",
      "runtime custom app SDK contract route does not execute DB or Search calls",
      "contracts/custom-app-sdk",
    ],
    "relay/src/server/remote-sync-routes.test.ts": [
      "relay exposes custom app SDK dispatch metadata as remote-safe contract projection",
      "/v1/remote/custom-app-sdk",
      "relay.remote.custom_app_sdk",
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
}

assertCompletionAudit();
assertPublicRouting();
assertRuntimeArtifacts();
assertTests();
assertSiblingClawJSArtifacts();

if (errors.length > 0) {
  console.error(`SDK-first custom surfaces verifier failed with ${errors.length} issue(s):`);
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("SDK-first custom surfaces verifier passed; goal remains active until closure blockers are resolved.");
