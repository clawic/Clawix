#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = process.argv.slice(2);
const allowedFlags = new Set(["--require-approved", "--include-pending"]);
const testOnlyFlags = new Set(["--include-pending"]);

function hasFlag(name) {
  return args.includes(name);
}

const requireApproved = hasFlag("--require-approved");
const includePending = hasFlag("--include-pending");

function readJson(relativePath) {
  return JSON.parse(fs.readFileSync(path.join(rootDir, relativePath), "utf8"));
}

const validationManifest = readJson("docs/ui/private-visual-validation.manifest.json");
const requiredRoots = Array.isArray(validationManifest.requiredRoots) ? validationManifest.requiredRoots : [];
const delegateCommands = Array.isArray(validationManifest.delegates) ? validationManifest.delegates : [];

function parseDelegate(command) {
  const parts = String(command || "").trim().split(/\s+/).filter(Boolean);
  const [runtime, script, ...delegateArgs] = parts;
  if (runtime !== "node" || !script?.startsWith("scripts/ui_private_") || script.includes("..")) {
    throw new Error(`invalid private visual delegate command: ${command}`);
  }
  if (!delegateArgs.includes("--require-approved")) {
    throw new Error(`private visual delegate must require approval: ${command}`);
  }
  return {
    script,
    args: [...delegateArgs, ...(includePending && !delegateArgs.includes("--include-pending") ? ["--include-pending"] : [])],
  };
}

if (!requireApproved) {
  console.error("UI private visual verification requires --require-approved.");
  process.exit(1);
}
for (const arg of args) {
  if (!allowedFlags.has(arg)) {
    console.error(`UI private visual verification received unknown flag ${arg}.`);
    process.exit(1);
  }
}
if (args.some((arg) => testOnlyFlags.has(arg)) && process.env.CLAWIX_UI_ALLOW_PENDING_PRIVATE_EVIDENCE !== "1") {
  console.error("UI private visual verification pending evidence flags require CLAWIX_UI_ALLOW_PENDING_PRIVATE_EVIDENCE=1.");
  process.exit(1);
}

const missingRoots = requiredRoots.filter((envName) => !process.env[envName]);
if (missingRoots.length > 0) {
  console.error(`EXTERNAL PENDING: set ${missingRoots.join(", ")} to verify private UI evidence.`);
  process.exit(2);
}

for (const delegateCommand of delegateCommands) {
  const delegate = parseDelegate(delegateCommand);
  const result = spawnSync(process.execPath, [path.join(rootDir, delegate.script), ...delegate.args], {
    cwd: rootDir,
    env: process.env,
    encoding: "utf8",
  });
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.status !== 0) {
    console.error(`UI private visual verification failed at ${delegate.script}.`);
    process.exit(result.status || 1);
  }
}

console.log("UI private visual verification passed");
