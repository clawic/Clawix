#!/usr/bin/env node
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const schemaPath = path.join(rootDir, "docs/ui/ux-trace-evidence.schema.json");
const registryPath = path.join(rootDir, "docs/ui/ux-trace-harness.registry.json");

function usage() {
  return `Usage:
  node scripts/verify_macos_ux_trace_evidence.mjs --path <run-or-suite-dir-or-baseline-json> [--json]
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

let kpiRegistryById = null;
function kpiRegistry() {
  if (!kpiRegistryById) {
    const registry = readJson(registryPath);
    kpiRegistryById = new Map((registry.kpis || []).map((kpi) => [kpi.id, kpi]));
  }
  return kpiRegistryById;
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

function requireArrayField(failures, object, label, field) {
  if (!Array.isArray(object?.[field])) {
    fail(failures, `${label}.${field} must be an array`);
    return [];
  }
  return object[field];
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

function validateTraceIsolation(failures, isolation, label, expectedNameField, expectedName, evidenceDir = null) {
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
  if (evidenceDir) {
    const evidenceRoot = path.dirname(evidenceDir);
    if (isolation?.evidenceRootName !== path.basename(evidenceRoot)) {
      fail(failures, `${label}.traceIsolation.evidenceRootName must match evidence parent directory`);
    }
    if (isolation?.evidenceRootHash !== stableHash(evidenceRoot)) {
      fail(failures, `${label}.traceIsolation.evidenceRootHash must match evidence parent directory`);
    }
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
  if (overhead?.status === "external_pending_control_run") {
    if (overhead.controlRun?.available !== false) fail(failures, `${label}.overheadCalibration.controlRun.available must be false when status is external_pending_control_run`);
    if (estimate?.measured !== false) fail(failures, `${label}.overheadCalibration.instrumentationOverheadEstimate.measured must be false when status is external_pending_control_run`);
  }
  if (overhead?.status === "compared") {
    if (overhead.controlRun?.available !== true) fail(failures, `${label}.overheadCalibration.controlRun.available must be true when status is compared`);
    if (overhead.controlRun?.highCardinalityInstrumentation !== false) fail(failures, `${label}.overheadCalibration.controlRun.highCardinalityInstrumentation must be false for harness-disabled controls`);
    for (const hashField of ["artifactHash", "pathHash"]) {
      if (typeof overhead.controlRun?.[hashField] !== "string" || !overhead.controlRun[hashField].startsWith("sha256:")) {
        fail(failures, `${label}.overheadCalibration.controlRun.${hashField} must be a sha256 hash when status is compared`);
      }
    }
    if (estimate?.measured !== true) fail(failures, `${label}.overheadCalibration.instrumentationOverheadEstimate.measured must be true when status is compared`);
    for (const numberField of ["currentTotalP95", "controlTotalP95", "delta"]) {
      if (!Number.isFinite(Number(estimate?.[numberField]))) {
        fail(failures, `${label}.overheadCalibration.instrumentationOverheadEstimate.${numberField} must be numeric when status is compared`);
      }
    }
    if (estimate?.percentDelta !== null && !Number.isFinite(Number(estimate?.percentDelta))) {
      fail(failures, `${label}.overheadCalibration.instrumentationOverheadEstimate.percentDelta must be numeric or null when status is compared`);
    }
  }
  if (overhead?.status === "control_artifact_without_comparable_metrics") {
    if (overhead.controlRun?.available !== true) fail(failures, `${label}.overheadCalibration.controlRun.available must be true when a control artifact is present`);
    if (overhead.controlRun?.highCardinalityInstrumentation !== false) fail(failures, `${label}.overheadCalibration.controlRun.highCardinalityInstrumentation must be false for harness-disabled controls`);
    if (estimate?.measured !== false) fail(failures, `${label}.overheadCalibration.instrumentationOverheadEstimate.measured must be false when control metrics are not comparable`);
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
  const requiredSources = schema.evidenceSourcesContract?.requiredSources || {};
  for (const [sourceKey, source] of Object.entries(sources || {})) {
    if (sourceKey === "schemaVersion") continue;
    requireFields(failures, source, `${label}.evidenceSources.${sourceKey}`, ["id", "path", "contentHash"]);
    const expectedSource = requiredSources[sourceKey];
    if (expectedSource?.id && source?.id !== expectedSource.id) {
      fail(failures, `${label}.evidenceSources.${sourceKey}.id must be ${expectedSource.id}`);
    }
    if (expectedSource?.path && source?.path !== expectedSource.path) {
      fail(failures, `${label}.evidenceSources.${sourceKey}.path must be ${expectedSource.path}`);
    }
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

function validateArtifactIndex(failures, rows, label, baseDir = null) {
  if (!Array.isArray(rows)) {
    fail(failures, `${label}.artifactIndex must be an array`);
    return;
  }
  for (const row of rows) {
    if (!isRelativeSafe(row)) {
      fail(failures, `${label}.artifactIndex contains unsafe path ${row}`);
      continue;
    }
    if (baseDir && !fs.existsSync(path.join(baseDir, row))) {
      fail(failures, `${label}.artifactIndex path must exist: ${row}`);
    }
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

const baselineComparisonStatuses = new Set(["gate_passed", "gate_failed", "baseline_missing", "compared"]);
const baselineComparisonRowStatuses = new Set(["baseline_missing", "baseline_regression", "compared"]);

function baselineComparisonMetricKey(row) {
  return [row?.runId || "", row?.scenarioId || "", row?.fixtureProfile || "", row?.kpiId || ""].join("\u001f");
}

function baselineFailureKey(row, type) {
  return [row?.runId || "", row?.scenarioId || "", row?.fixtureProfile || "", row?.kpiId || "", type].join("\u001f");
}

function failureEventKey(row) {
  return [row?.stepId || "", row?.actionId || "", row?.surfaceId || "", row?.controlId || "", row?.kpiId || ""].join("\u001f");
}

function stableAggregateKey(fields, row) {
  return JSON.stringify(Object.fromEntries(fields.map((field) => [field, row?.[field] ?? null])));
}

function addMultisetRow(map, key) {
  map.set(key, (map.get(key) || 0) + 1);
}

function addEventRow(map, key, event) {
  const rows = map.get(key) || [];
  rows.push(event);
  map.set(key, rows);
}

function compareMultisets(failures, label, expected, actual) {
  for (const [key, count] of expected.entries()) {
    if ((actual.get(key) || 0) !== count) {
      fail(failures, `${label} is missing expected child row ${key}`);
    }
  }
  for (const [key, count] of actual.entries()) {
    if ((expected.get(key) || 0) !== count) {
      fail(failures, `${label} contains row not emitted by child runs ${key}`);
    }
  }
}

function validateMetricsAgainstRegistry(failures, metrics, label) {
  const registry = kpiRegistry();
  for (const [index, metric] of metrics.entries()) {
    const rowLabel = `${label}[${index}]`;
    const kpi = registry.get(metric?.kpiId);
    if (!kpi) {
      fail(failures, `${rowLabel}.kpiId ${metric?.kpiId} is not declared in ux-trace-harness.registry.json`);
      continue;
    }
    if (metric.priority !== kpi.priority) fail(failures, `${rowLabel}.priority must match KPI registry`);
    if (metric.surface !== kpi.surface) fail(failures, `${rowLabel}.surface must match KPI registry`);
  }
}

function comparisonValueMatchesMetric(rowValue, metricValue) {
  if (rowValue === null || metricValue === null || rowValue === undefined || metricValue === undefined) {
    return rowValue === metricValue;
  }
  if (typeof rowValue === "string" || typeof metricValue === "string") {
    return rowValue === metricValue;
  }
  return Number.isFinite(Number(rowValue)) && Number(rowValue) === Number(metricValue);
}

function expectedBaselineComparisonStatus(comparison) {
  if (comparison.comparisons.some((row) => row.status === "baseline_regression")) {
    return comparison.gate ? "gate_failed" : "compared";
  }
  if (comparison.comparisons.some((row) => row.status === "baseline_missing")) {
    return "baseline_missing";
  }
  return comparison.gate ? "gate_passed" : "compared";
}

function expectedSuiteStatus(childStatuses, launchMode) {
  if (childStatuses.every((status) => status === "PASS")) return "PASS";
  if (launchMode === "dry-run" && childStatuses.every((status) => status === "BLOCKED")) return "BLOCKED";
  if (childStatuses.some((status) => status === "FAIL")) return "FAIL";
  if (childStatuses.some((status) => status === "BLOCKED" || status === "PARTIAL")) return "PARTIAL";
  return "FAIL";
}

function validateBaselineComparison(failures, comparison, label = "baseline-comparison.json", options = {}) {
  if (!comparison || typeof comparison !== "object") {
    fail(failures, `${label} must be an object`);
    return;
  }
  if (Object.hasOwn(comparison, "baselinePath")) {
    fail(failures, `${label} must not include raw baselinePath`);
  }
  if (comparison.baselineReference) {
    validatePathReference(failures, comparison.baselineReference, `${label}.baselineReference`);
  }
  requireFields(failures, comparison, label, ["schemaVersion", "status", "comparisons"]);
  if (comparison.schemaVersion !== 1) fail(failures, `${label}.schemaVersion must be 1`);
  if (!baselineComparisonStatuses.has(comparison.status)) {
    fail(failures, `${label}.status ${comparison.status} is not allowed`);
  }
  if (comparison.gate !== null && comparison.gate !== undefined) {
    if (typeof comparison.gate !== "object") {
      fail(failures, `${label}.gate must be null or an object`);
    } else {
      requireFields(failures, comparison.gate, `${label}.gate`, ["priority", "maxRegressionPercent"]);
      if (typeof comparison.gate.priority !== "string" || !/^P[0-2]$/.test(comparison.gate.priority)) {
        fail(failures, `${label}.gate.priority must be P0, P1, or P2`);
      }
      if (!Number.isFinite(Number(comparison.gate.maxRegressionPercent))) {
        fail(failures, `${label}.gate.maxRegressionPercent must be numeric`);
      }
    }
  }
  if (!Array.isArray(comparison.comparisons)) {
    fail(failures, `${label}.comparisons must be an array`);
    return;
  }
  if (Number.isInteger(options.expectedCount) && comparison.comparisons.length !== options.expectedCount) {
    fail(failures, `${label}.comparisons must include one row per metric`);
  }
  const seenRows = new Set();
  const failureKeys = new Set((options.failureRows || []).map((failure) => baselineFailureKey(failure, failure?.type || "")));
  for (const [index, row] of comparison.comparisons.entries()) {
    const rowLabel = `${label}.comparisons[${index}]`;
    requireFields(failures, row, rowLabel, ["kpiId", "priority", "surface", "p95", "baseline", "regressionPercent", "status"]);
    if (typeof row?.kpiId !== "string" || row.kpiId.length === 0) {
      fail(failures, `${rowLabel}.kpiId must be a non-empty string`);
    } else {
      const metricKey = baselineComparisonMetricKey(row);
      if (seenRows.has(metricKey)) fail(failures, `${rowLabel}.kpiId duplicates ${row.kpiId} for the same run/scenario/fixture`);
      seenRows.add(metricKey);
      if (options.metricKeys && !options.metricKeys.has(metricKey)) {
        fail(failures, `${rowLabel}.kpiId ${row.kpiId} has no matching metric row`);
      }
      const metric = options.metricRows?.get(metricKey);
      if (metric) {
        for (const field of ["priority", "surface", "p95", "baseline", "regressionPercent"]) {
          if (!comparisonValueMatchesMetric(row[field], metric[field])) {
            fail(failures, `${rowLabel}.${field} must match the emitted metric row`);
          }
        }
      }
    }
    if (typeof row?.priority !== "string" || !/^P[0-2]$/.test(row.priority)) {
      fail(failures, `${rowLabel}.priority must be P0, P1, or P2`);
    }
    if (typeof row?.surface !== "string" || row.surface.length === 0) {
      fail(failures, `${rowLabel}.surface must be a non-empty string`);
    }
    if (!Number.isFinite(Number(row?.p95))) fail(failures, `${rowLabel}.p95 must be numeric`);
    if (row?.baseline !== null && !Number.isFinite(Number(row?.baseline))) {
      fail(failures, `${rowLabel}.baseline must be numeric or null`);
    }
    if (row?.regressionPercent !== null && !Number.isFinite(Number(row?.regressionPercent))) {
      fail(failures, `${rowLabel}.regressionPercent must be numeric or null`);
    }
    if (!baselineComparisonRowStatuses.has(row?.status)) {
      fail(failures, `${rowLabel}.status ${row?.status} is not allowed`);
    }
    if (row?.status === "baseline_missing" && row?.baseline !== null) {
      fail(failures, `${rowLabel}.status baseline_missing requires baseline=null`);
    }
    if (row?.status === "compared" && row?.baseline === null) {
      fail(failures, `${rowLabel}.status compared requires a numeric baseline`);
    }
    if (row?.status === "baseline_regression") {
      if (row?.baseline === null) fail(failures, `${rowLabel}.status baseline_regression requires a numeric baseline`);
      if (row?.regressionPercent === null || !Number.isFinite(Number(row?.regressionPercent))) {
        fail(failures, `${rowLabel}.status baseline_regression requires numeric regressionPercent`);
      }
      if (
        comparison.gate
        && row?.priority === comparison.gate.priority
        && Number(row?.regressionPercent) <= Number(comparison.gate.maxRegressionPercent)
      ) {
        fail(failures, `${rowLabel}.status baseline_regression must exceed gate.maxRegressionPercent`);
      }
    }
    if (
      comparison.gate
      && row?.priority === comparison.gate.priority
      && (row?.status === "baseline_missing" || row?.status === "baseline_regression")
      && options.failureRows
      && !failureKeys.has(baselineFailureKey(row, row.status))
    ) {
      fail(failures, `${rowLabel}.status ${row.status} requires a matching failures.json row`);
    }
  }
  const expectedStatus = expectedBaselineComparisonStatus(comparison);
  if (comparison.status !== expectedStatus) {
    fail(failures, `${label}.status must be ${expectedStatus} for its comparison rows and gate`);
  }
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
  requireFields(failures, metricsArtifact, "metrics.json", ["schemaVersion", "runId", "metrics"]);
  requireFields(failures, failuresArtifact, "failures.json", ["schemaVersion", "runId", "failures"]);
  const metricList = requireArrayField(failures, metricsArtifact, "metrics.json", "metrics");
  const failureList = requireArrayField(failures, failuresArtifact, "failures.json", "failures");
  if (metricsArtifact.schemaVersion !== 1) fail(failures, "metrics.json.schemaVersion must be 1");
  if (failuresArtifact.schemaVersion !== 1) fail(failures, "failures.json.schemaVersion must be 1");
  validateMetricsAgainstRegistry(failures, metricList, "metrics.json.metrics");
  if (run.program !== "macos-ux-trace-harness") fail(failures, "run.json.program must be macos-ux-trace-harness");
  if (!schema.allowedRunStatuses.includes(run.status)) fail(failures, `run.json.status ${run.status} is not allowed`);
  validatePrivateBoundary(failures, run.privateBoundary, "run.json");
  validateExitPolicy(failures, run.exitPolicy, run.status, "run.json", schema);
  validateEvidenceSources(failures, run.evidenceSources, "run.json", schema);
  validateTraceIsolation(failures, run.traceIsolation, "run.json", "runDirectoryName", path.basename(runDir), runDir);
  if (run.traceIsolation?.runDirectoryMatchesRunId !== true) fail(failures, "run.json.traceIsolation.runDirectoryMatchesRunId must be true");
  validateOverheadCalibration(failures, run.overheadCalibration, "run.json", schema);
  validateArtifactIndex(failures, run.artifactIndex, "run.json", runDir);
  const runArtifactIndex = Array.isArray(run.artifactIndex) ? run.artifactIndex : [];
  for (const relativePath of requiredFiles) {
    if (!runArtifactIndex.includes(relativePath)) fail(failures, `run.json.artifactIndex is missing ${relativePath}`);
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
  const runStartedEvents = events.filter((event) => event.eventType === "run.started");
  const runCompletedEvents = events.filter((event) => event.eventType === "run.completed");
  if (runStartedEvents.length !== 1) fail(failures, "events.jsonl must include exactly one run.started");
  if (runCompletedEvents.length !== 1) {
    fail(failures, "events.jsonl must include exactly one run.completed");
  } else if (runCompletedEvents[0].status !== run.status) {
    fail(failures, "events.jsonl run.completed status must match run.json.status");
  }
  const scenarioStartedEvents = events.filter((event) => event.eventType === "scenario.started");
  const scenarioCompletedEvents = events.filter((event) => event.eventType === "scenario.completed");
  if (scenarioStartedEvents.length > 0 && scenarioCompletedEvents.length !== 1) {
    fail(failures, "events.jsonl scenario.started requires exactly one scenario.completed");
  }
  const stepFailedEventRows = new Map();
  const stepFailedEvents = new Map();
  for (const event of events.filter((item) => item.eventType === "step.failed")) {
    const key = failureEventKey(event);
    addEventRow(stepFailedEventRows, key, event);
    stepFailedEvents.set(key, event);
  }
  for (const [key, rows] of stepFailedEventRows.entries()) {
    if (rows.length !== 1) fail(failures, `events.jsonl step.failed ${key} must be unique`);
  }
  const stepStartedEvents = new Map();
  const actionDispatchedEvents = new Map();
  const stepCompletedEvents = new Map();
  const terminalStepEvents = new Map();
  for (const event of events) {
    const key = failureEventKey(event);
    if (event.eventType === "step.started") addEventRow(stepStartedEvents, key, event);
    if (event.eventType === "action.dispatched") addEventRow(actionDispatchedEvents, key, event);
    if (event.eventType === "step.completed") {
      addEventRow(stepCompletedEvents, key, event);
      addEventRow(terminalStepEvents, key, event);
    }
    if (event.eventType === "step.failed") addEventRow(terminalStepEvents, key, event);
  }
  for (const [key, startedRows] of stepStartedEvents.entries()) {
    if (startedRows.length !== 1) fail(failures, `events.jsonl step ${key} must have exactly one step.started`);
    const actionRows = actionDispatchedEvents.get(key) || [];
    if (actionRows.length !== 1) fail(failures, `events.jsonl step ${key} must have exactly one action.dispatched`);
    const terminalRows = terminalStepEvents.get(key) || [];
    if (terminalRows.length !== 1) fail(failures, `events.jsonl step ${key} must have exactly one step.completed or step.failed`);
    const started = startedRows[0];
    const action = actionRows[0];
    const terminal = terminalRows[0];
    if (action && Number(action.sequence) <= Number(started.sequence)) {
      fail(failures, `events.jsonl step ${key} action.dispatched must occur after step.started`);
    }
    if (terminal && action && Number(terminal.sequence) <= Number(action.sequence)) {
      fail(failures, `events.jsonl step ${key} terminal event must occur after action.dispatched`);
    }
  }
  for (const [key, completedRows] of stepCompletedEvents.entries()) {
    if (!stepStartedEvents.has(key)) fail(failures, `events.jsonl step.completed ${key} must have a matching step.started`);
    if (completedRows.length !== 1) fail(failures, `events.jsonl step.completed ${key} must be unique`);
  }

  const kpiIds = new Set();
  const metricKeys = new Set();
  const metricRows = new Map();
  for (const [index, metric] of metricList.entries()) {
    const label = `metrics.json.metrics[${index}]`;
    requireFields(failures, metric, label, schema.metricRequiredFields);
    kpiIds.add(metric.kpiId);
    const metricKey = baselineComparisonMetricKey(metric);
    metricKeys.add(metricKey);
    metricRows.set(metricKey, metric);
    if (!Array.isArray(metric.evidenceEventRefs) || metric.evidenceEventRefs.length === 0) {
      fail(failures, `${label}.evidenceEventRefs must include at least one event ref`);
    }
    let hasMatchingKpiEventRef = false;
    for (const ref of metric.evidenceEventRefs || []) {
      if (!eventKeys.has(ref)) {
        fail(failures, `${label}.evidenceEventRefs contains unknown event ref ${ref}`);
        continue;
      }
      const sequence = Number(String(ref).split(":")[0]);
      const event = eventsBySequence.get(sequence);
      if (event?.kpiId === metric.kpiId) hasMatchingKpiEventRef = true;
    }
    if (metric.kpiId !== "none" && !hasMatchingKpiEventRef) {
      fail(failures, `${label}.evidenceEventRefs must include an event for the same KPI`);
    }
  }
  validateBaselineComparison(failures, baselineComparison, "baseline-comparison.json", {
    metricKeys,
    metricRows,
    failureRows: failureList,
    expectedCount: metricList.length,
  });

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

  const failureRowsByEventKey = new Map();
  for (const [index, failure] of failureList.entries()) {
    const label = `failures.json.failures[${index}]`;
    requireFields(failures, failure, label, ["type", "message", "stepId", "actionId", "surfaceId", "controlId", "kpiId"]);
    if (!failureTypes.has(failure.type)) fail(failures, `${label}.type ${failure.type} is not declared`);
    const eventKey = failureEventKey(failure);
    if (failureRowsByEventKey.has(eventKey)) fail(failures, `${label} duplicates failure identity ${eventKey}`);
    failureRowsByEventKey.set(eventKey, failure);
    const stepFailedEvent = stepFailedEvents.get(eventKey);
    if (!stepFailedEvent) {
      fail(failures, `${label} must have a matching step.failed event`);
    } else if (stepFailedEvent.failure?.type && stepFailedEvent.failure.type !== failure.type) {
      fail(failures, `${label}.type must match step.failed failure.type`);
    }
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
  for (const [eventKey, event] of stepFailedEvents.entries()) {
    const label = `events.jsonl:${event.sequence}`;
    if (!event.failure || typeof event.failure !== "object") {
      fail(failures, `${label} step.failed must include a failure object`);
      continue;
    }
    if (!failureRowsByEventKey.has(eventKey)) {
      fail(failures, `${label} step.failed must have a matching failures.json row`);
    } else if (failureRowsByEventKey.get(eventKey).type !== event.failure.type) {
      fail(failures, `${label} failure.type must match failures.json row`);
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

  if (failureStates.length > 0 && !failureList.some((failure) => failure.finalUIStateRef)) {
    fail(failures, "failure UI state sidecar rows require matching failures.json finalUIStateRef");
  }
  if (!options.allowStatusMismatch && failureList.length > 0 && run.status === "PASS") {
    fail(failures, "run.json.status must not be PASS when failures.json has failures");
  }
  if (!options.allowStatusMismatch && failureList.length === 0 && run.status !== "PASS") {
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
    metrics: metricList.length,
    failures: failureList.length,
    failureUIStates: failureStates.length,
    sampleCounts,
    validationFailures: failures,
  };
}

function validateSuite(suiteDir, schema) {
  const failures = [];
  for (const relativePath of ["suite.json", "suite-metrics.json", "suite-failures.json", "suite-baseline-comparison.json"]) {
    requireFile(failures, suiteDir, relativePath);
  }
  if (failures.length) return { ok: false, kind: "suite", path: suiteDir, failures };

  const suite = readJson(path.join(suiteDir, "suite.json"));
  const suiteMetrics = readJson(path.join(suiteDir, "suite-metrics.json"));
  const suiteFailures = readJson(path.join(suiteDir, "suite-failures.json"));
  const suiteBaselineComparison = readJson(path.join(suiteDir, "suite-baseline-comparison.json"));
  const suiteBaselineObject = suiteBaselineComparison && typeof suiteBaselineComparison === "object"
    ? suiteBaselineComparison
    : {};
  requireFields(failures, suite, "suite.json", schema.suiteRequiredFields);
  requireFields(failures, suiteMetrics, "suite-metrics.json", ["schemaVersion", "suiteId", "metrics"]);
  requireFields(failures, suiteFailures, "suite-failures.json", ["schemaVersion", "suiteId", "failures"]);
  const suiteMetricList = requireArrayField(failures, suiteMetrics, "suite-metrics.json", "metrics");
  const suiteFailureList = requireArrayField(failures, suiteFailures, "suite-failures.json", "failures");
  if (suiteMetrics.schemaVersion !== 1) fail(failures, "suite-metrics.json.schemaVersion must be 1");
  if (suiteFailures.schemaVersion !== 1) fail(failures, "suite-failures.json.schemaVersion must be 1");
  validateMetricsAgainstRegistry(failures, suiteMetricList, "suite-metrics.json.metrics");
  if (suite.program !== "macos-ux-trace-harness") fail(failures, "suite.json.program must be macos-ux-trace-harness");
  if (!schema.allowedRunStatuses.includes(suite.status)) fail(failures, `suite.json.status ${suite.status} is not allowed`);
  validatePrivateBoundary(failures, suite.privateBoundary, "suite.json");
  validateExitPolicy(failures, suite.exitPolicy, suite.status, "suite.json", schema);
  validateEvidenceSources(failures, suite.evidenceSources, "suite.json", schema);
  validateTraceIsolation(failures, suite.traceIsolation, "suite.json", "suiteDirectoryName", path.basename(suiteDir), suiteDir);
  if (suite.traceIsolation?.suiteDirectoryMatchesSuiteId !== true) fail(failures, "suite.json.traceIsolation.suiteDirectoryMatchesSuiteId must be true");
  validateOverheadCalibration(failures, suite.overheadCalibration, "suite.json", schema);
  const requiredSuiteFiles = ["suite.json", "suite-metrics.json", "suite-failures.json", "suite-baseline-comparison.json"];
  validateArtifactIndex(failures, suite.artifactIndex, "suite.json", suiteDir);
  const suiteArtifactIndex = Array.isArray(suite.artifactIndex) ? suite.artifactIndex : [];
  for (const relativePath of requiredSuiteFiles) {
    if (!suiteArtifactIndex.includes(relativePath)) fail(failures, `suite.json.artifactIndex is missing ${relativePath}`);
  }
  if (suiteMetrics.suiteId !== suite.suiteId) fail(failures, "suite-metrics.json suiteId must match suite.json");
  if (suiteFailures.suiteId !== suite.suiteId) fail(failures, "suite-failures.json suiteId must match suite.json");
  if (suiteBaselineObject.suiteId !== suite.suiteId) {
    fail(failures, "suite-baseline-comparison.json suiteId must match suite.json");
  }
  const suiteMetricKeys = new Set();
  const suiteMetricRows = new Map();
  for (const metric of suiteMetricList) {
    const metricKey = baselineComparisonMetricKey(metric);
    suiteMetricKeys.add(metricKey);
    suiteMetricRows.set(metricKey, metric);
  }
  validateBaselineComparison(failures, suiteBaselineComparison, "suite-baseline-comparison.json", {
    metricKeys: suiteMetricKeys,
    metricRows: suiteMetricRows,
    failureRows: suiteFailureList,
    expectedCount: suiteMetricList.length,
  });
  if (!Array.isArray(suiteBaselineObject.childRuns)) {
    fail(failures, "suite-baseline-comparison.json.childRuns must be an array");
  } else if (suiteBaselineObject.childRuns.length !== (suite.runs || []).length) {
    fail(failures, "suite-baseline-comparison.json.childRuns must match suite runs");
  }

  const runResults = [];
  const expectedSuiteMetricRows = new Map();
  const expectedSuiteFailureRows = new Map();
  const metricAggregateFields = [
    "runId",
    "scenarioId",
    "fixtureProfile",
    "kpiId",
    "priority",
    "surface",
    "sampleCount",
    "unit",
    "p50",
    "p95",
    "p99",
    "worstSample",
    "budget",
    "baseline",
    "regressionPercent",
    "status",
    "evidenceEventRefs",
  ];
  const failureAggregateFields = ["runId", "scenarioId", "fixtureProfile", "type", "message", "stepId", "actionId", "surfaceId", "controlId", "kpiId", "finalUIStateHash", "finalUIStateRef"];
  for (const [index, row] of (suite.runs || []).entries()) {
    requireFields(failures, row, `suite.json.runs[${index}]`, ["runId", "scenarioId", "fixtureProfile", "status", "runDir"]);
    if (!isRelativeSafe(row.runDir)) fail(failures, `suite.json.runs[${index}].runDir must be relative and safe`);
    if (!suiteArtifactIndex.includes(row.runDir)) fail(failures, `suite.json.artifactIndex is missing child run directory ${row.runDir}`);
    const runDir = path.join(suiteDir, row.runDir);
    const runResult = validateRun(runDir, schema, { allowStatusMismatch: false });
    const childMetrics = readJson(path.join(runDir, "metrics.json"));
    const childFailures = readJson(path.join(runDir, "failures.json"));
    for (const metric of childMetrics.metrics || []) {
      addMultisetRow(expectedSuiteMetricRows, stableAggregateKey(metricAggregateFields, {
        ...metric,
        runId: row.runId,
        scenarioId: row.scenarioId,
        fixtureProfile: row.fixtureProfile,
      }));
    }
    for (const failure of childFailures.failures || []) {
      addMultisetRow(expectedSuiteFailureRows, stableAggregateKey(failureAggregateFields, {
        ...failure,
        runId: row.runId,
        scenarioId: row.scenarioId,
        fixtureProfile: row.fixtureProfile,
      }));
    }
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
  const suiteRunDirs = (suite.runs || []).map((row) => row.runDir);
  const uniqueSuiteRunDirs = new Set(suiteRunDirs);
  if (uniqueSuiteRunDirs.size !== suiteRunDirs.length) fail(failures, "suite.json.runs.runDir values must be unique");
  const traceChildRunDirs = suite.traceIsolation?.childRunDirectories;
  if (!Array.isArray(traceChildRunDirs)) {
    fail(failures, "suite.json.traceIsolation.childRunDirectories must be an array");
  } else {
    for (const childDir of traceChildRunDirs) {
      if (!isRelativeSafe(childDir)) fail(failures, `suite.json.traceIsolation.childRunDirectories contains unsafe path ${childDir}`);
    }
    if (JSON.stringify([...traceChildRunDirs].sort()) !== JSON.stringify([...suiteRunDirs].sort())) {
      fail(failures, "suite.json.traceIsolation.childRunDirectories must match suite run directories");
    }
  }
  for (const [index, row] of (suiteBaselineObject.childRuns || []).entries()) {
    requireFields(failures, row, `suite-baseline-comparison.json.childRuns[${index}]`, ["runId", "scenarioId", "fixtureProfile", "runDir", "baselineComparisonPath"]);
    if (!isRelativeSafe(row.runDir)) fail(failures, `suite-baseline-comparison.json.childRuns[${index}].runDir must be relative and safe`);
    const expectedBaselineComparisonPath = isRelativeSafe(row.runDir)
      ? path.posix.join(row.runDir, "baseline-comparison.json")
      : null;
    if (!isRelativeSafe(row.baselineComparisonPath)) {
      fail(failures, `suite-baseline-comparison.json.childRuns[${index}].baselineComparisonPath must be relative and safe`);
    } else {
      if (expectedBaselineComparisonPath && row.baselineComparisonPath !== expectedBaselineComparisonPath) {
        fail(failures, `suite-baseline-comparison.json.childRuns[${index}].baselineComparisonPath must point to the child run baseline-comparison.json`);
      }
      const baselineComparisonFile = path.join(suiteDir, row.baselineComparisonPath);
      if (!fs.existsSync(baselineComparisonFile)) {
        fail(failures, `suite-baseline-comparison.json.childRuns[${index}].baselineComparisonPath must exist`);
      } else {
        try {
          const childBaselineComparison = readJson(baselineComparisonFile);
          if (childBaselineComparison.runId !== row.runId) {
            fail(failures, `suite-baseline-comparison.json.childRuns[${index}].baselineComparisonPath runId must match child run`);
          }
          if (childBaselineComparison.scenarioId !== row.scenarioId) {
            fail(failures, `suite-baseline-comparison.json.childRuns[${index}].baselineComparisonPath scenarioId must match child run`);
          }
          if (childBaselineComparison.fixtureProfile !== row.fixtureProfile) {
            fail(failures, `suite-baseline-comparison.json.childRuns[${index}].baselineComparisonPath fixtureProfile must match child run`);
          }
        } catch (error) {
          fail(failures, `suite-baseline-comparison.json.childRuns[${index}].baselineComparisonPath must be valid JSON: ${error.message}`);
        }
      }
    }
    const suiteRun = (suite.runs || [])[index];
    if (suiteRun) {
      if (row.runId !== suiteRun.runId) fail(failures, `suite-baseline-comparison.json.childRuns[${index}].runId must match suite run`);
      if (row.scenarioId !== suiteRun.scenarioId) fail(failures, `suite-baseline-comparison.json.childRuns[${index}].scenarioId must match suite run`);
      if (row.fixtureProfile !== suiteRun.fixtureProfile) fail(failures, `suite-baseline-comparison.json.childRuns[${index}].fixtureProfile must match suite run`);
      if (row.runDir !== suiteRun.runDir) fail(failures, `suite-baseline-comparison.json.childRuns[${index}].runDir must match suite run`);
    }
  }
  if (suite.scenarioCount !== (suite.runs || []).length) fail(failures, "suite.json.scenarioCount must match runs.length");
  if (runResults.length === (suite.runs || []).length) {
    const expectedStatus = expectedSuiteStatus(runResults.map((result) => result.status), suite.launchMode);
    if (suite.status !== expectedStatus) fail(failures, `suite.json.status must be ${expectedStatus} for child run statuses`);
  }
  const actualSuiteMetricRows = new Map();
  for (const metric of suiteMetricList) {
    addMultisetRow(actualSuiteMetricRows, stableAggregateKey(metricAggregateFields, metric));
  }
  const actualSuiteFailureRows = new Map();
  for (const failure of suiteFailureList) {
    addMultisetRow(actualSuiteFailureRows, stableAggregateKey(failureAggregateFields, failure));
  }
  compareMultisets(failures, "suite-metrics.json", expectedSuiteMetricRows, actualSuiteMetricRows);
  compareMultisets(failures, "suite-failures.json", expectedSuiteFailureRows, actualSuiteFailureRows);

  return {
    ok: failures.length === 0,
    kind: "suite",
    path: suiteDir,
    suiteId: suite.suiteId,
    status: suite.status,
    runs: runResults.length,
    metrics: suiteMetricList.length,
    failures: suiteFailureList.length,
    validationFailures: failures,
  };
}

function validateBaselineArtifact(file, schema) {
  const failures = [];
  const baseline = readJson(file);
  requireFields(failures, baseline, "baseline", schema.baselineArtifactRequiredFields || [
    "schemaVersion",
    "program",
    "baselineVersion",
    "generatedAt",
    "platform",
    "sourceEvidence",
    "approval",
    "promotionPolicy",
    "evidenceSources",
    "privateBoundary",
    "metrics",
  ]);
  if (baseline.program !== "macos-ux-trace-harness-baseline") {
    fail(failures, "baseline.program must be macos-ux-trace-harness-baseline");
  }
  if (baseline.baselineVersion !== 1) fail(failures, "baseline.baselineVersion must be 1");
  if (baseline.platform !== "macos") fail(failures, "baseline.platform must be macos");
  validatePrivateBoundary(failures, baseline.privateBoundary, "baseline");
  validateEvidenceSources(failures, baseline.evidenceSources, "baseline", schema);
  requireFields(failures, baseline.sourceEvidence, "baseline.sourceEvidence", ["status", "artifactKind"]);
  if (!["run", "suite"].includes(baseline.sourceEvidence?.artifactKind)) {
    fail(failures, "baseline.sourceEvidence.artifactKind must be run or suite");
  } else if (baseline.sourceEvidence.artifactKind === "run") {
    requireFields(failures, baseline.sourceEvidence, "baseline.sourceEvidence", ["runId"]);
    if (typeof baseline.sourceEvidence.runId !== "string" || baseline.sourceEvidence.runId.length === 0) {
      fail(failures, "baseline.sourceEvidence.runId must be a non-empty string for run baselines");
    }
    if (baseline.sourceEvidence.suiteId !== null && baseline.sourceEvidence.suiteId !== undefined) {
      fail(failures, "baseline.sourceEvidence.suiteId must be null for run baselines");
    }
    if (typeof baseline.scenarioId !== "string" || baseline.scenarioId.length === 0) {
      fail(failures, "baseline.scenarioId must be a non-empty string for run baselines");
    }
    if (typeof baseline.fixtureProfile !== "string" || baseline.fixtureProfile.length === 0) {
      fail(failures, "baseline.fixtureProfile must be a non-empty string for run baselines");
    }
    if (baseline.suiteId !== null && baseline.suiteId !== undefined) {
      fail(failures, "baseline.suiteId must be null for run baselines");
    }
  } else if (baseline.sourceEvidence.artifactKind === "suite") {
    requireFields(failures, baseline.sourceEvidence, "baseline.sourceEvidence", ["suiteId"]);
    if (typeof baseline.sourceEvidence.suiteId !== "string" || baseline.sourceEvidence.suiteId.length === 0) {
      fail(failures, "baseline.sourceEvidence.suiteId must be a non-empty string for suite baselines");
    }
    if (baseline.sourceEvidence.runId !== null && baseline.sourceEvidence.runId !== undefined) {
      fail(failures, "baseline.sourceEvidence.runId must be null for suite baselines");
    }
    if (baseline.suiteId !== baseline.sourceEvidence.suiteId) {
      fail(failures, "baseline.suiteId must match baseline.sourceEvidence.suiteId for suite baselines");
    }
    if (typeof baseline.fixtureProfile !== "string" || baseline.fixtureProfile.length === 0) {
      fail(failures, "baseline.fixtureProfile must be a non-empty string for suite baselines");
    }
  }
  requireFields(failures, baseline.approval, "baseline.approval", ["status", "approvedByUserAt", "approvedScope"]);
  if (baseline.approval?.status !== schema.baselineArtifactContract?.defaultApprovalStatus) {
    fail(failures, `baseline.approval.status must be ${schema.baselineArtifactContract?.defaultApprovalStatus}`);
  }
  requireFields(failures, baseline.promotionPolicy, "baseline.promotionPolicy", [
    "lowerPriorityOptimizationMayUpdateP0",
    "requiresApprovedEvidence",
    "privateEvidenceRemainsExternal",
  ]);
  if (baseline.promotionPolicy?.lowerPriorityOptimizationMayUpdateP0 !== false) {
    fail(failures, "baseline.promotionPolicy.lowerPriorityOptimizationMayUpdateP0 must be false");
  }
  if (baseline.promotionPolicy?.requiresApprovedEvidence !== true) {
    fail(failures, "baseline.promotionPolicy.requiresApprovedEvidence must be true");
  }
  if (baseline.promotionPolicy?.privateEvidenceRemainsExternal !== true) {
    fail(failures, "baseline.promotionPolicy.privateEvidenceRemainsExternal must be true");
  }
  if (!Array.isArray(baseline.metrics) || baseline.metrics.length === 0) {
    fail(failures, "baseline.metrics must be a non-empty array");
  }
  for (const [index, metric] of (baseline.metrics || []).entries()) {
    requireFields(failures, metric, `baseline.metrics[${index}]`, ["kpiId", "priority", "surface", "unit", "p95", "sampleCount", "status"]);
    if (typeof metric.kpiId !== "string" || metric.kpiId.length === 0) {
      fail(failures, `baseline.metrics[${index}].kpiId must be a non-empty string`);
    }
  }
  validateMetricsAgainstRegistry(failures, baseline.metrics || [], "baseline.metrics");
  return {
    ok: failures.length === 0,
    kind: "baseline",
    path: file,
    scenarioId: baseline.scenarioId ?? null,
    suiteId: baseline.suiteId ?? null,
    fixtureProfile: baseline.fixtureProfile ?? null,
    metrics: Array.isArray(baseline.metrics) ? baseline.metrics.length : 0,
    approvalStatus: baseline.approval?.status ?? null,
    validationFailures: failures,
  };
}

function validatePath(targetPath) {
  const resolved = path.resolve(targetPath);
  const schema = readJson(schemaPath);
  if (fs.existsSync(resolved) && fs.statSync(resolved).isFile()) return validateBaselineArtifact(resolved, schema);
  if (fs.existsSync(path.join(resolved, "suite.json"))) return validateSuite(resolved, schema);
  if (fs.existsSync(path.join(resolved, "run.json"))) return validateRun(resolved, schema);
  throw new Error(`${resolved} is not a UX trace run, suite, or baseline artifact`);
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
