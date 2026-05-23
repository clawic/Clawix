#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const rawArgs = process.argv.slice(2);
const args = new Set(rawArgs);
const today = new Date().toISOString().slice(0, 10);
const isSelfTest = process.env.CLAWIX_UI_RENDERED_DRIFT_SELF_TEST === "1";
const simulationFlags = [
  "--simulate-verifier-mismatch",
  "--simulate-inactive-rendered-drift",
  "--simulate-extra-drift-category",
  "--simulate-duplicate-drift-category",
  "--simulate-missing-drift-category",
  "--simulate-extra-report-status",
  "--simulate-duplicate-report-status",
  "--simulate-extra-blocking-report-status",
  "--simulate-duplicate-blocking-report-status",
  "--simulate-extra-approval-required-status",
  "--simulate-duplicate-approval-required-status",
  "--simulate-extra-required-report-field",
  "--simulate-duplicate-required-report-field",
  "--simulate-extra-required-evidence-field",
  "--simulate-duplicate-required-evidence-field",
  "--simulate-extra-approved-drift-evidence-field",
  "--simulate-duplicate-approved-drift-evidence-field",
  "--simulate-missing-failure-output-requirement",
  "--simulate-extra-failure-output-requirement",
  "--simulate-duplicate-failure-output-requirement",
  "--simulate-duplicate-report",
  "--simulate-missing-coverage-report",
  "--simulate-unsafe-private-reference",
  "--simulate-mismatched-private-reference",
  "--simulate-expired-review",
  "--simulate-invalid-report-status",
  "--simulate-active-manifest-with-blocking-report",
  "--simulate-pending-manifest-with-all-nonblocking",
  "--simulate-report-extra-drift-category",
  "--simulate-report-duplicate-drift-category",
  "--simulate-enforcement-missing-rendered-drift",
  "--simulate-enforcement-missing-private-drift-verifier",
  "--simulate-enforcement-missing-private-drift-evidence",
  "--simulate-enforcement-premature-complete",
  "--simulate-active-drift-stale-decision",
];
const allowedFlags = new Set(simulationFlags);
const errors = [];

function fail(message) {
  errors.push(message);
}

for (const arg of rawArgs) {
  if (arg.startsWith("--") && !allowedFlags.has(arg)) {
    console.error(`UI rendered drift check received unknown flag ${arg}.`);
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
  if (nonEmpty && value.length === 0) fail(`${label}.${field} must not be empty`);
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

function requireAlias(value, alias, label) {
  if (typeof value !== "string" || !value.startsWith(`${alias}:`)) {
    fail(`${label} must use ${alias}:`);
    return null;
  }
  const suffix = value.slice(alias.length + 1);
  if (!suffix || suffix.startsWith("/") || suffix.startsWith("\\") || suffix.startsWith("~/") || suffix.includes("..") || /^[A-Z]:\\/.test(suffix)) {
    fail(`${label} must use a safe relative external reference`);
    return null;
  }
  if (value.includes("/Users/") || value.startsWith("~/") || value.startsWith("file://") || /^[A-Z]:\\/.test(value)) {
    fail(`${label} must not contain a local path`);
    return null;
  }
  return suffix;
}

const manifestPath = "docs/ui/rendered-drift.manifest.json";
const manifest = readJson(manifestPath);
const decisionVerificationPath = "docs/ui/decision-verification.json";
const decisionVerification = readJson(decisionVerificationPath);
const enforcementModeDecision = (decisionVerification?.decisions || []).find((decision) => decision?.id === "enforcement_mode");
const aggregateVisualManifestPath = "docs/ui/private-visual-validation.manifest.json";
const aggregateVisualManifest = readJson(aggregateVisualManifestPath);
if (manifest) {
  if (args.has("--simulate-verifier-mismatch")) {
    manifest.verificationCommand = "node scripts/ui_private_drift_verify.mjs --require-approved";
  }
  if (args.has("--simulate-inactive-rendered-drift")) {
    manifest.status = "captured";
  }
  if (args.has("--simulate-extra-drift-category") && Array.isArray(manifest.driftCategories)) {
    manifest.driftCategories.push("visual-copy");
  }
  if (args.has("--simulate-duplicate-drift-category") && Array.isArray(manifest.driftCategories) && manifest.driftCategories[0]) {
    manifest.driftCategories.push(manifest.driftCategories[0]);
  }
  if (args.has("--simulate-missing-drift-category") && Array.isArray(manifest.driftCategories)) {
    manifest.driftCategories = manifest.driftCategories.filter((category) => category !== "copy");
  }
  if (args.has("--simulate-extra-report-status") && Array.isArray(manifest.reportStatuses)) {
    manifest.reportStatuses.push("ignored-drift");
  }
  if (args.has("--simulate-duplicate-report-status") && Array.isArray(manifest.reportStatuses) && manifest.reportStatuses[0]) {
    manifest.reportStatuses.push(manifest.reportStatuses[0]);
  }
  if (args.has("--simulate-extra-blocking-report-status") && Array.isArray(manifest.blockingReportStatuses)) {
    manifest.blockingReportStatuses.push("approved-drift");
  }
  if (args.has("--simulate-duplicate-blocking-report-status") && Array.isArray(manifest.blockingReportStatuses) && manifest.blockingReportStatuses[0]) {
    manifest.blockingReportStatuses.push(manifest.blockingReportStatuses[0]);
  }
  if (args.has("--simulate-extra-approval-required-status") && Array.isArray(manifest.approvalRequiredStatuses)) {
    manifest.approvalRequiredStatuses.push("no-drift");
  }
  if (args.has("--simulate-duplicate-approval-required-status") && Array.isArray(manifest.approvalRequiredStatuses) && manifest.approvalRequiredStatuses[0]) {
    manifest.approvalRequiredStatuses.push(manifest.approvalRequiredStatuses[0]);
  }
  if (args.has("--simulate-extra-required-report-field") && Array.isArray(manifest.requiredReportFields)) {
    manifest.requiredReportFields.push("localReportPath");
  }
  if (args.has("--simulate-duplicate-required-report-field") && Array.isArray(manifest.requiredReportFields) && manifest.requiredReportFields[0]) {
    manifest.requiredReportFields.push(manifest.requiredReportFields[0]);
  }
  if (args.has("--simulate-extra-required-evidence-field") && Array.isArray(manifest.requiredEvidenceFields)) {
    manifest.requiredEvidenceFields.push("localTracePath");
  }
  if (args.has("--simulate-duplicate-required-evidence-field") && Array.isArray(manifest.requiredEvidenceFields) && manifest.requiredEvidenceFields[0]) {
    manifest.requiredEvidenceFields.push(manifest.requiredEvidenceFields[0]);
  }
  if (args.has("--simulate-extra-approved-drift-evidence-field") && Array.isArray(manifest.approvedDriftEvidenceFields)) {
    manifest.approvedDriftEvidenceFields.push("approvalScreenshotPath");
  }
  if (args.has("--simulate-duplicate-approved-drift-evidence-field") && Array.isArray(manifest.approvedDriftEvidenceFields) && manifest.approvedDriftEvidenceFields[0]) {
    manifest.approvedDriftEvidenceFields.push(manifest.approvedDriftEvidenceFields[0]);
  }
  if (args.has("--simulate-missing-failure-output-requirement") && Array.isArray(manifest.failureOutputRequirements)) {
    manifest.failureOutputRequirements = manifest.failureOutputRequirements.filter((field) => field !== "required permission");
  }
  if (args.has("--simulate-extra-failure-output-requirement") && Array.isArray(manifest.failureOutputRequirements)) {
    manifest.failureOutputRequirements.push("local path");
  }
  if (args.has("--simulate-duplicate-failure-output-requirement") && Array.isArray(manifest.failureOutputRequirements) && manifest.failureOutputRequirements[0]) {
    manifest.failureOutputRequirements.push(manifest.failureOutputRequirements[0]);
  }
  if (args.has("--simulate-duplicate-report") && Array.isArray(manifest.reports) && manifest.reports[0]) {
    manifest.reports.push({ ...manifest.reports[0] });
  }
  if (args.has("--simulate-missing-coverage-report") && Array.isArray(manifest.reports)) {
    manifest.reports = manifest.reports.slice(0, -1);
  }
  if (args.has("--simulate-unsafe-private-reference") && Array.isArray(manifest.reports) && manifest.reports[0]) {
    manifest.reports[0].privateDriftReportReference = `${manifest.privateDriftAlias}:../drift`;
  }
  if (args.has("--simulate-mismatched-private-reference") && Array.isArray(manifest.reports) && manifest.reports[0]) {
    manifest.reports[0].privateDriftReportReference = `${manifest.privateDriftAlias}:surfaces/${manifest.reports[0].platform}/wrong-surface`;
  }
  if (args.has("--simulate-expired-review") && Array.isArray(manifest.reports) && manifest.reports[0]) {
    manifest.reports[0].reviewAfter = "2026-01-01";
  }
  if (args.has("--simulate-invalid-report-status") && Array.isArray(manifest.reports) && manifest.reports[0]) {
    manifest.reports[0].status = "ignored-drift";
  }
  if (args.has("--simulate-active-manifest-with-blocking-report")) {
    manifest.status = "active";
  }
  if (args.has("--simulate-pending-manifest-with-all-nonblocking") && Array.isArray(manifest.reports)) {
    manifest.status = "pending-private-capture";
    manifest.reports = manifest.reports.map((report) => ({
      ...report,
      status: "no-drift",
    }));
  }
  if (args.has("--simulate-report-extra-drift-category") && Array.isArray(manifest.reports) && manifest.reports[0]) {
    manifest.reports[0].driftCategories.push("visual-copy");
  }
  if (args.has("--simulate-report-duplicate-drift-category") && Array.isArray(manifest.reports) && manifest.reports[0]) {
    manifest.reports[0].driftCategories.push(manifest.reports[0].driftCategories[0]);
  }
  if (args.has("--simulate-enforcement-missing-rendered-drift") && enforcementModeDecision) {
    enforcementModeDecision.publicEvidence = enforcementModeDecision.publicEvidence.filter((evidencePath) => evidencePath !== manifestPath);
  }
  if (args.has("--simulate-enforcement-missing-private-drift-verifier") && enforcementModeDecision) {
    enforcementModeDecision.blockingVerifiers = enforcementModeDecision.blockingVerifiers.filter((verifier) => verifier !== "scripts/ui_private_drift_verify.mjs");
  }
  if (args.has("--simulate-enforcement-missing-private-drift-evidence") && enforcementModeDecision) {
    enforcementModeDecision.externalEvidence = [];
  }
  if (args.has("--simulate-enforcement-premature-complete") && enforcementModeDecision) {
    enforcementModeDecision.status = "verified-complete";
    enforcementModeDecision.remaining = [];
  }
  if (args.has("--simulate-active-drift-stale-decision") && manifest && Array.isArray(manifest.reports) && enforcementModeDecision) {
    manifest.status = "active";
    manifest.reports = manifest.reports.map((report) => ({
      ...report,
      status: "no-drift",
    }));
    enforcementModeDecision.status = "open";
    enforcementModeDecision.remaining = ["Simulated stale decision after private rendered drift evidence."];
  }
}
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "surfaceBaselineCoveragePath",
  "privateDriftAlias",
  "verificationCommand",
  "driftCategories",
  "reportStatuses",
  "blockingReportStatuses",
  "approvalRequiredStatuses",
  "requiredReportFields",
  "requiredEvidenceFields",
  "approvedDriftEvidenceFields",
  "failureOutputRequirements",
  "evidenceFilename",
  "reports",
]);
if (manifest?.status !== "pending-private-capture" && manifest?.status !== "active") {
  fail(`${manifestPath}.status must be pending-private-capture or active`);
}
if (!String(manifest?.verificationCommand || "").includes("scripts/ui_private_visual_verify.mjs")) {
  fail(`${manifestPath}.verificationCommand must run scripts/ui_private_visual_verify.mjs`);
}
if (!String(manifest?.verificationCommand || "").includes("--require-approved")) {
  fail(`${manifestPath}.verificationCommand must require approved private drift evidence`);
}
if (manifest?.verificationCommand !== aggregateVisualManifest?.verificationCommand) {
  fail(`${manifestPath}.verificationCommand must match ${aggregateVisualManifestPath}.verificationCommand`);
}

const expectedCategories = ["geometry", "screenshot", "copy", "performance", "state"];
requireExactStringSet(requireArray(manifest, manifestPath, "driftCategories"), `${manifestPath}.driftCategories`, expectedCategories);
const statuses = requireExactStringSet(
  requireArray(manifest, manifestPath, "reportStatuses"),
  `${manifestPath}.reportStatuses`,
  ["pending-private-evidence", "no-drift", "drift-detected", "approved-drift"],
);
requireExactStringSet(
  requireArray(manifest, manifestPath, "blockingReportStatuses"),
  `${manifestPath}.blockingReportStatuses`,
  ["pending-private-evidence", "drift-detected"],
);
requireExactStringSet(
  requireArray(manifest, manifestPath, "approvalRequiredStatuses"),
  `${manifestPath}.approvalRequiredStatuses`,
  ["approved-drift"],
);
const requiredReportFieldValues = ["coverageId", "platform", "privateDriftReportReference", "driftCategories", "status", "reviewAfter"];
requireExactStringSet(
  requireArray(manifest, manifestPath, "requiredReportFields"),
  `${manifestPath}.requiredReportFields`,
  requiredReportFieldValues,
);
requireExactStringSet(
  requireArray(manifest, manifestPath, "requiredEvidenceFields"),
  `${manifestPath}.requiredEvidenceFields`,
  ["coverageId", "platform", "privateDriftReportReference", "driftCategories", "driftResults", "status", "reportHash", "producedAt"],
);
requireExactStringSet(
  requireArray(manifest, manifestPath, "approvedDriftEvidenceFields"),
  `${manifestPath}.approvedDriftEvidenceFields`,
  ["approvedByUserAt", "approvedScope"],
);
requireExactStringSet(
  requireArray(manifest, manifestPath, "failureOutputRequirements"),
  `${manifestPath}.failureOutputRequirements`,
  ["route", "reason", "required permission", "proposal route", "privateDriftReportReference"],
);
if (manifest?.evidenceFilename !== "drift-report.json") fail(`${manifestPath}.evidenceFilename must be drift-report.json`);

const coveragePath = manifest?.surfaceBaselineCoveragePath || "docs/ui/surface-baseline-coverage.manifest.json";
const coverage = readJson(coveragePath);
const coverageById = new Map();
for (const [index, entry] of requireArray(coverage, coveragePath, "coverage").entries()) {
  if (coverageById.has(entry.coverageId)) fail(`${coveragePath}.coverage[${index}].coverageId duplicates ${entry.coverageId}`);
  coverageById.set(entry.coverageId, entry);
}

const seen = new Set();
let blockingReportCount = 0;
const blockingReportStatuses = new Set(Array.isArray(manifest?.blockingReportStatuses) ? manifest.blockingReportStatuses : []);
for (const [index, report] of requireArray(manifest, manifestPath, "reports").entries()) {
  const label = `${manifestPath}.reports[${index}]`;
  requireFields(report, label, requiredReportFieldValues);
  if (seen.has(report.coverageId)) fail(`${label}.coverageId duplicates ${report.coverageId}`);
  seen.add(report.coverageId);
  const coverageEntry = coverageById.get(report.coverageId);
  if (!coverageEntry) {
    fail(`${label}.coverageId is not listed in ${coveragePath}`);
    continue;
  }
  if (report.platform !== coverageEntry.platform) fail(`${label}.platform must match ${coveragePath}`);
  const driftReferenceSuffix = requireAlias(report.privateDriftReportReference, manifest.privateDriftAlias, `${label}.privateDriftReportReference`);
  const expectedDriftReference = `surfaces/${report.platform}/${report.coverageId}`;
  if (driftReferenceSuffix && driftReferenceSuffix !== expectedDriftReference) {
    fail(`${label}.privateDriftReportReference must target ${expectedDriftReference}`);
  }
  if (!statuses.has(report.status)) fail(`${label}.status is not allowed`);
  if (blockingReportStatuses.has(report.status)) blockingReportCount += 1;
  if (report.reviewAfter < today) fail(`${label}.reviewAfter expired on ${report.reviewAfter}`);
  requireExactStringSet(requireArray(report, label, "driftCategories"), `${label}.driftCategories`, expectedCategories);
}

if (manifest?.status === "active" && blockingReportCount > 0) {
  fail(`${manifestPath}.status cannot be active while ${blockingReportCount} drift reports are blocking`);
}
if (manifest?.status === "pending-private-capture" && seen.size > 0 && blockingReportCount === 0) {
  fail(`${manifestPath}.status must be active when no drift reports are blocking`);
}

for (const coverageId of coverageById.keys()) {
  if (!seen.has(coverageId)) fail(`${manifestPath}.reports must include ${coverageId}`);
}

if (!enforcementModeDecision) {
  fail(`${decisionVerificationPath}.decisions must include enforcement_mode`);
} else {
  const publicEvidence = new Set(Array.isArray(enforcementModeDecision.publicEvidence) ? enforcementModeDecision.publicEvidence : []);
  for (const evidencePath of [
    "scripts/ui_governance_guard.mjs",
    "scripts/ui_geometry_contract_check.mjs",
    "scripts/ui_rendered_drift_check.mjs",
    "scripts/ui_private_drift_verify.mjs",
    manifestPath,
    "scripts/test.sh",
  ]) {
    if (!publicEvidence.has(evidencePath)) {
      fail(`${decisionVerificationPath}.decisions.enforcement_mode.publicEvidence must include ${evidencePath}`);
    }
  }
  const externalEvidence = new Set(Array.isArray(enforcementModeDecision.externalEvidence) ? enforcementModeDecision.externalEvidence : []);
  if (!externalEvidence.has(`${manifest?.privateDriftAlias}:surfaces/*`)) {
    fail(`${decisionVerificationPath}.decisions.enforcement_mode.externalEvidence must include ${manifest?.privateDriftAlias}:surfaces/*`);
  }
  const blockingVerifiers = new Set(Array.isArray(enforcementModeDecision.blockingVerifiers) ? enforcementModeDecision.blockingVerifiers : []);
  for (const verifier of [
    "scripts/ui_private_drift_verify.mjs",
    "scripts/ui_private_visual_verify.mjs",
  ]) {
    if (!blockingVerifiers.has(verifier)) {
      fail(`${decisionVerificationPath}.decisions.enforcement_mode.blockingVerifiers must include ${verifier}`);
    }
  }
  if (manifest?.status !== "active" && !["open", "blocked-external-pending"].includes(enforcementModeDecision.status)) {
    fail(`${decisionVerificationPath}.decisions.enforcement_mode.status must remain open or blocked-external-pending until private rendered drift evidence is captured`);
  }
  if (manifest?.status !== "active" && (!Array.isArray(enforcementModeDecision.remaining) || enforcementModeDecision.remaining.length === 0)) {
    fail(`${decisionVerificationPath}.decisions.enforcement_mode.remaining must describe pending rendered drift evidence`);
  }
  if (manifest?.status === "active" && enforcementModeDecision.status !== "verified-complete") {
    fail(`${decisionVerificationPath}.decisions.enforcement_mode.status must be verified-complete after private rendered drift evidence is captured`);
  }
  if (manifest?.status === "active" && Array.isArray(enforcementModeDecision.remaining) && enforcementModeDecision.remaining.length > 0) {
    fail(`${decisionVerificationPath}.decisions.enforcement_mode.remaining must be empty after private rendered drift evidence is captured`);
  }
}

if (errors.length > 0) {
  console.error("UI rendered drift check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

if (!isSelfTest && rawArgs.length === 0) {
  const selfTests = [
    ["--unknown-flag", "received unknown flag --unknown-flag"],
    ["--simulate-verifier-mismatch", "verificationCommand must run scripts/ui_private_visual_verify.mjs"],
    ["--simulate-missing-drift-category", "driftCategories must include copy"],
    ["--simulate-missing-failure-output-requirement", "failureOutputRequirements must include required permission"],
    ["--simulate-missing-coverage-report", "reports must include web-screens"],
    ["--simulate-unsafe-private-reference", "privateDriftReportReference must use a safe relative external reference"],
    ["--simulate-mismatched-private-reference", "privateDriftReportReference must target surfaces/"],
    ["--simulate-active-manifest-with-blocking-report", "status cannot be active while"],
    ["--simulate-enforcement-missing-private-drift-verifier", "blockingVerifiers must include scripts/ui_private_drift_verify.mjs"],
    ["--simulate-enforcement-premature-complete", "status must remain open or blocked-external-pending until private rendered drift evidence is captured"],
  ];
  const scriptPath = path.relative(rootDir, new URL(import.meta.url).pathname);
  for (const [flag, expectedOutput] of selfTests) {
    const result = spawnSync(process.execPath, [scriptPath, flag], {
      cwd: rootDir,
      encoding: "utf8",
      env: { ...process.env, CLAWIX_UI_RENDERED_DRIFT_SELF_TEST: "1" },
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status === 0 || !output.includes(expectedOutput)) {
      console.error(`UI rendered drift self-test failed for ${flag}.`);
      if (output) console.error(output.trim());
      process.exit(1);
    }
  }
}

console.log(`UI rendered drift check passed (${seen.size} drift report routes)`);
