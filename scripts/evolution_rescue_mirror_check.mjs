#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const siblingClawjs = path.resolve(rootDir, "../../clawjs");
const errors = [];
const args = new Set(process.argv.slice(2));

if (args.has("--self-test")) {
  runSelfTest();
  process.exit(0);
}

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
  "macos/Tests/ClawixMeshTests/RescueSurvivalMatrixTests.swift",
  "macos/Tests/ClawixMeshTests/RescueRepairContextTests.swift",
  "macos/Tests/ClawixMeshTests/RescueChatFallbackTests.swift",
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
requireSnippet("docs/agent-rules/index.md", "compatibility-evolution-work");
requireSnippet("docs/decision-map.md", "Evolution and rescue backbone mirror");
requireSnippet("scripts/check-clawjs-skills-sync.mjs", "\"compatibility-evolution-work\"");
for (const snippet of [
  "ephemeralChat",
  "diagnosticsOnly",
  "migrationFailure",
  "bridgeRuntimeDown",
  "highCPU",
  "highMemory",
  "RescueRepairStatusSummary",
  "RescueRuntimeSignalMapper",
  "RescueRuntimeSignalDetector",
  "RescueRuntimeHealthThresholds",
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
requireSnippet("macos/Sources/Clawix/AppState.swift", "rescueDecision");
requireSnippet("macos/Sources/Clawix/AppState.swift", "ResourceSampler.latestHealthSnapshot");
requireSnippet("macos/Sources/Clawix/AppState/MessageSending.swift", "handleRescueChatUnavailableIfNeeded");
requireSnippet("macos/Sources/Clawix/AppState/ConversationActions.swift", "handleRescueChatUnavailableIfNeeded");
requireSnippet("macos/Sources/Clawix/SidebarView.swift", "RescueRepairSidebarButton");
requireSnippet("macos/Sources/Clawix/SidebarView.swift", "RescueRepairStatusSummary(decision: appState.rescueDecision)");
requireSnippet("macos/Sources/Clawix/Diagnostics/ResourceSampler.swift", "latestHealthSnapshot");
requireSnippet("macos/Sources/Clawix/Diagnostics/ResourceSampler.swift", "persistedHealthSnapshot");
requireSnippet("macos/Sources/Clawix/AppState/Routes.swift", "case rescue");
requireSnippet("macos/Sources/Clawix/AppState/DeepLinks.swift", "openRescueDeepLink");
requireSnippet("macos/Sources/Clawix/AppState/DeepLinks.swift", "openRescueSurface(exportDiagnostics: true)");
requireSnippet("macos/Sources/Clawix/AppState/DeepLinks.swift", "SettingsUtilities.revealDiagnosticsFolder()");
requireSnippet("macos/Sources/Clawix/Rescue/RescueDiagnosticsView.swift", "SettingsUtilities.revealDiagnosticsFolder()");
for (const snippet of [
  "failed_migration",
  "partial_storage",
  "bridge_runtime_down_with_alternate_runtime",
  "startup_cpu_hang_circuit_breaker",
  "testNoRuntimeMatrixFallsBackToLocalDiagnosticsWithoutBlockingLaunch",
]) requireSnippet("macos/Tests/ClawixMeshTests/RescueSurvivalMatrixTests.swift", snippet);
requireSnippet("docs/evolution/README.md", "rescue-context.json");
requireSnippet("docs/evolution/README.md", "discreet");
requireSnippet("../scripts-dev/clawix-launcher.sh", "open-rescue");
requireSnippet("../scripts-dev/clawix-launcher.sh", "clawix://rescue");

if (fs.existsSync(siblingClawjs)) {
  const siblingAdr = path.join(siblingClawjs, "docs/adr/0030-post-v1-evolution-rescue-backbone.md");
  const siblingLedger = path.join(siblingClawjs, "docs/evolution/baseline.json");
  const siblingPackage = path.join(siblingClawjs, "package.json");
  if (!fs.existsSync(siblingAdr)) errors.push("sibling ClawJS ADR 0030 is missing");
  if (!fs.existsSync(siblingLedger)) errors.push("sibling ClawJS evolution ledger is missing");
  if (!fs.existsSync(siblingPackage)) errors.push("sibling ClawJS package.json is missing");
  if (fs.existsSync(siblingPackage)) runSiblingEvolutionGate();
}

runRescueSurvivalMatrixGate();

if (errors.length > 0) {
  console.error("Clawix evolution rescue mirror check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("Clawix evolution rescue mirror check passed");

function runSiblingEvolutionGate() {
  const timeout = parsePositiveIntegerEnv("CLAWIX_EVOLUTION_SIBLING_GATE_TIMEOUT_MS", 5 * 60 * 1000);
  const result = spawnSync("npm", ["run", "test:evolution", "--silent"], {
    cwd: siblingClawjs,
    encoding: "utf8",
    maxBuffer: 20 * 1024 * 1024,
    timeout,
    killSignal: "SIGTERM",
  });
  if (result.status !== 0) {
    errors.push(spawnFailureMessage("sibling ClawJS evolution gate", result, timeout));
  }
}

function runRescueSurvivalMatrixGate() {
  const scratchPath =
    process.env.CLAWIX_RESCUE_SWIFTPM_SCRATCH_PATH || path.join("/tmp", `clawix-rescue-survival-matrix-${process.pid}`);
  const result = spawnSync("swift", [
    "test",
    "--disable-sandbox",
    "--package-path",
    "macos",
    "--scratch-path",
    scratchPath,
    "--jobs",
    "1",
    "--filter",
    "RescueSurvivalMatrixTests",
  ], {
    cwd: rootDir,
    encoding: "utf8",
    maxBuffer: 20 * 1024 * 1024,
  });
  if (result.status !== 0) {
    errors.push(spawnFailureMessage("Clawix rescue survival matrix", result));
  }
}

function parsePositiveIntegerEnv(name, fallback) {
  const raw = process.env[name];
  if (!raw) return fallback;
  const value = Number.parseInt(raw, 10);
  if (!Number.isFinite(value) || value <= 0) return fallback;
  return value;
}

function spawnFailureMessage(label, result, timeout) {
  const output = `${result.stdout || ""}${result.stderr || ""}`.trim();
  const timedOut = result.error?.code === "ETIMEDOUT";
  const statusDetail = timedOut && timeout
    ? ` timed out after ${timeout}ms`
    : result.signal
      ? ` terminated by ${result.signal}`
      : "";
  return `${label} failed${statusDetail}${output ? `:\n${output}` : ""}`;
}

function runSelfTest() {
  const message = spawnFailureMessage(
    "self-test gate",
    { stdout: "", stderr: "late output", error: Object.assign(new Error("timed out"), { code: "ETIMEDOUT" }) },
    7,
  );
  if (!message.includes("self-test gate failed timed out after 7ms")) {
    console.error("self-test failed: timeout status was not reported");
    process.exit(1);
  }
  if (!message.includes("late output")) {
    console.error("self-test failed: child output was not preserved");
    process.exit(1);
  }
  console.log("evolution rescue mirror check self-test passed");
}
