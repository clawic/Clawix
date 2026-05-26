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

function fileContentHash(file) {
  return `sha256:${crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex")}`;
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

function isRelativeSafe(relativePath) {
  return typeof relativePath === "string" && relativePath.length > 0 && !relativePath.startsWith("..") && !path.isAbsolute(relativePath);
}

function validateTraceIsolation(failures, isolation, label, expectedNameField, expectedName) {
  requireFields(failures, isolation, `${label}.traceIsolation`, [
    "mode",
    "evidenceRootName",
    "evidenceRootHash",
    "globalSharedTraceFile",
    "mainDatabaseTraceWrites",
    "parallelSafe",
  ]);
  if (isolation?.globalSharedTraceFile !== false) fail(failures, `${label}.traceIsolation.globalSharedTraceFile must be false`);
  if (isolation?.mainDatabaseTraceWrites !== false) fail(failures, `${label}.traceIsolation.mainDatabaseTraceWrites must be false`);
  if (isolation?.parallelSafe !== true) fail(failures, `${label}.traceIsolation.parallelSafe must be true`);
  if (expectedNameField && isolation?.[expectedNameField] !== expectedName) {
    fail(failures, `${label}.traceIsolation.${expectedNameField} must be ${expectedName}`);
  }
}

function validateOverheadCalibration(failures, overhead, label, schema) {
  requireFields(failures, overhead, `${label}.overheadCalibration`, schema.overheadCalibrationRequiredFields || [
    "status",
    "harnessMode",
    "feasible",
    "controlRun",
    "instrumentationOverheadEstimate",
    "traceWriter",
  ]);
  const allowed = new Set(schema.overheadCalibrationContract?.statusValues || []);
  if (allowed.size > 0 && !allowed.has(overhead?.status)) {
    fail(failures, `${label}.overheadCalibration.status must be one of ${[...allowed].join(", ")}`);
  }
  if (overhead?.feasible !== true) fail(failures, `${label}.overheadCalibration.feasible must be true`);
  if (!overhead?.controlRun || typeof overhead.controlRun !== "object") {
    fail(failures, `${label}.overheadCalibration.controlRun must be an object`);
  } else if (Object.hasOwn(overhead.controlRun, "path")) {
    fail(failures, `${label}.overheadCalibration.controlRun must not include a local path`);
  }
  const estimate = overhead?.instrumentationOverheadEstimate;
  requireFields(failures, estimate, `${label}.overheadCalibration.instrumentationOverheadEstimate`, [
    "measured",
    "status",
    "unit",
  ]);
  if (estimate?.status !== overhead?.status) {
    fail(failures, `${label}.overheadCalibration.instrumentationOverheadEstimate.status must match overheadCalibration.status`);
  }
  const writer = overhead?.traceWriter;
  requireFields(failures, writer, `${label}.overheadCalibration.traceWriter`, [
    "eventCount",
    "eventBytes",
    "maxEventsPerRun",
    "maxEventBytesPerRun",
    "bounded",
  ]);
  const bounds = schema.overheadCalibrationContract?.traceWriterBounds || {};
  if (writer?.bounded !== true) fail(failures, `${label}.overheadCalibration.traceWriter.bounded must be true`);
  if (Number(writer?.eventCount) > Number(bounds.maxEventsPerRun ?? Number.POSITIVE_INFINITY)) {
    fail(failures, `${label}.overheadCalibration.traceWriter.eventCount exceeds maxEventsPerRun`);
  }
  if (Number(writer?.eventBytes) > Number(bounds.maxEventBytesPerRun ?? Number.POSITIVE_INFINITY)) {
    fail(failures, `${label}.overheadCalibration.traceWriter.eventBytes exceeds maxEventBytesPerRun`);
  }
  if (
    Object.hasOwn(writer || {}, "failureUIStateBytes")
    && Number(writer.failureUIStateBytes) > Number(bounds.maxFailureUIStateBytesPerRun ?? Number.POSITIVE_INFINITY)
  ) {
    fail(failures, `${label}.overheadCalibration.traceWriter.failureUIStateBytes exceeds maxFailureUIStateBytesPerRun`);
  }
}

function validateEvidenceSources(failures, sources, label, schema) {
  requireFields(failures, sources, `${label}.evidenceSources`, schema.evidenceSourcesRequiredFields || [
    "registry",
    "scenarioManifest",
    "evidenceSchema",
    "fixtureGenerator",
    "evidenceVerifier",
  ]);
  const requiredIds = new Set(schema.evidenceSourcesContract?.requiredSourceIds || []);
  for (const [sourceKey, source] of Object.entries(sources || {})) {
    if (sourceKey === "schemaVersion") continue;
    requireFields(failures, source, `${label}.evidenceSources.${sourceKey}`, ["id", "path", "contentHash"]);
    if (requiredIds.size > 0 && !requiredIds.has(source?.id)) {
      fail(failures, `${label}.evidenceSources.${sourceKey}.id is not an approved source id`);
    }
    if (!isRelativeSafe(source?.path)) {
      fail(failures, `${label}.evidenceSources.${sourceKey}.path must be repo-relative and safe`);
      continue;
    }
    const absolutePath = path.join(rootDir, source.path);
    if (!fs.existsSync(absolutePath)) {
      fail(failures, `${label}.evidenceSources.${sourceKey}.path points to missing source`);
      continue;
    }
    if (typeof source?.contentHash !== "string" || !source.contentHash.startsWith("sha256:")) {
      fail(failures, `${label}.evidenceSources.${sourceKey}.contentHash must be a sha256 hash`);
    } else if (source.contentHash !== fileContentHash(absolutePath)) {
      fail(failures, `${label}.evidenceSources.${sourceKey}.contentHash does not match current source content`);
    }
  }
}

function validateExitPolicy(failures, policy, status, label, schema) {
  requireFields(failures, policy, `${label}.exitPolicy`, schema.exitPolicyRequiredFields || [
    "gate",
    "gateEnforced",
    "nonZeroOnStatuses",
    "computedExitCode",
    "reason",
  ]);
  if (!Array.isArray(policy?.nonZeroOnStatuses)) {
    fail(failures, `${label}.exitPolicy.nonZeroOnStatuses must be an array`);
    return;
  }
  const allowed = new Set(schema.exitPolicyContract?.allowedNonZeroStatuses || []);
  for (const row of policy.nonZeroOnStatuses) {
    if (allowed.size > 0 && !allowed.has(row)) {
      fail(failures, `${label}.exitPolicy.nonZeroOnStatuses contains unsupported status ${row}`);
    }
  }
  const expectedExitCode = policy.nonZeroOnStatuses.includes(status) ? 1 : 0;
  if (policy.computedExitCode !== expectedExitCode) {
    fail(failures, `${label}.exitPolicy.computedExitCode must be ${expectedExitCode} for status ${status}`);
  }
  if (policy.gate === "p0") {
    if (policy.gateEnforced !== true) fail(failures, `${label}.exitPolicy.gateEnforced must be true for p0 gate`);
    for (const statusName of ["FAIL", "INVALID"]) {
      if (!policy.nonZeroOnStatuses.includes(statusName)) {
        fail(failures, `${label}.exitPolicy.nonZeroOnStatuses must include ${statusName} for p0 gate`);
      }
    }
  }
}

function validateArtifactIndex(failures, rows, label) {
  for (const row of rows || []) {
    if (!isRelativeSafe(row)) fail(failures, `${label}.artifactIndex contains unsafe path ${row}`);
  }
}

function validatePathReference(failures, value, label) {
  if (!value || typeof value !== "object") {
    fail(failures, `${label} must be a public-safe path reference object`);
    return;
  }
  if (value.kind === "relative-to-run") {
    if (!isRelativeSafe(value.path)) fail(failures, `${label}.path must be relative and safe`);
    return;
  }
  if (value.kind === "external-hash-only") {
    if (typeof value.pathHash !== "string" || !value.pathHash.startsWith("sha256:")) {
      fail(failures, `${label}.pathHash must be a sha256 hash`);
    }
    if (Object.hasOwn(value, "path")) fail(failures, `${label} must not include an external local path`);
    return;
  }
  fail(failures, `${label}.kind must be relative-to-run or external-hash-only`);
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
  validateExitPolicy(failures, run.exitPolicy, run.status, "run.json", schema);
  validateEvidenceSources(failures, run.evidenceSources, "run.json", schema);
  validateTraceIsolation(failures, run.traceIsolation, "run.json", "runDirectoryName", path.basename(runDir));
  if (run.traceIsolation?.runDirectoryMatchesRunId !== true) fail(failures, "run.json.traceIsolation.runDirectoryMatchesRunId must be true");
  validateOverheadCalibration(failures, run.overheadCalibration, "run.json", schema);
  validateArtifactIndex(failures, run.artifactIndex, "run.json");
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
  if (fixtureManifest.generatedFixture) {
    validatePathReference(failures, fixtureManifest.generatedFixture.path, "fixture-manifest.json.generatedFixture.path");
    validatePathReference(failures, fixtureManifest.generatedFixture.manifestPath, "fixture-manifest.json.generatedFixture.manifestPath");
  }

  const eventTypes = new Set(schema.eventTypes);
  const eventKeys = new Set();
  const eventsBySequence = new Map();
  const sampleCounts = {
    geometry: 0,
    scroll: 0,
    renderWindow: 0,
    hitch: 0,
    resource: 0,
    database: 0,
    bridge: 0,
  };
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
    if (event.eventType === "geometry.sample") {
      sampleCounts.geometry += 1;
      if (!Number.isFinite(Number(event.sample?.frame?.width)) || !Number.isFinite(Number(event.sample?.frame?.height))) {
        fail(failures, `${label}.sample.frame must include numeric width and height`);
      }
    }
    if (event.eventType === "scroll.sample") {
      sampleCounts.scroll += 1;
      if (
        !Number.isFinite(Number(event.sample?.scroll?.topDistance))
        && !Number.isFinite(Number(event.sample?.scroll?.bottomDistance))
        && !Number.isFinite(Number(event.sample?.scroll?.scrollPosition))
      ) {
        fail(failures, `${label}.sample.scroll must include numeric scroll distance or position`);
      }
    }
    if (event.eventType === "render.window") {
      sampleCounts.renderWindow += 1;
      if (!Number.isFinite(Number(event.sample?.visibleCount)) && !Number.isFinite(Number(event.sample?.totalCount))) {
        fail(failures, `${label}.sample must include visibleCount or totalCount`);
      }
    }
    if (event.eventType === "hitch.sample") {
      sampleCounts.hitch += 1;
      if (event.total !== null && !Number.isFinite(Number(event.total))) fail(failures, `${label}.total must be numeric or null`);
    }
    if (event.eventType === "resource.sample") {
      sampleCounts.resource += 1;
      if (
        !Number.isFinite(Number(event.sample?.residentBytes))
        && !Number.isFinite(Number(event.sample?.residentMB))
        && !Number.isFinite(Number(event.sample?.footprintBytes))
        && !Number.isFinite(Number(event.sample?.footprintMB))
      ) {
        fail(failures, `${label}.sample must include resident or footprint data`);
      }
    }
    if (event.eventType === "database.sample") {
      sampleCounts.database += 1;
      if (!Number.isFinite(Number(event.rows))) fail(failures, `${label}.rows must be numeric`);
    }
    if (event.eventType === "bridge.sample") {
      sampleCounts.bridge += 1;
      if (!Number.isFinite(Number(event.bytes))) fail(failures, `${label}.bytes must be numeric`);
    }
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
    sampleCounts,
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
  validateExitPolicy(failures, suite.exitPolicy, suite.status, "suite.json", schema);
  validateEvidenceSources(failures, suite.evidenceSources, "suite.json", schema);
  validateTraceIsolation(failures, suite.traceIsolation, "suite.json", "suiteDirectoryName", path.basename(suiteDir));
  if (suite.traceIsolation?.suiteDirectoryMatchesSuiteId !== true) fail(failures, "suite.json.traceIsolation.suiteDirectoryMatchesSuiteId must be true");
  validateOverheadCalibration(failures, suite.overheadCalibration, "suite.json", schema);
  validateArtifactIndex(failures, suite.artifactIndex, "suite.json");
  if (suiteMetrics.suiteId !== suite.suiteId) fail(failures, "suite-metrics.json suiteId must match suite.json");
  if (suiteFailures.suiteId !== suite.suiteId) fail(failures, "suite-failures.json suiteId must match suite.json");

  const runResults = [];
  for (const [index, row] of (suite.runs || []).entries()) {
    requireFields(failures, row, `suite.json.runs[${index}]`, ["runId", "scenarioId", "fixtureProfile", "status", "runDir"]);
    if (!isRelativeSafe(row.runDir)) fail(failures, `suite.json.runs[${index}].runDir must be relative and safe`);
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
