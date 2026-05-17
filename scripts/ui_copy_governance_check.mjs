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

function requirePublicSafeReference(value, alias, label) {
  if (typeof value !== "string" || !value.startsWith(`${alias}:`)) {
    fail(`${label} must use ${alias}: and must not contain a local path`);
    return null;
  }
  const suffix = value.slice(alias.length + 1);
  if (
    suffix.length === 0 ||
    suffix.startsWith("/") ||
    suffix.startsWith("\\") ||
    suffix.startsWith("~/") ||
    suffix.split("/").includes("..") ||
    suffix.split("/").includes(".") ||
    /^[A-Z]:\\/.test(suffix) ||
    value.includes("/Users/") ||
    value.startsWith("~/") ||
    value.startsWith("file://")
  ) {
    fail(`${label} must use ${alias}: and must not contain a local path`);
    return null;
  }
  return suffix;
}

const copyPath = "docs/ui/copy.inventory.json";
const copyInventory = readJson(copyPath);
const decisionVerificationPath = "docs/ui/decision-verification.json";
const decisionVerification = readJson(decisionVerificationPath);
const copyGovernanceDecision = (decisionVerification?.decisions || []).find((decision) => decision?.id === "copy_governance");
requireFields(copyInventory, copyPath, [
  "schemaVersion",
  "status",
  "policy",
  "patternCopySource",
  "surfaceCoverageSource",
  "protectedSurfaceSource",
  "privateSnapshotAlias",
  "evidenceFilename",
  "verificationCommand",
  "protectedSurfaceRequirement",
  "restrictedCopyKinds",
  "requiredEvidenceFields",
]);

if (args.has("--simulate-inactive-copy-inventory") && copyInventory) {
  copyInventory.status = "draft";
}
if (args.has("--simulate-wrong-private-snapshot-alias") && copyInventory) {
  copyInventory.privateSnapshotAlias = "private-local-copy-snapshots";
}
if (args.has("--simulate-extra-copy-kind") && Array.isArray(copyInventory?.restrictedCopyKinds)) {
  copyInventory.restrictedCopyKinds = [...copyInventory.restrictedCopyKinds, "marketing-tagline"];
}
if (args.has("--simulate-duplicate-copy-kind") && Array.isArray(copyInventory?.restrictedCopyKinds)) {
  copyInventory.restrictedCopyKinds = [...copyInventory.restrictedCopyKinds, copyInventory.restrictedCopyKinds[0]];
}
if (args.has("--simulate-extra-required-evidence") && Array.isArray(copyInventory?.requiredEvidenceFields)) {
  copyInventory.requiredEvidenceFields = [...copyInventory.requiredEvidenceFields, "approvalNote"];
}
if (args.has("--simulate-duplicate-required-evidence") && Array.isArray(copyInventory?.requiredEvidenceFields)) {
  copyInventory.requiredEvidenceFields = [...copyInventory.requiredEvidenceFields, copyInventory.requiredEvidenceFields[0]];
}

if (args.has("--simulate-copy-decision-missing-inventory") && copyGovernanceDecision) {
  copyGovernanceDecision.publicEvidence = copyGovernanceDecision.publicEvidence.filter((evidencePath) => evidencePath !== copyPath);
}
if (args.has("--simulate-copy-decision-missing-evidence-plan") && copyGovernanceDecision) {
  copyGovernanceDecision.publicEvidence = copyGovernanceDecision.publicEvidence.filter((evidencePath) => evidencePath !== "scripts/ui_private_evidence_plan_check.mjs");
}
if (args.has("--simulate-copy-decision-missing-evidence-verifier") && copyGovernanceDecision) {
  copyGovernanceDecision.publicEvidence = copyGovernanceDecision.publicEvidence.filter((evidencePath) => evidencePath !== "scripts/ui_private_evidence_verify.mjs");
}
if (args.has("--simulate-copy-decision-missing-private-verifier") && copyGovernanceDecision) {
  copyGovernanceDecision.blockingVerifiers = copyGovernanceDecision.blockingVerifiers.filter((verifier) => verifier !== "scripts/ui_private_copy_verify.mjs");
}
if (args.has("--simulate-copy-decision-missing-private-evidence") && copyGovernanceDecision) {
  copyGovernanceDecision.privateEvidence = [];
}
if (args.has("--simulate-copy-decision-premature-complete") && copyGovernanceDecision) {
  copyGovernanceDecision.status = "verified-complete";
  copyGovernanceDecision.remaining = [];
}

const requiredCopyKinds = [
  "visible-name",
  "label",
  "placeholder",
  "tooltip",
  "microcopy",
  "empty-state",
  "loading-state",
  "error-state",
  "copy-hierarchy",
];
if (copyInventory?.status !== "active" && copyInventory?.status !== "approved-private-snapshots") {
  fail(`${copyPath}.status must be active or approved-private-snapshots`);
}
if (copyInventory?.privateSnapshotAlias !== "private-codex-ui-copy-snapshots") {
  fail(`${copyPath}.privateSnapshotAlias must be private-codex-ui-copy-snapshots`);
}
if (copyInventory?.evidenceFilename !== "copy-evidence.json") {
  fail(`${copyPath}.evidenceFilename must be copy-evidence.json`);
}
if (!String(copyInventory?.verificationCommand || "").includes("scripts/ui_private_copy_verify.mjs")) {
  fail(`${copyPath}.verificationCommand must run scripts/ui_private_copy_verify.mjs`);
}
if (!String(copyInventory?.verificationCommand || "").includes("--require-approved")) {
  fail(`${copyPath}.verificationCommand must require approved private copy evidence`);
}
const protectedSurfaceRequirement = copyInventory?.protectedSurfaceRequirement || {};
for (const field of [
  "copySnapshotReferenceRequired",
  "approvedCopyHashRequired",
  "approvalBlockedWithoutSnapshot",
]) {
  if (protectedSurfaceRequirement[field] !== true) {
    fail(`${copyPath}.protectedSurfaceRequirement.${field} must be true`);
  }
}
let copyKinds = requireArray(copyInventory, copyPath, "restrictedCopyKinds");
if (args.has("--simulate-missing-copy-kind")) {
  copyKinds = copyKinds.filter((kind) => kind !== "tooltip");
}
requireExactStringSet(copyKinds, `${copyPath}.restrictedCopyKinds`, requiredCopyKinds);

const requiredEvidence = [
  "coverageId",
  "platform",
  "copyItems",
  "copySnapshotReference",
  "copySnapshotHash",
  "copyHierarchyHash",
  "approvedByUserAt",
  "approvedScope",
];
let evidence = requireArray(copyInventory, copyPath, "requiredEvidenceFields");
if (args.has("--simulate-missing-required-evidence")) {
  evidence = evidence.filter((field) => field !== "copyHierarchyHash");
}
requireExactStringSet(evidence, `${copyPath}.requiredEvidenceFields`, requiredEvidence);

const registryPath = "docs/ui/pattern-registry/patterns.registry.json";
const registry = readJson(registryPath);
const patternIds = requireArray(registry, registryPath, "patterns");
for (const patternId of patternIds) {
  const patternPath = `docs/ui/pattern-registry/patterns/${patternId}.pattern.json`;
  const pattern = readJson(patternPath);
  if (!pattern) continue;
  if (args.has("--simulate-missing-pattern-copy-contract") && patternId === "sidebar-row") {
    delete pattern.copy;
  }
  if (args.has("--simulate-invalid-pattern-copy-key") && patternId === "sidebar-row") {
    pattern.copy = { ...pattern.copy, "Visible Label": true };
  }
  const copy = pattern.copy;
  if (!copy || typeof copy !== "object" || Array.isArray(copy) || Object.keys(copy).length === 0) {
    fail(`${patternPath}.copy must declare a non-empty copy contract`);
    continue;
  }
  for (const [key, value] of Object.entries(copy)) {
    if (!/^[a-z][A-Za-z0-9]*$/.test(key)) {
      fail(`${patternPath}.copy.${key} must use stable lowerCamelCase naming`);
    }
    if (typeof value === "number" && (!Number.isFinite(value) || value < 0)) {
      fail(`${patternPath}.copy.${key} must be a finite non-negative number`);
    } else if (!["boolean", "number", "string"].includes(typeof value)) {
      fail(`${patternPath}.copy.${key} must be a boolean, number, or string`);
    }
  }
}

const protectedPath = "docs/ui/protected-surfaces.registry.json";
const protectedSurfaces = readJson(protectedPath);
const privateAlias = copyInventory?.privateSnapshotAlias || "";
const surfaceCoveragePath = copyInventory?.surfaceCoverageSource || "docs/ui/surface-baseline-coverage.manifest.json";
const surfaceCoverage = readJson(surfaceCoveragePath);
if (args.has("--simulate-mismatched-copy-snapshot-reference") && Array.isArray(surfaceCoverage?.coverage) && surfaceCoverage.coverage[0]) {
  surfaceCoverage.coverage[0] = {
    ...surfaceCoverage.coverage[0],
    copySnapshotReference: `${privateAlias}:surfaces/${surfaceCoverage.coverage[0].platform}/wrong-surface`,
  };
}
if (args.has("--simulate-absolute-copy-snapshot-reference") && Array.isArray(surfaceCoverage?.coverage) && surfaceCoverage.coverage[0]) {
  surfaceCoverage.coverage[0] = {
    ...surfaceCoverage.coverage[0],
    copySnapshotReference: `${privateAlias}:${path.join(path.sep, "tmp", "copy-evidence")}`,
  };
}
if (args.has("--simulate-coverage-missing-copy-hash") && Array.isArray(surfaceCoverage?.coverage) && surfaceCoverage.coverage[0]) {
  surfaceCoverage.coverage[0] = {
    ...surfaceCoverage.coverage[0],
    requiredEvidence: surfaceCoverage.coverage[0].requiredEvidence.filter((field) => field !== "copySnapshotHash"),
  };
}
if (args.has("--simulate-coverage-extra-copy-evidence") && Array.isArray(surfaceCoverage?.coverage) && surfaceCoverage.coverage[0]) {
  surfaceCoverage.coverage[0] = {
    ...surfaceCoverage.coverage[0],
    requiredEvidence: [...surfaceCoverage.coverage[0].requiredEvidence, "localCopyPath"],
  };
}
if (args.has("--simulate-coverage-duplicate-copy-evidence") && Array.isArray(surfaceCoverage?.coverage) && surfaceCoverage.coverage[0]?.requiredEvidence?.[0]) {
  surfaceCoverage.coverage[0] = {
    ...surfaceCoverage.coverage[0],
    requiredEvidence: [...surfaceCoverage.coverage[0].requiredEvidence, surfaceCoverage.coverage[0].requiredEvidence[0]],
  };
}
if (args.has("--simulate-wrong-surface-copy-alias") && surfaceCoverage) {
  surfaceCoverage.privateCopyAlias = "private-local-copy-snapshots";
}
if (surfaceCoverage?.privateCopyAlias !== privateAlias) {
  fail(`${surfaceCoveragePath}.privateCopyAlias must match ${copyPath}.privateSnapshotAlias`);
}
const surfaceCoverageEvidence = requireArray(surfaceCoverage, surfaceCoveragePath, "requiredEvidenceFields");
for (const [index, entry] of requireArray(surfaceCoverage, surfaceCoveragePath, "coverage").entries()) {
  const label = `${surfaceCoveragePath}.coverage[${index}]`;
  requireFields(entry, label, ["coverageId", "platform", "copySnapshotReference", "requiredEvidence"]);
  const copySnapshotSuffix = requirePublicSafeReference(entry.copySnapshotReference, privateAlias, `${label}.copySnapshotReference`);
  const expectedCopySnapshotSuffix = `surfaces/${entry.platform}/${entry.coverageId}`;
  if (copySnapshotSuffix && copySnapshotSuffix !== expectedCopySnapshotSuffix) {
    fail(`${label}.copySnapshotReference must target ${expectedCopySnapshotSuffix}`);
  }
  requireExactStringSet(requireArray(entry, label, "requiredEvidence"), `${label}.requiredEvidence`, surfaceCoverageEvidence);
}
for (const [index, surface] of requireArray(protectedSurfaces, protectedPath, "surfaces", { nonEmpty: false }).entries()) {
  const label = `${protectedPath}.surfaces[${index}]`;
  requireFields(surface, label, ["copySnapshotReference", "copySnapshotHash"]);
  requirePublicSafeReference(surface.copySnapshotReference, privateAlias, `${label}.copySnapshotReference`);
  if (typeof surface.copySnapshotHash !== "string" || surface.copySnapshotHash.length < 16) {
    fail(`${label}.copySnapshotHash must record the approved private copy snapshot hash`);
  }
}

const privateSnapshotAlias = copyInventory?.privateSnapshotAlias || "private-codex-ui-copy-snapshots";
if (!copyGovernanceDecision) {
  fail(`${decisionVerificationPath}.decisions must include copy_governance`);
} else {
  const publicEvidence = new Set(Array.isArray(copyGovernanceDecision.publicEvidence) ? copyGovernanceDecision.publicEvidence : []);
  for (const evidencePath of [
    "docs/ui/interface-governance.config.json",
    "docs/ui/visible-surfaces.inventory.json",
    copyPath,
    "scripts/ui_copy_governance_check.mjs",
    "scripts/ui_private_evidence_plan_check.mjs",
    "scripts/ui_private_evidence_verify.mjs",
    "scripts/ui_private_copy_verify.mjs",
  ]) {
    if (!publicEvidence.has(evidencePath)) {
      fail(`${decisionVerificationPath}.decisions.copy_governance.publicEvidence must include ${evidencePath}`);
    }
  }
  const privateEvidence = Array.isArray(copyGovernanceDecision.privateEvidence) ? copyGovernanceDecision.privateEvidence : [];
  if (!privateEvidence.includes(`${privateSnapshotAlias}:surfaces/*`)) {
    fail(`${decisionVerificationPath}.decisions.copy_governance.privateEvidence must include ${privateSnapshotAlias}:surfaces/*`);
  }
  const blockingVerifiers = new Set(Array.isArray(copyGovernanceDecision.blockingVerifiers) ? copyGovernanceDecision.blockingVerifiers : []);
  for (const verifier of [
    "scripts/ui_private_copy_verify.mjs",
    "scripts/ui_private_evidence_verify.mjs",
  ]) {
    if (!blockingVerifiers.has(verifier)) {
      fail(`${decisionVerificationPath}.decisions.copy_governance.blockingVerifiers must include ${verifier}`);
    }
  }
  if (copyInventory?.status !== "approved-private-snapshots" && copyGovernanceDecision.status !== "open") {
    fail(`${decisionVerificationPath}.decisions.copy_governance.status must remain open until private copy snapshots are captured and approved`);
  }
  if (copyInventory?.status !== "approved-private-snapshots" && (!Array.isArray(copyGovernanceDecision.remaining) || copyGovernanceDecision.remaining.length === 0)) {
    fail(`${decisionVerificationPath}.decisions.copy_governance.remaining must describe pending private copy snapshots`);
  }
}

if (errors.length > 0) {
  console.error("UI copy governance check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI copy governance check passed (${patternIds.length} pattern copy contracts)`);
