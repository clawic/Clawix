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

function runStatusScript(script, scriptArgs, extraEnv = {}) {
  const result = spawnSync(process.execPath, [path.join(rootDir, script), ...scriptArgs], {
    cwd: rootDir,
    env: { ...process.env, ...extraEnv },
    encoding: "utf8",
  });
  const output = `${result.stdout || ""}${result.stderr || ""}`;
  let json = null;
  try {
    json = result.stdout ? JSON.parse(result.stdout) : null;
  } catch {
    json = null;
  }
  return {
    script,
    args: scriptArgs,
    exitCode: result.status,
    status: json?.status || (result.status === 0 ? "passed" : output.includes("EXTERNAL PENDING") ? "external-pending" : "failed"),
    json,
    outputPreview: output.split(/\n/).filter((line) => line.trim()).slice(0, 12),
  };
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

  const statusResult = spawnSync(process.execPath, [new URL(import.meta.url).pathname, "--completion-status"], {
    cwd: rootDir,
    env: selfTestEnv,
    encoding: "utf8",
  });
  if (statusResult.status !== 0) {
    console.error("UI private completion verification self-test --completion-status must pass.");
    process.exit(1);
  }
  try {
    const status = JSON.parse(statusResult.stdout);
    if (status.updateGoalAllowed !== false || status.decisions?.open !== 9) {
      console.error("UI private completion verification self-test --completion-status must report blocked update_goal with 9 open decisions.");
      process.exit(1);
    }
    if (!status.privateSourceReview || typeof status.privateSourceReview.exitCode !== "number") {
      console.error("UI private completion verification self-test --completion-status must include privateSourceReview status.");
      process.exit(1);
    }
  } catch (error) {
    console.error(`UI private completion verification self-test --completion-status output must be JSON: ${error.message}.`);
    process.exit(1);
  }
}

const completionStatusMode = hasFlag("--completion-status");
if (!hasFlag("--require-approved") && !completionStatusMode) {
  console.error("UI private completion verification requires --require-approved.");
  process.exit(1);
}
enforcePrivateVerifierArgs(args, {
  label: "UI private completion verification",
  allowedFlags: [
    "--require-approved",
    "--completion-status",
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

if (completionStatusMode) {
  const privateEvidenceStatus = runStatusScript("scripts/ui_private_evidence_plan_check.mjs", ["--capture-decisions"]);
  const privateApprovalStatus = runStatusScript("scripts/ui_private_approval_verify.mjs", ["--approval-status"]);
  const privateSourceStatus = runStatusScript("scripts/ui_private_completion_source_verify.mjs", ["--require-approved"], {
    CLAWIX_UI_COMPLETION_SOURCE_VERIFY_SELF_TEST: "1",
  });
  const verifiedCompleteDecisions = decisions.filter((decision) => decision.status === "verified-complete");
  const openDecisionIds = actualOpenDecisions.map((decision) => decision.id);
  const evidenceTotals = privateEvidenceStatus.json?.totals || {};
  const approvalCounts = privateApprovalStatus.json?.counts || {};
  const blockers = [];
  if (openDecisionIds.length > 0) {
    blockers.push({
      id: "open-decisions",
      status: "external-pending",
      count: openDecisionIds.length,
      details: openDecisionIds,
    });
  }
  for (const [id, count] of [
    ["private-evidence-missing-root", evidenceTotals.missingRoot || 0],
    ["private-evidence-invalid-root", evidenceTotals.invalidRoot || 0],
    ["private-evidence-missing-file", evidenceTotals.missingFile || 0],
    ["private-evidence-invalid-json", evidenceTotals.invalidJson || 0],
    ["private-evidence-placeholder", evidenceTotals.placeholder || 0],
    ["private-evidence-invalid-candidate", evidenceTotals.invalidCandidate || 0],
    ["private-evidence-candidate-not-approved", evidenceTotals.candidate || 0],
    ["private-approval-missing-root", approvalCounts.missingRoot || 0],
    ["private-approval-invalid-root", approvalCounts.invalidRoot || 0],
    ["private-approval-invalid-reference", approvalCounts.invalidReference || 0],
    ["private-approval-missing-file", approvalCounts.missingFile || 0],
    ["private-approval-invalid-json", approvalCounts.invalidJson || 0],
    ["private-approval-placeholder", approvalCounts.placeholder || 0],
    ["private-approval-candidate-not-approved", approvalCounts.candidate || 0],
  ]) {
    if (count > 0) blockers.push({ id, status: "external-pending", count });
  }
  if (privateSourceStatus.status !== "passed") {
    blockers.push({
      id: "private-source-review",
      status: privateSourceStatus.status,
      count: 1,
      details: privateSourceStatus.outputPreview,
    });
  }
  const report = {
    schemaVersion: 1,
    status: openDecisionIds.length > 0
      ? "external-pending-open-decisions"
      : "pending-approved-private-verifiers",
    updateGoalAllowed: false,
    goalUpdateRule: manifest.goalUpdateRule,
    finalVerificationCommand: manifest.finalVerificationCommand,
    decisions: {
      total: decisions.length,
      verifiedComplete: verifiedCompleteDecisions.length,
      open: actualOpenDecisions.length,
      openDecisionIds,
    },
    privateEvidence: {
      script: privateEvidenceStatus.script,
      exitCode: privateEvidenceStatus.exitCode,
      status: privateEvidenceStatus.status,
      totalRecords: privateEvidenceStatus.json?.totalRecords ?? null,
      totals: privateEvidenceStatus.json?.totals ?? null,
      decisionCount: privateEvidenceStatus.json?.decisionCount ?? null,
    },
    privateApproval: {
      script: privateApprovalStatus.script,
      exitCode: privateApprovalStatus.exitCode,
      status: privateApprovalStatus.status,
      totalRecords: privateApprovalStatus.json?.totalRecords ?? null,
      counts: privateApprovalStatus.json?.counts ?? null,
    },
    privateSourceReview: {
      script: privateSourceStatus.script,
      exitCode: privateSourceStatus.exitCode,
      status: privateSourceStatus.status,
      outputPreview: privateSourceStatus.outputPreview,
    },
    blockingSummary: {
      totalBlockers: blockers.length,
      blockers,
    },
    note: "This status is public-safe and does not prove completion. update_goal is allowed only after --require-approved exits 0.",
  };
  console.log(JSON.stringify(report, null, 2));
  process.exit(0);
}

if (!isSelfTest) {
  runFailureSelfTests();
}
runPublicPrerequisites(manifest);

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
