#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const registryPath = "docs/ui/ux-trace-harness.registry.json";
const evidenceSchemaPath = "docs/ui/ux-trace-evidence.schema.json";
const scenariosPath = "docs/ui/ux-trace-scenarios.manifest.json";
const calibrationPath = "docs/ui/ux-trace-calibration.manifest.json";
const uiReadmePath = "docs/ui/README.md";
const uiPerformanceSkillPath = "skills/ui-performance-budget/SKILL.md";
const runnerPath = "scripts/run_macos_ux_trace_harness.mjs";
const evidenceVerifierPath = "scripts/verify_macos_ux_trace_evidence.mjs";
const fixtureGeneratorPath = "scripts/generate_macos_ux_trace_fixtures.mjs";
const fixtureVerificationPath = "scripts/scale_lab_fixture_check.mjs";
const clxControlModifierPath = "macos/Sources/Clawix/AgentControl/ClxControlModifier.swift";
const clxControlRegistryPath = "macos/Sources/Clawix/AgentControl/ClxControlRegistry.swift";
const clxAgentInstancePath = "macos/Sources/Clawix/AgentControl/ClxAgentInstance.swift";
const clxControlHandlersPath = "macos/Sources/Clawix/AgentControl/ClxControlHandlers.swift";
const errors = [];
const runnerSource = fs.existsSync(path.join(rootDir, runnerPath))
  ? fs.readFileSync(path.join(rootDir, runnerPath), "utf8")
  : "";
const evidenceVerifierSource = fs.existsSync(path.join(rootDir, evidenceVerifierPath))
  ? fs.readFileSync(path.join(rootDir, evidenceVerifierPath), "utf8")
  : "";
const fixtureGeneratorSource = fs.existsSync(path.join(rootDir, fixtureGeneratorPath))
  ? fs.readFileSync(path.join(rootDir, fixtureGeneratorPath), "utf8")
  : "";
const fixtureVerificationSource = fs.existsSync(path.join(rootDir, fixtureVerificationPath))
  ? fs.readFileSync(path.join(rootDir, fixtureVerificationPath), "utf8")
  : "";
const clxControlModifierSource = fs.existsSync(path.join(rootDir, clxControlModifierPath))
  ? fs.readFileSync(path.join(rootDir, clxControlModifierPath), "utf8")
  : "";
const clxControlRegistrySource = fs.existsSync(path.join(rootDir, clxControlRegistryPath))
  ? fs.readFileSync(path.join(rootDir, clxControlRegistryPath), "utf8")
  : "";
const clxAgentInstanceSource = fs.existsSync(path.join(rootDir, clxAgentInstancePath))
  ? fs.readFileSync(path.join(rootDir, clxAgentInstancePath), "utf8")
  : "";
const clxControlHandlersSource = fs.existsSync(path.join(rootDir, clxControlHandlersPath))
  ? fs.readFileSync(path.join(rootDir, clxControlHandlersPath), "utf8")
  : "";
const uiReadmeSource = fs.existsSync(path.join(rootDir, uiReadmePath))
  ? fs.readFileSync(path.join(rootDir, uiReadmePath), "utf8")
  : "";
const uiPerformanceSkillSource = fs.existsSync(path.join(rootDir, uiPerformanceSkillPath))
  ? fs.readFileSync(path.join(rootDir, uiPerformanceSkillPath), "utf8")
  : "";

const privatePathPattern = /(?:\/Users\/|\.signing\.env|Team ID|signing identity|bundle id|source session|rollout-|\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b)/iu;

function fail(message) {
  errors.push(message);
}

function readJson(relativePath) {
  const absolutePath = path.join(rootDir, relativePath);
  if (!fs.existsSync(absolutePath)) {
    fail(`missing ${relativePath}`);
    return null;
  }
  try {
    return JSON.parse(fs.readFileSync(absolutePath, "utf8"));
  } catch (error) {
    fail(`${relativePath} is not valid JSON: ${error.message}`);
    return null;
  }
}

function requireObject(value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail(`${label} must be an object`);
    return {};
  }
  return value;
}

function requireArray(value, label, minimum = 1) {
  if (!Array.isArray(value)) {
    fail(`${label} must be an array`);
    return [];
  }
  if (value.length < minimum) {
    fail(`${label} must contain at least ${minimum} item(s)`);
  }
  return value;
}

function requireFields(object, label, fields) {
  for (const field of fields) {
    if (object?.[field] === undefined || object?.[field] === null || object?.[field] === "") {
      fail(`${label} is missing ${field}`);
    }
  }
}

function requireUniqueStringArray(values, label, expected = []) {
  const seen = new Set();
  for (const value of values) {
    if (typeof value !== "string" || value.length === 0) {
      fail(`${label} must contain only non-empty strings`);
      continue;
    }
    if (seen.has(value)) fail(`${label} duplicates ${value}`);
    seen.add(value);
  }
  for (const value of expected) {
    if (!seen.has(value)) fail(`${label} is missing ${value}`);
  }
  return seen;
}

function requireRecordIds(records, label, expected = []) {
  const ids = [];
  for (const [index, record] of records.entries()) {
    requireObject(record, `${label}[${index}]`);
    if (typeof record?.id !== "string" || record.id.length === 0) {
      fail(`${label}[${index}] is missing id`);
    } else {
      ids.push(record.id);
    }
  }
  return requireUniqueStringArray(ids, `${label}.id`, expected);
}

function rejectPrivateText(relativePath, value) {
  const serialized = JSON.stringify(value);
  if (privatePathPattern.test(serialized)) {
    fail(`${relativePath} must not contain private paths, source sessions, signing data, bundle identifiers, or UUID-like private references`);
  }
}

function requireSnippet(source, relativePath, snippet) {
  if (!source.includes(snippet)) fail(`${relativePath} must mention ${snippet}`);
}

const expectedP0SurfaceIds = [
  "app.shell.firstUsableWindow",
  "sidebar.container",
  "sidebar.allChats.entry",
  "sidebar.pinned.entry",
  "sidebar.projects.entry",
  "sidebar.conversationList",
  "sidebar.conversation.row",
  "sidebar.hoverTarget",
  "sidebar.selectedRow",
  "sidebar.runningIndicator",
  "chat.route.container",
  "chat.transcript.scroll",
  "chat.visibleWindow.latest",
  "chat.message.row",
  "chat.message.user",
  "chat.message.assistant",
  "chat.message.workSummary",
  "chat.streaming.placeholder",
  "chat.streaming.deltaTarget",
  "composer.input",
  "composer.sendButton",
  "composer.stopButton",
  "terminal.openControl",
  "terminal.panel",
  "app.loadingState",
  "app.errorState",
  "app.blockingOverlay",
];

const expectedTraceControlImplementationIds = [
  "app.shell.firstUsableWindow",
  "sidebar.container",
  "sidebar.allChats.entry",
  "sidebar.pinned.entry",
  "sidebar.projects.entry",
  "sidebar.conversationList",
  "sidebar.conversation.row.dynamic",
  "sidebar.runningIndicator",
  "chat.route.container",
  "chat.visibleWindow.latest",
  "chat.transcript.scroll",
  "chat.message.row",
  "chat.message.user",
  "chat.message.assistant",
  "chat.message.workSummary",
  "chat.streaming.deltaTarget",
  "composer.input",
  "composer.sendButton",
  "composer.stopButton",
  "terminal.openControl",
  "terminal.panel",
  "app.loadingState",
  "app.errorState",
  "settings.route",
  "sidebar.settings.openAccountPopover",
  "sidebar.settings.account",
  "sidebar.settings.openSettings",
  "sidebar.settings.signOut",
];

const expectedFixtureProfiles = [
  "smoke",
  "medium",
  "dense-sidebar",
  "dense-chat",
  "streaming-heavy",
  "terminal-under-load",
  "worst-case",
  "real-equivalent-private",
];

const expectedP0Kpis = [
  "p0.launch.process_to_first_window_visible_ms",
  "p0.launch.process_to_sidebar_ready_ms",
  "p0.launch.process_to_initial_chat_ready_ms",
  "p0.launch.first_usable_interaction_ms",
  "p0.launch.hitches_until_usable_count",
  "p0.launch.memory_after_usable_mb",
  "p0.launch.no_crash_no_hang",
  "p0.sidebar.first_paint_ready_ms",
  "p0.sidebar.scroll_frame_p95_ms",
  "p0.sidebar.scroll_hitch_count",
  "p0.sidebar.hover_to_highlight_ms",
  "p0.sidebar.click_to_selection_visible_ms",
  "p0.sidebar.click_to_chat_route_started_ms",
  "p0.sidebar.metadata_update_invalidated_rows_count",
  "p0.sidebar.no_full_list_rebuild_on_single_row_update",
  "p0.sidebar.selected_row_stability_px",
  "p0.chat.open_click_to_route_selected_ms",
  "p0.chat.open_click_to_transcript_visible_ms",
  "p0.chat.open_click_to_final_visible_window_ms",
  "p0.chat.latest_message_visible_ms",
  "p0.chat.visible_latest_window_count",
  "p0.chat.visible_window_no_row_by_row_buildup",
  "p0.chat.open_hitch_count",
  "p0.chat.open_frame_p95_ms",
  "p0.chat.open_memory_delta_mb",
  "p0.chat.open_database_query_count",
  "p0.chat.open_bridge_payload_bytes",
  "p0.chat.scroll_frame_p95_ms",
  "p0.chat.scroll_hitch_count",
  "p0.chat.scroll_to_bottom_ms",
  "p0.chat.bottom_anchor_stability_px",
  "p0.chat.old_page_load_request_to_visible_ms",
  "p0.chat.old_page_insert_anchor_delta_px",
  "p0.chat.old_page_insert_hitch_count",
  "p0.chat.no_scroll_jump_during_prepend",
  "p0.chat.no_lost_latest_message_after_scroll",
  "p0.chat.scrollbar_position_consistency_px",
  "p0.stream.user_message_visible_ms",
  "p0.stream.assistant_placeholder_visible_ms",
  "p0.stream.first_delta_received_to_visible_ms",
  "p0.stream.delta_batch_to_visible_p95_ms",
  "p0.stream.completion_to_final_visible_ms",
  "p0.stream.unrelated_invalidations_count",
  "p0.stream.scroll_bottom_follow_stability_px",
  "p0.stream.no_freeze_under_many_active_runs",
  "p0.composer.focus_to_caret_visible_ms",
  "p0.composer.keystroke_to_text_visible_ms",
  "p0.composer.send_click_to_user_message_visible_ms",
  "p0.composer.send_click_to_input_cleared_ms",
  "p0.composer.no_typing_hitches",
  "p0.terminal.open_under_load_ms",
  "p0.terminal.switch_back_to_chat_ms",
  "p0.terminal.output_scroll_frame_p95_ms",
  "p0.terminal.no_main_chat_freeze",
  "p0.idle.cpu_percent",
  "p0.idle.memory_slope_mb_per_min",
  "p0.idle.timer_wakeups",
  "p0.idle.no_hang",
  "p0.idle.no_unbounded_log_growth",
];

const expectedKpiFields = [
  "id",
  "priority",
  "surface",
  "userOutcome",
  "trigger",
  "completionCondition",
  "geometryCondition",
  "fixtureProfiles",
  "sampleCount",
  "coldWarmMode",
  "absoluteBudget",
  "baselineComparison",
  "regressionThreshold",
  "evidenceRequired",
  "ownerDocs",
  "failureSeverity",
  "knownExternalDependencies",
];
const requiredNonNullKpiFields = expectedKpiFields.filter((field) => field !== "absoluteBudget");

const expectedScalingDimensions = [
  "conversationCount",
  "activeConversationCount",
  "pinnedConversationCount",
  "projectCount",
  "conversationsPerProject",
  "archivedConversationCount",
  "titleLengthDistribution",
  "timestampDistribution",
  "unreadRunningErrorStates",
  "messageCountPerConversation",
  "latestMessageLength",
  "middleMessageLength",
  "oldHistoryPageCount",
  "markdownDensity",
  "codeBlockDensity",
  "tableListQuoteDensity",
  "toolActionWorkSummaryDensity",
  "streamingDeltaCount",
  "streamingDeltaByteSize",
  "attachmentMetadataCount",
  "imageFilePlaceholderCount",
  "errorRetryCancelStates",
  "sidebarRowHeightVariance",
  "searchVisibleTextVolume",
  "incrementalMetadataChurn",
  "databaseRowCount",
  "bridgePayloadBytes",
  "idleTimerPressure",
];

const expectedScenarios = [
  "startup-to-usable",
  "dense-sidebar-operation",
  "open-heavy-chat-latest-window",
  "old-history-scroll-anchor",
  "live-streaming-under-load",
  "composer-and-send",
  "terminal-under-conversation-load",
  "idle-stability",
  "settings-account-route",
];

const expectedControlBusCapabilities = [
  "snapshot",
  "state-with-frame",
  "scroll-state",
  "wait-visible",
  "wait-gone",
  "wait-enabled",
  "wait-text",
  "wait-count",
  "wait-route",
  "wait-frame-stable",
  "wait-scroll-stable",
  "wait-bottom-anchored",
  "wait-chat-final-window",
  "wait-stream-delta",
  "wait-idle",
  "measure-action",
  "flow",
];

const expectedScenarioActions = [
  "analyze-events",
  "fixture-metadata-update",
  "hover",
  "include-scenario",
  "launch",
  "measure-action",
  "measure-anchor-delta",
  "mock-send",
  "mock-stream",
  "mock-stream-complete",
  "observe",
  "sample",
  "scroll",
  "scroll-to-bottom",
  "snapshot",
  "type",
];

const expectedMeasuredActionDispatches = {
  "fixture-metadata-update": "fixture-metadata-update",
  "hover": "hover",
  "measure-action": "click",
  "measure-anchor-delta": "measure-anchor-delta",
  "mock-send": "mock-send",
  "mock-stream": "mock-stream",
  "mock-stream-complete": "mock-stream-complete",
  "scroll": "scroll",
  "scroll-to-bottom": "scroll-to-bottom",
  "snapshot": "record-anchor",
  "type": "type",
};

function runnerHasActionDispatch(action, dispatch) {
  const actionBranch = runnerSource.includes(`step.action === "${action}"`);
  if (actionBranch && dispatch === action && runnerSource.includes("return step.action")) {
    return true;
  }
  if (action === dispatch) {
    return actionBranch && runnerSource.includes(`return "${dispatch}"`);
  }
  return actionBranch && runnerSource.includes(`return "${dispatch}"`);
}

function runnerHasMeasuredAction(action) {
  return runnerSource.includes(`"${action}"`) && runnerSource.includes("return \"measure-action\"");
}

const expectedEventTypes = [
  "run.started",
  "fixture.loaded",
  "scenario.started",
  "step.started",
  "action.dispatched",
  "state.changed",
  "visual.condition.met",
  "visual.condition.timeout",
  "geometry.sample",
  "scroll.sample",
  "scroll.anchor.delta",
  "render.mark",
  "render.window",
  "render.invalidated",
  "hitch.sample",
  "resource.sample",
  "database.sample",
  "bridge.sample",
  "stream.delta.received",
  "stream.delta.visible",
  "capture.written",
  "step.completed",
  "step.failed",
  "scenario.completed",
  "run.completed",
];

const registry = readJson(registryPath);
const evidenceSchema = readJson(evidenceSchemaPath);
const scenarios = readJson(scenariosPath);
const calibration = readJson(calibrationPath);

for (const [relativePath, value] of [
  [registryPath, registry],
  [evidenceSchemaPath, evidenceSchema],
  [scenariosPath, scenarios],
  [calibrationPath, calibration],
]) {
  if (value) rejectPrivateText(relativePath, value);
}

if (registry) {
  requireFields(registry, registryPath, [
    "schemaVersion",
    "program",
    "status",
    "platform",
    "policy",
    "activationPolicy",
    "overheadContract",
    "privateBoundary",
    "requiredArtifacts",
    "traceSurfaces",
    "traceControlImplementations",
    "fixtureProfiles",
    "scalingDimensions",
    "kpis",
  ]);
  if (registry.schemaVersion !== 1) fail(`${registryPath}.schemaVersion must be 1`);
  if (registry.program !== "macos-ux-trace-harness") fail(`${registryPath}.program must be macos-ux-trace-harness`);
  if (registry.platform !== "macos") fail(`${registryPath}.platform must be macos`);
  if (registry.activationPolicy?.primaryMeasurementSurface !== "agent-control-bus") {
    fail(`${registryPath}.activationPolicy.primaryMeasurementSurface must be agent-control-bus`);
  }
  for (const field of ["computerUseDependency", "mainDatabaseTraceWrites"]) {
    if (registry.activationPolicy?.[field] !== false) fail(`${registryPath}.activationPolicy.${field} must be false`);
  }
  for (const field of ["parallelTraceIsolationRequired", "boundedTraceWriterRequired"]) {
    if (registry.activationPolicy?.[field] !== true) fail(`${registryPath}.activationPolicy.${field} must be true`);
  }
  if (!String(registry.activationPolicy?.normalAppMode ?? "").includes("high-cardinality trace buffers disabled")) {
    fail(`${registryPath}.activationPolicy.normalAppMode must explicitly disable high-cardinality trace buffers`);
  }
  if (!String(registry.activationPolicy?.harnessMode ?? "").includes("explicit agent instance")) {
    fail(`${registryPath}.activationPolicy.harnessMode must require an explicit agent instance`);
  }
  requireFields(registry.overheadContract, `${registryPath}.overheadContract`, [
    "normalAppHighCardinalityInstrumentation",
    "normalAppControlRegistration",
    "harnessEvidenceWrites",
    "harnessDisabledControlRun",
    "eventWriterBounds",
    "staticVerification",
  ]);
  if (!String(registry.overheadContract?.normalAppHighCardinalityInstrumentation ?? "").includes("CLAWIX_AGENT_INSTANCE=1")) {
    fail(`${registryPath}.overheadContract.normalAppHighCardinalityInstrumentation must name the agent-instance gate`);
  }
  if (!String(registry.overheadContract?.normalAppControlRegistration ?? "").includes("accessibilityIdentifier only")) {
    fail(`${registryPath}.overheadContract.normalAppControlRegistration must say normal app registration is accessibilityIdentifier only`);
  }
  if (!String(registry.overheadContract?.normalAppControlRegistration ?? "").includes("no frame probes")) {
    fail(`${registryPath}.overheadContract.normalAppControlRegistration must forbid normal-mode frame probes`);
  }
  if (!String(registry.overheadContract?.harnessEvidenceWrites ?? "").includes("outside the main app database")) {
    fail(`${registryPath}.overheadContract.harnessEvidenceWrites must keep evidence outside the main app database`);
  }
  if (!String(registry.overheadContract?.harnessDisabledControlRun ?? "").includes("--overhead-control <file>")) {
    fail(`${registryPath}.overheadContract.harnessDisabledControlRun must document --overhead-control <file>`);
  }
  if (!String(registry.overheadContract?.harnessDisabledControlRun ?? "").includes("external_pending_control_run")) {
    fail(`${registryPath}.overheadContract.harnessDisabledControlRun must require explicit pending status without a control run`);
  }
  if (registry.overheadContract?.eventWriterBounds?.maxEventsPerRun !== 100000) {
    fail(`${registryPath}.overheadContract.eventWriterBounds.maxEventsPerRun must be 100000`);
  }
  if (registry.overheadContract?.eventWriterBounds?.maxEventBytesPerRun !== 33554432) {
    fail(`${registryPath}.overheadContract.eventWriterBounds.maxEventBytesPerRun must be 33554432`);
  }
  requireUniqueStringArray(requireArray(registry.overheadContract?.staticVerification, `${registryPath}.overheadContract.staticVerification`, 4), `${registryPath}.overheadContract.staticVerification`, [
    "ClxControlModifier registers probes only under ClxAgentInstance.isAgent",
    "ClxAgentInstance starts the loopback control server only when CLAWIX_AGENT_INSTANCE=1",
    "run_macos_ux_trace_harness writes evidence only to the selected per-run directory",
    "run_macos_ux_trace_harness records mainDatabaseTraceWrites=false in run and suite artifacts",
    "run_macos_ux_trace_harness records overheadCalibration in run and suite artifacts",
  ]);
  if (registry.requiredArtifacts?.evidenceSchema !== evidenceSchemaPath) fail(`${registryPath}.requiredArtifacts.evidenceSchema must point to ${evidenceSchemaPath}`);
  if (registry.requiredArtifacts?.scenarioManifest !== scenariosPath) fail(`${registryPath}.requiredArtifacts.scenarioManifest must point to ${scenariosPath}`);
  if (registry.requiredArtifacts?.calibrationManifest !== calibrationPath) fail(`${registryPath}.requiredArtifacts.calibrationManifest must point to ${calibrationPath}`);
  if (registry.requiredArtifacts?.runnerCommand !== `node ${runnerPath}`) fail(`${registryPath}.requiredArtifacts.runnerCommand must be node ${runnerPath}`);
  if (registry.requiredArtifacts?.runnerSelfTestCommand !== `node ${runnerPath} --self-test`) fail(`${registryPath}.requiredArtifacts.runnerSelfTestCommand must be node ${runnerPath} --self-test`);
  if (registry.requiredArtifacts?.suiteRunnerCommand !== `node ${runnerPath} --suite p0`) fail(`${registryPath}.requiredArtifacts.suiteRunnerCommand must be node ${runnerPath} --suite p0`);
  if (registry.requiredArtifacts?.baselineCaptureCommand !== `node ${runnerPath} --write-baseline <file>`) fail(`${registryPath}.requiredArtifacts.baselineCaptureCommand must be node ${runnerPath} --write-baseline <file>`);
  if (registry.requiredArtifacts?.p0GateCommand !== `node ${runnerPath} --baseline <file> --gate p0`) fail(`${registryPath}.requiredArtifacts.p0GateCommand must be node ${runnerPath} --baseline <file> --gate p0`);
  if (registry.requiredArtifacts?.fixtureGeneratorCommand !== `node ${fixtureGeneratorPath}`) fail(`${registryPath}.requiredArtifacts.fixtureGeneratorCommand must be node ${fixtureGeneratorPath}`);
  if (registry.requiredArtifacts?.fixtureVerificationCommand !== `node ${fixtureVerificationPath}`) fail(`${registryPath}.requiredArtifacts.fixtureVerificationCommand must be node ${fixtureVerificationPath}`);
  if (registry.requiredArtifacts?.evidenceVerificationCommand !== `node ${evidenceVerifierPath} --path <run-or-suite-dir>`) fail(`${registryPath}.requiredArtifacts.evidenceVerificationCommand must be node ${evidenceVerifierPath} --path <run-or-suite-dir>`);
  if (registry.requiredArtifacts?.verificationCommand !== "node scripts/ui_ux_trace_harness_check.mjs") fail(`${registryPath}.requiredArtifacts.verificationCommand must be node scripts/ui_ux_trace_harness_check.mjs`);
  if (!fs.existsSync(path.join(rootDir, runnerPath))) fail(`${runnerPath} must exist`);
  if (!fs.existsSync(path.join(rootDir, evidenceVerifierPath))) fail(`${evidenceVerifierPath} must exist`);
  if (!fs.existsSync(path.join(rootDir, fixtureGeneratorPath))) fail(`${fixtureGeneratorPath} must exist`);
  if (!fs.existsSync(path.join(rootDir, fixtureVerificationPath))) fail(`${fixtureVerificationPath} must exist`);

  const surfaces = requireArray(registry.traceSurfaces, `${registryPath}.traceSurfaces`, expectedP0SurfaceIds.length);
  const surfaceIds = requireRecordIds(surfaces, `${registryPath}.traceSurfaces`, expectedP0SurfaceIds);
  const allKpiIds = new Set((registry.kpis ?? []).map((kpi) => kpi.id));
  for (const surface of surfaces) {
    requireFields(surface, `${registryPath}.traceSurfaces.${surface.id ?? "unknown"}`, [
      "id",
      "priority",
      "role",
      "surface",
      "visibilityContract",
      "geometryContract",
      "criticalityReason",
      "kpiRefs",
    ]);
    if (!["P0", "P1", "P2"].includes(surface.priority)) fail(`${registryPath}.traceSurfaces.${surface.id}.priority must be P0/P1/P2`);
    if (typeof surface.criticalityReason !== "string" || surface.criticalityReason.length < 20) {
      fail(`${registryPath}.traceSurfaces.${surface.id}.criticalityReason must explain product criticality`);
    }
    const surfaceKpiRefs = requireArray(surface.kpiRefs, `${registryPath}.traceSurfaces.${surface.id}.kpiRefs`);
    for (const kpiRef of surfaceKpiRefs) {
      if (!allKpiIds.has(kpiRef)) fail(`${registryPath}.traceSurfaces.${surface.id}.kpiRefs references unknown KPI ${kpiRef}`);
    }
    if (surface.priority === "P0" && !surfaceKpiRefs.some((kpiRef) => kpiRef.startsWith("p0."))) {
      fail(`${registryPath}.traceSurfaces.${surface.id}.kpiRefs must include at least one P0 KPI`);
    }
  }

  const controlImplementations = requireArray(
    registry.traceControlImplementations,
    `${registryPath}.traceControlImplementations`,
    expectedTraceControlImplementationIds.length
  );
  requireRecordIds(controlImplementations, `${registryPath}.traceControlImplementations`, expectedTraceControlImplementationIds);
  for (const implementation of controlImplementations) {
    const label = `${registryPath}.traceControlImplementations.${implementation.id ?? "unknown"}`;
    requireFields(implementation, label, ["id", "priority", "surfaceId", "sourcePath", "sourceSnippet", "coverageReason"]);
    if (!["P0", "P1", "P2"].includes(implementation.priority)) fail(`${label}.priority must be P0/P1/P2`);
    if (!surfaceIds.has(implementation.surfaceId)) fail(`${label}.surfaceId references unknown surface ${implementation.surfaceId}`);
    if (typeof implementation.sourcePath === "string" && privatePathPattern.test(implementation.sourcePath)) {
      fail(`${label}.sourcePath must be repo-relative and public`);
    }
    const sourcePath = path.join(rootDir, implementation.sourcePath ?? "");
    if (!implementation.sourcePath || !fs.existsSync(sourcePath)) {
      fail(`${label}.sourcePath does not exist: ${implementation.sourcePath}`);
      continue;
    }
    const implementationSource = fs.readFileSync(sourcePath, "utf8");
    if (!implementationSource.includes(implementation.sourceSnippet)) {
      fail(`${label}.sourceSnippet was not found in ${implementation.sourcePath}`);
    }
  }

  const fixtureProfiles = requireArray(registry.fixtureProfiles, `${registryPath}.fixtureProfiles`, expectedFixtureProfiles.length);
  const fixtureIds = requireRecordIds(fixtureProfiles, `${registryPath}.fixtureProfiles`, expectedFixtureProfiles);
  for (const profile of fixtureProfiles) {
    requireFields(profile, `${registryPath}.fixtureProfiles.${profile.id ?? "unknown"}`, ["id", "priority", "scaleIntent", "requiresCalibration"]);
    if (typeof profile.requiresCalibration !== "boolean") fail(`${registryPath}.fixtureProfiles.${profile.id}.requiresCalibration must be boolean`);
  }

  requireUniqueStringArray(requireArray(registry.scalingDimensions, `${registryPath}.scalingDimensions`, expectedScalingDimensions.length), `${registryPath}.scalingDimensions`, expectedScalingDimensions);

  const kpis = requireArray(registry.kpis, `${registryPath}.kpis`, expectedP0Kpis.length);
  const kpiIds = requireRecordIds(kpis, `${registryPath}.kpis`, expectedP0Kpis);
  if (!kpis.some((kpi) => kpi.priority === "P1")) fail(`${registryPath}.kpis must include at least one P1 KPI`);
  if (!kpis.some((kpi) => kpi.priority === "P2")) fail(`${registryPath}.kpis must include at least one P2 KPI`);
  for (const kpi of kpis) {
    requireFields(kpi, `${registryPath}.kpis.${kpi.id ?? "unknown"}`, requiredNonNullKpiFields);
    for (const field of expectedKpiFields) {
      if (!Object.hasOwn(kpi, field)) fail(`${registryPath}.kpis.${kpi.id ?? "unknown"} is missing ${field}`);
    }
    if (!["P0", "P1", "P2"].includes(kpi.priority)) fail(`${registryPath}.kpis.${kpi.id}.priority must be P0/P1/P2`);
    if (typeof kpi.userOutcome !== "string" || kpi.userOutcome.length < 30) {
      fail(`${registryPath}.kpis.${kpi.id}.userOutcome must explain the user outcome`);
    }
    if (!Number.isInteger(kpi.sampleCount) || kpi.sampleCount < 1) {
      fail(`${registryPath}.kpis.${kpi.id}.sampleCount must be a positive integer`);
    }
    if (typeof kpi.coldWarmMode !== "string" || kpi.coldWarmMode.length === 0) {
      fail(`${registryPath}.kpis.${kpi.id}.coldWarmMode must be a non-empty string`);
    }
    if (!kpi.regressionThreshold || typeof kpi.regressionThreshold !== "object" || Array.isArray(kpi.regressionThreshold)) {
      fail(`${registryPath}.kpis.${kpi.id}.regressionThreshold must be an object`);
    } else if (kpi.priority !== "P2" && !Number.isFinite(Number(kpi.regressionThreshold.maxRegressionPercent))) {
      fail(`${registryPath}.kpis.${kpi.id}.regressionThreshold.maxRegressionPercent must be numeric for P0/P1 KPIs`);
    }
    if (kpi.absoluteBudget !== null && (typeof kpi.absoluteBudget !== "object" || Array.isArray(kpi.absoluteBudget))) {
      fail(`${registryPath}.kpis.${kpi.id}.absoluteBudget must be null or an object`);
    }
    requireUniqueStringArray(requireArray(kpi.evidenceRequired, `${registryPath}.kpis.${kpi.id}.evidenceRequired`, 4), `${registryPath}.kpis.${kpi.id}.evidenceRequired`, ["run.json", "events.jsonl", "metrics.json", "baseline-comparison.json"]);
    for (const ownerDoc of requireArray(kpi.ownerDocs, `${registryPath}.kpis.${kpi.id}.ownerDocs`, 1)) {
      if (typeof ownerDoc !== "string" || !fs.existsSync(path.join(rootDir, ownerDoc))) {
        fail(`${registryPath}.kpis.${kpi.id}.ownerDocs references missing doc ${ownerDoc}`);
      }
    }
    requireUniqueStringArray(requireArray(kpi.knownExternalDependencies, `${registryPath}.kpis.${kpi.id}.knownExternalDependencies`, 0), `${registryPath}.kpis.${kpi.id}.knownExternalDependencies`);
    const expectedSeverity = kpi.priority === "P0" ? "blocking" : kpi.priority === "P1" ? "warning" : "tracked";
    if (kpi.failureSeverity !== expectedSeverity) {
      fail(`${registryPath}.kpis.${kpi.id}.failureSeverity must be ${expectedSeverity}`);
    }
    for (const profile of requireArray(kpi.fixtureProfiles, `${registryPath}.kpis.${kpi.id}.fixtureProfiles`)) {
      if (!fixtureIds.has(profile)) fail(`${registryPath}.kpis.${kpi.id}.fixtureProfiles references unknown profile ${profile}`);
    }
  }

  if (!surfaceIds.has("chat.visibleWindow.latest")) fail(`${registryPath}.traceSurfaces must include chat.visibleWindow.latest`);
  if (!kpiIds.has("p0.chat.open_click_to_final_visible_window_ms")) fail(`${registryPath}.kpis must include north-star chat final visible window KPI`);
}

if (evidenceSchema) {
  requireFields(evidenceSchema, evidenceSchemaPath, [
    "schemaVersion",
    "program",
    "status",
    "evidenceDirectoryShape",
    "suiteDirectoryShape",
    "suiteRequiredFields",
    "runRequiredFields",
    "allowedRunStatuses",
    "traceIsolationRequiredFields",
    "overheadCalibrationRequiredFields",
    "evidenceSourcesRequiredFields",
    "exitPolicyRequiredFields",
    "baselineArtifactRequiredFields",
    "metricRegistryContract",
    "metricEventReferenceContract",
    "eventLifecycleContract",
    "eventRequiredFields",
    "eventTypes",
    "metricRequiredFields",
    "failureTypes",
    "failureCorrelationContract",
    "failureStateSidecar",
    "normalizedSampleEvents",
    "privacyRequirements",
    "correlationRequirements",
  ]);
  if (evidenceSchema.schemaVersion !== 1) fail(`${evidenceSchemaPath}.schemaVersion must be 1`);
  if (evidenceSchema.program !== "macos-ux-trace-harness") fail(`${evidenceSchemaPath}.program must be macos-ux-trace-harness`);
  requireUniqueStringArray(requireArray(evidenceSchema.eventTypes, `${evidenceSchemaPath}.eventTypes`, expectedEventTypes.length), `${evidenceSchemaPath}.eventTypes`, expectedEventTypes);
  requireUniqueStringArray(requireArray(evidenceSchema.suiteDirectoryShape, `${evidenceSchemaPath}.suiteDirectoryShape`), `${evidenceSchemaPath}.suiteDirectoryShape`, ["suite.json", "suite-metrics.json", "suite-failures.json", "suite-baseline-comparison.json"]);
  requireUniqueStringArray(requireArray(evidenceSchema.evidenceDirectoryShape, `${evidenceSchemaPath}.evidenceDirectoryShape`), `${evidenceSchemaPath}.evidenceDirectoryShape`, ["logs/failure-ui-states.jsonl"]);
  requireUniqueStringArray(requireArray(evidenceSchema.suiteRequiredFields, `${evidenceSchemaPath}.suiteRequiredFields`), `${evidenceSchemaPath}.suiteRequiredFields`, ["suiteId", "suiteName", "scenarioCount", "runs", "artifactIndex", "exitPolicy", "evidenceSources", "traceIsolation", "overheadCalibration"]);
  requireUniqueStringArray(requireArray(evidenceSchema.runRequiredFields, `${evidenceSchemaPath}.runRequiredFields`), `${evidenceSchemaPath}.runRequiredFields`, ["runId", "scenarioId", "fixtureProfile", "artifactIndex", "exitPolicy", "evidenceSources", "traceIsolation", "overheadCalibration"]);
  requireUniqueStringArray(requireArray(evidenceSchema.exitPolicyRequiredFields, `${evidenceSchemaPath}.exitPolicyRequiredFields`), `${evidenceSchemaPath}.exitPolicyRequiredFields`, ["gate", "gateEnforced", "nonZeroOnStatuses", "computedExitCode", "reason"]);
  requireFields(evidenceSchema.exitPolicyContract, `${evidenceSchemaPath}.exitPolicyContract`, ["p0Gate", "dryRunWithoutGate", "allowedNonZeroStatuses"]);
  requireUniqueStringArray(requireArray(evidenceSchema.exitPolicyContract?.allowedNonZeroStatuses, `${evidenceSchemaPath}.exitPolicyContract.allowedNonZeroStatuses`), `${evidenceSchemaPath}.exitPolicyContract.allowedNonZeroStatuses`, ["FAIL", "INVALID"]);
  if (!String(evidenceSchema.exitPolicyContract?.p0Gate ?? "").includes("exit code 1")) {
    fail(`${evidenceSchemaPath}.exitPolicyContract.p0Gate must require exit code 1`);
  }
  requireFields(evidenceSchema.baselineComparisonContract, `${evidenceSchemaPath}.baselineComparisonContract`, ["baselineReferencePolicy", "suiteAggregationPolicy", "rowPolicy", "statusConsistencyPolicy", "gatePolicy", "gateFailurePolicy", "allowedStatuses", "allowedRowStatuses", "allowedReferenceKinds"]);
  if (!String(evidenceSchema.baselineComparisonContract?.baselineReferencePolicy ?? "").includes("must not store raw external baseline paths")) {
    fail(`${evidenceSchemaPath}.baselineComparisonContract.baselineReferencePolicy must forbid raw external baseline paths`);
  }
  if (!String(evidenceSchema.baselineComparisonContract?.suiteAggregationPolicy ?? "").includes("one comparison row per suite metric")) {
    fail(`${evidenceSchemaPath}.baselineComparisonContract.suiteAggregationPolicy must require suite-level metric comparison coverage`);
  }
  if (!String(evidenceSchema.baselineComparisonContract?.suiteAggregationPolicy ?? "").includes("exact aggregations of child run metrics/failures")) {
    fail(`${evidenceSchemaPath}.baselineComparisonContract.suiteAggregationPolicy must require exact child aggregation`);
  }
  if (
    !String(evidenceSchema.baselineComparisonContract?.rowPolicy ?? "").includes("reference an emitted KPI metric")
    || !String(evidenceSchema.baselineComparisonContract?.rowPolicy ?? "").includes("must match the emitted metric row")
  ) {
    fail(`${evidenceSchemaPath}.baselineComparisonContract.rowPolicy must require KPI metric row correlation`);
  }
  if (!String(evidenceSchema.baselineComparisonContract?.statusConsistencyPolicy ?? "").includes("derived from row statuses")) {
    fail(`${evidenceSchemaPath}.baselineComparisonContract.statusConsistencyPolicy must derive aggregate status from rows`);
  }
  if (!String(evidenceSchema.baselineComparisonContract?.gatePolicy ?? "").includes("numeric maxRegressionPercent")) {
    fail(`${evidenceSchemaPath}.baselineComparisonContract.gatePolicy must require a numeric gate threshold`);
  }
  if (!String(evidenceSchema.baselineComparisonContract?.gateFailurePolicy ?? "").includes("matching structured failures.json row")) {
    fail(`${evidenceSchemaPath}.baselineComparisonContract.gateFailurePolicy must require matching gate failure rows`);
  }
  requireUniqueStringArray(requireArray(evidenceSchema.baselineComparisonContract?.allowedStatuses, `${evidenceSchemaPath}.baselineComparisonContract.allowedStatuses`), `${evidenceSchemaPath}.baselineComparisonContract.allowedStatuses`, ["gate_passed", "gate_failed", "baseline_missing", "compared"]);
  requireUniqueStringArray(requireArray(evidenceSchema.baselineComparisonContract?.allowedRowStatuses, `${evidenceSchemaPath}.baselineComparisonContract.allowedRowStatuses`), `${evidenceSchemaPath}.baselineComparisonContract.allowedRowStatuses`, ["baseline_missing", "baseline_regression", "compared"]);
  requireUniqueStringArray(requireArray(evidenceSchema.baselineComparisonContract?.allowedReferenceKinds, `${evidenceSchemaPath}.baselineComparisonContract.allowedReferenceKinds`), `${evidenceSchemaPath}.baselineComparisonContract.allowedReferenceKinds`, ["relative-to-run", "external-hash-only"]);
  requireUniqueStringArray(requireArray(evidenceSchema.baselineArtifactRequiredFields, `${evidenceSchemaPath}.baselineArtifactRequiredFields`), `${evidenceSchemaPath}.baselineArtifactRequiredFields`, ["baselineVersion", "sourceEvidence", "approval", "promotionPolicy", "evidenceSources", "privateBoundary", "metrics"]);
  requireFields(evidenceSchema.baselineArtifactContract, `${evidenceSchemaPath}.baselineArtifactContract`, ["defaultApprovalStatus", "versioned", "privateEvidenceRemainsExternal", "verifierTarget", "p0Protection", "sourceEvidencePolicy"]);
  if (evidenceSchema.baselineArtifactContract?.defaultApprovalStatus !== "pending-user-approval") {
    fail(`${evidenceSchemaPath}.baselineArtifactContract.defaultApprovalStatus must be pending-user-approval`);
  }
  if (evidenceSchema.baselineArtifactContract?.versioned !== true) {
    fail(`${evidenceSchemaPath}.baselineArtifactContract.versioned must be true`);
  }
  if (!String(evidenceSchema.baselineArtifactContract?.verifierTarget ?? "").includes("baseline JSON files")) {
    fail(`${evidenceSchemaPath}.baselineArtifactContract.verifierTarget must require baseline JSON verification`);
  }
  if (
    !String(evidenceSchema.baselineArtifactContract?.sourceEvidencePolicy ?? "").includes("Run baselines require a runId")
    || !String(evidenceSchema.baselineArtifactContract?.sourceEvidencePolicy ?? "").includes("Suite baselines require a suiteId")
  ) {
    fail(`${evidenceSchemaPath}.baselineArtifactContract.sourceEvidencePolicy must bind generated baselines to run or suite source evidence`);
  }
  requireFields(evidenceSchema.metricRegistryContract, `${evidenceSchemaPath}.metricRegistryContract`, ["source", "policy", "appliesTo"]);
  if (evidenceSchema.metricRegistryContract?.source !== registryPath) {
    fail(`${evidenceSchemaPath}.metricRegistryContract.source must be ${registryPath}`);
  }
  if (
    !String(evidenceSchema.metricRegistryContract?.policy ?? "").includes("declared KPI id")
    || !String(evidenceSchema.metricRegistryContract?.policy ?? "").includes("priority and surface")
  ) {
    fail(`${evidenceSchemaPath}.metricRegistryContract.policy must bind metric rows to KPI registry priority and surface`);
  }
  requireUniqueStringArray(requireArray(evidenceSchema.metricRegistryContract?.appliesTo, `${evidenceSchemaPath}.metricRegistryContract.appliesTo`), `${evidenceSchemaPath}.metricRegistryContract.appliesTo`, ["metrics.json", "suite-metrics.json", "baseline metrics"]);
  requireFields(evidenceSchema.metricValueContract, `${evidenceSchemaPath}.metricValueContract`, ["policy", "allowedStatuses", "appliesTo"]);
  if (
    !String(evidenceSchema.metricValueContract?.policy ?? "").includes("sampleCount > 0")
    || !String(evidenceSchema.metricValueContract?.policy ?? "").includes("p50 <= p95 <= p99 <= worstSample")
    || !String(evidenceSchema.metricValueContract?.policy ?? "").includes("p50 <= p95 <= p99 <= value")
    || !String(evidenceSchema.metricValueContract?.policy ?? "").includes("missing_sample rows require sampleCount = 0")
  ) {
    fail(`${evidenceSchemaPath}.metricValueContract.policy must require internally consistent metric values`);
  }
  requireUniqueStringArray(requireArray(evidenceSchema.metricValueContract?.allowedStatuses, `${evidenceSchemaPath}.metricValueContract.allowedStatuses`), `${evidenceSchemaPath}.metricValueContract.allowedStatuses`, ["measured", "missing_sample"]);
  requireUniqueStringArray(requireArray(evidenceSchema.metricValueContract?.appliesTo, `${evidenceSchemaPath}.metricValueContract.appliesTo`), `${evidenceSchemaPath}.metricValueContract.appliesTo`, ["metrics.json", "suite-metrics.json", "baseline metrics"]);
  requireFields(evidenceSchema.metricEventReferenceContract, `${evidenceSchemaPath}.metricEventReferenceContract`, ["policy", "purpose"]);
  if (
    !String(evidenceSchema.metricEventReferenceContract?.policy ?? "").includes("same KPI id")
    || !String(evidenceSchema.metricEventReferenceContract?.purpose ?? "").includes("action/visual-condition timeline")
  ) {
    fail(`${evidenceSchemaPath}.metricEventReferenceContract must bind metric rows to KPI-specific timeline events`);
  }
  requireFields(evidenceSchema.eventLifecycleContract, `${evidenceSchemaPath}.eventLifecycleContract`, ["policy", "purpose"]);
  if (
    !String(evidenceSchema.eventLifecycleContract?.policy ?? "").includes("exactly one run.started")
    || !String(evidenceSchema.eventLifecycleContract?.policy ?? "").includes("run.completed.status must match run.json.status")
    || !String(evidenceSchema.eventLifecycleContract?.policy ?? "").includes("exactly one step.started")
    || !String(evidenceSchema.eventLifecycleContract?.policy ?? "").includes("exactly one terminal step.completed or step.failed")
  ) {
    fail(`${evidenceSchemaPath}.eventLifecycleContract must bind run lifecycle events to run status`);
  }
  requireFields(evidenceSchema.timeRangeContract, `${evidenceSchemaPath}.timeRangeContract`, ["policy", "appliesTo"]);
  if (
    !String(evidenceSchema.timeRangeContract?.policy ?? "").includes("valid ISO timestamps")
    || !String(evidenceSchema.timeRangeContract?.policy ?? "").includes("timestampWallClock values must stay within the run range")
    || !String(evidenceSchema.timeRangeContract?.policy ?? "").includes("Suite child run ranges must stay within the suite range")
  ) {
    fail(`${evidenceSchemaPath}.timeRangeContract.policy must bind run, suite, event, and child-run timestamps`);
  }
  requireUniqueStringArray(requireArray(evidenceSchema.timeRangeContract?.appliesTo, `${evidenceSchemaPath}.timeRangeContract.appliesTo`), `${evidenceSchemaPath}.timeRangeContract.appliesTo`, ["run.json", "suite.json", "events.jsonl", "suite child runs"]);
  requireFields(evidenceSchema.suiteRunsContract, `${evidenceSchemaPath}.suiteRunsContract`, ["policy", "requiredRunFields"]);
  if (
    !String(evidenceSchema.suiteRunsContract?.policy ?? "").includes("suite.json.runs must be an array")
    || !String(evidenceSchema.suiteRunsContract?.policy ?? "").includes("scenarioCount must be a non-negative integer")
    || !String(evidenceSchema.suiteRunsContract?.policy ?? "").includes("without crashing")
  ) {
    fail(`${evidenceSchemaPath}.suiteRunsContract.policy must bind suite run shape and count safely`);
  }
  requireUniqueStringArray(requireArray(evidenceSchema.suiteRunsContract?.requiredRunFields, `${evidenceSchemaPath}.suiteRunsContract.requiredRunFields`), `${evidenceSchemaPath}.suiteRunsContract.requiredRunFields`, ["runId", "scenarioId", "fixtureProfile", "status", "runDir"]);
  requireFields(evidenceSchema.instrumentationModeContract, `${evidenceSchemaPath}.instrumentationModeContract`, ["policy", "requiredFlags", "appliesTo"]);
  if (
    !String(evidenceSchema.instrumentationModeContract?.policy ?? "").includes("launchMode must be dry-run or isolated-agent-instance")
    || !String(evidenceSchema.instrumentationModeContract?.policy ?? "").includes("computerUseWitness=false")
    || !String(evidenceSchema.instrumentationModeContract?.policy ?? "").includes("mainDatabaseTraceWrites=false")
  ) {
    fail(`${evidenceSchemaPath}.instrumentationModeContract.policy must bind launchMode to control-bus/dry-run flags and forbid Computer Use/database trace writes`);
  }
  requireUniqueStringArray(requireArray(evidenceSchema.instrumentationModeContract?.requiredFlags, `${evidenceSchemaPath}.instrumentationModeContract.requiredFlags`), `${evidenceSchemaPath}.instrumentationModeContract.requiredFlags`, ["controlBus", "dryRun", "computerUseWitness", "mainDatabaseTraceWrites"]);
  requireUniqueStringArray(requireArray(evidenceSchema.instrumentationModeContract?.appliesTo, `${evidenceSchemaPath}.instrumentationModeContract.appliesTo`), `${evidenceSchemaPath}.instrumentationModeContract.appliesTo`, ["run.json", "suite.json"]);
  requireUniqueStringArray(requireArray(evidenceSchema.evidenceSourcesRequiredFields, `${evidenceSchemaPath}.evidenceSourcesRequiredFields`), `${evidenceSchemaPath}.evidenceSourcesRequiredFields`, ["registry", "scenarioManifest", "evidenceSchema", "fixtureGenerator", "evidenceVerifier"]);
  requireFields(evidenceSchema.evidenceSourcesContract, `${evidenceSchemaPath}.evidenceSourcesContract`, ["pathPolicy", "hashPolicy", "keyIdentityPolicy", "requiredSources", "requiredSourceIds"]);
  if (!String(evidenceSchema.evidenceSourcesContract?.keyIdentityPolicy ?? "").includes("not interchangeable")) {
    fail(`${evidenceSchemaPath}.evidenceSourcesContract.keyIdentityPolicy must make evidence source keys non-interchangeable`);
  }
  const expectedEvidenceSources = {
    registry: { id: "ux-trace-harness-registry", path: registryPath },
    scenarioManifest: { id: "ux-trace-scenarios-manifest", path: scenariosPath },
    evidenceSchema: { id: "ux-trace-evidence-schema", path: evidenceSchemaPath },
    fixtureGenerator: { id: "macos-ux-trace-fixture-generator", path: fixtureGeneratorPath },
    evidenceVerifier: { id: "macos-ux-trace-evidence-verifier", path: evidenceVerifierPath },
  };
  const requiredSources = requireObject(evidenceSchema.evidenceSourcesContract?.requiredSources, `${evidenceSchemaPath}.evidenceSourcesContract.requiredSources`);
  for (const [sourceKey, expectedSource] of Object.entries(expectedEvidenceSources)) {
    requireFields(requiredSources?.[sourceKey], `${evidenceSchemaPath}.evidenceSourcesContract.requiredSources.${sourceKey}`, ["id", "path"]);
    if (requiredSources?.[sourceKey]?.id !== expectedSource.id) {
      fail(`${evidenceSchemaPath}.evidenceSourcesContract.requiredSources.${sourceKey}.id must be ${expectedSource.id}`);
    }
    if (requiredSources?.[sourceKey]?.path !== expectedSource.path) {
      fail(`${evidenceSchemaPath}.evidenceSourcesContract.requiredSources.${sourceKey}.path must be ${expectedSource.path}`);
    }
  }
  requireUniqueStringArray(requireArray(evidenceSchema.evidenceSourcesContract?.requiredSourceIds, `${evidenceSchemaPath}.evidenceSourcesContract.requiredSourceIds`), `${evidenceSchemaPath}.evidenceSourcesContract.requiredSourceIds`, ["ux-trace-harness-registry", "ux-trace-scenarios-manifest", "ux-trace-evidence-schema", "macos-ux-trace-fixture-generator", "macos-ux-trace-evidence-verifier"]);
  if (!String(evidenceSchema.evidenceSourcesContract?.pathPolicy ?? "").includes("repo-relative")) {
    fail(`${evidenceSchemaPath}.evidenceSourcesContract.pathPolicy must require repo-relative paths`);
  }
  if (!String(evidenceSchema.evidenceSourcesContract?.hashPolicy ?? "").includes("sha256 content hash")) {
    fail(`${evidenceSchemaPath}.evidenceSourcesContract.hashPolicy must require sha256 content hashes`);
  }
  requireUniqueStringArray(requireArray(evidenceSchema.traceIsolationRequiredFields, `${evidenceSchemaPath}.traceIsolationRequiredFields`), `${evidenceSchemaPath}.traceIsolationRequiredFields`, ["mode", "evidenceRootHash", "globalSharedTraceFile", "mainDatabaseTraceWrites", "parallelSafe"]);
  requireFields(evidenceSchema.traceIsolationContract, `${evidenceSchemaPath}.traceIsolationContract`, ["runDirectory", "suiteDirectory", "forbidden", "externalPaths"]);
  if (
    !String(evidenceSchema.traceIsolationContract?.runDirectory ?? "").includes("evidenceRootHash must match")
    || !String(evidenceSchema.traceIsolationContract?.suiteDirectory ?? "").includes("traceIsolation.childRunDirectories")
  ) {
    fail(`${evidenceSchemaPath}.traceIsolationContract must require evidence root hash and child run directory validation`);
  }
  requireUniqueStringArray(requireArray(evidenceSchema.traceIsolationContract?.forbidden, `${evidenceSchemaPath}.traceIsolationContract.forbidden`), `${evidenceSchemaPath}.traceIsolationContract.forbidden`, ["global shared trace files", "main app database trace writes", "absolute local paths in artifact indexes", "raw external fixture paths"]);
  if (!String(evidenceSchema.traceIsolationContract?.externalPaths ?? "").includes("sha256 hashes")) {
    fail(`${evidenceSchemaPath}.traceIsolationContract.externalPaths must require hash-only external paths`);
  }
  requireUniqueStringArray(requireArray(evidenceSchema.overheadCalibrationRequiredFields, `${evidenceSchemaPath}.overheadCalibrationRequiredFields`), `${evidenceSchemaPath}.overheadCalibrationRequiredFields`, ["status", "controlRun", "instrumentationOverheadEstimate", "traceWriter"]);
  requireFields(evidenceSchema.overheadCalibrationContract, `${evidenceSchemaPath}.overheadCalibrationContract`, ["statusValues", "requiredWhenNoControlRun", "controlRunPrivacy", "statusConsistency", "traceWriterBounds"]);
  requireUniqueStringArray(requireArray(evidenceSchema.overheadCalibrationContract?.statusValues, `${evidenceSchemaPath}.overheadCalibrationContract.statusValues`), `${evidenceSchemaPath}.overheadCalibrationContract.statusValues`, ["compared", "external_pending_control_run", "control_artifact_without_comparable_metrics"]);
  if (!String(evidenceSchema.overheadCalibrationContract?.requiredWhenNoControlRun ?? "").includes("external_pending_control_run")) {
    fail(`${evidenceSchemaPath}.overheadCalibrationContract.requiredWhenNoControlRun must require external_pending_control_run`);
  }
  if (!String(evidenceSchema.overheadCalibrationContract?.controlRunPrivacy ?? "").includes("must not be written")) {
    fail(`${evidenceSchemaPath}.overheadCalibrationContract.controlRunPrivacy must forbid public local control paths`);
  }
  if (
    !String(evidenceSchema.overheadCalibrationContract?.statusConsistency ?? "").includes("external_pending_control_run requires controlRun.available=false")
    || !String(evidenceSchema.overheadCalibrationContract?.statusConsistency ?? "").includes("compared requires controlRun.available=true")
    || !String(evidenceSchema.overheadCalibrationContract?.statusConsistency ?? "").includes("highCardinalityInstrumentation=false")
  ) {
    fail(`${evidenceSchemaPath}.overheadCalibrationContract.statusConsistency must bind overhead status to control artifact state`);
  }
  if (evidenceSchema.overheadCalibrationContract?.traceWriterBounds?.maxEventsPerRun !== 100000) {
    fail(`${evidenceSchemaPath}.overheadCalibrationContract.traceWriterBounds.maxEventsPerRun must be 100000`);
  }
  requireUniqueStringArray(requireArray(evidenceSchema.eventRequiredFields, `${evidenceSchemaPath}.eventRequiredFields`), `${evidenceSchemaPath}.eventRequiredFields`, ["runId", "actionId", "surfaceId", "controlId", "kpiId", "timestampMonotonicNs"]);
  requireUniqueStringArray(requireArray(evidenceSchema.metricRequiredFields, `${evidenceSchemaPath}.metricRequiredFields`), `${evidenceSchemaPath}.metricRequiredFields`, ["kpiId", "p50", "p95", "p99", "baseline", "evidenceEventRefs"]);
  requireFields(evidenceSchema.failureCorrelationContract, `${evidenceSchemaPath}.failureCorrelationContract`, ["requiredFields", "timelinePolicy"]);
  requireUniqueStringArray(requireArray(evidenceSchema.failureCorrelationContract?.requiredFields, `${evidenceSchemaPath}.failureCorrelationContract.requiredFields`), `${evidenceSchemaPath}.failureCorrelationContract.requiredFields`, ["type", "message", "stepId", "actionId", "surfaceId", "controlId", "kpiId"]);
  if (
    !String(evidenceSchema.failureCorrelationContract?.timelinePolicy ?? "").includes("matching step.failed event")
    || !String(evidenceSchema.failureCorrelationContract?.timelinePolicy ?? "").includes("every step.failed event must include a failure object")
    || !String(evidenceSchema.failureCorrelationContract?.timelinePolicy ?? "").includes("Duplicate step.failed events")
  ) {
    fail(`${evidenceSchemaPath}.failureCorrelationContract.timelinePolicy must require matching step.failed events`);
  }
  requireFields(evidenceSchema.failureStateSidecar, `${evidenceSchemaPath}.failureStateSidecar`, ["path", "requiredWhenFinalUIStateExists", "maxControlsPerState", "maxBytesPerRun", "contentPolicy"]);
  if (evidenceSchema.failureStateSidecar?.path !== "logs/failure-ui-states.jsonl") {
    fail(`${evidenceSchemaPath}.failureStateSidecar.path must be logs/failure-ui-states.jsonl`);
  }
  if (evidenceSchema.failureStateSidecar?.requiredWhenFinalUIStateExists !== true) {
    fail(`${evidenceSchemaPath}.failureStateSidecar.requiredWhenFinalUIStateExists must be true`);
  }
  if (evidenceSchema.failureStateSidecar?.maxControlsPerState !== 200) {
    fail(`${evidenceSchemaPath}.failureStateSidecar.maxControlsPerState must be 200`);
  }
  if (evidenceSchema.failureStateSidecar?.maxBytesPerRun !== 16777216) {
    fail(`${evidenceSchemaPath}.failureStateSidecar.maxBytesPerRun must be 16777216`);
  }
  if (!String(evidenceSchema.failureStateSidecar?.contentPolicy ?? "").includes("hashes/lengths")) {
    fail(`${evidenceSchemaPath}.failureStateSidecar.contentPolicy must require hashes/lengths for readable strings`);
  }
  requireUniqueStringArray(requireArray(evidenceSchema.normalizedSampleEvents?.eventTypes, `${evidenceSchemaPath}.normalizedSampleEvents.eventTypes`), `${evidenceSchemaPath}.normalizedSampleEvents.eventTypes`, [
    "geometry.sample",
    "scroll.sample",
    "render.window",
    "hitch.sample",
    "resource.sample",
    "database.sample",
    "bridge.sample",
  ]);
  if (!String(evidenceSchema.normalizedSampleEvents?.purpose ?? "").includes("opaque payload hashes")) {
    fail(`${evidenceSchemaPath}.normalizedSampleEvents.purpose must explain why samples cannot stay only in payload hashes`);
  }
  if (!String(evidenceSchema.normalizedSampleEvents?.publicSafety ?? "").includes("numeric dimensions")) {
    fail(`${evidenceSchemaPath}.normalizedSampleEvents.publicSafety must keep samples public-safe`);
  }
  if (evidenceSchema.correlationRequirements?.dispatchSuccessIsNotVisualSuccess !== true) {
    fail(`${evidenceSchemaPath}.correlationRequirements.dispatchSuccessIsNotVisualSuccess must be true`);
  }
}

if (calibration) {
  requireFields(calibration, calibrationPath, [
    "schemaVersion",
    "program",
    "status",
    "platform",
    "policy",
    "privateAggregatePolicy",
    "syntheticProfiles",
    "externalPending",
    "verification",
  ]);
  if (calibration.schemaVersion !== 1) fail(`${calibrationPath}.schemaVersion must be 1`);
  if (calibration.program !== "macos-ux-trace-harness") fail(`${calibrationPath}.program must be macos-ux-trace-harness`);
  if (calibration.platform !== "macos") fail(`${calibrationPath}.platform must be macos`);
  if (calibration.privateAggregatePolicy?.contentExportAllowed !== false) fail(`${calibrationPath}.privateAggregatePolicy.contentExportAllowed must be false`);
  if (calibration.privateAggregatePolicy?.aggregateMetricsOnly !== true) fail(`${calibrationPath}.privateAggregatePolicy.aggregateMetricsOnly must be true`);
  if (calibration.privateAggregatePolicy?.approvalRequiredBeforeStrictCalibration !== true) fail(`${calibrationPath}.privateAggregatePolicy.approvalRequiredBeforeStrictCalibration must be true`);
  const calibrationProfiles = requireArray(calibration.syntheticProfiles, `${calibrationPath}.syntheticProfiles`, expectedFixtureProfiles.length);
  const calibrationProfileIds = requireRecordIds(calibrationProfiles, `${calibrationPath}.syntheticProfiles`, expectedFixtureProfiles);
  for (const profile of calibrationProfiles) {
    requireFields(profile, `${calibrationPath}.syntheticProfiles.${profile.id ?? "unknown"}`, ["id", "status", "calibrationRole", "baselineAlias", "approvalStatus"]);
    if (typeof profile.baselineAlias !== "string" || !profile.baselineAlias.startsWith("external-ui-baselines:")) {
      fail(`${calibrationPath}.syntheticProfiles.${profile.id}.baselineAlias must use external-ui-baselines alias`);
    }
  }
  const externalPending = requireArray(calibration.externalPending, `${calibrationPath}.externalPending`, 1);
  if (!externalPending.some((entry) => entry.status === "EXTERNAL PENDING" && entry.id === "private-real-mode-aggregate-comparison")) {
    fail(`${calibrationPath}.externalPending must record private-real-mode-aggregate-comparison as EXTERNAL PENDING`);
  }
  if (calibration.verification?.publicContractCheck !== "node scripts/ui_ux_trace_harness_check.mjs") {
    fail(`${calibrationPath}.verification.publicContractCheck must be node scripts/ui_ux_trace_harness_check.mjs`);
  }
  if (calibration.verification?.privateApprovalRequiredForCompletion !== true) {
    fail(`${calibrationPath}.verification.privateApprovalRequiredForCompletion must be true`);
  }
  if (!calibrationProfileIds.has("real-equivalent-private")) fail(`${calibrationPath}.syntheticProfiles must include real-equivalent-private`);
}

if (scenarios) {
  requireFields(scenarios, scenariosPath, [
    "schemaVersion",
    "program",
    "status",
    "platform",
    "runnerContract",
    "requiredControlBusCapabilities",
    "scenarios",
  ]);
  if (scenarios.schemaVersion !== 1) fail(`${scenariosPath}.schemaVersion must be 1`);
  if (scenarios.program !== "macos-ux-trace-harness") fail(`${scenariosPath}.program must be macos-ux-trace-harness`);
  if (scenarios.platform !== "macos") fail(`${scenariosPath}.platform must be macos`);
  if (scenarios.runnerContract?.primaryMeasurementSurface !== "agent-control-bus") fail(`${scenariosPath}.runnerContract.primaryMeasurementSurface must be agent-control-bus`);
  if (scenarios.runnerContract?.computerUseAllowedAsWitnessOnly !== true) fail(`${scenariosPath}.runnerContract.computerUseAllowedAsWitnessOnly must be true`);
  for (const field of ["forbidsRealPrompts", "forbidsPaidServices", "forbidsMainDatabaseTraceWrites", "requiresPerInstanceTraceIsolation"]) {
    if (scenarios.runnerContract?.[field] !== true) fail(`${scenariosPath}.runnerContract.${field} must be true`);
  }
  requireUniqueStringArray(requireArray(scenarios.requiredControlBusCapabilities, `${scenariosPath}.requiredControlBusCapabilities`, expectedControlBusCapabilities.length), `${scenariosPath}.requiredControlBusCapabilities`, expectedControlBusCapabilities);
  if (!clxControlHandlersSource) fail(`${clxControlHandlersPath} must exist for control-bus verb verification`);
  for (const capability of expectedControlBusCapabilities) {
    if (!clxControlHandlersSource.includes(`case "${capability}"`)) {
      fail(`${clxControlHandlersPath} must implement declared control-bus capability ${capability}`);
    }
  }
  const scenarioRecords = requireArray(scenarios.scenarios, `${scenariosPath}.scenarios`, expectedScenarios.length);
  const scenarioIds = requireRecordIds(scenarioRecords, `${scenariosPath}.scenarios`, expectedScenarios);
  const registryKpiIds = new Set((registry?.kpis ?? []).map((kpi) => kpi.id));
  const registryFixtureIds = new Set((registry?.fixtureProfiles ?? []).map((profile) => profile.id));
  const registrySurfaceIds = new Set((registry?.traceSurfaces ?? []).map((surface) => surface.id));
  const scenarioActions = new Set();
  for (const scenario of scenarioRecords) {
    requireFields(scenario, `${scenariosPath}.scenarios.${scenario.id ?? "unknown"}`, ["id", "priority", "fixtureProfiles", "kpiRefs", "steps"]);
    for (const profile of requireArray(scenario.fixtureProfiles, `${scenariosPath}.scenarios.${scenario.id}.fixtureProfiles`)) {
      if (!registryFixtureIds.has(profile)) fail(`${scenariosPath}.scenarios.${scenario.id}.fixtureProfiles references unknown profile ${profile}`);
    }
    for (const kpiRef of requireArray(scenario.kpiRefs, `${scenariosPath}.scenarios.${scenario.id}.kpiRefs`)) {
      if (!registryKpiIds.has(kpiRef)) fail(`${scenariosPath}.scenarios.${scenario.id}.kpiRefs references unknown KPI ${kpiRef}`);
    }
    const steps = requireArray(scenario.steps, `${scenariosPath}.scenarios.${scenario.id}.steps`);
    requireRecordIds(steps, `${scenariosPath}.scenarios.${scenario.id}.steps`);
    for (const step of steps) {
      requireFields(step, `${scenariosPath}.scenarios.${scenario.id}.steps.${step.id ?? "unknown"}`, ["id", "action", "wait", "target"]);
      scenarioActions.add(step.action);
      if (step.action !== "include-scenario" && !registrySurfaceIds.has(step.target)) {
        fail(`${scenariosPath}.scenarios.${scenario.id}.steps.${step.id}.target references unknown trace surface ${step.target}`);
      }
      if (step.action === "include-scenario" && !scenarioIds.has(step.target)) {
        fail(`${scenariosPath}.scenarios.${scenario.id}.steps.${step.id}.target references unknown scenario ${step.target}`);
      }
    }
  }
  requireUniqueStringArray([...scenarioActions].sort(), `${scenariosPath}.scenarioActions`, expectedScenarioActions);
  const chatFinalWindowSteps = scenarioRecords.flatMap((scenario) =>
    (scenario.steps || [])
      .filter((step) => step.wait === "wait-chat-final-window" && step.action !== "include-scenario")
      .map((step) => ({ scenarioId: scenario.id, step }))
  );
  for (const { scenarioId, step } of chatFinalWindowSteps) {
    if (!Number.isInteger(step.minVisibleMessages) || step.minVisibleMessages < 1) {
      fail(`${scenariosPath}.scenarios.${scenarioId}.steps.${step.id}.minVisibleMessages must be a positive integer for wait-chat-final-window`);
    }
  }
  for (const [action, dispatch] of Object.entries(expectedMeasuredActionDispatches)) {
    if (!runnerHasActionDispatch(action, dispatch)) {
      fail(`${runnerPath} must dispatch scenario action ${action} as control action ${dispatch}`);
    }
    if (!runnerHasMeasuredAction(action)) {
      fail(`${runnerPath} must route scenario action ${action} through measure-action`);
    }
  }
  for (const scenario of scenarioRecords) {
    for (const step of scenario.steps || []) {
      if (
        step.action !== "include-scenario"
        && !expectedMeasuredActionDispatches[step.action]
        && !(typeof step.wait === "string" && step.wait.startsWith("wait-"))
      ) {
        fail(`${scenariosPath}.scenarios.${scenario.id}.steps.${step.id}.action ${step.action} has no runner verb contract`);
      }
    }
  }
}

for (const [relativePath, source] of [
  [clxControlModifierPath, clxControlModifierSource],
  [clxControlRegistryPath, clxControlRegistrySource],
  [clxAgentInstancePath, clxAgentInstanceSource],
]) {
  if (!source) fail(`${relativePath} must exist for UX trace overhead verification`);
}

if (clxControlModifierSource) {
  for (const snippet of [
    "accessibilityIdentifier(id)",
    "if ClxAgentInstance.isAgent",
    ".background(",
    "ClxControlFrameProbe(id: id, token: registrationToken)",
    "} else {\n                content\n            }",
  ]) {
    requireSnippet(clxControlModifierSource, clxControlModifierPath, snippet);
  }
}

if (clxControlRegistrySource) {
  const agentGuards = (clxControlRegistrySource.match(/guard ClxAgentInstance\.isAgent else \{ return \}/g) || []).length;
  if (agentGuards < 5) {
    fail(`${clxControlRegistryPath} must guard high-cardinality registries with ClxAgentInstance.isAgent`);
  }
  for (const snippet of [
    "Only ever\n/// populated in agent instances; inert in normal user builds.",
    "func upsertObservedView",
    "func observedViewState",
    "func upsert(_ scrollView: NSScrollView, id: String)",
    "func upsert(scrollView: NSScrollView, id: String, triggerTop: @escaping () -> Void)",
  ]) {
    requireSnippet(clxControlRegistrySource, clxControlRegistryPath, snippet);
  }
}

if (clxAgentInstanceSource) {
  for (const snippet of [
    "ProcessInfo.processInfo.environment[\"CLAWIX_AGENT_INSTANCE\"] == \"1\"",
    "if arg == \"--clawix-agent-instance\"",
    "setenv(\"CLAWIX_AGENT_INSTANCE\", \"1\", 1)",
    "guard isAgent else { return }",
    "let server = ClxControlServer(port: port, token: token)",
  ]) {
    requireSnippet(clxAgentInstanceSource, clxAgentInstancePath, snippet);
  }
}

if (clxControlHandlersSource) {
  for (const snippet of [
    "case \"snapshot\":  return snapshot(args)",
    "static func snapshot(_ args: [String: Any]) -> ClxControlResult",
    "let maxControls = boundedInt(args[\"maxControls\"]",
    "state[\"scrollState\"] = registeredScrollState(id: id) ?? [:]",
    "if let selected = ClxAX.bool(element, kAXSelectedAttribute) { out[\"selected\"] = selected }",
    "ChatVisibleWindowRenderLog.latestPayload(",
    "let minVisibleMessages = boundedInt(args[\"minVisibleMessages\"]",
    "finalUIStatePayload(actionArgs: actionArgs, waitArgs: waitArgs)",
    "out[\"failureReason\"] = \"visual_condition_failed\"",
    "\"maxControls\": 200",
  ]) {
    requireSnippet(clxControlHandlersSource, clxControlHandlersPath, snippet);
  }
}

if (runnerSource) {
  for (const snippet of [
    "const maxEvidenceEventsPerRun = 100_000",
    "const maxEvidenceEventBytesPerRun = 32 * 1024 * 1024",
    "UX trace event writer exceeded",
    "path.join(os.tmpdir(), \"clawix-ux-trace-runs\")",
    "mainDatabaseTraceWrites: false",
    "body.minVisibleMessages = step.minVisibleMessages",
    "const maxFailureUIStateBytesPerRun = 16 * 1024 * 1024",
    "function sanitizeFailureUIState(",
    "logs/failure-ui-states.jsonl",
    "artifactKind: \"redacted-final-ui-state\"",
    "finalUIStateHash: finalUIStateRef?.hash ?? null",
    "finalUIStateRef: finalUIStateRef?.ref ?? null",
    "function emitPayloadSamples(",
    "eventType: \"geometry.sample\"",
    "eventType: \"scroll.sample\"",
    "eventType: \"render.window\"",
    "eventType: \"hitch.sample\"",
    "eventType: \"resource.sample\"",
    "eventType: \"database.sample\"",
    "eventType: \"bridge.sample\"",
    "eventRefsByKpi",
    "eventRefsForKpi(kpiId)",
    "actionId,",
    "controlId: step.target",
    "function traceIsolationForRun(",
    "function evidenceSourceReferences(",
    "function exitPolicyForRun(",
    "function baselineReferenceForRun(",
    "function baselineComparisonsFromMetrics(",
    "baselineReference: baselineReferenceForRun(runDir, args.baseline)",
    "writeJson(path.join(suiteDir, \"suite-baseline-comparison.json\"), suiteBaselineComparison)",
    "baselineComparisonPath: path.join(suiteRunDirs[index], \"baseline-comparison.json\")",
    "verifyEvidencePath(baselinePath)",
    "approval: {",
    "status: \"pending-user-approval\"",
    "lowerPriorityOptimizationMayUpdateP0: false",
    "computedExitCode: nonZeroOnStatuses.includes(status) ? 1 : 0",
    "process.exitCode = result.exitPolicy?.computedExitCode ?? 0",
    "self-test gated dry-run with missing P0 baseline must exit 1",
    "scenarioManifest: contractSourceReference(\"ux-trace-scenarios-manifest\"",
    "evidenceSources: evidenceSourceReferences()",
    "traceIsolation: traceIsolationForRun(",
    "traceIsolation: traceIsolationForSuite(",
    "overheadCalibrationForRun(",
    "overheadCalibrationForSuite(",
    "external_pending_control_run",
    "--overhead-control <file>",
    "globalSharedTraceFile: false",
    "parallelSafe: true",
    "publicPathReference(runDir, fixturePack.path)",
    "verifyEvidencePath(result.runDir)",
    "verifyEvidencePath(suiteResult.suiteDir)",
  ]) {
    requireSnippet(runnerSource, runnerPath, snippet);
  }
  if (runnerSource.includes("ClawixPersistentSurfacePaths") || runnerSource.includes("GRDB") || runnerSource.includes("sqlite")) {
    fail(`${runnerPath} must not write UX trace evidence through the main app database path`);
  }
}

if (evidenceVerifierSource) {
  for (const snippet of [
    "schema.runRequiredFields",
    "schema.suiteRequiredFields",
    "schema.eventRequiredFields",
    "schema.metricRequiredFields",
    "logs/failure-ui-states.jsonl",
    "finalUIStateRef points to missing sidecar row",
    "capture.written",
    "sampleCounts",
    "validateTimeRange(",
    "timestampWallClock must not be before run.json.startedAt",
    "timestampWallClock must not be after run.json.finishedAt",
    "child startedAt must not be before suite.json.startedAt",
    "child finishedAt must not be after suite.json.finishedAt",
    "requireArrayField(failures, suite, \"suite.json\", \"runs\")",
    "suite.json.scenarioCount must be a non-negative integer",
    "suite.json.scenarioCount must match suite.json.runs.length",
    "validateInstrumentationMode(",
    "launchMode must be dry-run or isolated-agent-instance",
    "instrumentationFlags.computerUseWitness must be false",
    "instrumentationFlags.mainDatabaseTraceWrites must be false",
    "instrumentationFlags.controlBus must be false for dry-run launchMode",
    "instrumentationFlags.controlBus must be true for isolated-agent-instance launchMode",
    "validateTraceIsolation(",
    "validateEvidenceSources(",
    "requiredSources",
    "evidenceSources.${sourceKey}.id must be",
    "evidenceSources.${sourceKey}.path must be",
    "validateExitPolicy(",
    "validateBaselineComparison(",
    "baselineComparisonStatuses",
    "baselineComparisonRowStatuses",
    "baselineComparisonMetricKey(",
    "baselineFailureKey(",
    "failureEventKey(",
    "stableAggregateKey(",
    "compareMultisets(",
    "requireArrayField(",
    "validateMetricsAgainstRegistry(",
    "validateMetricValueShape(",
    "must match KPI registry",
    "is not declared in ux-trace-harness.registry.json",
    "sampleCount must be greater than zero when status is measured",
    "percentile values must be ordered p50 <= p95 <= p99 <= ${percentileFields[3]}",
    "sampleCount must be 0 when status is missing_sample",
    "evidenceEventRefs must include at least one event ref",
    "evidenceEventRefs must include an event for the same KPI",
    "run.completed status must match run.json.status",
    "scenario.started requires exactly one scenario.completed",
    "must have exactly one action.dispatched",
    "must have exactly one step.completed or step.failed",
    "terminal event must occur after action.dispatched",
    "metrics.json.schemaVersion must be 1",
    "failures.json.schemaVersion must be 1",
    "suite-metrics.json.schemaVersion must be 1",
    "suite-failures.json.schemaVersion must be 1",
    "failureRowsByEventKey",
    "comparisonValueMatchesMetric(",
    "expectedBaselineComparisonStatus(",
    "expectedSuiteStatus(",
    "metricKeys",
    "metricRows",
    "failureRows",
    "has no matching metric row",
    "must match the emitted metric row",
    "comparisons must include one row per metric",
    "requires a matching failures.json row",
    "must have a matching step.failed event",
    "step.failed must include a failure object",
    "step.failed must have a matching failures.json row",
    "step.failed ${key} must be unique",
    "duplicates failure identity",
    "contains row not emitted by child runs",
    "\"worstSample\"",
    "\"budget\"",
    "\"evidenceEventRefs\"",
    "baseline_regression must exceed gate.maxRegressionPercent",
    "status must be ${expectedStatus} for its comparison rows and gate",
    "suite.json.status must be ${expectedStatus} for child run statuses",
    "gate.maxRegressionPercent must be numeric",
    "validateBaselineArtifact(",
    "suite-baseline-comparison.json",
    "suiteBaselineComparison",
    "baselineComparisonPath",
    "baselineComparisonPath must point to the child run baseline-comparison.json",
    "baselineComparisonPath runId must match child run",
    "baselineComparisonPath scenarioId must match child run",
    "baselineComparisonPath fixtureProfile must match child run",
    "sourceEvidence.runId must be a non-empty string for run baselines",
    "sourceEvidence.suiteId must be a non-empty string for suite baselines",
    "baseline.suiteId must match baseline.sourceEvidence.suiteId for suite baselines",
    "is not a UX trace run, suite, or baseline artifact",
    "must not include raw baselinePath",
    "exitPolicy.computedExitCode must be",
    "contentHash does not match current source content",
    "runDirectoryMatchesRunId must be true",
    "suiteDirectoryMatchesSuiteId must be true",
    "evidenceRootHash must match evidence parent directory",
    "traceIsolation.childRunDirectories must match suite run directories",
    "suite.json.runs.runDir values must be unique",
    "artifactIndex must be an array",
    "artifactIndex path must exist",
    "artifactIndex is missing child run directory",
    "validateOverheadCalibration(",
    "overheadCalibration.controlRun must not include a local path",
    "controlRun.available must be false when status is external_pending_control_run",
    "controlRun.available must be true when status is compared",
    "highCardinalityInstrumentation must be false for harness-disabled controls",
    "instrumentationOverheadEstimate.${numberField} must be numeric when status is compared",
    "overheadCalibration.traceWriter.bounded must be true",
    "validatePathReference(",
    "must not include an external local path",
    "geometry.sample",
    "resource.sample",
    "database.sample",
    "bridge.sample",
    "privateBoundary.publicSafe must be true",
  ]) {
    requireSnippet(evidenceVerifierSource, evidenceVerifierPath, snippet);
  }
}

if (fixtureGeneratorSource) {
  for (const snippet of [
    "function scalingDimensionsFor(config)",
    "scalingDimensions: scalingDimensionsFor(config)",
    "scalingDimensions: scalingDimensionsFor(config),",
  ]) {
    requireSnippet(fixtureGeneratorSource, fixtureGeneratorPath, snippet);
  }
}

if (fixtureVerificationSource) {
  for (const snippet of [
    "docs\", \"ui\", \"ux-trace-harness.registry.json",
    "assertListedProfileScaling(",
    "realEquivalentPressureDimensions",
    "real-equivalent-private messageCountPerConversation",
  ]) {
    requireSnippet(fixtureVerificationSource, fixtureVerificationPath, snippet);
  }
}

for (const [relativePath, source] of [
  [uiReadmePath, uiReadmeSource],
  [uiPerformanceSkillPath, uiPerformanceSkillSource],
]) {
  if (!source) {
    fail(`${relativePath} must exist`);
    continue;
  }
  for (const snippet of [
    "docs/ui/ux-trace-calibration.manifest.json",
    "node scripts/run_macos_ux_trace_harness.mjs --self-test",
    "--suite p0",
    "real-equivalent-private",
    "worst-case",
    "Computer Use",
  ]) {
    requireSnippet(source, relativePath, snippet);
  }
}

if (errors.length > 0) {
  console.error("Clawix macOS UX trace harness contract check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("Clawix macOS UX trace harness contract check passed.");
