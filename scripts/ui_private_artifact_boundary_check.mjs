#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const uiDir = path.join(rootDir, "docs/ui");
const expectedPrivateBaselineAlias = "private-codex-ui-baselines";
const expectedPrivateAssignment = "outside-public-repo";
const args = new Set(process.argv.slice(2));
const errors = [];
const privatePathOrSecretPattern = /\/Users\/|~\/|file:\/\/|[A-Z]:\\|BEGIN [A-Z ]*PRIVATE KEY|\bAKIA[0-9A-Z]{16}\b|\bsk-[A-Za-z0-9]{20,}\b/;

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

function requireField(object, label, field, expected) {
  if (!object || object[field] === undefined || object[field] === null || object[field] === "") {
    fail(`${label} is missing ${field}`);
    return;
  }
  if (expected !== undefined && object[field] !== expected) {
    fail(`${label}.${field} must be ${expected}`);
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
  for (const [index, value] of values.entries()) {
    const entryLabel = `${label}[${index}]`;
    if (typeof value !== "string" || value === "") {
      fail(`${entryLabel} must be a non-empty string`);
      continue;
    }
    if (seen.has(value)) fail(`${entryLabel} duplicates ${value}`);
    seen.add(value);
  }
  return seen;
}

function requireExactStrings(values, label, expected) {
  requireUniqueStrings(values, label);
  if (values.length !== expected.length || values.some((value, index) => value !== expected[index])) {
    fail(`${label} must match ${JSON.stringify(expected)}`);
  }
  return new Set(values);
}

function isSafeRepoRelativePath(value) {
  return typeof value === "string" &&
    value !== "" &&
    !value.startsWith("/") &&
    !value.startsWith("~/") &&
    !value.startsWith("file://") &&
    !value.includes("\\") &&
    !value.includes("..") &&
    !/^[A-Z]:\\/.test(value);
}

function walk(directory) {
  const entries = fs.readdirSync(directory, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) files.push(...walk(absolute));
    if (entry.isFile()) files.push(absolute);
  }
  return files;
}

function scanValue(value, label) {
  if (Array.isArray(value)) {
    value.forEach((child, index) => scanValue(child, `${label}[${index}]`));
    return;
  }
  if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) scanValue(child, `${label}.${key}`);
    return;
  }
  if (typeof value !== "string") return;
  if (/^\/Users\//.test(value) || value.startsWith("~/") || value.startsWith("file://") || /^[A-Z]:\\/.test(value)) {
    fail(`${label} must not contain a local private path`);
  }
  if (/BEGIN [A-Z ]*PRIVATE KEY/.test(value) || /\bAKIA[0-9A-Z]{16}\b/.test(value) || /\bsk-[A-Za-z0-9]{20,}\b/.test(value)) {
    fail(`${label} looks like a secret`);
  }
}

const forbiddenExtensions = new Set([
  ".apng",
  ".avif",
  ".gif",
  ".heic",
  ".jpeg",
  ".jpg",
  ".mov",
  ".mp4",
  ".pdf",
  ".png",
  ".trace",
  ".webm",
  ".webp",
  ".zip",
]);
const allowedPublicUiExtensions = new Set([".json", ".md"]);

for (const file of walk(uiDir)) {
  const relativePath = path.relative(rootDir, file);
  const extension = path.extname(file).toLowerCase();
  if (!allowedPublicUiExtensions.has(extension)) {
    fail(`${relativePath} must be a JSON or Markdown public contract, not a generated artifact`);
  }
  if (forbiddenExtensions.has(extension)) {
    fail(`${relativePath} must not store private visual evidence in the public repo`);
  }
  const content = fs.readFileSync(file, "utf8");
  if (privatePathOrSecretPattern.test(content)) {
    fail(`${relativePath} contains a private path or secret-like token`);
  }
  if (extension === ".json") {
    try {
      scanValue(JSON.parse(content), relativePath);
    } catch (error) {
      fail(`${relativePath} is not valid JSON: ${error.message}`);
    }
  }
}
if (args.has("--simulate-public-ui-binary-artifact")) {
  fail("docs/ui/simulated-private-baseline.png must not store private visual evidence in the public repo");
}

const privateValidation = readJson("docs/ui/private-visual-validation.manifest.json");
const privateBaselines = readJson("docs/ui/private-baselines.manifest.json");
const config = readJson("docs/ui/interface-governance.config.json");
if (args.has("--simulate-missing-private-baseline-alias") && Array.isArray(privateValidation?.rootAliases)) {
  privateValidation.rootAliases = privateValidation.rootAliases.filter((entry) => entry?.alias !== expectedPrivateBaselineAlias);
}
if (args.has("--simulate-missing-required-root") && Array.isArray(privateValidation?.requiredRoots)) {
  privateValidation.requiredRoots = privateValidation.requiredRoots.filter((root) => root !== "CLAWIX_UI_PRIVATE_COPY_ROOT");
}
if (args.has("--simulate-unexpected-required-root") && Array.isArray(privateValidation?.requiredRoots)) {
  privateValidation.requiredRoots = [...privateValidation.requiredRoots, "CLAWIX_UI_PRIVATE_SCREENSHOT_ROOT"];
}
if (args.has("--simulate-required-root-without-alias") && Array.isArray(privateValidation?.requiredRoots)) {
  privateValidation.requiredRoots = [...privateValidation.requiredRoots, "CLAWIX_UI_PRIVATE_SIMULATED_ROOT"];
}
if (args.has("--simulate-duplicate-root-alias") && Array.isArray(privateValidation?.rootAliases) && privateValidation.rootAliases[0]) {
  privateValidation.rootAliases.push({ ...privateValidation.rootAliases[0], env: "CLAWIX_UI_PRIVATE_DUPLICATE_ALIAS_ROOT" });
}
if (args.has("--simulate-duplicate-root-env") && Array.isArray(privateValidation?.rootAliases) && privateValidation.rootAliases[0]) {
  privateValidation.rootAliases.push({ ...privateValidation.rootAliases[0], alias: "private-codex-ui-duplicate-alias" });
}
if (args.has("--simulate-root-alias-missing-field") && Array.isArray(privateValidation?.rootAliases) && privateValidation.rootAliases[0]) {
  delete privateValidation.rootAliases[0].manifestAliasField;
}
if (args.has("--simulate-root-alias-unsafe-manifest-path") && Array.isArray(privateValidation?.rootAliases) && privateValidation.rootAliases[0]) {
  privateValidation.rootAliases[0].manifestPath = "../private-baselines.manifest.json";
}
if (args.has("--simulate-root-alias-wrong-manifest-alias-field") && Array.isArray(privateValidation?.rootAliases) && privateValidation.rootAliases[1]) {
  privateValidation.rootAliases[1].manifestAliasField = "privateRootAlias";
}
if (args.has("--simulate-optional-root-alias-wrong-env") && Array.isArray(privateValidation?.optionalRootAliases) && privateValidation.optionalRootAliases[0]) {
  privateValidation.optionalRootAliases[0].env = "CLAWIX_UI_PRIVATE_BASELINE_ROOT";
}
if (args.has("--simulate-private-validation-command-missing-root") && privateValidation) {
  privateValidation.verificationCommand = String(privateValidation.verificationCommand || "").replace("CLAWIX_UI_PRIVATE_DRIFT_ROOT=<private-root> ", "");
}
if (args.has("--simulate-public-screenshots-policy") && config?.privateArtifactsPolicy) {
  config.privateArtifactsPolicy.screenshots = "public";
}
if (args.has("--simulate-public-baselines-policy") && config?.privateArtifactsPolicy) {
  config.privateArtifactsPolicy.goldenBaselines = "public";
}
if (args.has("--simulate-missing-public-manifest-store") && Array.isArray(config?.privateArtifactsPolicy?.publicRepoStores)) {
  config.privateArtifactsPolicy.publicRepoStores = config.privateArtifactsPolicy.publicRepoStores.filter((store) => store !== "manifest");
}
if (args.has("--simulate-extra-public-repo-store") && Array.isArray(config?.privateArtifactsPolicy?.publicRepoStores)) {
  config.privateArtifactsPolicy.publicRepoStores = [...config.privateArtifactsPolicy.publicRepoStores, "raw-screenshot"];
}
if (args.has("--simulate-public-baseline-may-store-raw-screenshot") && Array.isArray(privateBaselines?.privateArtifactPolicy?.publicRepoMayStore)) {
  privateBaselines.privateArtifactPolicy.publicRepoMayStore = [...privateBaselines.privateArtifactPolicy.publicRepoMayStore, "raw-screenshot"];
}
if (args.has("--simulate-public-baseline-must-not-store-missing-secret") && Array.isArray(privateBaselines?.privateArtifactPolicy?.publicRepoMustNotStore)) {
  privateBaselines.privateArtifactPolicy.publicRepoMustNotStore = privateBaselines.privateArtifactPolicy.publicRepoMustNotStore.filter((store) => store !== "secret");
}
requireField(privateBaselines, "docs/ui/private-baselines.manifest.json", "privateRootAlias");
const privateBaselineAlias = privateBaselines?.privateRootAlias;
if (privateBaselineAlias !== expectedPrivateBaselineAlias) {
  fail(`docs/ui/private-baselines.manifest.json.privateRootAlias must be ${expectedPrivateBaselineAlias}`);
}
const requiredRootValues = requireArray(privateValidation, "docs/ui/private-visual-validation.manifest.json", "requiredRoots");
const requiredRoots = requireExactStrings(requiredRootValues, "docs/ui/private-visual-validation.manifest.json.requiredRoots", [
  "CLAWIX_UI_PRIVATE_BASELINE_ROOT",
  "CLAWIX_UI_PRIVATE_GEOMETRY_ROOT",
  "CLAWIX_UI_PRIVATE_COPY_ROOT",
  "CLAWIX_UI_PRIVATE_DRIFT_ROOT",
  "CLAWIX_UI_PRIVATE_DEBT_AUDIT_ROOT",
]);
const rootAliases = Array.isArray(privateValidation?.rootAliases) ? privateValidation.rootAliases : [];
const optionalRootAliases = Array.isArray(privateValidation?.optionalRootAliases) ? privateValidation.optionalRootAliases : [];
if (rootAliases.length === 0) fail("docs/ui/private-visual-validation.manifest.json.rootAliases must not be empty");
if (!rootAliases.some((entry) => entry?.alias === privateBaselineAlias)) {
  fail(`docs/ui/private-visual-validation.manifest.json.rootAliases must include ${privateBaselineAlias}`);
}
const expectedRootAliases = [
  {
    alias: "private-codex-ui-baselines",
    env: "CLAWIX_UI_PRIVATE_BASELINE_ROOT",
    manifestPath: "docs/ui/private-baselines.manifest.json",
    manifestAliasField: "privateRootAlias",
  },
  {
    alias: "private-codex-ui-rendered-geometry",
    env: "CLAWIX_UI_PRIVATE_GEOMETRY_ROOT",
    manifestPath: "docs/ui/rendered-geometry.manifest.json",
    manifestAliasField: "privateGeometryAlias",
  },
  {
    alias: "private-codex-ui-copy-snapshots",
    env: "CLAWIX_UI_PRIVATE_COPY_ROOT",
    manifestPath: "docs/ui/copy.inventory.json",
    manifestAliasField: "privateSnapshotAlias",
  },
  {
    alias: "private-codex-ui-rendered-drift",
    env: "CLAWIX_UI_PRIVATE_DRIFT_ROOT",
    manifestPath: "docs/ui/rendered-drift.manifest.json",
    manifestAliasField: "privateDriftAlias",
  },
  {
    alias: "private-codex-ui-debt-audit",
    env: "CLAWIX_UI_PRIVATE_DEBT_AUDIT_ROOT",
    manifestPath: "docs/ui/debt-audit.manifest.json",
    manifestAliasField: "privateDebtAuditAlias",
  },
];
const expectedOptionalRootAliases = [
  {
    alias: "private-codex-ui-approval",
    env: "CLAWIX_UI_PRIVATE_APPROVAL_ROOT",
    manifestPath: "docs/ui/approval-authority.manifest.json",
    manifestAliasField: "privateApprovalAlias",
  },
  {
    alias: "private-codex-ui-mechanical-equivalence",
    env: "CLAWIX_UI_PRIVATE_MECHANICAL_EQUIVALENCE_ROOT",
    manifestPath: "docs/ui/mechanical-equivalence.manifest.json",
    manifestAliasField: "privateEvidenceAlias",
  },
];
for (const [index, expected] of expectedRootAliases.entries()) {
  const actual = rootAliases[index];
  const label = `docs/ui/private-visual-validation.manifest.json.rootAliases[${index}]`;
  for (const field of ["alias", "env", "manifestPath", "manifestAliasField"]) {
    if (actual?.[field] !== expected[field]) fail(`${label}.${field} must be ${expected[field]}`);
  }
}
if (rootAliases.length !== expectedRootAliases.length) {
  fail("docs/ui/private-visual-validation.manifest.json.rootAliases must match the required private evidence aliases");
}
for (const [index, expected] of expectedOptionalRootAliases.entries()) {
  const actual = optionalRootAliases[index];
  const label = `docs/ui/private-visual-validation.manifest.json.optionalRootAliases[${index}]`;
  for (const field of ["alias", "env", "manifestPath", "manifestAliasField"]) {
    if (actual?.[field] !== expected[field]) fail(`${label}.${field} must be ${expected[field]}`);
  }
}
if (optionalRootAliases.length !== expectedOptionalRootAliases.length) {
  fail("docs/ui/private-visual-validation.manifest.json.optionalRootAliases must match the approved optional private evidence aliases");
}
const seenAliases = new Set();
const seenEnvs = new Set();
for (const [index, entry] of [...rootAliases, ...optionalRootAliases].entries()) {
  const isRequiredAlias = index < rootAliases.length;
  const label = isRequiredAlias
    ? `docs/ui/private-visual-validation.manifest.json.rootAliases[${index}]`
    : `docs/ui/private-visual-validation.manifest.json.optionalRootAliases[${index - rootAliases.length}]`;
  requireField(entry, label, "alias");
  requireField(entry, label, "env");
  requireField(entry, label, "manifestPath");
  requireField(entry, label, "manifestAliasField");
  if (!entry?.env || !entry?.manifestPath || !entry?.manifestAliasField) continue;
  if (seenAliases.has(entry.alias)) fail(`${label}.alias duplicates ${entry.alias}`);
  if (seenEnvs.has(entry.env)) fail(`${label}.env duplicates ${entry.env}`);
  seenAliases.add(entry.alias);
  seenEnvs.add(entry.env);
  if (!isSafeRepoRelativePath(entry.manifestPath) || !entry.manifestPath.startsWith("docs/ui/")) {
    fail(`${label}.manifestPath must be a safe docs/ui relative path`);
    continue;
  }
  if (isRequiredAlias && !requiredRoots.has(entry.env)) {
    fail(`${label}.env must be listed in docs/ui/private-visual-validation.manifest.json.requiredRoots`);
  }
  const linkedManifest = readJson(entry.manifestPath);
  requireField(linkedManifest, entry.manifestPath, entry.manifestAliasField, entry.alias);
  if (
    typeof linkedManifest?.verificationCommand === "string" &&
    !linkedManifest.verificationCommand.includes(entry.env)
  ) {
    fail(`${entry.manifestPath}.verificationCommand must include ${entry.env}`);
  }
}

const visualModelAllowlist = readJson("docs/ui/visual-model-allowlist.manifest.json");
if (args.has("--simulate-public-visual-model-assignment")) {
  visualModelAllowlist.privateAssignment = "public-repo";
}
requireField(visualModelAllowlist, "docs/ui/visual-model-allowlist.manifest.json", "privateAssignment", expectedPrivateAssignment);

const visualScopes = readJson("docs/ui/visual-change-scopes.manifest.json");
if (args.has("--simulate-public-visual-scope-assignment")) {
  visualScopes.privateModelAssignment = "public-repo";
}
requireField(visualScopes, "docs/ui/visual-change-scopes.manifest.json", "privateModelAssignment", expectedPrivateAssignment);

for (const root of requiredRoots) {
  if (!rootAliases.some((entry) => entry?.env === root)) {
    fail("docs/ui/private-visual-validation.manifest.json.rootAliases is missing " + root);
  }
  if (!String(privateValidation?.verificationCommand || "").includes(root)) {
    fail(`docs/ui/private-visual-validation.manifest.json.verificationCommand must include ${root}`);
  }
}

requireField(config?.privateArtifactsPolicy, "docs/ui/interface-governance.config.json.privateArtifactsPolicy", "screenshots", "private");
requireField(config?.privateArtifactsPolicy, "docs/ui/interface-governance.config.json.privateArtifactsPolicy", "goldenBaselines", "private");
requireExactStrings(
  requireArray(config?.privateArtifactsPolicy, "docs/ui/interface-governance.config.json.privateArtifactsPolicy", "publicRepoStores"),
  "docs/ui/interface-governance.config.json.privateArtifactsPolicy.publicRepoStores",
  ["manifest", "metadata", "tolerance", "command", "hash"],
);
requireField(privateBaselines?.privateArtifactPolicy, "docs/ui/private-baselines.manifest.json.privateArtifactPolicy", "screenshots", "private-only");
requireField(privateBaselines?.privateArtifactPolicy, "docs/ui/private-baselines.manifest.json.privateArtifactPolicy", "videos", "private-only");
requireField(privateBaselines?.privateArtifactPolicy, "docs/ui/private-baselines.manifest.json.privateArtifactPolicy", "geometrySnapshots", "private-only");
requireField(privateBaselines?.privateArtifactPolicy, "docs/ui/private-baselines.manifest.json.privateArtifactPolicy", "performanceTraces", "private-only");
requireExactStrings(
  requireArray(privateBaselines?.privateArtifactPolicy, "docs/ui/private-baselines.manifest.json.privateArtifactPolicy", "publicRepoMayStore"),
  "docs/ui/private-baselines.manifest.json.privateArtifactPolicy.publicRepoMayStore",
  ["manifest", "metadata", "hash", "tolerance", "runner-id", "approval-record-reference"],
);
requireExactStrings(
  requireArray(privateBaselines?.privateArtifactPolicy, "docs/ui/private-baselines.manifest.json.privateArtifactPolicy", "publicRepoMustNotStore"),
  "docs/ui/private-baselines.manifest.json.privateArtifactPolicy.publicRepoMustNotStore",
  ["raw-screenshot", "raw-video", "raw-trace", "local-absolute-path", "secret", "signing-identity"],
);

if (errors.length > 0) {
  console.error("UI private artifact boundary check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("UI private artifact boundary check passed");
