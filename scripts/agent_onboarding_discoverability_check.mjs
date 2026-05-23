#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = new Set(process.argv.slice(2));
const runCli = args.has("--cli");

function read(relativePath) {
  return fs.readFileSync(path.join(rootDir, relativePath), "utf8");
}

function readJson(relativePath) {
  return JSON.parse(read(relativePath));
}

function requireFile(errors, relativePath) {
  if (!fs.existsSync(path.join(rootDir, relativePath))) {
    errors.push(`missing ${relativePath}`);
    return "";
  }
  return read(relativePath);
}

function requireSnippet(errors, relativePath, snippet) {
  const text = requireFile(errors, relativePath);
  if (text && !text.includes(snippet)) errors.push(`${relativePath}: missing ${JSON.stringify(snippet)}`);
}

function flattenJson(value) {
  return JSON.stringify(value);
}

function runClaw(errors, command, expected) {
  const result = spawnSync("claw", command, {
    cwd: rootDir,
    encoding: "utf8",
    timeout: 20000,
    maxBuffer: 1024 * 1024,
  });
  if (result.status !== 0) {
    errors.push(`claw ${command.join(" ")} failed: ${(result.stderr || result.stdout).trim()}`);
    return;
  }
  let parsed;
  try {
    parsed = JSON.parse(result.stdout);
  } catch (error) {
    errors.push(`claw ${command.join(" ")} did not return JSON: ${error instanceof Error ? error.message : String(error)}`);
    return;
  }
  if (!flattenJson(parsed).includes(expected)) {
    errors.push(`claw ${command.join(" ")} output did not include ${expected}`);
  }
}

const errors = [];
const onboardingPath = "docs/agent-onboarding.md";
const onboarding = requireFile(errors, onboardingPath);

for (const snippet of [
  "# Agent Onboarding And Work Playbooks",
  "## First Ten Minutes",
  "## Work Families",
  "## Prompt Starters",
  "## Closure Checklist",
  "Work family | Start here | Canonical documents | Minimum validation | Decision boundary | Closure criteria | Discoverability smoke",
  "Canon, governance, or ADR work",
  "Agent instructions, onboarding, or docs alignment",
  "Framework/host boundary or Clawix/ClawJS integration",
  "Surface, route, bridge, CLI, or protocol work",
  "Storage, data placement, catalogs, or persistence",
  "Native permissions, approvals, grants, secrets, or audit",
  "Visible UI, accessibility, localization, or visual canon",
  "Platform launch, visible app bug, or host-dependent validation",
  "Performance, slowness, freezes, memory, or hot paths",
  "External integration, connector, provider, sync, remote, or live service work",
  "Code hygiene, source shape, package surface, or refactor",
  "Release, publication, signing, or distribution",
]) {
  if (onboarding && !onboarding.includes(snippet)) errors.push(`${onboardingPath}: missing ${JSON.stringify(snippet)}`);
}

for (const [relativePath, snippet] of [
  ["AGENTS.md", onboardingPath],
  ["docs/agent-rules/index.md", onboardingPath],
  ["docs/decision-map.md", onboardingPath],
  ["docs/decision-map.md", "agent_onboarding_discoverability_check.mjs"],
  ["playbooks/README.md", onboardingPath],
  ["playbooks/agent-fast-validation.md", "agent-onboarding-discoverability"],
  ["qa/agent-fast-validation.matrix.json", "agent-onboarding-discoverability"],
  ["docs/discoverability.md", "clawix-agent-onboarding-playbook"],
  ["docs/discoverability.md", onboardingPath],
]) {
  requireSnippet(errors, relativePath, snippet);
}

const registry = readJson("docs/discoverability.registry.json");
const onboardingArtifact = registry.artifacts?.find((artifact) => artifact.id === "clawix-agent-onboarding-playbook");
if (!onboardingArtifact) {
  errors.push("docs/discoverability.registry.json: missing clawix-agent-onboarding-playbook");
} else {
  if (onboardingArtifact.canonicalSource !== onboardingPath) errors.push("clawix-agent-onboarding-playbook canonicalSource must be docs/agent-onboarding.md");
  for (const entrypoint of ["AGENTS.md", "CLAUDE.md", "docs/discoverability.md", "docs/decision-map.md"]) {
    if (!onboardingArtifact.requiredEntrypoints?.includes(entrypoint)) {
      errors.push(`clawix-agent-onboarding-playbook missing entrypoint ${entrypoint}`);
    }
  }
  const queryText = JSON.stringify(onboardingArtifact.searchQueries ?? []);
  if (!queryText.includes("agent onboarding playbook")) {
    errors.push("clawix-agent-onboarding-playbook missing agent onboarding playbook search query");
  }
}

if (runCli) {
  runClaw(errors, ["inspect", "why", "clawix-agent-onboarding-playbook", "--json"], onboardingPath);
  runClaw(
    errors,
    ["search", "query", "agent onboarding playbook", "--source-set", "full", "--file-root", rootDir, "--limit", "20", "--json"],
    onboardingPath,
  );
}

if (errors.length > 0) {
  console.error("agent onboarding discoverability check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.error(`agent onboarding discoverability check passed${runCli ? " with claw CLI smoke" : ""}`);

