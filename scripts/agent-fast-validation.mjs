#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const matrixPath = path.join(rootDir, "qa/agent-fast-validation.matrix.json");
const args = process.argv.slice(2);
const repoFingerprint = createHash("sha256").update(rootDir).digest("hex").slice(0, 12);
const coordinationIntent = `agent-fast-${process.pid}`;

function coordinationArgs() {
  return [
    ...(process.env.CLAW_AGENT_COORDINATION_STATE_DIR ? ["--state-dir", process.env.CLAW_AGENT_COORDINATION_STATE_DIR] : []),
    ...(process.env.CLAW_AGENT_COORDINATION_RUN_DIR ? ["--run-dir", process.env.CLAW_AGENT_COORDINATION_RUN_DIR] : []),
  ];
}

function clawCommand() {
  if (process.env.CLAWIX_CLAW_BIN) return { command: process.env.CLAWIX_CLAW_BIN, argsPrefix: [] };
  const pathProbe = spawnSync("bash", ["-lc", "command -v claw"], { encoding: "utf8" });
  if (pathProbe.status === 0 && pathProbe.stdout.trim()) return { command: pathProbe.stdout.trim(), argsPrefix: [] };
  const sibling = path.resolve(rootDir, "../clawjs/packages/clawjs/bin/claw.mjs");
  if (fs.existsSync(sibling)) return { command: sibling, argsPrefix: [] };
  return null;
}

function runClaw(args) {
  const resolved = clawCommand();
  if (!resolved) {
    return { status: 127, payload: null, stdout: "", stderr: "BLOCKED coordination broker: set CLAWIX_CLAW_BIN or install claw on PATH" };
  }
  const result = spawnSync(resolved.command, [...resolved.argsPrefix, ...args, "--json"], {
    cwd: rootDir,
    encoding: "utf8",
    env: process.env,
  });
  let payload = null;
  try {
    payload = result.stdout ? JSON.parse(result.stdout) : null;
  } catch {
    payload = null;
  }
  return { status: result.status ?? 1, payload, stdout: result.stdout ?? "", stderr: result.stderr ?? "" };
}

function acquireCheckLease(check) {
  if (process.env.CLAW_AGENT_COORDINATION_ACTIVE === "1") return null;
  const resource = `test:${repoFingerprint}:agent-fast:${check.id}`;
  if (process.env.CLAW_AGENT_COORDINATION_BYPASS === "1") {
    const reason = process.env.CLAW_AGENT_COORDINATION_BYPASS_REASON;
    if (!reason) fail("CLAW_AGENT_COORDINATION_BYPASS_REASON is required when bypassing agent fast validation coordination.");
    const bypass = runClaw(["agent-resource", "bypass", "--intent", coordinationIntent, "--resource", resource, "--reason", reason, ...coordinationArgs()]);
    if (bypass.payload?.data?.status !== "BYPASS_AUDITED") fail(`Could not audit coordination bypass:\n${bypass.stdout || bypass.stderr}`);
    console.error(`WARNING: bypassed coordination for ${check.id}; evidence is partial/degraded.`);
    return null;
  }
  const acquired = runClaw([
    "agent-resource",
    "acquire",
    "--resource",
    resource,
    "--mode",
    "exclusive",
    "--intent",
    coordinationIntent,
    "--pid",
    String(process.pid),
    "--ttl",
    String(check.maxSeconds || 60),
    "--kind",
    "test",
    "--reason",
    `agent-fast validation ${check.id}`,
    ...coordinationArgs(),
  ]);
  if (acquired.payload?.data?.status === "PENDING") {
    console.error(`PENDING agent fast validation ${check.id}: coordination lease is busy.`);
    console.error(acquired.stdout || acquired.stderr);
    process.exit(2);
  }
  const leaseId = acquired.payload?.data?.lease?.id;
  if (acquired.status !== 0 || !leaseId) fail(`Could not acquire coordination lease for ${check.id}:\n${acquired.stdout || acquired.stderr}`);
  return leaseId;
}

function releaseCheckLease(leaseId, passed, check) {
  if (!leaseId) return;
  const released = runClaw([
    "agent-resource",
    "release",
    "--lease",
    leaseId,
    "--status",
    passed ? "passed" : "failed",
    "--repo",
    rootDir,
    "--lane",
    "agent-fast",
    "--check",
    check.id,
    ...coordinationArgs(),
  ]);
  if (released.status !== 0) {
    console.error(`Could not release coordination lease ${leaseId}:\n${released.stdout || released.stderr}`);
  }
}

function readMatrix() {
  return JSON.parse(fs.readFileSync(matrixPath, "utf8"));
}

function usage() {
  console.log(`Usage:
  node scripts/agent-fast-validation.mjs [--smoke]
  node scripts/agent-fast-validation.mjs --changed [--base <ref>]
  node scripts/agent-fast-validation.mjs --checks <id,id>
  node scripts/agent-fast-validation.mjs --list
  node scripts/agent-fast-validation.mjs --matrix
  node scripts/agent-fast-validation.mjs --check-matrix`);
}

function fail(message) {
  console.error(message);
  process.exit(1);
}

function validateMatrix(matrix) {
  const errors = [];
  if (matrix.schemaVersion !== 1) errors.push("schemaVersion must be 1");
  if (!Array.isArray(matrix.checks) || matrix.checks.length === 0) errors.push("checks must be a non-empty array");
  if (!Array.isArray(matrix.changeTypes) || matrix.changeTypes.length === 0) errors.push("changeTypes must be a non-empty array");
  if (!Array.isArray(matrix.quickSuite) || matrix.quickSuite.length === 0) errors.push("quickSuite must be a non-empty array");

  const checkIds = new Set();
  for (const check of matrix.checks || []) {
    if (!check.id) errors.push("each check needs id");
    if (checkIds.has(check.id)) errors.push(`duplicate check id ${check.id}`);
    checkIds.add(check.id);
    for (const field of ["command", "detects", "failureAction"]) {
      if (!check[field]) errors.push(`check ${check.id || "<unknown>"} is missing ${field}`);
    }
    if (check.realServices !== false) errors.push(`check ${check.id} must explicitly set realServices false`);
    if (!Number.isFinite(check.measuredMs) || check.measuredMs <= 0) errors.push(`check ${check.id} needs positive measuredMs`);
    if (!Number.isFinite(check.maxSeconds) || check.maxSeconds <= 0) errors.push(`check ${check.id} needs positive maxSeconds`);
  }

  for (const id of matrix.quickSuite || []) {
    if (!checkIds.has(id)) errors.push(`quickSuite references unknown check ${id}`);
  }

  for (const changeType of matrix.changeTypes || []) {
    if (!changeType.id) errors.push("each changeType needs id");
    if (!Array.isArray(changeType.pathPatterns) || changeType.pathPatterns.length === 0) {
      errors.push(`changeType ${changeType.id || "<unknown>"} needs pathPatterns`);
    }
    if (!Array.isArray(changeType.recommendedChecks) || changeType.recommendedChecks.length === 0) {
      errors.push(`changeType ${changeType.id || "<unknown>"} needs recommendedChecks`);
    }
    for (const id of changeType.recommendedChecks || []) {
      if (!checkIds.has(id)) errors.push(`changeType ${changeType.id} references unknown check ${id}`);
    }
  }

  return errors;
}

function checkById(matrix) {
  return new Map(matrix.checks.map((check) => [check.id, check]));
}

function globToRegExp(glob) {
  const escaped = glob
    .replace(/[.+^${}()|[\]\\]/g, "\\$&")
    .replace(/\*\*/g, "\u0000")
    .replace(/\*/g, "[^/]*")
    .replace(/\u0000/g, ".*");
  return new RegExp(`^${escaped}$`);
}

function changedFiles(base) {
  const diffBase = base || spawnSync("git", ["merge-base", "HEAD", "origin/main"], {
    cwd: rootDir,
    encoding: "utf8"
  }).stdout.trim() || "HEAD~1";
  const result = spawnSync("git", ["diff", "--name-only", diffBase, "--"], {
    cwd: rootDir,
    encoding: "utf8"
  });
  if (result.status !== 0) {
    fail(`Could not read changed files from ${diffBase}:\n${result.stderr.trim()}`);
  }
  return result.stdout.split(/\r?\n/).filter(Boolean);
}

function recommendedChecksForFiles(matrix, files) {
  const selected = new Set(matrix.quickSuite);
  const matchedTypes = [];
  for (const changeType of matrix.changeTypes) {
    const patterns = changeType.pathPatterns.map(globToRegExp);
    if (files.some((file) => patterns.some((pattern) => pattern.test(file)))) {
      matchedTypes.push(changeType);
      for (const id of changeType.recommendedChecks) selected.add(id);
    }
  }
  return { selected: [...selected], matchedTypes };
}

function parseChecksArg(value, matrix) {
  const available = checkById(matrix);
  const ids = value.split(",").map((item) => item.trim()).filter(Boolean);
  const unknown = ids.filter((id) => !available.has(id));
  if (unknown.length) fail(`Unknown check id(s): ${unknown.join(", ")}`);
  return ids;
}

function runChecks(matrix, ids) {
  const available = checkById(matrix);
  const results = [];
  for (const id of ids) {
    const check = available.get(id);
    const leaseId = acquireCheckLease(check);
    const started = process.hrtime.bigint();
    let result = { status: 1, signal: null, stdout: "", stderr: "" };
    try {
      result = spawnSync("bash", ["-lc", check.command], {
        cwd: rootDir,
        encoding: "utf8",
        timeout: check.maxSeconds * 1000,
        maxBuffer: 1024 * 1024
      });
      const elapsedMs = Math.round(Number(process.hrtime.bigint() - started) / 1e6);
      const output = `${result.stdout || ""}${result.stderr || ""}`.trim();
      const status = result.signal ? result.signal : result.status === 0 ? "PASS" : `FAIL ${result.status}`;
      console.log(`${status.padEnd(8)} ${String(elapsedMs).padStart(6)}ms ${id}`);
      if (result.status !== 0 || result.signal) {
        const tail = output.split(/\r?\n/).slice(-8).join("\n");
        console.error(`  detects: ${check.detects}`);
        console.error(`  action: ${check.failureAction}`);
        if (tail) console.error(`  output:\n${tail.split("\n").map((line) => `    ${line}`).join("\n")}`);
      }
      results.push({ id, elapsedMs, status: result.status, signal: result.signal });
    } finally {
      releaseCheckLease(leaseId, result.status === 0 && !result.signal, check);
    }
  }
  const failed = results.filter((result) => result.status !== 0 || result.signal);
  const totalMs = results.reduce((sum, result) => sum + result.elapsedMs, 0);
  console.log(`agent fast validation: ${results.length - failed.length}/${results.length} passed in ${totalMs}ms`);
  return failed.length === 0;
}

const matrix = readMatrix();
const errors = validateMatrix(matrix);
if (errors.length && !args.includes("--matrix")) {
  fail(`Agent fast validation matrix is invalid:\n- ${errors.join("\n- ")}`);
}

if (args.includes("--help")) {
  usage();
  process.exit(0);
}

if (args.includes("--check-matrix")) {
  if (errors.length) fail(`Agent fast validation matrix is invalid:\n- ${errors.join("\n- ")}`);
  console.log("agent fast validation matrix passed");
  process.exit(0);
}

if (args.includes("--matrix")) {
  console.log(JSON.stringify(matrix, null, 2));
  process.exit(0);
}

if (args.includes("--list")) {
  for (const check of matrix.checks) {
    console.log(`${check.id}: ${check.command}`);
  }
  process.exit(0);
}

let ids = matrix.quickSuite;
if (args.includes("--changed")) {
  const baseIndex = args.indexOf("--base");
  const base = baseIndex === -1 ? undefined : args[baseIndex + 1];
  if (baseIndex !== -1 && !base) fail("--base requires a git ref");
  const files = changedFiles(base);
  const recommendation = recommendedChecksForFiles(matrix, files);
  if (recommendation.matchedTypes.length) {
    console.log(`matched change types: ${recommendation.matchedTypes.map((type) => type.id).join(", ")}`);
  } else {
    console.log("matched change types: none; using quick suite");
  }
  ids = recommendation.selected;
}

const checksIndex = args.indexOf("--checks");
if (checksIndex !== -1) {
  const value = args[checksIndex + 1];
  if (!value) fail("--checks requires a comma-separated id list");
  ids = parseChecksArg(value, matrix);
}

const ok = runChecks(matrix, ids);
process.exit(ok ? 0 : 1);
