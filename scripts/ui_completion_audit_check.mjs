#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = new Set(process.argv.slice(2));
const isSelfTest = process.env.CLAWIX_UI_COMPLETION_AUDIT_SELF_TEST === "1";
const errors = [];

function fail(message) {
  errors.push(message);
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

function requireArray(object, label, field, { nonEmpty = true } = {}) {
  const value = object?.[field];
  if (!Array.isArray(value)) {
    fail(`${label}.${field} must be an array`);
    return [];
  }
  if (nonEmpty && value.length === 0) fail(`${label}.${field} must not be empty`);
  return value;
}

function arrayEquals(actual, expected) {
  return actual.length === expected.length && actual.every((value, index) => value === expected[index]);
}

function setEquals(actual, expected) {
  if (actual.size !== expected.size) return false;
  for (const value of expected) {
    if (!actual.has(value)) return false;
  }
  return true;
}

function scanPublicSafety(content, label) {
  if (/\/Users\//.test(content) || /~\//.test(content) || /file:\/\//.test(content) || /^[A-Z]:\\/m.test(content)) {
    fail(`${label} must not publish local private paths`);
  }
  if (/BEGIN [A-Z ]*PRIVATE KEY/.test(content) || /\bAKIA[0-9A-Z]{16}\b/.test(content) || /\bsk-[A-Za-z0-9]{20,}\b/.test(content)) {
    fail(`${label} must not publish secret-like values`);
  }
  if (/rollout-2026-05-15T13-21-46/.test(content)) {
    fail(`${label} must use the public-safe source session alias, not the private filename`);
  }
}

function runPrivateEvidencePlan() {
  const result = spawnSync(process.execPath, [path.join(rootDir, "scripts/ui_private_evidence_plan_check.mjs"), "--json"], {
    cwd: rootDir,
    encoding: "utf8",
  });
  if (result.status !== 0) {
    fail("private evidence plan must pass before completion audit can be verified");
    if (result.stderr) {
      for (const line of result.stderr.trim().split("\n")) fail(`private evidence plan: ${line}`);
    }
    return { counts: {}, evidence: [] };
  }
  try {
    return JSON.parse(result.stdout);
  } catch (error) {
    fail(`private evidence plan output is not valid JSON: ${error.message}`);
    return { counts: {}, evidence: [] };
  }
}

function countPrivateApprovalRecords() {
  const approvalAuthorityPath = "docs/ui/approval-authority.manifest.json";
  const approvalAuthority = readJson(approvalAuthorityPath);
  let count = 0;
  for (const [sourceIndex, source] of requireArray(approvalAuthority, approvalAuthorityPath, "approvalSources").entries()) {
    const sourceLabel = `${approvalAuthorityPath}.approvalSources[${sourceIndex}]`;
    const registry = readJson(source?.path || "");
    const records = requireArray(registry, source?.path || sourceLabel, source?.arrayField || "items", { nonEmpty: false });
    const approvalRequiredStatuses = Array.isArray(source?.approvalRequiredStatuses)
      ? new Set(source.approvalRequiredStatuses)
      : null;
    for (const record of records) {
      if (approvalRequiredStatuses && !approvalRequiredStatuses.has(record?.[source.statusField])) continue;
      count += 1;
    }
  }
  return count;
}

const auditPath = "docs/ui/completion-audit.md";
const decisionPath = "docs/ui/decision-verification.json";
let audit = read(auditPath);
const decisionVerification = readJson(decisionPath);
const privateVisualValidation = readJson("docs/ui/private-visual-validation.manifest.json");
const completionSource = readJson("docs/ui/completion-source.manifest.json");
let privateEvidencePlan = runPrivateEvidencePlan();
const privateApprovalRecordCount = countPrivateApprovalRecords();
if (args.has("--simulate-unsafe-private-path")) {
  audit += "\nPrivate source: /Users/private/source-session.jsonl\n";
}
if (args.has("--simulate-missing-goal-reference")) {
  audit = audit.replace("private-codex-goal:clawix-interface-governance-plan-2026-05-15.md", "private-codex-goal:other.md");
}
if (args.has("--simulate-missing-blocked-status")) {
  audit = audit.replace("Completion status: blocked by EXTERNAL PENDING private evidence.", "Completion status: ready.");
}
if (args.has("--simulate-wrong-private-evidence-total")) {
  audit = audit.replace(/Private evidence plan: \d+ records must be verified before completion\./, "Private evidence plan: 0 records must be verified before completion.");
}
if (args.has("--simulate-missing-evidence-count-row")) {
  audit = audit.replace("| `surface-baseline` | 14 |\n", "");
}
if (args.has("--simulate-missing-open-decision-evidence-row")) {
  audit = audit.replace("| `initial_scope` | `surface-baseline`, `surface-geometry`, `surface-copy` |\n", "");
}
if (args.has("--simulate-missing-decision-row")) {
  audit = audit.replace("| 3 | `canonical_source` | verified-complete | Public evidence verified. |\n", "");
}
if (args.has("--simulate-open-decision-public-state")) {
  audit = audit.replace(
    "| 1 | `initial_scope` | open | EXTERNAL PENDING: private surface baselines, rendered geometry, and copy snapshots. |",
    "| 1 | `initial_scope` | open | Public evidence verified. |",
  );
}
if (args.has("--simulate-approval-state-public-only")) {
  audit = audit.replace(
    "| 5 | `canon_approval` | verified-complete | Public approval evidence and private approval verifier wired. |",
    "| 5 | `canon_approval` | verified-complete | Public evidence verified. |",
  );
}
if (args.has("--simulate-verified-state-external-pending")) {
  audit = audit.replace(
    "| 3 | `canonical_source` | verified-complete | Public evidence verified. |",
    "| 3 | `canonical_source` | verified-complete | EXTERNAL PENDING: private evidence. |",
  );
}
if (args.has("--simulate-decision-status-mismatch") && Array.isArray(decisionVerification?.decisions)) {
  decisionVerification.decisions[2] = {
    ...decisionVerification.decisions[2],
    status: "open",
  };
}
if (args.has("--simulate-private-evidence-count-mismatch")) {
  privateEvidencePlan = {
    ...privateEvidencePlan,
    counts: {
      ...(privateEvidencePlan.counts || {}),
      "surface-baseline": 15,
    },
  };
}
if (args.has("--simulate-missing-private-blocker") && Array.isArray(privateVisualValidation?.decisionBlockers)) {
  privateVisualValidation.decisionBlockers = privateVisualValidation.decisionBlockers.filter((id) => id !== "initial_scope");
}
if (args.has("--simulate-extra-private-blocker") && Array.isArray(privateVisualValidation?.decisionBlockers)) {
  privateVisualValidation.decisionBlockers.push("canonical_source");
}
if (args.has("--simulate-wrong-external-pending-exit-code")) {
  privateVisualValidation.externalPendingExitCode = 0;
}
if (args.has("--simulate-duplicate-audit-decision-row")) {
  audit = audit.replace(
    "| 3 | `canonical_source` | verified-complete | Public evidence verified. |\n",
    "| 3 | `canonical_source` | verified-complete | Public evidence verified. |\n| 3 | `canonical_source` | verified-complete | Public evidence verified. |\n",
  );
}
if (args.has("--simulate-wrong-row-index")) {
  audit = audit.replace(
    "| 3 | `canonical_source` | verified-complete | Public evidence verified. |",
    "| 30 | `canonical_source` | verified-complete | Public evidence verified. |",
  );
}
if (args.has("--simulate-open-decision-without-blocking-verifier") && Array.isArray(decisionVerification?.decisions)) {
  decisionVerification.decisions[0] = {
    ...decisionVerification.decisions[0],
    blockingVerifiers: [],
  };
}
if (args.has("--simulate-verified-decision-with-remaining") && Array.isArray(decisionVerification?.decisions)) {
  decisionVerification.decisions[2] = {
    ...decisionVerification.decisions[2],
    remaining: ["Still pending."],
  };
}
if (args.has("--simulate-decision-missing-public-evidence") && Array.isArray(decisionVerification?.decisions)) {
  decisionVerification.decisions[2] = {
    ...decisionVerification.decisions[2],
    publicEvidence: [],
  };
}
if (args.has("--simulate-unknown-status") && Array.isArray(decisionVerification?.decisions)) {
  decisionVerification.decisions[2] = {
    ...decisionVerification.decisions[2],
    status: "pending",
  };
}
if (args.has("--simulate-source-session-alias-mismatch")) {
  completionSource.sourceSessionAlias = "private-codex-session:other";
}
if (args.has("--simulate-wrong-conversation-id")) {
  decisionVerification.conversationId = "other";
}
scanPublicSafety(audit, auditPath);

if (completionSource?.goalReferenceAlias !== decisionVerification?.goalReference) {
  fail(`${decisionPath}.goalReference must match docs/ui/completion-source.manifest.json.goalReferenceAlias`);
}
if (completionSource?.sourceSessionAlias !== decisionVerification?.sourceSession) {
  fail(`${decisionPath}.sourceSession must match docs/ui/completion-source.manifest.json.sourceSessionAlias`);
}
if (completionSource?.expectedConversationId !== decisionVerification?.conversationId) {
  fail(`${decisionPath}.conversationId must match docs/ui/completion-source.manifest.json.expectedConversationId`);
}
if (completionSource?.externalPendingExitCode !== 2 || privateVisualValidation?.externalPendingExitCode !== 2) {
  fail("completion and private visual manifests must keep EXTERNAL PENDING exit code 2");
}
if (!String(decisionVerification?.completionRule || "").includes("Do not complete the goal")) {
  fail(`${decisionPath}.completionRule must preserve the private goal completion guard`);
}
const allowedStatuses = requireArray(decisionVerification, decisionPath, "statuses");
if (!arrayEquals(allowedStatuses, ["open", "verified-complete"])) {
  fail(`${decisionPath}.statuses must be exactly open and verified-complete`);
}

for (const required of [
  "private-codex-goal:clawix-interface-governance-plan-2026-05-15.md",
  "private-codex-session:019e2b5e-fe48-7231-8e13-49411999b001",
  "private session, not published",
  "Do not call update_goal",
]) {
  if (!audit.includes(required)) fail(`${auditPath} must include ${required}`);
}

const decisions = requireArray(decisionVerification, decisionPath, "decisions");
const expectedDecisionIds = requireArray(completionSource, "docs/ui/completion-source.manifest.json", "expectedDecisionIds");
const expectedDecisions = requireArray(completionSource, "docs/ui/completion-source.manifest.json", "expectedDecisions");
if (completionSource?.expectedDecisionCount !== decisions.length) {
  fail(`${decisionPath}.decisions must contain ${completionSource?.expectedDecisionCount} decisions`);
}
if (!arrayEquals(decisions.map((decision) => decision?.id), expectedDecisionIds)) {
  fail(`${decisionPath}.decisions must use the expected decision ids in source-session order`);
}
if (!arrayEquals(expectedDecisions.map((decision) => decision?.id), expectedDecisionIds)) {
  fail("docs/ui/completion-source.manifest.json expectedDecisions ids must match expectedDecisionIds");
}
for (const [decisionIndex, decision] of decisions.entries()) {
  const label = `${decisionPath}.decisions[${decisionIndex}]`;
  const expected = expectedDecisions[decisionIndex] || {};
  if (decision?.index !== decisionIndex + 1) fail(`${label}.index must be ${decisionIndex + 1}`);
  if (decision?.id !== expected.id) fail(`${label}.id must match source-session decision ${expected.id}`);
  if (decision?.choice !== expected.choice) fail(`${label}.choice must match the source-session choice`);
  if (!allowedStatuses.includes(decision?.status)) fail(`${label}.status is not an allowed status`);
  if (requireArray(decision, label, "publicEvidence").length === 0) {
    fail(`${label}.publicEvidence must not be empty`);
  }
}
const openDecisions = decisions.filter((decision) => decision?.status === "open");
if (openDecisions.length > 0 && !audit.includes("Completion status: blocked by EXTERNAL PENDING private evidence.")) {
  fail(`${auditPath} must state completion is blocked while decisions remain open`);
}
if (openDecisions.length === 0 && audit.includes("Completion status: blocked")) {
  fail(`${auditPath} must not stay blocked when all decisions are verified-complete`);
}

const plannedEvidenceTotal = Array.isArray(privateEvidencePlan.evidence) ? privateEvidencePlan.evidence.length : 0;
if (!audit.includes(`Private evidence plan: ${plannedEvidenceTotal} records must be verified before completion.`)) {
  fail(`${auditPath} must state the derived private evidence total`);
}
if (!audit.includes(`Private approval evidence: ${privateApprovalRecordCount} record(s) must be verified before completion.`)) {
  fail(`${auditPath} must state the private approval evidence total`);
}
const sourceSessionRequirements = completionSource?.sourceSessionRequirements || {};
for (const recordType of sourceSessionRequirements.requiredRecordTypes || []) {
  if (!audit.includes(recordType)) fail(`${auditPath} must include source session record type ${recordType}`);
}
if (!audit.includes(`at least ${sourceSessionRequirements.minimumUserMessages} user message records`)) {
  fail(`${auditPath} must state the source session user message minimum`);
}
if (sourceSessionRequirements.decisionsBeforeFirstGoalEvent && !audit.includes("before the first `thread_goal_*` event")) {
  fail(`${auditPath} must state decisions are verified before the first thread_goal event`);
}
for (const [type, count] of Object.entries(privateEvidencePlan.counts || {})) {
  const row = `| \`${type}\` | ${count} |`;
  if (!audit.includes(row)) fail(`${auditPath} must include private evidence count row ${row}`);
}
const decisionBlockerEvidenceTypes = requireArray(
  privateVisualValidation,
  "docs/ui/private-visual-validation.manifest.json",
  "decisionBlockerEvidenceTypes",
);
const privateEvidenceTypes = new Set(Object.keys(privateEvidencePlan.counts || {}));
const privateBlockerIds = requireArray(privateVisualValidation, "docs/ui/private-visual-validation.manifest.json", "decisionBlockers");
const openDecisionIds = new Set(openDecisions.map((decision) => decision.id));
const privateBlockerIdSet = new Set(privateBlockerIds);
if (!setEquals(openDecisionIds, privateBlockerIdSet)) {
  fail("open decisions must exactly match docs/ui/private-visual-validation.manifest.json.decisionBlockers");
}
if (!arrayEquals(openDecisions.map((decision) => decision.id), privateBlockerIds)) {
  fail("private visual decisionBlockers must stay in open decision order");
}
if (!arrayEquals(decisionBlockerEvidenceTypes.map((entry) => entry?.decisionId), privateBlockerIds)) {
  fail("decisionBlockerEvidenceTypes must match decisionBlockers in order");
}
for (const entry of decisionBlockerEvidenceTypes) {
  const evidenceTypes = requireArray(entry, `docs/ui/private-visual-validation.manifest.json.${entry?.decisionId || "unknown"}`, "evidenceTypes");
  for (const evidenceType of evidenceTypes) {
    if (!privateEvidenceTypes.has(evidenceType)) {
      fail(`docs/ui/private-visual-validation.manifest.json.${entry?.decisionId}.evidenceTypes contains unknown type ${evidenceType}`);
    }
  }
  const row = `| \`${entry.decisionId}\` | ${evidenceTypes.map((type) => `\`${type}\``).join(", ")} |`;
  if (!audit.includes(row)) fail(`${auditPath} must include open decision evidence row ${row}`);
}

const rowPattern = /^\| (\d+) \| `([^`]+)` \| ([^|]+) \| ([^|]+) \|$/gm;
const rows = [];
let match;
while ((match = rowPattern.exec(audit)) !== null) {
  rows.push({
    index: Number(match[1]),
    id: match[2],
    status: match[3].trim(),
    evidenceState: match[4].trim(),
  });
}

if (rows.length !== decisions.length) {
  fail(`${auditPath} must include one completion row per decision`);
}
if (!arrayEquals(rows.map((row) => row.id), decisions.map((decision) => decision.id))) {
  fail(`${auditPath} completion rows must match decision order exactly`);
}
if (!arrayEquals(rows.map((row) => row.index), decisions.map((decision) => decision.index))) {
  fail(`${auditPath} completion row indexes must match decision indexes exactly`);
}

const rowsById = new Map(rows.map((row) => [row.id, row]));
if (rowsById.size !== rows.length) {
  fail(`${auditPath} completion rows must not contain duplicate decisions`);
}
const approvalDecisionIds = new Set([
  "canon_approval",
  "human_visual_review",
  "approved_surface_protection",
  "visual_model_gate",
  "visual_change_scope_limit",
  "approved_baseline_authority",
]);
for (const decision of decisions) {
  const row = rowsById.get(decision.id);
  const label = `${auditPath}.${decision.id}`;
  if (!row) {
    fail(`${label} is missing`);
    continue;
  }
  if (row.index !== decision.index) fail(`${label} must use index ${decision.index}`);
  if (row.status !== decision.status) fail(`${label} status must match ${decisionPath}`);
  if (!allowedStatuses.includes(row.status)) fail(`${label} row status is not an allowed status`);
  if (decision.status === "open" && !row.evidenceState.includes("EXTERNAL PENDING")) {
    fail(`${label} must identify private evidence as EXTERNAL PENDING`);
  }
  if (decision.status === "open") {
    if (requireArray(decision, `${decisionPath}.${decision.id}`, "privateEvidence").length === 0) {
      fail(`${label} must include private evidence aliases while open`);
    }
    if (requireArray(decision, `${decisionPath}.${decision.id}`, "blockingVerifiers").length === 0) {
      fail(`${label} must include blocking private verifiers while open`);
    }
    if (requireArray(decision, `${decisionPath}.${decision.id}`, "remaining").length === 0) {
      fail(`${label} must include remaining work while open`);
    }
  }
  if (decision.status === "verified-complete" && approvalDecisionIds.has(decision.id)) {
    if (!decision.publicEvidence.includes("scripts/ui_private_approval_verify.mjs")) {
      fail(`${label} approval completion must include the private approval verifier`);
    }
    if (row.evidenceState !== "Public approval evidence and private approval verifier wired.") {
      fail(`${label} must state private approval verifier is wired`);
    }
  }
  if (decision.status === "verified-complete") {
    if (!approvalDecisionIds.has(decision.id) && row.evidenceState !== "Public evidence verified.") {
      fail(`${label} must state public evidence is verified`);
    }
    if (Array.isArray(decision.remaining) && decision.remaining.length > 0) {
      fail(`${label} verified-complete decisions must not have remaining work`);
    }
    if (Array.isArray(decision.privateEvidence) && decision.privateEvidence.length > 0) {
      fail(`${label} verified-complete decisions must not require private evidence`);
    }
    if (Array.isArray(decision.blockingVerifiers) && decision.blockingVerifiers.length > 0) {
      fail(`${label} verified-complete decisions must not have blocking verifiers`);
    }
  }
}

if (errors.length === 0 && !isSelfTest && args.size === 0) {
  for (const [flag, expectedOutput] of [
    ["--simulate-unsafe-private-path", "must not publish local private paths"],
    ["--simulate-missing-goal-reference", "must include private-codex-goal:clawix-interface-governance-plan-2026-05-15.md"],
    ["--simulate-missing-blocked-status", "must state completion is blocked while decisions remain open"],
    ["--simulate-wrong-private-evidence-total", "must state the derived private evidence total"],
    ["--simulate-missing-evidence-count-row", "must include private evidence count row"],
    ["--simulate-missing-open-decision-evidence-row", "must include open decision evidence row"],
    ["--simulate-missing-decision-row", "must include one completion row per decision"],
    ["--simulate-open-decision-public-state", "initial_scope must identify private evidence as EXTERNAL PENDING"],
    ["--simulate-approval-state-public-only", "canon_approval must state private approval verifier is wired"],
    ["--simulate-verified-state-external-pending", "canonical_source must state public evidence is verified"],
    ["--simulate-decision-status-mismatch", "canonical_source status must match"],
    ["--simulate-private-evidence-count-mismatch", "must include private evidence count row"],
    ["--simulate-missing-private-blocker", "open decisions must exactly match"],
    ["--simulate-extra-private-blocker", "open decisions must exactly match"],
    ["--simulate-wrong-external-pending-exit-code", "EXTERNAL PENDING exit code 2"],
    ["--simulate-duplicate-audit-decision-row", "must include one completion row per decision"],
    ["--simulate-wrong-row-index", "completion row indexes must match"],
    ["--simulate-open-decision-without-blocking-verifier", "must include blocking private verifiers while open"],
    ["--simulate-verified-decision-with-remaining", "verified-complete decisions must not have remaining work"],
    ["--simulate-decision-missing-public-evidence", "publicEvidence must not be empty"],
    ["--simulate-unknown-status", "status is not an allowed status"],
    ["--simulate-source-session-alias-mismatch", "sourceSession must match"],
    ["--simulate-wrong-conversation-id", "conversationId must match"],
  ]) {
    const result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, flag], {
      cwd: rootDir,
      env: { ...process.env, CLAWIX_UI_COMPLETION_AUDIT_SELF_TEST: "1" },
      encoding: "utf8",
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status === 0) {
      fail(`self-test ${flag} must fail when completion audit evidence is removed`);
      continue;
    }
    if (!output.includes(expectedOutput)) {
      fail(`self-test ${flag} output must include ${expectedOutput}`);
    }
  }
}

if (errors.length > 0) {
  console.error("UI completion audit check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI completion audit check passed (${rows.length} decisions, ${openDecisions.length} open)`);
