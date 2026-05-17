#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = new Set(process.argv.slice(2));
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

function requireUniqueStrings(values, label) {
  const seen = new Set();
  for (const value of values) {
    if (typeof value !== "string" || value.length === 0) {
      fail(`${label} must only include non-empty strings`);
      continue;
    }
    if (seen.has(value)) fail(`${label} duplicates ${value}`);
    seen.add(value);
  }
  return seen;
}

function requireExactStringSet(values, label, expectedValues) {
  const seen = requireUniqueStrings(values, label);
  const expected = new Set(expectedValues);
  for (const value of seen) {
    if (!expected.has(value)) fail(`${label} must not include ${value}`);
  }
  for (const value of expected) {
    if (!seen.has(value)) fail(`${label} must include ${value}`);
  }
  if (seen.size !== expected.size) fail(`${label} must exactly match approved values`);
  return seen;
}

function requireRepoReference(reference, label) {
  if (typeof reference !== "string" || reference.length === 0) {
    fail(`${label} must be a repo-relative reference`);
    return;
  }
  if (path.isAbsolute(reference) || reference.startsWith("~/") || reference.includes("\\") || reference.includes("/Users/") || reference.includes(":")) {
    fail(`${label} must be public-safe and repo-relative`);
    return;
  }
  if (!fs.existsSync(path.join(rootDir, reference.split("#", 1)[0]))) {
    fail(`${label} points to missing target ${reference}`);
  }
}

const manifestPath = "docs/ui/implementation-phases.manifest.json";
const manifest = readJson(manifestPath);
if (manifest) {
  if (args.has("--simulate-inactive-manifest")) {
    manifest.status = "draft";
  }
  if (args.has("--simulate-missing-allowed-action") && Array.isArray(manifest.nonAuthorizedAllowedActions)) {
    manifest.nonAuthorizedAllowedActions = manifest.nonAuthorizedAllowedActions.filter((action) => action !== "conceptual-proposal");
  }
  if (args.has("--simulate-extra-allowed-action") && Array.isArray(manifest.nonAuthorizedAllowedActions)) {
    manifest.nonAuthorizedAllowedActions.push("style-token-edit");
  }
  if (args.has("--simulate-duplicate-allowed-action") && Array.isArray(manifest.nonAuthorizedAllowedActions) && manifest.nonAuthorizedAllowedActions[0]) {
    manifest.nonAuthorizedAllowedActions.push(manifest.nonAuthorizedAllowedActions[0]);
  }
  if (args.has("--simulate-missing-forbidden-action") && Array.isArray(manifest.nonAuthorizedForbiddenActions)) {
    manifest.nonAuthorizedForbiddenActions = manifest.nonAuthorizedForbiddenActions.filter((action) => action !== "visual-ui");
  }
  if (args.has("--simulate-extra-forbidden-action") && Array.isArray(manifest.nonAuthorizedForbiddenActions)) {
    manifest.nonAuthorizedForbiddenActions.push("private-evidence-wiring");
  }
  if (args.has("--simulate-duplicate-forbidden-action") && Array.isArray(manifest.nonAuthorizedForbiddenActions) && manifest.nonAuthorizedForbiddenActions[0]) {
    manifest.nonAuthorizedForbiddenActions.push(manifest.nonAuthorizedForbiddenActions[0]);
  }
  if (args.has("--simulate-unknown-phase") && Array.isArray(manifest.phases) && manifest.phases[0]) {
    manifest.phases[0] = { ...manifest.phases[0], id: "visual-cleanup-now" };
  }
  if (args.has("--simulate-wrong-foundation-status") && Array.isArray(manifest.phases) && manifest.phases[0]) {
    manifest.phases[0] = { ...manifest.phases[0], status: "external-pending" };
  }
  if (args.has("--simulate-duplicate-phase") && Array.isArray(manifest.phases) && manifest.phases[0]) {
    manifest.phases.push({ ...manifest.phases[0] });
  }
  if (args.has("--simulate-missing-private-evidence-phase") && Array.isArray(manifest.phases)) {
    manifest.phases = manifest.phases.filter((phase) => phase.id !== "private-evidence-capture");
  }
  if (args.has("--simulate-unsafe-evidence-reference") && Array.isArray(manifest.phases) && manifest.phases[0]) {
    manifest.phases[0] = {
      ...manifest.phases[0],
      evidence: ["/Users/private/ui-evidence.json", ...(manifest.phases[0].evidence || [])],
    };
  }
  if (args.has("--simulate-missing-phase-evidence") && Array.isArray(manifest.phases) && manifest.phases[0]) {
    manifest.phases[0] = { ...manifest.phases[0], evidence: [] };
  }
  if (args.has("--simulate-duplicate-phase-evidence") && Array.isArray(manifest.phases)) {
    const phase = manifest.phases.find((candidate) => Array.isArray(candidate?.evidence) && candidate.evidence[0]);
    if (phase) phase.evidence.push(phase.evidence[0]);
  }
}
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "nonAuthorizedAllowedActions",
  "nonAuthorizedForbiddenActions",
  "phases",
]);

if (manifest?.status !== "active") fail(`${manifestPath}.status must be active`);
requireExactStringSet(
  requireArray(manifest, manifestPath, "nonAuthorizedAllowedActions"),
  `${manifestPath}.nonAuthorizedAllowedActions`,
  ["governance-manifest", "public-check", "private-verifier", "evidence-wiring", "conceptual-proposal"],
);
requireExactStringSet(
  requireArray(manifest, manifestPath, "nonAuthorizedForbiddenActions"),
  `${manifestPath}.nonAuthorizedForbiddenActions`,
  ["visual-ui", "copy-ui", "layout-change", "style-token-change", "critical-cleanup-execution"],
);

const expectedPhases = new Map([
  ["public-governance-foundation", "complete"],
  ["private-evidence-capture", "external-pending"],
  ["visual-cleanup-execution", "blocked-without-allowlisted-visual-lane"],
]);
const seen = new Set();
for (const [index, phase] of requireArray(manifest, manifestPath, "phases").entries()) {
  const label = `${manifestPath}.phases[${index}]`;
  requireFields(phase, label, ["id", "status", "evidence"]);
  if (!expectedPhases.has(phase.id)) fail(`${label}.id is not a required implementation phase`);
  if (expectedPhases.get(phase.id) !== phase.status) fail(`${label}.status must be ${expectedPhases.get(phase.id)}`);
  if (seen.has(phase.id)) fail(`${label}.id duplicates ${phase.id}`);
  seen.add(phase.id);
  const evidenceEntries = requireArray(phase, label, "evidence");
  requireUniqueStrings(evidenceEntries, `${label}.evidence`);
  for (const [evidenceIndex, evidence] of evidenceEntries.entries()) {
    requireRepoReference(evidence, `${label}.evidence[${evidenceIndex}]`);
  }
}
for (const phaseId of expectedPhases.keys()) {
  if (!seen.has(phaseId)) fail(`${manifestPath}.phases must include ${phaseId}`);
}

if (errors.length > 0) {
  console.error("UI implementation phase check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI implementation phase check passed (${seen.size} phases)`);
