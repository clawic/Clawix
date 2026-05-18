#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const rawArgs = process.argv.slice(2);
const isSelfTest = process.env.CLAWIX_UI_PRIVATE_CAPTURE_RUNNER_SELF_TEST === "1";
const simulationFlags = [
  "--simulate-missing-runner",
  "--simulate-unsafe-command",
  "--simulate-approval-status",
  "--simulate-missing-baseline-runner",
];
const allowedFlags = new Set(simulationFlags);
const errors = [];

function fail(message) {
  errors.push(message);
}

for (const arg of rawArgs) {
  if (arg.startsWith("--") && !allowedFlags.has(arg)) {
    console.error(`UI private capture runner check received unknown flag ${arg}.`);
    process.exit(1);
  }
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

function requireArray(object, label, field, { nonEmpty = true } = {}) {
  const value = object?.[field];
  if (!Array.isArray(value)) {
    fail(`${label}.${field} must be an array`);
    return [];
  }
  if (nonEmpty && value.length === 0) fail(`${label}.${field} must not be empty`);
  return value;
}

function requireFields(object, label, fields) {
  if (!object) return;
  for (const field of fields) {
    if (object[field] === undefined || object[field] === null || object[field] === "") {
      fail(`${label} is missing ${field}`);
    }
  }
}

function scanPublicSafe(value, label) {
  if (Array.isArray(value)) {
    value.forEach((child, index) => scanPublicSafe(child, `${label}[${index}]`));
    return;
  }
  if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) scanPublicSafe(child, `${label}.${key}`);
    return;
  }
  if (typeof value !== "string") return;
  if (/\/Users\/|~\/|file:\/\/|[A-Z]:\\|CLAWIX_UI_PRIVATE_[A-Z_]+_ROOT/.test(value)) {
    fail(`${label} must not contain local paths or private root env vars`);
  }
}

function runnerForRecord(runners, record) {
  return runners.filter((runner) =>
    new Set(runner.platforms || []).has(record.platform) &&
    new Set(runner.evidenceTypes || []).has(record.type)
  );
}

function runPlan(runnerId) {
  const result = spawnSync(
    process.execPath,
    [path.join(rootDir, "scripts/ui_private_capture_plan.mjs"), "--runner-id", runnerId, "--json"],
    { cwd: rootDir, encoding: "utf8" },
  );
  if (result.status !== 0) {
    fail(`scripts/ui_private_capture_plan.mjs must plan runner ${runnerId}`);
    return null;
  }
  try {
    return JSON.parse(result.stdout);
  } catch (error) {
    fail(`scripts/ui_private_capture_plan.mjs output for ${runnerId} must be valid JSON: ${error.message}`);
    return null;
  }
}

const manifestPath = "docs/ui/private-capture-runners.manifest.json";
const manifest = readJson(manifestPath);
const baselines = readJson("docs/ui/private-baselines.manifest.json");
const visualValidation = readJson("docs/ui/private-visual-validation.manifest.json");
const evidencePlanResult = spawnSync(process.execPath, [path.join(rootDir, "scripts/ui_private_evidence_plan_check.mjs"), "--json"], {
  cwd: rootDir,
  encoding: "utf8",
});
const evidencePlan = evidencePlanResult.status === 0 ? JSON.parse(evidencePlanResult.stdout) : { evidence: [] };

if (rawArgs.includes("--simulate-missing-runner") && Array.isArray(manifest?.runners)) {
  manifest.runners = manifest.runners.filter((runner) => runner.id !== "web-private-visual-baseline");
}
if (rawArgs.includes("--simulate-unsafe-command") && Array.isArray(manifest?.runners) && manifest.runners[0]) {
  manifest.runners[0].planCommand = "CLAWIX_UI_PRIVATE_BASELINE_ROOT=/Users/example/private node scripts/ui_private_capture_plan.mjs";
}
if (rawArgs.includes("--simulate-approval-status")) {
  manifest.candidateEvidenceStatus = "approved";
}
if (rawArgs.includes("--simulate-missing-baseline-runner") && Array.isArray(baselines?.flows) && baselines.flows[0]) {
  baselines.flows[0].runnerId = "missing-private-runner";
}

requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "candidatePlanCommand",
  "candidateEvidenceStatus",
  "approvalRule",
  "publicRepoMustNotStore",
  "runners",
]);
scanPublicSafe(manifest, manifestPath);
if (manifest?.status !== "active") fail(`${manifestPath}.status must be active`);
if (manifest?.candidatePlanCommand !== "node scripts/ui_private_capture_plan.mjs --runner-id <runner-id> --json") {
  fail(`${manifestPath}.candidatePlanCommand must call scripts/ui_private_capture_plan.mjs`);
}
if (manifest?.candidateEvidenceStatus !== "candidate-not-approved") {
  fail(`${manifestPath}.candidateEvidenceStatus must be candidate-not-approved`);
}
if (!String(manifest?.approvalRule || "").includes("--require-approved")) {
  fail(`${manifestPath}.approvalRule must require --require-approved private verifiers`);
}
for (const forbidden of ["raw-screenshot", "raw-geometry-dump", "local-absolute-path", "secret", "approvalHash"]) {
  if (!requireArray(manifest, manifestPath, "publicRepoMustNotStore").includes(forbidden)) {
    fail(`${manifestPath}.publicRepoMustNotStore must include ${forbidden}`);
  }
}

const runners = requireArray(manifest, manifestPath, "runners");
const runnerIds = new Set();
for (const [index, runner] of runners.entries()) {
  const label = `${manifestPath}.runners[${index}]`;
  requireFields(runner, label, ["id", "platforms", "evidenceTypes", "planCommand", "outputAliases", "requiresHumanApproval"]);
  if (runnerIds.has(runner?.id)) fail(`${label}.id duplicates ${runner.id}`);
  runnerIds.add(runner?.id);
  if (runner?.requiresHumanApproval !== true) fail(`${label}.requiresHumanApproval must be true`);
  if (runner?.planCommand !== `node scripts/ui_private_capture_plan.mjs --runner-id ${runner?.id} --json`) {
    fail(`${label}.planCommand must call the capture plan script for ${runner?.id}`);
  }
  const plan = runPlan(runner?.id);
  if (plan && plan.requiresHumanApproval !== true) fail(`${label} capture plan must require human approval`);
}

for (const flow of requireArray(baselines, "docs/ui/private-baselines.manifest.json", "flows")) {
  if (!runnerIds.has(flow?.runnerId)) {
    fail(`docs/ui/private-baselines.manifest.json flow ${flow?.platform}/${flow?.id} references missing runner ${flow?.runnerId}`);
  }
}

for (const record of evidencePlan.evidence || []) {
  const matches = runnerForRecord(runners, record);
  if (matches.length !== 1) {
    fail(`private evidence ${record.type}:${record.platform}/${record.id} must be covered by exactly one capture runner`);
  }
}

if (visualValidation?.candidateCaptureRunnerManifestPath !== manifestPath) {
  fail("docs/ui/private-visual-validation.manifest.json.candidateCaptureRunnerManifestPath must point to private-capture-runners.manifest.json");
}

if (errors.length === 0 && !isSelfTest && rawArgs.length === 0) {
  for (const [flag, expected] of [
    ["--unknown-flag", "received unknown flag --unknown-flag"],
    ["--simulate-missing-runner", "must be covered by exactly one capture runner"],
    ["--simulate-unsafe-command", "must not contain local paths or private root env vars"],
    ["--simulate-approval-status", "candidateEvidenceStatus must be candidate-not-approved"],
    ["--simulate-missing-baseline-runner", "references missing runner missing-private-runner"],
  ]) {
    const result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, flag], {
      cwd: rootDir,
      env: { ...process.env, CLAWIX_UI_PRIVATE_CAPTURE_RUNNER_SELF_TEST: "1" },
      encoding: "utf8",
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status === 0) {
      fail(`self-test ${flag} must fail`);
      continue;
    }
    if (!output.includes(expected)) fail(`self-test ${flag} output must include ${expected}`);
  }
}

if (errors.length > 0) {
  console.error("UI private capture runner check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI private capture runner check passed (${runners.length} runners, ${(evidencePlan.evidence || []).length} evidence records)`);
