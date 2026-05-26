#!/usr/bin/env node
import crypto from "node:crypto";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const registryPath = path.join(rootDir, "docs/ui/ux-trace-harness.registry.json");
const scenarioManifestPath = path.join(rootDir, "docs/ui/ux-trace-scenarios.manifest.json");
const evidenceSchemaPath = path.join(rootDir, "docs/ui/ux-trace-evidence.schema.json");
const fixtureGeneratorPath = path.join(rootDir, "scripts/generate_macos_ux_trace_fixtures.mjs");
const evidenceVerifierPath = path.join(rootDir, "scripts/verify_macos_ux_trace_evidence.mjs");

const defaultTimeoutMs = 5_000;
const defaultPollMs = 50;
const defaultDurationMs = 250;
const defaultTolerancePx = 1;
const defaultControlReadyTimeoutMs = 10_000;
const maxIncludeDepth = 8;
const maxEvidenceEventsPerRun = 100_000;
const maxEvidenceEventBytesPerRun = 32 * 1024 * 1024;
const maxFailureUIStateControls = 200;
const maxFailureUIStateArrayItems = 240;
const maxFailureUIStateDepth = 8;
const maxFailureUIStateBytesPerRun = 16 * 1024 * 1024;

function usage() {
  return `Usage:
  node scripts/run_macos_ux_trace_harness.mjs --list
  node scripts/run_macos_ux_trace_harness.mjs --self-test
  node scripts/run_macos_ux_trace_harness.mjs --dry-run --suite p0 [--fixture-profile <id>] [--out-dir <dir>]
  node scripts/run_macos_ux_trace_harness.mjs --dry-run --scenario <id> --fixture-profile <id> [--out-dir <dir>]
  node scripts/run_macos_ux_trace_harness.mjs --control-url <url> --token <token> --suite p0 --fixture-profile <id> [--out-dir <dir>]
  node scripts/run_macos_ux_trace_harness.mjs --control-url <url> --token <token> --scenario <id> --fixture-profile <id> [--out-dir <dir>]

Options:
  --suite <id>             Suite id. Currently supports p0.
  --scenario <id>          Scenario id from docs/ui/ux-trace-scenarios.manifest.json.
  --fixture-profile <id>   Fixture profile declared by the scenario. With --suite, filters to compatible scenarios.
  --control-url <url>      Agent control bus base URL, for example http://127.0.0.1:24500.
  --token <token>          Owner token for the isolated agent instance.
  --out-dir <dir>          Evidence root. Defaults to a temporary directory.
  --baseline <file>        Optional metrics.json or baseline-comparison source.
  --write-baseline <file>  Write current measured metrics as a public-safe baseline artifact.
  --gate p0                Activate P0 baseline gate. Requires baseline and fails P0 regressions.
  --max-regression-percent <n> Allowed P0 regression percentage for --gate p0. Defaults to 10.
  --fixture-dir <dir>      Existing generated fixture pack to attach to evidence.
  --generate-fixture       Generate a fixture pack for the selected profile into the run directory.
  --timeout-ms <n>         Default wait timeout.
  --poll-ms <n>            Default wait poll interval.
  --request-timeout-ms <n> Default HTTP request timeout.
  --control-ready-timeout-ms <n> Time to wait for the control bus before steps.
  --dry-run                Do not contact the app; emit BLOCKED evidence for wiring validation.
  --json                   Print machine-readable result.
`;
}

function parseArgs(argv) {
  const args = { _: [] };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (!arg.startsWith("--")) {
      args._.push(arg);
      continue;
    }
    const key = arg.slice(2);
    if (["dry-run", "json", "list", "self-test", "generate-fixture"].includes(key)) {
      args[key] = true;
      continue;
    }
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) {
      throw new Error(`missing value for --${key}`);
    }
    args[key] = value;
    index += 1;
  }
  return args;
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function writeJson(file, value) {
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);
}

function isoNow() {
  return new Date().toISOString();
}

function monotonicNs() {
  return Number(process.hrtime.bigint());
}

function stableHash(value) {
  return `sha256:${crypto.createHash("sha256").update(JSON.stringify(value)).digest("hex")}`;
}

function redactedString(value) {
  return {
    redacted: true,
    length: value.length,
    hash: stableHash(value),
  };
}

function publicSafeIdentifier(value, indexes) {
  if (typeof value !== "string") return value;
  if (indexes.surfaceIds.has(value)) return value;
  return redactedString(value);
}

function sanitizeFailureUIState(value, indexes, key = "", depth = 0) {
  if (value === null || value === undefined) return value ?? null;
  if (typeof value === "number" || typeof value === "boolean") return value;
  if (typeof value === "string") {
    if (["role", "source", "axRole", "failureReason", "condition", "action"].includes(key)) return value;
    if (["id", "resolvedId", "controlId", "surfaceId", "target", "waitTarget"].includes(key)) {
      return publicSafeIdentifier(value, indexes);
    }
    return redactedString(value);
  }
  if (depth >= maxFailureUIStateDepth) {
    return { truncated: true, reason: "max-depth", valueHash: stableHash(value) };
  }
  if (Array.isArray(value)) {
    const limit = Math.min(value.length, key === "controls" ? maxFailureUIStateControls : maxFailureUIStateArrayItems);
    const items = value.slice(0, limit).map((item) => sanitizeFailureUIState(item, indexes, key, depth + 1));
    if (value.length > limit) {
      return {
        count: value.length,
        truncated: true,
        items,
      };
    }
    return items;
  }
  if (typeof value === "object") {
    const out = {};
    for (const [childKey, childValue] of Object.entries(value)) {
      out[childKey] = sanitizeFailureUIState(childValue, indexes, childKey, depth + 1);
    }
    return out;
  }
  return null;
}

function failureUIStateWriter(file, common, indexes) {
  fs.writeFileSync(file, "");
  let sequence = 0;
  let bytesWritten = 0;
  const refs = [];
  return {
    write(fields) {
      if (!fields.finalUIState) return null;
      sequence += 1;
      const finalUIStateHash = stableHash(fields.finalUIState);
      const row = {
        schemaVersion: 1,
        runId: common.runId,
        scenarioId: common.scenarioId,
        fixtureProfile: common.fixtureProfile,
        sequence,
        stepId: fields.stepId,
        actionId: fields.actionId,
        surfaceId: fields.surfaceId,
        controlId: fields.controlId,
        kpiId: fields.kpiId,
        finalUIStateHash,
        redactedState: sanitizeFailureUIState(fields.finalUIState, indexes),
        privateBoundary: {
          containsPrivateConversationText: false,
          containsReadablePrivateScreenshots: false,
          containsCredentials: false,
          publicSafe: true,
          stringContentPolicy: "raw strings are replaced with length and sha256 hash unless they are stable trace surface identifiers or enum-like control metadata",
        },
      };
      const line = `${JSON.stringify(row)}\n`;
      bytesWritten += Buffer.byteLength(line, "utf8");
      if (bytesWritten > maxFailureUIStateBytesPerRun) {
        throw new Error(`UX trace failure UI state writer exceeded ${maxFailureUIStateBytesPerRun} bytes for ${common.runId}`);
      }
      fs.appendFileSync(file, line);
      const ref = `logs/failure-ui-states.jsonl#${sequence}`;
      refs.push(ref);
      return { ref, hash: finalUIStateHash };
    },
    refs,
  };
}

function runIdFor(scenarioId, fixtureProfile) {
  const stamp = new Date().toISOString().replace(/[-:.TZ]/g, "").slice(0, 14);
  const suffix = crypto.randomBytes(4).toString("hex");
  return `uxtrace-${scenarioId}-${fixtureProfile}-${stamp}-${suffix}`;
}

function suiteIdFor(suiteName, fixtureProfile) {
  const stamp = new Date().toISOString().replace(/[-:.TZ]/g, "").slice(0, 14);
  const suffix = crypto.randomBytes(4).toString("hex");
  const profilePart = fixtureProfile ? `-${fixtureProfile}` : "";
  return `uxtrace-suite-${suiteName}${profilePart}-${stamp}-${suffix}`;
}

function boundedInteger(value, fallback, min, max) {
  const parsed = Number.parseInt(value ?? "", 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function requireString(value, label) {
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`${label} is required`);
  }
  return value;
}

function mkdirEvidence(root, runId) {
  const runDir = path.resolve(root || path.join(os.tmpdir(), "clawix-ux-trace-runs"), runId);
  for (const relative of ["captures", "logs", "traces"]) {
    fs.mkdirSync(path.join(runDir, relative), { recursive: true });
  }
  return runDir;
}

function mkdirSuiteEvidence(root, suiteId) {
  const suiteDir = path.resolve(root || path.join(os.tmpdir(), "clawix-ux-trace-runs"), suiteId);
  fs.mkdirSync(suiteDir, { recursive: true });
  return suiteDir;
}

function buildIndexes(registry, manifest) {
  return {
    surfaceIds: new Set((registry.traceSurfaces || []).map((surface) => surface.id)),
    fixtureIds: new Set((registry.fixtureProfiles || []).map((profile) => profile.id)),
    kpisById: new Map((registry.kpis || []).map((kpi) => [kpi.id, kpi])),
    scenariosById: new Map((manifest.scenarios || []).map((scenario) => [scenario.id, scenario])),
    eventTypes: new Set((readJson(evidenceSchemaPath).eventTypes || [])),
  };
}

function validateScenarioSelection(args, indexes) {
  const scenarioId = requireString(args.scenario, "--scenario");
  const fixtureProfile = requireString(args["fixture-profile"], "--fixture-profile");
  const scenario = indexes.scenariosById.get(scenarioId);
  if (!scenario) throw new Error(`unknown scenario: ${scenarioId}`);
  if (!scenario.fixtureProfiles?.includes(fixtureProfile)) {
    throw new Error(`${scenarioId} does not declare fixture profile ${fixtureProfile}`);
  }
  if (!indexes.fixtureIds.has(fixtureProfile)) {
    throw new Error(`unknown fixture profile: ${fixtureProfile}`);
  }
  return { scenario, scenarioId, fixtureProfile };
}

function suiteSelections(args, manifest, indexes) {
  const suiteName = requireString(args.suite, "--suite");
  if (suiteName !== "p0") {
    throw new Error(`unknown suite: ${suiteName}`);
  }
  const requestedProfile = args["fixture-profile"] || null;
  const scenarios = (manifest.scenarios || []).filter((scenario) => scenario.priority === "P0");
  const selections = scenarios
    .filter((scenario) => !requestedProfile || scenario.fixtureProfiles?.includes(requestedProfile))
    .map((scenario) => {
      const fixtureProfile = requestedProfile || scenario.fixtureProfiles?.[0];
      if (!fixtureProfile) throw new Error(`${scenario.id} does not declare fixture profiles`);
      if (!indexes.fixtureIds.has(fixtureProfile)) throw new Error(`${scenario.id} references unknown fixture profile ${fixtureProfile}`);
      return { scenarioId: scenario.id, fixtureProfile };
    });
  if (!selections.length) {
    const suffix = requestedProfile ? ` for fixture profile ${requestedProfile}` : "";
    throw new Error(`suite ${suiteName} has no runnable scenarios${suffix}`);
  }
  return { suiteName, requestedProfile, selections };
}

function expandScenarioSteps(scenario, indexes, stack = []) {
  if (stack.length > maxIncludeDepth) {
    throw new Error(`scenario include depth exceeded: ${stack.join(" -> ")}`);
  }
  const expanded = [];
  for (const step of scenario.steps || []) {
    if (step.action !== "include-scenario") {
      expanded.push({ ...step, sourceScenarioId: scenario.id });
      continue;
    }
    const included = indexes.scenariosById.get(step.target);
    if (!included) throw new Error(`${scenario.id}.${step.id} includes unknown scenario ${step.target}`);
    expanded.push(...expandScenarioSteps(included, indexes, [...stack, scenario.id]));
  }
  return expanded;
}

function eventWriter(file, common) {
  fs.writeFileSync(file, "");
  let sequence = 0;
  let bytesWritten = 0;
  const eventRefs = [];
  return {
    write(fields) {
      if (sequence >= maxEvidenceEventsPerRun) {
        throw new Error(`UX trace event writer exceeded ${maxEvidenceEventsPerRun} events for ${common.runId}`);
      }
      sequence += 1;
      const event = {
        schemaVersion: 1,
        runId: common.runId,
        scenarioId: common.scenarioId,
        fixtureProfile: common.fixtureProfile,
        stepId: fields.stepId || "run",
        actionId: fields.actionId || "run",
        surfaceId: fields.surfaceId || fields.controlId || "app.shell.firstUsableWindow",
        controlId: fields.controlId || fields.surfaceId || "app.shell.firstUsableWindow",
        kpiId: fields.kpiId || "none",
        eventType: fields.eventType,
        timestampMonotonicNs: monotonicNs(),
        timestampWallClock: isoNow(),
        sequence,
        ...fields,
      };
      const line = `${JSON.stringify(event)}\n`;
      bytesWritten += Buffer.byteLength(line, "utf8");
      if (bytesWritten > maxEvidenceEventBytesPerRun) {
        throw new Error(`UX trace event writer exceeded ${maxEvidenceEventBytesPerRun} bytes for ${common.runId}`);
      }
      fs.appendFileSync(file, line);
      eventRefs.push(`${event.sequence}:${event.eventType}:${event.stepId}`);
      return event;
    },
    close() {
      // Events are written synchronously so evidence is complete on return.
    },
    eventRefs,
  };
}

function actionDispatchFor(step) {
  if (step.dispatch) return step.dispatch;
  if (step.action === "scroll") return "scroll";
  if (step.action === "scroll-to-bottom") return "scroll-to-bottom";
  if (step.action === "type") return "type";
  if (step.action === "hover") return "hover";
  if (step.action === "mock-send") return "mock-send";
  if (step.action === "mock-stream" || step.action === "mock-bridge-stream") return step.action;
  if (step.action === "mock-stream-complete") return "mock-stream-complete";
  if (step.action === "fixture-metadata-update") return "fixture-metadata-update";
  if (step.action === "measure-anchor-delta") return "measure-anchor-delta";
  if (step.action === "measure-action") return "click";
  if (step.action === "snapshot") return "record-anchor";
  return null;
}

function verbForStep(step) {
  if (step.action === "measure-action" || [
    "scroll",
    "scroll-to-bottom",
    "type",
    "hover",
    "mock-send",
    "mock-stream",
    "mock-stream-complete",
    "mock-bridge-stream",
    "fixture-metadata-update",
    "measure-anchor-delta",
    "snapshot",
  ].includes(step.action)) {
    return "measure-action";
  }
  if (typeof step.wait === "string" && step.wait.startsWith("wait-")) return step.wait;
  return null;
}

function requestBodyForStep(step, options) {
  const body = {
    token: options.token,
    id: step.target,
    target: step.target,
    wait: step.wait,
    waitTarget: step.waitTarget || step.target,
    timeoutMs: boundedInteger(step.timeoutMs, options.timeoutMs, 100, 120_000),
    pollMs: boundedInteger(step.pollMs, options.pollMs, 10, 5_000),
    durationMs: boundedInteger(step.durationMs, defaultDurationMs, 50, 30_000),
    tolerancePx: Number.isFinite(Number(step.tolerancePx)) ? Number(step.tolerancePx) : defaultTolerancePx,
  };
  const dispatch = actionDispatchFor(step);
  if (dispatch) body.action = dispatch;
  if (Object.hasOwn(step, "text")) body.text = step.text;
  if (Object.hasOwn(step, "reasoning")) body.reasoning = step.reasoning;
  if (Object.hasOwn(step, "intervalMs")) body.intervalMs = boundedInteger(step.intervalMs, 12, 0, 5_000);
  if (Object.hasOwn(step, "initialDelayMs")) body.initialDelayMs = boundedInteger(step.initialDelayMs, 0, 0, 5_000);
  if (Object.hasOwn(step, "chunkWords")) body.chunkWords = boundedInteger(step.chunkWords, 1, 1, 12);
  if (Object.hasOwn(step, "includeTool")) body.includeTool = Boolean(step.includeTool);
  if (step.direction) body.direction = step.direction;
  if (step.pages) body.pages = step.pages;
  if (step.contains) body.contains = step.contains;
  if (step.query) body.query = step.query;
  if (step.minCount) body.minCount = step.minCount;
  if (step.minVisibleMessages) body.minVisibleMessages = step.minVisibleMessages;
  if (step.route) body.route = step.route;
  return body;
}

async function postControl(options, verb, body) {
  const url = `${options.controlUrl.replace(/\/+$/, "")}/control/${verb}`;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), options.requestTimeoutMs);
  let response;
  let text;
  try {
    response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    text = await response.text();
  } catch (error) {
    if (error?.name === "AbortError") {
      throw new Error(`control ${verb} exceeded request timeout ${options.requestTimeoutMs}ms`);
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }
  let payload = null;
  try {
    payload = text ? JSON.parse(text) : null;
  } catch {
    payload = { raw: text };
  }
  if (!response.ok) {
    const error = new Error(`control ${verb} failed with HTTP ${response.status}`);
    error.payload = payload;
    throw error;
  }
  return payload;
}

async function waitForControlReady(options) {
  if (options.dryRun) return null;
  const deadline = Date.now() + options.controlReadyTimeoutMs;
  let lastError = null;
  while (Date.now() <= deadline) {
    try {
      const payload = await postControl(options, "wait-visible", {
        token: options.token,
        id: "app.shell.firstUsableWindow",
        target: "app.shell.firstUsableWindow",
        timeoutMs: 250,
        pollMs: 50,
      });
      if (payload?.ok !== false && payload?.timedOut !== true) return payload;
    } catch (error) {
      lastError = error;
    }
    await sleep(100);
  }
  const suffix = lastError ? `: ${lastError.message}` : "";
  throw new Error(`control bus did not become ready within ${options.controlReadyTimeoutMs}ms${suffix}`);
}

function stepSurfaceId(step, indexes) {
  if (indexes.surfaceIds.has(step.target)) return step.target;
  return "app.shell.firstUsableWindow";
}

function stepKpiId(step, scenario, indexes) {
  const explicit = step.kpi || step.kpiId;
  if (explicit === "none") return "none";
  if (explicit && indexes.kpisById.has(explicit)) return explicit;
  return (scenario.kpiRefs || []).find((kpiId) => indexes.kpisById.has(kpiId)) || "none";
}

function elapsedFromPayload(payload, fallbackMs) {
  const candidates = [
    payload?.elapsedMs,
    payload?.wait?.elapsedMs,
    payload?.actionResult?.elapsedMs,
    payload?.json?.elapsedMs,
  ];
  for (const value of candidates) {
    const number = Number(value);
    if (Number.isFinite(number)) return number;
  }
  return fallbackMs;
}

function sampleValueForKpi(kpiId, payload, fallbackMs) {
  if (kpiId.includes("hitch")) {
    const total = Number(payload?.diagnostics?.hitches?.total ?? payload?.wait?.diagnostics?.hitches?.total);
    return Number.isFinite(total) ? total : fallbackMs;
  }
  if (kpiId.endsWith("_mb")) {
    const resource = payload?.diagnostics?.resource ?? payload?.wait?.diagnostics?.resource;
    const value = Number(resource?.footprintMB ?? resource?.residentMB);
    return Number.isFinite(value) ? value : fallbackMs;
  }
  return elapsedFromPayload(payload, fallbackMs);
}

function makeMetric(kpi, samples, eventRefs, baselineEntry) {
  const sorted = [...samples].sort((a, b) => a - b);
  const percentile = (p) => {
    if (!sorted.length) return null;
    const index = Math.min(sorted.length - 1, Math.floor((p / 100) * (sorted.length - 1)));
    return sorted[index];
  };
  const p95 = percentile(95);
  const baseline = baselineEntry?.p95 ?? baselineEntry?.value ?? null;
  const regressionPercent = Number.isFinite(p95) && Number.isFinite(Number(baseline)) && Number(baseline) > 0
    ? ((p95 - Number(baseline)) / Number(baseline)) * 100
    : null;
  return {
    kpiId: kpi.id,
    priority: kpi.priority,
    surface: kpi.surface,
    sampleCount: sorted.length,
    unit: kpi.id.endsWith("_count") ? "count" : kpi.id.endsWith("_mb") ? "mb" : "ms",
    p50: percentile(50),
    p95,
    p99: percentile(99),
    worstSample: sorted.length ? sorted[sorted.length - 1] : null,
    budget: null,
    baseline,
    regressionPercent,
    status: sorted.length ? "measured" : "missing_sample",
    evidenceEventRefs: eventRefs.slice(0, 20),
  };
}

function readBaseline(file) {
  if (!file) return new Map();
  const payload = readJson(path.resolve(file));
  const rows = Array.isArray(payload) ? payload : (payload.metrics || payload.comparisons || []);
  return new Map(rows.filter((row) => row?.kpiId).map((row) => [row.kpiId, row]));
}

function gateOptions(args) {
  const gate = args.gate || null;
  if (!gate) return null;
  if (gate !== "p0") throw new Error(`unknown gate: ${gate}`);
  return {
    priority: "P0",
    maxRegressionPercent: Number.isFinite(Number(args["max-regression-percent"]))
      ? Number(args["max-regression-percent"])
      : 10,
    requireBaseline: true,
  };
}

function baselineGateFailures(metrics, gate) {
  if (!gate) return [];
  const failures = [];
  for (const metric of metrics) {
    if (metric.priority !== gate.priority) continue;
    if (metric.baseline === null || metric.baseline === undefined) {
      failures.push({
        type: "baseline_missing",
        kpiId: metric.kpiId,
        surfaceId: metric.surface,
        message: `${gate.priority} baseline is required for ${metric.kpiId}`,
      });
      continue;
    }
    if (
      Number.isFinite(Number(metric.regressionPercent))
      && Number(metric.regressionPercent) > gate.maxRegressionPercent
    ) {
      failures.push({
        type: "baseline_regression",
        kpiId: metric.kpiId,
        surfaceId: metric.surface,
        regressionPercent: metric.regressionPercent,
        maxRegressionPercent: gate.maxRegressionPercent,
        message: `${metric.kpiId} regressed ${metric.regressionPercent.toFixed(2)}% over baseline`,
      });
    }
  }
  return failures;
}

function baselineComparisonStatus(comparisons, gate) {
  if (!gate) {
    return comparisons.every((comparison) => comparison.baseline !== null) ? "compared" : "baseline_missing";
  }
  if (comparisons.some((comparison) => comparison.status === "baseline_regression")) return "gate_failed";
  if (comparisons.some((comparison) => comparison.status === "baseline_missing")) return "baseline_missing";
  return "gate_passed";
}

function writeBaselineArtifact(file, context, metrics) {
  if (!file) return null;
  const baseline = {
    schemaVersion: 1,
    program: "macos-ux-trace-harness-baseline",
    generatedAt: isoNow(),
    platform: "macos",
    scenarioId: context.scenarioId,
    fixtureProfile: context.fixtureProfile,
    suiteId: context.suiteId || null,
    privateBoundary: {
      containsPrivateConversationText: false,
      containsReadablePrivateScreenshots: false,
      containsCredentials: false,
      publicSafe: true,
    },
    metrics: metrics.map((metric) => ({
      kpiId: metric.kpiId,
      priority: metric.priority,
      surface: metric.surface,
      unit: metric.unit,
      p50: metric.p50,
      p95: metric.p95,
      p99: metric.p99,
      value: metric.p95,
      sampleCount: metric.sampleCount,
      status: metric.status,
    })),
  };
  const out = path.resolve(file);
  fs.mkdirSync(path.dirname(out), { recursive: true });
  writeJson(out, baseline);
  return out;
}

function fixtureManifestFromPack(fixtureDir) {
  if (!fixtureDir) return null;
  const resolved = path.resolve(fixtureDir);
  const manifestPath = path.join(resolved, "manifest.json");
  if (!fs.existsSync(manifestPath)) {
    throw new Error(`fixture pack is missing manifest.json: ${resolved}`);
  }
  const manifest = readJson(manifestPath);
  return {
    path: resolved,
    manifestPath,
    manifest,
  };
}

function generateFixturePack(args, runDir, fixtureProfile) {
  if (!args["generate-fixture"]) return fixtureManifestFromPack(args["fixture-dir"]);
  if (args["fixture-dir"]) {
    throw new Error("--generate-fixture and --fixture-dir are mutually exclusive");
  }
  const outDir = path.join(runDir, "fixture-pack");
  const seed = args["fixture-seed"] || "default";
  const result = spawnSync(process.execPath, [
    fixtureGeneratorPath,
    "--profile",
    fixtureProfile,
    "--seed",
    seed,
    "--out-dir",
    outDir,
    "--json",
  ], {
    cwd: rootDir,
    encoding: "utf8",
  });
  if (result.status !== 0) {
    const detail = `${result.stderr || ""}${result.stdout || ""}`.trim();
    throw new Error(`fixture generation failed for ${fixtureProfile}${detail ? `: ${detail}` : ""}`);
  }
  return fixtureManifestFromPack(outDir);
}

function verifyEvidencePath(targetPath) {
  const result = spawnSync(process.execPath, [
    evidenceVerifierPath,
    "--path",
    targetPath,
    "--json",
  ], {
    cwd: rootDir,
    encoding: "utf8",
    maxBuffer: 80 * 1024 * 1024,
  });
  if (result.status !== 0) {
    const detail = `${result.stderr || ""}${result.stdout || ""}`.trim();
    throw new Error(`evidence verification failed for ${targetPath}${detail ? `: ${detail}` : ""}`);
  }
  return result.stdout ? JSON.parse(result.stdout) : null;
}

async function runScenario(args) {
  const registry = readJson(registryPath);
  const manifest = readJson(scenarioManifestPath);
  const indexes = buildIndexes(registry, manifest);
  const { scenario, scenarioId, fixtureProfile } = validateScenarioSelection(args, indexes);
  const runId = args["run-id"] || runIdFor(scenarioId, fixtureProfile);
  const runDir = mkdirEvidence(args["out-dir"], runId);
  const startedAt = isoNow();
  const events = eventWriter(path.join(runDir, "events.jsonl"), { runId, scenarioId, fixtureProfile });
  const failureUIStates = failureUIStateWriter(
    path.join(runDir, "logs/failure-ui-states.jsonl"),
    { runId, scenarioId, fixtureProfile },
    indexes
  );
  const failures = [];
  const kpiSamples = new Map();
  const baseline = readBaseline(args.baseline);
  const gate = gateOptions(args);
  const fixturePack = generateFixturePack(args, runDir, fixtureProfile);
  const options = {
    dryRun: Boolean(args["dry-run"]),
    controlUrl: args["control-url"],
    token: args.token,
    timeoutMs: boundedInteger(args["timeout-ms"], defaultTimeoutMs, 100, 120_000),
    pollMs: boundedInteger(args["poll-ms"], defaultPollMs, 10, 5_000),
    requestTimeoutMs: boundedInteger(args["request-timeout-ms"], Math.max(boundedInteger(args["timeout-ms"], defaultTimeoutMs, 100, 120_000) + 10_000, 15_000), 500, 180_000),
    controlReadyTimeoutMs: boundedInteger(args["control-ready-timeout-ms"], defaultControlReadyTimeoutMs, 500, 120_000),
  };
  if (!options.dryRun) {
    requireString(options.controlUrl, "--control-url");
    requireString(options.token, "--token");
  }

  const expandedSteps = expandScenarioSteps(scenario, indexes);
  events.write({ eventType: "run.started", stepId: "run", actionId: runId });
  let skipScenarioSteps = false;
  if (!options.dryRun) {
    events.write({
      eventType: "action.dispatched",
      stepId: "control-ready",
      actionId: `${runId}:control-ready`,
      surfaceId: "app.shell.firstUsableWindow",
      controlId: "app.shell.firstUsableWindow",
      kpiId: "none",
      controlVerb: "wait-visible",
    });
    try {
      const payload = await waitForControlReady(options);
      events.write({
        eventType: "visual.condition.met",
        stepId: "control-ready",
        actionId: `${runId}:control-ready`,
        surfaceId: "app.shell.firstUsableWindow",
        controlId: "app.shell.firstUsableWindow",
        kpiId: "none",
        elapsedMs: payload?.elapsedMs ?? null,
        payloadHash: stableHash(payload),
      });
    } catch (error) {
      const failure = {
        type: "instrumentation_error",
        stepId: "control-ready",
        surfaceId: "app.shell.firstUsableWindow",
        kpiId: "none",
        message: error.message,
        payloadHash: error.payload ? stableHash(error.payload) : null,
      };
      failures.push(failure);
      events.write({
        eventType: "step.failed",
        stepId: "control-ready",
        actionId: `${runId}:control-ready`,
        surfaceId: "app.shell.firstUsableWindow",
        controlId: "app.shell.firstUsableWindow",
        kpiId: "none",
        failure,
      });
      skipScenarioSteps = true;
    }
  }
  if (!skipScenarioSteps) {
    events.write({
      eventType: "fixture.loaded",
      stepId: "fixture",
      actionId: fixtureProfile,
      fixtureManifestHash: fixturePack?.manifest?.manifestHash ?? null,
      fixtureCounts: fixturePack?.manifest?.counts ?? null,
    });
    events.write({ eventType: "scenario.started", stepId: scenarioId, actionId: scenarioId });
  }

  for (const step of skipScenarioSteps ? [] : expandedSteps) {
    const actionId = `${runId}:${step.sourceScenarioId || scenarioId}:${step.id}`;
    const surfaceId = stepSurfaceId(step, indexes);
    const kpiId = stepKpiId(step, scenario, indexes);
    const started = performance.now();
    events.write({
      eventType: "step.started",
      stepId: step.id,
      actionId,
      surfaceId,
      controlId: step.target,
      kpiId,
      action: step.action,
    });

    const verb = verbForStep(step);
    if (!verb) {
      const failure = {
        type: "instrumentation_error",
        stepId: step.id,
        action: step.action,
        message: `No control-bus verb mapping for action ${step.action}`,
      };
      failures.push(failure);
      events.write({
        eventType: "step.failed",
        stepId: step.id,
        actionId,
        surfaceId,
        controlId: step.target,
        kpiId,
        failure,
      });
      continue;
    }

    events.write({
      eventType: "action.dispatched",
      stepId: step.id,
      actionId,
      surfaceId,
      controlId: step.target,
      kpiId,
      controlVerb: verb,
    });

    try {
      let payload;
      if (options.dryRun) {
        payload = {
          ok: false,
          dryRun: true,
          blockedReason: "dry-run does not contact the app control bus",
          elapsedMs: Math.round(performance.now() - started),
        };
      } else {
        payload = await postControl(options, verb, requestBodyForStep(step, options));
      }
      const fallbackMs = Math.round(performance.now() - started);
      const elapsedMs = elapsedFromPayload(payload, fallbackMs);
      const sampleValue = sampleValueForKpi(kpiId, payload, fallbackMs);
      if (!kpiSamples.has(kpiId)) kpiSamples.set(kpiId, []);
      if (kpiId !== "none") kpiSamples.get(kpiId).push(sampleValue);
      const conditionMet = payload?.ok !== false && payload?.timedOut !== true && payload?.wait?.timedOut !== true;
      events.write({
        eventType: conditionMet ? "visual.condition.met" : "visual.condition.timeout",
        stepId: step.id,
        actionId,
        surfaceId,
        controlId: step.target,
        kpiId,
        elapsedMs,
        payloadHash: stableHash(payload),
      });
      events.write({
        eventType: conditionMet ? "step.completed" : "step.failed",
        stepId: step.id,
        actionId,
        surfaceId,
        controlId: step.target,
        kpiId,
        elapsedMs,
      });
      if (!conditionMet) {
        const finalUIStateRef = failureUIStates.write({
          stepId: step.id,
          actionId,
          surfaceId,
          controlId: step.target,
          kpiId,
          finalUIState: payload?.finalUIState,
        });
        if (finalUIStateRef) {
          events.write({
            eventType: "capture.written",
            stepId: step.id,
            actionId,
            surfaceId,
            controlId: step.target,
            kpiId,
            artifactPath: finalUIStateRef.ref,
            artifactKind: "redacted-final-ui-state",
            artifactHash: finalUIStateRef.hash,
          });
        }
        failures.push({
          type: options.dryRun ? "external_pending" : "condition_timeout",
          stepId: step.id,
          surfaceId,
          kpiId,
          message: options.dryRun ? "dry-run evidence only" : `condition did not complete for ${step.wait}`,
          finalUIStateHash: finalUIStateRef?.hash ?? null,
          finalUIStateRef: finalUIStateRef?.ref ?? null,
        });
      }
    } catch (error) {
      const finalUIStateRef = failureUIStates.write({
        stepId: step.id,
        actionId,
        surfaceId,
        controlId: step.target,
        kpiId,
        finalUIState: error.payload?.finalUIState,
      });
      if (finalUIStateRef) {
        events.write({
          eventType: "capture.written",
          stepId: step.id,
          actionId,
          surfaceId,
          controlId: step.target,
          kpiId,
          artifactPath: finalUIStateRef.ref,
          artifactKind: "redacted-final-ui-state",
          artifactHash: finalUIStateRef.hash,
        });
      }
      const failure = {
        type: "instrumentation_error",
        stepId: step.id,
        surfaceId,
        kpiId,
        message: error.message,
        payloadHash: error.payload ? stableHash(error.payload) : null,
        finalUIStateHash: finalUIStateRef?.hash ?? null,
        finalUIStateRef: finalUIStateRef?.ref ?? null,
      };
      failures.push(failure);
      events.write({
        eventType: "step.failed",
        stepId: step.id,
        actionId,
        surfaceId,
        controlId: step.target,
        kpiId,
        failure,
      });
    }
  }

  if (!skipScenarioSteps) {
    events.write({ eventType: "scenario.completed", stepId: scenarioId, actionId: scenarioId });
  }
  const metrics = (scenario.kpiRefs || []).map((kpiId) => {
    const kpi = indexes.kpisById.get(kpiId);
    return makeMetric(kpi, kpiSamples.get(kpiId) || [], events.eventRefs, baseline.get(kpiId));
  });
  const gateFailures = baselineGateFailures(metrics, gate);
  for (const failure of gateFailures) {
    failures.push(failure);
    events.write({
      eventType: "step.failed",
      stepId: "baseline-gate",
      actionId: `${runId}:baseline-gate`,
      surfaceId: failure.surfaceId || "app.shell.firstUsableWindow",
      controlId: failure.surfaceId || "app.shell.firstUsableWindow",
      kpiId: failure.kpiId || "none",
      failure,
    });
  }
  const comparisons = metrics.map((metric) => {
    let comparisonStatus = metric.baseline === null ? "baseline_missing" : "compared";
    if (
      gate
      && metric.priority === gate.priority
      && Number.isFinite(Number(metric.regressionPercent))
      && Number(metric.regressionPercent) > gate.maxRegressionPercent
    ) {
      comparisonStatus = "baseline_regression";
    }
    return {
      kpiId: metric.kpiId,
      p95: metric.p95,
      baseline: metric.baseline,
      regressionPercent: metric.regressionPercent,
      status: comparisonStatus,
    };
  });
  const baselineComparison = {
    schemaVersion: 1,
    runId,
    scenarioId,
    fixtureProfile,
    baselinePath: args.baseline || null,
    gate: gate ? {
      priority: gate.priority,
      maxRegressionPercent: gate.maxRegressionPercent,
    } : null,
    status: baselineComparisonStatus(comparisons, gate),
    comparisons,
  };
  const status = failures.length === 0 ? "PASS" : options.dryRun && gateFailures.length === 0 ? "BLOCKED" : "FAIL";
  events.write({ eventType: "run.completed", stepId: "run", actionId: runId, status });
  events.close();
  const finishedAt = isoNow();
  const run = {
    schemaVersion: 1,
    runId,
    program: "macos-ux-trace-harness",
    scenarioId,
    fixtureProfile,
    fixtureSeed: args["fixture-seed"] || fixturePack?.manifest?.seed || "default",
    harnessVersion: 1,
    appBuild: options.dryRun ? "dry-run" : "control-bus",
    gitSnapshot: {
      head: process.env.GIT_COMMIT || null,
      dirty: null,
    },
    platform: "macos",
    osVersion: os.release(),
    launchMode: options.dryRun ? "dry-run" : "isolated-agent-instance",
    instrumentationFlags: {
      controlBus: !options.dryRun,
      dryRun: options.dryRun,
      computerUseWitness: false,
      mainDatabaseTraceWrites: false,
    },
    startedAt,
    finishedAt,
    status,
    privateBoundary: {
      containsPrivateConversationText: false,
      containsReadablePrivateScreenshots: false,
      containsCredentials: false,
      publicSafe: true,
    },
    artifactIndex: [
      "run.json",
      "events.jsonl",
      "metrics.json",
      "failures.json",
      "logs/failure-ui-states.jsonl",
      "fixture-manifest.json",
      "baseline-comparison.json",
    ],
  };

  writeJson(path.join(runDir, "run.json"), run);
  writeJson(path.join(runDir, "metrics.json"), { schemaVersion: 1, runId, metrics });
  writeJson(path.join(runDir, "failures.json"), { schemaVersion: 1, runId, failures });
  writeJson(path.join(runDir, "fixture-manifest.json"), {
    schemaVersion: 1,
    runId,
    fixtureProfile,
    fixtureSeed: run.fixtureSeed,
    scenarioFixtureProfiles: scenario.fixtureProfiles,
    synthetic: true,
    privateContentExported: false,
    generatedFixture: fixturePack ? {
      path: fixturePack.path,
      manifestPath: fixturePack.manifestPath,
      manifestHash: fixturePack.manifest.manifestHash,
      generatorVersion: fixturePack.manifest.generatorVersion,
      counts: fixturePack.manifest.counts,
      scalingDimensions: fixturePack.manifest.scalingDimensions,
      privateBoundary: fixturePack.manifest.privateBoundary,
      materializedArtifacts: fixturePack.manifest.materializedArtifacts,
    } : null,
  });
  writeJson(path.join(runDir, "baseline-comparison.json"), baselineComparison);
  const writtenBaselinePath = writeBaselineArtifact(args["write-baseline"], { scenarioId, fixtureProfile }, metrics);

  return { ok: status === "PASS", status, runId, runDir, failures: failures.length, metrics: metrics.length, baselinePath: writtenBaselinePath };
}

function aggregateSuiteStatus(results, dryRun) {
  if (results.every((result) => result.status === "PASS")) return "PASS";
  if (dryRun && results.every((result) => result.status === "BLOCKED")) return "BLOCKED";
  if (results.some((result) => result.status === "FAIL")) return "FAIL";
  if (results.some((result) => result.status === "BLOCKED")) return "PARTIAL";
  return "FAIL";
}

function readRunArtifact(runDir, file, fallback) {
  try {
    return readJson(path.join(runDir, file));
  } catch {
    return fallback;
  }
}

async function runSuite(args) {
  if (args.scenario) throw new Error("--suite and --scenario are mutually exclusive");
  if (args["fixture-dir"] && !args["fixture-profile"]) {
    throw new Error("--fixture-dir with --suite requires --fixture-profile so one app fixture pack maps to the selected scenarios");
  }
  const registry = readJson(registryPath);
  const manifest = readJson(scenarioManifestPath);
  const indexes = buildIndexes(registry, manifest);
  const { suiteName, requestedProfile, selections } = suiteSelections(args, manifest, indexes);
  const suiteId = args["run-id"] || suiteIdFor(suiteName, requestedProfile);
  const suiteDir = mkdirSuiteEvidence(args["out-dir"], suiteId);
  const startedAt = isoNow();
  const results = [];
  const metrics = [];
  const failures = [];

  for (const [index, selection] of selections.entries()) {
    const scenarioArgs = {
      ...args,
      scenario: selection.scenarioId,
      "fixture-profile": selection.fixtureProfile,
      "run-id": `${suiteId}-${String(index + 1).padStart(2, "0")}-${selection.scenarioId}`,
      "out-dir": suiteDir,
    };
    delete scenarioArgs.suite;
    delete scenarioArgs["write-baseline"];
    const result = await runScenario(scenarioArgs);
    results.push(result);
    const metricArtifact = readRunArtifact(result.runDir, "metrics.json", { metrics: [] });
    for (const metric of metricArtifact.metrics || []) {
      metrics.push({
        ...metric,
        runId: result.runId,
        scenarioId: selection.scenarioId,
        fixtureProfile: selection.fixtureProfile,
      });
    }
    const failureArtifact = readRunArtifact(result.runDir, "failures.json", { failures: [] });
    for (const failure of failureArtifact.failures || []) {
      failures.push({
        ...failure,
        runId: result.runId,
        scenarioId: selection.scenarioId,
        fixtureProfile: selection.fixtureProfile,
      });
    }
  }

  const status = aggregateSuiteStatus(results, Boolean(args["dry-run"]));
  const finishedAt = isoNow();
  const suite = {
    schemaVersion: 1,
    suiteId,
    program: "macos-ux-trace-harness",
    suiteName,
    platform: "macos",
    requestedFixtureProfile: requestedProfile,
    scenarioCount: selections.length,
    startedAt,
    finishedAt,
    status,
    launchMode: args["dry-run"] ? "dry-run" : "isolated-agent-instance",
    instrumentationFlags: {
      controlBus: !args["dry-run"],
      dryRun: Boolean(args["dry-run"]),
      computerUseWitness: false,
      mainDatabaseTraceWrites: false,
    },
    privateBoundary: {
      containsPrivateConversationText: false,
      containsReadablePrivateScreenshots: false,
      containsCredentials: false,
      publicSafe: true,
    },
    runs: results.map((result, index) => ({
      runId: result.runId,
      scenarioId: selections[index].scenarioId,
      fixtureProfile: selections[index].fixtureProfile,
      status: result.status,
      failures: result.failures,
      metrics: result.metrics,
      runDir: path.relative(suiteDir, result.runDir),
    })),
    artifactIndex: [
      "suite.json",
      "suite-metrics.json",
      "suite-failures.json",
      ...results.map((result) => path.relative(suiteDir, result.runDir)),
    ],
  };
  writeJson(path.join(suiteDir, "suite.json"), suite);
  writeJson(path.join(suiteDir, "suite-metrics.json"), { schemaVersion: 1, suiteId, metrics });
  writeJson(path.join(suiteDir, "suite-failures.json"), { schemaVersion: 1, suiteId, failures });
  const writtenBaselinePath = writeBaselineArtifact(args["write-baseline"], { suiteId, scenarioId: null, fixtureProfile: requestedProfile || "mixed" }, metrics);

  return {
    ok: status === "PASS",
    status,
    suiteId,
    suiteDir,
    scenarios: selections.length,
    failures: failures.length,
    metrics: metrics.length,
    baselinePath: writtenBaselinePath,
    runs: results.map((result, index) => ({
      runId: result.runId,
      scenarioId: selections[index].scenarioId,
      fixtureProfile: selections[index].fixtureProfile,
      status: result.status,
      runDir: result.runDir,
    })),
  };
}

async function selfTest() {
  const outDir = fs.mkdtempSync(path.join(os.tmpdir(), "clawix-ux-trace-self-test-"));
  const result = await runScenario({
    scenario: "startup-to-usable",
    "fixture-profile": "smoke",
    "dry-run": true,
    "out-dir": outDir,
  });
  const required = ["run.json", "events.jsonl", "metrics.json", "failures.json", "fixture-manifest.json", "baseline-comparison.json", "logs/failure-ui-states.jsonl"];
  for (const file of required) {
    if (!fs.existsSync(path.join(result.runDir, file))) {
      throw new Error(`self-test did not create ${file}`);
    }
  }
  const run = readJson(path.join(result.runDir, "run.json"));
  if (run.status !== "BLOCKED") throw new Error("dry-run self-test must produce BLOCKED run evidence");
  verifyEvidencePath(result.runDir);
  const suiteResult = await runSuite({
    suite: "p0",
    "fixture-profile": "smoke",
    "dry-run": true,
    "out-dir": outDir,
  });
  for (const file of ["suite.json", "suite-metrics.json", "suite-failures.json"]) {
    if (!fs.existsSync(path.join(suiteResult.suiteDir, file))) {
      throw new Error(`self-test did not create ${file}`);
    }
  }
  const suite = readJson(path.join(suiteResult.suiteDir, "suite.json"));
  if (suite.status !== "BLOCKED") throw new Error("dry-run suite self-test must produce BLOCKED suite evidence");
  verifyEvidencePath(suiteResult.suiteDir);
  return result;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const manifest = readJson(scenarioManifestPath);
  if (args.list) {
    const rows = (manifest.scenarios || []).map((scenario) => ({
      id: scenario.id,
      priority: scenario.priority,
      fixtureProfiles: scenario.fixtureProfiles,
      kpis: scenario.kpiRefs?.length || 0,
      steps: scenario.steps?.length || 0,
    }));
    console.log(JSON.stringify(rows, null, 2));
    return;
  }
  const result = args["self-test"] ? await selfTest() : args.suite ? await runSuite(args) : await runScenario(args);
  if (args.json) {
    console.log(JSON.stringify(result, null, 2));
  } else {
    console.log(`UX trace harness ${args.suite ? "suite" : "run"} ${result.status}: ${result.suiteDir || result.runDir}`);
  }
}

main().catch((error) => {
  console.error(error.message);
  if (process.env.CLAWIX_UX_TRACE_DEBUG) console.error(error.stack);
  process.exitCode = 1;
});
