#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const failures = [];

function read(relativePath) {
  return fs.readFileSync(path.join(rootDir, relativePath), "utf8");
}

function fail(message) {
  failures.push(message);
}

function listFiles(relativeDir, extensions, output = []) {
  const absoluteDir = path.join(rootDir, relativeDir);
  if (!fs.existsSync(absoluteDir)) return output;
  for (const entry of fs.readdirSync(absoluteDir, { withFileTypes: true })) {
    const relativePath = path.join(relativeDir, entry.name);
    if (entry.isDirectory()) {
      listFiles(relativePath, extensions, output);
    } else if (entry.isFile() && extensions.some((extension) => relativePath.endsWith(extension))) {
      output.push(relativePath);
    }
  }
  return output;
}

const requiredSnippets = [
  ["macos/Sources/Clawix/Apps/AppsStore.swift", "ClawixFrameworkResourceRoutes.appsRootURL()"],
  ["macos/Sources/Clawix/Design/DesignStore.swift", "ClawixFrameworkResourceRoutes.designRootURL()"],
  ["macos/Sources/Clawix/Design/EditorStore.swift", "ClawixFrameworkResourceRoutes.editorDocumentsRootURL()"],
  ["macos/Sources/Clawix/Persistence/ClawixFrameworkResourceRoutes.swift", "ClawixPersistentSurfacePaths.frameworkGlobalChild(appsDirectoryName"],
  ["macos/Sources/Clawix/Persistence/ClawixFrameworkResourceRoutes.swift", "ClawixPersistentSurfacePaths.frameworkGlobalChild(designDirectoryName"],
  ["ios/Sources/Clawix/Design/DesignStore.swift", ".appendingPathComponent(frameworkRootName"],
  ["ios/Sources/Clawix/Design/EditorStore.swift", ".appendingPathComponent(frameworkRootName"],
  ["ios/Sources/Clawix/ClawixTemporaryRoutes.swift", "audioPlaybackCacheDirectoryName = \"clawix-audio\""],
  ["ios/Sources/Clawix/ChatDetail/UserAudioBubble.swift", "ClawixTemporaryRoutes.audioPlaybackCacheURL"],
  ["ios/Sources/Clawix/Composer/VoiceRecorder.swift", "ClawixTemporaryRoutes.voiceRecordingURL()"],
  ["ios/Sources/Clawix/Design/EditorExport.swift", "ClawixTemporaryRoutes.designExportURL"],
  ["macos/Sources/Clawix/Apps/AGENT_CONTRACT.md", "~/.claw/apps/"],
  ["macos/Sources/Clawix/Persistence/TranscriptionsRepository.swift", "Regular dictation audio is encoded in"],
  ["macos/Sources/Clawix/Dictation/DictationAudioCatalogRecorder.swift", "DictationAudioStorage.wavFileBytes(samples: samples)"],
  ["macos/Sources/Clawix/Audio/UserAudioBubble.swift", "framework audio catalog only"],
  ["macos/Sources/Clawix/QuickAsk/QuickAskSlashCommands.swift", "framework-owned snippets"],
  ["macos/Sources/Clawix/QuickAsk/QuickAskMentions.swift", "ClawJSFrameworkRecordsClient.shared.listSnippets"],
  ["macos/Sources/Clawix/Dictation/WhisperPromptStore.swift", "framework-owned snippets"],
  ["macos/Sources/Clawix/Dictation/Enhancement/PromptLibrary.swift", "framework-owned snippets"],
  ["macos/Sources/Clawix/Providers/FeatureRouting.swift", "framework stores only opaque account refs"],
  ["macos/Sources/Clawix/Agents/AgentStore.swift", "production path delegates reads and writes"],
  ["macos/Sources/Clawix/Agents/AgentStore.swift", "frameworkClient.listAgents"],
  ["macos/Sources/Clawix/Skills/SkillsStore.swift", "Source of truth lives in ClawJS"],
  ["macos/Sources/Clawix/Skills/SkillsStore.swift", "frameworkClient?.upsertSkillRecord"],
  ["macos/Sources/Clawix/HostActions/HostActionPolicy.swift", "Requires explicit host approval."],
  ["macos/Sources/Clawix/MacUtilities/MacUtilitiesController.swift", "HostActionPolicy.authorize"],
  ["macos/Sources/Clawix/ScreenTools/ScreenToolService+HostPolicy.swift", "HostActionPolicy.authorize"],
  ["macos/Sources/Clawix/LocalModels/LocalModelsDaemon.swift", "`HOME` is reset to our Application Support directory"],
  ["macos/Sources/Clawix/LocalModels/LocalModelsDaemon.swift", "ClawixRedactedProcessLogSink"],
  ["macos/Sources/Clawix/LocalModels/LocalModelsRuntimeInstaller.swift", "pinnedSHA256Base64"],
  ["macos/Sources/Clawix/MCP/MCPServersStore.swift", "Clawix never parses or"],
  ["macos/Sources/Clawix/MCP/MCPServersStore.swift", "mutates Codex-owned TOML directly"],
  ["macos/Sources/Clawix/MCP/ClawJSMCPClient.swift", "\"mcp\", \"upsert\""],
  ["web/src/screens/agents/agent-family-model.ts", "UI-only fixture projection for the Web companion"],
  ["web/src/screens/agents/agent-family-model.ts", "ClawJS remains the"],
  ["web/src/screens/index/index-model.ts", "UI-only fixture projection for the Web companion"],
  ["web/src/screens/index/index-model.ts", "ClawJS remains the"],
  ["web/src/screens/mac-care/mac-care-model.ts", "UI-only fixture projection for the Web companion"],
  ["web/src/screens/mac-care/mac-care-model.ts", "ClawJS owns the Mac Care"],
  ["web/src/screens/pomodoro/pomodoro-view.tsx", "UI-only Pomodoro scratchpad"],
  ["web/src/screens/pomodoro/pomodoro-view.tsx", "not framework sessions/messages"],
  ["web/src/lib/storage.ts", "pomodoroSessionParity"],
  ["windows/Clawix.App/Services/Preferences.cs", "This store is UI-only"],
  ["windows/Clawix.App/Services/Preferences.cs", "must not"],
  ["windows/Clawix.App/Services/Preferences.cs", "sessions, messages, searches, grants, approvals, audits, or secrets"],
  ["packages/ClawixCore/Sources/ClawixCore/SnapshotCache.swift", "maxChats = 30"],
  ["packages/ClawixCore/Sources/ClawixCore/SnapshotCache.swift", "maxMessagesPerChat = 80"],
  ["android/app/src/main/java/com/example/clawix/android/core/SnapshotCache.kt", "private val maxChats = 30"],
  ["android/app/src/main/java/com/example/clawix/android/core/SnapshotCache.kt", "private val maxMessages = 80"],
  ["android/app/src/main/java/com/example/clawix/android/bridge/Credentials.kt", "EncryptedSharedPreferences-backed credential store"],
  ["android/app/src/main/java/com/example/clawix/android/bridge/Credentials.kt", "MasterKey.KeyScheme.AES256_GCM"],
  ["ios/Sources/Clawix/Bridge/ProjectLabelsCache.swift", "When the bridge eventually grows a"],
  ["ios/Sources/Clawix/Bridge/UnreadChatsCache.swift", "lives entirely on the"],
  ["android/app/src/main/java/com/example/clawix/android/bridge/ProjectLabelsCache.kt", "cold-start"],
  ["android/app/src/main/java/com/example/clawix/android/bridge/UnreadChatsCache.kt", "plain SharedPreferences (no secrets)"],
  ["docs/interface-matrix.md", "Reject App Support as canonical Apps path"],
  ["docs/interface-matrix.md", "Framework workspace storage"],
];

for (const [relativePath, snippet] of requiredSnippets) {
  if (!read(relativePath).includes(snippet)) {
    fail(`${relativePath} is missing required storage-boundary snippet ${JSON.stringify(snippet)}`);
  }
}

const forbiddenByPath = new Map([
  ["docs/data-storage-boundary.md", ["workspace legacy folder"]],
  ["macos/Sources/Clawix/Apps/AppsStore.swift", [
    "Application Support/Clawix/Apps",
    "Library/Application Support/Clawix/Apps",
    "ClawixPersistentSurfacePaths.frameworkGlobalChild(\"apps\"",
    "manifestName = \"manifest.json\"",
  ]],
  ["macos/Sources/Clawix/Apps/AppRecord.swift", ["Application Support/Clawix/Apps", "Library/Application Support/Clawix/Apps"]],
  ["macos/Sources/Clawix/Apps/AGENT_CONTRACT.md", ["Application Support/Clawix/Apps", "Library/Application Support/Clawix/Apps"]],
  ["macos/Sources/Clawix/Design/DesignStore.swift", [
    "Application Support/Clawix/Design",
    "Library/Application Support/Clawix/Design",
    "ClawixPersistentSurfacePaths.frameworkGlobalChild(\"design\"",
    "appendingPathComponent(\"styles\"",
    "appendingPathComponent(\"templates\"",
    "appendingPathComponent(\"references\"",
  ]],
  ["macos/Sources/Clawix/Design/EditorStore.swift", [
    "Application Support/Clawix/Design",
    "Library/Application Support/Clawix/Design",
    "ClawixPersistentSurfacePaths.frameworkGlobalChild(\"design\"",
    "appendingPathComponent(\"documents\"",
    "manifestName = \"document.json\"",
  ]],
  ["macos/Sources/Clawix/Design/EditorDocument.swift", ["Application Support/Clawix/Design", "Library/Application Support/Clawix/Design"]],
  ["ios/Sources/Clawix/Design/DesignStore.swift", ["Application Support/Clawix/Design", "Library/Application Support/Clawix/Design"]],
  ["ios/Sources/Clawix/Design/EditorStore.swift", ["Application Support/Clawix/Design", "Library/Application Support/Clawix/Design"]],
  ["ios/Sources/Clawix/Design/EditorDocument.swift", ["Application Support/Clawix/Design", "Library/Application Support/Clawix/Design"]],
  ["ios/Sources/Clawix/ChatDetail/UserAudioBubble.swift", ["FileManager.default.temporaryDirectory", ".urls(for: .cachesDirectory", "appendingPathComponent(\"clawix-audio\""]],
  ["ios/Sources/Clawix/Composer/VoiceRecorder.swift", ["FileManager.default.temporaryDirectory", "appendingPathComponent(\"clawix_voice_"]],
  ["ios/Sources/Clawix/Design/EditorExport.swift", ["FileManager.default.temporaryDirectory", "appendingPathComponent(\"\\(base)-"]],
  ["macos/Sources/Clawix/Persistence/TranscriptionsRepository.swift", ["Application Support/Clawix/dictation-audio", "Application Support/Clawix/dictation-audio-debug", "frameworkGlobalChild(ClawixPersistentSurfacePaths.components.audio"]],
  ["macos/Sources/Clawix/Dictation/DictationCoordinator.swift", ["DictationAudioStorage.writeWAV(samples: samples, id: id)", "audioFilePath: audioURL?.path"]],
  ["macos/Sources/Clawix/AppState/MessageSending.swift", ["AudioMessageStore.shared.ingest", "legacy store is still the source of truth"]],
  ["macos/Sources/Clawix/AppState/EngineHost.swift", ["AudioMessageStore.shared.data", "Fall through to legacy"]],
  ["macos/Sources/Clawix/Audio/UserAudioBubble.swift", ["AudioMessageStore.shared.data", "Fall through to legacy"]],
  ["macos/Helpers/Bridged/Sources/clawix-bridge/main.swift", ["AudioMessageStore.shared.ingest", "AudioMessageStore.shared.data", "Fall through to legacy"]],
  ["macos/Sources/Clawix/QuickAsk/QuickAskSlashCommands.swift", ["UserDefaults.standard.set", "UserDefaults.standard.data", "quickAsk.slashCommandsCustom"]],
  ["macos/Sources/Clawix/QuickAsk/QuickAskMentions.swift", ["UserDefaults.standard.set", "UserDefaults.standard.data", "quickAsk.mentionPromptsCustom"]],
  ["macos/Sources/Clawix/Dictation/WhisperPromptStore.swift", ["UserDefaults.standard.set", "UserDefaults.standard.data", "dictation.whisperPrompts"]],
  ["macos/Sources/Clawix/Dictation/Enhancement/PromptLibrary.swift", ["dictation.enhancement.customPrompts"]],
  ["macos/Sources/Clawix/Dictation/Enhancement/EnhancementSettings.swift", ["providerKey", "modelKey(", "baseURLKey(", "dictation.enhancement.provider", "dictation.enhancement.model.", "dictation.enhancement.baseURL."]],
  ["macos/Sources/Clawix/Dictation/Enhancement/EnhancementService.swift", ["EnhancementSettings.providerKey", "EnhancementSettings.modelKey", "EnhancementProvider", "configured provider"]],
  ["macos/Sources/Clawix/Dictation/Enhancement/EnhancementUI.swift", ["EnhancementSettings.providerKey", "EnhancementSettings.modelKey", "EnhancementSettings.baseURLKey", "EnhancementSecrets", "API key"]],
  ["macos/Sources/Clawix/Dictation/DictationCoordinator.swift", ["cloud.transcribe(", "CloudTranscriptionProvider", "configured cloud provider"]],
  ["macos/Sources/Clawix/DictationSettingsPage.swift", ["CloudTranscriptionSecrets", "CloudBackendsSheet", "Cloud backend keys"]],
  ["macos/Sources/Clawix/Providers/FeatureRouting.swift", ["providerAccountKey", "modelKey(", "providerEnabledKey", "feature.<feature>.providerAccountId", "feature.<feature>.modelId", "provider.<provider>.enabled"]],
  ["macos/Sources/Clawix/Agents/AgentStore.swift", ["Filesystem source-of-truth"]],
  ["macos/Sources/Clawix/Skills/SkillsStore.swift", ["UserDefaults.standard", "ClawixSkillsActiveByScope", "ClawixSkillsUserCatalog", "seed data + UserDefaults"]],
  ["docs/persistent-surface-clawix.manifest.json", [
    "Application Support/Clawix/Apps",
    "Application Support/Clawix/Design",
    "Application Support/Clawix/dictation-audio",
    "Application Support/Clawix/audio-meta.json",
    "quickAsk.slashCommandsCustom",
    "quickAsk.mentionPromptsCustom",
    "dictation.whisperPrompts",
    "dictation.enhancement.customPrompts",
    "feature.<feature>.providerAccountId",
    "feature.<feature>.modelId",
    "provider.<provider>.enabled",
    "clawix.prefs.dictation.customBaseUrl",
    "clawix.prefs.dictation.customModel",
    "clawix.prefs.dictation.enhancement.provider",
    "clawix.prefs.dictation.enhancement.model",
    "clawix.prefs.dictation.enhancement.baseUrl",
    "clawix.prefs.dictation.cloudModel",
    "clawix.prefs.dictation.cloudBaseUrl",
    "dictation.transcription.baseURL",
    "dictation.transcription.model",
    "dictation.enhancement.provider",
    "dictation.enhancement.model.<provider>",
    "dictation.enhancement.baseURL.<provider>",
    "ClawixSkillsActiveByScope",
    "ClawixSkillsUserCatalog",
  ]],
]);

for (const [relativePath, patterns] of forbiddenByPath) {
  const text = read(relativePath);
  for (const pattern of patterns) {
    if (text.includes(pattern)) {
      fail(`${relativePath} still contains retired Clawix-owned framework storage path ${JSON.stringify(pattern)}`);
    }
  }
}

const manifest = JSON.parse(read("docs/persistent-surface-clawix.manifest.json"));
const nodes = new Map(manifest.nodes.map((node) => [node.id, node]));
if (!Array.isArray(manifest.edges) || manifest.edges.length === 0) {
  fail("persistent surface manifest must preserve route graph edges");
}
if (!Array.isArray(manifest.routes) || manifest.routes.length === 0) {
  fail("persistent surface manifest must preserve route graph routes");
}
const routeGraphContractIds = [
  ...(manifest.edges ?? []).map((edge) => edge.contractId),
  ...(manifest.routes ?? []).flatMap((route) => (route.steps ?? []).map((step) => step.contractId)),
].filter(Boolean);
if (routeGraphContractIds.includes("clawix.protocol.bridge")) {
  fail("persistent surface route graph must use clawix.protocol.bridge.v1, not the unversioned bridge contract id");
}
if (!routeGraphContractIds.includes("clawix.protocol.bridge.v1")) {
  fail("persistent surface route graph must reference clawix.protocol.bridge.v1");
}
for (const [id, expectedPath] of [
  ["claw.framework.apps", "~/.claw/apps"],
  ["claw.framework.design", "~/.claw/design"],
  ["claw.framework.audio", "~/.claw/audio"],
  ["claw.framework.snippets", "~/.claw/core.sqlite#snippets"],
  ["claw.framework.agents", "~/.claw/agents,~/.claw/personalities,~/.claw/skill-collections,~/.claw/connections"],
  ["claw.framework.skills", "~/.claw/core.sqlite#skills"],
  ["claw.framework.providerRouting", "~/.claw/core.sqlite#provider_routing,provider_settings"],
]) {
  const node = nodes.get(id);
  if (!node) {
    fail(`persistent surface manifest is missing ${id}`);
    continue;
  }
  if (node.surfaceSteward !== "claw") fail(`${id} surfaceSteward must be claw`);
  if (node.path !== expectedPath) fail(`${id} path must be ${expectedPath}`);
  if (node.storageClass !== "frameworkGlobal") fail(`${id} storageClass must be frameworkGlobal`);
  if (node.canonicality !== "frameworkCanonical") fail(`${id} canonicality must be frameworkCanonical`);
}

const hostActionAudit = nodes.get("clawix.hostActionAudit");
if (!hostActionAudit) {
  fail("persistent surface manifest is missing clawix.hostActionAudit");
} else {
  if (hostActionAudit.surfaceSteward !== "clawix") fail("clawix.hostActionAudit surfaceSteward must be clawix");
  if (hostActionAudit.path !== "~/Library/Application Support/Clawix/host-action-audit.jsonl") {
    fail("clawix.hostActionAudit path must be ~/Library/Application Support/Clawix/host-action-audit.jsonl");
  }
  if (hostActionAudit.storageClass !== "hostOperational") fail("clawix.hostActionAudit storageClass must be hostOperational");
  if (hostActionAudit.canonicality !== "hostOnly") fail("clawix.hostActionAudit canonicality must be hostOnly");
}

for (const [id, expectedPath] of [
  ["clawix.macControlTimeline", "~/Library/Application Support/Clawix/mac-control-timeline.jsonl"],
  ["clawix.macControlPendingApprovals", "~/Library/Application Support/Clawix/mac-control-pending-approvals.json"],
]) {
  const node = nodes.get(id);
  if (!node) {
    fail(`persistent surface manifest is missing ${id}`);
    continue;
  }
  if (node.surfaceSteward !== "clawix") fail(`${id} surfaceSteward must be clawix`);
  if (node.path !== expectedPath) fail(`${id} path must be ${expectedPath}`);
  if (node.storageClass !== "hostOperational") fail(`${id} storageClass must be hostOperational`);
  if (node.canonicality !== "hostOnly") fail(`${id} canonicality must be hostOnly`);
}

for (const [id, requiredNote] of [
  ["clawix.database.local", "UI/cache/snapshot"],
  ["clawix.embeddedRuntimeDistribution", "compatibility layout only"],
  ["clawix.secrets", "opaque secret ids only"],
  ["clawix.localModels", "model binaries"],
  ["clawix.dictationSounds", "framework audio surface"],
]) {
  const node = nodes.get(id);
  if (!node) {
    fail(`persistent surface manifest is missing ${id}`);
    continue;
  }
  if (node.surfaceSteward !== "clawix") fail(`${id} surfaceSteward must be clawix`);
  if (node.canonicality !== "hostOnly") fail(`${id} canonicality must be hostOnly`);
  if (id !== "clawix.database.local" && node.storageClass !== "hostOperational") {
    fail(`${id} storageClass must be hostOperational`);
  }
  if (!node.notes || !node.notes.includes(requiredNote)) {
    fail(`${id} must document host-only storage boundary note ${JSON.stringify(requiredNote)}`);
  }
}

if (nodes.has("clawix.clawjs")) {
  fail("persistent surface manifest must use clawix.embeddedRuntimeDistribution instead of clawix.clawjs");
}

for (const staleId of ["clawix.apps", "clawix.design", "clawix.audioCatalog", "clawix.audioCatalogMetadata", "clawix.dictationAudio"]) {
  if (nodes.has(staleId)) fail(`persistent surface manifest still exposes retired host-owned node ${staleId}`);
}

const codeRoots = [
  "macos/Sources",
  "macos/Helpers",
  "packages",
  "android/app/src",
  "ios/Sources",
  "web/src",
  "linux/app/src",
  "windows",
];
const sourceExtensions = [".swift", ".kt", ".java", ".ts", ".tsx", ".js", ".jsx", ".mjs", ".rs", ".cs", ".xaml"];
for (const codeRoot of codeRoots) {
  for (const relativePath of listFiles(codeRoot, sourceExtensions)) {
    const source = read(relativePath);
    if (/["'`]~?\/?\.clawjs\b/.test(source) || /["'`][^"'`]*\/\.clawjs\b/.test(source)) {
      fail(`${relativePath} references retired .clawjs workspace storage; new canonical writes must use .claw/ or framework storage`);
    }
  }
}

for (const relativePath of listFiles("linux/app/src-tauri/src", [".rs"])) {
  const source = read(relativePath);
  const mutatingSessionSql = /\b(?:INSERT\s+(?:OR\s+\w+\s+)?INTO|UPDATE|DELETE\s+FROM)\s+(?:chats|messages)\b/iu;
  if (mutatingSessionSql.test(source)) {
    fail(`${relativePath} writes Linux host-local chats/messages tables; sessions must remain daemon/framework owned or use a bounded snapshot-cache contract`);
  }
  const localSecretsSql = /\bCREATE\s+TABLE\b[\s\S]{0,240}\b(?:secret|secrets|vault)\b|\b(?:INSERT\s+(?:OR\s+\w+\s+)?INTO|UPDATE|DELETE\s+FROM)\s+(?:secret|secrets|vault)\b/iu;
  if (localSecretsSql.test(source)) {
    fail(`${relativePath} defines or writes Linux host-local Secrets/Vault storage; secrets must project ClawJS Secrets or carry an explicit blocked migration design`);
  }
}

for (const relativePath of listFiles("web/src/screens/secrets", [".ts", ".tsx", ".js", ".jsx"])) {
  const source = read(relativePath);
  if (/\b(?:localStorage|sessionStorage|indexedDB|openDatabase)\b|\bcaches\.open\b/.test(source)) {
    fail(`${relativePath} persists data from the web Secrets companion; web may keep pairing/UI prefs only, not secret or vault state`);
  }
}

for (const relativePath of listFiles("web/src/screens/agents", [".ts", ".tsx", ".js", ".jsx"])) {
  const source = read(relativePath);
  if (/\b(?:localStorage|sessionStorage|indexedDB|openDatabase)\b|\bcaches\.open\b/.test(source)) {
    fail(`${relativePath} persists Web agent-family data locally; agents, personalities, connections, grants, runtime assignment, and Secrets references must project ClawJS authority`);
  }
  if (/\b(?:writeFile|fs\.write|FileSystemWritableFileStream)\b/.test(source)) {
    fail(`${relativePath} writes Web agent-family records directly; agent-family mutations must route through ClawJS contracts`);
  }
}

for (const relativePath of listFiles("web/src/screens/index", [".ts", ".tsx", ".js", ".jsx"])) {
  const source = read(relativePath);
  if (/\b(?:localStorage|sessionStorage|indexedDB|openDatabase)\b|\bcaches\.open\b/.test(source)) {
    fail(`${relativePath} persists Web index/search data locally; index records, saved searches, monitors, runs, and alerts must project ClawJS authority`);
  }
  if (/\b(?:writeFile|fs\.write|FileSystemWritableFileStream|fetch\s*\()\b/.test(source)) {
    fail(`${relativePath} writes or mutates Web index/search records directly; index mutations must route through ClawJS contracts`);
  }
}

for (const relativePath of listFiles("web/src/screens/mac-care", [".ts", ".tsx", ".js", ".jsx"])) {
  const source = read(relativePath);
  if (/\b(?:localStorage|sessionStorage|indexedDB|openDatabase)\b|\bcaches\.open\b/.test(source)) {
    fail(`${relativePath} persists Web Mac Care data locally; route atlas, scan history, action plans, approvals, and receipts must project ClawJS authority`);
  }
  if (/\b(?:writeFile|fs\.write|FileSystemWritableFileStream|fetch\s*\(|invoke\s*\()\b/.test(source)) {
    fail(`${relativePath} writes, executes, or mutates Web Mac Care records directly; Mac Care actions must route through ClawJS contracts and signed-host approval`);
  }
}

for (const relativePath of listFiles("web/src/screens/pomodoro", [".ts", ".tsx", ".js", ".jsx"])) {
  const source = read(relativePath);
  if (/\b(?:localStorage|sessionStorage|indexedDB|openDatabase)\b|\bcaches\.open\b/.test(source)) {
    fail(`${relativePath} persists Pomodoro state directly; this surface may only use the typed UI-only storage wrapper`);
  }
  if (/\b(?:writeFile|fs\.write|FileSystemWritableFileStream|fetch\s*\(|invoke\s*\(|Notification\s*\.|new\s+Notification|serviceWorker)\b/.test(source)) {
    fail(`${relativePath} performs Pomodoro side effects directly; Pomodoro must remain UI-only until Calendar/Reminders/blockers/runtime routes exist`);
  }
}

const allowedWebStorageFiles = new Set(["web/src/lib/storage.ts", "web/src/bridge/client.ts"]);
for (const relativePath of listFiles("web/src", [".ts", ".tsx", ".js", ".jsx"])) {
  const source = read(relativePath);
  if (/\b(?:localStorage|sessionStorage|indexedDB|openDatabase)\b|\bcaches\.open\b/.test(source) && !allowedWebStorageFiles.has(relativePath)) {
    fail(`${relativePath} uses browser persistence outside the approved pairing/UI storage wrappers; web must not persist framework sessions, messages, secrets, or search state`);
  }
}

if (!read("web/src/lib/storage.ts").includes("Never used for secrets, chats")) {
  fail("web/src/lib/storage.ts must keep documenting that browser storage is not used for secrets, chats, or messages");
}
if (!read("web/src/bridge/client.ts").includes("stable client ids")) {
  fail("web/src/bridge/client.ts localStorage use must remain limited to stable bridge client identifiers");
}
if (!read("web/src/screens/mcp/mcp-view.tsx").includes("ClawJS MCP route")) {
  fail("web/src/screens/mcp/mcp-view.tsx must describe MCP as a ClawJS route projection, not a web-owned backend");
}
if (read("web/src/screens/mcp/mcp-view.tsx").includes("configuration is owned by the Mac app")) {
  fail("web/src/screens/mcp/mcp-view.tsx must not describe MCP config as Mac-app-owned authority");
}

const linuxVaultView = read("linux/app/src/views/VaultManagement.tsx");
if (/\b(?:localStorage|sessionStorage|indexedDB|openDatabase|invoke)\b|\bcaches\.open\b/.test(linuxVaultView)) {
  fail("linux/app/src/views/VaultManagement.tsx wires local persistence or Tauri commands for the Vault placeholder; implement a ClawJS Secrets projection or update the blocked migration design first");
}

const windowsAppProject = read("windows/Clawix.App/Clawix.App.csproj");
if (windowsAppProject.includes("Clawix.Secrets")) {
  fail("windows/Clawix.App must not reference Clawix.Secrets; Windows Secrets must project ClawJS Secrets or remain explicitly blocked");
}

for (const relativePath of listFiles("windows/Clawix.App", [".cs", ".xaml"])) {
  const source = read(relativePath);
  if (/\bClawix\.Secrets\b|\bnew\s+Vault\s*\(|\busing\s+Clawix\.Secrets\b/.test(source)) {
    fail(`${relativePath} wires Windows-local Secrets vault code into the app; use a ClawJS Secrets projection or keep the migration blocked`);
  }
}

for (const [relativePath, snippet] of [
  ["windows/README.md", "legacy scaffold only"],
  ["windows/README.md", "must project the ClawJS Secrets service"],
  ["windows/CLAUDE.md", "not a live Windows app dependency"],
  ["windows/CLAUDE.md", "Windows Secrets must project ClawJS Secrets"],
]) {
  if (!read(relativePath).includes(snippet)) {
    fail(`${relativePath} must document the Windows Secrets host/framework boundary snippet ${JSON.stringify(snippet)}`);
  }
}

const windowsPreferenceKeysSource = read("windows/Clawix.App/Services/WindowsPreferenceKeys.cs");
for (const forbidden of ["secret", "token", "session", "message", "search", "grant", "approval", "audit", "credential", "auth"]) {
  for (const match of windowsPreferenceKeysSource.matchAll(/"([^"]+)"/gu)) {
    const key = match[1].toLowerCase();
    if (forbidden === "token" && (key.includes("outputtokens") || key.includes("bytokens"))) continue;
    if (key.includes(forbidden)) {
      fail(`Windows JSON preferences must not add ${forbidden} key ${JSON.stringify(match[1])}; use the owning framework/host route instead`);
    }
  }
}

if (failures.length > 0) {
  console.error("Storage boundary guard failed:");
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log("storage boundary guard passed");
