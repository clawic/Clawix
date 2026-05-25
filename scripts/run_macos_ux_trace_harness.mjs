#!/usr/bin/env node
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const registryPath = path.join(rootDir, "docs/ui/ux-trace-harness.registry.json");
const scenarioManifestPath = path.join(rootDir, "docs/ui/ux-trace-scenarios.manifest.json");
const evidenceSchemaPath = path.join(rootDir, "docs/ui/ux-trace-evidence.schema.json");

const defaultTimeoutMs = 5_000;
const defaultPollMs = 50;
const defaultDurationMs = 250;
const defaultTolerancePx = 1;
const maxIncludeDepth = 8;

function usage() {
  return `Usage:
  node scripts/run_macos_ux_trace_harness.mjs --list
  node scripts/run_macos_ux_trace_harness.mjs --self-test
  node scripts/run_macos_ux_trace_harness.mjs --dry-run --scenario <id> --fixture-profile <id> [--out-dir <dir>]
  node scripts/run_macos_ux_trace_harness.mjs --control-url <url> --token <token> --scenario <id> --fixture-profile <id> [--out-dir <dir>]

Options:
  --scenario <id>          Scenario id from docs/ui/ux-trace-scenarios.manifest.json.
  --fixture-profile <id>   Fixture profile declared by the scenario.
  --control-url <url>      Agent control bus base URL, for example http://127.0.0.1:24500.
  --token <token>          Owner token for the isolated agent instance.
  --out-dir <dir>          Evidence root. Defaults to a temporary directory.
  --baseline <file>        Optional metrics.json or baseline-comparison source.
  --timeout-ms <n>         Default wait timeout.
  --poll-ms <n>            Default wait poll interval.
  --request-timeout-ms <n> Default HTTP request timeout.
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
    if (["dry-run", "json", "list", "self-test"].includes(key)) {
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

function runIdFor(scenarioId, fixtureProfile) {
  const stamp = new Date().toISOString().replace(/[-:.TZ]/g, "").slice(0, 14);
  const suffix = crypto.randomBytes(4).toString("hex");
  return `uxtrace-${scenarioId}-${fixtureProfile}-${stamp}-${suffix}`;
}

function boundedInteger(value, fallback, min, max) {
  const parsed = Number.parseInt(value ?? "", 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, parsed));
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
  const eventRefs = [];
  return {
    write(fields) {
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
      fs.appendFileSync(file, `${JSON.stringify(event)}\n`);
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
  if (step.action === "type") return "type";
  if (step.action === "mock-stream" || step.action === "mock-bridge-stream") return step.action;
  if (step.action === "measure-action") return "click";
  if (step.action === "snapshot") return "mark";
  return null;
}

function verbForStep(step) {
  if (step.action === "measure-action" || ["scroll", "type", "mock-stream", "mock-bridge-stream", "snapshot"].includes(step.action)) {
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
  if (step.text) body.text = step.text;
  if (step.direction) body.direction = step.direction;
  if (step.pages) body.pages = step.pages;
  if (step.contains) body.contains = step.contains;
  if (step.query) body.query = step.query;
  if (step.minCount) body.minCount = step.minCount;
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

function stepSurfaceId(step, indexes) {
  if (indexes.surfaceIds.has(step.target)) return step.target;
  return "app.shell.firstUsableWindow";
}

function stepKpiId(step, scenario, indexes) {
  const explicit = step.kpi || step.kpiId;
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

async function runScenario(args) {
  const registry = readJson(registryPath);
  const manifest = readJson(scenarioManifestPath);
  const indexes = buildIndexes(registry, manifest);
  const { scenario, scenarioId, fixtureProfile } = validateScenarioSelection(args, indexes);
  const runId = args["run-id"] || runIdFor(scenarioId, fixtureProfile);
  const runDir = mkdirEvidence(args["out-dir"], runId);
  const startedAt = isoNow();
  const events = eventWriter(path.join(runDir, "events.jsonl"), { runId, scenarioId, fixtureProfile });
  const failures = [];
  const kpiSamples = new Map();
  const baseline = readBaseline(args.baseline);
  const options = {
    dryRun: Boolean(args["dry-run"]),
    controlUrl: args["control-url"],
    token: args.token,
    timeoutMs: boundedInteger(args["timeout-ms"], defaultTimeoutMs, 100, 120_000),
    pollMs: boundedInteger(args["poll-ms"], defaultPollMs, 10, 5_000),
    requestTimeoutMs: boundedInteger(args["request-timeout-ms"], Math.max(boundedInteger(args["timeout-ms"], defaultTimeoutMs, 100, 120_000) + 2_000, 5_000), 500, 180_000),
  };
  if (!options.dryRun) {
    requireString(options.controlUrl, "--control-url");
    requireString(options.token, "--token");
  }

  const expandedSteps = expandScenarioSteps(scenario, indexes);
  events.write({ eventType: "run.started", stepId: "run", actionId: runId });
  events.write({ eventType: "fixture.loaded", stepId: "fixture", actionId: fixtureProfile });
  events.write({ eventType: "scenario.started", stepId: scenarioId, actionId: scenarioId });

  for (const step of expandedSteps) {
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
      const elapsedMs = elapsedFromPayload(payload, Math.round(performance.now() - started));
      if (!kpiSamples.has(kpiId)) kpiSamples.set(kpiId, []);
      if (kpiId !== "none") kpiSamples.get(kpiId).push(elapsedMs);
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
        failures.push({
          type: options.dryRun ? "external_pending" : "condition_timeout",
          stepId: step.id,
          surfaceId,
          kpiId,
          message: options.dryRun ? "dry-run evidence only" : `condition did not complete for ${step.wait}`,
        });
      }
    } catch (error) {
      const failure = {
        type: "instrumentation_error",
        stepId: step.id,
        surfaceId,
        kpiId,
        message: error.message,
        payloadHash: error.payload ? stableHash(error.payload) : null,
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

  events.write({ eventType: "scenario.completed", stepId: scenarioId, actionId: scenarioId });
  const status = failures.length === 0 ? "PASS" : options.dryRun ? "BLOCKED" : "FAIL";
  events.write({ eventType: "run.completed", stepId: "run", actionId: runId, status });
  events.close();

  const metrics = (scenario.kpiRefs || []).map((kpiId) => {
    const kpi = indexes.kpisById.get(kpiId);
    return makeMetric(kpi, kpiSamples.get(kpiId) || [], events.eventRefs, baseline.get(kpiId));
  });
  const baselineComparison = {
    schemaVersion: 1,
    runId,
    scenarioId,
    fixtureProfile,
    baselinePath: args.baseline || null,
    status: args.baseline ? "compared" : "baseline_missing",
    comparisons: metrics.map((metric) => ({
      kpiId: metric.kpiId,
      p95: metric.p95,
      baseline: metric.baseline,
      regressionPercent: metric.regressionPercent,
      status: metric.baseline === null ? "baseline_missing" : "compared",
    })),
  };
  const finishedAt = isoNow();
  const run = {
    schemaVersion: 1,
    runId,
    program: "macos-ux-trace-harness",
    scenarioId,
    fixtureProfile,
    fixtureSeed: args["fixture-seed"] || "default",
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
  });
  writeJson(path.join(runDir, "baseline-comparison.json"), baselineComparison);

  return { ok: status === "PASS", status, runId, runDir, failures: failures.length, metrics: metrics.length };
}

async function selfTest() {
  const outDir = fs.mkdtempSync(path.join(os.tmpdir(), "clawix-ux-trace-self-test-"));
  const result = await runScenario({
    scenario: "startup-to-usable",
    "fixture-profile": "smoke",
    "dry-run": true,
    "out-dir": outDir,
  });
  const required = ["run.json", "events.jsonl", "metrics.json", "failures.json", "fixture-manifest.json", "baseline-comparison.json"];
  for (const file of required) {
    if (!fs.existsSync(path.join(result.runDir, file))) {
      throw new Error(`self-test did not create ${file}`);
    }
  }
  const run = readJson(path.join(result.runDir, "run.json"));
  if (run.status !== "BLOCKED") throw new Error("dry-run self-test must produce BLOCKED run evidence");
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
  const result = args["self-test"] ? await selfTest() : await runScenario(args);
  if (args.json) {
    console.log(JSON.stringify(result, null, 2));
  } else {
    console.log(`UX trace harness run ${result.status}: ${result.runDir}`);
  }
}

main().catch((error) => {
  console.error(error.message);
  if (process.env.CLAWIX_UX_TRACE_DEBUG) console.error(error.stack);
  process.exitCode = 1;
});
