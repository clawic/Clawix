#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const sourceRoot = "macos/Sources/Clawix";
const brokerPath = "macos/Sources/Clawix/HostActions/NativeMacActionBroker.swift";
const wirePath = "macos/Sources/Clawix/HostActions/NativeMacActionWire.swift";
const allowlistPath = "docs/native-action-broker-allowlist.json";
const today = new Date().toISOString().slice(0, 10);

const patterns = [
  { id: "appleScript", label: "AppleScript execution", pattern: /\b(?:NSAppleScript|executeAndReturnError)\b/ },
  { id: "networksetup", label: "networksetup execution", pattern: /["']\/usr\/sbin\/networksetup["']/ },
  { id: "shortcuts", label: "Shortcuts CLI execution", pattern: /["']\/usr\/bin\/shortcuts["']/ },
  { id: "pmset", label: "pmset execution", pattern: /["']\/usr\/bin\/pmset["']/ },
  { id: "defaults", label: "defaults execution", pattern: /["']\/usr\/bin\/defaults["']/ },
  { id: "killall", label: "killall execution", pattern: /["']\/usr\/bin\/killall["']/ },
  { id: "osascript", label: "osascript execution", pattern: /["']\/usr\/bin\/osascript["']/ },
  { id: "keyboardEventInjection", label: "keyboard event injection", pattern: /\bCGEvent\s*\(\s*keyboardEventSource:/ },
  {
    id: "crossAppPasteboardInjection",
    label: "cross-app pasteboard injection",
    pattern: (text) =>
      /\bCGEvent\s*\(\s*keyboardEventSource:/.test(text) &&
      /\bpasteboard\.(?:clearContents|setString)\s*\(/.test(text),
  },
  { id: "powerAssertion", label: "power assertion control", pattern: /\b(?:IOPMAssertionID|IOPMAssertionCreateWithName|IOPMAssertionRelease|kIOPMAssertionTypeNoIdleSleep)\b/ },
  { id: "pointerControl", label: "pointer control", pattern: /\b(?:CGWarpMouseCursorPosition|CGAssociateMouseAndMouseCursorPosition)\b/ },
  { id: "systemSettingsDeepLink", label: "System Settings deep link", pattern: /x-apple\.systempreferences:/ },
  { id: "coreAudioWrite", label: "CoreAudio write", pattern: /\bAudioObjectSetPropertyData\b/ },
  { id: "ioKitDisplayWrite", label: "IOKit display write", pattern: /\bIODisplaySetFloatParameter\b/ },
];

const brokerOwnedPaths = new Set([
  brokerPath,
  wirePath,
  "macos/Sources/Clawix/HostActions/NativeMacPermissionBroker.swift",
]);

function fail(message) {
  failures.push(message);
}

function readJson(relativePath) {
  return JSON.parse(fs.readFileSync(path.join(rootDir, relativePath), "utf8"));
}

function listFiles(relativeDir, output = []) {
  const absoluteDir = path.join(rootDir, relativeDir);
  for (const entry of fs.readdirSync(absoluteDir, { withFileTypes: true })) {
    const relativePath = path.join(relativeDir, entry.name);
    if (entry.isDirectory()) {
      if (relativePath.includes("Resources/web-dist")) continue;
      listFiles(relativePath, output);
    } else if (entry.isFile() && relativePath.endsWith(".swift")) {
      output.push(relativePath);
    }
  }
  return output;
}

function patternMatches(pattern, text, relativePath = "") {
  if (typeof pattern.pattern === "function") {
    return pattern.pattern(text, relativePath);
  }
  return pattern.pattern.test(text);
}

function runSelfTest() {
  const fixtures = [
    {
      id: "keyboardEventInjection",
      text: "let event = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)",
    },
    {
      id: "crossAppPasteboardInjection",
      text: "let pasteboard = NSPasteboard.general\npasteboard.clearContents()\npasteboard.setString(payload, forType: .string)\nlet event = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)",
    },
    {
      id: "powerAssertion",
      text: "let result = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoIdleSleep as CFString, level, reason, &assertionID)",
    },
    {
      id: "pointerControl",
      text: "CGWarpMouseCursorPosition(CGPoint(x: 0, y: 0))",
    },
    {
      id: "systemSettingsDeepLink",
      text: "openSystemSettings(\"x-apple.systempreferences:com.apple.Sound-Settings.extension\")",
    },
    {
      id: "coreAudioWrite",
      text: "AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value)",
    },
    {
      id: "ioKitDisplayWrite",
      text: "IODisplaySetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, brightness)",
    },
    {
      id: "pmset",
      text: "static let pmsetCLI = \"/usr/bin/pmset\"",
    },
  ];

  const selfTestFailures = [];
  for (const fixture of fixtures) {
    const pattern = patterns.find((candidate) => candidate.id === fixture.id);
    if (!pattern) {
      selfTestFailures.push(`missing pattern ${fixture.id}`);
      continue;
    }
    if (!patternMatches(pattern, fixture.text, "SelfTest.swift")) {
      selfTestFailures.push(`pattern ${fixture.id} did not match its fixture`);
    }
  }

  if (selfTestFailures.length > 0) {
    console.error(`Native action broker check self-test failed:\n- ${selfTestFailures.join("\n- ")}`);
    process.exit(1);
  }
  console.log("Native action broker check self-test passed");
}

if (process.argv.includes("--self-test")) {
  runSelfTest();
  process.exit(0);
}

const failures = [];
const allowlist = readJson(allowlistPath);
if (allowlist.schemaVersion !== 1) fail(`${allowlistPath}.schemaVersion must be 1`);
if (allowlist.program !== "mac-control-plane") fail(`${allowlistPath}.program must be mac-control-plane`);
if (allowlist.status !== "active") fail(`${allowlistPath}.status must be active`);
if (!Array.isArray(allowlist.entries)) fail(`${allowlistPath}.entries must be an array`);

const brokerText = fs.readFileSync(path.join(rootDir, brokerPath), "utf8");
if (!brokerText.includes("import ClawHostKit")) {
  fail(`${brokerPath} must route Mac control actions through ClawHostKit`);
}
if (!brokerText.includes("typealias NativeMacActionBroker = MacControlActionBroker")) {
  fail(`${brokerPath} must keep NativeMacActionBroker as a compatibility alias to MacControlActionBroker`);
}
if (!brokerText.includes("typealias NativeMacActionPolicy = MacControlPolicy")) {
  fail(`${brokerPath} must keep NativeMacActionPolicy as a compatibility alias to MacControlPolicy`);
}

const wireText = fs.readFileSync(path.join(rootDir, wirePath), "utf8");
if (!wireText.includes("import ClawHostKit")) {
  fail(`${wirePath} must route Mac control wire contracts through ClawHostKit`);
}
if (!wireText.includes("typealias NativeMacActionWire = MacControlWire")) {
  fail(`${wirePath} must keep NativeMacActionWire as a compatibility alias to MacControlWire`);
}

const allowlistByPath = new Map();
for (const [index, entry] of (allowlist.entries ?? []).entries()) {
  const label = `${allowlistPath}.entries[${index}]`;
  for (const field of ["path", "ownerArea", "reason", "migrationTarget", "expiresAt"]) {
    if (typeof entry[field] !== "string" || entry[field] === "") fail(`${label}.${field} must be a non-empty string`);
  }
  if (!Array.isArray(entry.allowedPatterns) || entry.allowedPatterns.length === 0) {
    fail(`${label}.allowedPatterns must be a non-empty array`);
  }
  for (const patternId of entry.allowedPatterns ?? []) {
    if (!patterns.some((pattern) => pattern.id === patternId)) fail(`${label}.allowedPatterns contains unknown pattern ${patternId}`);
  }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(entry.expiresAt ?? "")) fail(`${label}.expiresAt must use YYYY-MM-DD`);
  if ((entry.expiresAt ?? "") <= today) fail(`${label}.expiresAt is expired`);
  if (typeof entry.path === "string" && /^\/Users\//.test(entry.path)) fail(`${label}.path must not publish a private path`);
  allowlistByPath.set(entry.path, new Set(entry.allowedPatterns ?? []));
}

for (const relativePath of listFiles(sourceRoot)) {
  const text = fs.readFileSync(path.join(rootDir, relativePath), "utf8");
  for (const pattern of patterns) {
    const { id, label } = pattern;
    if (!patternMatches(pattern, text, relativePath)) continue;
    if (brokerOwnedPaths.has(relativePath)) continue;
    const allowedPatterns = allowlistByPath.get(relativePath);
    if (!allowedPatterns?.has(id)) {
      fail(`${relativePath} directly uses native action surface (${label}) without a ${allowlistPath} entry`);
    }
  }
}

if (failures.length > 0) {
  console.error(`Native action broker check failed:\n- ${failures.join("\n- ")}`);
  process.exit(1);
}

console.log("Native action broker check passed");
