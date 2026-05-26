#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const clawixRoot = path.resolve(scriptDir, "..");
const defaultClawjsRoot = path.resolve(clawixRoot, "..", "..", "clawjs");
const clawjsRoot = process.env.CLAWJS_ROOT ? path.resolve(process.env.CLAWJS_ROOT) : defaultClawjsRoot;
const generatorPath = path.join(clawixRoot, "scripts", "generate_macos_ux_trace_fixtures.mjs");
const registryPath = path.join(clawixRoot, "docs", "ui", "ux-trace-harness.registry.json");

const fallbackRequiredProfiles = [
  "smoke",
  "medium",
  "dense-sidebar",
  "dense-chat",
  "streaming-heavy",
  "terminal-under-load",
  "worst-case",
  "real-equivalent-private",
];

const fallbackRequiredScalingDimensions = [
  "conversationCount",
  "activeConversationCount",
  "pinnedConversationCount",
  "projectCount",
  "conversationsPerProject",
  "archivedConversationCount",
  "titleLengthDistribution",
  "timestampDistribution",
  "unreadRunningErrorStates",
  "messageCountPerConversation",
  "latestMessageLength",
  "middleMessageLength",
  "oldHistoryPageCount",
  "markdownDensity",
  "codeBlockDensity",
  "tableListQuoteDensity",
  "toolActionWorkSummaryDensity",
  "streamingDeltaCount",
  "streamingDeltaByteSize",
  "attachmentMetadataCount",
  "imageFilePlaceholderCount",
  "errorRetryCancelStates",
  "sidebarRowHeightVariance",
  "searchVisibleTextVolume",
  "incrementalMetadataChurn",
  "databaseRowCount",
  "bridgePayloadBytes",
  "idleTimerPressure",
];

const realEquivalentPressureDimensions = [
  "conversationCount",
  "activeConversationCount",
  "pinnedConversationCount",
  "projectCount",
  "archivedConversationCount",
  "unreadRunningErrorStates",
  "latestMessageLength",
  "middleMessageLength",
  "oldHistoryPageCount",
  "markdownDensity",
  "codeBlockDensity",
  "tableListQuoteDensity",
  "toolActionWorkSummaryDensity",
  "streamingDeltaCount",
  "streamingDeltaByteSize",
  "attachmentMetadataCount",
  "imageFilePlaceholderCount",
  "errorRetryCancelStates",
  "searchVisibleTextVolume",
  "incrementalMetadataChurn",
  "databaseRowCount",
  "bridgePayloadBytes",
  "idleTimerPressure",
];

function fail(message) {
  console.error(`Clawix scale lab fixture check failed: ${message}`);
  process.exit(1);
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function registryFixtureContract() {
  if (!fs.existsSync(registryPath)) {
    return {
      requiredProfiles: fallbackRequiredProfiles,
      requiredScalingDimensions: fallbackRequiredScalingDimensions,
    };
  }
  const registry = readJson(registryPath);
  return {
    requiredProfiles: (registry.fixtureProfiles || []).map((profile) => profile.id).filter(Boolean),
    requiredScalingDimensions: registry.scalingDimensions || fallbackRequiredScalingDimensions,
  };
}

function runNode(args, options = {}) {
  const result = spawnSync(process.execPath, args, {
    cwd: clawixRoot,
    encoding: "utf8",
    ...options,
  });
  if (result.status !== 0) {
    process.stderr.write(result.stderr);
    process.stderr.write(result.stdout);
    process.exit(result.status ?? 1);
  }
  return result.stdout;
}

function assertMacOSFixturePack(profile, outDir, requiredScalingDimensions) {
  const manifestPath = path.join(outDir, "manifest.json");
  const threadsPath = path.join(outDir, "threads.json");
  for (const file of [
    manifestPath,
    threadsPath,
    path.join(outDir, "pinned-thread-ids.json"),
    path.join(outDir, "stream-plan.json"),
    path.join(outDir, "metadata-churn-plan.json"),
    path.join(outDir, "terminal-output.log"),
  ]) {
    if (!fs.existsSync(file)) fail(`generated ${profile} pack is missing ${path.basename(file)}`);
  }
  const manifest = readJson(manifestPath);
  const threads = readJson(threadsPath);
  if (manifest.program !== "macos-ux-trace-fixture-generator") fail(`${profile} manifest has wrong program`);
  if (manifest.profile !== profile) fail(`${profile} manifest has wrong profile`);
  if (manifest.privateBoundary?.privateContentExported !== false) fail(`${profile} manifest must reject private export`);
  if (manifest.counts?.threads !== threads.length) fail(`${profile} manifest thread count does not match threads.json`);
  if (manifest.counts?.heavyRollouts < 1) fail(`${profile} pack must contain at least one heavy rollout`);
  for (const dimension of requiredScalingDimensions) {
    if (manifest.scalingDimensions?.[dimension] === undefined) fail(`${profile} manifest missing scaling dimension ${dimension}`);
  }
  for (const [index, thread] of threads.entries()) {
    for (const field of ["id", "cwd", "name", "preview", "path", "createdAt", "updatedAt", "archived"]) {
      if (thread[field] === undefined || thread[field] === null || thread[field] === "") {
        fail(`${profile} thread ${index} is missing ${field}`);
      }
    }
    if (!String(thread.path).startsWith(outDir)) fail(`${profile} thread ${thread.id} path must stay inside generated pack`);
    if (!fs.existsSync(thread.path)) fail(`${profile} rollout missing for ${thread.id}`);
  }
  const firstRollout = fs.readFileSync(threads[0].path, "utf8").trim().split(/\n/).map((line) => JSON.parse(line));
  if (firstRollout[0]?.type !== "session_meta") fail(`${profile} first rollout must begin with session_meta`);
  if (!firstRollout.some((record) => record.type === "event_msg" && record.payload?.type === "user_message")) fail(`${profile} rollout missing user_message`);
  if (!firstRollout.some((record) => record.type === "event_msg" && record.payload?.type === "agent_message" && record.payload?.phase === "final_answer")) fail(`${profile} rollout missing final assistant message`);
  if (!firstRollout.some((record) => record.type === "event_msg" && record.payload?.type === "exec_command_end")) fail(`${profile} rollout missing tool/work summary event`);
  return manifest;
}

function dimensionValue(profile, dimension) {
  if (!profile?.scalingDimensions || profile.scalingDimensions[dimension] === undefined) {
    fail(`${profile?.id || "unknown"} listed profile missing scaling dimension ${dimension}`);
  }
  return profile.scalingDimensions[dimension];
}

function numericDimension(profile, dimension) {
  const value = dimensionValue(profile, dimension);
  if (typeof value !== "number" || !Number.isFinite(value)) {
    fail(`${profile.id} scaling dimension ${dimension} must be numeric`);
  }
  return value;
}

function assertListedProfileScaling(listedProfiles, requiredProfiles, requiredScalingDimensions) {
  const byId = new Map(listedProfiles.map((profile) => [profile.id, profile]));
  for (const profile of requiredProfiles) {
    if (!byId.has(profile)) fail(`fixture generator is missing profile ${profile}`);
  }
  for (const profile of byId.values()) {
    for (const dimension of requiredScalingDimensions) {
      dimensionValue(profile, dimension);
    }
  }
  const worst = byId.get("worst-case");
  const realEquivalent = byId.get("real-equivalent-private");
  if (!worst || !realEquivalent) return;
  for (const dimension of realEquivalentPressureDimensions) {
    if (numericDimension(realEquivalent, dimension) < numericDimension(worst, dimension)) {
      fail(`real-equivalent-private ${dimension} must be >= worst-case`);
    }
  }
  for (const field of ["default", "heavy", "heavyConversationCount"]) {
    const realValue = dimensionValue(realEquivalent, "messageCountPerConversation")?.[field];
    const worstValue = dimensionValue(worst, "messageCountPerConversation")?.[field];
    if (typeof realValue !== "number" || typeof worstValue !== "number" || realValue < worstValue) {
      fail(`real-equivalent-private messageCountPerConversation.${field} must be >= worst-case`);
    }
  }
}

if (!fs.existsSync(path.join(clawjsRoot, "scripts", "scale-lab.ts"))) {
  console.error(`EXTERNAL PENDING scale lab fixture: missing ClawJS scale lab at ${clawjsRoot}`);
  process.exit(2);
}
if (!fs.existsSync(generatorPath)) {
  fail(`missing macOS UX trace fixture generator at ${generatorPath}`);
}

const scratchRoot = fs.mkdtempSync(path.join(os.tmpdir(), "clawix-scale-lab-fixture-"));
const reportPath = path.join(scratchRoot, "scale-lab-report.json");
const lockPath = path.join(scratchRoot, "scale.lock");
try {
  const { requiredProfiles, requiredScalingDimensions } = registryFixtureContract();
  const listedProfiles = JSON.parse(runNode([generatorPath, "--list"]));
  assertListedProfileScaling(listedProfiles, requiredProfiles, requiredScalingDimensions);
  const listedIds = new Set(listedProfiles.map((profile) => profile.id));

  const fixtureA = path.join(scratchRoot, "macos-fixture-a");
  const fixtureB = path.join(scratchRoot, "macos-fixture-b");
  runNode([generatorPath, "--profile", "smoke", "--seed", "scale-lab-check", "--out-dir", fixtureA, "--json"]);
  runNode([generatorPath, "--profile", "smoke", "--seed", "scale-lab-check", "--out-dir", fixtureB, "--json"]);
  const manifestA = assertMacOSFixturePack("smoke", fixtureA, requiredScalingDimensions);
  const manifestB = assertMacOSFixturePack("smoke", fixtureB, requiredScalingDimensions);
  if (manifestA.manifestHash !== manifestB.manifestHash) {
    fail("fixture generator must be deterministic for the same profile and seed");
  }

  const result = spawnSync("npm", [
    "run",
    "scale:lab",
    "--",
    "--profile",
    "smoke",
    "--workload",
    "sessions,attachments",
    "--report",
    reportPath,
    "--lock",
    lockPath,
    "--json",
  ], {
    cwd: clawjsRoot,
    encoding: "utf8",
    env: {
      ...process.env,
      CLAW_HOME: path.join(scratchRoot, "home"),
      CLAW_DATA_DIR: path.join(scratchRoot, "home", "data"),
    },
  });

  if (result.status !== 0) {
    process.stderr.write(result.stderr);
    process.stderr.write(result.stdout);
    process.exit(result.status ?? 1);
  }

  const report = JSON.parse(fs.readFileSync(reportPath, "utf8"));
  if (report.ok !== true) {
    fail("report is not ok");
  }
  if (report.cleanup?.status !== "removed") {
    fail("Scale Lab did not clean up its temporary root");
  }
  const workloadNames = new Set((report.workloads ?? []).map((workload) => workload.name));
  if (!workloadNames.has("sessions") || !workloadNames.has("attachments")) {
    fail("expected sessions and attachments workloads");
  }
  console.log(JSON.stringify({
    ok: true,
    profile: report.profile,
    workloads: [...workloadNames],
    macosFixtureGenerator: {
      profiles: [...listedIds],
      smokeThreads: manifestA.counts.threads,
      smokeRolloutJsonlLines: manifestA.counts.rolloutJsonlLines,
      deterministicHash: manifestA.manifestHash,
    },
    externalPending: report.externalPending,
  }, null, 2));
} finally {
  fs.rmSync(scratchRoot, { recursive: true, force: true });
}
