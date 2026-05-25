#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const registryPath = "docs/ui/ux-trace-harness.registry.json";
const evidenceSchemaPath = "docs/ui/ux-trace-evidence.schema.json";
const scenariosPath = "docs/ui/ux-trace-scenarios.manifest.json";
const runnerPath = "scripts/run_macos_ux_trace_harness.mjs";
const errors = [];

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

for (const [relativePath, value] of [
  [registryPath, registry],
  [evidenceSchemaPath, evidenceSchema],
  [scenariosPath, scenarios],
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
    "privateBoundary",
    "requiredArtifacts",
    "traceSurfaces",
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
  if (registry.requiredArtifacts?.evidenceSchema !== evidenceSchemaPath) fail(`${registryPath}.requiredArtifacts.evidenceSchema must point to ${evidenceSchemaPath}`);
  if (registry.requiredArtifacts?.scenarioManifest !== scenariosPath) fail(`${registryPath}.requiredArtifacts.scenarioManifest must point to ${scenariosPath}`);
  if (registry.requiredArtifacts?.runnerCommand !== `node ${runnerPath}`) fail(`${registryPath}.requiredArtifacts.runnerCommand must be node ${runnerPath}`);
  if (registry.requiredArtifacts?.runnerSelfTestCommand !== `node ${runnerPath} --self-test`) fail(`${registryPath}.requiredArtifacts.runnerSelfTestCommand must be node ${runnerPath} --self-test`);
  if (registry.requiredArtifacts?.verificationCommand !== "node scripts/ui_ux_trace_harness_check.mjs") fail(`${registryPath}.requiredArtifacts.verificationCommand must be node scripts/ui_ux_trace_harness_check.mjs`);
  if (!fs.existsSync(path.join(rootDir, runnerPath))) fail(`${runnerPath} must exist`);

  const surfaces = requireArray(registry.traceSurfaces, `${registryPath}.traceSurfaces`, expectedP0SurfaceIds.length);
  const surfaceIds = requireRecordIds(surfaces, `${registryPath}.traceSurfaces`, expectedP0SurfaceIds);
  for (const surface of surfaces) {
    requireFields(surface, `${registryPath}.traceSurfaces.${surface.id ?? "unknown"}`, ["id", "priority", "role", "surface", "visibilityContract", "geometryContract"]);
    if (!["P0", "P1", "P2"].includes(surface.priority)) fail(`${registryPath}.traceSurfaces.${surface.id}.priority must be P0/P1/P2`);
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
    requireFields(kpi, `${registryPath}.kpis.${kpi.id ?? "unknown"}`, ["id", "priority", "surface", "trigger", "completionCondition", "geometryCondition", "fixtureProfiles", "baselineComparison"]);
    if (!["P0", "P1", "P2"].includes(kpi.priority)) fail(`${registryPath}.kpis.${kpi.id}.priority must be P0/P1/P2`);
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
    "runRequiredFields",
    "allowedRunStatuses",
    "eventRequiredFields",
    "eventTypes",
    "metricRequiredFields",
    "failureTypes",
    "privacyRequirements",
    "correlationRequirements",
  ]);
  if (evidenceSchema.schemaVersion !== 1) fail(`${evidenceSchemaPath}.schemaVersion must be 1`);
  if (evidenceSchema.program !== "macos-ux-trace-harness") fail(`${evidenceSchemaPath}.program must be macos-ux-trace-harness`);
  requireUniqueStringArray(requireArray(evidenceSchema.eventTypes, `${evidenceSchemaPath}.eventTypes`, expectedEventTypes.length), `${evidenceSchemaPath}.eventTypes`, expectedEventTypes);
  requireUniqueStringArray(requireArray(evidenceSchema.runRequiredFields, `${evidenceSchemaPath}.runRequiredFields`), `${evidenceSchemaPath}.runRequiredFields`, ["runId", "scenarioId", "fixtureProfile", "artifactIndex"]);
  requireUniqueStringArray(requireArray(evidenceSchema.eventRequiredFields, `${evidenceSchemaPath}.eventRequiredFields`), `${evidenceSchemaPath}.eventRequiredFields`, ["runId", "actionId", "surfaceId", "controlId", "kpiId", "timestampMonotonicNs"]);
  requireUniqueStringArray(requireArray(evidenceSchema.metricRequiredFields, `${evidenceSchemaPath}.metricRequiredFields`), `${evidenceSchemaPath}.metricRequiredFields`, ["kpiId", "p50", "p95", "p99", "baseline", "evidenceEventRefs"]);
  if (evidenceSchema.correlationRequirements?.dispatchSuccessIsNotVisualSuccess !== true) {
    fail(`${evidenceSchemaPath}.correlationRequirements.dispatchSuccessIsNotVisualSuccess must be true`);
  }
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
  const scenarioRecords = requireArray(scenarios.scenarios, `${scenariosPath}.scenarios`, expectedScenarios.length);
  const scenarioIds = requireRecordIds(scenarioRecords, `${scenariosPath}.scenarios`, expectedScenarios);
  const registryKpiIds = new Set((registry?.kpis ?? []).map((kpi) => kpi.id));
  const registryFixtureIds = new Set((registry?.fixtureProfiles ?? []).map((profile) => profile.id));
  const registrySurfaceIds = new Set((registry?.traceSurfaces ?? []).map((surface) => surface.id));
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
      if (step.action !== "include-scenario" && !registrySurfaceIds.has(step.target)) {
        fail(`${scenariosPath}.scenarios.${scenario.id}.steps.${step.id}.target references unknown trace surface ${step.target}`);
      }
      if (step.action === "include-scenario" && !scenarioIds.has(step.target)) {
        fail(`${scenariosPath}.scenarios.${scenario.id}.steps.${step.id}.target references unknown scenario ${step.target}`);
      }
    }
  }
}

if (errors.length > 0) {
  console.error("Clawix macOS UX trace harness contract check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("Clawix macOS UX trace harness contract check passed.");
