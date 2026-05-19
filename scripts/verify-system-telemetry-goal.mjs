#!/usr/bin/env node
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = new Set(process.argv.slice(2));
const errors = [];

function fail(message) {
  errors.push(message);
}

function assert(condition, message) {
  if (!condition) fail(message);
}

function read(relativePath) {
  return fs.readFileSync(path.join(rootDir, relativePath), "utf8");
}

function requireSnippet(relativePath, snippet) {
  const text = read(relativePath);
  assert(text.includes(snippet), `${relativePath}: missing ${JSON.stringify(snippet)}`);
}

function run(command, commandArgs, options = {}) {
  try {
    return execFileSync(command, commandArgs, {
      cwd: options.cwd ?? rootDir,
      env: { ...process.env, ...(options.env ?? {}) },
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
      timeout: options.timeout ?? 120_000,
    });
  } catch (error) {
    fail(`${command} ${commandArgs.join(" ")} failed: ${error.stderr || error.message}`);
    return "";
  }
}

function assertNoForbiddenPublicNames() {
  const forbidden = [
    [105, 115, 116, 97, 116],
    [98, 106, 97, 110, 103, 111],
  ].map((chars) => String.fromCharCode(...chars).toLowerCase());
  const scanned = [
    "macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift",
    "macos/Sources/Clawix/SystemTelemetry/SystemTelemetryHistoryReader.swift",
    "macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift",
    "macos/Sources/Clawix/SystemTelemetry/SystemTelemetryMonitorRecorder.swift",
    "macos/Tests/ClawixMeshTests/SystemTelemetryBridgeTests.swift",
    "docs/system-telemetry-external-pending-validation.md",
    "scripts/verify-system-telemetry-goal.mjs",
  ];
  for (const file of scanned) {
    const text = read(file).toLowerCase();
    for (const term of forbidden) {
      if (text.includes(term)) fail(`${file}: contains a forbidden external product name`);
    }
  }
}

function assertExternalPendingLedger() {
  const text = read("docs/system-telemetry-external-pending-validation.md");
  for (const snippet of [
    "Source conversation: `019e359b-c0ab-7dc1-ba94-11a49d11dc76`",
    "Plan item: `019e3b6c-3dd8-76d2-bf1e-f50a23db7b07-plan`",
    "Status: `active_goal_not_complete`",
    "`EXTERNAL PENDING` are not passes and must not be used to close the goal.",
    "| CLX-SYS-TEL-EXT-001 | Strict native menu-bar visual validation |",
    "| CLX-SYS-TEL-EXT-002 | Live host telemetry recording through the app |",
    "| CLX-SYS-TEL-EXT-003 | Physical sensor and fan readings surfaced in the UI |",
    "| CLX-SYS-TEL-EXT-004 | Live external context provider displayed in menu-bar widgets |",
    "| CLX-SYS-TEL-EXT-005 | Dangerous controls reachable from UI only through governed plans |",
    "| CLX-SYS-TEL-EXT-006 | Rendered graph view over retained telemetry |",
    "must not be downgraded to `EXTERNAL PENDING`",
  ]) {
    assert(text.includes(snippet), `docs/system-telemetry-external-pending-validation.md: missing ${JSON.stringify(snippet)}`);
  }

  const requiredRows = [
    "CLX-SYS-TEL-EXT-001",
    "CLX-SYS-TEL-EXT-002",
    "CLX-SYS-TEL-EXT-003",
    "CLX-SYS-TEL-EXT-004",
    "CLX-SYS-TEL-EXT-005",
    "CLX-SYS-TEL-EXT-006",
  ];
  for (const rowId of requiredRows) {
    const rowPattern = new RegExp(`\\|\\s*${rowId}\\s*\\|[^\\n]*\\|\\s*EXTERNAL PENDING\\s*\\|`);
    assert(rowPattern.test(text), `docs/system-telemetry-external-pending-validation.md: ${rowId} must remain EXTERNAL PENDING`);
  }
}

function assertBridgeContracts() {
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "struct SystemTelemetrySample");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "struct SystemTelemetryHistoryChart");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "func history(metricKey: String, range: String = \"1h\")");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "static func decodeHistory(");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "struct SystemTelemetryProviderPlan");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "func providerPlan(");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "func controlPlan(");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "metricKeys: stringArray(from: object[\"metric_keys\"]) ?? stringArray(from: object[\"metricKeys\"]) ?? stringArray(from: object[\"metrics\"]) ?? []");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "widgets = enabledWidgets.filter");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "panelWidgets = enabledWidgets.filter");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "providers = await nextProviders");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "histories = await nextHistories");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "func sparkline(for metricKey: String");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "let ticks = Array(\"▁▂▃▄▅▆▇█\")");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "func combinedPanelTitle() -> String");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryBridge.swift", "func providerStatusRows(limit: Int = 5) -> [String]");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryHistoryReader.swift", "final class SystemTelemetryHistoryReader");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryHistoryReader.swift", "\"history\"");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryHistoryReader.swift", "\"--range\"");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryHistoryReader.swift", "CommanderCore.JSONValue.from(any: payload)");
}

function assertStatusItemAndRecorder() {
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "private func makeCombinedPanelItem() -> NSStatusItem");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "private func makeCombinedPanelMenu(model: SystemTelemetryMenuBarModel, title: String) -> NSMenu");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "private func addProviderItems(to menu: NSMenu, model: SystemTelemetryMenuBarModel)");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "private func addWidgetConfigurationItems(to menu: NSMenu, model: SystemTelemetryMenuBarModel) -> Bool");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "private func addPanelItems(to menu: NSMenu, model: SystemTelemetryMenuBarModel, currentWidgetID: String)");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "private let historyReader = SystemTelemetryHistoryReader()");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "case (\"history\", \"get\")");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "historyReader.historyPayload");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryStatusItemController.swift", "let refresh = NSMenuItem(title: \"Refresh\"");

  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryMonitorRecorder.swift", "final class SystemTelemetryMonitorRecorder");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryMonitorRecorder.swift", "\"system\"");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryMonitorRecorder.swift", "\"snapshot\"");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryMonitorRecorder.swift", "\"--source\"");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryMonitorRecorder.swift", "\"host\"");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryMonitorRecorder.swift", "\"--record\"");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryMonitorRecorder.swift", "reason: \"minimum_interval\"");
  requireSnippet("macos/Sources/Clawix/SystemTelemetry/SystemTelemetryMonitorRecorder.swift", "reason: \"host_command_unavailable\"");
}

function assertSwiftTestCoverage() {
  const testFile = "macos/Tests/ClawixMeshTests/SystemTelemetryBridgeTests.swift";
  for (const snippet of [
    "testDecodesSnapshotPolicySamplesAndUnavailableMetrics",
    "testDecodesHistoryChartPayload",
    "testHistoryReaderRunsClawSystemHistoryCommand",
    "testDecodesPortableCliSnapshotPayload",
    "testDecodesPortableCliWidgetListPayload",
    "testDecodesControlCatalogAndPlanPayloads",
    "testDecodesProviderCatalogAndPlanPayloads",
    "testControlPlanBridgeSendsPlanOnlyRequestArguments",
    "testProviderPlanBridgeSendsPlanOnlyRequestArguments",
    "testMenuBarModelLoadsProviderStatusRows",
    "testMenuBarConfigurationTogglesFromDefaultWidgetCatalog",
    "testMenuBarModelIncludesPortableBothPlacement",
    "testMenuBarModelRendersStringSamplesForTextWidgets",
    "testMenuBarModelRendersSparklineFromHistoryChart",
    "testMonitorRecorderRecordsHostSnapshotThroughClawCLI",
    "minimum_interval",
    "testMonitorRecorderReportsUnavailableWithoutHostCommand",
    "system.sensor.fan_speed",
    "context.weather.temperature",
    "metricKeys\": .string(\"[REDACTED]\")",
  ]) {
    requireSnippet(testFile, snippet);
  }
}

function assertOptionalPreflight() {
  if (!args.has("--preflight")) return;
  const launcher = path.resolve(rootDir, "..", "scripts-dev", "clawix-launcher.sh");
  if (!fs.existsSync(launcher)) {
    fail("--preflight requested but private launcher is unavailable");
    return;
  }
  const output = run("bash", [launcher, "preflight-computer-use"], { cwd: path.dirname(rootDir), timeout: 60_000 });
  assert(output.includes("PREFLIGHT OK"), "preflight: expected PREFLIGHT OK");
}

function assertOptionalSwiftTests() {
  if (!args.has("--swift-test")) return;
  const scratch = process.env.CLAWIX_SYSTEM_TELEMETRY_SCRATCH
    || "/tmp/clawix-system-telemetry-goal-build";
  fs.mkdirSync(scratch, { recursive: true });
  run("swift", [
    "test",
    "--package-path",
    path.join(rootDir, "macos"),
    "--scratch-path",
    scratch,
    "--filter",
    "SystemTelemetryBridgeTests",
  ], { timeout: 600_000 });
}

function assertOptionalAccessibilitySmoke() {
  if (!args.has("--accessibility-smoke")) return;
  const titlesScript = `
tell application "System Events"
  tell process "Clawix"
    return title of every menu bar item of menu bar 2
  end tell
end tell
`;
  const titlesOutput = run("osascript", ["-e", titlesScript], { cwd: rootDir, timeout: 30_000 });
  const titles = titlesOutput.split(",").map((title) => title.trim()).filter(Boolean);
  assert(titles.length >= 3, `accessibility smoke: expected at least 3 status items, got ${titles.length}`);
  assert(titles.includes("System OK"), "accessibility smoke: missing combined System OK status item");

  const menuScript = `
tell application "System Events"
  tell process "Clawix"
    set targetItem to first menu bar item of menu bar 2 whose title is "System OK"
    click targetItem
    delay 0.3
    set itemNames to name of every menu item of menu 1 of targetItem
    key code 53
    return itemNames
  end tell
end tell
`;
  const menuOutput = run("osascript", ["-e", menuScript], { cwd: rootDir, timeout: 30_000 });
  for (const snippet of [
    "System indicators",
    "Providers",
    "Menu bar indicators",
    "Refresh",
    "Mock weather context: Ready",
    "Live weather context: External Pending",
    "Signed hardware sensor provider: External Pending",
  ]) {
    assert(menuOutput.includes(snippet), `accessibility smoke: menu missing ${JSON.stringify(snippet)}`);
  }
}

function main() {
  assertNoForbiddenPublicNames();
  assertExternalPendingLedger();
  assertBridgeContracts();
  assertStatusItemAndRecorder();
  assertSwiftTestCoverage();
  assertOptionalPreflight();
  assertOptionalSwiftTests();
  assertOptionalAccessibilitySmoke();

  if (errors.length) {
    console.error(`Clawix system telemetry goal verifier failed with ${errors.length} issue(s):`);
    for (const error of errors) console.error(`- ${error}`);
    process.exit(1);
  }
  console.log("Clawix system telemetry goal verifier passed.");
}

main();
