#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const today = new Date().toISOString().slice(0, 10);
const rawArgs = process.argv.slice(2);
const args = new Set(rawArgs);
const isSelfTest = process.env.CLAWIX_UI_SURFACE_INVENTORY_SELF_TEST === "1";
const simulationFlags = [
  "--simulate-pattern-platform-mismatch",
  "--simulate-expired-review-after",
  "--simulate-unsafe-source-root",
  "--simulate-missing-required-source-root",
  "--simulate-ungoverned-source-root",
  "--simulate-missing-source-root",
  "--simulate-ambiguous-visible-candidate",
  "--simulate-uncovered-visible-candidate",
  "--simulate-duplicate-coverage-id",
  "--simulate-unsupported-platform",
  "--simulate-invalid-classification",
  "--simulate-unknown-pattern",
  "--simulate-unknown-debt-id",
  "--simulate-unknown-protected-surface",
  "--simulate-unknown-exception",
  "--simulate-unmatched-coverage-scope",
  "--simulate-unsafe-coverage-scope",
  "--simulate-v1-pattern-set-missing-registry",
  "--simulate-v1-pattern-set-missing-inventory",
  "--simulate-v1-pattern-set-missing-baseline-coverage",
  "--simulate-v1-pattern-set-missing-private-baseline",
  "--simulate-v1-pattern-set-missing-private-geometry-platform",
  "--simulate-v1-pattern-set-missing-private-verifier",
  "--simulate-v1-pattern-set-premature-complete",
  "--simulate-approved-v1-pattern-set-stale-decision",
];
const allowedFlags = new Set(simulationFlags);
const errors = [];

function fail(message) {
  errors.push(message);
}

for (const arg of rawArgs) {
  if (arg.startsWith("--") && !allowedFlags.has(arg)) {
    console.error(`UI surface inventory check received unknown flag ${arg}.`);
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
  if (!object) return [];
  const value = object[field];
  if (value === undefined && !nonEmpty) return [];
  if (!Array.isArray(value)) {
    fail(`${label}.${field} must be an array`);
    return [];
  }
  if (nonEmpty && value.length === 0) {
    fail(`${label}.${field} must not be empty`);
  }
  return value;
}

function isSafeRelativePath(value) {
  return typeof value === "string"
    && value !== ""
    && !value.startsWith("/")
    && !value.startsWith("~/")
    && !value.includes("\\")
    && !value.includes("..")
    && !value.startsWith("file://")
    && !/^[A-Z]:\\/.test(value);
}

function walk(relativeDir) {
  const absoluteDir = path.join(rootDir, relativeDir);
  if (!fs.existsSync(absoluteDir)) return [];
  const result = [];
  const stack = [relativeDir];
  while (stack.length > 0) {
    const current = stack.pop();
    const absolute = path.join(rootDir, current);
    for (const entry of fs.readdirSync(absolute, { withFileTypes: true })) {
      const relativePath = path.posix.join(current, entry.name);
      if (entry.isDirectory()) {
        if ([".build", "build", "dist", "node_modules", "Resources", "Assets.xcassets", "Fonts", "Mocks"].includes(entry.name)) {
          continue;
        }
        stack.push(relativePath);
      } else {
        result.push(relativePath);
      }
    }
  }
  return result.sort();
}

function globToRegExp(glob) {
  let output = "^";
  for (let index = 0; index < glob.length; index += 1) {
    const char = glob[index];
    const next = glob[index + 1];
    if (char === "*" && next === "*") {
      output += ".*";
      index += 1;
    } else if (char === "*") {
      output += "[^/]*";
    } else {
      output += char.replace(/[|\\{}()[\]^$+?.]/g, "\\$&");
    }
  }
  return new RegExp(`${output}$`);
}

function platformFor(relativePath) {
  if (relativePath.startsWith("macos/")) return "macos";
  if (relativePath.startsWith("ios/")) return "ios";
  if (relativePath.startsWith("apps/macos/")) return "macos";
  if (relativePath.startsWith("apps/ios/")) return "ios";
  if (relativePath.startsWith("android/")) return "android";
  if (relativePath.startsWith("web/")) return "web";
  return "unknown";
}

function isVisibleCandidate(relativePath) {
  const extension = path.extname(relativePath);
  if (![".swift", ".kt", ".tsx"].includes(extension)) return false;
  const basename = path.basename(relativePath);
  if (/ViewModel|PersistentSurfaceRegistry|Intents|Backfill/.test(basename)) return false;
  const visibleName = /(View|Screen|Page|Panel|Sidebar|Composer|Button|Card|Menu|Sheet|Toast|Search|Terminal|Surface|Icon|Chrome|Bubble|Timeline|Shimmer|Picker|Controls|Overlay|Header|Footer|Segmented|Field|Row)/;
  if (extension === ".tsx") return true;
  const text = fs.readFileSync(path.join(rootDir, relativePath), "utf8");
  if (extension === ".swift") {
    return visibleName.test(basename) || /:\s*(some\s+)?View\b|NSView|NSPanel|NSWindow|LucideIcon|Image\(lucide/.test(text);
  }
  return visibleName.test(basename) || /@Composable/.test(text);
}

const registry = readJson("docs/ui/pattern-registry/patterns.registry.json");
const patternIds = new Set(requireArray(registry, "docs/ui/pattern-registry/patterns.registry.json", "patterns"));
const patternPlatforms = new Map();
for (const patternId of patternIds) {
  const patternPath = `docs/ui/pattern-registry/patterns/${patternId}.pattern.json`;
  const pattern = readJson(patternPath);
  if (args.has("--simulate-pattern-platform-mismatch") && patternId === "sidebar-row") {
    pattern.platforms = ["macos"];
  }
  patternPlatforms.set(patternId, new Set(requireArray(pattern, patternPath, "platforms")));
}

const debt = readJson("docs/ui/debt.baseline.json");
const debtIds = new Set(requireArray(debt, "docs/ui/debt.baseline.json", "entries").map((entry) => entry.id));

const protectedSurfaces = readJson("docs/ui/protected-surfaces.registry.json");
const protectedIds = new Set(requireArray(protectedSurfaces, "docs/ui/protected-surfaces.registry.json", "surfaces", { nonEmpty: false }).map((entry) => entry.id));

const exceptions = readJson("docs/ui/exceptions.registry.json");
const exceptionIds = new Set(requireArray(exceptions, "docs/ui/exceptions.registry.json", "exceptions", { nonEmpty: false }).map((entry) => entry.id));

const inventoryPath = "docs/ui/visible-surfaces.inventory.json";
const inventory = readJson(inventoryPath);
const surfaceBaselineCoveragePath = "docs/ui/surface-baseline-coverage.manifest.json";
const surfaceBaselineCoverage = readJson(surfaceBaselineCoveragePath);
const decisionVerificationPath = "docs/ui/decision-verification.json";
const decisionVerification = readJson(decisionVerificationPath);
const v1PatternSetDecision = (decisionVerification?.decisions || []).find((decision) => decision?.id === "v1_pattern_set");
requireFields(inventory, inventoryPath, ["schemaVersion", "status", "policy", "reviewAfter", "sourceRoots", "coverage"]);
if (args.has("--simulate-expired-review-after") && inventory) {
  inventory.reviewAfter = "2026-01-01";
}
if (args.has("--simulate-unsafe-source-root") && Array.isArray(inventory?.sourceRoots)) {
  inventory.sourceRoots[0] = "/Users/example/Clawix";
}
if (args.has("--simulate-missing-required-source-root") && Array.isArray(inventory?.sourceRoots)) {
  inventory.sourceRoots = inventory.sourceRoots.filter((sourceRoot) => sourceRoot !== "web/src");
}
if (args.has("--simulate-ungoverned-source-root") && Array.isArray(inventory?.sourceRoots)) {
  inventory.sourceRoots.push("tools/ui");
}
if (args.has("--simulate-missing-source-root") && Array.isArray(inventory?.sourceRoots)) {
  inventory.sourceRoots.push("web/missing");
}
if (args.has("--simulate-ambiguous-visible-candidate") && Array.isArray(inventory?.coverage) && inventory.coverage[0]) {
  inventory.coverage.push({
    ...inventory.coverage[0],
    id: "simulated-ambiguous-visible-candidate",
  });
}
if (args.has("--simulate-uncovered-visible-candidate") && Array.isArray(inventory?.coverage)) {
  inventory.coverage = inventory.coverage.filter((entry) => entry?.id !== "web-components-and-shell");
}
if (args.has("--simulate-duplicate-coverage-id") && Array.isArray(inventory?.coverage) && inventory.coverage[0]) {
  inventory.coverage.push({
    ...inventory.coverage[0],
  });
}
if (args.has("--simulate-unsupported-platform") && Array.isArray(inventory?.coverage) && inventory.coverage[0]) {
  inventory.coverage[0].platform = "visionos";
}
if (args.has("--simulate-invalid-classification") && Array.isArray(inventory?.coverage) && inventory.coverage[0]) {
  inventory.coverage[0].classification = "misc";
}
if (args.has("--simulate-unknown-pattern") && Array.isArray(inventory?.coverage) && inventory.coverage[0]) {
  inventory.coverage[0].patterns = ["missing-pattern"];
}
if (args.has("--simulate-unknown-debt-id") && Array.isArray(inventory?.coverage)) {
  const debtEntry = inventory.coverage.find((entry) => entry?.classification === "debt");
  if (debtEntry) debtEntry.debtIds = ["missing-debt"];
}
if (args.has("--simulate-unknown-protected-surface") && Array.isArray(inventory?.coverage)) {
  inventory.coverage.push({
    id: "simulated-unknown-protected-surface",
    platform: "web",
    scopes: ["web/src/__missing-protected__/**/*.tsx"],
    classification: "protected",
    surfaceIds: ["missing-protected"],
    reason: "Simulated inventory failure for unknown protected surface references.",
  });
}
if (args.has("--simulate-unknown-exception") && Array.isArray(inventory?.coverage)) {
  inventory.coverage.push({
    id: "simulated-unknown-exception",
    platform: "web",
    scopes: ["web/src/__missing-exception__/**/*.tsx"],
    classification: "exception",
    exceptionIds: ["missing-exception"],
    reason: "Simulated inventory failure for unknown exception references.",
  });
}
if (args.has("--simulate-unmatched-coverage-scope") && Array.isArray(inventory?.coverage) && inventory.coverage[0]) {
  inventory.coverage[0].scopes = ["missing/**/*.swift"];
}
if (args.has("--simulate-unsafe-coverage-scope") && Array.isArray(inventory?.coverage) && inventory.coverage[0]) {
  inventory.coverage[0].scopes = ["/Users/example/View.swift"];
}
if (args.has("--simulate-v1-pattern-set-missing-registry") && v1PatternSetDecision) {
  v1PatternSetDecision.publicEvidence = v1PatternSetDecision.publicEvidence.filter(
    (evidencePath) => evidencePath !== "docs/ui/pattern-registry/patterns.registry.json",
  );
}
if (args.has("--simulate-v1-pattern-set-missing-inventory") && v1PatternSetDecision) {
  v1PatternSetDecision.publicEvidence = v1PatternSetDecision.publicEvidence.filter((evidencePath) => evidencePath !== inventoryPath);
}
if (args.has("--simulate-v1-pattern-set-missing-baseline-coverage") && v1PatternSetDecision) {
  v1PatternSetDecision.publicEvidence = v1PatternSetDecision.publicEvidence.filter((evidencePath) => evidencePath !== surfaceBaselineCoveragePath);
}
if (args.has("--simulate-v1-pattern-set-missing-private-baseline") && v1PatternSetDecision) {
  v1PatternSetDecision.privateEvidence = v1PatternSetDecision.privateEvidence.filter(
    (evidenceReference) => evidenceReference !== "private-codex-ui-baselines:surfaces/*",
  );
}
if (args.has("--simulate-v1-pattern-set-missing-private-geometry-platform") && v1PatternSetDecision) {
  v1PatternSetDecision.privateEvidence = v1PatternSetDecision.privateEvidence.filter(
    (evidenceReference) => evidenceReference !== "private-codex-ui-rendered-geometry:web/*",
  );
}
if (args.has("--simulate-v1-pattern-set-missing-private-verifier") && v1PatternSetDecision) {
  v1PatternSetDecision.blockingVerifiers = v1PatternSetDecision.blockingVerifiers.filter(
    (verifier) => verifier !== "scripts/ui_private_geometry_verify.mjs",
  );
}
if (args.has("--simulate-v1-pattern-set-premature-complete") && v1PatternSetDecision) {
  v1PatternSetDecision.status = "verified-complete";
  v1PatternSetDecision.remaining = [];
}
if (args.has("--simulate-approved-v1-pattern-set-stale-decision") && surfaceBaselineCoverage && v1PatternSetDecision) {
  surfaceBaselineCoverage.status = "approved-private-capture";
  v1PatternSetDecision.status = "open";
  v1PatternSetDecision.remaining = ["Simulated stale decision after approved visible inventory screenshots."];
}
if (inventory?.reviewAfter && inventory.reviewAfter < today) {
  fail(`${inventoryPath}.reviewAfter expired on ${inventory.reviewAfter}`);
}

const requiredPlatforms = ["macos", "ios", "android", "web"];
const requiredSourceRoots = [
  "macos/Sources/Clawix",
  "ios/Sources/Clawix",
  "apps/macos/Sources",
  "apps/ios/Sources",
  "android/app/src/main/java/com/example/clawix/android",
  "web/src",
];
const sourceRoots = requireArray(inventory, inventoryPath, "sourceRoots");
for (const sourceRoot of sourceRoots) {
  if (!isSafeRelativePath(sourceRoot)) {
    fail(`${inventoryPath}.sourceRoots must use safe relative paths`);
    continue;
  }
  if (platformFor(sourceRoot) === "unknown") fail(`${inventoryPath}.sourceRoots includes ungoverned root ${sourceRoot}`);
  if (!fs.existsSync(path.join(rootDir, sourceRoot))) fail(`${inventoryPath}.sourceRoots missing root ${sourceRoot}`);
}
for (const sourceRoot of requiredSourceRoots) {
  if (!sourceRoots.includes(sourceRoot)) fail(`${inventoryPath}.sourceRoots must include ${sourceRoot}`);
}
const platformCoverage = new Set();
const coverage = requireArray(inventory, inventoryPath, "coverage");
const compiledCoverage = [];
const coverageIds = new Set();
for (const [index, entry] of coverage.entries()) {
  const label = `${inventoryPath}.coverage[${index}]`;
  requireFields(entry, label, ["id", "platform", "scopes", "classification", "reason"]);
  if (!entry) continue;
  if (coverageIds.has(entry.id)) fail(`${label}.id duplicates ${entry.id}`);
  coverageIds.add(entry.id);
  platformCoverage.add(entry.platform);
  if (!requiredPlatforms.includes(entry.platform)) fail(`${label}.platform is not governed`);
  const scopes = requireArray(entry, label, "scopes");
  const excludeScopes = requireArray(entry, label, "excludeScopes", { nonEmpty: false });
  for (const [scopeIndex, scope] of scopes.entries()) {
    if (!isSafeRelativePath(scope)) fail(`${label}.scopes[${scopeIndex}] must be a safe relative path`);
  }
  for (const [scopeIndex, scope] of excludeScopes.entries()) {
    if (!isSafeRelativePath(scope)) fail(`${label}.excludeScopes[${scopeIndex}] must be a safe relative path`);
  }
  if (!["pattern", "debt", "exception", "protected"].includes(entry.classification)) {
    fail(`${label}.classification must be pattern, debt, exception, or protected`);
  }
  if (entry.classification === "pattern") {
    for (const patternId of requireArray(entry, label, "patterns")) {
      if (!patternIds.has(patternId)) fail(`${label}.patterns references unknown pattern ${patternId}`);
      const platforms = patternPlatforms.get(patternId) || new Set();
      if (platforms.size > 0 && !platforms.has(entry.platform)) {
        fail(`${label}.patterns references ${patternId}, which is not declared for ${entry.platform}`);
      }
    }
  }
  if (entry.classification === "debt") {
    for (const debtId of requireArray(entry, label, "debtIds")) {
      if (!debtIds.has(debtId)) fail(`${label}.debtIds references unknown debt ${debtId}`);
    }
  }
  if (entry.classification === "protected") {
    for (const surfaceId of requireArray(entry, label, "surfaceIds")) {
      if (!protectedIds.has(surfaceId)) fail(`${label}.surfaceIds references unknown protected surface ${surfaceId}`);
    }
  }
  if (entry.classification === "exception") {
    for (const exceptionId of requireArray(entry, label, "exceptionIds")) {
      if (!exceptionIds.has(exceptionId)) fail(`${label}.exceptionIds references unknown exception ${exceptionId}`);
    }
  }
  compiledCoverage.push({
    id: entry.id,
    platform: entry.platform,
    classification: entry.classification,
    scopes: scopes.map((scope) => [scope, globToRegExp(scope)]),
    excludeScopes: excludeScopes.map((scope) => [scope, globToRegExp(scope)]),
  });
}

for (const platform of requiredPlatforms) {
  if (!platformCoverage.has(platform)) fail(`${inventoryPath}.coverage must include ${platform}`);
}

const candidates = sourceRoots.flatMap(walk).filter(isVisibleCandidate);
const uncovered = [];
const ambiguous = [];
for (const candidate of candidates) {
  const platform = platformFor(candidate);
  const matches = compiledCoverage.filter((entry) => {
    if (entry.platform !== platform) return false;
    if (entry.excludeScopes.some(([, pattern]) => pattern.test(candidate))) return false;
    return entry.scopes.some(([, pattern]) => pattern.test(candidate));
  });
  if (matches.length === 0) {
    uncovered.push(candidate);
  } else if (matches.length > 1) {
    ambiguous.push({ candidate, matches });
  }
}

if (uncovered.length > 0) {
  fail(
    [
      "visible UI candidates are not mapped in docs/ui/visible-surfaces.inventory.json",
      ...uncovered.slice(0, 80).map((candidate) => `  ${candidate}`),
      uncovered.length > 80 ? `  ...and ${uncovered.length - 80} more` : "",
    ].filter(Boolean).join("\n"),
  );
}

if (ambiguous.length > 0) {
  fail(
    [
      "visible UI candidates must map to exactly one inventory classification",
      ...ambiguous.slice(0, 80).map(({ candidate, matches }) => (
        `  ${candidate}: ${matches.map((entry) => `${entry.id}:${entry.classification}`).join(", ")}`
      )),
      ambiguous.length > 80 ? `  ...and ${ambiguous.length - 80} more` : "",
    ].filter(Boolean).join("\n"),
  );
}

requireFields(surfaceBaselineCoverage, surfaceBaselineCoveragePath, ["status", "coverage"]);
if (!v1PatternSetDecision) {
  fail(`${decisionVerificationPath}.decisions must include v1_pattern_set`);
} else {
  const publicEvidence = new Set(Array.isArray(v1PatternSetDecision.publicEvidence) ? v1PatternSetDecision.publicEvidence : []);
  for (const evidencePath of [
    "docs/ui/pattern-registry/patterns.registry.json",
    inventoryPath,
    surfaceBaselineCoveragePath,
    "scripts/ui_surface_inventory_check.mjs",
    "scripts/ui_surface_baseline_coverage_check.mjs",
    "scripts/ui_private_evidence_plan_check.mjs",
    "scripts/ui_private_evidence_verify.mjs",
  ]) {
    if (!publicEvidence.has(evidencePath)) {
      fail(`${decisionVerificationPath}.decisions.v1_pattern_set.publicEvidence must include ${evidencePath}`);
    }
  }
  const privateEvidence = new Set(Array.isArray(v1PatternSetDecision.privateEvidence) ? v1PatternSetDecision.privateEvidence : []);
  for (const evidenceReference of [
    "private-codex-ui-baselines:surfaces/*",
    "private-codex-ui-rendered-geometry:macos/*",
    "private-codex-ui-rendered-geometry:ios/*",
    "private-codex-ui-rendered-geometry:android/*",
    "private-codex-ui-rendered-geometry:web/*",
  ]) {
    if (!privateEvidence.has(evidenceReference)) {
      fail(`${decisionVerificationPath}.decisions.v1_pattern_set.privateEvidence must include ${evidenceReference}`);
    }
  }
  const blockingVerifiers = new Set(Array.isArray(v1PatternSetDecision.blockingVerifiers) ? v1PatternSetDecision.blockingVerifiers : []);
  for (const verifier of [
    "scripts/ui_private_evidence_verify.mjs",
    "scripts/ui_private_baseline_verify.mjs",
    "scripts/ui_private_geometry_verify.mjs",
  ]) {
    if (!blockingVerifiers.has(verifier)) {
      fail(`${decisionVerificationPath}.decisions.v1_pattern_set.blockingVerifiers must include ${verifier}`);
    }
  }
  if (surfaceBaselineCoverage?.status !== "approved-private-capture" && !["open", "blocked-external-pending"].includes(v1PatternSetDecision.status)) {
    fail(`${decisionVerificationPath}.decisions.v1_pattern_set.status must remain open or blocked-external-pending until visible inventory has approved private rendered screenshots`);
  }
  if (surfaceBaselineCoverage?.status !== "approved-private-capture" && (!Array.isArray(v1PatternSetDecision.remaining) || v1PatternSetDecision.remaining.length === 0)) {
    fail(`${decisionVerificationPath}.decisions.v1_pattern_set.remaining must describe pending approved private rendered screenshots`);
  }
  if (surfaceBaselineCoverage?.status === "approved-private-capture" && v1PatternSetDecision.status !== "verified-complete") {
    fail(`${decisionVerificationPath}.decisions.v1_pattern_set.status must be verified-complete after visible inventory has approved private rendered screenshots`);
  }
  if (surfaceBaselineCoverage?.status === "approved-private-capture" && Array.isArray(v1PatternSetDecision.remaining) && v1PatternSetDecision.remaining.length > 0) {
    fail(`${decisionVerificationPath}.decisions.v1_pattern_set.remaining must be empty after visible inventory has approved private rendered screenshots`);
  }
}

if (errors.length > 0) {
  console.error("UI surface inventory check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

if (!isSelfTest && rawArgs.length === 0) {
  const selfTests = [
    ["--unknown-flag", "received unknown flag --unknown-flag"],
    ["--simulate-expired-review-after", "reviewAfter expired"],
    ["--simulate-unsafe-source-root", "sourceRoots must use safe relative paths"],
    ["--simulate-missing-required-source-root", "sourceRoots must include web/src"],
    ["--simulate-unsupported-platform", "platform is not governed"],
    ["--simulate-invalid-classification", "classification must be pattern, debt, exception, or protected"],
    ["--simulate-unknown-pattern", "patterns references unknown pattern missing-pattern"],
    ["--simulate-unsafe-coverage-scope", "scopes[0] must be a safe relative path"],
    ["--simulate-v1-pattern-set-missing-private-verifier", "blockingVerifiers must include scripts/ui_private_geometry_verify.mjs"],
    ["--simulate-v1-pattern-set-premature-complete", "status must remain open or blocked-external-pending until visible inventory has approved private rendered screenshots"],
  ];
  const scriptPath = path.relative(rootDir, new URL(import.meta.url).pathname);
  for (const [flag, expectedOutput] of selfTests) {
    const result = spawnSync(process.execPath, [scriptPath, flag], {
      cwd: rootDir,
      encoding: "utf8",
      env: { ...process.env, CLAWIX_UI_SURFACE_INVENTORY_SELF_TEST: "1" },
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status === 0 || !output.includes(expectedOutput)) {
      console.error(`UI surface inventory self-test failed for ${flag}.`);
      if (output) console.error(output.trim());
      process.exit(1);
    }
  }
}

console.log(`UI surface inventory check passed (${candidates.length} visible candidates)`);
