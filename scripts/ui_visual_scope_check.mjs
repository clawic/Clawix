#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const today = new Date().toISOString().slice(0, 10);
const rawArgs = process.argv.slice(2);
const args = new Set(rawArgs);
const isSelfTest = process.env.CLAWIX_UI_VISUAL_SCOPE_SELF_TEST === "1";
const errors = [];
const simulationFlags = [
  "--simulate-expired-approved-scope",
  "--simulate-unsupported-platform",
  "--simulate-uncovered-change-budget",
  "--simulate-duplicate-scope-id",
  "--simulate-duplicate-scope-platform",
  "--simulate-duplicate-scope-surface",
  "--simulate-duplicate-scope-pattern",
  "--simulate-duplicate-scope-change-kind",
  "--simulate-duplicate-scope-file",
  "--simulate-inactive-scope-manifest",
  "--simulate-extra-scope-status",
  "--simulate-duplicate-scope-status",
  "--simulate-missing-required-change-kind",
  "--simulate-missing-required-approval-field",
  "--simulate-extra-required-approval-field",
  "--simulate-duplicate-required-approval-field",
];
const allowedFlags = new Set(simulationFlags);

function fail(message) {
  errors.push(message);
}

for (const arg of rawArgs) {
  if (arg.startsWith("--") && !allowedFlags.has(arg)) {
    console.error(`UI visual scope check received unknown flag ${arg}.`);
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
  if (nonEmpty && value.length === 0) {
    fail(`${label}.${field} must not be empty`);
  }
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

function hasLocalPath(value) {
  return (
    typeof value === "string" &&
    (/^\/Users\//.test(value) || value.startsWith("~/") || value.startsWith("file://") || /^[A-Z]:\\/.test(value))
  );
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
  if (hasLocalPath(value)) fail(`${label} must not contain a local path`);
}

function requireSafePrivateReference(value, alias, label) {
  if (typeof value !== "string" || !value.startsWith(`${alias}:`)) {
    fail(`${label} must use ${alias}:`);
    return;
  }
  const suffix = value.slice(alias.length + 1);
  if (!suffix || suffix.startsWith("/") || suffix.startsWith("\\") || suffix.startsWith("~/") || suffix.includes("..") || /^[A-Z]:\\/.test(suffix)) {
    fail(`${label} must use a safe relative private reference`);
  }
  if (hasLocalPath(value) || value.includes("/Users/")) {
    fail(`${label} must not contain a local path`);
  }
}

function requireIsoDate(value, label) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value) || Number.isNaN(Date.parse(value))) {
    fail(`${label} must be an ISO date`);
  }
}

function requireExistingRepoFile(reference, label) {
  if (typeof reference !== "string" || reference.startsWith("/") || reference.includes("..") || reference.includes("\\") || reference.includes(":")) {
    fail(`${label} must be a public repo relative path`);
    return;
  }
  if (!fs.existsSync(path.join(rootDir, reference))) {
    fail(`${label} points to missing target ${reference}`);
  }
}

function runFailureSelfTests() {
  const selfTestEnv = {
    ...process.env,
    CLAWIX_UI_VISUAL_SCOPE_SELF_TEST: "1",
  };
  const tests = [
    [["--unknown-flag"], "received unknown flag --unknown-flag"],
    [["--simulate-expired-approved-scope"], "approved scope expired on 2026-01-01"],
    [["--simulate-unsupported-platform"], "platforms contains unsupported visionos"],
    [["--simulate-uncovered-change-budget"], "changeBudget.allowedChangeKinds must cover scope change kind spacing"],
    [["--simulate-duplicate-scope-id"], "id duplicates simulated-scope"],
    [["--simulate-duplicate-scope-platform"], "platforms duplicates macos"],
    [["--simulate-duplicate-scope-surface"], "surfaces duplicates"],
    [["--simulate-duplicate-scope-pattern"], "patterns duplicates"],
    [["--simulate-duplicate-scope-change-kind"], "changeKinds duplicates color"],
    [["--simulate-duplicate-scope-file"], "files duplicates macos/Sources/Clawix/SidebarView.swift"],
    [["--simulate-inactive-scope-manifest"], "status must be active"],
    [["--simulate-extra-scope-status"], "scopeStatuses must not include pending-review"],
    [["--simulate-duplicate-scope-status"], "scopeStatuses duplicates proposed"],
    [["--simulate-missing-required-change-kind"], "requiredChangeKinds must include typography"],
    [["--simulate-missing-required-approval-field"], "requiredApprovalFields must include changeKinds"],
    [["--simulate-extra-required-approval-field"], "requiredApprovalFields must not include screenshotPath"],
    [["--simulate-duplicate-required-approval-field"], "requiredApprovalFields duplicates id"],
  ];

  for (const [testArgs, expectedOutput] of tests) {
    const result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, ...testArgs], {
      cwd: rootDir,
      env: selfTestEnv,
      encoding: "utf8",
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status === 0) {
      fail(`self-test ${testArgs.join(" ")} must fail for UI visual scope validation`);
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

const configPath = "docs/ui/interface-governance.config.json";
const config = readJson(configPath);
const requiredPlatforms = new Set(requireArray(config, configPath, "platforms"));
const requiredChangeKinds = new Set(requireArray(config, configPath, "restrictedChangeKinds"));

const manifestPath = "docs/ui/visual-change-scopes.manifest.json";
const manifest = readJson(manifestPath);
const inventoryPath = "docs/ui/visible-surfaces.inventory.json";
const inventory = readJson(inventoryPath);
const patternRegistryPath = "docs/ui/pattern-registry/patterns.registry.json";
const patternRegistry = readJson(patternRegistryPath);
const inventorySurfaceIds = new Set(requireArray(inventory, inventoryPath, "coverage").map((entry) => entry?.id).filter(Boolean));
const patternIds = new Set(requireArray(patternRegistry, patternRegistryPath, "patterns"));
if (
  manifest &&
  (args.has("--simulate-expired-approved-scope") ||
    args.has("--simulate-unsupported-platform") ||
    args.has("--simulate-uncovered-change-budget") ||
    args.has("--simulate-duplicate-scope-id") ||
    args.has("--simulate-duplicate-scope-platform") ||
    args.has("--simulate-duplicate-scope-surface") ||
    args.has("--simulate-duplicate-scope-pattern") ||
    args.has("--simulate-duplicate-scope-change-kind") ||
    args.has("--simulate-duplicate-scope-file"))
) {
  const [surfaceId] = inventorySurfaceIds;
  const [patternId] = patternIds;
  const simulatedScope = {
    id: "simulated-scope",
    status: "approved",
    platforms: args.has("--simulate-unsupported-platform") ? ["visionos"] : ["macos"],
    surfaces: [surfaceId],
    patterns: [patternId],
    files: ["macos/Sources/Clawix/SidebarView.swift"],
    changeKinds: args.has("--simulate-uncovered-change-budget") ? ["color", "spacing"] : ["color"],
    changeBudget: {
      maxFiles: 1,
      maxLines: 10,
      allowedChangeKinds: ["color"],
    },
    approvedBy: "user",
    approvedAt: "2026-05-15",
    expiresAt: args.has("--simulate-expired-approved-scope") ? "2026-01-01" : "2999-12-31",
    privateApprovalReference: "private-codex-ui-approval:scopes/simulated-scope",
  };
  manifest.activeScopes = [...(manifest.activeScopes || []), simulatedScope];
  if (args.has("--simulate-duplicate-scope-id")) {
    manifest.activeScopes.push({ ...simulatedScope });
  }
}
if (manifest && args.has("--simulate-inactive-scope-manifest")) {
  manifest.status = "draft";
}
if (manifest && args.has("--simulate-extra-scope-status") && Array.isArray(manifest.scopeStatuses)) {
  manifest.scopeStatuses.push("pending-review");
}
if (manifest && args.has("--simulate-duplicate-scope-status") && Array.isArray(manifest.scopeStatuses) && manifest.scopeStatuses[0]) {
  manifest.scopeStatuses.push(manifest.scopeStatuses[0]);
}
if (manifest && args.has("--simulate-missing-required-change-kind") && Array.isArray(manifest.requiredChangeKinds)) {
  manifest.requiredChangeKinds = manifest.requiredChangeKinds.filter((kind) => kind !== "typography");
}
if (manifest && args.has("--simulate-missing-required-approval-field") && Array.isArray(manifest.requiredApprovalFields)) {
  manifest.requiredApprovalFields = manifest.requiredApprovalFields.filter((field) => field !== "changeKinds");
}
if (manifest && args.has("--simulate-extra-required-approval-field") && Array.isArray(manifest.requiredApprovalFields)) {
  manifest.requiredApprovalFields.push("screenshotPath");
}
if (manifest && args.has("--simulate-duplicate-required-approval-field") && Array.isArray(manifest.requiredApprovalFields) && manifest.requiredApprovalFields[0]) {
  manifest.requiredApprovalFields.push(manifest.requiredApprovalFields[0]);
}
if (manifest && args.has("--simulate-duplicate-scope-platform") && Array.isArray(manifest.activeScopes)) {
  const scope = manifest.activeScopes.find((candidate) => Array.isArray(candidate?.platforms) && candidate.platforms[0]);
  if (scope) scope.platforms.push(scope.platforms[0]);
}
if (manifest && args.has("--simulate-duplicate-scope-surface") && Array.isArray(manifest.activeScopes)) {
  const scope = manifest.activeScopes.find((candidate) => Array.isArray(candidate?.surfaces) && candidate.surfaces[0]);
  if (scope) scope.surfaces.push(scope.surfaces[0]);
}
if (manifest && args.has("--simulate-duplicate-scope-pattern") && Array.isArray(manifest.activeScopes)) {
  const scope = manifest.activeScopes.find((candidate) => Array.isArray(candidate?.patterns) && candidate.patterns[0]);
  if (scope) scope.patterns.push(scope.patterns[0]);
}
if (manifest && args.has("--simulate-duplicate-scope-change-kind") && Array.isArray(manifest.activeScopes)) {
  const scope =
    manifest.activeScopes.find((candidate) => candidate?.id === "simulated-scope" && Array.isArray(candidate?.changeKinds) && candidate.changeKinds[0]) ??
    manifest.activeScopes.find((candidate) => Array.isArray(candidate?.changeKinds) && candidate.changeKinds[0]);
  if (scope) scope.changeKinds.push(scope.changeKinds[0]);
}
if (manifest && args.has("--simulate-duplicate-scope-file") && Array.isArray(manifest.activeScopes)) {
  const scope =
    manifest.activeScopes.find((candidate) => candidate?.id === "simulated-scope" && Array.isArray(candidate?.files) && candidate.files[0]) ??
    manifest.activeScopes.find((candidate) => Array.isArray(candidate?.files) && candidate.files[0]);
  if (scope) scope.files.push(scope.files[0]);
}
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "privateModelAssignment",
  "defaultAuthorized",
  "scopeSignal",
  "scopeStatuses",
  "requiredChangeKinds",
  "requiredApprovalFields",
  "activeScopes",
]);
if (manifest?.status !== "active") fail(`${manifestPath}.status must be active`);
if (manifest?.defaultAuthorized !== false) {
  fail(`${manifestPath}.defaultAuthorized must be false`);
}
if (manifest?.privateModelAssignment !== "outside-public-repo") {
  fail(`${manifestPath}.privateModelAssignment must stay outside-public-repo`);
}
requireFields(manifest?.scopeSignal, `${manifestPath}.scopeSignal`, ["env", "requiredForVisualMutation"]);
if (manifest?.scopeSignal?.env !== "CLAWIX_UI_VISUAL_SCOPE_ID") {
  fail(`${manifestPath}.scopeSignal.env must be CLAWIX_UI_VISUAL_SCOPE_ID`);
}
if (manifest?.scopeSignal?.requiredForVisualMutation !== true) {
  fail(`${manifestPath}.scopeSignal.requiredForVisualMutation must be true`);
}

const allowedStatuses = requireExactStringSet(
  requireArray(manifest, manifestPath, "scopeStatuses"),
  `${manifestPath}.scopeStatuses`,
  ["proposed", "approved", "expired", "revoked"],
);

const manifestRequiredChangeKinds = new Set(requireArray(manifest, manifestPath, "requiredChangeKinds"));
for (const kind of requiredChangeKinds) {
  if (!manifestRequiredChangeKinds.has(kind)) fail(`${manifestPath}.requiredChangeKinds must include ${kind}`);
}
for (const kind of manifestRequiredChangeKinds) {
  if (!requiredChangeKinds.has(kind)) fail(`${manifestPath}.requiredChangeKinds contains unsupported ${kind}`);
}
if (manifestRequiredChangeKinds.size !== requiredChangeKinds.size || manifest?.requiredChangeKinds?.length !== manifestRequiredChangeKinds.size) {
  fail(`${manifestPath}.requiredChangeKinds must exactly match ${configPath}.restrictedChangeKinds`);
}

const requiredApprovalFields = requireArray(manifest, manifestPath, "requiredApprovalFields");
requireExactStringSet(requiredApprovalFields, `${manifestPath}.requiredApprovalFields`, [
  "id",
  "status",
  "platforms",
  "surfaces",
  "patterns",
  "files",
  "changeKinds",
  "changeBudget",
  "approvedBy",
  "approvedAt",
  "expiresAt",
  "privateApprovalReference",
]);

const scopes = requireArray(manifest, manifestPath, "activeScopes", { nonEmpty: false });
const scopeIds = new Set();
for (const [index, scope] of scopes.entries()) {
  const label = `${manifestPath}.activeScopes[${index}]`;
  requireFields(scope, label, requiredApprovalFields);
  if (scopeIds.has(scope.id)) fail(`${label}.id duplicates ${scope.id}`);
  scopeIds.add(scope.id);
  if (!allowedStatuses.has(scope.status)) fail(`${label}.status is invalid`);
  if (scope.approvedBy !== "user") fail(`${label}.approvedBy must be user`);
  requireIsoDate(scope.approvedAt, `${label}.approvedAt`);
  requireIsoDate(scope.expiresAt, `${label}.expiresAt`);
  if (scope.status === "approved" && scope.expiresAt < today) {
    fail(`${label} approved scope expired on ${scope.expiresAt}`);
  }
  const platforms = requireArray(scope, label, "platforms");
  requireUniqueStrings(platforms, `${label}.platforms`);
  for (const platform of platforms) {
    if (!requiredPlatforms.has(platform)) fail(`${label}.platforms contains unsupported ${platform}`);
  }
  const surfaces = requireArray(scope, label, "surfaces");
  requireUniqueStrings(surfaces, `${label}.surfaces`);
  for (const surface of surfaces) {
    if (!inventorySurfaceIds.has(surface)) fail(`${label}.surfaces references unknown visible surface ${surface}`);
  }
  const patterns = requireArray(scope, label, "patterns");
  requireUniqueStrings(patterns, `${label}.patterns`);
  for (const pattern of patterns) {
    if (!patternIds.has(pattern)) fail(`${label}.patterns references unknown pattern ${pattern}`);
  }
  const changeKinds = requireArray(scope, label, "changeKinds");
  requireUniqueStrings(changeKinds, `${label}.changeKinds`);
  for (const kind of changeKinds) {
    if (!requiredChangeKinds.has(kind)) fail(`${label}.changeKinds contains unsupported ${kind}`);
  }
  const files = requireArray(scope, label, "files");
  requireUniqueStrings(files, `${label}.files`);
  for (const [fileIndex, file] of files.entries()) {
    requireExistingRepoFile(file, `${label}.files[${fileIndex}]`);
  }
  const changeBudget = scope.changeBudget || {};
  requireFields(changeBudget, `${label}.changeBudget`, ["maxFiles", "maxLines", "allowedChangeKinds"]);
  if (!Number.isInteger(changeBudget.maxFiles) || changeBudget.maxFiles < 1) {
    fail(`${label}.changeBudget.maxFiles must be a positive integer`);
  }
  if (!Number.isInteger(changeBudget.maxLines) || changeBudget.maxLines < 1) {
    fail(`${label}.changeBudget.maxLines must be a positive integer`);
  }
  for (const kind of requireArray(changeBudget, `${label}.changeBudget`, "allowedChangeKinds")) {
    if (!requiredChangeKinds.has(kind)) fail(`${label}.changeBudget.allowedChangeKinds contains unsupported ${kind}`);
    if (!scope.changeKinds.includes(kind)) fail(`${label}.changeBudget.allowedChangeKinds must be within scope.changeKinds`);
  }
  const budgetKinds = new Set(changeBudget.allowedChangeKinds || []);
  for (const kind of scope.changeKinds || []) {
    if (!budgetKinds.has(kind)) fail(`${label}.changeBudget.allowedChangeKinds must cover scope change kind ${kind}`);
  }
  requireSafePrivateReference(scope.privateApprovalReference, "private-codex-ui-approval", `${label}.privateApprovalReference`);
}

scanForLocalPaths(manifest, manifestPath);

if (errors.length > 0) {
  console.error("UI visual scope check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI visual scope check passed (${scopes.length} active scopes)`);
