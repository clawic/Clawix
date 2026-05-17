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

const manifestPath = "docs/ui/visual-model-allowlist.manifest.json";
const manifest = readJson(manifestPath);
if (args.has("--simulate-missing-active-initial-model") && Array.isArray(manifest?.allowedVisualModels)) {
  manifest.allowedVisualModels = manifest.allowedVisualModels.map((model) => (
    model?.id === "claude-opus-4.7" ? { ...model, status: "revoked" } : model
  ));
}
if (args.has("--simulate-extra-initial-model") && Array.isArray(manifest?.initialActiveModels)) {
  manifest.initialActiveModels.push("other-visual-model");
}
if (args.has("--simulate-duplicate-initial-model") && Array.isArray(manifest?.initialActiveModels) && manifest.initialActiveModels[0]) {
  manifest.initialActiveModels.push(manifest.initialActiveModels[0]);
}
if (args.has("--simulate-extra-model-status") && Array.isArray(manifest?.modelStatuses)) {
  manifest.modelStatuses.push("pending-review");
}
if (args.has("--simulate-duplicate-model-status") && Array.isArray(manifest?.modelStatuses) && manifest.modelStatuses[0]) {
  manifest.modelStatuses.push(manifest.modelStatuses[0]);
}
if (args.has("--simulate-duplicate-visual-model") && Array.isArray(manifest?.allowedVisualModels) && manifest.allowedVisualModels[0]) {
  manifest.allowedVisualModels.push({ ...manifest.allowedVisualModels[0] });
}
if (args.has("--simulate-duplicate-mutation-class") && Array.isArray(manifest?.allowedVisualModels)) {
  manifest.allowedVisualModels = manifest.allowedVisualModels.map((model) => (
    model?.id === "claude-opus-4.7" && Array.isArray(model.allowedMutationClasses) && model.allowedMutationClasses[0]
      ? { ...model, allowedMutationClasses: [...model.allowedMutationClasses, model.allowedMutationClasses[0]] }
      : model
  ));
}
if (args.has("--simulate-missing-copy-class") && Array.isArray(manifest?.allowedVisualModels)) {
  manifest.allowedVisualModels = manifest.allowedVisualModels.map((model) =>
    model?.id === "claude-opus-4.7"
      ? { ...model, allowedMutationClasses: (model.allowedMutationClasses || []).filter((mutationClass) => mutationClass !== "copy-ui") }
      : model,
  );
}
if (args.has("--simulate-unknown-mutation-class") && Array.isArray(manifest?.allowedVisualModels)) {
  manifest.allowedVisualModels = manifest.allowedVisualModels.map((model) => (
    model?.id === "claude-opus-4.7"
      ? { ...model, allowedMutationClasses: [...(model.allowedMutationClasses || []), "layout-ui"] }
      : model
  ));
}
if (args.has("--simulate-private-approval-not-required") && Array.isArray(manifest?.allowedVisualModels)) {
  manifest.allowedVisualModels = manifest.allowedVisualModels.map((model) => (
    model?.id === "claude-opus-4.7" ? { ...model, privateApprovalRequired: false } : model
  ));
}
if (args.has("--simulate-wrong-scope-source") && Array.isArray(manifest?.allowedVisualModels)) {
  manifest.allowedVisualModels = manifest.allowedVisualModels.map((model) => (
    model?.id === "claude-opus-4.7" ? { ...model, scopeSource: "docs/ui/unknown-scopes.manifest.json" } : model
  ));
}
if (args.has("--simulate-model-signal-not-required")) {
  manifest.modelSignal = { ...manifest.modelSignal, requiredForVisualMutation: false };
}
if (args.has("--simulate-wrong-authorization-signal")) {
  manifest.authorizationSignal = { ...manifest.authorizationSignal, env: "CLAWIX_VISUAL_AUTHORIZED" };
}
if (args.has("--simulate-wrong-model-signal-env")) {
  manifest.modelSignal = { ...manifest.modelSignal, env: "CLAWIX_VISUAL_MODEL" };
}
if (args.has("--simulate-private-assignment-public")) {
  manifest.privateAssignment = "public-repo";
}
if (args.has("--simulate-inactive-manifest")) {
  manifest.status = "draft";
}
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "privateAssignment",
  "authorizationSignal",
  "modelSignal",
  "proposalPath",
  "privateApprovalAlias",
  "modelStatuses",
  "initialActiveModels",
  "additionalActiveModelPolicy",
  "allowedVisualModels",
]);

if (manifest?.status !== "active") fail(`${manifestPath}.status must be active`);
if (manifest?.privateAssignment !== "outside-public-repo") {
  fail(`${manifestPath}.privateAssignment must stay outside-public-repo`);
}
requireFields(manifest?.authorizationSignal, `${manifestPath}.authorizationSignal`, ["env", "value"]);
if (manifest?.authorizationSignal?.env !== "CLAWIX_UI_VISUAL_AUTHORIZED") {
  fail(`${manifestPath}.authorizationSignal.env must be CLAWIX_UI_VISUAL_AUTHORIZED`);
}
if (manifest?.authorizationSignal?.value !== "1") {
  fail(`${manifestPath}.authorizationSignal.value must be 1`);
}
requireFields(manifest?.modelSignal, `${manifestPath}.modelSignal`, ["env", "requiredForVisualMutation"]);
if (manifest?.modelSignal?.env !== "CLAWIX_UI_VISUAL_MODEL") {
  fail(`${manifestPath}.modelSignal.env must be CLAWIX_UI_VISUAL_MODEL`);
}
if (manifest?.modelSignal?.requiredForVisualMutation !== true) {
  fail(`${manifestPath}.modelSignal.requiredForVisualMutation must be true`);
}
if (manifest?.proposalPath !== "docs/ui/visual-change-proposal.template.md") {
  fail(`${manifestPath}.proposalPath must point to docs/ui/visual-change-proposal.template.md`);
}
const approvalAuthority = readJson("docs/ui/approval-authority.manifest.json");
if (manifest?.privateApprovalAlias !== approvalAuthority?.privateApprovalAlias) {
  fail(`${manifestPath}.privateApprovalAlias must match docs/ui/approval-authority.manifest.json.privateApprovalAlias`);
}
requireFields(manifest?.additionalActiveModelPolicy, `${manifestPath}.additionalActiveModelPolicy`, [
  "requiresExplicitUserApproval",
  "privateApprovalReferenceRequired",
  "publicRepoStoresApprovalAliasOnly",
]);
if (manifest?.additionalActiveModelPolicy?.requiresExplicitUserApproval !== true) {
  fail(`${manifestPath}.additionalActiveModelPolicy.requiresExplicitUserApproval must be true`);
}
if (manifest?.additionalActiveModelPolicy?.privateApprovalReferenceRequired !== true) {
  fail(`${manifestPath}.additionalActiveModelPolicy.privateApprovalReferenceRequired must be true`);
}
if (manifest?.additionalActiveModelPolicy?.publicRepoStoresApprovalAliasOnly !== true) {
  fail(`${manifestPath}.additionalActiveModelPolicy.publicRepoStoresApprovalAliasOnly must be true`);
}
const initialActiveModels = requireExactStringSet(
  requireArray(manifest, manifestPath, "initialActiveModels"),
  `${manifestPath}.initialActiveModels`,
  ["claude-opus-4.7"],
);
if (!initialActiveModels.has("claude-opus-4.7")) {
  fail(`${manifestPath}.initialActiveModels must include claude-opus-4.7`);
}
const modelStatuses = requireExactStringSet(requireArray(manifest, manifestPath, "modelStatuses"), `${manifestPath}.modelStatuses`, ["active", "revoked"]);

const allowedMutationClasses = new Set(["visual-ui", "copy-ui", "mechanical-equivalent-refactor"]);
const requiredInitialMutationClasses = new Set(["visual-ui", "copy-ui", "mechanical-equivalent-refactor"]);
let activeVisualModelCount = 0;
let initialVisualModel = null;
const modelIds = new Set();
for (const [index, model] of requireArray(manifest, manifestPath, "allowedVisualModels").entries()) {
  const label = `${manifestPath}.allowedVisualModels[${index}]`;
  requireFields(model, label, [
    "id",
    "label",
    "status",
    "allowedMutationClasses",
    "scopeSource",
    "privateApprovalRequired",
  ]);
  if (modelIds.has(model?.id)) fail(`${label}.id duplicates ${model.id}`);
  modelIds.add(model?.id);
  if (!modelStatuses.has(model.status)) fail(`${label}.status is invalid`);
  if (model.status === "active") activeVisualModelCount += 1;
  if (model.id === "claude-opus-4.7") initialVisualModel = { model, label };
  if (model.privateApprovalRequired !== true) fail(`${label}.privateApprovalRequired must be true`);
  if (model.status === "active") {
    requireFields(model, label, ["approvedBy", "approvedAt", "privateApprovalReference"]);
    if (model.approvedBy !== "user") fail(`${label}.approvedBy must be user`);
    if (typeof model.approvedAt !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(model.approvedAt) || Number.isNaN(Date.parse(model.approvedAt))) {
      fail(`${label}.approvedAt must be an ISO date`);
    }
    requireSafePrivateReference(model.privateApprovalReference, manifest.privateApprovalAlias, `${label}.privateApprovalReference`);
  }
  if (model.scopeSource !== "docs/ui/visual-change-scopes.manifest.json") {
    fail(`${label}.scopeSource must be docs/ui/visual-change-scopes.manifest.json`);
  }
  const mutationClasses = requireArray(model, label, "allowedMutationClasses");
  requireUniqueStrings(mutationClasses, `${label}.allowedMutationClasses`);
  for (const mutationClass of mutationClasses) {
    if (!allowedMutationClasses.has(mutationClass)) fail(`${label}.allowedMutationClasses contains ${mutationClass}`);
  }
}
if (activeVisualModelCount < 1) fail(`${manifestPath}.allowedVisualModels must include at least one active model`);

const activeIds = new Set(
  (manifest?.allowedVisualModels || []).filter((model) => model.status === "active").map((model) => model.id),
);
if (!activeIds.has("claude-opus-4.7")) {
  fail(`${manifestPath}.allowedVisualModels must include active claude-opus-4.7`);
}
if (!initialVisualModel) {
  fail(`${manifestPath}.allowedVisualModels must include claude-opus-4.7`);
} else {
  const mutationClasses = new Set(Array.isArray(initialVisualModel.model.allowedMutationClasses) ? initialVisualModel.model.allowedMutationClasses : []);
  for (const mutationClass of requiredInitialMutationClasses) {
    if (!mutationClasses.has(mutationClass)) {
      fail(`${initialVisualModel.label}.allowedMutationClasses must include ${mutationClass}`);
    }
  }
}

const guardPath = "scripts/ui_governance_guard.mjs";
const guardSource = fs.existsSync(path.join(rootDir, guardPath))
  ? fs.readFileSync(path.join(rootDir, guardPath), "utf8")
  : "";
for (const snippet of [
  "required permission:",
  "current model signal:",
  "proposal route:",
  "reason=",
  "active visual model",
]) {
  if (!guardSource.includes(snippet)) fail(`${guardPath} must include clear visual guard diagnostic snippet: ${snippet}`);
}

scanForLocalPaths(manifest, manifestPath);

if (errors.length > 0) {
  console.error("UI visual model allowlist check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI visual model allowlist check passed (${activeVisualModelCount} active model)`);
