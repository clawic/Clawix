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
const copyKinds = new Set(requireArray(copyInventory, copyPath, "restrictedCopyKinds"));
if (args.has("--simulate-missing-copy-kind")) {
  copyKinds.delete("tooltip");
}
for (const kind of requiredCopyKinds) {
  if (!copyKinds.has(kind)) fail(`${copyPath}.restrictedCopyKinds must include ${kind}`);
}

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
const evidence = new Set(requireArray(copyInventory, copyPath, "requiredEvidenceFields"));
if (args.has("--simulate-missing-required-evidence")) {
  evidence.delete("copyHierarchyHash");
}
for (const field of requiredEvidence) {
  if (!evidence.has(field)) fail(`${copyPath}.requiredEvidenceFields must include ${field}`);
}

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
for (const [index, entry] of requireArray(surfaceCoverage, surfaceCoveragePath, "coverage").entries()) {
  const label = `${surfaceCoveragePath}.coverage[${index}]`;
  requireFields(entry, label, ["coverageId", "platform", "copySnapshotReference", "requiredEvidence"]);
  const copySnapshotSuffix = requirePublicSafeReference(entry.copySnapshotReference, privateAlias, `${label}.copySnapshotReference`);
  const expectedCopySnapshotSuffix = `surfaces/${entry.platform}/${entry.coverageId}`;
  if (copySnapshotSuffix && copySnapshotSuffix !== expectedCopySnapshotSuffix) {
    fail(`${label}.copySnapshotReference must target ${expectedCopySnapshotSuffix}`);
  }
  const coverageEvidence = new Set(requireArray(entry, label, "requiredEvidence"));
  if (!coverageEvidence.has("copySnapshotHash")) fail(`${label}.requiredEvidence must include copySnapshotHash`);
}
for (const [index, surface] of requireArray(protectedSurfaces, protectedPath, "surfaces", { nonEmpty: false }).entries()) {
  const label = `${protectedPath}.surfaces[${index}]`;
  requireFields(surface, label, ["copySnapshotReference", "copySnapshotHash"]);
  requirePublicSafeReference(surface.copySnapshotReference, privateAlias, `${label}.copySnapshotReference`);
  if (typeof surface.copySnapshotHash !== "string" || surface.copySnapshotHash.length < 16) {
    fail(`${label}.copySnapshotHash must record the approved private copy snapshot hash`);
  }
}

if (errors.length > 0) {
  console.error("UI copy governance check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI copy governance check passed (${patternIds.length} pattern copy contracts)`);
