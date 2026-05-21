#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = new Set(process.argv.slice(2));
const failures = [];
const overrides = new Map();

function read(relativePath) {
  return fs.readFileSync(path.join(rootDir, relativePath), "utf8");
}

function fail(message) {
  failures.push(message);
}

function requireSnippet(relativePath, snippet) {
  const content = overrides.get(relativePath) ?? read(relativePath);
  if (!content.includes(snippet)) fail(`${relativePath} must include ${JSON.stringify(snippet)}`);
}

if (args.has("--simulate-missing-mirror")) {
  overrides.set("docs/governance/performance-governance.md", read("docs/governance/performance-governance.md").replace("whole-computer resource behavior", "latency only"));
}

for (const [relativePath, snippets] of new Map([
  ["CONSTITUTION.md", [
    "The computer's resources are product correctness",
    "CPU, RAM, GPU/Neural Engine, disk, network, battery, thermals",
    "boundedness, lazy startup, cancellation, backpressure, windowing, and idle quiescence",
  ]],
  ["docs/adr/0022-performance-governance-mirror.md", [
    "Status: Accepted",
    "Performance means whole-computer resource behavior",
    "Windowing/Pagination by Default",
    "Resource Contract is required for Clawix implementation closure",
    "docs/boundedness-baseline.json",
    "Idle Quiescence Contract P1",
    "docs/idle-quiescence.manifest.json",
    "docs/surface-resource-contract-clawix-baseline.json",
    "## Performance Impact",
    "adr:performance-governance",
  ]],
  ["docs/adr/0029-streaming-backpressure-bounded-queues-mirror.md", [
    "Status: Accepted",
    "resourceContract.streaming",
    "bounded stream behavior",
  ]],
  ["docs/adr/0030-launch-and-idle-contract-mirror.md", [
    "Status: Accepted",
    "resourceContract.startup",
    "resourceContract.idle",
  ]],
  ["docs/adr/0031-ui-state-invalidation-high-churn-data-boundary-mirror.md", [
    "Status: Accepted",
    "high-churn",
    "local bounded stores",
  ]],
  ["docs/governance/performance-governance.md", [
    "whole-computer resource behavior",
    "## Required Impact Classification",
    "## Windowing/Pagination by Default",
    "load all -> filter/sort/render",
    "cursor/window/batch/limit",
    "## Hot Path Guard P1",
    "hot-path-ok",
    "## Idle Quiescence Contract P1",
    "docs/idle-quiescence.manifest.json",
    "## Resource Dimensions",
    "GPU / Neural Engine",
    "## Visual Boundary",
  ]],
  ["docs/performance/startup-release-contract.md", [
    "macos-startup-first-chat-interactive",
    "process_start -> first_chat_interactive",
    "EXTERNAL PENDING",
  ]],
  ["docs/performance/startup-release-contract.manifest.json", [
    "macos-startup-first-chat-interactive",
    "private-codex-startup-baselines",
    "CLAWIX_STARTUP_PRIVATE_BASELINE_ROOT",
  ]],
  ["docs/adr/TEMPLATE.md", [
    "## Performance Impact",
    "CPU, RAM, GPU/Neural Engine, disk, network, battery, thermals",
  ]],
  ["docs/decision-map.md", [
    "Performance Governance",
    "streaming/backpressure",
    "launch/idle",
    "high-churn UI",
    "docs/adr/0022-performance-governance-mirror.md",
    "scripts/performance_governance_check.mjs",
    "scripts/boundedness_guard.mjs",
    "scripts/hot_path_guard.mjs",
    "scripts/idle_quiescence_check.mjs",
    "scripts/surface_resource_contract_guard.mjs",
  ]],
  ["docs/constitution-map.md", [
    "Performance Governance",
    "CPU/RAM/GPU/disk/network/battery",
  ]],
  ["docs/agent-rules/index.md", [
    "Performance governance",
    "performance-governance.md",
  ]],
  ["docs/governance/README.md", [
    "Performance Governance",
  ]],
  ["docs/boundedness-baseline.json", [
    "\"program\": \"boundedness-guard\"",
    "\"entries\"",
  ]],
  ["docs/hot-path-baseline.json", [
    "\"program\": \"hot-path-guard\"",
    "\"entries\"",
  ]],
  ["docs/idle-quiescence.manifest.json", [
    "\"program\": \"idle-quiescence-check\"",
    "\"severity\": \"P1\"",
    "\"visibleOnly\"",
  ]],
  ["scripts/hot_path_guard.mjs", [
    "Hot Path Guard P1",
    "hot-path-ok",
  ]],
  ["scripts/idle_quiescence_check.mjs", [
    "Idle Quiescence Contract P1",
    "diagnosticsOptIn",
  ]],
  ["scripts/boundedness_guard.mjs", [
    "Boundedness Guard P0",
    "buffer-concat",
    "eventbus",
  ]],
  ["PERF.md", [
    "whole-computer resource pressure",
  ]],
  ["macos/PERF.md", [
    "whole-computer resource pressure",
  ]],
  ["skills/performance-investigation/SKILL.md", [
    "CPU, RAM, GPU/Neural Engine, disk, network, battery, thermals",
  ]],
  ["skills/ui-performance-budget/SKILL.md", [
    "CPU, RAM, GPU/Neural Engine, disk, network, battery, thermals",
  ]],
  ["scripts/startup_release_contract_check.mjs", [
    "macos-startup-first-chat-interactive",
    "CLAWIX_STARTUP_PRIVATE_BASELINE_ROOT",
  ]],
])) {
  for (const snippet of snippets) requireSnippet(relativePath, snippet);
}

if (args.has("--self-test")) {
  const { spawnSync } = await import("node:child_process");
  const result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, "--simulate-missing-mirror"], {
    cwd: rootDir,
    encoding: "utf8",
  });
  if (result.status === 0 || !String(result.stderr).includes("docs/governance/performance-governance.md")) {
    fail("self-test failed to catch missing performance governance mirror");
  }
}

if (failures.length > 0) {
  console.error("performance governance check failed:");
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log("performance governance check passed");
