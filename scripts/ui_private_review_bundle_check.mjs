#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const rawArgs = process.argv.slice(2);
const args = new Set(rawArgs);
const allowedFlags = new Set(["--json"]);
const errors = [];

function fail(message) {
  errors.push(message);
}

for (const arg of rawArgs) {
  if (arg.startsWith("--") && !allowedFlags.has(arg)) {
    console.error(`UI private review bundle check received unknown flag ${arg}.`);
    process.exit(1);
  }
}

function runJson(script, scriptArgs) {
  const result = spawnSync(process.execPath, [path.join(rootDir, script), ...scriptArgs], {
    cwd: rootDir,
    env: process.env,
    encoding: "utf8",
  });
  if (result.status !== 0) {
    fail(`${script} ${scriptArgs.join(" ")} must pass before review bundles can be generated`);
    const output = `${result.stdout || ""}${result.stderr || ""}`.trim();
    if (output) {
      for (const line of output.split("\n").slice(0, 8)) fail(`${script}: ${line}`);
    }
    return null;
  }
  try {
    return JSON.parse(result.stdout);
  } catch (error) {
    fail(`${script} ${scriptArgs.join(" ")} output must be valid JSON: ${error.message}`);
    return null;
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
    fail(`${relativePath} must be valid JSON: ${error.message}`);
    return null;
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

function stateCounts(records) {
  return records.reduce((counts, record) => {
    counts[record.state] = (counts[record.state] || 0) + 1;
    return counts;
  }, {});
}

const packagesReport = runJson("scripts/ui_private_evidence_plan_check.mjs", ["--capture-packages"]);
const decisionsReport = runJson("scripts/ui_private_evidence_plan_check.mjs", ["--capture-decisions"]);
const approvalStatus = runJson("scripts/ui_private_approval_verify.mjs", ["--approval-status"]);
const decisionVerification = readJson("docs/ui/decision-verification.json");

if (packagesReport?.totalRecords !== decisionsReport?.totalRecords) {
  fail("capture package and decision reports must agree on totalRecords");
}

const unresolvedDecisionIds = new Set((decisionVerification?.decisions || [])
  .filter((decision) => decision?.status === "open" || decision?.status === "blocked-external-pending")
  .map((decision) => decision.id));
const recordsByType = new Map((packagesReport?.packages || []).map((pkg) => [pkg.evidenceType, pkg.records || []]));

const bundles = (decisionsReport?.decisions || []).map((decision) => {
  if (!unresolvedDecisionIds.has(decision.decisionId)) {
    fail(`review bundle contains non-unresolved decision ${decision.decisionId}`);
  }
  const records = [];
  for (const pkg of decision.packages || []) {
    const packageRecords = recordsByType.get(pkg.evidenceType) || [];
    for (const record of packageRecords) {
      records.push({
        evidenceType: pkg.evidenceType,
        id: record.id,
        platform: record.platform,
        state: record.state,
        relativeEvidencePath: record.relativeEvidencePath,
        privateReference: record.privateReference,
        requiredFields: record.requiredFields,
        verifierCommands: pkg.verifierCommands || [],
      });
    }
  }
  const counts = stateCounts(records);
  const recordCount = records.length;
  if (recordCount !== decision.recordCount) {
    fail(`review bundle ${decision.decisionId} must include ${decision.recordCount} records, found ${recordCount}`);
  }
  return {
    decisionId: decision.decisionId,
    status: decision.status,
    recordCount,
    placeholders: counts.placeholder || 0,
    missingRoots: counts["missing-root"] || 0,
    missingFiles: counts["missing-file"] || 0,
    invalidJson: counts["invalid-json"] || 0,
    invalidCandidates: counts["invalid-candidate"] || 0,
    candidates: counts.candidate || 0,
    packages: (decision.packages || []).map((pkg) => pkg.evidenceType),
    approvalReadiness: recordCount > 0 && records.every((record) => record.state === "candidate")
      ? "ready-for-human-review-and-approved-verifiers"
      : "capture-required-before-human-review",
    records,
  };
});

for (const decisionId of unresolvedDecisionIds) {
  if (!bundles.some((bundle) => bundle.decisionId === decisionId)) {
    fail(`review bundles must include unresolved decision ${decisionId}`);
  }
}

const report = {
  schemaVersion: 1,
  status: bundles.every((bundle) => bundle.approvalReadiness === "ready-for-human-review-and-approved-verifiers")
    ? "private-review-bundles-ready-for-human-review"
    : "private-review-bundles-capture-required",
  note: "This report is public-safe. It lists aliases, relative evidence paths, states, required fields, and verifier commands, not local private root paths or raw artifacts.",
  totalRecords: decisionsReport?.totalRecords ?? null,
  decisionCount: bundles.length,
  captureTotals: decisionsReport?.totals || null,
  approval: {
    status: approvalStatus?.status || null,
    totalRecords: approvalStatus?.totalRecords ?? null,
    counts: approvalStatus?.counts || null,
  },
  bundles,
};

scanPublicSafe(report, "reviewBundleReport");

if (errors.length > 0) {
  console.error("UI private review bundle check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

if (args.has("--json")) {
  console.log(JSON.stringify(report, null, 2));
} else {
  console.log(`UI private review bundle check passed (${report.decisionCount} decisions, ${report.totalRecords} private evidence records)`);
}
