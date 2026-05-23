#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { enforcePrivateVerifierArgs } from "./ui_private_verifier_args.mjs";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = process.argv.slice(2);
const isSelfTest = process.env.CLAWIX_UI_COMPLETION_SOURCE_VERIFY_SELF_TEST === "1";
const errors = [];

function fail(message) {
  errors.push(message);
}

function hasFlag(name) {
  return args.includes(name);
}

enforcePrivateVerifierArgs(args, {
  label: "UI private completion source verification",
  allowedFlags: [
    "--require-approved",
    "--simulate-missing-expected-decision-id",
    "--simulate-duplicate-expected-decision-id",
    "--simulate-wrong-expected-decision-choice",
  ],
  testOnlyFlags: [
    "--simulate-missing-expected-decision-id",
    "--simulate-duplicate-expected-decision-id",
    "--simulate-wrong-expected-decision-choice",
  ],
  testOnlyEnv: "CLAWIX_UI_ALLOW_COMPLETION_SOURCE_SIMULATION",
});

function readJson(relativePath) {
  return JSON.parse(fs.readFileSync(path.join(rootDir, relativePath), "utf8"));
}

function normalizeText(value) {
  return String(value || "")
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .toLowerCase();
}

function assertPrivateFile(file, envName) {
  const resolved = path.resolve(file);
  const relativeToRepo = path.relative(rootDir, resolved);
  if (!relativeToRepo.startsWith("..") && !path.isAbsolute(relativeToRepo)) {
    fail(`${envName} must point outside the public repository`);
  }
  if (!fs.existsSync(resolved) || !fs.statSync(resolved).isFile()) {
    fail(`${envName} does not point to an existing file`);
    return null;
  }
  return resolved;
}

function countJsonlRecords(file) {
  let count = 0;
  forEachJsonlLine(file, (line) => {
    if (line.trim() !== "") count += 1;
  });
  return count;
}

function parseJsonlRecords(file, label) {
  const records = [];
  forEachJsonlLine(file, (line, index) => {
    if (line.trim() === "") return;
    try {
      records.push(JSON.parse(line));
    } catch (error) {
      fail(`${label} line ${index + 1} is not valid JSON: ${error.message}`);
    }
  });
  return records;
}

function forEachJsonlLine(file, visit, { chunkBytes = 64 * 1024 } = {}) {
  const fd = fs.openSync(file, "r");
  const buffer = Buffer.alloc(chunkBytes);
  let carry = "";
  let index = 0;
  try {
    for (;;) {
      const bytesRead = fs.readSync(fd, buffer, 0, buffer.length, null);
      if (bytesRead === 0) break;
      carry += buffer.toString("utf8", 0, bytesRead);
      let newlineIndex;
      while ((newlineIndex = carry.indexOf("\n")) >= 0) {
        const line = carry.slice(0, newlineIndex).replace(/\r$/u, "");
        carry = carry.slice(newlineIndex + 1);
        visit(line, index);
        index += 1;
      }
    }
    if (carry.length > 0) visit(carry.replace(/\r$/u, ""), index);
  } finally {
    fs.closeSync(fd);
  }
}

function recordTypeKey(record) {
  return record?.payload?.type ? `${record.type}:${record.payload.type}` : String(record?.type || "");
}

function recordText(record) {
  return JSON.stringify(record || "");
}

function sourceBeforeFirstGoalEvent(records) {
  const firstGoalEventIndex = records.findIndex((record) => recordTypeKey(record).startsWith("event_msg:thread_goal_"));
  const sourceRecords = firstGoalEventIndex >= 0 ? records.slice(0, firstGoalEventIndex) : records;
  return sourceRecords.map(recordText).join("\n");
}

function runFailureSelfTests(goalEnv, sessionEnv) {
  const selfTestEnv = {
    ...process.env,
    CLAWIX_UI_COMPLETION_SOURCE_VERIFY_SELF_TEST: "1",
  };
  delete selfTestEnv[goalEnv];
  delete selfTestEnv[sessionEnv];
  delete selfTestEnv.CLAWIX_UI_ALLOW_COMPLETION_SOURCE_SIMULATION;
  const missingGoalFile = path.join(os.tmpdir(), `clawix-ui-completion-goal-missing-${process.pid}.md`);
  const missingSessionFile = path.join(os.tmpdir(), `clawix-ui-completion-session-missing-${process.pid}.jsonl`);
  const tests = [
    [[], {}, "requires --require-approved"],
    [["--require-approved", "--unknown-flag"], {}, "received unknown flag --unknown-flag"],
    [
      ["--require-approved", "--simulate-missing-expected-decision-id"],
      {},
      "CLAWIX_UI_ALLOW_COMPLETION_SOURCE_SIMULATION",
    ],
    [
      ["--require-approved"],
      { [goalEnv]: rootDir, [sessionEnv]: rootDir },
      `${goalEnv} must point outside the public repository`,
    ],
    [
      ["--require-approved"],
      { [goalEnv]: missingGoalFile, [sessionEnv]: missingSessionFile },
      `${goalEnv} does not point to an existing file`,
    ],
    [
      ["--require-approved", "--simulate-missing-expected-decision-id"],
      { CLAWIX_UI_ALLOW_COMPLETION_SOURCE_SIMULATION: "1" },
      "expectedDecisionIds must contain expectedDecisionCount entries",
    ],
    [
      ["--require-approved", "--simulate-duplicate-expected-decision-id"],
      { CLAWIX_UI_ALLOW_COMPLETION_SOURCE_SIMULATION: "1" },
      "expectedDecisionIds must not contain duplicate decisions",
    ],
    [
      ["--require-approved", "--simulate-wrong-expected-decision-choice"],
      { CLAWIX_UI_ALLOW_COMPLETION_SOURCE_SIMULATION: "1" },
      "expectedDecisions[0].choice must be Cross-platform desde dia 1",
    ],
  ];

  for (const [testArgs, extraEnv, expectedOutput] of tests) {
    const result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, ...testArgs], {
      cwd: rootDir,
      env: { ...selfTestEnv, ...extraEnv },
      encoding: "utf8",
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status === 0) {
      fail(`self-test ${testArgs.join(" ") || "<no args>"} must fail for private completion source verification`);
      continue;
    }
    if (!output.includes(expectedOutput)) {
      fail(`self-test ${testArgs.join(" ") || "<no args>"} output must include ${expectedOutput}`);
    }
  }
}

if (!hasFlag("--require-approved")) {
  console.error("UI private completion source verification requires --require-approved.");
  process.exit(1);
}

const manifest = readJson("docs/ui/completion-source.manifest.json");
if (hasFlag("--simulate-missing-expected-decision-id") && Array.isArray(manifest.expectedDecisionIds)) {
  manifest.expectedDecisionIds = manifest.expectedDecisionIds.filter((id) => id !== "initial_scope");
}
if (hasFlag("--simulate-duplicate-expected-decision-id") && Array.isArray(manifest.expectedDecisionIds) && manifest.expectedDecisionIds[0]) {
  manifest.expectedDecisionIds = [...manifest.expectedDecisionIds, manifest.expectedDecisionIds[0]];
}
if (hasFlag("--simulate-wrong-expected-decision-choice") && Array.isArray(manifest.expectedDecisions) && manifest.expectedDecisions[0]) {
  manifest.expectedDecisions[0] = {
    ...manifest.expectedDecisions[0],
    choice: "Wrong choice",
  };
}
const decisionVerification = readJson("docs/ui/decision-verification.json");
const decisions = Array.isArray(decisionVerification.decisions) ? decisionVerification.decisions : [];
const decisionsById = new Map(decisions.map((decision) => [decision.id, decision]));
const expectedDecisionIds = Array.isArray(manifest.expectedDecisionIds) ? manifest.expectedDecisionIds : [];
const expectedDecisions = Array.isArray(manifest.expectedDecisions)
  ? manifest.expectedDecisions
  : expectedDecisionIds.map((id) => ({ id }));
const expectedDecisionIdSet = new Set(expectedDecisionIds);
if (!Number.isInteger(manifest.expectedDecisionCount) || manifest.expectedDecisionCount <= 0) {
  fail("docs/ui/completion-source.manifest.json expectedDecisionCount must be a positive integer");
}
if (expectedDecisionIds.length !== manifest.expectedDecisionCount) {
  fail("docs/ui/completion-source.manifest.json expectedDecisionIds must contain expectedDecisionCount entries");
}
if (expectedDecisions.length !== manifest.expectedDecisionCount) {
  fail("docs/ui/completion-source.manifest.json expectedDecisions must contain expectedDecisionCount entries");
}
if (expectedDecisionIdSet.size !== expectedDecisionIds.length) {
  fail("docs/ui/completion-source.manifest.json expectedDecisionIds must not contain duplicate decisions");
}
if (expectedDecisionIds.length !== decisions.length) {
  fail("docs/ui/completion-source.manifest.json expectedDecisionIds must mirror decision-verification decisions");
}
if (expectedDecisions.length !== decisions.length) {
  fail("docs/ui/completion-source.manifest.json expectedDecisions must mirror decision-verification decisions");
}
for (const [index, decision] of decisions.entries()) {
  if (expectedDecisionIds[index] !== decision?.id) {
    fail(`docs/ui/completion-source.manifest.json expectedDecisionIds[${index}] must be ${decision?.id}`);
  }
  const expectedDecision = expectedDecisions[index];
  if (expectedDecision?.id !== decision?.id) {
    fail(`docs/ui/completion-source.manifest.json expectedDecisions[${index}].id must be ${decision?.id}`);
  }
  if (expectedDecision?.choice !== decision?.choice) {
    fail(`docs/ui/completion-source.manifest.json expectedDecisions[${index}].choice must be ${decision?.choice}`);
  }
}

if (errors.length > 0) {
  console.error("UI private completion source verification failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

const goalEnv = manifest.privateGoalFileEnv;
const sessionEnv = manifest.privateSourceSessionFileEnv;
if (!isSelfTest) {
  runFailureSelfTests(goalEnv, sessionEnv);
}
const missingEnv = [goalEnv, sessionEnv].filter((envName) => !process.env[envName]);
if (missingEnv.length > 0) {
  console.error(`EXTERNAL PENDING: set ${missingEnv.join(", ")} to verify private completion sources.`);
  process.exit(2);
}

const goalFile = assertPrivateFile(process.env[goalEnv], goalEnv);
const sessionFile = assertPrivateFile(process.env[sessionEnv], sessionEnv);
const goalSource = goalFile ? fs.readFileSync(goalFile, "utf8") : "";
const sessionSource = sessionFile ? fs.readFileSync(sessionFile, "utf8") : "";
const sessionRecords = sessionFile ? parseJsonlRecords(sessionFile, sessionEnv) : [];
const normalizedGoalSource = normalizeText(goalSource);
const normalizedSessionSource = normalizeText(sessionSource);
const normalizedPreGoalSessionSource = normalizeText(sourceBeforeFirstGoalEvent(sessionRecords));
const sourceSessionRequirements = manifest.sourceSessionRequirements || {};
const sessionMeta = sessionRecords.find((record) => record?.type === "session_meta");
const privateConversationId = sessionMeta?.payload?.id ? String(sessionMeta.payload.id) : "";

for (const snippet of [
  "Required Decision Verification Checklist",
  "Do not mark the associated goal complete",
  "update_goal(status:",
]) {
  if (!goalSource.includes(snippet)) fail(`${goalEnv} must include ${snippet}`);
}
if (privateConversationId && !goalSource.includes(privateConversationId)) {
  fail(`${goalEnv} must include the private source conversation id`);
}
if (privateConversationId && !sessionSource.includes(privateConversationId)) {
  fail(`${sessionEnv} must include the private source conversation id`);
}
if (sessionFile && countJsonlRecords(sessionFile) < manifest.expectedDecisionCount) {
  fail(`${sessionEnv} must contain enough JSONL records to cover the source conversation`);
}
if (sourceSessionRequirements.sessionMetaIdMatchesConversation) {
  if (!sessionMeta) {
    fail(`${sessionEnv} must contain a session_meta record`);
  } else if (!privateConversationId) {
    fail(`${sessionEnv} session_meta id must be a non-empty private conversation id`);
  }
}
const userMessageCount = sessionRecords.filter((record) => recordTypeKey(record) === "event_msg:user_message").length;
if (userMessageCount < Number(sourceSessionRequirements.minimumUserMessages || 0)) {
  fail(`${sessionEnv} must contain at least ${sourceSessionRequirements.minimumUserMessages} user message records`);
}
for (const recordType of sourceSessionRequirements.requiredRecordTypes || []) {
  if (!sessionRecords.some((record) => recordTypeKey(record) === recordType)) {
    fail(`${sessionEnv} must contain record type ${recordType}`);
  }
}

for (const expectedDecision of expectedDecisions) {
  const decisionId = expectedDecision.id;
  const decision = decisionsById.get(decisionId);
  if (!goalSource.includes(`\`${decisionId}\``)) {
    fail(`${goalEnv} must include decision ${decisionId}`);
  }
  if (!sessionSource.includes(decisionId)) {
    fail(`${sessionEnv} must include decision ${decisionId}`);
  }
  if (expectedDecision.choice && decision?.choice !== expectedDecision.choice) {
    fail(`docs/ui/decision-verification.json choice for ${decisionId} must be ${expectedDecision.choice}`);
  }
  if (!decision?.choice) {
    fail(`docs/ui/decision-verification.json must include a choice for ${decisionId}`);
    continue;
  }
  const normalizedChoice = normalizeText(decision.choice);
  if (!normalizedGoalSource.includes(normalizedChoice)) {
    fail(`${goalEnv} must include choice ${decision.choice} for decision ${decisionId}`);
  }
  if (!normalizedSessionSource.includes(normalizedChoice)) {
    fail(`${sessionEnv} must include choice ${decision.choice} for decision ${decisionId}`);
  }
  if (sourceSessionRequirements.decisionsBeforeFirstGoalEvent) {
    if (!normalizedPreGoalSessionSource.includes(decisionId)) {
      fail(`${sessionEnv} must include decision ${decisionId} before the first thread goal event`);
    }
    if (!normalizedPreGoalSessionSource.includes(normalizedChoice)) {
      fail(`${sessionEnv} must include choice ${decision.choice} before the first thread goal event`);
    }
  }
}

if (errors.length > 0) {
  console.error("UI private completion source verification failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI private completion source verification passed (${expectedDecisions.length} decisions)`);
