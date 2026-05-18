#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { enforcePrivateVerifierArgs } from "./ui_private_verifier_args.mjs";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = process.argv.slice(2);
const isSelfTest = process.env.CLAWIX_UI_COMPLETION_VERIFY_SELF_TEST === "1";

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

function runFailureSelfTests() {
  const selfTestEnv = {
    ...process.env,
    CLAWIX_UI_COMPLETION_VERIFY_SELF_TEST: "1",
  };
  delete selfTestEnv.CLAWIX_UI_ALLOW_COMPLETION_SIMULATION;
  const simulationEnv = {
    ...selfTestEnv,
    CLAWIX_UI_ALLOW_COMPLETION_SIMULATION: "1",
  };
  const tests = [
    [[], selfTestEnv, "requires --require-approved"],
    [["--require-approved", "--unknown-flag"], selfTestEnv, "received unknown flag --unknown-flag"],
    [
      ["--require-approved", "--skip-public-prerequisites", "--simulate-no-open-decisions"],
      selfTestEnv,
      "CLAWIX_UI_ALLOW_COMPLETION_SIMULATION",
    ],
    [
      ["--require-approved", "--skip-public-prerequisites", "--simulate-missing-decision-blocker"],
      simulationEnv,
      "requires private visual decisionBlockers to include open decision initial_scope",
    ],
    [
      ["--require-approved", "--skip-public-prerequisites", "--simulate-stale-decision-blocker"],
      simulationEnv,
      "found stale private visual decisionBlocker simulated_stale_decision",
    ],
    [
      ["--require-approved", "--skip-public-prerequisites", "--simulate-open-decision-without-private-evidence"],
      simulationEnv,
      "requires open decision initial_scope to list private evidence aliases",
    ],
    [
      ["--require-approved", "--skip-public-prerequisites", "--simulate-verified-complete-with-remaining"],
      simulationEnv,
      "requires verified-complete decision canonical_source to have no remaining work",
    ],
  ];

  for (const [testArgs, env, expectedOutput] of tests) {
    const result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, ...testArgs], {
      cwd: rootDir,
      env,
      encoding: "utf8",
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status === 0) {
      console.error(`UI private completion verification self-test ${testArgs.join(" ") || "<no args>"} must fail.`);
      process.exit(1);
    }
    if (!output.includes(expectedOutput)) {
      console.error(`UI private completion verification self-test ${testArgs.join(" ") || "<no args>"} output must include ${expectedOutput}.`);
      process.exit(1);
    }
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
    "--simulate-verified-complete-with-remaining",
    "--simulate-verified-complete-with-private-evidence",
    "--simulate-open-decision-without-private-evidence",
    "--simulate-open-decision-without-blocking-verifier",
    "--simulate-open-decision-without-remaining",
  ],
  testOnlyFlags: [
    "--simulate-no-open-decisions",
    "--simulate-missing-decision-blocker",
    "--simulate-stale-decision-blocker",
    "--simulate-verified-complete-with-remaining",
    "--simulate-verified-complete-with-private-evidence",
    "--simulate-open-decision-without-private-evidence",
    "--simulate-open-decision-without-blocking-verifier",
    "--simulate-open-decision-without-remaining",
  ],
  testOnlyEnv: "CLAWIX_UI_ALLOW_COMPLETION_SIMULATION",
});

const manifest = readJson("docs/ui/completion-gate.manifest.json");
if (!isSelfTest) {
  runFailureSelfTests();
}
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
const firstOpenDecision = decisions.find((decision) => decision?.status === "open");
const firstVerifiedDecision = decisions.find((decision) => decision?.status === "verified-complete");
if (hasFlag("--simulate-verified-complete-with-remaining") && firstVerifiedDecision) {
  firstVerifiedDecision.remaining = ["Simulated remaining work."];
}
if (hasFlag("--simulate-verified-complete-with-private-evidence") && firstVerifiedDecision) {
  firstVerifiedDecision.privateEvidence = ["private-codex-ui-baselines:simulated"];
}
if (hasFlag("--simulate-open-decision-without-private-evidence") && firstOpenDecision) {
  firstOpenDecision.privateEvidence = [];
}
if (hasFlag("--simulate-open-decision-without-blocking-verifier") && firstOpenDecision) {
  firstOpenDecision.blockingVerifiers = [];
}
if (hasFlag("--simulate-open-decision-without-remaining") && firstOpenDecision) {
  firstOpenDecision.remaining = [];
}
for (const decision of decisions) {
  if (!["open", "verified-complete"].includes(decision?.status)) {
    console.error(`UI private completion verification found unsupported decision status for ${decision?.id || "unknown"}.`);
    process.exit(1);
  }
  const remaining = Array.isArray(decision.remaining) ? decision.remaining : [];
  const privateEvidence = Array.isArray(decision.privateEvidence) ? decision.privateEvidence : [];
  const blockingVerifiers = Array.isArray(decision.blockingVerifiers) ? decision.blockingVerifiers : [];
  if (decision.status === "open") {
    if (remaining.length === 0) {
      console.error(`UI private completion verification requires open decision ${decision.id} to list remaining work.`);
      process.exit(1);
    }
    if (privateEvidence.length === 0) {
      console.error(`UI private completion verification requires open decision ${decision.id} to list private evidence aliases.`);
      process.exit(1);
    }
    if (blockingVerifiers.length === 0) {
      console.error(`UI private completion verification requires open decision ${decision.id} to list blocking private verifiers.`);
      process.exit(1);
    }
  }
  if (decision.status === "verified-complete") {
    if (remaining.length > 0) {
      console.error(`UI private completion verification requires verified-complete decision ${decision.id} to have no remaining work.`);
      process.exit(1);
    }
    if (privateEvidence.length > 0) {
      console.error(`UI private completion verification requires verified-complete decision ${decision.id} to have no private evidence blockers.`);
      process.exit(1);
    }
    if (blockingVerifiers.length > 0) {
      console.error(`UI private completion verification requires verified-complete decision ${decision.id} to have no blocking private verifiers.`);
      process.exit(1);
    }
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
