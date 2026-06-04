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

requireSnippet("web/src/bridge/store.ts", "searchMessagesBySession");
requireSnippet("web/src/bridge/store.ts", "STREAMING_TRANSCRIPT_FLUSH_MS");
requireSnippet("web/src/bridge/store.ts", "SEARCH_TRANSCRIPT_SNAPSHOT_DEBOUNCE_MS");
requireSnippet("web/src/bridge/store.ts", "enqueueStreamingFrame(set, get, frame)");
requireSnippet("web/src/bridge/store.ts", "clearStreamingTimers()");
requireSnippet("web/src/screens/search/search-view.tsx", "s.searchMessagesBySession");
requireSnippet("web/tests/unit/store.test.ts", "keeps sidebar summaries isolated from streaming-only frames");
requireSnippet("web/tests/unit/store.test.ts", "debounces global search snapshots during active streaming");
requireSnippet("web/tests/unit/store.test.ts", "flushes finished streaming frames immediately");
requireSnippet("web/tests/unit/store.test.ts", "clears pending streaming work on detach");

requireSnippet("android/app/src/main/java/com/example/clawix/android/bridge/BridgeState.kt", "data class BridgeSummaryState");
requireSnippet("android/app/src/main/java/com/example/clawix/android/bridge/BridgeState.kt", "data class BridgeTranscriptState");
requireSnippet("android/app/src/main/java/com/example/clawix/android/bridge/BridgeStore.kt", "val summaryState: StateFlow<BridgeSummaryState>");
requireSnippet("android/app/src/main/java/com/example/clawix/android/bridge/BridgeStore.kt", "val transcriptState: StateFlow<BridgeTranscriptState>");
requireSnippet("android/app/src/main/java/com/example/clawix/android/bridge/BridgeStore.kt", "summary.withTranscript(transcript)");
requireSnippet("android/app/src/main/java/com/example/clawix/android/chatlist/ChatListViewModel.kt", "container.bridgeStore.summaryState");
requireSnippet("android/app/src/main/java/com/example/clawix/android/projectdetail/ProjectDetailViewModel.kt", "container.bridgeStore.summaryState");
requireSnippet("android/app/src/main/java/com/example/clawix/android/chatdetail/ChatDetailViewModel.kt", "container.bridgeStore.transcriptState");
requireSnippet("android/app/src/test/java/com/example/clawix/android/BridgeStoreInvalidationTest.kt", "streamingBatchUpdatesTranscriptWithoutEmittingSummaryState");
requireSnippet("android/app/src/test/java/com/example/clawix/android/BridgeStoreInvalidationTest.kt", "summaryMutationsDoNotEmitTranscriptState");
requireSnippet("android/app/src/test/java/com/example/clawix/android/StreamCoalescerTest.kt", "coalescesMultipleFramesForSameMessageWithLatestContent");
requireSnippet("android/app/src/test/java/com/example/clawix/android/StreamCoalescerTest.kt", "finishedFrameFlushesImmediately");

requireSnippet("ios/Sources/Clawix/Bridge/BridgeTranscriptStore.swift", "final class BridgeTranscriptStore");
requireSnippet("ios/Sources/Clawix/Bridge/BridgeTranscriptStore.swift", "func applyStreamingBatch");
requireSnippet("ios/Sources/Clawix/Bridge/BridgeStore.swift", "let transcriptStore = BridgeTranscriptStore()");
requireSnippet("ios/Sources/Clawix/Bridge/BridgeClient.swift", "store.transcriptStore.applyStreamingBatch");
requireSnippet("ios/Tests/ClawixTests/BridgeStoreInvalidationTests.swift", "testStreamingLoopDoesNotNotifySummaryObservation");
requireSnippet("ios/Tests/ClawixTests/BridgeStoreInvalidationTests.swift", "testStreamingLoopDoesNotifyActiveTranscriptObservation");
requireSnippet("ios/Tests/ClawixTests/BridgeStoreInvalidationTests.swift", "testMessagesSnapshotAndPageUpdateOnlyTargetTranscript");
requireSnippet("ios/Tests/ClawixTests/BridgeStoreInvalidationTests.swift", "testSessionUpdatedChangesSummaryWithoutTranscriptMutation");
requireSnippet("ios/Tests/ClawixTests/BridgeStoreInvalidationTests.swift", "testStreamingBatchDoesNotReorderSummaries");
requireSnippet("ios/Tests/ClawixTests/BridgeStoreInvalidationTests.swift", "testOptimisticNewChatWritesTranscriptAndSummaryTogether");
requireSnippet("ios/Tests/ClawixTests/BridgeStoreInvalidationTests.swift", "testStreamingHandlingDoesNotCallSnapshotPersistenceDirectly");
requireSnippet("ios/project.yml", "ClawixTests");

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

// macOS render-layer-thinness boundary (ADR 0041/0042): the send/turn-boundary
// hot path routes only through named chatStore events and must not re-publish
// the legacy AppState.chats mirror before the bubble paints.
const messageSending = read("macos/Sources/Clawix/AppState/MessageSending.swift");
if (!messageSending.includes("chatStore.appendMessage")) {
  fail("MessageSending send path must land the bubble through the named chatStore.appendMessage event");
}
if (messageSending.includes("syncLegacyChatFromStore")) {
  fail("MessageSending send/turn hot path must not call syncLegacyChatFromStore (legacy AppState.chats mirror is retired from the hot path)");
}
if (/\bself\.chats\s*=/.test(messageSending) || /\bchats\.append\s*\(/.test(messageSending)) {
  fail("MessageSending send path must not write the legacy AppState.chats array directly");
}

// The session presentation/compute layer (ADR 0042) is the chat-side mirror of
// SidebarStore: it subscribes ONLY to the narrow per-chat publishers, never the
// god object, and produces draw-only display models.
const sessionStore = read("macos/Sources/Clawix/Chat/SessionPresentationStore.swift");
// Code (not doc-comment prose) must not wire the god object: no @EnvironmentObject,
// no `appState.` member access, no AppState-typed stored property.
if (/@EnvironmentObject/.test(sessionStore)
  || /\bappState\s*\./.test(sessionStore)
  || /:\s*AppState\b/.test(sessionStore)) {
  fail("SessionPresentationStore must not observe AppState; it binds to the per-chat ChatStore publishers");
}
if (!sessionStore.includes("transcript.$messageIds")) {
  fail("SessionPresentationStore must subscribe to the per-chat ChatTranscriptStore.$messageIds for structure");
}
if (!sessionStore.includes("store.$message")) {
  fail("SessionPresentationStore must subscribe to each visible message's ChatMessageStore.$message for content");
}

// The permanent deterministic locks for the boundary must stay present.
requireSnippet(
  "macos/Tests/ClawixMeshTests/UIThinnessContractTests.swift",
  "testSendCallBudgetIsIndependentOfChatCount"
);
requireSnippet(
  "macos/Tests/ClawixMeshTests/UIThinnessContractTests.swift",
  "testRateLimitWriteDoesNotReEvaluateChatOrSidebar"
);

const webSearchView = read("web/src/screens/search/search-view.tsx");
if (webSearchView.includes("s.messagesBySession")) {
  fail("Web SearchView must consume the debounced searchMessagesBySession snapshot, not live messagesBySession");
}

const webBridgeStore = read("web/src/bridge/store.ts");
if (/case "messageStreaming":[\s\S]{0,800}set\(\{\s*messagesBySession/.test(webBridgeStore)) {
  fail("Web messageStreaming frames must be coalesced before publishing messagesBySession");
}

for (const [relativePath, label] of [
  ["android/app/src/main/java/com/example/clawix/android/chatlist/ChatListViewModel.kt", "Android ChatListViewModel"],
  ["android/app/src/main/java/com/example/clawix/android/projectdetail/ProjectDetailViewModel.kt", "Android ProjectDetailViewModel"],
  ["android/app/src/main/java/com/example/clawix/android/chatdetail/AssistantInlineImagesView.kt", "Android AssistantInlineImagesView"],
  ["android/app/src/main/java/com/example/clawix/android/chatdetail/ImageViewerScreen.kt", "Android ImageViewerScreen"],
  ["android/app/src/main/java/com/example/clawix/android/chatdetail/FileViewerScreen.kt", "Android FileViewerScreen"],
]) {
  const source = read(relativePath);
  if (source.includes("bridgeStore.state")) {
    fail(`${label} must not collect the compatibility BridgeStore.state projection`);
  }
  if (source.includes("messagesBySession")) {
    fail(`${label} must not consume transcript state`);
  }
}

const androidChatDetail = read("android/app/src/main/java/com/example/clawix/android/chatdetail/ChatDetailViewModel.kt");
if (!androidChatDetail.includes("container.bridgeStore.summaryState") || !androidChatDetail.includes("container.bridgeStore.transcriptState")) {
  fail("Android ChatDetailViewModel must combine summaryState and transcriptState explicitly");
}

const iosBridgeStore = read("ios/Sources/Clawix/Bridge/BridgeStore.swift");
for (const forbidden of ["messagesByChat", "hasMoreByChat", "loadingOlderByChat", "oldestKnownIdByChat"]) {
  const fieldPattern = new RegExp(`^\\s*var\\s+${forbidden}\\b`, "m");
  if (fieldPattern.test(iosBridgeStore)) {
    fail(`iOS BridgeStore must not own transcript field ${forbidden}`);
  }
}

const iosBridgeClient = read("ios/Sources/Clawix/Bridge/BridgeClient.swift");
const iosStreamingCase = iosBridgeClient.match(/case \.messageStreaming[\s\S]*?case \.errorEvent/);
if (!iosStreamingCase) {
  fail("iOS BridgeClient messageStreaming case could not be located");
} else {
  const streamingSource = iosStreamingCase[0];
  if (streamingSource.includes("persistSnapshotDebounced")) {
    fail("iOS messageStreaming handling must not call persistSnapshotDebounced");
  }
  if (streamingSource.includes("store.chats")) {
    fail("iOS messageStreaming handling must not mutate summary chats");
  }
}
const iosFlush = iosBridgeClient.match(/private func flushPendingStreamUpdates\(\)[\s\S]*?\n    \}/);
if (!iosFlush || !iosFlush[0].includes("store.transcriptStore.applyStreamingBatch")) {
  fail("iOS streaming flush must publish through BridgeTranscriptStore.applyStreamingBatch");
}

for (const [relativePath, label] of [
  ["ios/Sources/Clawix/ChatList/ChatListView.swift", "iOS ChatListView"],
  ["ios/Sources/Clawix/ProjectDetail/ProjectDetailView.swift", "iOS ProjectDetailView"],
]) {
  const source = read(relativePath);
  for (const forbidden of ["messagesByChat", "transcriptStore", "reasoningText", "timeline"]) {
    if (source.includes(forbidden)) {
      fail(`${label} must not reference transcript payload boundary ${forbidden}`);
    }
  }
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
