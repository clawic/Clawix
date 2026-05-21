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
  ]],
  ["docs/adr/0022-performance-governance-mirror.md", [
    "Status: Accepted",
    "Performance means whole-computer resource behavior",
    "## Performance Impact",
    "adr:performance-governance",
  ]],
  ["docs/governance/performance-governance.md", [
    "whole-computer resource behavior",
    "## Required Impact Classification",
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
    "docs/adr/0022-performance-governance-mirror.md",
    "scripts/performance_governance_check.mjs",
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
