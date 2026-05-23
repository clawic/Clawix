#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const rawArgs = process.argv.slice(2);
const isSelfTest = process.env.CLAWIX_UI_COMPLETION_GATE_SELF_TEST === "1";
const errors = [];

function fail(message) {
  errors.push(message);
}

for (const arg of rawArgs) {
  if (arg.startsWith("--")) {
    console.error(`UI completion gate check received unsupported public flag ${arg}.`);
    process.exit(1);
  }
}

function read(relativePath) {
  const file = path.join(rootDir, relativePath);
  if (!fs.existsSync(file)) {
    fail(`missing ${relativePath}`);
    return "";
  }
  return fs.readFileSync(file, "utf8");
}

function readJson(relativePath) {
  const content = read(relativePath);
  if (!content) return null;
  try {
    return JSON.parse(content);
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

function scanPublicSafety(value, label) {
  if (Array.isArray(value)) {
    value.forEach((child, index) => scanPublicSafety(child, `${label}[${index}]`));
    return;
  }
  if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) scanPublicSafety(child, `${label}.${key}`);
    return;
  }
  if (typeof value !== "string") return;
  if (/\/Users\//.test(value) || value.startsWith("~/") || value.startsWith("file://") || /^[A-Z]:\\/.test(value)) {
    fail(`${label} must not publish a local private path`);
  }
}

function withoutPrivateCompletionEnv() {
  const env = { ...process.env };
  for (const key of Object.keys(env)) {
    if (key.startsWith("CLAWIX_UI_PRIVATE_")) delete env[key];
  }
  return env;
}

function withTemporaryCompletionSources(sourceManifest, callback) {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "clawix-ui-completion-"));
  try {
    const goalFile = path.join(tempRoot, "goal.md");
    const sessionFile = path.join(tempRoot, "session.jsonl");
    const decisions = sourceManifest?.expectedDecisions || [];
    const decisionLines = decisions.map((decision) => `- \`${decision.id}\`: ${decision.choice}`).join("\n");
    fs.writeFileSync(
      goalFile,
      [
        sourceManifest.expectedConversationId,
        "Required Decision Verification Checklist",
        "Do not mark the associated goal complete",
        "update_goal(status:",
        decisionLines,
      ].join("\n"),
    );
    fs.writeFileSync(
      sessionFile,
      [
        JSON.stringify({ type: "session_meta", payload: { id: sourceManifest.expectedConversationId } }),
        ...Array.from({ length: sourceManifest.sourceSessionRequirements?.minimumUserMessages || 1 }, (_, index) =>
          JSON.stringify({
            type: "event_msg",
            payload: {
              type: "user_message",
              text: index === 0 ? decisionLines : `source verification user message ${index}`,
            },
          }),
        ),
        JSON.stringify({
          type: "response_item",
          payload: {
            type: "message",
            text: decisions.map((decision) => `${decision.id}: ${decision.choice}`).join("\n"),
          },
        }),
        ...decisions.map((decision) =>
          JSON.stringify({
            type: "response_item",
            payload: {
              type: "message",
              text: `${decision.id}: ${decision.choice}`,
            },
          }),
        ),
        JSON.stringify({
          type: "event_msg",
          payload: {
            type: "thread_goal_updated",
            text: "simulated goal event after source decisions",
          },
        }),
      ].join("\n"),
    );
    return callback({
      [sourceManifest.privateGoalFileEnv]: goalFile,
      [sourceManifest.privateSourceSessionFileEnv]: sessionFile,
    });
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
}

function withTemporaryPrivatePlaceholderRoots(callback) {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "clawix-ui-private-placeholders-"));
  try {
    const evidenceTemplateRoot = path.join(tempRoot, "evidence");
    const approvalTemplateRoot = path.join(tempRoot, "approval");
    const evidenceTemplateResult = spawnSync(
      process.execPath,
      [
        path.join(rootDir, "scripts/ui_private_evidence_plan_check.mjs"),
        "--write-template-root",
        evidenceTemplateRoot,
      ],
      {
        cwd: rootDir,
        env: withoutPrivateCompletionEnv(),
        encoding: "utf8",
      },
    );
    if (evidenceTemplateResult.status !== 0) {
      fail("scripts/ui_private_evidence_plan_check.mjs must write temporary placeholder evidence roots");
      return callback({});
    }
    const approvalTemplateResult = spawnSync(
      process.execPath,
      [
        path.join(rootDir, "scripts/ui_private_approval_verify.mjs"),
        "--write-approval-template-root",
        approvalTemplateRoot,
      ],
      {
        cwd: rootDir,
        env: withoutPrivateCompletionEnv(),
        encoding: "utf8",
      },
    );
    if (approvalTemplateResult.status !== 0) {
      fail("scripts/ui_private_approval_verify.mjs must write temporary placeholder approval roots");
      return callback({});
    }
    return callback({
      CLAWIX_UI_PRIVATE_BASELINE_ROOT: path.join(evidenceTemplateRoot, "private-codex-ui-baselines"),
      CLAWIX_UI_PRIVATE_GEOMETRY_ROOT: path.join(evidenceTemplateRoot, "private-codex-ui-rendered-geometry"),
      CLAWIX_UI_PRIVATE_COPY_ROOT: path.join(evidenceTemplateRoot, "private-codex-ui-copy-snapshots"),
      CLAWIX_UI_PRIVATE_DRIFT_ROOT: path.join(evidenceTemplateRoot, "private-codex-ui-rendered-drift"),
      CLAWIX_UI_PRIVATE_DEBT_AUDIT_ROOT: path.join(evidenceTemplateRoot, "private-codex-ui-debt-audit"),
      CLAWIX_UI_PRIVATE_APPROVAL_ROOT: path.join(approvalTemplateRoot, "private-codex-ui-approval"),
    });
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
}

function withTemporaryPrivateInvalidCandidateRoots(callback) {
  return withTemporaryPrivatePlaceholderRoots((temporaryPrivateRootEnv) => {
    const evidencePath = path.join(
      temporaryPrivateRootEnv.CLAWIX_UI_PRIVATE_BASELINE_ROOT,
      "macos",
      "dropdown-open",
      "evidence.json",
    );
    const evidence = JSON.parse(fs.readFileSync(evidencePath, "utf8"));
    delete evidence._templateStatus;
    fs.writeFileSync(evidencePath, `${JSON.stringify(evidence, null, 2)}\n`);
    return callback(temporaryPrivateRootEnv);
  });
}

function withTemporaryPrivateInvalidApprovalCandidateRoots(callback) {
  return withTemporaryPrivatePlaceholderRoots((temporaryPrivateRootEnv) => {
    const approvalPath = path.join(
      temporaryPrivateRootEnv.CLAWIX_UI_PRIVATE_APPROVAL_ROOT,
      "models",
      "claude-opus-4.7",
      "approval-evidence.json",
    );
    const approval = JSON.parse(fs.readFileSync(approvalPath, "utf8"));
    delete approval._templateStatus;
    fs.writeFileSync(approvalPath, `${JSON.stringify(approval, null, 2)}\n`);
    return callback(temporaryPrivateRootEnv);
  });
}

function approvalRecords(approvalManifest) {
  const records = [];
  for (const [sourceIndex, source] of requireArray(approvalManifest, "docs/ui/approval-authority.manifest.json", "approvalSources").entries()) {
    const label = `docs/ui/approval-authority.manifest.json.approvalSources[${sourceIndex}]`;
    requireFields(source, label, ["id", "path", "arrayField", "privateApprovalField"]);
    if (!source?.path || !source?.arrayField || !source?.privateApprovalField) continue;
    const registry = readJson(source.path);
    const requiredStatuses = Array.isArray(source.approvalRequiredStatuses)
      ? new Set(source.approvalRequiredStatuses)
      : null;
    for (const record of requireArray(registry, source.path, source.arrayField, { nonEmpty: false })) {
      if (requiredStatuses && !requiredStatuses.has(record?.[source.statusField])) continue;
      records.push(record);
    }
  }
  return records;
}

function mechanicalEquivalenceRecords(mechanicalManifest) {
  return requireArray(mechanicalManifest, "docs/ui/mechanical-equivalence.manifest.json", "records", { nonEmpty: false });
}

function requireConditionalRootContract({ rootsByEnv, env, condition, manifestPath: sourceManifestPath }) {
  if (!env || !condition || !sourceManifestPath) {
    fail(`${manifestPath}.conditionalPrivateRoots entries must include env, condition, and manifestPath`);
    return;
  }
  if (!fs.existsSync(path.join(rootDir, sourceManifestPath))) {
    fail(`${manifestPath}.conditionalPrivateRoots entry for ${env} points to missing ${sourceManifestPath}`);
  }
  if (!rootsByEnv.has(env)) {
    fail(`${manifestPath}.conditionalPrivateRoots entry for ${env} must map to a private visual optional root alias`);
  }
}

function runFailureSelfTests() {
  const selfTestEnv = { ...process.env, CLAWIX_UI_COMPLETION_GATE_SELF_TEST: "1" };
  const tests = [
    [["--unknown-flag"], "received unsupported public flag --unknown-flag"],
    [["--simulate-no-open-decisions"], "received unsupported public flag --simulate-no-open-decisions"],
    [["--simulate-verified-complete-with-remaining"], "received unsupported public flag --simulate-verified-complete-with-remaining"],
    [["--simulate-open-decision-without-private-evidence"], "received unsupported public flag --simulate-open-decision-without-private-evidence"],
    [["--simulate-missing-decision-blocker"], "received unsupported public flag --simulate-missing-decision-blocker"],
    [["--simulate-stale-decision-blocker"], "received unsupported public flag --simulate-stale-decision-blocker"],
    [["--simulate-open-decision-without-blocking-verifier"], "received unsupported public flag --simulate-open-decision-without-blocking-verifier"],
    [["--simulate-open-decision-without-remaining"], "received unsupported public flag --simulate-open-decision-without-remaining"],
    [["--simulate-verified-complete-with-private-evidence"], "received unsupported public flag --simulate-verified-complete-with-private-evidence"],
  ];

  for (const [testArgs, expectedOutput] of tests) {
    const result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, ...testArgs], {
      cwd: rootDir,
      env: selfTestEnv,
      encoding: "utf8",
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status === 0) {
      fail(`self-test ${testArgs.join(" ")} must fail for public completion gate argument validation`);
      continue;
    }
    if (!output.includes(expectedOutput)) {
      fail(`self-test ${testArgs.join(" ")} output must include ${expectedOutput}`);
    }
  }
}

if (!isSelfTest) runFailureSelfTests();

const manifestPath = "docs/ui/completion-gate.manifest.json";
const manifest = readJson(manifestPath);
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "decisionVerificationPath",
  "completionAuditPath",
  "completionSourceManifestPath",
  "privateVisualValidationManifestPath",
  "approvalAuthorityManifestPath",
  "publicCheckScript",
  "privateVerifierScript",
  "privateApprovalVerifierScript",
  "privateReviewBundleScript",
  "completionStatusCommand",
  "completionStatusRequiredBlockersWithoutPrivateRoots",
  "completionStatusRequiredBlockersWithSourceReview",
  "completionStatusRequiredBlockersWithPrivatePlaceholders",
  "completionStatusRequiredBlockersWithInvalidCandidates",
  "completionStatusRequiredBlockersWithInvalidApprovalCandidates",
  "finalVerificationCommand",
  "conditionalPrivateRoots",
  "requiredPublicChecks",
  "publicPrerequisiteScripts",
  "goalUpdateRule",
  "externalPendingExitCode",
]);
scanPublicSafety(manifest, manifestPath);

if (manifest?.publicCheckScript !== "scripts/ui_completion_gate_check.mjs") {
  fail(`${manifestPath}.publicCheckScript must be scripts/ui_completion_gate_check.mjs`);
}
if (manifest?.privateVerifierScript !== "scripts/ui_private_completion_verify.mjs") {
  fail(`${manifestPath}.privateVerifierScript must be scripts/ui_private_completion_verify.mjs`);
}
if (manifest?.privateApprovalVerifierScript !== "scripts/ui_private_approval_verify.mjs") {
  fail(`${manifestPath}.privateApprovalVerifierScript must be scripts/ui_private_approval_verify.mjs`);
}
if (manifest?.privateReviewBundleScript !== "scripts/ui_private_review_bundle_check.mjs") {
  fail(`${manifestPath}.privateReviewBundleScript must be scripts/ui_private_review_bundle_check.mjs`);
}
if (manifest?.completionStatusCommand !== "node scripts/ui_private_completion_verify.mjs --completion-status") {
  fail(`${manifestPath}.completionStatusCommand must be node scripts/ui_private_completion_verify.mjs --completion-status`);
}
const requiredBlockersWithoutPrivateRoots = requireArray(manifest, manifestPath, "completionStatusRequiredBlockersWithoutPrivateRoots");
const requiredBlockersWithSourceReview = requireArray(manifest, manifestPath, "completionStatusRequiredBlockersWithSourceReview");
const requiredBlockersWithPrivatePlaceholders = requireArray(manifest, manifestPath, "completionStatusRequiredBlockersWithPrivatePlaceholders");
const requiredBlockersWithInvalidCandidates = requireArray(manifest, manifestPath, "completionStatusRequiredBlockersWithInvalidCandidates");
const requiredBlockersWithInvalidApprovalCandidates = requireArray(manifest, manifestPath, "completionStatusRequiredBlockersWithInvalidApprovalCandidates");
for (const blocker of [
  ...requiredBlockersWithoutPrivateRoots,
  ...requiredBlockersWithSourceReview,
  ...requiredBlockersWithPrivatePlaceholders,
  ...requiredBlockersWithInvalidCandidates,
  ...requiredBlockersWithInvalidApprovalCandidates,
]) {
  if (typeof blocker !== "string" || blocker.length === 0 || /[A-Z_]/.test(blocker)) {
    fail(`${manifestPath} completion status blocker ids must be stable lowercase strings`);
  }
}
if (!String(manifest?.finalVerificationCommand || "").includes("scripts/ui_private_completion_verify.mjs --require-approved")) {
  fail(`${manifestPath}.finalVerificationCommand must require the private completion verifier`);
}
if (!String(manifest?.goalUpdateRule || "").includes("update_goal")) {
  fail(`${manifestPath}.goalUpdateRule must mention update_goal`);
}
if (manifest?.externalPendingExitCode !== 2) fail(`${manifestPath}.externalPendingExitCode must be 2`);

for (const relativePath of [
  manifest?.decisionVerificationPath,
  manifest?.completionAuditPath,
  manifest?.completionSourceManifestPath,
  manifest?.privateVisualValidationManifestPath,
  manifest?.approvalAuthorityManifestPath,
  manifest?.publicCheckScript,
  manifest?.privateVerifierScript,
  manifest?.privateApprovalVerifierScript,
  manifest?.privateReviewBundleScript,
]) {
  if (!relativePath || relativePath.includes("..") || path.isAbsolute(relativePath)) {
    fail(`${manifestPath} contains an unsafe relative path ${relativePath}`);
    continue;
  }
  if (!fs.existsSync(path.join(rootDir, relativePath))) fail(`missing ${relativePath}`);
}

const sourceManifest = readJson(manifest?.completionSourceManifestPath || "docs/ui/completion-source.manifest.json");
const visualManifest = readJson(manifest?.privateVisualValidationManifestPath || "docs/ui/private-visual-validation.manifest.json");
const approvalManifest = readJson(manifest?.approvalAuthorityManifestPath || "docs/ui/approval-authority.manifest.json");
const mechanicalManifest = readJson("docs/ui/mechanical-equivalence.manifest.json");
for (const envName of [
  sourceManifest?.privateGoalFileEnv,
  sourceManifest?.privateSourceSessionFileEnv,
  ...(Array.isArray(visualManifest?.requiredRoots) ? visualManifest.requiredRoots : []),
]) {
  if (!String(manifest?.finalVerificationCommand || "").includes(envName)) {
    fail(`${manifestPath}.finalVerificationCommand must include ${envName}`);
  }
}
const optionalRootAliases = requireArray(visualManifest, manifest?.privateVisualValidationManifestPath || "docs/ui/private-visual-validation.manifest.json", "optionalRootAliases");
const optionalRootsByEnv = new Map(optionalRootAliases.map((entry) => [entry?.env, entry]));
const conditionalRootContracts = requireArray(manifest, manifestPath, "conditionalPrivateRoots");
for (const contract of conditionalRootContracts) {
  requireConditionalRootContract({ rootsByEnv: optionalRootsByEnv, ...contract });
}
const conditionalRootsByCondition = new Map(conditionalRootContracts.map((entry) => [entry?.condition, entry]));
for (const [condition, expected] of [
  ["required-when-approval-records-exist", { env: "CLAWIX_UI_PRIVATE_APPROVAL_ROOT", manifestPath: manifest?.approvalAuthorityManifestPath }],
  ["required-when-mechanical-equivalence-records-exist", { env: "CLAWIX_UI_PRIVATE_MECHANICAL_EQUIVALENCE_ROOT", manifestPath: "docs/ui/mechanical-equivalence.manifest.json" }],
]) {
  const contract = conditionalRootsByCondition.get(condition);
  if (!contract) {
    fail(`${manifestPath}.conditionalPrivateRoots must include ${condition}`);
    continue;
  }
  for (const [field, value] of Object.entries(expected)) {
    if (contract[field] !== value) fail(`${manifestPath}.conditionalPrivateRoots ${condition} must set ${field}=${value}`);
  }
}
const activeApprovalRecords = approvalRecords(approvalManifest);
if (activeApprovalRecords.length > 0) {
  if (!String(manifest?.finalVerificationCommand || "").includes("CLAWIX_UI_PRIVATE_APPROVAL_ROOT")) {
    fail(`${manifestPath}.finalVerificationCommand must include CLAWIX_UI_PRIVATE_APPROVAL_ROOT while approval records exist`);
  }
  if (!requireArray(visualManifest, manifest?.privateVisualValidationManifestPath || "docs/ui/private-visual-validation.manifest.json", "delegates").includes("node scripts/ui_private_approval_verify.mjs --require-approved")) {
    fail(`${manifest?.privateVisualValidationManifestPath}.delegates must include scripts/ui_private_approval_verify.mjs while approval records exist`);
  }
  if (!optionalRootAliases.some((entry) => entry?.alias === approvalManifest?.privateApprovalAlias && entry?.env === "CLAWIX_UI_PRIVATE_APPROVAL_ROOT")) {
    fail(`${manifest?.privateVisualValidationManifestPath}.optionalRootAliases must expose CLAWIX_UI_PRIVATE_APPROVAL_ROOT for private approvals`);
  }
  const approvalResult = spawnSync(process.execPath, [path.join(rootDir, manifest.privateApprovalVerifierScript), "--require-approved"], {
    cwd: rootDir,
    env: withoutPrivateCompletionEnv(),
    encoding: "utf8",
  });
  const approvalOutput = `${approvalResult.stdout || ""}${approvalResult.stderr || ""}`;
  if (approvalResult.status !== manifest.externalPendingExitCode) {
    fail(`${manifest.privateApprovalVerifierScript} must exit ${manifest.externalPendingExitCode} while private approval evidence is missing`);
  }
  if (!approvalOutput.includes("CLAWIX_UI_PRIVATE_APPROVAL_ROOT")) {
    fail(`${manifest.privateApprovalVerifierScript} must report CLAWIX_UI_PRIVATE_APPROVAL_ROOT when approval records exist`);
  }
}
const activeMechanicalRecords = mechanicalEquivalenceRecords(mechanicalManifest);
if (activeMechanicalRecords.length > 0 && !String(manifest?.finalVerificationCommand || "").includes("CLAWIX_UI_PRIVATE_MECHANICAL_EQUIVALENCE_ROOT")) {
  fail(`${manifestPath}.finalVerificationCommand must include CLAWIX_UI_PRIVATE_MECHANICAL_EQUIVALENCE_ROOT while mechanical equivalence records exist`);
}

const config = readJson("docs/ui/interface-governance.config.json");
const publicChecks = new Set(requireArray(config, "docs/ui/interface-governance.config.json", "publicChecks"));
if (!publicChecks.has("completion-final-gate-check")) {
  fail("docs/ui/interface-governance.config.json.publicChecks must include completion-final-gate-check");
}
for (const check of requireArray(manifest, manifestPath, "requiredPublicChecks")) {
  if (!publicChecks.has(check)) fail(`${manifestPath}.requiredPublicChecks includes undeclared check ${check}`);
}
if (!Array.isArray(manifest.publicPrerequisiteScripts) || !manifest.publicPrerequisiteScripts.includes("scripts/ui_release_gate_check.mjs")) {
  fail(`${manifestPath}.publicPrerequisiteScripts must include scripts/ui_release_gate_check.mjs`);
}
for (const [index, script] of (manifest.publicPrerequisiteScripts || []).entries()) {
  if (typeof script !== "string" || !script.startsWith("scripts/ui_") || !script.endsWith(".mjs")) {
    fail(`${manifestPath}.publicPrerequisiteScripts[${index}] must be a public UI script`);
    continue;
  }
  if (!fs.existsSync(path.join(rootDir, script))) {
    fail(`${manifestPath}.publicPrerequisiteScripts[${index}] points to missing ${script}`);
  }
}

const privateVerifier = read(manifest?.privateVerifierScript || "scripts/ui_private_completion_verify.mjs");
for (const snippet of [
  "docs/ui/completion-gate.manifest.json",
  "scripts/ui_private_completion_source_verify.mjs",
  "scripts/ui_private_visual_verify.mjs",
  "publicPrerequisiteScripts",
  "--skip-public-prerequisites",
  "EXTERNAL PENDING",
  "process.exit(2)",
  "--completion-status",
  "privateSourceReview",
  "updateGoalAllowed",
  "unresolved decisions",
  "decisionBlockers",
  "--simulate-no-open-decisions",
  "--simulate-verified-complete-with-remaining",
  "--simulate-open-decision-without-private-evidence",
  "CLAWIX_UI_ALLOW_COMPLETION_SIMULATION",
  "enforcePrivateVerifierArgs",
]) {
  if (!privateVerifier.includes(snippet)) {
    fail(`${manifest.privateVerifierScript} must include ${snippet}`);
  }
}
const unknownFlagResult = spawnSync(process.execPath, [path.join(rootDir, manifest.privateVerifierScript), "--require-approved", "--unknown-flag"], {
  cwd: rootDir,
  env: withoutPrivateCompletionEnv(),
  encoding: "utf8",
});
if (unknownFlagResult.status === 0 || unknownFlagResult.status === manifest.externalPendingExitCode) {
  fail(`${manifest.privateVerifierScript} must reject unknown flags before private completion checks`);
}
const unexpectedArgumentResult = spawnSync(
  process.execPath,
  [path.join(rootDir, manifest.privateVerifierScript), "--require-approved", "unexpected-arg"],
  {
    cwd: rootDir,
    env: withoutPrivateCompletionEnv(),
    encoding: "utf8",
  },
);
const unexpectedArgumentOutput = `${unexpectedArgumentResult.stdout || ""}${unexpectedArgumentResult.stderr || ""}`;
if (unexpectedArgumentResult.status === 0 || unexpectedArgumentResult.status === manifest.externalPendingExitCode) {
  fail(`${manifest.privateVerifierScript} must reject unexpected positional arguments before private completion checks`);
}
if (!unexpectedArgumentOutput.includes("received unexpected argument unexpected-arg")) {
  fail(`${manifest.privateVerifierScript} must explain unexpected positional arguments`);
}

const completionStatusResult = spawnSync(process.execPath, [path.join(rootDir, manifest.privateVerifierScript), "--completion-status"], {
  cwd: rootDir,
  env: withoutPrivateCompletionEnv(),
  encoding: "utf8",
});
if (completionStatusResult.status !== 0) {
  fail(`${manifest.privateVerifierScript} --completion-status must produce public-safe status JSON without private roots`);
} else {
  try {
    const status = JSON.parse(completionStatusResult.stdout);
    if (status.updateGoalAllowed !== false) {
      fail(`${manifest.privateVerifierScript} --completion-status must keep updateGoalAllowed false`);
    }
    if (status.decisions?.open !== 0 || status.decisions?.blockedExternalPending !== 9 || status.decisions?.unresolved !== 9) {
      fail(`${manifest.privateVerifierScript} --completion-status must report 0 open decisions, 9 blocked decisions, and 9 unresolved decisions`);
    }
    if (!Array.isArray(status.decisions?.openDecisionIds) || status.decisions.openDecisionIds.length !== 0) {
      fail(`${manifest.privateVerifierScript} --completion-status must list no open decision ids`);
    }
    if (!Array.isArray(status.decisions?.blockedExternalPendingDecisionIds) || !status.decisions.blockedExternalPendingDecisionIds.includes("initial_scope")) {
      fail(`${manifest.privateVerifierScript} --completion-status must list blocked decision ids`);
    }
    if (!status.privateEvidence || status.privateEvidence.totalRecords !== 166) {
      fail(`${manifest.privateVerifierScript} --completion-status must include private evidence totals`);
    }
    if (!status.privateApproval || status.privateApproval.totalRecords !== activeApprovalRecords.length) {
      fail(`${manifest.privateVerifierScript} --completion-status must include private approval totals`);
    }
    if (!status.privateReviewBundles || status.privateReviewBundles.totalRecords !== 166 || status.privateReviewBundles.decisionCount !== 9) {
      fail(`${manifest.privateVerifierScript} --completion-status must include private review bundle totals`);
    }
    if (!Array.isArray(status.privateReviewBundles?.decisions) || !status.privateReviewBundles.decisions.some((decision) => decision.decisionId === "initial_scope")) {
      fail(`${manifest.privateVerifierScript} --completion-status must include private review bundle decision summaries`);
    }
    if (
      !status.privateSourceReview ||
      status.privateSourceReview.exitCode !== manifest.externalPendingExitCode ||
      status.privateSourceReview.status !== "external-pending"
    ) {
      fail(`${manifest.privateVerifierScript} --completion-status must include external-pending private source review without private source env`);
    }
    const blockerIds = new Set((status.blockingSummary?.blockers || []).map((blocker) => blocker?.id));
    for (const blockerId of requiredBlockersWithoutPrivateRoots) {
      if (!blockerIds.has(blockerId)) {
        fail(`${manifest.privateVerifierScript} --completion-status must include blockingSummary ${blockerId} without private roots`);
      }
    }
  } catch (error) {
    fail(`${manifest.privateVerifierScript} --completion-status output must be valid JSON: ${error.message}`);
  }
}

const decisionVerification = readJson(manifest?.decisionVerificationPath || "docs/ui/decision-verification.json");
const openDecisions = requireArray(decisionVerification, manifest?.decisionVerificationPath || "docs/ui/decision-verification.json", "decisions")
  .filter((decision) => decision?.status === "open");
if (openDecisions.length > 0) {
  const unsafeSimulationResult = spawnSync(
    process.execPath,
    [path.join(rootDir, manifest.privateVerifierScript), "--require-approved", "--simulate-no-open-decisions", "--skip-public-prerequisites"],
    {
      cwd: rootDir,
      env: withoutPrivateCompletionEnv(),
      encoding: "utf8",
    },
  );
  const unsafeSimulationOutput = `${unsafeSimulationResult.stdout || ""}${unsafeSimulationResult.stderr || ""}`;
  if (unsafeSimulationResult.status === 0 || unsafeSimulationResult.status === manifest.externalPendingExitCode) {
    fail(`${manifest.privateVerifierScript} must reject simulation flags unless explicitly enabled for tests`);
  }
  if (!unsafeSimulationOutput.includes("CLAWIX_UI_ALLOW_COMPLETION_SIMULATION")) {
    fail(`${manifest.privateVerifierScript} must explain the test-only simulation guard`);
  }

  const result = spawnSync(process.execPath, [path.join(rootDir, manifest.privateVerifierScript), "--require-approved", "--skip-public-prerequisites"], {
    cwd: rootDir,
    env: withoutPrivateCompletionEnv(),
    encoding: "utf8",
  });
  const output = `${result.stdout || ""}${result.stderr || ""}`;
  if (result.status !== manifest.externalPendingExitCode) {
    fail(`${manifest.privateVerifierScript} must exit ${manifest.externalPendingExitCode} while decisions remain open`);
  }
  if (!output.includes("unresolved decisions block update_goal")) {
    fail(`${manifest.privateVerifierScript} must report unresolved decisions before asking for private roots`);
  }
  for (const decision of openDecisions) {
    if (!output.includes(decision.id)) {
      fail(`${manifest.privateVerifierScript} open-decision output must include ${decision.id}`);
    }
  }

  const missingBlockerResult = spawnSync(
    process.execPath,
    [path.join(rootDir, manifest.privateVerifierScript), "--require-approved", "--simulate-missing-decision-blocker", "--skip-public-prerequisites"],
    {
      cwd: rootDir,
      env: { ...withoutPrivateCompletionEnv(), CLAWIX_UI_ALLOW_COMPLETION_SIMULATION: "1" },
      encoding: "utf8",
    },
  );
  const missingBlockerOutput = `${missingBlockerResult.stdout || ""}${missingBlockerResult.stderr || ""}`;
  if (missingBlockerResult.status === 0 || missingBlockerResult.status === manifest.externalPendingExitCode) {
    fail(`${manifest.privateVerifierScript} must fail before EXTERNAL PENDING when private decisionBlockers omit an unresolved decision`);
  }
  if (!missingBlockerOutput.includes("decisionBlockers") || !missingBlockerOutput.includes("initial_scope")) {
    fail(`${manifest.privateVerifierScript} must explain missing private decisionBlockers for unresolved decisions`);
  }

  const staleBlockerResult = spawnSync(
    process.execPath,
    [path.join(rootDir, manifest.privateVerifierScript), "--require-approved", "--simulate-stale-decision-blocker", "--skip-public-prerequisites"],
    {
      cwd: rootDir,
      env: { ...withoutPrivateCompletionEnv(), CLAWIX_UI_ALLOW_COMPLETION_SIMULATION: "1" },
      encoding: "utf8",
    },
  );
  const staleBlockerOutput = `${staleBlockerResult.stdout || ""}${staleBlockerResult.stderr || ""}`;
  if (staleBlockerResult.status === 0 || staleBlockerResult.status === manifest.externalPendingExitCode) {
    fail(`${manifest.privateVerifierScript} must fail before EXTERNAL PENDING when private decisionBlockers contain stale decisions`);
  }
  if (!staleBlockerOutput.includes("stale private visual decisionBlocker") || !staleBlockerOutput.includes("simulated_stale_decision")) {
    fail(`${manifest.privateVerifierScript} must explain stale private decisionBlockers`);
  }

  for (const [flag, expectedOutput] of [
    ["--simulate-open-decision-without-private-evidence", "blocked decision initial_scope to list private evidence aliases"],
    ["--simulate-open-decision-without-blocking-verifier", "blocked decision initial_scope to list blocking private verifiers"],
    ["--simulate-open-decision-without-remaining", "blocked decision initial_scope to list remaining work"],
    ["--simulate-verified-complete-with-remaining", "verified-complete decision canonical_source to have no remaining work"],
    ["--simulate-verified-complete-with-private-evidence", "verified-complete decision canonical_source to have no private evidence blockers"],
  ]) {
    const malformedDecisionResult = spawnSync(
      process.execPath,
      [path.join(rootDir, manifest.privateVerifierScript), "--require-approved", flag, "--skip-public-prerequisites"],
      {
        cwd: rootDir,
        env: { ...withoutPrivateCompletionEnv(), CLAWIX_UI_ALLOW_COMPLETION_SIMULATION: "1" },
        encoding: "utf8",
      },
    );
    const malformedDecisionOutput = `${malformedDecisionResult.stdout || ""}${malformedDecisionResult.stderr || ""}`;
    if (malformedDecisionResult.status === 0 || malformedDecisionResult.status === manifest.externalPendingExitCode) {
      fail(`${manifest.privateVerifierScript} must fail before EXTERNAL PENDING for ${flag}`);
    }
    if (!malformedDecisionOutput.includes(expectedOutput)) {
      fail(`${manifest.privateVerifierScript} ${flag} output must include ${expectedOutput}`);
    }
  }
}

const simulatedClosedResult = spawnSync(
  process.execPath,
  [path.join(rootDir, manifest.privateVerifierScript), "--require-approved", "--simulate-no-open-decisions", "--skip-public-prerequisites"],
  {
    cwd: rootDir,
    env: { ...withoutPrivateCompletionEnv(), CLAWIX_UI_ALLOW_COMPLETION_SIMULATION: "1" },
    encoding: "utf8",
  },
);
const simulatedClosedOutput = `${simulatedClosedResult.stdout || ""}${simulatedClosedResult.stderr || ""}`;
if (simulatedClosedResult.status !== manifest.externalPendingExitCode) {
  fail(`${manifest.privateVerifierScript} must exit ${manifest.externalPendingExitCode} when closed decisions still lack private sources`);
}
if (!simulatedClosedOutput.includes("CLAWIX_UI_PRIVATE_COMPLETION_GOAL_FILE")) {
  fail(`${manifest.privateVerifierScript} must delegate to private completion source verification after decisions close`);
}
if (simulatedClosedOutput.includes("unresolved decisions block update_goal")) {
  fail(`${manifest.privateVerifierScript} must not report unresolved decisions during closed-decision simulation`);
}
withTemporaryCompletionSources(sourceManifest, (temporaryEnv) => {
  const statusResult = spawnSync(
    process.execPath,
    [path.join(rootDir, manifest.privateVerifierScript), "--completion-status"],
    {
      cwd: rootDir,
      env: { ...withoutPrivateCompletionEnv(), ...temporaryEnv },
      encoding: "utf8",
    },
  );
  if (statusResult.status !== 0) {
    fail(`${manifest.privateVerifierScript} --completion-status must pass with temporary private source files`);
  } else {
    try {
      const status = JSON.parse(statusResult.stdout);
      if (status.privateSourceReview?.exitCode !== 0 || status.privateSourceReview?.status !== "passed") {
        fail(`${manifest.privateVerifierScript} --completion-status must report passed private source review with temporary private source files`);
      }
      if (status.updateGoalAllowed !== false || status.decisions?.open !== 0 || status.decisions?.blockedExternalPending !== 9 || status.decisions?.unresolved !== 9) {
        fail(`${manifest.privateVerifierScript} --completion-status must keep update_goal blocked even when private source review passes while decisions remain unresolved`);
      }
      const blockerIds = new Set((status.blockingSummary?.blockers || []).map((blocker) => blocker?.id));
      if (blockerIds.has("private-source-review")) {
        fail(`${manifest.privateVerifierScript} --completion-status must remove private-source-review blocker after source review passes`);
      }
      for (const blockerId of requiredBlockersWithSourceReview) {
        if (!blockerIds.has(blockerId)) {
          fail(`${manifest.privateVerifierScript} --completion-status must keep ${blockerId} blocker while private roots remain missing`);
        }
      }
    } catch (error) {
      fail(`${manifest.privateVerifierScript} --completion-status with temporary sources output must be valid JSON: ${error.message}`);
    }
  }

  withTemporaryPrivatePlaceholderRoots((temporaryPrivateRootEnv) => {
    const placeholderStatusResult = spawnSync(
      process.execPath,
      [path.join(rootDir, manifest.privateVerifierScript), "--completion-status"],
      {
        cwd: rootDir,
        env: {
          ...withoutPrivateCompletionEnv(),
          ...temporaryEnv,
          ...temporaryPrivateRootEnv,
        },
        encoding: "utf8",
      },
    );
    if (placeholderStatusResult.status !== 0) {
      fail(`${manifest.privateVerifierScript} --completion-status must pass with temporary private placeholder roots`);
      return;
    }
    try {
      const status = JSON.parse(placeholderStatusResult.stdout);
      if (status.privateSourceReview?.status !== "passed") {
        fail(`${manifest.privateVerifierScript} --completion-status must keep private source review passed with placeholder roots`);
      }
      if (status.privateEvidence?.totals?.placeholder !== 166 || status.privateEvidence?.totals?.candidate !== 0) {
        fail(`${manifest.privateVerifierScript} --completion-status must classify temporary private evidence templates as placeholders`);
      }
      if (status.privateApproval?.counts?.placeholder !== activeApprovalRecords.length || status.privateApproval?.counts?.candidate !== 0) {
        fail(`${manifest.privateVerifierScript} --completion-status must classify temporary private approval templates as placeholders`);
      }
      if (
        status.privateReviewBundles?.captureTotals?.placeholder !== 166 ||
        status.privateReviewBundles?.decisionCount !== 9 ||
        status.privateReviewBundles?.totalRecords !== 166
      ) {
        fail(`${manifest.privateVerifierScript} --completion-status must include placeholder private review bundle readiness`);
      }
      const blockerIds = new Set((status.blockingSummary?.blockers || []).map((blocker) => blocker?.id));
      for (const blockerId of requiredBlockersWithPrivatePlaceholders) {
        if (!blockerIds.has(blockerId)) {
          fail(`${manifest.privateVerifierScript} --completion-status must include ${blockerId} blocker while private roots contain placeholders`);
        }
      }
      for (const blockerId of [
        "private-evidence-missing-root",
        "private-approval-missing-root",
        "private-source-review",
      ]) {
        if (blockerIds.has(blockerId)) {
          fail(`${manifest.privateVerifierScript} --completion-status must not keep ${blockerId} after placeholder roots and source review are present`);
        }
      }
    } catch (error) {
      fail(`${manifest.privateVerifierScript} --completion-status with temporary private placeholder roots output must be valid JSON: ${error.message}`);
    }
  });

  withTemporaryPrivateInvalidCandidateRoots((temporaryPrivateRootEnv) => {
    const invalidCandidateReportResult = spawnSync(
      process.execPath,
      [path.join(rootDir, "scripts/ui_private_evidence_plan_check.mjs"), "--capture-invalid-candidates"],
      {
        cwd: rootDir,
        env: {
          ...withoutPrivateCompletionEnv(),
          ...temporaryPrivateRootEnv,
        },
        encoding: "utf8",
      },
    );
    if (invalidCandidateReportResult.status !== 0) {
      fail("scripts/ui_private_evidence_plan_check.mjs --capture-invalid-candidates must pass with malformed private candidate roots");
    } else {
      try {
        const report = JSON.parse(invalidCandidateReportResult.stdout);
        if (report.invalidCandidateCount !== 1 || report.totals?.invalidCandidate !== 1) {
          fail("scripts/ui_private_evidence_plan_check.mjs --capture-invalid-candidates must report one malformed candidate");
        }
        const candidate = report.invalidCandidates?.[0];
        if (
          candidate?.relativeEvidencePath !== "macos/dropdown-open/evidence.json" ||
          candidate?.rootAlias !== "private-codex-ui-baselines" ||
          !candidate?.missingOrInvalidFields?.includes("geometryHash") ||
          String(JSON.stringify(report)).includes(path.dirname(temporaryPrivateRootEnv.CLAWIX_UI_PRIVATE_BASELINE_ROOT))
        ) {
          fail("scripts/ui_private_evidence_plan_check.mjs --capture-invalid-candidates must report public-safe relative candidate details");
        }
      } catch (error) {
        fail(`scripts/ui_private_evidence_plan_check.mjs --capture-invalid-candidates output must be valid JSON: ${error.message}`);
      }
    }

    const invalidCandidateStatusResult = spawnSync(
      process.execPath,
      [path.join(rootDir, manifest.privateVerifierScript), "--completion-status"],
      {
        cwd: rootDir,
        env: {
          ...withoutPrivateCompletionEnv(),
          ...temporaryEnv,
          ...temporaryPrivateRootEnv,
        },
        encoding: "utf8",
      },
    );
    if (invalidCandidateStatusResult.status !== 0) {
      fail(`${manifest.privateVerifierScript} --completion-status must pass with malformed private candidate roots`);
      return;
    }
    try {
      const status = JSON.parse(invalidCandidateStatusResult.stdout);
      if (status.privateEvidence?.totals?.invalidCandidate !== 1 || status.privateEvidence?.totals?.candidate !== 0) {
        fail(`${manifest.privateVerifierScript} --completion-status must classify malformed private candidate evidence as invalidCandidate, not candidate`);
      }
      const blockerIds = new Set((status.blockingSummary?.blockers || []).map((blocker) => blocker?.id));
      for (const blockerId of requiredBlockersWithInvalidCandidates) {
        if (!blockerIds.has(blockerId)) {
          fail(`${manifest.privateVerifierScript} --completion-status must include ${blockerId} blocker while private roots contain invalid candidates`);
        }
      }
    } catch (error) {
      fail(`${manifest.privateVerifierScript} --completion-status with malformed private candidate roots output must be valid JSON: ${error.message}`);
    }
  });

  withTemporaryPrivateInvalidApprovalCandidateRoots((temporaryPrivateRootEnv) => {
    const invalidApprovalStatusResult = spawnSync(
      process.execPath,
      [path.join(rootDir, "scripts/ui_private_approval_verify.mjs"), "--approval-status"],
      {
        cwd: rootDir,
        env: {
          ...withoutPrivateCompletionEnv(),
          ...temporaryPrivateRootEnv,
        },
        encoding: "utf8",
      },
    );
    if (invalidApprovalStatusResult.status !== 0) {
      fail("scripts/ui_private_approval_verify.mjs --approval-status must pass with malformed private approval candidate roots");
    } else {
      try {
        const report = JSON.parse(invalidApprovalStatusResult.stdout);
        if (report.counts?.invalidCandidate !== 1 || report.counts?.candidate !== 0) {
          fail("scripts/ui_private_approval_verify.mjs --approval-status must classify malformed approval evidence as invalidCandidate, not candidate");
        }
        const approval = report.records?.find((record) => record?.state === "invalid-candidate");
        if (
          approval?.state !== "invalid-candidate" ||
          !approval?.missingOrInvalidFields?.includes("approvalHash")
        ) {
          fail("scripts/ui_private_approval_verify.mjs --approval-status must report missing malformed approval fields");
        }
      } catch (error) {
        fail(`scripts/ui_private_approval_verify.mjs --approval-status with malformed approval candidate roots output must be valid JSON: ${error.message}`);
      }
    }

    const invalidApprovalCompletionStatusResult = spawnSync(
      process.execPath,
      [path.join(rootDir, manifest.privateVerifierScript), "--completion-status"],
      {
        cwd: rootDir,
        env: {
          ...withoutPrivateCompletionEnv(),
          ...temporaryEnv,
          ...temporaryPrivateRootEnv,
        },
        encoding: "utf8",
      },
    );
    if (invalidApprovalCompletionStatusResult.status !== 0) {
      fail(`${manifest.privateVerifierScript} --completion-status must pass with malformed private approval candidate roots`);
      return;
    }
    try {
      const status = JSON.parse(invalidApprovalCompletionStatusResult.stdout);
      if (status.privateApproval?.counts?.invalidCandidate !== 1 || status.privateApproval?.counts?.candidate !== 0) {
        fail(`${manifest.privateVerifierScript} --completion-status must classify malformed private approval evidence as invalidCandidate, not candidate`);
      }
      const blockerIds = new Set((status.blockingSummary?.blockers || []).map((blocker) => blocker?.id));
      for (const blockerId of requiredBlockersWithInvalidApprovalCandidates) {
        if (!blockerIds.has(blockerId)) {
          fail(`${manifest.privateVerifierScript} --completion-status must include ${blockerId} blocker while private approval root contains invalid candidates`);
        }
      }
    } catch (error) {
      fail(`${manifest.privateVerifierScript} --completion-status with malformed private approval candidate roots output must be valid JSON: ${error.message}`);
    }
  });

  const result = spawnSync(
    process.execPath,
    [path.join(rootDir, manifest.privateVerifierScript), "--require-approved", "--simulate-no-open-decisions", "--skip-public-prerequisites"],
    {
      cwd: rootDir,
      env: { ...withoutPrivateCompletionEnv(), ...temporaryEnv, CLAWIX_UI_ALLOW_COMPLETION_SIMULATION: "1" },
      encoding: "utf8",
    },
  );
  const output = `${result.stdout || ""}${result.stderr || ""}`;
  if (result.status !== manifest.externalPendingExitCode) {
    fail(`${manifest.privateVerifierScript} must exit ${manifest.externalPendingExitCode} after source verification when visual roots are missing`);
  }
  if (!output.includes("CLAWIX_UI_PRIVATE_BASELINE_ROOT")) {
    fail(`${manifest.privateVerifierScript} must advance to private visual root verification after private source verification passes`);
  }
  if (output.includes("CLAWIX_UI_PRIVATE_COMPLETION_GOAL_FILE")) {
    fail(`${manifest.privateVerifierScript} must not keep blocking on private completion sources after source verification passes`);
  }
});

const gateSurface = readJson("docs/ui/gate-surface.manifest.json");
if (!requireArray(gateSurface, "docs/ui/gate-surface.manifest.json", "requiredPublicCheckScripts").includes(manifest?.publicCheckScript)) {
  fail("docs/ui/gate-surface.manifest.json.requiredPublicCheckScripts must include the completion gate check");
}
const gateCoverage = gateSurface?.publicCheckCoverage || {};
if (!Array.isArray(gateCoverage["completion-final-gate-check"]) || !gateCoverage["completion-final-gate-check"].includes(manifest?.publicCheckScript)) {
  fail("docs/ui/gate-surface.manifest.json.publicCheckCoverage must cover completion-final-gate-check");
}

if (errors.length > 0) {
  console.error("UI completion gate check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("UI completion gate check passed");
