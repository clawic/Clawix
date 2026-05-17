#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = new Set(process.argv.slice(2));
const errors = [];

function fail(message) {
  errors.push(message);
}

function readText(relativePath) {
  const file = path.join(rootDir, relativePath);
  if (!fs.existsSync(file)) {
    fail(`missing ${relativePath}`);
    return "";
  }
  return fs.readFileSync(file, "utf8");
}

function readJson(relativePath) {
  const text = readText(relativePath);
  if (!text) return null;
  try {
    return JSON.parse(text);
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

function requireIncludes(values, label, expected) {
  const set = new Set(values);
  for (const value of expected) {
    if (!set.has(value)) fail(`${label} must include ${value}`);
  }
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

const manifestPath = "docs/ui/implementation-evidence.manifest.json";
const manifest = readJson(manifestPath);
if (manifest) {
  if (args.has("--simulate-inactive-manifest")) {
    manifest.status = "draft";
  }
  if (args.has("--simulate-missing-evidence-field") && Array.isArray(manifest.requiredEvidenceFields)) {
    manifest.requiredEvidenceFields = manifest.requiredEvidenceFields.filter((field) => field !== "visibleSurfaces");
  }
  if (args.has("--simulate-missing-mapping-kind") && Array.isArray(manifest.mappingKinds)) {
    manifest.mappingKinds = manifest.mappingKinds.filter((kind) => kind !== "protected");
  }
  if (args.has("--simulate-missing-interactive-state") && Array.isArray(manifest.requiredInteractiveStates)) {
    manifest.requiredInteractiveStates = manifest.requiredInteractiveStates.filter((state) => state !== "error");
  }
  if (args.has("--simulate-missing-visual-model-check") && Array.isArray(manifest.requiredPublicChecks)) {
    manifest.requiredPublicChecks = manifest.requiredPublicChecks.filter((check) => check !== "node scripts/ui_visual_model_allowlist_check.mjs");
  }
  if (args.has("--simulate-missing-private-data-ban")) {
    manifest.privateDataPolicy = manifest.privateDataPolicy || {};
    manifest.privateDataPolicy.publicRepoMustNotStore = (manifest.privateDataPolicy.publicRepoMustNotStore || []).filter(
      (item) => item !== "private model assignment",
    );
  }
  if (args.has("--simulate-missing-pr-template-snippet") && Array.isArray(manifest.prTemplateRequiredSnippets)) {
    manifest.prTemplateRequiredSnippets = [...manifest.prTemplateRequiredSnippets, "Simulated required evidence line:"];
  }
  if (args.has("--simulate-nonconceptual-proposal")) {
    manifest.proposalPath = "docs/ui/implementation-evidence.manifest.json";
  }
  if (args.has("--simulate-extra-evidence-field") && Array.isArray(manifest.requiredEvidenceFields)) {
    manifest.requiredEvidenceFields.push("privateScreenshotPath");
  }
  if (args.has("--simulate-duplicate-evidence-field") && Array.isArray(manifest.requiredEvidenceFields) && manifest.requiredEvidenceFields[0]) {
    manifest.requiredEvidenceFields.push(manifest.requiredEvidenceFields[0]);
  }
  if (args.has("--simulate-extra-mapping-kind") && Array.isArray(manifest.mappingKinds)) {
    manifest.mappingKinds.push("private-baseline");
  }
  if (args.has("--simulate-duplicate-mapping-kind") && Array.isArray(manifest.mappingKinds) && manifest.mappingKinds[0]) {
    manifest.mappingKinds.push(manifest.mappingKinds[0]);
  }
  if (args.has("--simulate-extra-allowed-mutation-class") && Array.isArray(manifest.allowedMutationClasses)) {
    manifest.allowedMutationClasses.push("presentation-cleanup");
  }
  if (args.has("--simulate-duplicate-public-check") && Array.isArray(manifest.requiredPublicChecks) && manifest.requiredPublicChecks[0]) {
    manifest.requiredPublicChecks.push(manifest.requiredPublicChecks[0]);
  }
  if (args.has("--simulate-duplicate-private-data-ban") && Array.isArray(manifest.privateDataPolicy?.publicRepoMustNotStore) && manifest.privateDataPolicy.publicRepoMustNotStore[0]) {
    manifest.privateDataPolicy.publicRepoMustNotStore.push(manifest.privateDataPolicy.publicRepoMustNotStore[0]);
  }
}
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "prTemplatePath",
  "proposalPath",
  "requiredEvidenceFields",
  "mappingKinds",
  "allowedMutationClasses",
  "requiredInteractiveStates",
  "requiredPublicChecks",
  "prTemplateRequiredSnippets",
  "privateDataPolicy",
]);

if (manifest?.status !== "active") fail(`${manifestPath}.status must be active`);
if (manifest?.prTemplatePath !== ".github/PULL_REQUEST_TEMPLATE.md") {
  fail(`${manifestPath}.prTemplatePath must point to .github/PULL_REQUEST_TEMPLATE.md`);
}
if (manifest?.proposalPath !== "docs/ui/visual-change-proposal.template.md") {
  fail(`${manifestPath}.proposalPath must point to docs/ui/visual-change-proposal.template.md`);
}

const configPath = "docs/ui/interface-governance.config.json";
const config = readJson(configPath);
const configMutationClasses = requireArray(config, configPath, "mutationClasses");
requireUniqueStrings(configMutationClasses, `${configPath}.mutationClasses`);
const manifestMutationClasses = requireArray(manifest, manifestPath, "allowedMutationClasses");
requireExactStringSet(manifestMutationClasses, `${manifestPath}.allowedMutationClasses`, configMutationClasses);

const requiredEvidenceFields = [
  "mutationClass",
  "patternOrDebtProtectedExceptionMapping",
  "touchedFiles",
  "visibleSurfaces",
  "requiredInteractiveStates",
  "publicChecks",
  "visualCopyLayoutAuthorization",
];
requireExactStringSet(
  requireArray(manifest, manifestPath, "requiredEvidenceFields"),
  `${manifestPath}.requiredEvidenceFields`,
  requiredEvidenceFields,
);

requireExactStringSet(
  requireArray(manifest, manifestPath, "mappingKinds"),
  `${manifestPath}.mappingKinds`,
  ["pattern", "debt", "protected", "exception"],
);

const configInteractiveStates = requireArray(config, configPath, "requiredInteractiveStates");
requireUniqueStrings(configInteractiveStates, `${configPath}.requiredInteractiveStates`);
requireExactStringSet(
  requireArray(manifest, manifestPath, "requiredInteractiveStates"),
  `${manifestPath}.requiredInteractiveStates`,
  configInteractiveStates,
);

requireIncludes(
  requireArray(manifest, manifestPath, "requiredPublicChecks"),
  `${manifestPath}.requiredPublicChecks`,
  [
    "node scripts/ui_governance_guard.mjs",
    "node scripts/ui_surface_inventory_check.mjs",
    "node scripts/ui_visual_scope_check.mjs",
    "node scripts/ui_visual_model_allowlist_check.mjs",
  ],
);
requireUniqueStrings(requireArray(manifest, manifestPath, "requiredPublicChecks"), `${manifestPath}.requiredPublicChecks`);

requireIncludes(
  requireArray(config, configPath, "publicChecks"),
  `${configPath}.publicChecks`,
  ["implementation-evidence-contract-check"],
);

const privateDataPolicy = manifest?.privateDataPolicy || {};
requireUniqueStrings(
  requireArray(privateDataPolicy, `${manifestPath}.privateDataPolicy`, "publicRepoMayStore"),
  `${manifestPath}.privateDataPolicy.publicRepoMayStore`,
);
const publicRepoMustNotStore = requireArray(privateDataPolicy, `${manifestPath}.privateDataPolicy`, "publicRepoMustNotStore");
requireUniqueStrings(publicRepoMustNotStore, `${manifestPath}.privateDataPolicy.publicRepoMustNotStore`);
requireIncludes(
  publicRepoMustNotStore,
  `${manifestPath}.privateDataPolicy.publicRepoMustNotStore`,
  ["raw screenshot", "private model assignment", "local absolute path", "secret"],
);

const prTemplate = readText(manifest?.prTemplatePath || ".github/PULL_REQUEST_TEMPLATE.md");
const requiredSnippets = requireArray(manifest, manifestPath, "prTemplateRequiredSnippets");
requireUniqueStrings(requiredSnippets, `${manifestPath}.prTemplateRequiredSnippets`);
for (const snippet of requiredSnippets) {
  if (!prTemplate.includes(snippet)) fail(`${manifest?.prTemplatePath} is missing required snippet: ${snippet}`);
}

const skill = readText("skills/ui-implementation/SKILL.md");
for (const snippet of [
  "Declare the UI governance evidence",
  "pattern IDs or debt/protected/exception mapping",
  "public checks to run",
]) {
  if (!skill.includes(snippet)) fail(`skills/ui-implementation/SKILL.md is missing required snippet: ${snippet}`);
}

const proposal = readText(manifest?.proposalPath || "docs/ui/visual-change-proposal.template.md");
if (!proposal.includes("Status: conceptual-only")) {
  fail(`${manifest?.proposalPath} must remain conceptual-only`);
}

if (errors.length > 0) {
  console.error("UI implementation evidence check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("UI implementation evidence check passed");
