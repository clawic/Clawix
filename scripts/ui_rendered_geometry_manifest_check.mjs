#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const rawArgs = process.argv.slice(2);
const args = new Set(rawArgs);
const isSelfTest = process.env.CLAWIX_UI_RENDERED_GEOMETRY_MANIFEST_SELF_TEST === "1";
const simulationFlags = [
  "--simulate-inactive-rendered-geometry",
  "--simulate-wrong-private-alias",
  "--simulate-wrong-evidence-filename",
  "--simulate-verifier-without-approval",
  "--simulate-missing-pattern-evidence-field",
  "--simulate-extra-pattern-evidence-field",
  "--simulate-duplicate-pattern-evidence-field",
  "--simulate-missing-surface-evidence-field",
  "--simulate-extra-surface-evidence-field",
  "--simulate-duplicate-surface-evidence-field",
  "--simulate-extra-public-forbidden-store",
  "--simulate-duplicate-public-forbidden-store",
  "--simulate-local-path-reference",
  "--simulate-alignment-decision-missing-rendered-geometry",
  "--simulate-alignment-decision-missing-private-visual",
  "--simulate-alignment-decision-missing-private-geometry-verifier",
  "--simulate-alignment-decision-missing-baseline-verifier",
  "--simulate-alignment-decision-missing-platform-evidence",
  "--simulate-alignment-decision-premature-complete",
  "--simulate-approved-geometry-stale-decision",
];
const allowedFlags = new Set(simulationFlags);
const errors = [];

function fail(message) {
  errors.push(message);
}

for (const arg of rawArgs) {
  if (arg.startsWith("--") && !allowedFlags.has(arg)) {
    console.error(`UI rendered geometry manifest check received unknown flag ${arg}.`);
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

function requireArray(object, label, field) {
  const value = object?.[field];
  if (!Array.isArray(value)) {
    fail(`${label}.${field} must be an array`);
    return [];
  }
  if (value.length === 0) fail(`${label}.${field} must not be empty`);
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

function scanForLocalPaths(value, label) {
  if (Array.isArray(value)) {
    value.forEach((child, index) => scanForLocalPaths(child, `${label}[${index}]`));
    return;
  }
  if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) scanForLocalPaths(child, `${label}.${key}`);
    return;
  }
  if (typeof value === "string" && (/^\/Users\//.test(value) || value.startsWith("~/") || value.startsWith("file://") || /^[A-Z]:\\/.test(value))) {
    fail(`${label} must not contain a local path`);
  }
}

const manifestPath = "docs/ui/rendered-geometry.manifest.json";
const manifest = readJson(manifestPath);
const decisionVerificationPath = "docs/ui/decision-verification.json";
const decisionVerification = readJson(decisionVerificationPath);
const alignmentValidationDecision = (decisionVerification?.decisions || []).find((decision) => decision?.id === "alignment_validation");
if (manifest) {
  if (args.has("--simulate-inactive-rendered-geometry")) {
    manifest.status = "active";
  }
  if (args.has("--simulate-wrong-private-alias")) {
    manifest.externalGeometryAlias = "external-ui-baselines";
  }
  if (args.has("--simulate-wrong-evidence-filename")) {
    manifest.evidenceFilename = "geometry-evidence.txt";
  }
  if (args.has("--simulate-verifier-without-approval")) {
    manifest.verificationCommand = "CLAWIX_UI_PRIVATE_GEOMETRY_ROOT=<private-root> node scripts/ui_private_geometry_verify.mjs";
  }
  if (args.has("--simulate-missing-pattern-evidence-field") && Array.isArray(manifest.requiredEvidenceFields)) {
    manifest.requiredEvidenceFields = manifest.requiredEvidenceFields.filter((field) => field !== "screenshotComparisonHash");
  }
  if (args.has("--simulate-extra-pattern-evidence-field") && Array.isArray(manifest.requiredEvidenceFields)) {
    manifest.requiredEvidenceFields.push("localGeometryPath");
  }
  if (args.has("--simulate-duplicate-pattern-evidence-field") && Array.isArray(manifest.requiredEvidenceFields) && manifest.requiredEvidenceFields[0]) {
    manifest.requiredEvidenceFields.push(manifest.requiredEvidenceFields[0]);
  }
  if (args.has("--simulate-missing-surface-evidence-field") && Array.isArray(manifest.requiredSurfaceEvidenceFields)) {
    manifest.requiredSurfaceEvidenceFields = manifest.requiredSurfaceEvidenceFields.filter((field) => field !== "coverageId");
  }
  if (args.has("--simulate-extra-surface-evidence-field") && Array.isArray(manifest.requiredSurfaceEvidenceFields)) {
    manifest.requiredSurfaceEvidenceFields.push("localGeometryPath");
  }
  if (args.has("--simulate-duplicate-surface-evidence-field") && Array.isArray(manifest.requiredSurfaceEvidenceFields) && manifest.requiredSurfaceEvidenceFields[0]) {
    manifest.requiredSurfaceEvidenceFields.push(manifest.requiredSurfaceEvidenceFields[0]);
  }
  if (args.has("--simulate-extra-public-forbidden-store") && Array.isArray(manifest.publicRepoMustNotStore)) {
    manifest.publicRepoMustNotStore.push("temporary-screenshot");
  }
  if (args.has("--simulate-duplicate-public-forbidden-store") && Array.isArray(manifest.publicRepoMustNotStore) && manifest.publicRepoMustNotStore[0]) {
    manifest.publicRepoMustNotStore.push(manifest.publicRepoMustNotStore[0]);
  }
  if (args.has("--simulate-local-path-reference")) {
    manifest.patternSource = "/Users/example/patterns.registry.json";
  }
  if (args.has("--simulate-alignment-decision-missing-rendered-geometry") && alignmentValidationDecision) {
    alignmentValidationDecision.publicEvidence = alignmentValidationDecision.publicEvidence.filter((evidencePath) => evidencePath !== manifestPath);
  }
  if (args.has("--simulate-alignment-decision-missing-private-visual") && alignmentValidationDecision) {
    alignmentValidationDecision.publicEvidence = alignmentValidationDecision.publicEvidence.filter(
      (evidencePath) =>
        evidencePath !== "docs/ui/private-visual-validation.manifest.json" &&
        evidencePath !== "scripts/ui_private_visual_verify.mjs",
    );
    alignmentValidationDecision.blockingVerifiers = alignmentValidationDecision.blockingVerifiers.filter(
      (verifier) => verifier !== "scripts/ui_private_visual_verify.mjs",
    );
  }
  if (args.has("--simulate-alignment-decision-missing-private-geometry-verifier") && alignmentValidationDecision) {
    alignmentValidationDecision.publicEvidence = alignmentValidationDecision.publicEvidence.filter(
      (evidencePath) => evidencePath !== "scripts/ui_private_geometry_verify.mjs",
    );
    alignmentValidationDecision.blockingVerifiers = alignmentValidationDecision.blockingVerifiers.filter(
      (verifier) => verifier !== "scripts/ui_private_geometry_verify.mjs",
    );
  }
  if (args.has("--simulate-alignment-decision-missing-baseline-verifier") && alignmentValidationDecision) {
    alignmentValidationDecision.publicEvidence = alignmentValidationDecision.publicEvidence.filter(
      (evidencePath) => evidencePath !== "scripts/ui_private_baseline_verify.mjs",
    );
    alignmentValidationDecision.blockingVerifiers = alignmentValidationDecision.blockingVerifiers.filter(
      (verifier) => verifier !== "scripts/ui_private_baseline_verify.mjs",
    );
  }
  if (args.has("--simulate-alignment-decision-missing-platform-evidence") && alignmentValidationDecision) {
    alignmentValidationDecision.externalEvidence = alignmentValidationDecision.externalEvidence.filter(
      (evidenceReference) => evidenceReference !== "external-ui-rendered-geometry:web/*",
    );
  }
  if (args.has("--simulate-alignment-decision-premature-complete") && alignmentValidationDecision) {
    alignmentValidationDecision.status = "verified-complete";
    alignmentValidationDecision.remaining = [];
  }
  if (args.has("--simulate-approved-geometry-stale-decision") && manifest && alignmentValidationDecision) {
    manifest.status = "approved-private-geometry";
    alignmentValidationDecision.status = "open";
    alignmentValidationDecision.remaining = ["Simulated stale decision after approved private rendered geometry."];
  }
}
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "patternSource",
  "externalGeometryAlias",
  "evidenceFilename",
  "surfaceEvidenceFilename",
  "verificationCommand",
  "requiredEvidenceFields",
  "requiredSurfaceEvidenceFields",
  "publicRepoMustNotStore",
]);

if (!["pending-private-capture", "approved-private-geometry"].includes(manifest?.status)) {
  fail(`${manifestPath}.status must be pending-private-capture or approved-private-geometry`);
}
if (manifest?.externalGeometryAlias !== "external-ui-rendered-geometry") {
  fail(`${manifestPath}.externalGeometryAlias must be external-ui-rendered-geometry`);
}
if (manifest?.evidenceFilename !== "geometry-evidence.json") {
  fail(`${manifestPath}.evidenceFilename must be geometry-evidence.json`);
}
if (manifest?.surfaceEvidenceFilename !== "surface-geometry.json") {
  fail(`${manifestPath}.surfaceEvidenceFilename must be surface-geometry.json`);
}
if (!String(manifest?.verificationCommand || "").includes("scripts/ui_private_geometry_verify.mjs")) {
  fail(`${manifestPath}.verificationCommand must run scripts/ui_private_geometry_verify.mjs`);
}
if (!String(manifest?.verificationCommand || "").includes("--require-approved")) {
  fail(`${manifestPath}.verificationCommand must require approved private geometry evidence`);
}

requireExactStringSet(
  requireArray(manifest, manifestPath, "requiredEvidenceFields"),
  `${manifestPath}.requiredEvidenceFields`,
  ["patternId", "platform", "geometryEvidenceReference", "measurements", "geometryHash", "screenshotComparisonHash", "captureCommand", "approvedByUserAt", "approvedScope"],
);
requireExactStringSet(
  requireArray(manifest, manifestPath, "requiredSurfaceEvidenceFields"),
  `${manifestPath}.requiredSurfaceEvidenceFields`,
  ["coverageId", "platform", "geometryEvidenceReference", "measurements", "geometryHash", "screenshotComparisonHash", "captureCommand", "approvedByUserAt", "approvedScope"],
);
requireExactStringSet(
  requireArray(manifest, manifestPath, "publicRepoMustNotStore"),
  `${manifestPath}.publicRepoMustNotStore`,
  ["raw-geometry-dump", "raw-screenshot", "local-absolute-path", "secret", "signing-identity"],
);

const registry = readJson(manifest?.patternSource || "");
requireArray(registry, manifest?.patternSource || "patternSource", "patterns");
scanForLocalPaths(manifest, manifestPath);

const externalGeometryAlias = manifest?.externalGeometryAlias || "external-ui-rendered-geometry";
if (!alignmentValidationDecision) {
  fail(`${decisionVerificationPath}.decisions must include alignment_validation`);
} else {
  const publicEvidence = new Set(Array.isArray(alignmentValidationDecision.publicEvidence) ? alignmentValidationDecision.publicEvidence : []);
  for (const evidencePath of [
    "docs/ui/interface-governance.config.json",
    manifestPath,
    "docs/ui/private-visual-validation.manifest.json",
    "scripts/ui_geometry_contract_check.mjs",
    "scripts/ui_rendered_geometry_manifest_check.mjs",
    "scripts/ui_private_evidence_plan_check.mjs",
    "scripts/ui_private_evidence_verify.mjs",
    "scripts/ui_private_visual_verify.mjs",
    "scripts/ui_private_geometry_verify.mjs",
    "scripts/ui_private_baseline_verify.mjs",
  ]) {
    if (!publicEvidence.has(evidencePath)) {
      fail(`${decisionVerificationPath}.decisions.alignment_validation.publicEvidence must include ${evidencePath}`);
    }
  }
  const externalEvidence = new Set(Array.isArray(alignmentValidationDecision.externalEvidence) ? alignmentValidationDecision.externalEvidence : []);
  for (const evidenceReference of [
    `${externalGeometryAlias}:surfaces/*`,
    `${externalGeometryAlias}:macos/*`,
    `${externalGeometryAlias}:ios/*`,
    `${externalGeometryAlias}:android/*`,
    `${externalGeometryAlias}:web/*`,
    "external-ui-baselines:surfaces/*",
  ]) {
    if (!externalEvidence.has(evidenceReference)) {
      fail(`${decisionVerificationPath}.decisions.alignment_validation.externalEvidence must include ${evidenceReference}`);
    }
  }
  const blockingVerifiers = new Set(Array.isArray(alignmentValidationDecision.blockingVerifiers) ? alignmentValidationDecision.blockingVerifiers : []);
  for (const verifier of [
    "scripts/ui_private_geometry_verify.mjs",
    "scripts/ui_private_baseline_verify.mjs",
    "scripts/ui_private_evidence_verify.mjs",
    "scripts/ui_private_visual_verify.mjs",
  ]) {
    if (!blockingVerifiers.has(verifier)) {
      fail(`${decisionVerificationPath}.decisions.alignment_validation.blockingVerifiers must include ${verifier}`);
    }
  }
  if (manifest?.status !== "approved-private-geometry" && !["open", "blocked-external-pending"].includes(alignmentValidationDecision.status)) {
    fail(`${decisionVerificationPath}.decisions.alignment_validation.status must remain open or blocked-external-pending until private rendered geometry and baseline evidence are approved`);
  }
  if (manifest?.status !== "approved-private-geometry" && (!Array.isArray(alignmentValidationDecision.remaining) || alignmentValidationDecision.remaining.length === 0)) {
    fail(`${decisionVerificationPath}.decisions.alignment_validation.remaining must describe pending private rendered geometry and screenshot comparison evidence`);
  }
  if (manifest?.status === "approved-private-geometry" && alignmentValidationDecision.status !== "verified-complete") {
    fail(`${decisionVerificationPath}.decisions.alignment_validation.status must be verified-complete after private rendered geometry and baseline evidence are approved`);
  }
  if (manifest?.status === "approved-private-geometry" && Array.isArray(alignmentValidationDecision.remaining) && alignmentValidationDecision.remaining.length > 0) {
    fail(`${decisionVerificationPath}.decisions.alignment_validation.remaining must be empty after private rendered geometry and baseline evidence are approved`);
  }
}

if (errors.length > 0) {
  console.error("UI rendered geometry manifest check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

if (!isSelfTest && rawArgs.length === 0) {
  const selfTests = [
    ["--unknown-flag", "received unknown flag --unknown-flag"],
    ["--simulate-wrong-private-alias", "externalGeometryAlias must be external-ui-rendered-geometry"],
    ["--simulate-verifier-without-approval", "verificationCommand must require approved private geometry evidence"],
    ["--simulate-local-path-reference", "must not contain a local path"],
    ["--simulate-alignment-decision-missing-private-geometry-verifier", "publicEvidence must include scripts/ui_private_geometry_verify.mjs"],
    ["--simulate-alignment-decision-premature-complete", "status must remain open or blocked-external-pending until private rendered geometry and baseline evidence are approved"],
    ["--simulate-approved-geometry-stale-decision", "status must be verified-complete after private rendered geometry and baseline evidence are approved"],
  ];
  const scriptPath = path.relative(rootDir, new URL(import.meta.url).pathname);
  for (const [flag, expectedOutput] of selfTests) {
    const result = spawnSync(process.execPath, [scriptPath, flag], {
      cwd: rootDir,
      encoding: "utf8",
      env: { ...process.env, CLAWIX_UI_RENDERED_GEOMETRY_MANIFEST_SELF_TEST: "1" },
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status === 0 || !output.includes(expectedOutput)) {
      console.error(`UI rendered geometry manifest self-test failed for ${flag}.`);
      if (output) console.error(output.trim());
      process.exit(1);
    }
  }
}

console.log("UI rendered geometry manifest check passed");
