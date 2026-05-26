#!/usr/bin/env node
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const generatorVersion = 1;
const program = "macos-ux-trace-fixture-generator";
const baseEpochSeconds = Date.parse("2026-01-15T12:00:00.000Z") / 1000;

const profileDefinitions = {
  "smoke": {
    conversationCount: 12,
    activeConversationCount: 2,
    pinnedConversationCount: 3,
    projectCount: 3,
    archivedConversationCount: 1,
    messagesPerConversation: 10,
    heavyMessagesPerConversation: 24,
    heavyConversationCount: 1,
    oldHistoryPageCount: 1,
    streamingDeltaCount: 16,
    streamingDeltaByteSize: 64,
    attachmentMetadataCount: 6,
    imageFilePlaceholderCount: 3,
    toolActionWorkSummaryDensity: 0.18,
    markdownDensity: 0.2,
    codeBlockDensity: 0.12,
    tableListQuoteDensity: 0.12,
    sidebarRowHeightVariance: "low",
    searchVisibleTextVolume: 1_500,
    incrementalMetadataChurn: 12,
    databaseRowCount: 120,
    bridgePayloadBytes: 32_768,
    idleTimerPressure: 2,
  },
  "medium": {
    conversationCount: 180,
    activeConversationCount: 12,
    pinnedConversationCount: 24,
    projectCount: 18,
    archivedConversationCount: 20,
    messagesPerConversation: 18,
    heavyMessagesPerConversation: 120,
    heavyConversationCount: 6,
    oldHistoryPageCount: 4,
    streamingDeltaCount: 80,
    streamingDeltaByteSize: 128,
    attachmentMetadataCount: 160,
    imageFilePlaceholderCount: 36,
    toolActionWorkSummaryDensity: 0.26,
    markdownDensity: 0.34,
    codeBlockDensity: 0.18,
    tableListQuoteDensity: 0.2,
    sidebarRowHeightVariance: "medium",
    searchVisibleTextVolume: 30_000,
    incrementalMetadataChurn: 260,
    databaseRowCount: 4_200,
    bridgePayloadBytes: 786_432,
    idleTimerPressure: 14,
  },
  "dense-sidebar": {
    conversationCount: 2_400,
    activeConversationCount: 180,
    pinnedConversationCount: 220,
    projectCount: 72,
    archivedConversationCount: 260,
    messagesPerConversation: 6,
    heavyMessagesPerConversation: 48,
    heavyConversationCount: 20,
    oldHistoryPageCount: 2,
    streamingDeltaCount: 40,
    streamingDeltaByteSize: 96,
    attachmentMetadataCount: 420,
    imageFilePlaceholderCount: 96,
    toolActionWorkSummaryDensity: 0.14,
    markdownDensity: 0.18,
    codeBlockDensity: 0.08,
    tableListQuoteDensity: 0.16,
    sidebarRowHeightVariance: "high",
    searchVisibleTextVolume: 260_000,
    incrementalMetadataChurn: 3_600,
    databaseRowCount: 18_000,
    bridgePayloadBytes: 4_194_304,
    idleTimerPressure: 32,
  },
  "dense-chat": {
    conversationCount: 96,
    activeConversationCount: 12,
    pinnedConversationCount: 16,
    projectCount: 12,
    archivedConversationCount: 8,
    messagesPerConversation: 16,
    heavyMessagesPerConversation: 2_400,
    heavyConversationCount: 3,
    oldHistoryPageCount: 24,
    streamingDeltaCount: 160,
    streamingDeltaByteSize: 192,
    attachmentMetadataCount: 300,
    imageFilePlaceholderCount: 72,
    toolActionWorkSummaryDensity: 0.42,
    markdownDensity: 0.55,
    codeBlockDensity: 0.34,
    tableListQuoteDensity: 0.36,
    sidebarRowHeightVariance: "medium",
    searchVisibleTextVolume: 420_000,
    incrementalMetadataChurn: 700,
    databaseRowCount: 230_000,
    bridgePayloadBytes: 12_582_912,
    idleTimerPressure: 22,
  },
  "streaming-heavy": {
    conversationCount: 220,
    activeConversationCount: 60,
    pinnedConversationCount: 32,
    projectCount: 24,
    archivedConversationCount: 18,
    messagesPerConversation: 14,
    heavyMessagesPerConversation: 480,
    heavyConversationCount: 8,
    oldHistoryPageCount: 8,
    streamingDeltaCount: 900,
    streamingDeltaByteSize: 256,
    attachmentMetadataCount: 220,
    imageFilePlaceholderCount: 64,
    toolActionWorkSummaryDensity: 0.38,
    markdownDensity: 0.38,
    codeBlockDensity: 0.22,
    tableListQuoteDensity: 0.24,
    sidebarRowHeightVariance: "high",
    searchVisibleTextVolume: 180_000,
    incrementalMetadataChurn: 2_200,
    databaseRowCount: 120_000,
    bridgePayloadBytes: 18_874_368,
    idleTimerPressure: 55,
  },
  "terminal-under-load": {
    conversationCount: 260,
    activeConversationCount: 48,
    pinnedConversationCount: 40,
    projectCount: 20,
    archivedConversationCount: 20,
    messagesPerConversation: 20,
    heavyMessagesPerConversation: 640,
    heavyConversationCount: 4,
    oldHistoryPageCount: 8,
    streamingDeltaCount: 220,
    streamingDeltaByteSize: 192,
    attachmentMetadataCount: 180,
    imageFilePlaceholderCount: 36,
    toolActionWorkSummaryDensity: 0.5,
    markdownDensity: 0.32,
    codeBlockDensity: 0.28,
    tableListQuoteDensity: 0.22,
    sidebarRowHeightVariance: "medium",
    searchVisibleTextVolume: 150_000,
    incrementalMetadataChurn: 1_800,
    databaseRowCount: 160_000,
    bridgePayloadBytes: 10_485_760,
    idleTimerPressure: 64,
  },
  "worst-case": {
    conversationCount: 3_200,
    activeConversationCount: 260,
    pinnedConversationCount: 320,
    projectCount: 96,
    archivedConversationCount: 420,
    messagesPerConversation: 10,
    heavyMessagesPerConversation: 3_200,
    heavyConversationCount: 6,
    oldHistoryPageCount: 36,
    streamingDeltaCount: 1_200,
    streamingDeltaByteSize: 384,
    attachmentMetadataCount: 900,
    imageFilePlaceholderCount: 180,
    toolActionWorkSummaryDensity: 0.56,
    markdownDensity: 0.62,
    codeBlockDensity: 0.42,
    tableListQuoteDensity: 0.44,
    sidebarRowHeightVariance: "extreme",
    searchVisibleTextVolume: 900_000,
    incrementalMetadataChurn: 6_400,
    databaseRowCount: 900_000,
    bridgePayloadBytes: 41_943_040,
    idleTimerPressure: 100,
  },
  "real-equivalent-private": {
    conversationCount: 3_500,
    activeConversationCount: 300,
    pinnedConversationCount: 360,
    projectCount: 120,
    archivedConversationCount: 500,
    messagesPerConversation: 12,
    heavyMessagesPerConversation: 3_600,
    heavyConversationCount: 8,
    oldHistoryPageCount: 40,
    streamingDeltaCount: 1_400,
    streamingDeltaByteSize: 384,
    attachmentMetadataCount: 1_200,
    imageFilePlaceholderCount: 220,
    toolActionWorkSummaryDensity: 0.6,
    markdownDensity: 0.64,
    codeBlockDensity: 0.46,
    tableListQuoteDensity: 0.46,
    sidebarRowHeightVariance: "extreme",
    searchVisibleTextVolume: 1_100_000,
    incrementalMetadataChurn: 7_500,
    databaseRowCount: 1_100_000,
    bridgePayloadBytes: 52_428_800,
    idleTimerPressure: 120,
  },
};

function usage() {
  return `Usage:
  node scripts/generate_macos_ux_trace_fixtures.mjs --list
  node scripts/generate_macos_ux_trace_fixtures.mjs --profile <id> --out-dir <dir> [--seed <seed>] [--json]
  node scripts/generate_macos_ux_trace_fixtures.mjs --all --out-dir <dir> [--seed <seed>] [--json]
`;
}

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (!arg.startsWith("--")) throw new Error(`unexpected argument ${arg}`);
    const key = arg.slice(2);
    if (["list", "all", "json", "help"].includes(key)) {
      args[key] = true;
      continue;
    }
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) throw new Error(`missing value for --${key}`);
    args[key] = value;
    index += 1;
  }
  return args;
}

function hashText(text) {
  return crypto.createHash("sha256").update(text).digest("hex");
}

function stableHash(value) {
  return `sha256:${hashText(JSON.stringify(value))}`;
}

function createPrng(seedText) {
  let state = crypto.createHash("sha256").update(seedText).digest().readUInt32LE(0) || 1;
  return () => {
    state |= 0;
    state = (state + 0x6D2B79F5) | 0;
    let t = Math.imul(state ^ (state >>> 15), 1 | state);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function pick(prng, values) {
  return values[Math.floor(prng() * values.length) % values.length];
}

function pad(value, width) {
  return String(value).padStart(width, "0");
}

function isoFromSeconds(seconds) {
  return new Date(seconds * 1000).toISOString();
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function writeJson(file, value) {
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);
}

function appendJsonLine(fd, value) {
  fs.writeSync(fd, `${JSON.stringify(value)}\n`);
}

function titleFor(profile, index, prng, config) {
  const prefixes = ["Trace run", "Parallel agent", "Dense transcript", "Sidebar audit", "Streaming review", "Terminal load"];
  const domains = ["routing", "fixtures", "rendering", "scroll anchoring", "metadata churn", "bridge payloads"];
  const suffix = config.sidebarRowHeightVariance === "extreme" && index % 7 === 0
    ? " with unusually long title text to force two-line sidebar row measurement and search index pressure"
    : "";
  return `${pick(prng, prefixes)} ${pad(index + 1, 5)} ${pick(prng, domains)} ${profile}${suffix}`;
}

function projectPath(index, config) {
  const projectIndex = index % Math.max(1, config.projectCount);
  return `/tmp/clawix-ux-fixtures/project-${pad(projectIndex + 1, 3)}`;
}

function userPrompt(index, turn, config) {
  const target = ["sidebar", "transcript", "composer", "terminal", "stream", "project list"][turn % 6];
  const density = Math.round(config.searchVisibleTextVolume / Math.max(1, config.conversationCount));
  return `Synthetic request ${pad(index + 1, 5)}.${pad(turn + 1, 4)}: inspect ${target} behavior with ${density} searchable markers and keep latest output visible.`;
}

function markdownBlock(index, turn, config) {
  const fragments = [
    `Measured state for turn ${turn}: latest row stays at the bottom and no private text is present.`,
    `- visible window: ${12 + (turn % 8)} rows\n- scroll anchor: stable\n- metadata churn batch: ${index % 13}`,
    `| surface | expected |\n| --- | --- |\n| sidebar | stable |\n| chat | latest-visible |\n| stream | bounded |`,
    `> Synthetic note ${index}-${turn}: this quote exists only to vary row height.`,
    "```swift\nlet visibleRows = transcript.window.suffix(12)\nassert(visibleRows.last?.role == .assistant)\n```",
    "```json\n{\"fixture\":\"macos-ux-trace\",\"privateContentExported\":false,\"latestVisible\":true}\n```",
  ];
  const count = Math.max(1, Math.ceil(config.markdownDensity * 3));
  return Array.from({ length: count }, (_, offset) => fragments[(turn + offset) % fragments.length]).join("\n\n");
}

function assistantMessage(index, turn, config) {
  const base = `Synthetic assistant result ${pad(index + 1, 5)}.${pad(turn + 1, 4)}. The latest response is intentionally explicit, searchable, and safe.`;
  const repeat = turn % 11 === 0 ? Math.max(1, Math.round(config.streamingDeltaByteSize / 96)) : 1;
  return `${base}\n\n${Array.from({ length: repeat }, () => markdownBlock(index, turn, config)).join("\n\n")}`;
}

function commandPayload(index, turn, commandIndex) {
  const action = commandIndex % 3 === 0 ? "search" : commandIndex % 3 === 1 ? "read" : "list_files";
  return {
    type: "exec_command_end",
    call_id: `cmd-${pad(index, 5)}-${pad(turn, 5)}-${commandIndex}`,
    command: ["bash", "-lc", action === "search" ? "rg synthetic" : action === "read" ? "sed -n '1,120p' synthetic.md" : "rg --files"],
    parsed_cmd: [{ action, path: `synthetic/project-${pad(index % 97, 3)}/file-${pad(turn % 31, 2)}.md` }],
  };
}

function patchPayload(index, turn) {
  return {
    type: "custom_tool_call",
    payload: {
      type: "custom_tool_call",
      name: "apply_patch",
      call_id: `patch-${pad(index, 5)}-${pad(turn, 5)}`,
      input: `*** Begin Patch\n*** Update File: synthetic/project-${pad(index % 97, 3)}/file-${pad(turn % 31, 2)}.md\n@@\n-old\n+new\n*** End Patch\n`,
    },
  };
}

function attachmentPayload(index, turn) {
  return {
    id: `att-${pad(index, 5)}-${pad(turn, 5)}`,
    kind: "image",
    filename: `placeholder-${pad(index, 5)}-${pad(turn, 5)}.png`,
    mime_type: "image/png",
    byte_size: 4096 + ((index + turn) % 17) * 1024,
  };
}

function writeRollout({ file, profile, config, threadId, index, messageCount, prng }) {
  const fd = fs.openSync(file, "w");
  const cwd = projectPath(index, config);
  const sessionMeta = {
    timestamp: isoFromSeconds(baseEpochSeconds - index * 60),
    type: "session_meta",
    payload: { id: threadId, cwd },
  };
  appendJsonLine(fd, sessionMeta);

  const toolModulo = Math.max(2, Math.round(1 / Math.max(0.01, config.toolActionWorkSummaryDensity)));
  const attachmentModulo = Math.max(3, Math.floor(messageCount / Math.max(1, Math.min(config.attachmentMetadataCount, 24))));
  let lineCount = 1;
  try {
    for (let turn = 0; turn < messageCount; turn += 1) {
      const timestamp = baseEpochSeconds - index * 60 + turn;
      const images = turn % attachmentModulo === 0 && turn < config.imageFilePlaceholderCount
        ? [attachmentPayload(index, turn)]
        : undefined;
      appendJsonLine(fd, {
        timestamp: isoFromSeconds(timestamp),
        type: "event_msg",
        payload: {
          type: "user_message",
          message: userPrompt(index, turn, config),
          ...(images ? { images } : {}),
        },
      });
      lineCount += 1;

      if (turn % toolModulo === 0) {
        const commandCount = 1 + Math.floor(prng() * 3);
        for (let commandIndex = 0; commandIndex < commandCount; commandIndex += 1) {
          appendJsonLine(fd, {
            timestamp: isoFromSeconds(timestamp + 0.1 + commandIndex / 10),
            type: "event_msg",
            payload: commandPayload(index, turn, commandIndex),
          });
          lineCount += 1;
        }
      }

      if (config.codeBlockDensity > 0.25 && turn % 19 === 0) {
        appendJsonLine(fd, {
          timestamp: isoFromSeconds(timestamp + 0.45),
          type: "response_item",
          payload: patchPayload(index, turn).payload,
        });
        lineCount += 1;
      }

      const phase = turn === messageCount - 1 ? "final_answer" : (turn % 5 === 0 ? "commentary" : "final_answer");
      appendJsonLine(fd, {
        timestamp: isoFromSeconds(timestamp + 0.6),
        type: "event_msg",
        payload: {
          type: "agent_message",
          phase,
          message: assistantMessage(index, turn, config),
        },
      });
      lineCount += 1;

      appendJsonLine(fd, {
        timestamp: isoFromSeconds(timestamp + 0.8),
        type: "event_msg",
        payload: {
          type: "task_complete",
          duration_ms: 800 + ((index + turn) % 29) * 137,
        },
      });
      lineCount += 1;
    }
  } finally {
    fs.closeSync(fd);
  }
  return { lineCount };
}

function buildThreads(profile, config, outputDir, prng) {
  const rolloutsDir = path.join(outputDir, "rollouts");
  ensureDir(rolloutsDir);
  const threads = [];
  const rolloutFiles = [];
  const heavyCutoff = config.heavyConversationCount;
  for (let index = 0; index < config.conversationCount; index += 1) {
    const threadId = `${profile}-thread-${pad(index + 1, 5)}`;
    const rolloutPath = path.join(rolloutsDir, `${threadId}.jsonl`);
    const messageCount = index < heavyCutoff
      ? config.heavyMessagesPerConversation
      : config.messagesPerConversation + (index % 5);
    const result = writeRollout({ file: rolloutPath, profile, config, threadId, index, messageCount, prng });
    const updatedAt = baseEpochSeconds - index * 37;
    const archived = index >= config.conversationCount - config.archivedConversationCount;
    threads.push({
      id: threadId,
      cwd: projectPath(index, config),
      name: titleFor(profile, index, prng, config),
      preview: `Latest synthetic preview for ${threadId}; messages=${messageCount}; active=${index < config.activeConversationCount}.`,
      path: rolloutPath,
      createdAt: updatedAt - messageCount * 60,
      updatedAt,
      archived,
    });
    rolloutFiles.push({
      threadId,
      relativePath: path.relative(outputDir, rolloutPath),
      messageCount,
      lineCount: result.lineCount,
      heavy: index < heavyCutoff,
      active: index < config.activeConversationCount,
      pinnedCandidate: index < config.pinnedConversationCount,
      archived,
    });
  }
  return { threads, rolloutFiles };
}

function writeSupportArtifacts(outputDir, profile, config) {
  const pinnedThreadIds = Array.from({ length: config.pinnedConversationCount }, (_, index) => `${profile}-thread-${pad(index + 1, 5)}`);
  const streamPlan = Array.from({ length: config.streamingDeltaCount }, (_, index) => ({
    sequence: index + 1,
    byteSize: config.streamingDeltaByteSize + (index % 7) * 17,
    targetThreadId: `${profile}-thread-${pad((index % Math.max(1, config.activeConversationCount)) + 1, 5)}`,
  }));
  const churnPlan = Array.from({ length: Math.min(config.incrementalMetadataChurn, 2_000) }, (_, index) => ({
    sequence: index + 1,
    threadId: `${profile}-thread-${pad((index % config.conversationCount) + 1, 5)}`,
    field: ["preview", "updatedAt", "running", "unread", "error"][index % 5],
  }));
  const terminalLines = Array.from({ length: Math.min(config.databaseRowCount / 100, 5_000) }, (_, index) => (
    `terminal fixture line ${pad(index + 1, 5)} profile=${profile} status=synthetic`
  ));
  writeJson(path.join(outputDir, "pinned-thread-ids.json"), pinnedThreadIds);
  writeJson(path.join(outputDir, "stream-plan.json"), streamPlan);
  writeJson(path.join(outputDir, "metadata-churn-plan.json"), churnPlan);
  fs.writeFileSync(path.join(outputDir, "terminal-output.log"), `${terminalLines.join("\n")}\n`);
  return {
    pinnedThreadIds: "pinned-thread-ids.json",
    streamPlan: "stream-plan.json",
    metadataChurnPlan: "metadata-churn-plan.json",
    terminalOutput: "terminal-output.log",
  };
}

function scalingDimensionsFor(config) {
  return {
    conversationCount: config.conversationCount,
    activeConversationCount: config.activeConversationCount,
    pinnedConversationCount: config.pinnedConversationCount,
    projectCount: config.projectCount,
    conversationsPerProject: Math.ceil(config.conversationCount / Math.max(1, config.projectCount)),
    archivedConversationCount: config.archivedConversationCount,
    titleLengthDistribution: config.sidebarRowHeightVariance,
    timestampDistribution: "recency-skewed-deterministic",
    unreadRunningErrorStates: config.activeConversationCount,
    messageCountPerConversation: {
      default: config.messagesPerConversation,
      heavy: config.heavyMessagesPerConversation,
      heavyConversationCount: config.heavyConversationCount,
    },
    latestMessageLength: config.streamingDeltaByteSize * 4,
    middleMessageLength: config.streamingDeltaByteSize * 2,
    oldHistoryPageCount: config.oldHistoryPageCount,
    markdownDensity: config.markdownDensity,
    codeBlockDensity: config.codeBlockDensity,
    tableListQuoteDensity: config.tableListQuoteDensity,
    toolActionWorkSummaryDensity: config.toolActionWorkSummaryDensity,
    streamingDeltaCount: config.streamingDeltaCount,
    streamingDeltaByteSize: config.streamingDeltaByteSize,
    attachmentMetadataCount: config.attachmentMetadataCount,
    imageFilePlaceholderCount: config.imageFilePlaceholderCount,
    errorRetryCancelStates: Math.max(1, Math.floor(config.activeConversationCount / 4)),
    sidebarRowHeightVariance: config.sidebarRowHeightVariance,
    searchVisibleTextVolume: config.searchVisibleTextVolume,
    incrementalMetadataChurn: config.incrementalMetadataChurn,
    databaseRowCount: config.databaseRowCount,
    bridgePayloadBytes: config.bridgePayloadBytes,
    idleTimerPressure: config.idleTimerPressure,
  };
}

function checksumsFor(outputDir, relativeFiles) {
  const checksums = {};
  for (const relative of relativeFiles) {
    const file = path.join(outputDir, relative);
    checksums[relative] = `sha256:${hashText(fs.readFileSync(file, "utf8"))}`;
  }
  return checksums;
}

function materializeProfile(profile, rootOutDir, seedText) {
  const config = profileDefinitions[profile];
  if (!config) throw new Error(`unknown profile ${profile}`);
  const outputDir = path.resolve(rootOutDir);
  ensureDir(outputDir);
  const prng = createPrng(`${profile}:${seedText}`);
  const { threads, rolloutFiles } = buildThreads(profile, config, outputDir, prng);
  writeJson(path.join(outputDir, "threads.json"), threads);
  const supportArtifacts = writeSupportArtifacts(outputDir, profile, config);
  const artifactFiles = [
    "threads.json",
    supportArtifacts.pinnedThreadIds,
    supportArtifacts.streamPlan,
    supportArtifacts.metadataChurnPlan,
    supportArtifacts.terminalOutput,
  ];
  const manifest = {
    schemaVersion: 1,
    program,
    generatorVersion,
    profile,
    seed: seedText,
    deterministic: true,
    platform: "macos",
    createdAt: isoFromSeconds(baseEpochSeconds),
    privateBoundary: {
      synthetic: true,
      privateContentExported: false,
      containsPrivateConversationText: false,
      containsReadablePrivateScreenshots: false,
      containsCredentials: false,
      publicSafe: true,
    },
    calibration: {
      requiresPrivateAggregateCalibration: ["dense-sidebar", "dense-chat", "streaming-heavy", "terminal-under-load", "worst-case", "real-equivalent-private"].includes(profile),
      privateAggregateOnly: profile === "real-equivalent-private",
      status: "calibratable-with-approved-private-aggregates",
    },
    clawjsScaleLabCompatibility: {
      reusesConceptualDimensions: true,
      compatibleWorkloads: ["sessions", "attachments", "dense"],
      adapter: "clawix-macos-thread-fixture-and-rollout-jsonl",
    },
    scalingDimensions: scalingDimensionsFor(config),
    materializedArtifacts: {
      threadFixture: "threads.json",
      rolloutDirectory: "rollouts",
      supportArtifacts,
      rolloutFiles,
    },
    counts: {
      threads: threads.length,
      rollouts: rolloutFiles.length,
      heavyRollouts: rolloutFiles.filter((file) => file.heavy).length,
      rolloutJsonlLines: rolloutFiles.reduce((sum, file) => sum + file.lineCount, 0),
    },
  };
  writeJson(path.join(outputDir, "manifest.json"), manifest);
  const checksumInputs = artifactFiles;
  manifest.checksums = checksumsFor(outputDir, checksumInputs);
  manifest.manifestHash = stableHash({
    profile: manifest.profile,
    seed: manifest.seed,
    scalingDimensions: manifest.scalingDimensions,
    counts: manifest.counts,
    rolloutFiles: manifest.materializedArtifacts.rolloutFiles.map((file) => ({
      threadId: file.threadId,
      messageCount: file.messageCount,
      lineCount: file.lineCount,
      heavy: file.heavy,
      active: file.active,
      pinnedCandidate: file.pinnedCandidate,
      archived: file.archived,
    })),
  });
  writeJson(path.join(outputDir, "manifest.json"), manifest);
  return {
    ok: true,
    profile,
    outputDir,
    threadFixture: path.join(outputDir, "threads.json"),
    threadPinFixture: path.join(outputDir, "pinned-thread-ids.json"),
    manifest: path.join(outputDir, "manifest.json"),
    counts: manifest.counts,
    manifestHash: manifest.manifestHash,
  };
}

function listProfiles() {
  return Object.entries(profileDefinitions).map(([id, config]) => ({
    id,
    conversationCount: config.conversationCount,
    heavyMessagesPerConversation: config.heavyMessagesPerConversation,
    streamingDeltaCount: config.streamingDeltaCount,
    databaseRowCount: config.databaseRowCount,
    scalingDimensions: scalingDimensionsFor(config),
  }));
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    console.log(usage());
    return;
  }
  if (args.list) {
    console.log(JSON.stringify(listProfiles(), null, 2));
    return;
  }
  const seed = args.seed || "default";
  const outDir = args["out-dir"] || fs.mkdtempSync(path.join(os.tmpdir(), "clawix-macos-ux-fixtures-"));
  if (args.all) {
    const results = [];
    for (const profile of Object.keys(profileDefinitions)) {
      results.push(materializeProfile(profile, path.join(outDir, profile), seed));
    }
    const summary = { ok: true, program, generatorVersion, seed, outDir: path.resolve(outDir), profiles: results };
    if (args.json) console.log(JSON.stringify(summary, null, 2));
    else console.log(`Generated ${results.length} macOS UX fixture profiles at ${summary.outDir}`);
    return;
  }
  const profile = args.profile;
  if (!profile) throw new Error("--profile is required unless --list or --all is used");
  const result = materializeProfile(profile, outDir, seed);
  if (args.json) console.log(JSON.stringify(result, null, 2));
  else console.log(`Generated ${profile} macOS UX fixtures at ${result.outputDir}`);
}

main().catch((error) => {
  console.error(error.message);
  console.error(usage());
  process.exitCode = 1;
});
