#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const errors = [];
const args = new Set(process.argv.slice(2));

function fail(message) {
  errors.push(message);
}

function readJson(relativePath) {
  const file = path.join(rootDir, relativePath);
  if (!fs.existsSync(file)) {
    fail(`missing ${relativePath}`);
    return null;
  }
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (error) {
    fail(`${relativePath} is not valid JSON: ${error.message}`);
    return null;
  }
}

function requireFields(object, label, fields) {
  if (!object) return;
  for (const field of fields) {
    if (object[field] === undefined || object[field] === null || object[field] === "") {
      fail(`${label} is missing ${field}`);
    }
  }
}

function requireArray(object, label, field, { nonEmpty = true } = {}) {
  const value = object?.[field];
  if (!Array.isArray(value)) {
    fail(`${label}.${field} must be an array`);
    return [];
  }
  if (nonEmpty && value.length === 0) {
    fail(`${label}.${field} must not be empty`);
  }
  return value;
}

function requireExactStringSet(values, label, expectedValues) {
  const expected = new Set(expectedValues);
  const seen = new Set();
  for (const value of values) {
    if (typeof value !== "string" || value.length === 0) {
      fail(`${label} must only include non-empty strings`);
      continue;
    }
    if (seen.has(value)) fail(`${label} duplicates ${value}`);
    seen.add(value);
    if (!expected.has(value)) fail(`${label} must not include ${value}`);
  }
  for (const value of expected) {
    if (!seen.has(value)) fail(`${label} must include ${value}`);
  }
  if (seen.size !== expected.size) fail(`${label} must exactly match approved values`);
  return seen;
}

function privateReferenceSuffix(reference, expectedAlias, label) {
  if (typeof reference !== "string" || reference.length === 0) {
    fail(`${label} must be a private baseline alias reference`);
    return null;
  }
  const prefix = `${expectedAlias}:`;
  if (!reference.startsWith(prefix)) {
    fail(`${label} must start with ${prefix}`);
    return null;
  }
  const suffix = reference.slice(prefix.length);
  if (
    suffix.length === 0 ||
    suffix.startsWith("/") ||
    suffix.startsWith("~") ||
    suffix.includes("\\") ||
    suffix.split("/").includes("..") ||
    suffix.split("/").includes(".")
  ) {
    fail(`${label} must be a relative private alias suffix`);
    return null;
  }
  return suffix;
}

const requiredPlatforms = ["macos", "ios", "android", "web"];
const requiredFlows = [
  "sidebar-hover-click-expand",
  "chat-scroll",
  "composer-typing",
  "dropdown-open",
  "terminal-sidebar-switch",
  "right-sidebar-browser-use",
];
const requiredMetrics = ["interactionLatencyMs", "p95FrameTimeMs", "hitchCount", "memoryDeltaMb"];
const allowedBaselineStatuses = new Set(["pending-user-approved-baseline", "approved"]);
const allowedBudgetStatuses = new Set(["pending-approved-measurement", "enforced"]);

const budgetsPath = "docs/ui/performance-budgets.registry.json";
const budgets = readJson(budgetsPath);
const decisionVerificationPath = "docs/ui/decision-verification.json";
const decisionVerification = readJson(decisionVerificationPath);
const perfBudgetSourceDecision = (decisionVerification?.decisions || []).find((decision) => decision?.id === "perf_budget_source");
if (budgets && args.has("--simulate-inactive-budget-registry")) {
  budgets.status = "active";
}
requireFields(budgets, budgetsPath, [
  "schemaVersion",
  "status",
  "policy",
  "budgetStyle",
  "requiredMetrics",
  "requiredEvidenceFields",
  "evidenceFilename",
  "verificationCommand",
  "flows",
]);
if (args.has("--simulate-extra-required-flow") && Array.isArray(budgets?.budgetStyle?.requiredFlows)) {
  budgets.budgetStyle.requiredFlows.push("search-open");
}
if (args.has("--simulate-duplicate-required-flow") && Array.isArray(budgets?.budgetStyle?.requiredFlows) && budgets.budgetStyle.requiredFlows[0]) {
  budgets.budgetStyle.requiredFlows.push(budgets.budgetStyle.requiredFlows[0]);
}
if (args.has("--simulate-extra-required-metric") && Array.isArray(budgets?.requiredMetrics)) {
  budgets.requiredMetrics.push("cpuUsagePercent");
}
if (args.has("--simulate-duplicate-required-metric") && Array.isArray(budgets?.requiredMetrics) && budgets.requiredMetrics[0]) {
  budgets.requiredMetrics.push(budgets.requiredMetrics[0]);
}
if (args.has("--simulate-extra-required-evidence-field") && Array.isArray(budgets?.requiredEvidenceFields)) {
  budgets.requiredEvidenceFields.push("localTracePath");
}
if (args.has("--simulate-duplicate-required-evidence-field") && Array.isArray(budgets?.requiredEvidenceFields) && budgets.requiredEvidenceFields[0]) {
  budgets.requiredEvidenceFields.push(budgets.requiredEvidenceFields[0]);
}
if (args.has("--simulate-missing-required-flow") && Array.isArray(budgets?.flows)) {
  budgets.flows = budgets.flows.filter((flow) => !(flow?.platform === "web" && flow?.id === "chat-scroll"));
}
if (args.has("--simulate-missing-required-metric") && Array.isArray(budgets?.flows) && budgets.flows[0]) {
  budgets.flows[0] = {
    ...budgets.flows[0],
    requiredMetrics: budgets.flows[0].requiredMetrics.filter((metric) => metric !== "memoryDeltaMb"),
  };
}
if (args.has("--simulate-flow-extra-required-metric") && Array.isArray(budgets?.flows) && budgets.flows[0]) {
  budgets.flows[0] = {
    ...budgets.flows[0],
    requiredMetrics: [...budgets.flows[0].requiredMetrics, "cpuUsagePercent"],
  };
}
if (args.has("--simulate-flow-duplicate-required-metric") && Array.isArray(budgets?.flows) && budgets.flows[0]) {
  budgets.flows[0] = {
    ...budgets.flows[0],
    requiredMetrics: [...budgets.flows[0].requiredMetrics, budgets.flows[0].requiredMetrics[0]],
  };
}
if (args.has("--simulate-invalid-budget-status") && Array.isArray(budgets?.flows) && budgets.flows[0]) {
  budgets.flows[0] = { ...budgets.flows[0], budgetStatus: "active" };
}
if (args.has("--simulate-enforced-before-approved") && Array.isArray(budgets?.flows) && budgets.flows[0]) {
  budgets.flows[0] = { ...budgets.flows[0], budgetStatus: "enforced" };
}
if (args.has("--simulate-approved-before-private-baseline") && Array.isArray(budgets?.flows) && budgets.flows[0]) {
  budgets.flows[0] = { ...budgets.flows[0], baselineStatus: "approved" };
}
if (args.has("--simulate-perf-decision-missing-budget-registry") && perfBudgetSourceDecision) {
  perfBudgetSourceDecision.publicEvidence = perfBudgetSourceDecision.publicEvidence.filter((evidencePath) => evidencePath !== budgetsPath);
}
if (args.has("--simulate-perf-decision-missing-private-baselines") && perfBudgetSourceDecision) {
  perfBudgetSourceDecision.publicEvidence = perfBudgetSourceDecision.publicEvidence.filter((evidencePath) => evidencePath !== "docs/ui/private-baselines.manifest.json");
}
if (args.has("--simulate-perf-decision-missing-visual-validation") && perfBudgetSourceDecision) {
  perfBudgetSourceDecision.publicEvidence = perfBudgetSourceDecision.publicEvidence.filter((evidencePath) => evidencePath !== "docs/ui/private-visual-validation.manifest.json");
}
if (args.has("--simulate-perf-decision-missing-evidence-plan") && perfBudgetSourceDecision) {
  perfBudgetSourceDecision.publicEvidence = perfBudgetSourceDecision.publicEvidence.filter((evidencePath) => evidencePath !== "scripts/ui_private_evidence_plan_check.mjs");
}
if (args.has("--simulate-perf-decision-missing-evidence-verifier") && perfBudgetSourceDecision) {
  perfBudgetSourceDecision.publicEvidence = perfBudgetSourceDecision.publicEvidence.filter((evidencePath) => evidencePath !== "scripts/ui_private_evidence_verify.mjs");
}
if (args.has("--simulate-perf-decision-missing-visual-verifier") && perfBudgetSourceDecision) {
  perfBudgetSourceDecision.publicEvidence = perfBudgetSourceDecision.publicEvidence.filter((evidencePath) => evidencePath !== "scripts/ui_private_visual_verify.mjs");
}
if (args.has("--simulate-perf-decision-missing-private-verifier") && perfBudgetSourceDecision) {
  perfBudgetSourceDecision.blockingVerifiers = perfBudgetSourceDecision.blockingVerifiers.filter((verifier) => verifier !== "scripts/ui_private_performance_budget_verify.mjs");
}
if (args.has("--simulate-perf-decision-missing-platform-evidence") && perfBudgetSourceDecision) {
  perfBudgetSourceDecision.privateEvidence = perfBudgetSourceDecision.privateEvidence.filter((evidence) => evidence !== "private-codex-ui-baselines:web/*");
}
if (args.has("--simulate-perf-decision-premature-complete") && perfBudgetSourceDecision) {
  perfBudgetSourceDecision.status = "verified-complete";
  perfBudgetSourceDecision.remaining = [];
}
if (budgets?.evidenceFilename !== "performance-evidence.json") {
  fail(`${budgetsPath}.evidenceFilename must be performance-evidence.json`);
}
if (!["pending-approved-baseline-capture", "approved-baseline-enforced"].includes(budgets?.status)) {
  fail(`${budgetsPath}.status must be pending-approved-baseline-capture or approved-baseline-enforced`);
}
if (!String(budgets?.verificationCommand || "").includes("scripts/ui_private_performance_budget_verify.mjs --require-approved")) {
  fail(`${budgetsPath}.verificationCommand must run scripts/ui_private_performance_budget_verify.mjs --require-approved`);
}
const budgetStyle = budgets?.budgetStyle || {};
requireFields(budgetStyle, `${budgetsPath}.budgetStyle`, [
  "unit",
  "platformScope",
  "requiredFlows",
  "measurementSource",
  "approvalRequiredBeforeEnforcement",
]);
if (budgetStyle.unit !== "critical-flow") fail(`${budgetsPath}.budgetStyle.unit must be critical-flow`);
if (budgetStyle.platformScope !== "per-governed-platform") {
  fail(`${budgetsPath}.budgetStyle.platformScope must be per-governed-platform`);
}
if (budgetStyle.measurementSource !== "private-baseline") {
  fail(`${budgetsPath}.budgetStyle.measurementSource must be private-baseline`);
}
if (budgetStyle.approvalRequiredBeforeEnforcement !== true) {
  fail(`${budgetsPath}.budgetStyle.approvalRequiredBeforeEnforcement must be true`);
}
requireExactStringSet(
  requireArray(budgetStyle, `${budgetsPath}.budgetStyle`, "requiredFlows"),
  `${budgetsPath}.budgetStyle.requiredFlows`,
  requiredFlows,
);
requireExactStringSet(
  requireArray(budgets, budgetsPath, "requiredMetrics"),
  `${budgetsPath}.requiredMetrics`,
  requiredMetrics,
);
const requiredEvidenceFields = [
  "flowId",
  "platform",
  "privateBaselineReference",
  "metrics",
  "measurementSamples",
  "measurementHash",
  "measuredAt",
  "approvedByUserAt",
  "approvedScope",
];
requireExactStringSet(
  requireArray(budgets, budgetsPath, "requiredEvidenceFields"),
  `${budgetsPath}.requiredEvidenceFields`,
  requiredEvidenceFields,
);

const privateBaselinesPath = "docs/ui/private-baselines.manifest.json";
const privateBaselines = readJson(privateBaselinesPath);
if (privateBaselines?.privateRootAlias !== "private-codex-ui-baselines") {
  fail(`${privateBaselinesPath}.privateRootAlias must be private-codex-ui-baselines`);
}
if (args.has("--simulate-missing-private-baseline") && Array.isArray(privateBaselines?.flows)) {
  privateBaselines.flows = privateBaselines.flows.filter((flow) => !(flow?.platform === "web" && flow?.id === "chat-scroll"));
}
if (args.has("--simulate-duplicate-private-baseline") && Array.isArray(privateBaselines?.flows) && privateBaselines.flows[0]) {
  privateBaselines.flows.push({ ...privateBaselines.flows[0] });
}
if (args.has("--simulate-wrong-private-reference")) {
  const flow = budgets?.flows?.[0];
  const baseline = privateBaselines?.flows?.find((candidate) => (
    candidate.platform === flow?.platform && candidate.id === flow?.id
  ));
  if (flow && baseline) {
    const wrongReference = `${privateBaselines.privateRootAlias}:${flow.platform}/wrong-flow`;
    flow.privateBaselineReference = wrongReference;
    baseline.privateBaselineReference = wrongReference;
  }
}
const baselineByFlow = new Map();
for (const [index, flow] of requireArray(privateBaselines, privateBaselinesPath, "flows").entries()) {
  const key = `${flow.platform}:${flow.id}`;
  if (baselineByFlow.has(key)) fail(`${privateBaselinesPath}.flows[${index}] duplicates ${key}`);
  baselineByFlow.set(key, flow);
}

const seen = new Set();
for (const [index, flow] of requireArray(budgets, budgetsPath, "flows").entries()) {
  const label = `${budgetsPath}.flows[${index}]`;
  requireFields(flow, label, [
    "id",
    "platform",
    "baselineStatus",
    "measurementSource",
    "privateBaselineReference",
    "requiredMetrics",
    "budgetStatus",
  ]);
  const key = `${flow.platform}:${flow.id}`;
  if (seen.has(key)) fail(`${label} duplicates ${key}`);
  seen.add(key);
  if (!requiredPlatforms.includes(flow.platform)) fail(`${label}.platform is not governed`);
  if (!requiredFlows.includes(flow.id)) fail(`${label}.id is not a required critical flow`);
  if (!allowedBaselineStatuses.has(flow.baselineStatus)) fail(`${label}.baselineStatus is invalid`);
  if (!allowedBudgetStatuses.has(flow.budgetStatus)) fail(`${label}.budgetStatus is invalid`);
  if (flow.measurementSource !== "private-baseline") fail(`${label}.measurementSource must be private-baseline`);
  const expectedSuffix = `${flow.platform}/${flow.id}`;
  const actualSuffix = privateReferenceSuffix(
    flow.privateBaselineReference,
    privateBaselines?.privateRootAlias,
    `${label}.privateBaselineReference`,
  );
  if (actualSuffix && actualSuffix !== expectedSuffix) {
    fail(`${label}.privateBaselineReference must resolve to ${expectedSuffix}`);
  }
  requireExactStringSet(requireArray(flow, label, "requiredMetrics"), `${label}.requiredMetrics`, requiredMetrics);
  const baseline = baselineByFlow.get(key);
  if (!baseline) {
    fail(`${label} must have matching ${privateBaselinesPath}.flows entry`);
    continue;
  }
  if (baseline.privateBaselineReference !== flow.privateBaselineReference) {
    fail(`${label}.privateBaselineReference must match ${privateBaselinesPath}`);
  }
  if (flow.baselineStatus === "approved" && baseline.baselineStatus !== "approved") {
    fail(`${label}.baselineStatus cannot be approved before private baseline is approved`);
  }
  if (flow.budgetStatus === "enforced" && flow.baselineStatus !== "approved") {
    fail(`${label}.budgetStatus cannot be enforced before baselineStatus is approved`);
  }
}

for (const platform of requiredPlatforms) {
  for (const flow of requiredFlows) {
    if (!seen.has(`${platform}:${flow}`)) fail(`${budgetsPath}.flows must include ${platform}:${flow}`);
  }
}

if (!perfBudgetSourceDecision) {
  fail(`${decisionVerificationPath}.decisions must include perf_budget_source`);
} else {
  const publicEvidence = new Set(Array.isArray(perfBudgetSourceDecision.publicEvidence) ? perfBudgetSourceDecision.publicEvidence : []);
  for (const evidencePath of [
    budgetsPath,
    privateBaselinesPath,
    "docs/ui/private-visual-validation.manifest.json",
    "scripts/ui_performance_budget_check.mjs",
    "scripts/ui_private_evidence_plan_check.mjs",
    "scripts/ui_private_evidence_verify.mjs",
    "scripts/ui_private_performance_budget_verify.mjs",
    "scripts/ui_private_visual_verify.mjs",
  ]) {
    if (!publicEvidence.has(evidencePath)) {
      fail(`${decisionVerificationPath}.decisions.perf_budget_source.publicEvidence must include ${evidencePath}`);
    }
  }
  const privateEvidence = new Set(Array.isArray(perfBudgetSourceDecision.privateEvidence) ? perfBudgetSourceDecision.privateEvidence : []);
  const privateAlias = privateBaselines?.privateRootAlias || "private-codex-ui-baselines";
  for (const platform of requiredPlatforms) {
    const evidencePath = `${privateAlias}:${platform}/*`;
    if (!privateEvidence.has(evidencePath)) {
      fail(`${decisionVerificationPath}.decisions.perf_budget_source.privateEvidence must include ${evidencePath}`);
    }
  }
  const blockingVerifiers = new Set(Array.isArray(perfBudgetSourceDecision.blockingVerifiers) ? perfBudgetSourceDecision.blockingVerifiers : []);
  for (const verifier of [
    "scripts/ui_private_performance_budget_verify.mjs",
    "scripts/ui_private_evidence_verify.mjs",
    "scripts/ui_private_visual_verify.mjs",
  ]) {
    if (!blockingVerifiers.has(verifier)) {
      fail(`${decisionVerificationPath}.decisions.perf_budget_source.blockingVerifiers must include ${verifier}`);
    }
  }
  if (budgets?.status !== "approved-baseline-enforced" && perfBudgetSourceDecision.status !== "open") {
    fail(`${decisionVerificationPath}.decisions.perf_budget_source.status must remain open until private performance baselines are approved`);
  }
  if (budgets?.status !== "approved-baseline-enforced" && (!Array.isArray(perfBudgetSourceDecision.remaining) || perfBudgetSourceDecision.remaining.length === 0)) {
    fail(`${decisionVerificationPath}.decisions.perf_budget_source.remaining must describe pending approved performance baselines`);
  }
}

if (errors.length > 0) {
  console.error("UI performance budget check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI performance budget check passed (${seen.size} flow budgets)`);
