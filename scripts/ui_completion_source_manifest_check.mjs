#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const rawArgs = process.argv.slice(2);
const args = new Set(rawArgs);
const isSelfTest = process.env.CLAWIX_UI_COMPLETION_SOURCE_MANIFEST_SELF_TEST === "1";
const errors = [];
const simulationFlags = [
  "--simulate-unsafe-private-path",
  "--simulate-wrong-goal-alias",
  "--simulate-wrong-source-session-alias",
  "--simulate-wrong-private-goal-env",
  "--simulate-verifier-without-require-approved",
  "--simulate-wrong-external-pending-exit-code",
  "--simulate-wrong-decision-count",
  "--simulate-missing-required-record-type",
  "--simulate-zero-minimum-user-messages",
  "--simulate-missing-expected-decision-id",
  "--simulate-duplicate-expected-decision-id",
  "--simulate-wrong-expected-decision-choice",
  "--simulate-wrong-decision-conversation-id",
  "--simulate-audit-missing-source-alias",
  "--simulate-private-verifier-missing-snippet",
];
const allowedFlags = new Set(simulationFlags);

function fail(message) {
  errors.push(message);
}

for (const arg of rawArgs) {
  if (arg.startsWith("--") && !allowedFlags.has(arg)) {
    console.error(`UI completion source manifest check received unknown flag ${arg}.`);
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
  if (/rollout-2026-05-15T13-21-46/.test(value)) {
    fail(`${label} must use the public-safe source session alias, not the private filename`);
  }
}

function runFailureSelfTests() {
  const selfTestEnv = { ...process.env, CLAWIX_UI_COMPLETION_SOURCE_MANIFEST_SELF_TEST: "1" };
  const tests = [
    [["--unknown-flag"], "received unknown flag --unknown-flag"],
    [["--simulate-unsafe-private-path"], "sourceSessionAlias must not publish a local private path"],
    [["--simulate-wrong-goal-alias"], "goalReferenceAlias must match the private goal alias"],
    [["--simulate-wrong-source-session-alias"], "sourceSessionAlias must match the private source session alias"],
    [["--simulate-wrong-private-goal-env"], "privateGoalFileEnv must be CLAWIX_UI_PRIVATE_COMPLETION_GOAL_FILE"],
    [["--simulate-verifier-without-require-approved"], "verificationCommand must require the private completion source verifier"],
    [["--simulate-wrong-external-pending-exit-code"], "externalPendingExitCode must be 2"],
    [["--simulate-wrong-decision-count"], "expectedDecisionCount must be 39"],
    [["--simulate-missing-required-record-type"], "requiredRecordTypes must include event_msg:thread_goal_updated"],
    [["--simulate-zero-minimum-user-messages"], "minimumUserMessages must be a positive integer"],
    [["--simulate-missing-expected-decision-id"], "expectedDecisionIds must contain expectedDecisionCount entries"],
    [["--simulate-duplicate-expected-decision-id"], "expectedDecisionIds must contain expectedDecisionCount entries"],
    [["--simulate-wrong-expected-decision-choice"], "expectedDecisions[0].choice must be"],
    [["--simulate-wrong-decision-conversation-id"], "expectedConversationId must match docs/ui/decision-verification.json.conversationId"],
    [["--simulate-audit-missing-source-alias"], "completion-audit.md must include private-codex-session:019e2b5e-fe48-7231-8e13-49411999b001"],
    [["--simulate-private-verifier-missing-snippet"], "ui_private_completion_source_verify.mjs must include sourceBeforeFirstGoalEvent"],
  ];

  for (const [testArgs, expectedOutput] of tests) {
    const result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, ...testArgs], {
      cwd: rootDir,
      env: selfTestEnv,
      encoding: "utf8",
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status === 0) {
      fail(`self-test ${testArgs.join(" ")} must fail for UI completion source manifest validation`);
      continue;
    }
    if (!output.includes(expectedOutput)) {
      fail(`self-test ${testArgs.join(" ")} output must include ${expectedOutput}`);
    }
  }
}

if (!isSelfTest) runFailureSelfTests();

const manifestPath = "docs/ui/completion-source.manifest.json";
const manifest = readJson(manifestPath);
if (manifest) {
  if (args.has("--simulate-unsafe-private-path")) {
    manifest.sourceSessionAlias = "/Users/private/source-session.jsonl";
  }
  if (args.has("--simulate-wrong-goal-alias")) {
    manifest.goalReferenceAlias = "private-codex-goal:other-plan.md";
  }
  if (args.has("--simulate-wrong-source-session-alias")) {
    manifest.sourceSessionAlias = "private-codex-session:other";
  }
  if (args.has("--simulate-wrong-private-goal-env")) {
    manifest.privateGoalFileEnv = "CLAWIX_UI_OTHER_GOAL_FILE";
  }
  if (args.has("--simulate-verifier-without-require-approved")) {
    manifest.verificationCommand = String(manifest.verificationCommand || "").replace(" --require-approved", "");
  }
  if (args.has("--simulate-wrong-external-pending-exit-code")) {
    manifest.externalPendingExitCode = 1;
  }
  if (args.has("--simulate-wrong-decision-count")) {
    manifest.expectedDecisionCount = 38;
  }
  if (args.has("--simulate-missing-required-record-type")) {
    manifest.sourceSessionRequirements = {
      ...(manifest.sourceSessionRequirements || {}),
      requiredRecordTypes: (manifest.sourceSessionRequirements?.requiredRecordTypes || []).filter(
        (recordType) => recordType !== "event_msg:thread_goal_updated",
      ),
    };
  }
  if (args.has("--simulate-zero-minimum-user-messages")) {
    manifest.sourceSessionRequirements = {
      ...(manifest.sourceSessionRequirements || {}),
      minimumUserMessages: 0,
    };
  }
  if (args.has("--simulate-missing-expected-decision-id") && Array.isArray(manifest.expectedDecisionIds)) {
    manifest.expectedDecisionIds = manifest.expectedDecisionIds.filter((id) => id !== "initial_scope");
  }
  if (args.has("--simulate-duplicate-expected-decision-id") && Array.isArray(manifest.expectedDecisionIds) && manifest.expectedDecisionIds[0]) {
    manifest.expectedDecisionIds = [...manifest.expectedDecisionIds, manifest.expectedDecisionIds[0]];
  }
  if (args.has("--simulate-wrong-expected-decision-choice") && Array.isArray(manifest.expectedDecisions) && manifest.expectedDecisions[0]) {
    manifest.expectedDecisions[0] = {
      ...manifest.expectedDecisions[0],
      choice: "Wrong choice",
    };
  }
}
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "goalReferenceAlias",
  "sourceSessionAlias",
  "privateGoalFileEnv",
  "privateSourceSessionFileEnv",
  "verificationCommand",
  "expectedConversationId",
  "expectedDecisionCount",
  "sourceSessionRequirements",
  "expectedDecisionIds",
  "expectedDecisions",
  "externalPendingExitCode",
]);
scanPublicSafety(manifest, manifestPath);

if (manifest?.goalReferenceAlias !== "private-codex-goal:clawix-interface-governance-plan-2026-05-15.md") {
  fail(`${manifestPath}.goalReferenceAlias must match the private goal alias`);
}
if (manifest?.sourceSessionAlias !== "private-codex-session:019e2b5e-fe48-7231-8e13-49411999b001") {
  fail(`${manifestPath}.sourceSessionAlias must match the private source session alias`);
}
if (manifest?.privateGoalFileEnv !== "CLAWIX_UI_PRIVATE_COMPLETION_GOAL_FILE") {
  fail(`${manifestPath}.privateGoalFileEnv must be CLAWIX_UI_PRIVATE_COMPLETION_GOAL_FILE`);
}
if (manifest?.privateSourceSessionFileEnv !== "CLAWIX_UI_PRIVATE_COMPLETION_SOURCE_SESSION_FILE") {
  fail(`${manifestPath}.privateSourceSessionFileEnv must be CLAWIX_UI_PRIVATE_COMPLETION_SOURCE_SESSION_FILE`);
}
if (!String(manifest?.verificationCommand || "").includes("scripts/ui_private_completion_source_verify.mjs --require-approved")) {
  fail(`${manifestPath}.verificationCommand must require the private completion source verifier`);
}
for (const envName of [manifest?.privateGoalFileEnv, manifest?.privateSourceSessionFileEnv]) {
  if (!String(manifest?.verificationCommand || "").includes(envName)) {
    fail(`${manifestPath}.verificationCommand must include ${envName}`);
  }
}
if (manifest?.externalPendingExitCode !== 2) fail(`${manifestPath}.externalPendingExitCode must be 2`);
if (manifest?.expectedDecisionCount !== 39) fail(`${manifestPath}.expectedDecisionCount must be 39`);
requireFields(manifest?.sourceSessionRequirements, `${manifestPath}.sourceSessionRequirements`, [
  "sessionMetaIdMatchesConversation",
  "decisionsBeforeFirstGoalEvent",
  "minimumUserMessages",
  "requiredRecordTypes",
]);
if (manifest?.sourceSessionRequirements?.sessionMetaIdMatchesConversation !== true) {
  fail(`${manifestPath}.sourceSessionRequirements.sessionMetaIdMatchesConversation must be true`);
}
if (manifest?.sourceSessionRequirements?.decisionsBeforeFirstGoalEvent !== true) {
  fail(`${manifestPath}.sourceSessionRequirements.decisionsBeforeFirstGoalEvent must be true`);
}
if (!Number.isInteger(manifest?.sourceSessionRequirements?.minimumUserMessages) || manifest.sourceSessionRequirements.minimumUserMessages < 1) {
  fail(`${manifestPath}.sourceSessionRequirements.minimumUserMessages must be a positive integer`);
}
const requiredRecordTypes = requireArray(manifest?.sourceSessionRequirements, `${manifestPath}.sourceSessionRequirements`, "requiredRecordTypes");
for (const recordType of ["session_meta", "event_msg:user_message", "response_item:message", "event_msg:thread_goal_updated"]) {
  if (!requiredRecordTypes.includes(recordType)) {
    fail(`${manifestPath}.sourceSessionRequirements.requiredRecordTypes must include ${recordType}`);
  }
}

const decisionVerification = readJson("docs/ui/decision-verification.json");
if (args.has("--simulate-wrong-decision-conversation-id") && decisionVerification) {
  decisionVerification.conversationId = "other-conversation";
}
if (manifest?.expectedConversationId !== decisionVerification?.conversationId) {
  fail(`${manifestPath}.expectedConversationId must match docs/ui/decision-verification.json.conversationId`);
}
if (decisionVerification?.goalReference !== manifest?.goalReferenceAlias) {
  fail(`${manifestPath}.goalReferenceAlias must match docs/ui/decision-verification.json.goalReference`);
}
if (decisionVerification?.sourceSession !== manifest?.sourceSessionAlias) {
  fail(`${manifestPath}.sourceSessionAlias must match docs/ui/decision-verification.json.sourceSession`);
}
const decisions = requireArray(decisionVerification, "docs/ui/decision-verification.json", "decisions");
const expectedDecisionIds = requireArray(manifest, manifestPath, "expectedDecisionIds");
const expectedDecisions = requireArray(manifest, manifestPath, "expectedDecisions");
if (expectedDecisionIds.length !== manifest?.expectedDecisionCount) {
  fail(`${manifestPath}.expectedDecisionIds must contain expectedDecisionCount entries`);
}
if (expectedDecisions.length !== manifest?.expectedDecisionCount) {
  fail(`${manifestPath}.expectedDecisions must contain expectedDecisionCount entries`);
}
if (expectedDecisionIds.length !== decisions.length) {
  fail(`${manifestPath}.expectedDecisionIds must mirror docs/ui/decision-verification.json decisions`);
}
if (expectedDecisions.length !== decisions.length) {
  fail(`${manifestPath}.expectedDecisions must mirror docs/ui/decision-verification.json decisions`);
}
for (const [index, decision] of decisions.entries()) {
  if (expectedDecisionIds[index] !== decision?.id) {
    fail(`${manifestPath}.expectedDecisionIds[${index}] must be ${decision?.id}`);
  }
  const expectedDecision = expectedDecisions[index];
  if (expectedDecision?.id !== decision?.id) {
    fail(`${manifestPath}.expectedDecisions[${index}].id must be ${decision?.id}`);
  }
  if (expectedDecision?.choice !== decision?.choice) {
    fail(`${manifestPath}.expectedDecisions[${index}].choice must be ${decision?.choice}`);
  }
}

let completionAudit = read("docs/ui/completion-audit.md");
if (args.has("--simulate-audit-missing-source-alias")) {
  completionAudit = completionAudit.replace(String(manifest?.sourceSessionAlias || ""), "private-codex-session:missing");
}
for (const snippet of [
  manifest?.goalReferenceAlias,
  manifest?.sourceSessionAlias,
  "private session, not published",
  "Do not call update_goal",
]) {
  if (!completionAudit.includes(snippet)) fail(`docs/ui/completion-audit.md must include ${snippet}`);
}

let privateVerifier = read("scripts/ui_private_completion_source_verify.mjs");
if (args.has("--simulate-private-verifier-missing-snippet")) {
  privateVerifier = privateVerifier.split("sourceBeforeFirstGoalEvent").join("sourceAfterFirstGoalEvent");
}
for (const snippet of [
  "docs/ui/completion-source.manifest.json",
  "EXTERNAL PENDING",
  "process.exit(2)",
  "expectedDecisionIds",
  "expectedDecisions",
  "expectedConversationId",
  "expectedDecisionCount",
  "sourceSessionRequirements",
  "session_meta",
  "event_msg:user_message",
  "thread_goal_",
  "decisionsBeforeFirstGoalEvent",
  "decision.choice",
  "normalizeText",
  "parseJsonlRecords",
  "recordTypeKey",
  "sourceBeforeFirstGoalEvent",
  "enforcePrivateVerifierArgs",
]) {
  if (!privateVerifier.includes(snippet)) {
    fail(`scripts/ui_private_completion_source_verify.mjs must include ${snippet}`);
  }
}
const unknownFlagResult = spawnSync(
  process.execPath,
  [path.join(rootDir, "scripts/ui_private_completion_source_verify.mjs"), "--require-approved", "--unknown-flag"],
  {
    cwd: rootDir,
    encoding: "utf8",
  },
);
if (unknownFlagResult.status === 0 || unknownFlagResult.status === manifest?.externalPendingExitCode) {
  fail("scripts/ui_private_completion_source_verify.mjs must reject unknown flags before private source checks");
}
const unexpectedArgumentResult = spawnSync(
  process.execPath,
  [path.join(rootDir, "scripts/ui_private_completion_source_verify.mjs"), "--require-approved", "unexpected-arg"],
  {
    cwd: rootDir,
    encoding: "utf8",
  },
);
const unexpectedArgumentOutput = `${unexpectedArgumentResult.stdout || ""}${unexpectedArgumentResult.stderr || ""}`;
if (unexpectedArgumentResult.status === 0 || unexpectedArgumentResult.status === manifest?.externalPendingExitCode) {
  fail("scripts/ui_private_completion_source_verify.mjs must reject unexpected positional arguments before private source checks");
}
if (!unexpectedArgumentOutput.includes("received unexpected argument unexpected-arg")) {
  fail("scripts/ui_private_completion_source_verify.mjs must explain unexpected positional arguments");
}
for (const [flag, expectedOutput] of [
  ["--simulate-missing-expected-decision-id", "expectedDecisionIds must contain expectedDecisionCount entries"],
  ["--simulate-duplicate-expected-decision-id", "expectedDecisionIds must contain expectedDecisionCount entries"],
  ["--simulate-wrong-expected-decision-choice", "expectedDecisions[0].choice must be"],
]) {
  const simulatedResult = spawnSync(
    process.execPath,
    [path.join(rootDir, "scripts/ui_private_completion_source_verify.mjs"), "--require-approved", flag],
    {
      cwd: rootDir,
      env: { ...process.env, CLAWIX_UI_ALLOW_COMPLETION_SOURCE_SIMULATION: "1" },
      encoding: "utf8",
    },
  );
  const simulatedOutput = `${simulatedResult.stdout || ""}${simulatedResult.stderr || ""}`;
  if (simulatedResult.status === 0 || simulatedResult.status === manifest?.externalPendingExitCode) {
    fail(`scripts/ui_private_completion_source_verify.mjs must fail before EXTERNAL PENDING for ${flag}`);
  }
  if (!simulatedOutput.includes(expectedOutput)) {
    fail(`scripts/ui_private_completion_source_verify.mjs ${flag} output must include ${expectedOutput}`);
  }
}

if (errors.length > 0) {
  console.error("UI completion source manifest check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI completion source manifest check passed (${expectedDecisionIds.length} decisions)`);
