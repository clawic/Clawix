#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const rawArgs = process.argv.slice(2);
const args = new Set(rawArgs);
const isSelfTest = process.env.CLAWIX_UI_SURFACE_REFERENCE_SELF_TEST === "1";
const simulationFlags = [
  "--simulate-inactive-surface-references",
  "--simulate-wrong-inventory-path",
  "--simulate-wrong-pattern-registry-path",
  "--simulate-wrong-debt-registry-path",
  "--simulate-wrong-protected-surface-registry-path",
  "--simulate-wrong-exception-registry-path",
  "--simulate-extra-required-reference-kind",
  "--simulate-duplicate-required-reference-kind",
  "--simulate-missing-anchor",
  "--simulate-absolute-pattern-reference",
  "--simulate-pattern-missing-entry-platform",
  "--simulate-duplicate-coverage-id",
  "--simulate-unknown-pattern-reference",
  "--simulate-private-scope-reference",
  "--simulate-duplicate-source-root",
  "--simulate-unknown-platform",
  "--simulate-duplicate-scope",
  "--simulate-duplicate-pattern-reference",
  "--simulate-inactive-inventory",
  "--simulate-missing-source-root",
  "--simulate-missing-coverage-entry",
  "--simulate-unexpected-coverage-entry",
  "--simulate-wrong-coverage-classification",
  "--simulate-missing-coverage-reason",
  "--simulate-irrelevant-kind-field",
];
const allowedFlags = new Set(simulationFlags);
const errors = [];

function fail(message) {
  errors.push(message);
}

for (const arg of rawArgs) {
  if (arg.startsWith("--") && !allowedFlags.has(arg)) {
    console.error(`UI surface reference check received unknown flag ${arg}.`);
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

function isPublicSafeReference(reference) {
  if (typeof reference !== "string" || reference.length === 0) return false;
  if (path.isAbsolute(reference)) return false;
  if (reference.startsWith("~/") || reference.includes("\\") || reference.includes("/Users/")) return false;
  if (reference.startsWith("private-") || reference.includes(":")) return false;
  return true;
}

function referenceTarget(reference) {
  return reference.split("#", 1)[0];
}

function referenceAnchor(reference) {
  const [, anchor] = reference.split("#", 2);
  return anchor || "";
}

function markdownSlug(text) {
  return text
    .toLowerCase()
    .replace(/`([^`]+)`/g, "$1")
    .replace(/\*\*([^*]+)\*\*/g, "$1")
    .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
    .replace(/<[^>]+>/g, "")
    .replace(/^[\s#>*-]+/, "")
    .replace(/[^\p{L}\p{N}\s-]/gu, "")
    .trim()
    .replace(/\s/g, "-");
}

function anchorExists(reference, target) {
  const anchor = referenceAnchor(reference);
  if (!anchor) return true;
  const targetPath = path.join(rootDir, target);
  const content = fs.readFileSync(targetPath, "utf8");
  if (target.endsWith(".md")) {
    return content
      .split("\n")
      .some((line) => {
        if (/^\s*#+\s+/.test(line)) return markdownSlug(line) === anchor;
        if (/^\s*(?:[-*]|\d+\.)\s+/.test(line)) return markdownSlug(line) === anchor || markdownSlug(line).startsWith(`${anchor}-`);
        return false;
      });
  }
  if (target.endsWith(".json")) {
    return content.includes(`"id": "${anchor}"`) || content.includes(`"${anchor}"`);
  }
  return false;
}

function requireExistingReference(reference, label) {
  if (!isPublicSafeReference(reference)) {
    fail(`${label} must be a public-safe repo-relative reference`);
    return;
  }
  const target = referenceTarget(reference);
  if (!target) {
    fail(`${label} must include a file or directory target`);
    return;
  }
  if (!fs.existsSync(path.join(rootDir, target))) {
    fail(`${label} points to missing target ${target}`);
    return;
  }
  if (!anchorExists(reference, target)) {
    fail(`${label} points to missing anchor ${referenceAnchor(reference)} in ${target}`);
  }
}

const manifestPath = "docs/ui/surface-references.manifest.json";
const manifest = readJson(manifestPath);
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "inventoryPath",
  "patternRegistryPath",
  "debtRegistryPath",
  "protectedSurfaceRegistryPath",
  "exceptionRegistryPath",
  "requiredReferenceKinds",
  "publicReferencePolicy",
]);
if (args.has("--simulate-inactive-surface-references") && manifest) {
  manifest.status = "draft";
}
if (args.has("--simulate-wrong-inventory-path") && manifest) {
  manifest.inventoryPath = "docs/ui/surfaces.inventory.json";
}
if (args.has("--simulate-wrong-pattern-registry-path") && manifest) {
  manifest.patternRegistryPath = "docs/ui/patterns.registry.json";
}
if (args.has("--simulate-wrong-debt-registry-path") && manifest) {
  manifest.debtRegistryPath = "docs/ui/debt-baseline.json";
}
if (args.has("--simulate-wrong-protected-surface-registry-path") && manifest) {
  manifest.protectedSurfaceRegistryPath = "docs/ui/protected-surfaces.json";
}
if (args.has("--simulate-wrong-exception-registry-path") && manifest) {
  manifest.exceptionRegistryPath = "docs/ui/ui-exceptions.registry.json";
}
if (manifest?.schemaVersion !== 1) fail(`${manifestPath}.schemaVersion must be 1`);
if (manifest?.status !== "active") fail(`${manifestPath}.status must be active`);
if (manifest?.inventoryPath !== "docs/ui/visible-surfaces.inventory.json") {
  fail(`${manifestPath}.inventoryPath must be docs/ui/visible-surfaces.inventory.json`);
}
if (manifest?.patternRegistryPath !== "docs/ui/pattern-registry/patterns.registry.json") {
  fail(`${manifestPath}.patternRegistryPath must be docs/ui/pattern-registry/patterns.registry.json`);
}
if (manifest?.debtRegistryPath !== "docs/ui/debt.baseline.json") {
  fail(`${manifestPath}.debtRegistryPath must be docs/ui/debt.baseline.json`);
}
if (manifest?.protectedSurfaceRegistryPath !== "docs/ui/protected-surfaces.registry.json") {
  fail(`${manifestPath}.protectedSurfaceRegistryPath must be docs/ui/protected-surfaces.registry.json`);
}
if (manifest?.exceptionRegistryPath !== "docs/ui/exceptions.registry.json") {
  fail(`${manifestPath}.exceptionRegistryPath must be docs/ui/exceptions.registry.json`);
}
for (const kind of ["pattern", "debt", "protected", "exception"]) {
  if (!requireArray(manifest, manifestPath, "requiredReferenceKinds").includes(kind)) {
    fail(`${manifestPath}.requiredReferenceKinds must include ${kind}`);
  }
}
requireFields(manifest?.publicReferencePolicy, `${manifestPath}.publicReferencePolicy`, [
  "allowRepoRelativePath",
  "allowMarkdownAnchor",
  "forbidAbsolutePath",
  "forbidHomePath",
  "forbidPrivateRootAlias",
]);
for (const [field, expected] of Object.entries({
  allowRepoRelativePath: true,
  allowMarkdownAnchor: true,
  forbidAbsolutePath: true,
  forbidHomePath: true,
  forbidPrivateRootAlias: true,
})) {
  if (manifest?.publicReferencePolicy?.[field] !== expected) {
    fail(`${manifestPath}.publicReferencePolicy.${field} must be ${expected}`);
  }
}

if (args.has("--simulate-extra-required-reference-kind") && Array.isArray(manifest?.requiredReferenceKinds)) {
  manifest.requiredReferenceKinds.push("private-baseline");
}

if (args.has("--simulate-duplicate-required-reference-kind") && Array.isArray(manifest?.requiredReferenceKinds) && manifest.requiredReferenceKinds[0]) {
  manifest.requiredReferenceKinds.push(manifest.requiredReferenceKinds[0]);
}

requireExactStringSet(
  requireArray(manifest, manifestPath, "requiredReferenceKinds"),
  `${manifestPath}.requiredReferenceKinds`,
  ["pattern", "debt", "protected", "exception"],
);

const inventoryPath = manifest?.inventoryPath || "docs/ui/visible-surfaces.inventory.json";
const inventory = readJson(inventoryPath);
const registryPath = manifest?.patternRegistryPath || "docs/ui/pattern-registry/patterns.registry.json";
const registry = readJson(registryPath);
const patternIds = new Set(requireArray(registry, registryPath, "patterns"));
const patternReferences = new Map();
const patternPlatforms = new Map();
for (const patternId of patternIds) {
  const patternPath = `docs/ui/pattern-registry/patterns/${patternId}.pattern.json`;
  const pattern = readJson(patternPath);
  if (args.has("--simulate-missing-anchor") && patternId === "sidebar-section") {
    pattern.canonicalReferences = ["STYLE.md#missing-interface-governance-anchor"];
  }
  if (args.has("--simulate-absolute-pattern-reference") && patternId === "sidebar-section") {
    pattern.canonicalReferences = [path.join(path.sep, "tmp", "visual-baseline.md")];
  }
  if (args.has("--simulate-pattern-missing-entry-platform") && patternId === "chat-surface") {
    pattern.platforms = pattern.platforms.filter((platform) => platform !== "ios");
  }
  const references = requireArray(pattern, patternPath, "canonicalReferences");
  requireUniqueStrings(references, `${patternPath}.canonicalReferences`);
  for (const [index, reference] of references.entries()) {
    requireExistingReference(reference, `${patternPath}.canonicalReferences[${index}]`);
  }
  patternReferences.set(patternId, references);
  patternPlatforms.set(patternId, new Set(requireArray(pattern, patternPath, "platforms")));
}

const debtPath = manifest?.debtRegistryPath || "docs/ui/debt.baseline.json";
const debt = readJson(debtPath);
const debtIds = new Set(requireArray(debt, debtPath, "entries").map((entry) => entry.id));

const protectedPath = manifest?.protectedSurfaceRegistryPath || "docs/ui/protected-surfaces.registry.json";
const protectedSurfaces = readJson(protectedPath);
const protectedIds = new Set(requireArray(protectedSurfaces, protectedPath, "surfaces", { nonEmpty: false }).map((entry) => entry.id));

const exceptionPath = manifest?.exceptionRegistryPath || "docs/ui/exceptions.registry.json";
const exceptions = readJson(exceptionPath);
const exceptionIds = new Set(requireArray(exceptions, exceptionPath, "exceptions", { nonEmpty: false }).map((entry) => entry.id));

if (args.has("--simulate-duplicate-coverage-id") && Array.isArray(inventory?.coverage) && inventory.coverage[0]) {
  inventory.coverage = [...inventory.coverage, { ...inventory.coverage[0] }];
}
if (args.has("--simulate-unknown-pattern-reference") && Array.isArray(inventory?.coverage)) {
  const entry = inventory.coverage.find((candidate) => candidate?.classification === "pattern" && Array.isArray(candidate?.patterns));
  if (entry) entry.patterns = [...entry.patterns, "missing-pattern"];
}
if (args.has("--simulate-private-scope-reference") && Array.isArray(inventory?.coverage) && inventory.coverage[0]) {
  inventory.coverage[0] = { ...inventory.coverage[0], scopes: ["private-ui-root/**"] };
}
if (args.has("--simulate-duplicate-source-root") && Array.isArray(inventory?.sourceRoots) && inventory.sourceRoots[0]) {
  inventory.sourceRoots.push(inventory.sourceRoots[0]);
}
if (args.has("--simulate-unknown-platform") && Array.isArray(inventory?.coverage) && inventory.coverage[0]) {
  inventory.coverage[0] = { ...inventory.coverage[0], platform: "desktop" };
}
if (args.has("--simulate-duplicate-scope") && Array.isArray(inventory?.coverage)) {
  const entry = inventory.coverage.find((candidate) => Array.isArray(candidate?.scopes) && candidate.scopes[0]);
  if (entry) entry.scopes.push(entry.scopes[0]);
}
if (args.has("--simulate-duplicate-pattern-reference") && Array.isArray(inventory?.coverage)) {
  const entry = inventory.coverage.find((candidate) => Array.isArray(candidate?.patterns) && candidate.patterns[0]);
  if (entry) entry.patterns.push(entry.patterns[0]);
}
if (args.has("--simulate-inactive-inventory") && inventory) {
  inventory.status = "draft";
}
if (args.has("--simulate-missing-source-root") && Array.isArray(inventory?.sourceRoots)) {
  inventory.sourceRoots = inventory.sourceRoots.filter((sourceRoot) => sourceRoot !== "web/src");
}
if (args.has("--simulate-missing-coverage-entry") && Array.isArray(inventory?.coverage)) {
  inventory.coverage = inventory.coverage.filter((entry) => entry?.id !== "web-screens");
}
if (args.has("--simulate-unexpected-coverage-entry") && Array.isArray(inventory?.coverage)) {
  inventory.coverage.push({
    id: "desktop-floating-surfaces",
    platform: "macos",
    scopes: ["macos/Sources/Clawix/Floating/**"],
    classification: "pattern",
    patterns: ["sheet-chrome"],
    reason: "Simulated unmanaged surface.",
  });
}
if (args.has("--simulate-wrong-coverage-classification") && Array.isArray(inventory?.coverage)) {
  const entry = inventory.coverage.find((candidate) => candidate?.id === "macos-sidebar");
  if (entry) entry.classification = "debt";
}
if (args.has("--simulate-missing-coverage-reason") && Array.isArray(inventory?.coverage)) {
  const entry = inventory.coverage.find((candidate) => candidate?.id === "macos-sidebar");
  if (entry) delete entry.reason;
}
if (args.has("--simulate-irrelevant-kind-field") && Array.isArray(inventory?.coverage)) {
  const entry = inventory.coverage.find((candidate) => candidate?.classification === "pattern");
  if (entry) entry.debtIds = ["ui-debt-design-surface-raw-visual-values"];
}

const allowedPlatforms = new Set(["macos", "ios", "android", "web"]);
requireFields(inventory, inventoryPath, ["schemaVersion", "status", "policy", "reviewAfter", "sourceRoots", "coverage"]);
if (inventory?.schemaVersion !== 1) fail(`${inventoryPath}.schemaVersion must be 1`);
if (inventory?.status !== "active") fail(`${inventoryPath}.status must be active`);
if (typeof inventory?.reviewAfter !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(inventory.reviewAfter)) {
  fail(`${inventoryPath}.reviewAfter must be an ISO date`);
}
const sourceRoots = requireArray(inventory, inventoryPath, "sourceRoots");
requireUniqueStrings(sourceRoots, `${inventoryPath}.sourceRoots`);
requireExactStringSet(
  sourceRoots,
  `${inventoryPath}.sourceRoots`,
  [
    "macos/Sources/Clawix",
    "ios/Sources/Clawix",
    "apps/macos/Sources",
    "apps/ios/Sources",
    "android/app/src/main/java/com/example/clawix/android",
    "web/src",
  ],
);
for (const [index, sourceRoot] of sourceRoots.entries()) {
  requireExistingReference(sourceRoot, `${inventoryPath}.sourceRoots[${index}]`);
}

const expectedCoverage = new Map([
  ["macos-root-chrome", { platform: "macos", classification: "pattern" }],
  ["macos-sidebar", { platform: "macos", classification: "pattern" }],
  ["macos-chat-and-composer", { platform: "macos", classification: "pattern" }],
  ["macos-settings-and-configuration", { platform: "macos", classification: "pattern" }],
  ["macos-domain-surfaces", { platform: "macos", classification: "pattern" }],
  ["macos-design-debt", { platform: "macos", classification: "debt" }],
  ["macos-agent-and-bridge-support", { platform: "macos", classification: "pattern" }],
  ["macos-icon-and-visual-support", { platform: "macos", classification: "pattern" }],
  ["ios-chat-and-composer", { platform: "ios", classification: "pattern" }],
  ["ios-domain-surfaces", { platform: "ios", classification: "pattern" }],
  ["android-chat-and-composer", { platform: "android", classification: "pattern" }],
  ["android-domain-surfaces", { platform: "android", classification: "pattern" }],
  ["web-components-and-shell", { platform: "web", classification: "pattern" }],
  ["web-screens", { platform: "web", classification: "pattern" }],
]);
const seenCoverage = new Set();
for (const [index, entry] of requireArray(inventory, inventoryPath, "coverage").entries()) {
  const label = `${inventoryPath}.coverage[${index}]`;
  requireFields(entry, label, ["id", "platform", "classification", "scopes", "reason"]);
  if (seenCoverage.has(entry.id)) fail(`${label}.id duplicates ${entry.id}`);
  seenCoverage.add(entry.id);
  const expectedEntry = expectedCoverage.get(entry.id);
  if (!expectedEntry) {
    fail(`${label}.id is not a governed visible surface coverage id`);
  } else {
    if (entry.platform !== expectedEntry.platform) fail(`${label}.platform must be ${expectedEntry.platform}`);
    if (entry.classification !== expectedEntry.classification) fail(`${label}.classification must be ${expectedEntry.classification}`);
  }
  if (!allowedPlatforms.has(entry.platform)) fail(`${label}.platform must be macos, ios, android, or web`);
  if (typeof entry.reason !== "string" || entry.reason.length < 12) fail(`${label}.reason must explain the mapping`);
  const scopes = requireArray(entry, label, "scopes");
  requireUniqueStrings(scopes, `${label}.scopes`);
  for (const [scopeIndex, scope] of scopes.entries()) {
    requireExistingReference(scope.replace(/\*\*.*$/, "").replace(/\*.*$/, ""), `${label}.scopes[${scopeIndex}]`);
  }
  if (Array.isArray(entry.excludeScopes)) {
    requireUniqueStrings(entry.excludeScopes, `${label}.excludeScopes`);
    for (const [scopeIndex, scope] of entry.excludeScopes.entries()) {
      requireExistingReference(scope.replace(/\*\*.*$/, "").replace(/\*.*$/, ""), `${label}.excludeScopes[${scopeIndex}]`);
    }
  }
  if (entry.classification === "pattern") {
    for (const field of ["debtIds", "surfaceIds", "exceptionIds"]) {
      if (entry[field] !== undefined) fail(`${label}.${field} must not be set for pattern classification`);
    }
    const patterns = requireArray(entry, label, "patterns");
    requireUniqueStrings(patterns, `${label}.patterns`);
    for (const patternId of patterns) {
      if (!patternIds.has(patternId)) fail(`${label}.patterns references unknown pattern ${patternId}`);
      if ((patternReferences.get(patternId) || []).length === 0) fail(`${label}.patterns ${patternId} has no canonical references`);
      if (!patternPlatforms.get(patternId)?.has(entry.platform)) {
        fail(`${label}.patterns ${patternId} must declare platform ${entry.platform}`);
      }
    }
  } else if (entry.classification === "debt") {
    for (const field of ["patterns", "surfaceIds", "exceptionIds"]) {
      if (entry[field] !== undefined) fail(`${label}.${field} must not be set for debt classification`);
    }
    for (const debtId of requireArray(entry, label, "debtIds")) {
      if (!debtIds.has(debtId)) fail(`${label}.debtIds references unknown debt ${debtId}`);
    }
  } else if (entry.classification === "protected") {
    for (const field of ["patterns", "debtIds", "exceptionIds"]) {
      if (entry[field] !== undefined) fail(`${label}.${field} must not be set for protected classification`);
    }
    for (const surfaceId of requireArray(entry, label, "surfaceIds")) {
      if (!protectedIds.has(surfaceId)) fail(`${label}.surfaceIds references unknown protected surface ${surfaceId}`);
    }
  } else if (entry.classification === "exception") {
    for (const field of ["patterns", "debtIds", "surfaceIds"]) {
      if (entry[field] !== undefined) fail(`${label}.${field} must not be set for exception classification`);
    }
    for (const exceptionId of requireArray(entry, label, "exceptionIds")) {
      if (!exceptionIds.has(exceptionId)) fail(`${label}.exceptionIds references unknown exception ${exceptionId}`);
    }
  } else {
    fail(`${label}.classification must be pattern, debt, protected, or exception`);
  }
}
for (const coverageId of expectedCoverage.keys()) {
  if (!seenCoverage.has(coverageId)) fail(`${inventoryPath}.coverage must include ${coverageId}`);
}

if (errors.length > 0) {
  console.error("UI surface reference check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

if (!isSelfTest && rawArgs.length === 0) {
  const selfTests = [
    ["--unknown-flag", "received unknown flag --unknown-flag"],
    ["--simulate-inactive-surface-references", "docs/ui/surface-references.manifest.json.status must be active"],
    ["--simulate-wrong-inventory-path", "inventoryPath must be docs/ui/visible-surfaces.inventory.json"],
    ["--simulate-absolute-pattern-reference", "canonicalReferences[0] must be a public-safe repo-relative reference"],
    ["--simulate-missing-anchor", "points to missing anchor missing-interface-governance-anchor"],
    ["--simulate-private-scope-reference", "scopes[0] must be a public-safe repo-relative reference"],
    ["--simulate-unknown-pattern-reference", "references unknown pattern missing-pattern"],
    ["--simulate-wrong-coverage-classification", "classification must be pattern"],
  ];
  const scriptPath = path.relative(rootDir, new URL(import.meta.url).pathname);
  for (const [flag, expectedOutput] of selfTests) {
    const result = spawnSync(process.execPath, [scriptPath, flag], {
      cwd: rootDir,
      encoding: "utf8",
      env: { ...process.env, CLAWIX_UI_SURFACE_REFERENCE_SELF_TEST: "1" },
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status === 0 || !output.includes(expectedOutput)) {
      console.error(`UI surface reference self-test failed for ${flag}.`);
      if (output) console.error(output.trim());
      process.exit(1);
    }
  }
}

console.log(`UI surface reference check passed (${seenCoverage.size} surface coverage entries)`);
