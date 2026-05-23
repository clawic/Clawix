#!/usr/bin/env node
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const defaultRootDir = path.resolve(new URL("..", import.meta.url).pathname);
const manifestPath = "docs/governance/core-ux-reliability.manifest.json";
const contractPath = "docs/governance/core-ux-reliability.md";
const approvedStatus = "approved-baseline-enforced";
const pendingStatus = "pending-approved-baseline";
const allowedStatuses = new Set(["PASS", "FAIL", "INVALID", "BLOCKED", "PARTIAL", "EXTERNAL_PENDING"]);
const privatePathPattern = /(?:\/Users\/|\.signing\.env|Team ID|signing identity|bundle id|source session|rollout-|\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b)/iu;

function parseArgs(argv) {
  const args = {
    rootDir: defaultRootDir,
    selfTest: false,
    requireApproved: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--root") args.rootDir = path.resolve(argv[++index]);
    else if (arg === "--self-test") args.selfTest = true;
    else if (arg === "--require-approved") args.requireApproved = true;
    else throw new Error(`unknown argument ${arg}`);
  }
  return args;
}

function readText(rootDir, relativePath) {
  return fs.readFileSync(path.join(rootDir, relativePath), "utf8");
}

function readJson(rootDir, relativePath) {
  return JSON.parse(readText(rootDir, relativePath));
}

function requireArray(failures, value, label, minimum = 1) {
  if (!Array.isArray(value) || value.length < minimum) {
    failures.push(`${label} must be an array with at least ${minimum} item(s)`);
    return [];
  }
  return value;
}

function requireObject(failures, value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    failures.push(`${label} must be an object`);
    return {};
  }
  return value;
}

function hasAll(values, required) {
  const seen = new Set(values);
  return required.every((item) => seen.has(item));
}

function validateManifest(manifest, { requireApproved = false } = {}) {
  const failures = [];
  if (manifest.schemaVersion !== 1) failures.push(`${manifestPath} schemaVersion must be 1`);
  if (manifest.program !== "core-ux-reliability") failures.push(`${manifestPath} program must be core-ux-reliability`);
  if (![pendingStatus, approvedStatus].includes(manifest.status)) {
    failures.push(`${manifestPath} status must be ${pendingStatus} or ${approvedStatus}`);
  }
  if (requireApproved && manifest.status !== approvedStatus) {
    failures.push(`${manifestPath} cannot satisfy strict P0 closure until status is ${approvedStatus}`);
  }
  if (manifest.lane !== "core-ux") failures.push(`${manifestPath} lane must be core-ux`);
  if (manifest.publicContract !== contractPath) failures.push(`${manifestPath} publicContract must point to ${contractPath}`);
  if (manifest.privateCommandEnv !== "CLAWIX_CORE_UX_GATE_COMMAND") failures.push(`${manifestPath} privateCommandEnv must be CLAWIX_CORE_UX_GATE_COMMAND`);
  if (manifest.externalEvidenceRootEnv !== "CLAWIX_CORE_UX_PRIVATE_ROOT") failures.push(`${manifestPath} externalEvidenceRootEnv must be CLAWIX_CORE_UX_PRIVATE_ROOT`);
  if (manifest.visibleFlowCommandEnv !== "CLAWIX_CORE_UX_VISIBLE_FLOW_COMMAND") failures.push(`${manifestPath} visibleFlowCommandEnv must be CLAWIX_CORE_UX_VISIBLE_FLOW_COMMAND`);
  if (manifest.visibleFlowEvidenceFileEnv !== "CLAWIX_CORE_UX_VISIBLE_FLOW_EVIDENCE_FILE") failures.push(`${manifestPath} visibleFlowEvidenceFileEnv must be CLAWIX_CORE_UX_VISIBLE_FLOW_EVIDENCE_FILE`);
  if (manifest.metricsFileEnv !== "CLAWIX_CORE_UX_METRICS_FILE") failures.push(`${manifestPath} metricsFileEnv must be CLAWIX_CORE_UX_METRICS_FILE`);
  if (manifest.baselineFileEnv !== "CLAWIX_CORE_UX_BASELINE_FILE") failures.push(`${manifestPath} baselineFileEnv must be CLAWIX_CORE_UX_BASELINE_FILE`);
  if (manifest.strictEnv !== "CLAWIX_CORE_UX_STRICT") failures.push(`${manifestPath} strictEnv must be CLAWIX_CORE_UX_STRICT`);
  if (manifest.approvedBaselineRequiredForPass !== true) failures.push(`${manifestPath} approvedBaselineRequiredForPass must be true`);
  if (manifest.strictReleaseBlocksExternalPending !== true) failures.push(`${manifestPath} strictReleaseBlocksExternalPending must be true`);

  const platforms = requireArray(failures, manifest.platforms, `${manifestPath}.platforms`);
  if (!platforms.some((platform) => platform.id === "macos-real" && platform.p0 === true)) {
    failures.push(`${manifestPath}.platforms must include macos-real as p0`);
  }

  const snapshotGuard = requireObject(failures, manifest.snapshotGuard, `${manifestPath}.snapshotGuard`);
  if (snapshotGuard.trackedFileChangeResult !== "INVALID") {
    failures.push(`${manifestPath}.snapshotGuard.trackedFileChangeResult must be INVALID`);
  }
  if (!hasAll(snapshotGuard.captures ?? [], ["branch", "head", "dirtyStatus", "trackedFileMtimes", "trackedFileSizes"])) {
    failures.push(`${manifestPath}.snapshotGuard.captures must include branch/head/status/mtime/size`);
  }

  const governor = requireObject(failures, manifest.conversationGovernor, `${manifestPath}.conversationGovernor`);
  if (governor.lockRoot !== "external-core-ux-locks") failures.push(`${manifestPath}.conversationGovernor.lockRoot must be external-core-ux-locks`);
  if (governor.maxNewConversationsPerRun !== 1) failures.push(`${manifestPath}.conversationGovernor.maxNewConversationsPerRun must be 1`);
  if (governor.maxNewConversationsPerDay !== 3) failures.push(`${manifestPath}.conversationGovernor.maxNewConversationsPerDay must be 3`);
  if (governor.minimalPrompt !== "reply OK") failures.push(`${manifestPath}.conversationGovernor.minimalPrompt must be reply OK`);
  for (const field of ["mutatesOnlyGateAuthoredLedgerEntries", "reuseRequiresNoActiveGeneration", "archiveRequiresNoActiveGeneration"]) {
    if (governor[field] !== true) failures.push(`${manifestPath}.conversationGovernor.${field} must be true`);
  }

  if (!hasAll(manifest.requiredAppPreflight ?? [], [
    "appModeReal",
    "stableSignedBuild",
    "canonicalAppIdentity",
    "exactlyOneCanonicalPid",
    "zeroNonCanonicalClawixProcesses",
  ])) {
    failures.push(`${manifestPath}.requiredAppPreflight is missing required macOS real-app checks`);
  }

  if (!hasAll(manifest.criticalFlows ?? [], [
    "allChats",
    "pinned",
    "projects",
    "newConversation",
    "minimalReplyOkPrompt",
    "visibleResponse",
    "noActiveGenerationAfterResponse",
  ])) {
    failures.push(`${manifestPath}.criticalFlows is missing required P0 flows`);
  }

  if (!hasAll(manifest.metricFlows ?? [], [
    "startup",
    "sidebarHoverClick",
    "chatScroll",
    "composerTyping",
    "dropdown",
    "terminalSidebarSwitch",
    "idle",
  ])) {
    failures.push(`${manifestPath}.metricFlows is missing required latency/performance flows`);
  }

  const margins = requireObject(failures, manifest.baselineMargins, `${manifestPath}.baselineMargins`);
  const expectedMargins = {
    startupP95Ratio: 1.15,
    interactionP95Ratio: 1.2,
    frameP95Ratio: 1.15,
    memoryDeltaMegabytes: 25,
    hitchesAllowedIncreasePerFlow: 1,
    crashesAllowed: 0,
    hangsAllowed: 0,
  };
  for (const [field, expected] of Object.entries(expectedMargins)) {
    if (margins[field] !== expected) failures.push(`${manifestPath}.baselineMargins.${field} must be ${expected}`);
  }

  const witness = requireObject(failures, manifest.computerUseWitness, `${manifestPath}.computerUseWitness`);
  if (witness.requiredForVisibleP0Closure !== true) failures.push(`${manifestPath}.computerUseWitness.requiredForVisibleP0Closure must be true`);
  if (!hasAll(witness.unavailableStatus ?? [], ["PARTIAL", "EXTERNAL_PENDING"])) {
    failures.push(`${manifestPath}.computerUseWitness.unavailableStatus must include PARTIAL and EXTERNAL_PENDING`);
  }

  const statuses = requireArray(failures, manifest.allowedStatuses, `${manifestPath}.allowedStatuses`, allowedStatuses.size);
  for (const status of allowedStatuses) {
    if (!statuses.includes(status)) failures.push(`${manifestPath}.allowedStatuses is missing ${status}`);
  }

  if (!hasAll(manifest.requiredEvidenceFields ?? [], [
    "status",
    "runId",
    "startedAt",
    "finishedAt",
    "gitSnapshot",
    "appPreflight",
    "crashDelta",
    "conversationGovernor",
    "criticalFlows",
    "metrics",
    "baselineComparison",
    "computerUseWitness",
  ])) {
    failures.push(`${manifestPath}.requiredEvidenceFields is missing required evidence fields`);
  }

  const retention = requireObject(failures, manifest.retention, `${manifestPath}.retention`);
  if (retention.keepLatestSuccessfulRuns !== 10) failures.push(`${manifestPath}.retention.keepLatestSuccessfulRuns must be 10`);
  if (retention.keepAllNonPassUntilResolved !== true) failures.push(`${manifestPath}.retention.keepAllNonPassUntilResolved must be true`);

  const serialized = JSON.stringify(manifest);
  if (privatePathPattern.test(serialized)) {
    failures.push(`${manifestPath} must not contain private paths, identifiers, source sessions, or signing data`);
  }
  return failures;
}

function strictExternalPendingBlocks({ strict, commandStatus, output }) {
  if (!strict) return false;
  return commandStatus === 2 || /\bEXTERNAL PENDING\b/u.test(output);
}

function validateRepository(rootDir, options) {
  const failures = [];
  for (const required of [manifestPath, contractPath, "scripts/test.sh", "docs/decision-map.md", "docs/governance/README.md"]) {
    if (!fs.existsSync(path.join(rootDir, required))) failures.push(`missing ${required}`);
  }
  if (failures.length > 0) return failures;

  const manifest = readJson(rootDir, manifestPath);
  failures.push(...validateManifest(manifest, options));

  const contract = readText(rootDir, contractPath);
  for (const requiredText of [
    "Core UX Reliability Gate",
    "reply OK",
    "EXTERNAL PENDING",
    "INVALID",
    "Computer Use",
    "CLAWIX_CORE_UX_VISIBLE_FLOW_EVIDENCE_FILE",
    "CLAWIX_CORE_UX_METRICS_FILE",
    "startup p95",
  ]) {
    if (!contract.includes(requiredText)) failures.push(`${contractPath} must mention ${requiredText}`);
  }
  if (privatePathPattern.test(contract)) {
    failures.push(`${contractPath} must not contain private paths, identifiers, source sessions, or signing data`);
  }

  const testScript = readText(rootDir, "scripts/test.sh");
  for (const requiredText of [
    "core_ux_tests",
    "CLAWIX_CORE_UX_GATE_COMMAND",
    "CLAWIX_CORE_UX_REQUIRE_APPROVED",
    "core-ux)",
    "CLAWIX_TEST_STRICT_EXTERNAL_PENDING=1 CLAWIX_CORE_UX_REQUIRE_APPROVED=1 core_ux_tests",
  ]) {
    if (!testScript.includes(requiredText)) failures.push(`scripts/test.sh must wire ${requiredText}`);
  }

  const decisionMap = readText(rootDir, "docs/decision-map.md");
  if (!decisionMap.includes("Core UX Reliability Gate")) failures.push("docs/decision-map.md must route Core UX Reliability Gate");
  if (!decisionMap.includes("scripts/core_ux_reliability_check.mjs")) failures.push("docs/decision-map.md must mention the Core UX checker");

  const governanceReadme = readText(rootDir, "docs/governance/README.md");
  if (!governanceReadme.includes("Core UX Reliability")) failures.push("docs/governance/README.md must list Core UX Reliability");

  return failures;
}

function runSelfTest() {
  const completeManifest = {
    schemaVersion: 1,
    program: "core-ux-reliability",
    status: approvedStatus,
    owner: "clawix-macos-real-app",
    lane: "core-ux",
    platforms: [{ id: "macos-real", p0: true, enforcement: "blocking-after-approved-baseline" }],
    publicContract: contractPath,
    privateCommandEnv: "CLAWIX_CORE_UX_GATE_COMMAND",
    externalEvidenceRootEnv: "CLAWIX_CORE_UX_PRIVATE_ROOT",
    visibleFlowCommandEnv: "CLAWIX_CORE_UX_VISIBLE_FLOW_COMMAND",
    visibleFlowEvidenceFileEnv: "CLAWIX_CORE_UX_VISIBLE_FLOW_EVIDENCE_FILE",
    metricsFileEnv: "CLAWIX_CORE_UX_METRICS_FILE",
    baselineFileEnv: "CLAWIX_CORE_UX_BASELINE_FILE",
    strictEnv: "CLAWIX_CORE_UX_STRICT",
    approvedBaselineRequiredForPass: true,
    strictReleaseBlocksExternalPending: true,
    snapshotGuard: {
      trackedFileChangeResult: "INVALID",
      captures: ["branch", "head", "dirtyStatus", "trackedFileMtimes", "trackedFileSizes"],
    },
    conversationGovernor: {
      lockRoot: "external-core-ux-locks",
      maxNewConversationsPerRun: 1,
      maxNewConversationsPerDay: 3,
      minimalPrompt: "reply OK",
      mutatesOnlyGateAuthoredLedgerEntries: true,
      reuseRequiresNoActiveGeneration: true,
      archiveRequiresNoActiveGeneration: true,
    },
    requiredAppPreflight: ["appModeReal", "stableSignedBuild", "canonicalAppIdentity", "exactlyOneCanonicalPid", "zeroNonCanonicalClawixProcesses"],
    criticalFlows: ["allChats", "pinned", "projects", "newConversation", "minimalReplyOkPrompt", "visibleResponse", "noActiveGenerationAfterResponse"],
    metricFlows: ["startup", "sidebarHoverClick", "chatScroll", "composerTyping", "dropdown", "terminalSidebarSwitch", "idle"],
    baselineMargins: {
      startupP95Ratio: 1.15,
      interactionP95Ratio: 1.2,
      frameP95Ratio: 1.15,
      memoryDeltaMegabytes: 25,
      hitchesAllowedIncreasePerFlow: 1,
      crashesAllowed: 0,
      hangsAllowed: 0,
    },
    computerUseWitness: {
      requiredForVisibleP0Closure: true,
      unavailableStatus: ["PARTIAL", "EXTERNAL_PENDING"],
      notRequiredForRoutineProgrammaticNightly: true,
    },
    allowedStatuses: [...allowedStatuses],
    requiredEvidenceFields: ["status", "runId", "startedAt", "finishedAt", "gitSnapshot", "appPreflight", "crashDelta", "conversationGovernor", "criticalFlows", "metrics", "baselineComparison", "computerUseWitness"],
    retention: {
      keepLatestSuccessfulRuns: 10,
      keepAllNonPassUntilResolved: true,
    },
  };

  const incomplete = { ...completeManifest };
  delete incomplete.conversationGovernor;
  if (validateManifest(incomplete).length === 0) throw new Error("self-test failed: incomplete manifest should fail");

  const pending = { ...completeManifest, status: pendingStatus };
  if (validateManifest(pending, { requireApproved: true }).length === 0) {
    throw new Error("self-test failed: pending baseline should not satisfy strict approval");
  }

  if (!strictExternalPendingBlocks({ strict: true, commandStatus: 2, output: "" })) {
    throw new Error("self-test failed: strict status 2 should block");
  }
  if (!strictExternalPendingBlocks({ strict: true, commandStatus: 0, output: "EXTERNAL PENDING core-ux lane" })) {
    throw new Error("self-test failed: strict EXTERNAL PENDING output should block");
  }
  if (strictExternalPendingBlocks({ strict: false, commandStatus: 2, output: "EXTERNAL PENDING" })) {
    throw new Error("self-test failed: non-strict external pending should not block");
  }

  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "clawix-core-ux-check."));
  try {
    fs.mkdirSync(path.join(tmp, "docs/governance"), { recursive: true });
    fs.mkdirSync(path.join(tmp, "scripts"), { recursive: true });
    fs.writeFileSync(path.join(tmp, manifestPath), `${JSON.stringify(completeManifest, null, 2)}\n`);
    fs.writeFileSync(path.join(tmp, contractPath), "# Core UX Reliability Gate\nreply OK\nEXTERNAL PENDING\nINVALID\nComputer Use\nCLAWIX_CORE_UX_VISIBLE_FLOW_EVIDENCE_FILE\nCLAWIX_CORE_UX_METRICS_FILE\nstartup p95\n");
    fs.writeFileSync(path.join(tmp, "docs/decision-map.md"), "Core UX Reliability Gate scripts/core_ux_reliability_check.mjs\n");
    fs.writeFileSync(path.join(tmp, "docs/governance/README.md"), "Core UX Reliability\n");
    fs.writeFileSync(path.join(tmp, "scripts/test.sh"), "core_ux_tests CLAWIX_CORE_UX_GATE_COMMAND CLAWIX_CORE_UX_REQUIRE_APPROVED core-ux) CLAWIX_TEST_STRICT_EXTERNAL_PENDING=1 CLAWIX_CORE_UX_REQUIRE_APPROVED=1 core_ux_tests\n");
    const failures = validateRepository(tmp, { requireApproved: true });
    if (failures.length > 0) throw new Error(`self-test failed: complete fixture failed: ${failures.join("; ")}`);
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

const args = parseArgs(process.argv.slice(2));
if (args.selfTest) {
  runSelfTest();
  console.error("core UX reliability self-test passed");
  process.exit(0);
}

const failures = validateRepository(args.rootDir, { requireApproved: args.requireApproved });
if (failures.length > 0) {
  for (const failure of failures) console.error(`core UX reliability check failed: ${failure}`);
  process.exit(1);
}
console.error("core UX reliability check passed");
