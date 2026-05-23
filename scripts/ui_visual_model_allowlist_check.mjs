#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const rawArgs = process.argv.slice(2);
const args = new Set(rawArgs);
const isSelfTest = process.env.CLAWIX_UI_VISUAL_MODEL_ALLOWLIST_SELF_TEST === "1";
const errors = [];
const simulationFlags = [
  "--simulate-missing-active-initial-model",
  "--simulate-extra-initial-model",
  "--simulate-duplicate-initial-model",
  "--simulate-extra-model-status",
  "--simulate-duplicate-model-status",
  "--simulate-duplicate-visual-model",
  "--simulate-duplicate-mutation-class",
  "--simulate-missing-copy-class",
  "--simulate-unknown-mutation-class",
  "--simulate-private-approval-not-required",
  "--simulate-wrong-scope-source",
  "--simulate-model-signal-not-required",
  "--simulate-wrong-authorization-signal",
  "--simulate-wrong-model-signal-env",
  "--simulate-private-assignment-public",
  "--simulate-inactive-manifest",
];
const allowedFlags = new Set(simulationFlags);

function fail(message) {
  errors.push(message);
}

for (const arg of rawArgs) {
  if (arg.startsWith("--") && !allowedFlags.has(arg)) {
    console.error(`UI visual model allowlist check received unknown flag ${arg}.`);
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

function requireSafeExternalReference(value, alias, label) {
  if (typeof value !== "string" || !value.startsWith(`${alias}:`)) {
    fail(`${label} must use ${alias}:`);
    return;
  }
  const suffix = value.slice(alias.length + 1);
  if (!suffix || suffix.startsWith("/") || suffix.startsWith("\\") || suffix.startsWith("~/") || suffix.includes("..") || /^[A-Z]:\\/.test(suffix)) {
    fail(`${label} must use a safe relative external reference`);
  }
  if (hasLocalPath(value) || value.includes("/Users/")) {
    fail(`${label} must not contain a local path`);
  }
}

function runFailureSelfTests() {
  const selfTestEnv = {
    ...process.env,
    CLAWIX_UI_VISUAL_MODEL_ALLOWLIST_SELF_TEST: "1",
  };
  const tests = [
    [["--unknown-flag"], "received unknown flag --unknown-flag"],
    [["--simulate-missing-active-initial-model"], "allowedVisualModels must include active approved-visual-model"],
    [["--simulate-extra-initial-model"], "initialActiveModels must not include other-visual-model"],
    [["--simulate-duplicate-initial-model"], "initialActiveModels duplicates approved-visual-model"],
    [["--simulate-extra-model-status"], "modelStatuses must not include pending-review"],
    [["--simulate-duplicate-model-status"], "modelStatuses duplicates active"],
    [["--simulate-duplicate-visual-model"], "id duplicates approved-visual-model"],
    [["--simulate-duplicate-mutation-class"], "allowedMutationClasses duplicates visual-ui"],
    [["--simulate-missing-copy-class"], "allowedMutationClasses must include copy-ui"],
    [["--simulate-unknown-mutation-class"], "allowedMutationClasses contains layout-ui"],
    [["--simulate-private-approval-not-required"], "privateApprovalRequired must be true"],
    [["--simulate-wrong-scope-source"], "scopeSource must be docs/ui/visual-change-scopes.manifest.json"],
    [["--simulate-model-signal-not-required"], "modelSignal.requiredForVisualMutation must be true"],
    [["--simulate-wrong-authorization-signal"], "authorizationSignal.env must be CLAWIX_UI_VISUAL_AUTHORIZED"],
    [["--simulate-wrong-model-signal-env"], "modelSignal.env must be CLAWIX_UI_VISUAL_MODEL"],
    [["--simulate-private-assignment-public"], "privateAssignment must stay outside-public-repo"],
    [["--simulate-inactive-manifest"], "status must be active"],
  ];

  for (const [testArgs, expectedOutput] of tests) {
    const result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, ...testArgs], {
      cwd: rootDir,
      env: selfTestEnv,
      encoding: "utf8",
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status === 0) {
      fail(`self-test ${testArgs.join(" ")} must fail for UI visual model allowlist validation`);
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

const manifestPath = "docs/ui/visual-model-allowlist.manifest.json";
const manifest = readJson(manifestPath);
if (args.has("--simulate-missing-active-initial-model") && Array.isArray(manifest?.allowedVisualModels)) {
  manifest.allowedVisualModels = manifest.allowedVisualModels.map((model) => (
    model?.id === "approved-visual-model" ? { ...model, status: "revoked" } : model
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
    model?.id === "approved-visual-model" && Array.isArray(model.allowedMutationClasses) && model.allowedMutationClasses[0]
      ? { ...model, allowedMutationClasses: [...model.allowedMutationClasses, model.allowedMutationClasses[0]] }
      : model
  ));
}
if (args.has("--simulate-missing-copy-class") && Array.isArray(manifest?.allowedVisualModels)) {
  manifest.allowedVisualModels = manifest.allowedVisualModels.map((model) =>
    model?.id === "approved-visual-model"
      ? { ...model, allowedMutationClasses: (model.allowedMutationClasses || []).filter((mutationClass) => mutationClass !== "copy-ui") }
      : model,
  );
}
if (args.has("--simulate-unknown-mutation-class") && Array.isArray(manifest?.allowedVisualModels)) {
  manifest.allowedVisualModels = manifest.allowedVisualModels.map((model) => (
    model?.id === "approved-visual-model"
      ? { ...model, allowedMutationClasses: [...(model.allowedMutationClasses || []), "layout-ui"] }
      : model
  ));
}
if (args.has("--simulate-private-approval-not-required") && Array.isArray(manifest?.allowedVisualModels)) {
  manifest.allowedVisualModels = manifest.allowedVisualModels.map((model) => (
    model?.id === "approved-visual-model" ? { ...model, privateApprovalRequired: false } : model
  ));
}
if (args.has("--simulate-wrong-scope-source") && Array.isArray(manifest?.allowedVisualModels)) {
  manifest.allowedVisualModels = manifest.allowedVisualModels.map((model) => (
    model?.id === "approved-visual-model" ? { ...model, scopeSource: "docs/ui/unknown-scopes.manifest.json" } : model
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
  "externalApprovalAlias",
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
if (manifest?.externalApprovalAlias !== approvalAuthority?.externalApprovalAlias) {
  fail(`${manifestPath}.externalApprovalAlias must match docs/ui/approval-authority.manifest.json.externalApprovalAlias`);
}
requireFields(manifest?.additionalActiveModelPolicy, `${manifestPath}.additionalActiveModelPolicy`, [
  "requiresExplicitUserApproval",
  "externalApprovalReferenceRequired",
  "publicRepoStoresApprovalAliasOnly",
]);
if (manifest?.additionalActiveModelPolicy?.requiresExplicitUserApproval !== true) {
  fail(`${manifestPath}.additionalActiveModelPolicy.requiresExplicitUserApproval must be true`);
}
if (manifest?.additionalActiveModelPolicy?.externalApprovalReferenceRequired !== true) {
  fail(`${manifestPath}.additionalActiveModelPolicy.externalApprovalReferenceRequired must be true`);
}
if (manifest?.additionalActiveModelPolicy?.publicRepoStoresApprovalAliasOnly !== true) {
  fail(`${manifestPath}.additionalActiveModelPolicy.publicRepoStoresApprovalAliasOnly must be true`);
}
const initialActiveModels = requireExactStringSet(
  requireArray(manifest, manifestPath, "initialActiveModels"),
  `${manifestPath}.initialActiveModels`,
  ["approved-visual-model"],
);
if (!initialActiveModels.has("approved-visual-model")) {
  fail(`${manifestPath}.initialActiveModels must include approved-visual-model`);
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
  if (model.id === "approved-visual-model") initialVisualModel = { model, label };
  if (model.privateApprovalRequired !== true) fail(`${label}.privateApprovalRequired must be true`);
  if (model.status === "active") {
    requireFields(model, label, ["approvedBy", "approvedAt", "externalApprovalReference"]);
    if (model.approvedBy !== "user") fail(`${label}.approvedBy must be user`);
    if (typeof model.approvedAt !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(model.approvedAt) || Number.isNaN(Date.parse(model.approvedAt))) {
      fail(`${label}.approvedAt must be an ISO date`);
    }
    requireSafeExternalReference(model.externalApprovalReference, manifest.externalApprovalAlias, `${label}.externalApprovalReference`);
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
if (!activeIds.has("approved-visual-model")) {
  fail(`${manifestPath}.allowedVisualModels must include active approved-visual-model`);
}
if (!initialVisualModel) {
  fail(`${manifestPath}.allowedVisualModels must include approved-visual-model`);
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
