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
];

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
  for (const { id, label, pattern } of patterns) {
    if (!pattern.test(text)) continue;
    if (relativePath === brokerPath) continue;
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
