#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const today = new Date().toISOString().slice(0, 10);
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
  if (nonEmpty && value.length === 0) {
    fail(`${label}.${field} must not be empty`);
  }
  return value;
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
    args.has("--simulate-duplicate-scope-id"))
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
if (manifest && args.has("--simulate-missing-required-change-kind") && Array.isArray(manifest.requiredChangeKinds)) {
  manifest.requiredChangeKinds = manifest.requiredChangeKinds.filter((kind) => kind !== "typography");
}
if (manifest && args.has("--simulate-missing-required-approval-field") && Array.isArray(manifest.requiredApprovalFields)) {
  manifest.requiredApprovalFields = manifest.requiredApprovalFields.filter((field) => field !== "changeKinds");
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

const allowedStatuses = new Set(requireArray(manifest, manifestPath, "scopeStatuses"));
for (const status of ["proposed", "approved", "expired", "revoked"]) {
  if (!allowedStatuses.has(status)) fail(`${manifestPath}.scopeStatuses must include ${status}`);
}

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
const requiredApprovalFieldSet = new Set(requiredApprovalFields);
for (const field of [
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
]) {
  if (!requiredApprovalFieldSet.has(field)) fail(`${manifestPath}.requiredApprovalFields must include ${field}`);
}

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
  for (const platform of requireArray(scope, label, "platforms")) {
    if (!requiredPlatforms.has(platform)) fail(`${label}.platforms contains unsupported ${platform}`);
  }
  for (const surface of requireArray(scope, label, "surfaces")) {
    if (!inventorySurfaceIds.has(surface)) fail(`${label}.surfaces references unknown visible surface ${surface}`);
  }
  for (const pattern of requireArray(scope, label, "patterns")) {
    if (!patternIds.has(pattern)) fail(`${label}.patterns references unknown pattern ${pattern}`);
  }
  for (const kind of requireArray(scope, label, "changeKinds")) {
    if (!requiredChangeKinds.has(kind)) fail(`${label}.changeKinds contains unsupported ${kind}`);
  }
  for (const file of requireArray(scope, label, "files")) {
    if (typeof file !== "string" || file.startsWith("/") || file.includes("..")) {
      fail(`${label}.files entries must be public repo relative paths`);
    }
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
