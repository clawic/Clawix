#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const errors = [];
const rawArgs = process.argv.slice(2);

function fail(message) {
  errors.push(message);
}

function read(relativePath) {
  const absolute = path.join(rootDir, relativePath);
  if (!fs.existsSync(absolute)) {
    fail(`missing ${relativePath}`);
    return "";
  }
  return fs.readFileSync(absolute, "utf8");
}

function requireSnippet(relativePath, snippet) {
  const source = read(relativePath);
  if (!source.includes(snippet)) {
    fail(`${relativePath} must include ${snippet}`);
  }
  return source;
}

function parseMetrics(line) {
  const metrics = new Map();
  for (const match of line.matchAll(/(?:^|\s)([A-Za-z0-9_.>:-]+)=([0-9]+)/g)) {
    metrics.set(match[1], Number(match[2]));
  }
  return metrics;
}

function checkRenderLog(text, label) {
  let insideStreamingWindow = false;
  let sawStreamingWindow = false;
  const findings = [];

  for (const [index, line] of text.split(/\r?\n/).entries()) {
    if (line.includes("MARK: ui-state-invalidation-streaming-start")) {
      insideStreamingWindow = true;
      sawStreamingWindow = true;
      continue;
    }
    if (line.includes("MARK: ui-state-invalidation-streaming-end")) {
      insideStreamingWindow = false;
      continue;
    }
    if (!insideStreamingWindow || !line.startsWith("[")) continue;

    const metrics = parseMetrics(line);
    const snapshotCount = metrics.get("makeSnapshot") ?? 0;
    const sidebarBodyCount = metrics.get("SidebarView") ?? 0;
    if (snapshotCount > 0 || sidebarBodyCount > 0) {
      findings.push(
        `${label}:${index + 1} streaming-only window invalidated sidebar ` +
          `(makeSnapshot=${snapshotCount}, SidebarView=${sidebarBodyCount})`
      );
    }
  }

  return { sawStreamingWindow, findings };
}

function runRenderLogFixtures() {
  const passingFixture = [
    "MARK: ui-state-invalidation-streaming-start",
    "[1710000000.000 Δ0.50s] ChatMessageStore.message=40  render.streaming.ingest=40",
    "[1710000000.500 Δ0.50s] ChatMessageStore.message=40",
    "MARK: ui-state-invalidation-streaming-end",
  ].join("\n");
  const failingFixture = [
    "MARK: ui-state-invalidation-streaming-start",
    "[1710000001.000 Δ0.50s] ChatMessageStore.message=40  makeSnapshot=1 tot=1.20ms mx=1.20ms  SidebarView=1",
    "MARK: ui-state-invalidation-streaming-end",
  ].join("\n");

  const pass = checkRenderLog(passingFixture, "passing-fixture");
  if (!pass.sawStreamingWindow || pass.findings.length !== 0) {
    fail("render-log passing fixture must not report sidebar invalidation");
  }

  const regression = checkRenderLog(failingFixture, "failing-fixture");
  if (!regression.sawStreamingWindow || regression.findings.length === 0) {
    fail("render-log failing fixture must report sidebar invalidation");
  }
}

function renderLogArgument() {
  const index = rawArgs.indexOf("--render-log");
  if (index === -1) return process.env.CLAWIX_UI_INVALIDATION_RENDER_LOG || null;
  return rawArgs[index + 1] || null;
}

for (const arg of rawArgs) {
  if (arg !== "--render-log" && !arg.endsWith(".log") && !arg.startsWith("/")) {
    console.error(`ui_state_invalidation_boundary_check received unknown flag ${arg}.`);
    process.exit(1);
  }
}

requireSnippet(
  "docs/adr/0036-ui-state-invalidation-boundary.md",
  "high-churn streaming data must not publish through global app state"
);
requireSnippet("docs/decision-map.md", "UI state invalidation boundary");
requireSnippet("docs/discoverability.registry.json", "adr:ui-state-invalidation-boundary");
requireSnippet("docs/discoverability.md", "adr:ui-state-invalidation-boundary");
requireSnippet("macos/PERF.md", "Long streaming invalidates unrelated UI");
requireSnippet(
  "macos/Tests/ClawixMeshTests/SidebarStoreTests.swift",
  "testLongStreamingRunDoesNotAdvanceSidebarRevisionUntilSummaryChanges"
);
requireSnippet(
  "macos/Tests/ClawixMeshTests/ChatStorePublicationTests.swift",
  "testLongStreamingPublishesOnlyMessageStoreAndNotGlobalSurfaces"
);
requireSnippet("scripts/test.sh", "ui_state_invalidation_boundary_check.mjs");

const chatStores = read("macos/Sources/Clawix/AppState/ChatStores.swift");
const chatSummaryMatch = chatStores.match(/struct ChatSummary: Identifiable, Equatable \{([\s\S]*?)\n    init\(chat: Chat\)/);
if (!chatSummaryMatch) {
  fail("ChatSummary stored fields could not be located");
} else {
  const storedFields = chatSummaryMatch[1];
  for (const forbidden of ["messages", "content", "reasoningText", "timeline"]) {
    const fieldPattern = new RegExp(`\\b(?:let|var)\\s+${forbidden}\\b`);
    if (fieldPattern.test(storedFields)) {
      fail(`ChatSummary must not store high-churn field ${forbidden}`);
    }
  }
}
if (!chatStores.includes("transcriptChangesPublisher")) {
  fail("ChatStore must expose a dedicated transcriptChangesPublisher for high-churn transcript mutations");
}
if (!chatStores.includes("transcriptChanges.send(id)")) {
  fail("ChatTranscriptStore changes must publish through transcriptChanges, not ChatStore.objectWillChange");
}
if (chatStores.includes("objectWillChange.send()")) {
  fail("ChatStore must not forward transcript/message deltas through objectWillChange");
}

const sidebarStore = read("macos/Sources/Clawix/Sidebar/SidebarStore.swift");
if (sidebarStore.includes("appState.$chats")) {
  fail("SidebarStore must consume ChatSummary publishers, not AppState.$chats");
}
if (!sidebarStore.includes("appState.chatStore.$summaries")) {
  fail("SidebarStore must subscribe to chatStore summaries");
}
if (!sidebarStore.includes("messages: []")) {
  fail("SidebarStore sidebar chats must be summary snapshots without transcript payloads");
}

const engineHost = read("macos/Sources/Clawix/AppState/EngineHost.swift");
if (engineHost.includes("chatStore.objectWillChange")) {
  fail("EngineHost bridge publisher must not subscribe to ChatStore.objectWillChange");
}
if (!engineHost.includes("chatStore.transcriptChangesPublisher")) {
  fail("EngineHost bridge publisher must consume the dedicated transcriptChangesPublisher");
}
if (!engineHost.includes(".throttle(for: .milliseconds(16)")) {
  fail("EngineHost transcript bridge snapshots must be coalesced to a frame before snapshot generation");
}

runRenderLogFixtures();

const renderLog = renderLogArgument();
if (renderLog) {
  const absolute = path.isAbsolute(renderLog) ? renderLog : path.join(rootDir, renderLog);
  if (!fs.existsSync(absolute)) {
    fail(`render log does not exist: ${renderLog}`);
  } else {
    const result = checkRenderLog(fs.readFileSync(absolute, "utf8"), renderLog);
    if (!result.sawStreamingWindow) {
      fail(`${renderLog} must include MARK: ui-state-invalidation-streaming-start/end markers`);
    }
    for (const finding of result.findings) fail(finding);
  }
}

if (errors.length > 0) {
  console.error(`UI state invalidation boundary check failed with ${errors.length} finding(s):`);
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("UI state invalidation boundary check passed.");
