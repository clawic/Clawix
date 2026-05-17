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

const manifestPath = "docs/ui/pattern-performance.manifest.json";
const manifest = readJson(manifestPath);
if (manifest) {
  if (args.has("--simulate-wrong-pattern-registry-path")) {
    manifest.patternRegistryPath = "docs/ui/pattern-registry/other.registry.json";
  }
  if (args.has("--simulate-wrong-budget-registry-path")) {
    manifest.performanceBudgetRegistryPath = "docs/ui/other-performance-budgets.registry.json";
  }
  if (args.has("--simulate-wrong-private-baseline-alias")) {
    manifest.privateBaselineAlias = "local-private-baselines";
  }
  if (args.has("--simulate-missing-flow-mapping") && Array.isArray(manifest.requiredFlowMappings)) {
    manifest.requiredFlowMappings = manifest.requiredFlowMappings.filter(
      (mapping) => mapping.flowId !== "chat-scroll",
    );
  }
  if (args.has("--simulate-duplicate-flow-mapping") && Array.isArray(manifest.requiredFlowMappings) && manifest.requiredFlowMappings[0]) {
    manifest.requiredFlowMappings.push({ ...manifest.requiredFlowMappings[0] });
  }
  if (args.has("--simulate-unknown-pattern-mapping") && Array.isArray(manifest.requiredFlowMappings) && manifest.requiredFlowMappings[0]) {
    manifest.requiredFlowMappings[0] = {
      ...manifest.requiredFlowMappings[0],
      patterns: [...(manifest.requiredFlowMappings[0].patterns || []), "missing-performance-pattern"],
    };
  }
  if (args.has("--simulate-duplicate-mapping-pattern") && Array.isArray(manifest.requiredFlowMappings) && manifest.requiredFlowMappings[0]) {
    manifest.requiredFlowMappings[0] = {
      ...manifest.requiredFlowMappings[0],
      patterns: [
        ...(manifest.requiredFlowMappings[0].patterns || []),
        (manifest.requiredFlowMappings[0].patterns || [])[0],
      ],
    };
  }
}
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "patternRegistryPath",
  "performanceBudgetRegistryPath",
  "privateBaselineAlias",
  "requiredFlowMappings",
]);
if (manifest?.status !== "active") fail(`${manifestPath}.status must be active`);
if (manifest?.patternRegistryPath !== "docs/ui/pattern-registry/patterns.registry.json") {
  fail(`${manifestPath}.patternRegistryPath must be docs/ui/pattern-registry/patterns.registry.json`);
}
if (manifest?.performanceBudgetRegistryPath !== "docs/ui/performance-budgets.registry.json") {
  fail(`${manifestPath}.performanceBudgetRegistryPath must be docs/ui/performance-budgets.registry.json`);
}
if (manifest?.privateBaselineAlias !== "private-codex-ui-baselines") {
  fail(`${manifestPath}.privateBaselineAlias must be private-codex-ui-baselines`);
}

const registryPath = manifest?.patternRegistryPath || "docs/ui/pattern-registry/patterns.registry.json";
const registry = readJson(registryPath);
const patternIds = requireUniqueStrings(requireArray(registry, registryPath, "patterns"), `${registryPath}.patterns`);

const budgetsPath = manifest?.performanceBudgetRegistryPath || "docs/ui/performance-budgets.registry.json";
const budgets = readJson(budgetsPath);
if (budgets && args.has("--simulate-missing-budget-platform") && Array.isArray(budgets.flows)) {
  budgets.flows = budgets.flows.filter((flow) => !(flow.id === "chat-scroll" && flow.platform === "web"));
}
const budgetFlows = new Set(requireArray(budgets, budgetsPath, "flows").map((flow) => flow.id));
const budgetPlatforms = new Map();
for (const flow of requireArray(budgets, budgetsPath, "flows")) {
  if (!flow?.id || !flow?.platform) continue;
  const platforms = budgetPlatforms.get(flow.id) || new Set();
  platforms.add(flow.platform);
  budgetPlatforms.set(flow.id, platforms);
}

const mappedFlows = new Set();
for (const [index, mapping] of requireArray(manifest, manifestPath, "requiredFlowMappings").entries()) {
  const label = `${manifestPath}.requiredFlowMappings[${index}]`;
  requireFields(mapping, label, ["flowId", "patterns"]);
  if (mappedFlows.has(mapping?.flowId)) fail(`${label}.flowId must be unique`);
  if (!budgetFlows.has(mapping?.flowId)) fail(`${label}.flowId must exist in ${budgetsPath}`);
  mappedFlows.add(mapping?.flowId);
  const mappingPlatforms = new Set();
  for (const patternId of requireUniqueStrings(requireArray(mapping, label, "patterns"), `${label}.patterns`)) {
    if (!patternIds.has(patternId)) {
      fail(`${label}.patterns references unknown pattern ${patternId}`);
      continue;
    }
    const patternPath = `docs/ui/pattern-registry/patterns/${patternId}.pattern.json`;
    const pattern = readJson(patternPath);
    if (pattern && args.has("--simulate-pattern-missing-critical-flow") && patternId === "chat-surface") {
      pattern.performance = {
        ...(pattern.performance || {}),
        criticalFlows: [],
      };
    }
    if (pattern && args.has("--simulate-pattern-wrong-budget-registry") && patternId === "sidebar-row") {
      pattern.performance = {
        ...(pattern.performance || {}),
        budgetRegistry: "docs/ui/other-performance-budgets.registry.json",
      };
    }
    if (pattern && args.has("--simulate-pattern-wrong-private-baseline-alias") && patternId === "sidebar-row") {
      pattern.performance = {
        ...(pattern.performance || {}),
        privateBaselineAlias: "private-other-baselines",
      };
    }
    if (pattern && args.has("--simulate-pattern-missing-platform") && patternId === "chat-surface") {
      pattern.platforms = (pattern.platforms || []).filter((platform) => platform !== "web");
    }
    for (const platform of requireUniqueStrings(requireArray(pattern, patternPath, "platforms"), `${patternPath}.platforms`)) {
      mappingPlatforms.add(platform);
    }
    const performance = pattern?.performance || {};
    if (pattern && args.has("--simulate-pattern-duplicate-critical-flow") && patternId === "sidebar-row") {
      performance.criticalFlows = [...(performance.criticalFlows || []), "sidebar-hover-click-expand"];
    }
    if (pattern && args.has("--simulate-pattern-empty-critical-flow") && patternId === "sidebar-row") {
      performance.criticalFlows = [...(performance.criticalFlows || []), ""];
    }
    requireFields(performance, `${patternPath}.performance`, [
      "criticalFlows",
      "budgetRegistry",
      "privateBaselineAlias",
    ]);
    if (performance.budgetRegistry !== budgetsPath) {
      fail(`${patternPath}.performance.budgetRegistry must be ${budgetsPath}`);
    }
    if (performance.privateBaselineAlias !== manifest.privateBaselineAlias) {
      fail(`${patternPath}.performance.privateBaselineAlias must match ${manifestPath}`);
    }
    const criticalFlows = requireUniqueStrings(
      requireArray(performance, `${patternPath}.performance`, "criticalFlows", { nonEmpty: false }),
      `${patternPath}.performance.criticalFlows`,
    );
    if (!criticalFlows.has(mapping.flowId)) {
      fail(`${patternPath}.performance.criticalFlows must include ${mapping.flowId}`);
    }
  }
  for (const platform of budgetPlatforms.get(mapping.flowId) || []) {
    if (!mappingPlatforms.has(platform)) {
      fail(`${label}.patterns must include at least one pattern declared for ${platform}`);
    }
  }
}

for (const flow of budgetFlows) {
  if (!mappedFlows.has(flow)) fail(`${manifestPath}.requiredFlowMappings must map critical flow ${flow}`);
}
for (const [flow, platforms] of budgetPlatforms.entries()) {
  for (const platform of ["macos", "ios", "android", "web"]) {
    if (!platforms.has(platform)) fail(`${budgetsPath}.flows must include ${platform}:${flow}`);
  }
}

for (const patternId of patternIds) {
  const patternPath = `docs/ui/pattern-registry/patterns/${patternId}.pattern.json`;
  const pattern = readJson(patternPath);
  if (pattern && args.has("--simulate-pattern-unknown-critical-flow") && patternId === "sidebar-row") {
    pattern.performance = {
      ...(pattern.performance || {}),
      criticalFlows: [...(pattern.performance?.criticalFlows || []), "unknown-critical-flow"],
    };
  }
  const performance = pattern?.performance || {};
  if (pattern && args.has("--simulate-pattern-duplicate-critical-flow") && patternId === "sidebar-row") {
    performance.criticalFlows = [...(performance.criticalFlows || []), "sidebar-hover-click-expand"];
  }
  if (pattern && args.has("--simulate-pattern-empty-critical-flow") && patternId === "sidebar-row") {
    performance.criticalFlows = [...(performance.criticalFlows || []), ""];
  }
  requireFields(performance, `${patternPath}.performance`, [
    "criticalFlows",
    "budgetRegistry",
    "privateBaselineAlias",
  ]);
  if (performance.budgetRegistry !== budgetsPath) {
    fail(`${patternPath}.performance.budgetRegistry must be ${budgetsPath}`);
  }
  if (performance.privateBaselineAlias !== manifest?.privateBaselineAlias) {
    fail(`${patternPath}.performance.privateBaselineAlias must be ${manifestPath}.privateBaselineAlias`);
  }
  for (const flowId of requireUniqueStrings(
    requireArray(performance, `${patternPath}.performance`, "criticalFlows", { nonEmpty: false }),
    `${patternPath}.performance.criticalFlows`,
  )) {
    if (!budgetFlows.has(flowId)) fail(`${patternPath}.performance.criticalFlows references unknown flow ${flowId}`);
  }
}

if (errors.length > 0) {
  console.error("UI pattern performance check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI pattern performance check passed (${mappedFlows.size} critical flows, ${patternIds.size} patterns)`);
