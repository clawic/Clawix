#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const sourceRoot = "macos/Sources/Clawix";
const brokerPath = "macos/Sources/Clawix/HostActions/NativeMacPermissionBroker.swift";

const patterns = [
  { name: "microphone or camera native authorization", pattern: /\bAVCaptureDevice\.(?:authorizationStatus|requestAccess)\b/ },
  { name: "speech recognition native authorization", pattern: /\bSFSpeechRecognizer\.(?:authorizationStatus|requestAuthorization)\b/ },
  { name: "accessibility trust check", pattern: /\bAXIsProcessTrusted(?:WithOptions)?\b/ },
  { name: "input monitoring access", pattern: /\bIOHID(?:Request|Check)Access\b/ },
];

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
for (const relativePath of listFiles(sourceRoot)) {
  if (relativePath === brokerPath) continue;
  const text = fs.readFileSync(path.join(rootDir, relativePath), "utf8");
  for (const { name, pattern } of patterns) {
    if (pattern.test(text)) {
      failures.push(`${relativePath} directly uses native permission surface: ${name}`);
    }
  }
}

if (failures.length > 0) {
  console.error(`Native permission broker check failed:\n- ${failures.join("\n- ")}`);
  process.exit(1);
}

console.log("Native permission broker check passed");
