#!/usr/bin/env node
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const schemaPath = path.join(rootDir, "docs/ui/ux-trace-evidence.schema.json");

function usage() {
  return `Usage:
  node scripts/verify_macos_ux_trace_evidence.mjs --path <run-or-suite-dir> [--json]
`;
}

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--json") {
      args.json = true;
      continue;
    }
    if (arg === "--path") {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) throw new Error("missing value for --path");
      args.path = value;
      index += 1;
      continue;
    }
    throw new Error(`unknown argument ${arg}`);
  }
  if (!args.path) throw new Error("missing --path");
  return args;
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function readJsonl(file) {
  const text = fs.existsSync(file) ? fs.readFileSync(file, "utf8").trim() : "";
  if (!text) return [];
  return text.split("\n").filter(Boolean).map((line, index) => {
    try {
      return JSON.parse(line);
    } catch (error) {
      throw new Error(`${file}:${index + 1} is not valid JSON: ${error.message}`);
    }
  });
}

function stableHash(value) {
  return `sha256:${crypto.createHash("sha256").update(JSON.stringify(value)).digest("hex")}`;
}

function fail(failures, message) {
  failures.push(message);
}

function requireFields(failures, object, label, fields) {
  for (const field of fields) {
    if (!object || !Object.hasOwn(object, field)) fail(failures, `${label} is missing ${field}`);
  }
}

function requireFile(failures, dir, relativePath) {
  const file = path.join(dir, relativePath);
  if (!fs.existsSync(file)) fail(failures, `${relativePath} is missing`);
  return file;
}

function validatePrivateBoundary(failures, boundary, label) {
  if (!boundary || typeof boundary !== "object") {
    fail(failures, `${label} is missing privateBoundary`);
    return;
  }
  for (const field of ["containsPrivateConversationText", "containsReadablePrivateScreenshots", "containsCredentials"]) {
    if (boundary[field] !== false) fail(failures, `${label}.privateBoundary.${field} must be false`);
  }
  if (boundary.publicSafe !== true) fail(failures, `${label}.privateBoundary.publicSafe must be true`);
}

function validateRun(runDir, schema, options = {}) {
  const failures = [];
  const requiredFiles = [
    "run.json",
    "events.jsonl",
    "metrics.json",
    "failures.json",
    "fixture-manifest.json",
    "baseline-comparison.json",
    "logs/failure-ui-states.jsonl",
  ];
  for (const relativePath of requiredFiles) requireFile(failures, runDir, relativePath);
  if (failures.length) return { ok: false, kind: "run", path: runDir, failures };

  const run = readJson(path.join(runDir, "run.json"));
  const metricsArtifact = readJson(path.join(runDir, "metrics.json"));
  const failuresArtifact = readJson(path.join(runDir, "failures.json"));
  const fixtureManifest = readJson(path.join(runDir, "fixture-manifest.json"));
  const baselineComparison = readJson(path.join(runDir, "baseline-comparison.json"));
  const events = readJsonl(path.join(runDir, "events.jsonl"));
  const failureStates = readJsonl(path.join(runDir, "logs/failure-ui-states.jsonl"));

  requireFields(failures, run, "run.json", schema.runRequiredFields);
  if (run.program !== "macos-ux-trace-harness") fail(failures, "run.json.program must be macos-ux-trace-harness");
  if (!schema.allowedRunStatuses.includes(run.status)) fail(failures, `run.json.status ${run.status} is not allowed`);
  validatePrivateBoundary(failures, run.privateBoundary, "run.json");
  for (const relativePath of requiredFiles) {
    if (!run.artifactIndex?.includes(relativePath)) fail(failures, `run.json.artifactIndex is missing ${relativePath}`);
  }

  if (metricsArtifact.runId !== run.runId) fail(failures, "metrics.json runId must match run.json");
  if (failuresArtifact.runId !== run.runId) fail(failures, "failures.json runId must match run.json");
  if (fixtureManifest.runId !== run.runId) fail(failures, "fixture-manifest.json runId must match run.json");
  if (baselineComparison.runId !== run.runId) fail(failures, "baseline-comparison.json runId must match run.json");
  if (fixtureManifest.generatedFixture?.privateBoundary || fixtureManifest.privateBoundary) {
    validatePrivateBoundary(failures, fixtureManifest.generatedFixture?.privateBoundary ?? fixtureManifest.privateBoundary, "fixture-manifest.json");
  } else if (fixtureManifest.privateContentExported !== false) {
    fail(failures, "fixture-manifest.json must either carry privateBoundary or privateContentExported=false");
  }

  const eventTypes = new Set(schema.eventTypes);
  const eventKeys = new Set();
  const eventsBySequence = new Map();
  let previousSequence = 0;
  for (const [index, event] of events.entries()) {
    const label = `events.jsonl:${index + 1}`;
    requireFields(failures, event, label, schema.eventRequiredFields);
    if (event.runId !== run.runId) fail(failures, `${label}.runId must match run.json`);
    if (event.scenarioId !== run.scenarioId) fail(failures, `${label}.scenarioId must match run.json`);
    if (event.fixtureProfile !== run.fixtureProfile) fail(failures, `${label}.fixtureProfile must match run.json`);
    if (!eventTypes.has(event.eventType)) fail(failures, `${label}.eventType ${event.eventType} is not declared`);
    if (!Number.isInteger(event.sequence) || event.sequence <= previousSequence) {
      fail(failures, `${label}.sequence must be strictly increasing`);
    }
    previousSequence = Number(event.sequence);
    const ref = `${event.sequence}:${event.eventType}:${event.stepId}`;
    eventKeys.add(ref);
    eventsBySequence.set(event.sequence, event);
  }
  if (!events.some((event) => event.eventType === "run.started")) fail(failures, "events.jsonl must include run.started");
  if (!events.some((event) => event.eventType === "run.completed")) fail(failures, "events.jsonl must include run.completed");

  const kpiIds = new Set();
  for (const [index, metric] of (metricsArtifact.metrics || []).entries()) {
    const label = `metrics.json.metrics[${index}]`;
    requireFields(failures, metric, label, schema.metricRequiredFields);
    kpiIds.add(metric.kpiId);
    for (const ref of metric.evidenceEventRefs || []) {
      if (!eventKeys.has(ref)) fail(failures, `${label}.evidenceEventRefs contains unknown event ref ${ref}`);
    }
  }

  const failureTypes = new Set(schema.failureTypes);
  const failureStateByRef = new Map();
  for (const state of failureStates) {
    const ref = `logs/failure-ui-states.jsonl#${state.sequence}`;
    failureStateByRef.set(ref, state);
    requireFields(failures, state, ref, [
      "schemaVersion",
      "runId",
      "scenarioId",
      "fixtureProfile",
      "sequence",
      "stepId",
      "actionId",
      "surfaceId",
      "controlId",
      "kpiId",
      "finalUIStateHash",
      "redactedState",
      "privateBoundary",
    ]);
    if (state.runId !== run.runId) fail(failures, `${ref}.runId must match run.json`);
    validatePrivateBoundary(failures, state.privateBoundary, ref);
  }

  for (const [index, failure] of (failuresArtifact.failures || []).entries()) {
    const label = `failures.json.failures[${index}]`;
    requireFields(failures, failure, label, ["type", "message"]);
    if (!failureTypes.has(failure.type)) fail(failures, `${label}.type ${failure.type} is not declared`);
    if (failure.kpiId && failure.kpiId !== "none" && !kpiIds.has(failure.kpiId)) {
      fail(failures, `${label}.kpiId ${failure.kpiId} has no metric row`);
    }
    if (failure.finalUIStateRef) {
      const state = failureStateByRef.get(failure.finalUIStateRef);
      if (!state) {
        fail(failures, `${label}.finalUIStateRef points to missing sidecar row ${failure.finalUIStateRef}`);
      } else if (state.finalUIStateHash !== failure.finalUIStateHash) {
        fail(failures, `${label}.finalUIStateHash must match sidecar row`);
      }
    }
  }

  for (const event of events.filter((item) => item.eventType === "capture.written" && item.artifactKind === "redacted-final-ui-state")) {
    const state = failureStateByRef.get(event.artifactPath);
    if (!state) {
      fail(failures, `capture.written ${event.sequence} points to missing sidecar row ${event.artifactPath}`);
    } else if (state.finalUIStateHash !== event.artifactHash) {
      fail(failures, `capture.written ${event.sequence} artifactHash must match sidecar row`);
    }
  }

  if (failureStates.length > 0 && !(failuresArtifact.failures || []).some((failure) => failure.finalUIStateRef)) {
    fail(failures, "failure UI state sidecar rows require matching failures.json finalUIStateRef");
  }
  if (!options.allowStatusMismatch && failuresArtifact.failures?.length > 0 && run.status === "PASS") {
    fail(failures, "run.json.status must not be PASS when failures.json has failures");
  }
  if (!options.allowStatusMismatch && failuresArtifact.failures?.length === 0 && run.status !== "PASS") {
    fail(failures, "run.json.status should be PASS when failures.json is empty");
  }
  if (stableHash(run).length < 10) fail(failures, "internal hash sanity failed");

  return {
    ok: failures.length === 0,
    kind: "run",
    path: runDir,
    runId: run.runId,
    status: run.status,
    events: events.length,
    metrics: (metricsArtifact.metrics || []).length,
    failures: (failuresArtifact.failures || []).length,
    failureUIStates: failureStates.length,
    validationFailures: failures,
  };
}

function validateSuite(suiteDir, schema) {
  const failures = [];
  for (const relativePath of ["suite.json", "suite-metrics.json", "suite-failures.json"]) {
    requireFile(failures, suiteDir, relativePath);
  }
  if (failures.length) return { ok: false, kind: "suite", path: suiteDir, failures };

  const suite = readJson(path.join(suiteDir, "suite.json"));
  const suiteMetrics = readJson(path.join(suiteDir, "suite-metrics.json"));
  const suiteFailures = readJson(path.join(suiteDir, "suite-failures.json"));
  requireFields(failures, suite, "suite.json", schema.suiteRequiredFields);
  if (suite.program !== "macos-ux-trace-harness") fail(failures, "suite.json.program must be macos-ux-trace-harness");
  if (!schema.allowedRunStatuses.includes(suite.status)) fail(failures, `suite.json.status ${suite.status} is not allowed`);
  validatePrivateBoundary(failures, suite.privateBoundary, "suite.json");
  if (suiteMetrics.suiteId !== suite.suiteId) fail(failures, "suite-metrics.json suiteId must match suite.json");
  if (suiteFailures.suiteId !== suite.suiteId) fail(failures, "suite-failures.json suiteId must match suite.json");

  const runResults = [];
  for (const [index, row] of (suite.runs || []).entries()) {
    requireFields(failures, row, `suite.json.runs[${index}]`, ["runId", "scenarioId", "fixtureProfile", "status", "runDir"]);
    const runDir = path.join(suiteDir, row.runDir);
    const runResult = validateRun(runDir, schema, { allowStatusMismatch: false });
    runResults.push(runResult);
    if (!runResult.ok) {
      fail(failures, `suite run ${row.runId} failed evidence validation`);
      for (const runFailure of runResult.validationFailures || runResult.failures || []) {
        fail(failures, `  ${row.runId}: ${runFailure}`);
      }
    }
    if (runResult.runId && runResult.runId !== row.runId) fail(failures, `suite.json.runs[${index}].runId must match child run`);
    if (runResult.status && runResult.status !== row.status) fail(failures, `suite.json.runs[${index}].status must match child run`);
  }
  if (suite.scenarioCount !== (suite.runs || []).length) fail(failures, "suite.json.scenarioCount must match runs.length");
  if ((suiteMetrics.metrics || []).length < runResults.reduce((sum, result) => sum + (result.metrics || 0), 0)) {
    fail(failures, "suite-metrics.json must include child run metrics");
  }
  if ((suiteFailures.failures || []).length < runResults.reduce((sum, result) => sum + (result.failures || 0), 0)) {
    fail(failures, "suite-failures.json must include child run failures");
  }

  return {
    ok: failures.length === 0,
    kind: "suite",
    path: suiteDir,
    suiteId: suite.suiteId,
    status: suite.status,
    runs: runResults.length,
    metrics: (suiteMetrics.metrics || []).length,
    failures: (suiteFailures.failures || []).length,
    validationFailures: failures,
  };
}

function validatePath(targetPath) {
  const resolved = path.resolve(targetPath);
  const schema = readJson(schemaPath);
  if (fs.existsSync(path.join(resolved, "suite.json"))) return validateSuite(resolved, schema);
  if (fs.existsSync(path.join(resolved, "run.json"))) return validateRun(resolved, schema);
  throw new Error(`${resolved} is not a UX trace run or suite directory`);
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const result = validatePath(args.path);
  if (args.json) {
    console.log(JSON.stringify(result, null, 2));
  } else {
    console.log(`UX trace evidence ${result.ok ? "valid" : "invalid"}: ${result.path}`);
    for (const failure of result.validationFailures || result.failures || []) {
      console.error(`- ${failure}`);
    }
  }
  if (!result.ok) process.exitCode = 1;
}

main();
