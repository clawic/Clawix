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
  if (nonEmpty && value.length === 0) fail(`${label}.${field} must not be empty`);
  return value;
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
        if ([".build", "build", "dist", "node_modules", "Resources", "Assets.xcassets", "Fonts", "Mocks"].includes(entry.name)) continue;
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

function tokenRegExp(tokens) {
  return new RegExp(tokens.map((token) => token.replace(/[|\\{}()[\]^$+?.]/g, "\\$&")).join("|"), "i");
}

const manifestPath = "docs/ui/state-coverage.manifest.json";
const manifest = readJson(manifestPath);
if (manifest && args.has("--simulate-missing-required-state")) {
  manifest.requiredStates = manifest.requiredStates.filter((state) => state !== "error");
}
if (manifest && args.has("--simulate-unknown-source-token-group")) {
  manifest.sourceTokenGroups = {
    ...manifest.sourceTokenGroups,
    decorative: ["decorative-only"],
  };
}
if (manifest && args.has("--simulate-empty-source-token-group")) {
  manifest.sourceTokenGroups.error = [];
}
if (manifest && args.has("--simulate-missing-source-evidence-token")) {
  manifest.sourceTokenGroups.error = ["codex-state-token-that-does-not-exist"];
}
if (manifest && args.has("--simulate-invalid-gap-status")) {
  manifest.allowedGaps = [
    {
      coverageId: "simulated-state-gap",
      state: "error",
      status: "ready-to-ignore",
      owner: "interface-governance",
      reviewAfter: "2999-12-31",
      reason: "Simulated invalid status must fail state coverage.",
    },
  ];
}
if (manifest && args.has("--simulate-expired-gap")) {
  manifest.allowedGaps = [
    {
      coverageId: "simulated-state-gap",
      state: "error",
      status: "pending-implementation-evidence",
      owner: "interface-governance",
      reviewAfter: "2026-01-01",
      reason: "Simulated expired state coverage gap must fail.",
    },
  ];
}
if (manifest && args.has("--simulate-stale-gap")) {
  manifest.allowedGaps = [
    {
      coverageId: "simulated-state-gap",
      state: "error",
      status: "pending-implementation-evidence",
      owner: "interface-governance",
      reviewAfter: "2999-12-31",
      reason: "Simulated stale state coverage gap must fail.",
    },
  ];
}
if (manifest && args.has("--simulate-unknown-gap-state")) {
  manifest.allowedGaps = [
    {
      coverageId: "simulated-state-gap",
      state: "decorative",
      status: "pending-implementation-evidence",
      owner: "interface-governance",
      reviewAfter: "2999-12-31",
      reason: "Simulated unknown state coverage gap must fail.",
    },
  ];
}
if (manifest && args.has("--simulate-duplicate-gap")) {
  manifest.allowedGaps = [
    {
      coverageId: "simulated-state-gap",
      state: "error",
      status: "pending-implementation-evidence",
      owner: "interface-governance",
      reviewAfter: "2999-12-31",
      reason: "Simulated duplicate state coverage gap must fail.",
    },
    {
      coverageId: "simulated-state-gap",
      state: "error",
      status: "pending-implementation-evidence",
      owner: "interface-governance",
      reviewAfter: "2999-12-31",
      reason: "Simulated duplicate state coverage gap must fail.",
    },
  ];
}
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "inventoryPath",
  "requiredStates",
  "sourceTokenGroups",
  "allowedGapStatuses",
  "allowedGaps",
]);
if (manifest?.status !== "active") fail(`${manifestPath}.status must be active`);

const configPath = "docs/ui/interface-governance.config.json";
const config = readJson(configPath);
const requiredStates = requireArray(config, configPath, "requiredInteractiveStates");
const manifestStates = new Set(requireArray(manifest, manifestPath, "requiredStates"));
for (const state of manifestStates) {
  if (!requiredStates.includes(state)) fail(`${manifestPath}.requiredStates contains unknown state ${state}`);
}
for (const state of Object.keys(manifest?.sourceTokenGroups || {})) {
  if (!requiredStates.includes(state)) fail(`${manifestPath}.sourceTokenGroups contains unknown state ${state}`);
}
for (const state of requiredStates) {
  if (!manifestStates.has(state)) fail(`${manifestPath}.requiredStates must include ${state}`);
  const tokens = manifest?.sourceTokenGroups?.[state];
  if (!Array.isArray(tokens) || tokens.length === 0) fail(`${manifestPath}.sourceTokenGroups.${state} must not be empty`);
}

const inventoryPath = manifest?.inventoryPath || "docs/ui/visible-surfaces.inventory.json";
const inventory = readJson(inventoryPath);
if (inventory && args.has("--simulate-unsafe-source-root")) {
  inventory.sourceRoots = ["/Users/example/Clawix/macos", ...inventory.sourceRoots.slice(1)];
}
if (inventory && args.has("--simulate-unmatched-scope") && Array.isArray(inventory.coverage) && inventory.coverage[0]) {
  inventory.coverage[0] = { ...inventory.coverage[0], scopes: ["missing/state-coverage/**/*.swift"] };
}
if (inventory && args.has("--simulate-unknown-pattern-reference") && Array.isArray(inventory.coverage) && inventory.coverage[0]) {
  inventory.coverage[0] = { ...inventory.coverage[0], classification: "pattern", patterns: ["missing-pattern"] };
}
const sourceRoots = requireArray(inventory, inventoryPath, "sourceRoots");
for (const sourceRoot of sourceRoots) {
  if (sourceRoot.startsWith("/") || sourceRoot.startsWith("~/") || sourceRoot.includes("\\") || sourceRoot.includes("..") || sourceRoot.startsWith("file://") || /^[A-Z]:\\/.test(sourceRoot)) {
    fail(`${inventoryPath}.sourceRoots must use safe relative paths`);
    continue;
  }
  if (!fs.existsSync(path.join(rootDir, sourceRoot))) fail(`${inventoryPath}.sourceRoots missing root ${sourceRoot}`);
}
const patternRegistryPath = "docs/ui/pattern-registry/patterns.registry.json";
const patternRegistry = readJson(patternRegistryPath);
const patternIds = new Set(requireArray(patternRegistry, patternRegistryPath, "patterns"));
const patternStates = new Map();
for (const patternId of patternIds) {
  const patternPath = `docs/ui/pattern-registry/patterns/${patternId}.pattern.json`;
  const pattern = readJson(patternPath);
  if (pattern && args.has("--simulate-pattern-missing-state") && patternId === "sidebar-row") {
    pattern.states = pattern.states.filter((state) => state !== "error");
  }
  patternStates.set(patternId, new Set(requireArray(pattern, patternPath, "states")));
}

const sourceFiles = sourceRoots.flatMap(walk).filter((file) => [".swift", ".kt", ".tsx"].includes(path.extname(file)));

const gapByKey = new Map();
const allowedStatuses = new Set(requireArray(manifest, manifestPath, "allowedGapStatuses"));
for (const [index, gap] of requireArray(manifest, manifestPath, "allowedGaps", { nonEmpty: false }).entries()) {
  const label = `${manifestPath}.allowedGaps[${index}]`;
  requireFields(gap, label, ["coverageId", "state", "status", "owner", "reviewAfter", "reason"]);
  if (!allowedStatuses.has(gap.status)) fail(`${label}.status is not allowed`);
  if (!requiredStates.includes(gap.state)) fail(`${label}.state is not a required interactive state`);
  if (gap.owner !== "interface-governance") fail(`${label}.owner must be interface-governance`);
  if (gap.reviewAfter < today) fail(`${label}.reviewAfter expired on ${gap.reviewAfter}`);
  const key = `${gap.coverageId}:${gap.state}`;
  if (gapByKey.has(key)) fail(`${label} duplicates state coverage gap ${key}`);
  gapByKey.set(key, gap);
}

const missingKeys = new Set();
for (const [index, entry] of requireArray(inventory, inventoryPath, "coverage").entries()) {
  const label = `${inventoryPath}.coverage[${index}]`;
  requireFields(entry, label, ["id", "scopes", "classification"]);
  if (entry.classification === "pattern") {
    for (const patternId of requireArray(entry, label, "patterns")) {
      const states = patternStates.get(patternId);
      if (!states) fail(`${label}.patterns references unknown pattern ${patternId}`);
      for (const state of requiredStates) {
        if (states && !states.has(state)) fail(`docs/ui/pattern-registry/patterns/${patternId}.pattern.json.states must include ${state}`);
      }
    }
  }

  const matchers = requireArray(entry, label, "scopes").map(globToRegExp);
  const matchedFiles = sourceFiles.filter((file) => matchers.some((matcher) => matcher.test(file)));
  if (matchedFiles.length === 0) fail(`${label}.scopes must match at least one source file`);
  const text = matchedFiles.map((file) => fs.readFileSync(path.join(rootDir, file), "utf8")).join("\n");
  for (const state of requiredStates) {
    if (state === "idle") continue;
    const tokens = manifest.sourceTokenGroups[state] || [];
    if (!tokenRegExp(tokens).test(text)) {
      const key = `${entry.id}:${state}`;
      missingKeys.add(key);
      if (!gapByKey.has(key)) fail(`${label} has no source evidence for state ${state}`);
    }
  }
}

for (const key of gapByKey.keys()) {
  if (!missingKeys.has(key)) fail(`${manifestPath}.allowedGaps contains stale gap ${key}`);
}

if (errors.length > 0) {
  console.error("UI state coverage check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("UI state coverage check passed");
