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
  allowedFlags: ["--require-approved", "--skip-public-prerequisites", "--simulate-no-open-decisions"],
  testOnlyFlags: ["--simulate-no-open-decisions"],
  testOnlyEnv: "CLAWIX_UI_ALLOW_COMPLETION_SIMULATION",
});

const manifest = readJson("docs/ui/completion-gate.manifest.json");
runPublicPrerequisites(manifest);
const decisionVerification = readJson(manifest.decisionVerificationPath || "docs/ui/decision-verification.json");
const decisions = decisionVerification.decisions || [];
for (const decision of decisions) {
  if (!["open", "verified-complete"].includes(decision?.status)) {
    console.error(`UI private completion verification found unsupported decision status for ${decision?.id || "unknown"}.`);
    process.exit(1);
  }
}
const openDecisions = hasFlag("--simulate-no-open-decisions")
  ? []
  : decisions.filter((decision) => decision.status === "open");
if (openDecisions.length > 0) {
  console.error(`EXTERNAL PENDING: ${openDecisions.length} open decisions block update_goal: ${openDecisions.map((decision) => decision.id).join(", ")}.`);
  process.exit(2);
}

runScript("scripts/ui_private_completion_source_verify.mjs");
runScript("scripts/ui_private_visual_verify.mjs");

console.log("UI private completion verification passed; update_goal may now be called");
