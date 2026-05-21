#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = new Set(process.argv.slice(2));
const failures = [];
const selfTest = args.has("--self-test");

function fail(message) {
  failures.push(message);
}

function read(relativePath) {
  return fs.readFileSync(path.join(rootDir, relativePath), "utf8");
}

function requireSnippets(relativePath, snippets) {
  if (!fs.existsSync(path.join(rootDir, relativePath))) {
    fail(`missing ${relativePath}`);
    return "";
  }
  const text = read(relativePath);
  for (const snippet of snippets) {
    if (!text.includes(snippet)) {
      fail(`${relativePath} must include ${JSON.stringify(snippet)}`);
    }
  }
  return text;
}

function appStateInitSlice(source) {
  const initMarker = "    init(\n";
  const nextMarker = "    func loadThreadsFromRuntime()";
  const start = source.indexOf(initMarker);
  const end = source.indexOf(nextMarker, start);
  if (start === -1 || end === -1) {
    fail("AppState.init slice could not be located");
    return "";
  }
  return source.slice(start, end);
}

function runChecks() {
  requireSnippets("docs/adr/0026-zero-accidental-work-mirror.md", [
    "Status: Accepted",
    "Zero Accidental Work",
    "AppState.init",
    "startPostFirstFramePersistence()",
    "Bridge transport and runtime startup are separate contracts",
  ]);
  requireSnippets("docs/decision-map.md", [
    "Zero Accidental Work",
    "scripts/zero_accidental_work_check.mjs",
  ]);
  requireSnippets("docs/discoverability.md", [
    "adr-docs-adr-0026-zero-accidental-work-mirror",
    "guard-scripts-zero-accidental-work-check",
  ]);
  requireSnippets("docs/discoverability.registry.json", [
    "adr-docs-adr-0026-zero-accidental-work-mirror",
    "guard-scripts-zero-accidental-work-check",
  ]);
  requireSnippets("docs/adr-operational-coverage.manifest.json", [
    "docs/adr/0026-zero-accidental-work-mirror.md",
    "scripts/zero_accidental_work_check.mjs",
  ]);
  requireSnippets("scripts/test.sh", [
    "scripts/zero_accidental_work_check.mjs",
  ]);

  const appState = requireSnippets("macos/Sources/Clawix/AppState.swift", [
    "func startPostFirstFramePersistence()",
    "startPostFirstFrameFaviconCache()",
    "GUI-owned backend startup is demand-driven",
    "Bridge transport startup is allowed here without runtime",
  ]);
  const initBody = appStateInitSlice(appState);
  if (initBody.includes("FaviconCache.shared.primeDiskCache()")) {
    fail("AppState.init must not prime the favicon disk cache");
  }
  if (initBody.includes("clawix.startIfNeeded(") || initBody.includes("await clawix.startIfNeeded(")) {
    fail("AppState.init must not start the Codex backend");
  }
  if (initBody.includes("databaseProvider.openIfNeeded()")) {
    fail("AppState.init must not open the local database");
  }

  requireSnippets("macos/Sources/Clawix/ClawJS/ClawJSServiceDemandPolicy.swift", [
    "static let startupCoreServices: Set<ClawJSService> = []",
  ]);
  requireSnippets("macos/Tests/ClawixMeshTests/ClawJSServiceDemandPolicyTests.swift", [
    "testMainStartupCoreDoesNotStartRuntimeServices",
    "testAppStateInitDoesNotStartPostFirstFrameWork",
  ]);
  requireSnippets("packages/ClawixEngine/Sources/ClawixEngine/BridgeRuntimeWakePolicy.swift", [
    "case .listSessions where clientKind == .desktop",
    "default:",
    "return nil",
  ]);
  requireSnippets("packages/ClawixEngine/Tests/ClawixEngineTests/BridgeRuntimeWakePolicyTests.swift", [
    "testPassiveFramesDoNotWakeRuntime",
    "testCompanionListSessionsDoesNotWakeRuntime",
    "testRealChatFramesWakeRuntime",
  ]);
  requireSnippets("packages/ClawixEngine/Tests/ClawixEngineTests/BridgeIntentRuntimeWakeTests.swift", [
    "testDesktopListSessionsStartsRuntimeBeforeReplying",
    "testCompanionListSessionsRepliesWithoutStartingRuntime",
  ]);
}

if (selfTest) {
  const originalRead = fs.readFileSync;
  fs.readFileSync = function patchedRead(file, ...rest) {
    const text = originalRead.call(this, file, ...rest);
    if (String(file).endsWith("AppState.swift")) {
      return String(text).replace(
        "        loadHostFavicons()\n",
        "        loadHostFavicons()\n        FaviconCache.shared.primeDiskCache()\n",
      );
    }
    return text;
  };
  runChecks();
  if (failures.some((failure) => failure.includes("favicon disk cache"))) {
    console.log("zero accidental work check self-test passed");
    process.exit(0);
  }
  console.error("zero accidental work check self-test failed: negative fixture did not trip");
  process.exit(1);
}

runChecks();

if (failures.length > 0) {
  console.error("zero accidental work check failed:");
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log("zero accidental work check passed");
