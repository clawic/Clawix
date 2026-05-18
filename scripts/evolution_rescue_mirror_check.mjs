#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const siblingClawjs = path.resolve(rootDir, "../../clawjs");
const errors = [];

function read(relativePath) {
  return fs.readFileSync(path.join(rootDir, relativePath), "utf8");
}

function requireFile(relativePath) {
  if (!fs.existsSync(path.join(rootDir, relativePath))) errors.push(`missing ${relativePath}`);
}

function requireSnippet(relativePath, snippet) {
  if (!read(relativePath).includes(snippet)) errors.push(`${relativePath} is missing ${JSON.stringify(snippet)}`);
}

for (const file of [
  "docs/adr/0018-evolution-rescue-backbone-mirror.md",
  "docs/evolution/README.md",
  "skills/compatibility-evolution-work/SKILL.md",
  "macos/Sources/Clawix/Rescue/RescueSurvivalPolicy.swift",
  "macos/Sources/Clawix/Rescue/RescueRepairContext.swift",
  "macos/Tests/ClawixMeshTests/RescueSurvivalPolicyTests.swift",
  "macos/Tests/ClawixMeshTests/RescueRepairContextTests.swift",
]) requireFile(file);

for (const snippet of [
  "launch, chat, and repair",
  "claw evolution",
  "compatibility-evolution-work",
  "0030-post-v1-evolution-rescue-backbone",
]) {
  requireSnippet("docs/adr/0018-evolution-rescue-backbone-mirror.md", snippet);
  requireSnippet("docs/evolution/README.md", snippet);
}

requireSnippet("CONSTITUTION.md", "launch, chat, and agent-readable repair context");
requireSnippet("AGENTS.md", "compatibility-evolution-work");
requireSnippet("docs/decision-map.md", "Evolution and rescue backbone mirror");
requireSnippet("scripts/check-clawjs-skills-sync.mjs", "\"compatibility-evolution-work\"");
for (const snippet of [
  "ephemeralChat",
  "diagnosticsOnly",
  "migrationFailure",
  "bridgeRuntimeDown",
  "highCPU",
  "highMemory",
]) requireSnippet("macos/Sources/Clawix/Rescue/RescueSurvivalPolicy.swift", snippet);

for (const snippet of [
  "RescueRepairContextPackage",
  "RescueRepairContextExporter",
  "RescueEvolutionCommandClient",
  "claw evolution doctor",
  "claw evolution repair",
  "rescue-context.json",
  "explicit_approval_only",
  "offline_unavailable",
  "redacted",
]) requireSnippet("macos/Sources/Clawix/Rescue/RescueRepairContext.swift", snippet);

requireSnippet("macos/Sources/Clawix/Settings/SettingsView+Controls.swift", "RescueRepairContextExporter.writeCurrentRescueContext");
requireSnippet("docs/evolution/README.md", "rescue-context.json");

if (fs.existsSync(siblingClawjs)) {
  const siblingAdr = path.join(siblingClawjs, "docs/adr/0030-post-v1-evolution-rescue-backbone.md");
  const siblingLedger = path.join(siblingClawjs, "docs/evolution/baseline.json");
  if (!fs.existsSync(siblingAdr)) errors.push("sibling ClawJS ADR 0030 is missing");
  if (!fs.existsSync(siblingLedger)) errors.push("sibling ClawJS evolution ledger is missing");
}

if (errors.length > 0) {
  console.error("Clawix evolution rescue mirror check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("Clawix evolution rescue mirror check passed");
