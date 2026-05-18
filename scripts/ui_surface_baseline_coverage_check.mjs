#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const rawArgs = process.argv.slice(2);
const args = new Set(rawArgs);
const isSelfTest = process.env.CLAWIX_UI_SURFACE_BASELINE_COVERAGE_SELF_TEST === "1";
const errors = [];
const simulationFlags = [
  "--simulate-inactive-surface-baseline-manifest",
  "--simulate-extra-allowed-baseline-status",
  "--simulate-duplicate-allowed-baseline-status",
  "--simulate-extra-required-evidence-field",
  "--simulate-duplicate-required-evidence-field",
  "--simulate-mismatched-surface-reference",
  "--simulate-duplicate-coverage-id",
  "--simulate-missing-inventory-coverage",
  "--simulate-invalid-baseline-status",
  "--simulate-unsafe-geometry-reference",
  "--simulate-unsafe-copy-reference",
  "--simulate-missing-required-evidence",
  "--simulate-extra-entry-required-evidence",
  "--simulate-duplicate-entry-required-evidence",
  "--simulate-approved-invalid-hash",
  "--simulate-approved-manifest-with-pending-entry",
  "--simulate-pending-manifest-with-all-approved",
  "--simulate-missing-platform-scope",
  "--simulate-initial-scope-missing-surface-manifest",
  "--simulate-initial-scope-missing-private-geometry",
  "--simulate-initial-scope-missing-copy-verifier",
  "--simulate-initial-scope-premature-complete",
  "--simulate-approved-surface-baselines-stale-decision",
];
const allowedFlags = new Set(simulationFlags);

function fail(message) {
  errors.push(message);
}

for (const arg of rawArgs) {
  if (arg.startsWith("--") && !allowedFlags.has(arg)) {
    console.error(`UI surface baseline coverage check received unknown flag ${arg}.`);
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

function requireAlias(reference, alias, label) {
  if (typeof reference !== "string" || !reference.startsWith(`${alias}:`)) {
    fail(`${label} must use ${alias}:`);
    return null;
  }
  const suffix = reference.slice(alias.length + 1);
  if (!suffix || suffix.startsWith("/") || suffix.startsWith("\\") || suffix.startsWith("~/") || suffix.includes("..") || /^[A-Z]:\\/.test(suffix)) {
    fail(`${label} must use a safe relative private reference`);
    return null;
  }
  if (reference.includes("/Users/") || reference.startsWith("/") || reference.startsWith("~/") || reference.startsWith("file://") || /^[A-Z]:\\/.test(reference)) {
    fail(`${label} must not contain a local path`);
  }
  return suffix;
}

function requireHash(value, label) {
  if (typeof value !== "string" || !/^[a-f0-9]{64}$/i.test(value)) {
    fail(`${label} must be a 64-character hex hash`);
  }
}

function runFailureSelfTests() {
  const selfTestEnv = {
    ...process.env,
    CLAWIX_UI_SURFACE_BASELINE_COVERAGE_SELF_TEST: "1",
  };
  const tests = [
    [["--unknown-flag"], "received unknown flag --unknown-flag"],
    [["--simulate-missing-platform-scope"], "coverage must include at least one android surface"],
    [["--simulate-unsafe-geometry-reference"], "geometryEvidenceReference must use a safe relative private reference"],
    [["--simulate-mismatched-surface-reference"], "privateBaselineReference must target"],
    [["--simulate-initial-scope-premature-complete"], "status must remain open until private surface baseline, geometry, and copy artifacts are approved"],
  ];

  for (const [testArgs, expectedOutput] of tests) {
    const result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, ...testArgs], {
      cwd: rootDir,
      env: selfTestEnv,
      encoding: "utf8",
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status === 0) {
      fail(`self-test ${testArgs.join(" ")} must fail for surface baseline coverage validation`);
      continue;
    }
    if (!output.includes(expectedOutput)) {
      fail(`self-test ${testArgs.join(" ")} output must include ${expectedOutput}`);
    }
  }
}

if (!isSelfTest) {
  runFailureSelfTests();
}

const manifestPath = "docs/ui/surface-baseline-coverage.manifest.json";
const manifest = readJson(manifestPath);
const decisionVerificationPath = "docs/ui/decision-verification.json";
const decisionVerification = readJson(decisionVerificationPath);
const initialScopeDecision = (decisionVerification?.decisions || []).find((decision) => decision?.id === "initial_scope");
if (args.has("--simulate-inactive-surface-baseline-manifest") && manifest) {
  manifest.status = "active";
}
if (args.has("--simulate-extra-allowed-baseline-status") && Array.isArray(manifest?.allowedBaselineStatuses)) {
  manifest.allowedBaselineStatuses.push("captured-without-user-approval");
}
if (args.has("--simulate-duplicate-allowed-baseline-status") && Array.isArray(manifest?.allowedBaselineStatuses) && manifest.allowedBaselineStatuses[0]) {
  manifest.allowedBaselineStatuses.push(manifest.allowedBaselineStatuses[0]);
}
if (args.has("--simulate-extra-required-evidence-field") && Array.isArray(manifest?.requiredEvidenceFields)) {
  manifest.requiredEvidenceFields.push("localScreenshotPath");
}
if (args.has("--simulate-duplicate-required-evidence-field") && Array.isArray(manifest?.requiredEvidenceFields) && manifest.requiredEvidenceFields[0]) {
  manifest.requiredEvidenceFields.push(manifest.requiredEvidenceFields[0]);
}
if (args.has("--simulate-mismatched-surface-reference") && Array.isArray(manifest?.coverage) && manifest.coverage[0]) {
  manifest.coverage[0] = {
    ...manifest.coverage[0],
    privateBaselineReference: `${manifest.privateBaselineAlias}:surfaces/${manifest.coverage[0].platform}/wrong-surface`,
  };
}
if (args.has("--simulate-duplicate-coverage-id") && Array.isArray(manifest?.coverage) && manifest.coverage[0]) {
  manifest.coverage.push({ ...manifest.coverage[0] });
}
if (args.has("--simulate-missing-inventory-coverage") && Array.isArray(manifest?.coverage)) {
  manifest.coverage = manifest.coverage.slice(0, -1);
}
if (args.has("--simulate-invalid-baseline-status") && Array.isArray(manifest?.coverage) && manifest.coverage[0]) {
  manifest.coverage[0].baselineStatus = "captured-without-user-approval";
}
if (args.has("--simulate-unsafe-geometry-reference") && Array.isArray(manifest?.coverage) && manifest.coverage[0]) {
  manifest.coverage[0].geometryEvidenceReference = `${manifest.privateGeometryAlias}:../geometry`;
}
if (args.has("--simulate-unsafe-copy-reference") && Array.isArray(manifest?.coverage) && manifest.coverage[0]) {
  manifest.coverage[0].copySnapshotReference = "/Users/example/copy-snapshot";
}
if (args.has("--simulate-missing-required-evidence") && Array.isArray(manifest?.coverage) && manifest.coverage[0]) {
  manifest.coverage[0].requiredEvidence = manifest.coverage[0].requiredEvidence.filter((field) => field !== "approvedScope");
}
if (args.has("--simulate-extra-entry-required-evidence") && Array.isArray(manifest?.coverage) && manifest.coverage[0]) {
  manifest.coverage[0].requiredEvidence.push("localScreenshotPath");
}
if (args.has("--simulate-duplicate-entry-required-evidence") && Array.isArray(manifest?.coverage) && manifest.coverage[0]) {
  manifest.coverage[0].requiredEvidence.push(manifest.coverage[0].requiredEvidence[0]);
}
if (args.has("--simulate-approved-invalid-hash") && Array.isArray(manifest?.coverage) && manifest.coverage[0]) {
  manifest.coverage[0].baselineStatus = "approved";
  manifest.coverage[0].screenshotHash = "not-a-hex-hash";
}
if (args.has("--simulate-approved-manifest-with-pending-entry") && manifest) {
  manifest.status = "approved-private-capture";
}
if (args.has("--simulate-pending-manifest-with-all-approved") && Array.isArray(manifest?.coverage)) {
  manifest.status = "pending-private-capture";
  const simulatedHash = "a".repeat(64);
  manifest.coverage = manifest.coverage.map((entry) => ({
    ...entry,
    baselineStatus: "approved",
    screenshotHash: simulatedHash,
    geometryHash: simulatedHash,
    copySnapshotHash: simulatedHash,
    baselineArtifactHash: simulatedHash,
  }));
}
if (args.has("--simulate-missing-platform-scope") && Array.isArray(manifest?.coverage)) {
  manifest.coverage = manifest.coverage.filter((entry) => entry?.platform !== "android");
}
if (args.has("--simulate-initial-scope-missing-surface-manifest") && initialScopeDecision) {
  initialScopeDecision.publicEvidence = initialScopeDecision.publicEvidence.filter((evidencePath) => evidencePath !== manifestPath);
}
if (args.has("--simulate-initial-scope-missing-private-geometry") && initialScopeDecision) {
  initialScopeDecision.privateEvidence = initialScopeDecision.privateEvidence.filter((evidencePath) => evidencePath !== `${manifest?.privateGeometryAlias}:surfaces/*`);
}
if (args.has("--simulate-initial-scope-missing-copy-verifier") && initialScopeDecision) {
  initialScopeDecision.blockingVerifiers = initialScopeDecision.blockingVerifiers.filter((verifier) => verifier !== "scripts/ui_private_copy_verify.mjs");
}
if (args.has("--simulate-initial-scope-premature-complete") && initialScopeDecision) {
  initialScopeDecision.status = "verified-complete";
  initialScopeDecision.remaining = [];
}
if (args.has("--simulate-approved-surface-baselines-stale-decision") && manifest && Array.isArray(manifest.coverage) && initialScopeDecision) {
  manifest.status = "approved-private-capture";
  const simulatedHash = "a".repeat(64);
  manifest.coverage = manifest.coverage.map((entry) => ({
    ...entry,
    baselineStatus: "approved",
    screenshotHash: simulatedHash,
    geometryHash: simulatedHash,
    copySnapshotHash: simulatedHash,
    baselineArtifactHash: simulatedHash,
  }));
  initialScopeDecision.status = "open";
  initialScopeDecision.remaining = ["Simulated stale decision after approved private surface evidence."];
}
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "inventoryPath",
  "privateBaselineAlias",
  "privateGeometryAlias",
  "privateCopyAlias",
  "surfaceEvidenceFilename",
  "allowedBaselineStatuses",
  "requiredEvidenceFields",
  "coverage",
]);
if (manifest?.surfaceEvidenceFilename !== "surface-evidence.json") {
  fail(`${manifestPath}.surfaceEvidenceFilename must be surface-evidence.json`);
}
if (!["pending-private-capture", "approved-private-capture"].includes(manifest?.status)) {
  fail(`${manifestPath}.status must be pending-private-capture or approved-private-capture`);
}

const privateBaselines = readJson("docs/ui/private-baselines.manifest.json");
if (manifest?.privateBaselineAlias !== privateBaselines?.privateRootAlias) {
  fail(`${manifestPath}.privateBaselineAlias must match docs/ui/private-baselines.manifest.json`);
}
const renderedGeometry = readJson("docs/ui/rendered-geometry.manifest.json");
if (manifest?.privateGeometryAlias !== renderedGeometry?.privateGeometryAlias) {
  fail(`${manifestPath}.privateGeometryAlias must match docs/ui/rendered-geometry.manifest.json`);
}
const copyInventory = readJson("docs/ui/copy.inventory.json");
if (manifest?.privateCopyAlias !== copyInventory?.privateSnapshotAlias) {
  fail(`${manifestPath}.privateCopyAlias must match docs/ui/copy.inventory.json`);
}

const requiredEvidenceFieldValues = [
  "coverageId",
  "platform",
  "privateBaselineReference",
  "captureCommand",
  "screenshotHash",
  "geometryHash",
  "copySnapshotHash",
  "baselineArtifactHash",
  "approvedByUserAt",
  "approvedScope",
];
requireExactStringSet(
  requireArray(manifest, manifestPath, "requiredEvidenceFields"),
  `${manifestPath}.requiredEvidenceFields`,
  requiredEvidenceFieldValues,
);
const allowedStatuses = requireExactStringSet(
  requireArray(manifest, manifestPath, "allowedBaselineStatuses"),
  `${manifestPath}.allowedBaselineStatuses`,
  ["pending-user-approved-capture", "approved"],
);

const inventoryPath = manifest?.inventoryPath || "docs/ui/visible-surfaces.inventory.json";
const inventory = readJson(inventoryPath);
const inventoryById = new Map();
for (const [index, entry] of requireArray(inventory, inventoryPath, "coverage").entries()) {
  if (inventoryById.has(entry.id)) fail(`${inventoryPath}.coverage[${index}].id duplicates ${entry.id}`);
  inventoryById.set(entry.id, entry);
}

const seen = new Set();
const platformsSeen = new Set();
let approvedCoverageCount = 0;
let pendingCoverageCount = 0;
for (const [index, entry] of requireArray(manifest, manifestPath, "coverage").entries()) {
  const label = `${manifestPath}.coverage[${index}]`;
  requireFields(entry, label, [
    "coverageId",
    "platform",
    "classification",
    "baselineStatus",
    "privateBaselineReference",
    "geometryEvidenceReference",
    "copySnapshotReference",
    "requiredEvidence",
  ]);
  if (seen.has(entry.coverageId)) fail(`${label}.coverageId duplicates ${entry.coverageId}`);
  seen.add(entry.coverageId);
  if (entry.platform) platformsSeen.add(entry.platform);
  if (entry.baselineStatus === "approved") approvedCoverageCount += 1;
  if (entry.baselineStatus === "pending-user-approved-capture") pendingCoverageCount += 1;
  const inventoryEntry = inventoryById.get(entry.coverageId);
  if (!inventoryEntry) {
    fail(`${label}.coverageId is not listed in ${inventoryPath}`);
    continue;
  }
  if (entry.platform !== inventoryEntry.platform) fail(`${label}.platform must match ${inventoryPath}`);
  if (entry.classification !== inventoryEntry.classification) fail(`${label}.classification must match ${inventoryPath}`);
  if (!allowedStatuses.has(entry.baselineStatus)) fail(`${label}.baselineStatus is not allowed`);
  const expectedSurfaceReference = `surfaces/${entry.platform}/${entry.coverageId}`;
  const baselineReferenceSuffix = requireAlias(entry.privateBaselineReference, manifest.privateBaselineAlias, `${label}.privateBaselineReference`);
  const geometryReferenceSuffix = requireAlias(entry.geometryEvidenceReference, manifest.privateGeometryAlias, `${label}.geometryEvidenceReference`);
  const copyReferenceSuffix = requireAlias(entry.copySnapshotReference, manifest.privateCopyAlias, `${label}.copySnapshotReference`);
  if (baselineReferenceSuffix && baselineReferenceSuffix !== expectedSurfaceReference) {
    fail(`${label}.privateBaselineReference must target ${expectedSurfaceReference}`);
  }
  if (geometryReferenceSuffix && geometryReferenceSuffix !== expectedSurfaceReference) {
    fail(`${label}.geometryEvidenceReference must target ${expectedSurfaceReference}`);
  }
  if (copyReferenceSuffix && copyReferenceSuffix !== expectedSurfaceReference) {
    fail(`${label}.copySnapshotReference must target ${expectedSurfaceReference}`);
  }
  requireExactStringSet(requireArray(entry, label, "requiredEvidence"), `${label}.requiredEvidence`, requiredEvidenceFieldValues);
  if (entry.baselineStatus === "approved") {
    for (const hashField of ["screenshotHash", "geometryHash", "copySnapshotHash", "baselineArtifactHash"]) {
      requireHash(entry[hashField], `${label}.${hashField}`);
    }
  }
}

if (manifest?.status === "approved-private-capture" && pendingCoverageCount > 0) {
  fail(`${manifestPath}.status cannot be approved-private-capture while ${pendingCoverageCount} coverage entries are pending`);
}
if (manifest?.status === "pending-private-capture" && approvedCoverageCount === seen.size && seen.size > 0) {
  fail(`${manifestPath}.status must be approved-private-capture when all coverage entries are approved`);
}

for (const coverageId of inventoryById.keys()) {
  if (!seen.has(coverageId)) fail(`${manifestPath}.coverage must include ${coverageId}`);
}

for (const platform of ["macos", "ios", "android", "web"]) {
  if (!platformsSeen.has(platform)) fail(`${manifestPath}.coverage must include at least one ${platform} surface`);
}

if (!initialScopeDecision) {
  fail(`${decisionVerificationPath}.decisions must include initial_scope`);
} else {
  const publicEvidence = new Set(Array.isArray(initialScopeDecision.publicEvidence) ? initialScopeDecision.publicEvidence : []);
  for (const evidencePath of [
    "docs/ui/interface-governance.config.json",
    "docs/ui/pattern-registry/patterns.registry.json",
    inventoryPath,
    manifestPath,
    "scripts/ui_surface_baseline_coverage_check.mjs",
    "scripts/ui_private_evidence_plan_check.mjs",
    "scripts/ui_private_evidence_verify.mjs",
  ]) {
    if (!publicEvidence.has(evidencePath)) {
      fail(`${decisionVerificationPath}.decisions.initial_scope.publicEvidence must include ${evidencePath}`);
    }
  }
  const privateEvidence = new Set(Array.isArray(initialScopeDecision.privateEvidence) ? initialScopeDecision.privateEvidence : []);
  for (const evidencePath of [
    `${manifest?.privateBaselineAlias}:surfaces/*`,
    `${manifest?.privateGeometryAlias}:surfaces/*`,
    `${manifest?.privateCopyAlias}:surfaces/*`,
  ]) {
    if (!privateEvidence.has(evidencePath)) {
      fail(`${decisionVerificationPath}.decisions.initial_scope.privateEvidence must include ${evidencePath}`);
    }
  }
  const blockingVerifiers = new Set(Array.isArray(initialScopeDecision.blockingVerifiers) ? initialScopeDecision.blockingVerifiers : []);
  for (const verifier of [
    "scripts/ui_private_evidence_verify.mjs",
    "scripts/ui_private_baseline_verify.mjs",
    "scripts/ui_private_geometry_verify.mjs",
    "scripts/ui_private_copy_verify.mjs",
  ]) {
    if (!blockingVerifiers.has(verifier)) {
      fail(`${decisionVerificationPath}.decisions.initial_scope.blockingVerifiers must include ${verifier}`);
    }
  }
  if (manifest?.status !== "approved-private-capture" && initialScopeDecision.status !== "open") {
    fail(`${decisionVerificationPath}.decisions.initial_scope.status must remain open until private surface baseline, geometry, and copy artifacts are approved`);
  }
  if (manifest?.status !== "approved-private-capture" && (!Array.isArray(initialScopeDecision.remaining) || initialScopeDecision.remaining.length === 0)) {
    fail(`${decisionVerificationPath}.decisions.initial_scope.remaining must describe pending private surface evidence`);
  }
  if (manifest?.status === "approved-private-capture" && initialScopeDecision.status !== "verified-complete") {
    fail(`${decisionVerificationPath}.decisions.initial_scope.status must be verified-complete after private surface baseline, geometry, and copy artifacts are approved`);
  }
  if (manifest?.status === "approved-private-capture" && Array.isArray(initialScopeDecision.remaining) && initialScopeDecision.remaining.length > 0) {
    fail(`${decisionVerificationPath}.decisions.initial_scope.remaining must be empty after private surface baseline, geometry, and copy artifacts are approved`);
  }
}

if (errors.length > 0) {
  console.error("UI surface baseline coverage check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI surface baseline coverage check passed (${seen.size} surface baselines)`);
