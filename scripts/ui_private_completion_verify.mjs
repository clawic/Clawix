#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { enforcePrivateVerifierArgs } from "./ui_private_verifier_args.mjs";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = process.argv.slice(2);

function hasFlag(name) {
  return args.includes(name);
}

function readJson(relativePath) {
  return JSON.parse(fs.readFileSync(path.join(rootDir, relativePath), "utf8"));
}

function runPublicPrerequisites(manifest) {
  if (hasFlag("--skip-public-prerequisites")) return;
  for (const script of manifest.publicPrerequisiteScripts || []) {
    runScript(script, []);
  }
}

function runScript(script, scriptArgs = ["--require-approved"]) {
  const result = spawnSync(process.execPath, [path.join(rootDir, script), ...scriptArgs], {
    cwd: rootDir,
    env: process.env,
    encoding: "utf8",
  });
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.status !== 0) {
    console.error(`UI private completion verification failed at ${script}.`);
    process.exit(result.status || 1);
  }
}

if (!hasFlag("--require-approved")) {
  console.error("UI private completion verification requires --require-approved.");
  process.exit(1);
}
enforcePrivateVerifierArgs(args, {
  label: "UI private completion verification",
  allowedFlags: [
    "--require-approved",
    "--skip-public-prerequisites",
    "--simulate-no-open-decisions",
    "--simulate-missing-decision-blocker",
    "--simulate-stale-decision-blocker",
  ],
  testOnlyFlags: ["--simulate-no-open-decisions", "--simulate-missing-decision-blocker", "--simulate-stale-decision-blocker"],
  testOnlyEnv: "CLAWIX_UI_ALLOW_COMPLETION_SIMULATION",
});

const manifest = readJson("docs/ui/completion-gate.manifest.json");
runPublicPrerequisites(manifest);
const decisionVerification = readJson(manifest.decisionVerificationPath || "docs/ui/decision-verification.json");
const privateVisualValidation = readJson(manifest.privateVisualValidationManifestPath || "docs/ui/private-visual-validation.manifest.json");
if (hasFlag("--simulate-missing-decision-blocker") && Array.isArray(privateVisualValidation.decisionBlockers)) {
  privateVisualValidation.decisionBlockers = privateVisualValidation.decisionBlockers.filter((decisionId) => decisionId !== "initial_scope");
}
if (hasFlag("--simulate-stale-decision-blocker") && Array.isArray(privateVisualValidation.decisionBlockers)) {
  privateVisualValidation.decisionBlockers = [...privateVisualValidation.decisionBlockers, "simulated_stale_decision"];
}
const decisions = decisionVerification.decisions || [];
for (const decision of decisions) {
  if (!["open", "verified-complete"].includes(decision?.status)) {
    console.error(`UI private completion verification found unsupported decision status for ${decision?.id || "unknown"}.`);
    process.exit(1);
  }
}
const actualOpenDecisions = decisions.filter((decision) => decision.status === "open");
const decisionBlockers = Array.isArray(privateVisualValidation.decisionBlockers)
  ? privateVisualValidation.decisionBlockers
  : [];
const blockerSet = new Set(decisionBlockers);
if (blockerSet.size !== decisionBlockers.length) {
  console.error("UI private completion verification found duplicate private decision blockers.");
  process.exit(1);
}
for (const decision of actualOpenDecisions) {
  if (!blockerSet.has(decision.id)) {
    console.error(`UI private completion verification requires private visual decisionBlockers to include open decision ${decision.id}.`);
    process.exit(1);
  }
}
for (const decisionId of decisionBlockers) {
  if (!actualOpenDecisions.some((decision) => decision.id === decisionId)) {
    console.error(`UI private completion verification found stale private visual decisionBlocker ${decisionId}.`);
    process.exit(1);
  }
}
const openDecisions = hasFlag("--simulate-no-open-decisions")
  ? []
  : actualOpenDecisions;
if (openDecisions.length > 0) {
  console.error(`EXTERNAL PENDING: ${openDecisions.length} open decisions block update_goal: ${openDecisions.map((decision) => decision.id).join(", ")}.`);
  process.exit(2);
}

runScript("scripts/ui_private_completion_source_verify.mjs");
runScript("scripts/ui_private_visual_verify.mjs");

console.log("UI private completion verification passed; update_goal may now be called");
