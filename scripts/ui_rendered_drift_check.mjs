#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = new Set(process.argv.slice(2));
const today = new Date().toISOString().slice(0, 10);
const errors = [];

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
  if (nonEmpty && value.length === 0) fail(`${label}.${field} must not be empty`);
  return value;
}

function requireAlias(value, alias, label) {
  if (typeof value !== "string" || !value.startsWith(`${alias}:`)) {
    fail(`${label} must use ${alias}:`);
    return;
  }
  const suffix = value.slice(alias.length + 1);
  if (!suffix || suffix.startsWith("/") || suffix.startsWith("\\") || suffix.startsWith("~/") || suffix.includes("..") || /^[A-Z]:\\/.test(suffix)) {
    fail(`${label} must use a safe relative private reference`);
  }
  if (value.includes("/Users/") || value.startsWith("~/") || value.startsWith("file://") || /^[A-Z]:\\/.test(value)) {
    fail(`${label} must not contain a local path`);
  }
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
  if (args.has("--simulate-missing-drift-category") && Array.isArray(manifest.driftCategories)) {
    manifest.driftCategories = manifest.driftCategories.filter((category) => category !== "copy");
  }
  if (args.has("--simulate-missing-failure-output-requirement") && Array.isArray(manifest.failureOutputRequirements)) {
    manifest.failureOutputRequirements = manifest.failureOutputRequirements.filter((field) => field !== "required permission");
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
  if (args.has("--simulate-expired-review") && Array.isArray(manifest.reports) && manifest.reports[0]) {
    manifest.reports[0].reviewAfter = "2026-01-01";
  }
  if (args.has("--simulate-invalid-report-status") && Array.isArray(manifest.reports) && manifest.reports[0]) {
    manifest.reports[0].status = "ignored-drift";
  }
  if (args.has("--simulate-enforcement-missing-rendered-drift") && enforcementModeDecision) {
    enforcementModeDecision.publicEvidence = enforcementModeDecision.publicEvidence.filter((evidencePath) => evidencePath !== manifestPath);
  }
  if (args.has("--simulate-enforcement-missing-private-drift-verifier") && enforcementModeDecision) {
    enforcementModeDecision.blockingVerifiers = enforcementModeDecision.blockingVerifiers.filter((verifier) => verifier !== "scripts/ui_private_drift_verify.mjs");
  }
  if (args.has("--simulate-enforcement-missing-private-drift-evidence") && enforcementModeDecision) {
    enforcementModeDecision.privateEvidence = [];
  }
  if (args.has("--simulate-enforcement-premature-complete") && enforcementModeDecision) {
    enforcementModeDecision.status = "verified-complete";
    enforcementModeDecision.remaining = [];
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
const categories = new Set(requireArray(manifest, manifestPath, "driftCategories"));
for (const category of expectedCategories) {
  if (!categories.has(category)) fail(`${manifestPath}.driftCategories must include ${category}`);
}
const statuses = new Set(requireArray(manifest, manifestPath, "reportStatuses"));
for (const status of ["pending-private-evidence", "no-drift", "drift-detected", "approved-drift"]) {
  if (!statuses.has(status)) fail(`${manifestPath}.reportStatuses must include ${status}`);
}
const blockingStatuses = new Set(requireArray(manifest, manifestPath, "blockingReportStatuses"));
for (const status of ["pending-private-evidence", "drift-detected"]) {
  if (!blockingStatuses.has(status)) fail(`${manifestPath}.blockingReportStatuses must include ${status}`);
}
const approvalRequiredStatuses = new Set(requireArray(manifest, manifestPath, "approvalRequiredStatuses"));
if (!approvalRequiredStatuses.has("approved-drift")) {
  fail(`${manifestPath}.approvalRequiredStatuses must include approved-drift`);
}
const requiredReportFields = requireArray(manifest, manifestPath, "requiredReportFields");
for (const field of ["coverageId", "platform", "privateDriftReportReference", "driftCategories", "status", "reviewAfter"]) {
  if (!requiredReportFields.includes(field)) fail(`${manifestPath}.requiredReportFields must include ${field}`);
}
const requiredEvidenceFields = requireArray(manifest, manifestPath, "requiredEvidenceFields");
for (const field of ["coverageId", "platform", "privateDriftReportReference", "driftCategories", "driftResults", "status", "reportHash", "producedAt"]) {
  if (!requiredEvidenceFields.includes(field)) fail(`${manifestPath}.requiredEvidenceFields must include ${field}`);
}
const approvedDriftEvidenceFields = requireArray(manifest, manifestPath, "approvedDriftEvidenceFields");
for (const field of ["approvedByUserAt", "approvedScope"]) {
  if (!approvedDriftEvidenceFields.includes(field)) fail(`${manifestPath}.approvedDriftEvidenceFields must include ${field}`);
}
const failureOutputRequirements = requireArray(manifest, manifestPath, "failureOutputRequirements");
for (const field of ["route", "reason", "required permission", "proposal route", "privateDriftReportReference"]) {
  if (!failureOutputRequirements.includes(field)) fail(`${manifestPath}.failureOutputRequirements must include ${field}`);
}
if (manifest?.evidenceFilename !== "drift-report.json") fail(`${manifestPath}.evidenceFilename must be drift-report.json`);

const coveragePath = manifest?.surfaceBaselineCoveragePath || "docs/ui/surface-baseline-coverage.manifest.json";
const coverage = readJson(coveragePath);
const coverageById = new Map();
for (const entry of requireArray(coverage, coveragePath, "coverage")) {
  coverageById.set(entry.coverageId, entry);
}

const seen = new Set();
for (const [index, report] of requireArray(manifest, manifestPath, "reports").entries()) {
  const label = `${manifestPath}.reports[${index}]`;
  requireFields(report, label, requiredReportFields);
  if (seen.has(report.coverageId)) fail(`${label}.coverageId duplicates ${report.coverageId}`);
  seen.add(report.coverageId);
  const coverageEntry = coverageById.get(report.coverageId);
  if (!coverageEntry) {
    fail(`${label}.coverageId is not listed in ${coveragePath}`);
    continue;
  }
  if (report.platform !== coverageEntry.platform) fail(`${label}.platform must match ${coveragePath}`);
  requireAlias(report.privateDriftReportReference, manifest.privateDriftAlias, `${label}.privateDriftReportReference`);
  if (!statuses.has(report.status)) fail(`${label}.status is not allowed`);
  if (report.reviewAfter < today) fail(`${label}.reviewAfter expired on ${report.reviewAfter}`);
  const reportCategories = new Set(requireArray(report, label, "driftCategories"));
  for (const category of categories) {
    if (!reportCategories.has(category)) fail(`${label}.driftCategories must include ${category}`);
  }
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
  const privateEvidence = new Set(Array.isArray(enforcementModeDecision.privateEvidence) ? enforcementModeDecision.privateEvidence : []);
  if (!privateEvidence.has(`${manifest?.privateDriftAlias}:surfaces/*`)) {
    fail(`${decisionVerificationPath}.decisions.enforcement_mode.privateEvidence must include ${manifest?.privateDriftAlias}:surfaces/*`);
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
  if (manifest?.status !== "active" && enforcementModeDecision.status !== "open") {
    fail(`${decisionVerificationPath}.decisions.enforcement_mode.status must remain open until private rendered drift evidence is captured`);
  }
  if (manifest?.status !== "active" && (!Array.isArray(enforcementModeDecision.remaining) || enforcementModeDecision.remaining.length === 0)) {
    fail(`${decisionVerificationPath}.decisions.enforcement_mode.remaining must describe pending rendered drift evidence`);
  }
}

if (errors.length > 0) {
  console.error("UI rendered drift check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI rendered drift check passed (${seen.size} drift report routes)`);
