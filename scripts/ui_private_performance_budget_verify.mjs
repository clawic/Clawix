#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { privateRootEnvForAlias } from "./ui_private_root_contract.mjs";
import { assertApprovedScopeMetadata, loadApprovedScopeContract } from "./ui_private_approved_scope_contract.mjs";
import { enforcePrivateVerifierArgs } from "./ui_private_verifier_args.mjs";
import { isCriticalMacosFlow, privateSliceOption, sliceLabel } from "./ui_private_slice_scope.mjs";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = process.argv.slice(2);
const isSelfTest = process.env.CLAWIX_UI_PERFORMANCE_BUDGET_VERIFY_SELF_TEST === "1";
const errors = [];

function fail(message) {
  errors.push(message);
}

function readJsonFile(file, label) {
  if (!fs.existsSync(file)) {
    fail(`missing ${label}`);
    return null;
  }
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (error) {
    fail(`${label} is not valid JSON: ${error.message}`);
    return null;
  }
}

function readJson(relativePath) {
  return readJsonFile(path.join(rootDir, relativePath), relativePath);
}

function optionValue(name) {
  const index = args.indexOf(name);
  if (index === -1) return null;
  return args[index + 1] || null;
}

function hasFlag(name) {
  return args.includes(name);
}

enforcePrivateVerifierArgs(args, {
  label: "UI private performance budget verification",
  allowedFlags: ["--require-approved", "--include-pending", "--root", "--slice"],
  optionsWithValues: ["--root", "--slice"],
  testOnlyFlags: ["--include-pending"],
});

function requireField(object, label, field) {
  if (object?.[field] === undefined || object[field] === null || object[field] === "") {
    fail(`${label} is missing ${field}`);
    return false;
  }
  return true;
}

function relativePathFromReference(reference, alias) {
  const prefix = `${alias}:`;
  if (typeof reference !== "string" || !reference.startsWith(prefix)) return null;
  const suffix = reference.slice(prefix.length);
  if (!suffix || suffix.includes("..") || suffix.startsWith("/") || suffix.startsWith("\\") || suffix.startsWith("~/") || /^[A-Z]:\\/.test(suffix)) return null;
  return suffix.split("/").join(path.sep);
}

function assertHash(value, label) {
  if (typeof value !== "string" || !/^[a-f0-9]{64}$/i.test(value)) {
    fail(`${label} must be a 64-character hex hash`);
  }
}

function assertIsoTimestamp(value, label) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}(?:T.+)?$/.test(value) || Number.isNaN(Date.parse(value))) {
    fail(`${label} must be an ISO date or timestamp`);
  }
}

function assertApprovedScope(value, label) {
  assertApprovedScopeMetadata(value, label, approvedScopeContract, fail);
}

function verifyMeasurementSamples(evidence, label, requiredMetrics) {
  if (!Array.isArray(evidence.measurementSamples) || evidence.measurementSamples.length === 0) {
    fail(`${label}.measurementSamples must be a non-empty array`);
    return;
  }
  const seenMetrics = new Set();
  for (const [index, sample] of evidence.measurementSamples.entries()) {
    const sampleLabel = `${label}.measurementSamples[${index}]`;
    if (!sample || typeof sample !== "object" || Array.isArray(sample)) {
      fail(`${sampleLabel} must be an object`);
      continue;
    }
    if (typeof sample.metric !== "string" || !requiredMetrics.includes(sample.metric)) {
      fail(`${sampleLabel}.metric must be one of the required metrics`);
    } else {
      seenMetrics.add(sample.metric);
    }
    if (typeof sample.value !== "number" || !Number.isFinite(sample.value) || sample.value < 0) {
      fail(`${sampleLabel}.value must be a finite non-negative number`);
    }
    assertHash(sample.sampleHash, `${sampleLabel}.sampleHash`);
  }
  for (const metric of requiredMetrics) {
    if (!seenMetrics.has(metric)) fail(`${label}.measurementSamples must include ${metric}`);
  }
}

function runFailureSelfTests() {
  const selfTestEnv = {
    ...process.env,
    CLAWIX_UI_PERFORMANCE_BUDGET_VERIFY_SELF_TEST: "1",
    CLAWIX_UI_ALLOW_PENDING_PRIVATE_EVIDENCE: "",
  };
  const missingRoot = path.join(os.tmpdir(), `clawix-ui-private-performance-missing-${process.pid}`);
  const tests = [
    [[], "requires --require-approved"],
    [["--require-approved", "--unknown-flag"], "received unknown flag --unknown-flag"],
    [["--require-approved", "--include-pending"], "CLAWIX_UI_ALLOW_PENDING_PRIVATE_EVIDENCE"],
    [["--require-approved", "--root", rootDir], "private performance root must be outside the public repository"],
    [["--require-approved", "--root", missingRoot], `private performance root does not exist: ${path.resolve(missingRoot)}`],
  ];

  for (const [testArgs, expectedOutput] of tests) {
    const result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, ...testArgs], {
      cwd: rootDir,
      env: selfTestEnv,
      encoding: "utf8",
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status === 0) {
      fail(`self-test ${testArgs.join(" ") || "<no args>"} must fail for private performance budget verification`);
      continue;
    }
    if (!output.includes(expectedOutput)) {
      fail(`self-test ${testArgs.join(" ") || "<no args>"} output must include ${expectedOutput}`);
    }
  }
}

const requireApproved = hasFlag("--require-approved");
const includePending = hasFlag("--include-pending");
const privateSlice = privateSliceOption(args, fail, "UI private performance budget verification");
const budgets = readJson("docs/ui/performance-budgets.registry.json");
const privateBaselines = readJson("docs/ui/private-baselines.manifest.json");
const approvedScopeContract = loadApprovedScopeContract(rootDir, fail);
const alias = privateBaselines?.privateRootAlias || "private-codex-ui-baselines";
const privateRootEnv = privateRootEnvForAlias(rootDir, alias);

if (!requireApproved) {
  console.error("UI private performance budget verification requires --require-approved.");
  process.exit(1);
}

if (!isSelfTest && !includePending) {
  runFailureSelfTests();
}

const privateRootArg = optionValue("--root");
const privateRootRaw = privateRootArg || process.env[privateRootEnv] || "";
if (!privateRootRaw) {
  console.error(`EXTERNAL PENDING: set ${privateRootEnv} or pass --root to verify private UI performance budgets.`);
  process.exit(2);
}

const privateRoot = path.resolve(privateRootRaw);
const relativeToRepo = path.relative(rootDir, privateRoot);
if (!relativeToRepo.startsWith("..") && !path.isAbsolute(relativeToRepo)) {
  fail("private performance root must be outside the public repository");
}
if (!fs.existsSync(privateRoot) || !fs.statSync(privateRoot).isDirectory()) {
  fail(`private performance root does not exist: ${privateRoot}`);
}

const evidenceFilename = budgets?.evidenceFilename || "performance-evidence.json";
const requiredEvidenceFields = Array.isArray(budgets?.requiredEvidenceFields) ? budgets.requiredEvidenceFields : [];
const requiredMetrics = Array.isArray(budgets?.requiredMetrics) ? budgets.requiredMetrics : [];
let verified = 0;
let pending = 0;

for (const [index, flow] of (budgets?.flows || []).entries()) {
  if (privateSlice && !isCriticalMacosFlow(flow)) continue;
  const label = `${flow.platform || "unknown"}:${flow.id || index}`;
  if (flow.budgetStatus === "pending-approved-measurement" || flow.baselineStatus !== "approved") {
    pending += 1;
    if (!includePending && !privateSlice) {
      if (requireApproved) fail(`${label} is pending approved performance measurement`);
      continue;
    }
  }
  const relativeEvidenceDir = relativePathFromReference(flow.privateBaselineReference, alias);
  if (!relativeEvidenceDir) {
    fail(`${label} has invalid privateBaselineReference`);
    continue;
  }
  const evidencePath = path.join(privateRoot, relativeEvidenceDir, evidenceFilename);
  const evidence = readJsonFile(evidencePath, `${label} ${evidenceFilename}`);
  if (!evidence) continue;
  for (const field of requiredEvidenceFields) requireField(evidence, `${label} evidence`, field);
  assertIsoTimestamp(evidence.measuredAt, `${label}.measuredAt`);
  assertIsoTimestamp(evidence.approvedByUserAt, `${label}.approvedByUserAt`);
  assertApprovedScope(evidence.approvedScope, `${label}.approvedScope`);
  if (evidence.flowId !== flow.id) fail(`${label}.flowId must match the budget registry`);
  if (evidence.platform !== flow.platform) fail(`${label}.platform must match the budget registry`);
  if (evidence.privateBaselineReference !== flow.privateBaselineReference) {
    fail(`${label}.privateBaselineReference must match the budget registry`);
  }
  assertHash(evidence.measurementHash, `${label}.measurementHash`);
  const metrics = evidence.metrics || {};
  for (const metric of requiredMetrics) {
    if (typeof metrics[metric] !== "number" || !Number.isFinite(metrics[metric]) || metrics[metric] < 0) {
      fail(`${label}.metrics.${metric} must be a finite non-negative number`);
    }
  }
  verifyMeasurementSamples(evidence, label, requiredMetrics);
  verified += 1;
}

if (errors.length > 0) {
  console.error("UI private performance budget verification failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI private performance budget verification passed (${verified} verified, ${pending} pending${sliceLabel(privateSlice)})`);
