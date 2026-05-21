#!/usr/bin/env node
// Windowing/Pagination by Default: broad reads need an explicit window or reviewed baseline.
// Boundedness Guard P0 coverage includes buffer-concat and eventbus retained-state risks.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

const rootDefault = path.resolve(new URL("..", import.meta.url).pathname);
const args = { rootDir: rootDefault, selfTest: false };
for (let i = 2; i < process.argv.length; i += 1) {
  if (process.argv[i] === "--root") args.rootDir = path.resolve(process.argv[++i]);
  else if (process.argv[i] === "--self-test") args.selfTest = true;
  else throw new Error(`unknown argument ${process.argv[i]}`);
}

const scanRoots = ["apps", "bridge", "cli", "ios", "macos", "packages", "publishing", "scripts", "tests", "web"];
const exts = new Set([".cjs", ".cs", ".js", ".jsx", ".kt", ".mjs", ".sh", ".swift", ".ts", ".tsx", ".yaml", ".yml"]);
const skipParts = new Set([".git", ".next", ".tmp", ".turbo", ".build", "build", "coverage", "DerivedData", "dist", "fixtures", "__fixtures__", "generated", "node_modules", "target", "vendor", "web-dist"]);
const skipFiles = new Set(["boundedness-guard.mjs", "boundedness_guard.mjs", "package-lock.json", "Cargo.lock"]);
const bounded = /\b(?:limit|pageSize|offset|cursor|nextCursor|hasMore|window|windowed|visible|prefix|suffix|batch|chunk|tail|readWindowBefore|loadOlder|max\w*|cap|capped|bounded|stream|streaming)\b/iu;
const highVolume = /\b(?:items|rows|records|messages|sessions|events|timeline|results|transcripts|transcript|documents|embeddings|rollouts|sidebars|imports)\b/iu;

function rel(abs) {
  return path.relative(args.rootDir, abs).split(path.sep).join("/");
}

function read(file) {
  return fs.readFileSync(path.join(args.rootDir, file), "utf8");
}

function shouldSkip(file) {
  const parts = file.split("/");
  if (parts.some((part) => skipParts.has(part))) return true;
  const basename = path.basename(file);
  if (skipFiles.has(basename) || /\.generated\./u.test(basename) || basename.endsWith(".min.js")) return true;
  return !exts.has(path.extname(file));
}

function listFiles(dir, out = []) {
  const absDir = path.join(args.rootDir, dir);
  if (!fs.existsSync(absDir)) return out;
  for (const entry of fs.readdirSync(absDir, { withFileTypes: true })) {
    const file = rel(path.join(absDir, entry.name));
    if (entry.isDirectory()) {
      if (!skipParts.has(entry.name)) listFiles(file, out);
    } else if (entry.isFile() && !shouldSkip(file)) {
      out.push(file);
    }
  }
  return out;
}

function statement(lines, index) {
  return lines.slice(Math.max(0, index - 2), Math.min(lines.length, index + 9)).join("\n");
}

function nearbyBound(lines, index) {
  return bounded.test(lines.slice(Math.max(0, index - 4), Math.min(lines.length, index + 5)).join("\n"));
}

function riskFor(line, context, lines, index) {
  const trimmed = line.trim();
  if (!trimmed || trimmed.startsWith("//") || trimmed.startsWith("*") || trimmed.startsWith("#")) return null;
  if (/\blistRecords\s*\(/u.test(line) && !/\b(?:function|func)\s+listRecords\s*\(/u.test(line) && !/\blistRecords\s*\([^)]*\)\s*(?::|=>)/u.test(line) && !/\blimit\b/u.test(context)) return "database-list-without-explicit-window";
  if (/\breadFileSync\s*\(/u.test(line) && /\.(?:jsonl|ndjson)\b/iu.test(line) && !nearbyBound(lines, index)) return "full-jsonl-read";
  if (/\breadFileSync\s*\(/u.test(line) && /\.(?:split|filter|sort|map)\s*\(/u.test(line) && /\b(?:session|rollout|transcript|timeline|import|embedding|search|records?)\b/iu.test(context) && !nearbyBound(lines, index)) return "full-file-split-over-large-source";
  if (/\.(?:filter|sort)\s*\(/u.test(line) && highVolume.test(line) && /\.(?:filter|sort)\s*\([^)]*\)\s*\.\s*(?:filter|sort|map|forEach)\s*\(/su.test(context) && !nearbyBound(lines, index)) return "load-all-filter-sort-render";
  if (/\bForEach\s*\(/u.test(line) && highVolume.test(line) && !nearbyBound(lines, index)) return "ui-foreach-over-unbounded-source";
  return null;
}

function scanFile(file) {
  const lines = read(file).split(/\r?\n/u);
  const findings = [];
  for (let index = 0; index < lines.length; index += 1) {
    const riskKind = riskFor(lines[index], statement(lines, index), lines, index);
    if (riskKind) findings.push({ path: file, line: index + 1, riskKind, snippet: lines[index].trim().slice(0, 160) });
  }
  return findings;
}

function validDate(value) {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/u.test(value);
}

function baselineKeys(failures) {
  const file = "docs/boundedness-baseline.json";
  const abs = path.join(args.rootDir, file);
  if (!fs.existsSync(abs)) {
    failures.push(`missing ${file}`);
    return new Set();
  }
  const json = JSON.parse(fs.readFileSync(abs, "utf8"));
  if (json.schemaVersion !== 1) failures.push(`${file} schemaVersion must be 1`);
  if (json.program !== "boundedness-guard") failures.push(`${file} program must be boundedness-guard`);
  if (!Number.isInteger(json.defaultExpiryDays) || json.defaultExpiryDays <= 0) failures.push(`${file} defaultExpiryDays must be positive`);
  if (!Array.isArray(json.entries)) failures.push(`${file} entries must be an array`);
  const today = new Date().toISOString().slice(0, 10);
  const ids = new Set();
  const keys = new Set();
  for (const [index, entry] of (json.entries ?? []).entries()) {
    const label = entry.id || `entries[${index}]`;
    if (!entry.id || ids.has(entry.id)) failures.push(`${label} must have a unique id`);
    ids.add(entry.id);
    for (const field of ["path", "riskKind", "ownerArea", "reason", "limitKind", "limitValue", "cleanupPolicy", "reference", "expiresAt"]) {
      if (!entry[field]) failures.push(`${label} is missing ${field}`);
    }
    if (typeof entry.blocksRelease !== "boolean") failures.push(`${label} blocksRelease must be boolean`);
    if (entry.path && !fs.existsSync(path.join(args.rootDir, entry.path))) failures.push(`${label} path does not exist: ${entry.path}`);
    if (entry.expiresAt && !validDate(entry.expiresAt)) failures.push(`${label} expiresAt must be YYYY-MM-DD`);
    if (validDate(entry.expiresAt) && entry.expiresAt < today) failures.push(`${label} expired on ${entry.expiresAt}`);
    const key = `${entry.path}:${entry.riskKind}`;
    if (keys.has(key)) failures.push(`${label} duplicates baseline key ${key}`);
    keys.add(key);
  }
  return keys;
}

function requireDoc(snippet, failures) {
  const file = path.join(args.rootDir, "docs/governance/performance-governance.md");
  if (!fs.existsSync(file)) {
    failures.push("missing docs/governance/performance-governance.md");
    return;
  }
  if (!fs.readFileSync(file, "utf8").includes(snippet)) failures.push(`performance governance must include ${JSON.stringify(snippet)}`);
}

function check() {
  const failures = [];
  requireDoc("Windowing/Pagination by Default", failures);
  requireDoc("load all -> filter/sort/render", failures);
  requireDoc("cursor/window/batch/limit", failures);
  const covered = baselineKeys(failures);
  const files = [...new Set(scanRoots.flatMap((dir) => listFiles(dir)))].sort();
  const findings = files.flatMap(scanFile);
  for (const finding of findings) {
    if (!covered.has(`${finding.path}:${finding.riskKind}`)) failures.push(`${finding.path}:${finding.line} has ${finding.riskKind} without an explicit cursor/window/batch/limit or docs/boundedness-baseline.json entry: ${finding.snippet}`);
  }
  return { failures, findings, filesScanned: files.length };
}

function writeFixture(root, file, content) {
  const abs = path.join(root, file);
  fs.mkdirSync(path.dirname(abs), { recursive: true });
  fs.writeFileSync(abs, content);
}

function run(root) {
  return spawnSync(process.execPath, [new URL(import.meta.url).pathname, "--root", root], { encoding: "utf8" });
}

function selfTest() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "boundedness-guard-"));
  const emptyBaseline = { schemaVersion: 1, program: "boundedness-guard", defaultExpiryDays: 90, entries: [] };
  writeFixture(root, "docs/governance/performance-governance.md", "# Performance Governance\n");
  writeFixture(root, "docs/boundedness-baseline.json", JSON.stringify(emptyBaseline, null, 2));
  writeFixture(root, "packages/demo/src/db.ts", "await db.listRecords('sessions');\n");
  let result = run(root);
  if (result.status === 0 || !result.stderr.includes("Windowing/Pagination by Default")) throw new Error("self-test missed missing policy");
  writeFixture(root, "docs/governance/performance-governance.md", "## Windowing/Pagination by Default\nDo not load all -> filter/sort/render; use cursor/window/batch/limit.\n");
  result = run(root);
  if (result.status === 0 || !result.stderr.includes("database-list-without-explicit-window")) throw new Error("self-test missed unbounded listRecords");
  writeFixture(root, "packages/demo/src/db.ts", "await db.listRecords('sessions', { limit: 20, offset: 0 });\n");
  writeFixture(root, "scripts/reader.mjs", "const body = fs.readFileSync('rollout.jsonl', 'utf8');\n");
  result = run(root);
  if (result.status === 0 || !result.stderr.includes("full-jsonl-read")) throw new Error("self-test missed JSONL full read");
  writeFixture(root, "scripts/reader.mjs", "const maxBytes = 1024;\nconst body = fs.readFileSync('rollout.jsonl', 'utf8');\n");
  writeFixture(root, "macos/View.swift", "let messages = store.messages\nForEach(messages) { message in Text(message.text) }\n");
  result = run(root);
  if (result.status === 0 || !result.stderr.includes("ui-foreach-over-unbounded-source")) throw new Error("self-test missed unbounded ForEach");
  writeFixture(root, "docs/boundedness-baseline.json", JSON.stringify({
    ...emptyBaseline,
    entries: [{
      id: "demo-ui-baseline",
      path: "macos/View.swift",
      riskKind: "ui-foreach-over-unbounded-source",
      ownerArea: "demo",
      reason: "self-test historical violation",
      limitKind: "baseline",
      limitValue: "temporary",
      cleanupPolicy: "replace with visible window",
      reference: "self-test",
      expiresAt: "2099-01-01",
      blocksRelease: false,
    }],
  }, null, 2));
  result = run(root);
  if (result.status !== 0) throw new Error(`self-test baseline should pass: ${result.stderr}`);
  fs.rmSync(root, { recursive: true, force: true });
}

if (args.selfTest) {
  selfTest();
  console.log("boundedness guard self-test passed");
} else {
  const { failures, findings, filesScanned } = check();
  if (failures.length > 0) {
    console.error("Boundedness guard failed:");
    for (const failure of failures) console.error(`- ${failure}`);
    process.exit(1);
  }
  console.log(`Boundedness guard passed (${filesScanned} files scanned, ${findings.length} baseline-covered findings).`);
}
