#!/usr/bin/env node
// Windowing/Pagination by Default: broad reads must use an explicit window or baseline.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

const defaultRootDir = path.resolve(new URL("..", import.meta.url).pathname);

function parseArgs(argv) {
  const args = { rootDir: defaultRootDir, selfTest: false };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--root") args.rootDir = path.resolve(argv[++index]);
    else if (arg === "--self-test") args.selfTest = true;
    else throw new Error(`unknown argument ${arg}`);
  }
  return args;
}

const args = parseArgs(process.argv.slice(2));

const excludedParts = new Set([
  ".git",
  ".next",
  ".tmp",
  ".turbo",
  "build",
  ".build",
  "dist",
  "coverage",
  "node_modules",
  "vendor",
  "fixtures",
  "__fixtures__",
  "generated",
  "DerivedData",
  "target",
]);

const excludedBasenames = new Set([
  "package-lock.json",
  "Cargo.lock",
  "boundedness-baseline.json",
  "boundedness-guard.mjs",
  "boundedness_guard.mjs",
  "codebase-manifest.json",
  "discoverability.registry.json",
  "discoverability-baseline.json",
]);

const allowedExtensions = new Set([".cjs", ".cs", ".js", ".jsx", ".kt", ".mjs", ".sh", ".swift", ".ts", ".tsx", ".yaml", ".yml"]);
const scanRoots = ["apps", "bridge", "cli", "docs", "macos", "ios", "android", "linux", "packages", "publishing", "scripts", "skills", "tests", "web", "windows"];

const boundedTerms = /\b(?:limit|pageSize|offset|cursor|nextCursor|hasMore|window|windowed|visible|prefix|suffix|batch|chunk|tail|readWindowBefore|loadOlder|max(?:imum)?|cap|capped|bounded|stream|streaming)\b/iu;
const highVolumeNames = /\b(?:items|rows|records|messages|sessions|events|timeline|results|transcripts|transcript|documents|embeddings|rollouts|sidebars|imports)\b/iu;

function relative(rootDir, absolutePath) {
  return path.relative(rootDir, absolutePath).split(path.sep).join("/");
}

function readText(rootDir, relativePath) {
  return fs.readFileSync(path.join(rootDir, relativePath), "utf8");
}

function readJson(rootDir, relativePath) {
  return JSON.parse(readText(rootDir, relativePath));
}

function isDate(value) {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/u.test(value);
}

function shouldSkip(relativePath) {
  const parts = relativePath.split("/");
  if (parts.some((part) => excludedParts.has(part))) return true;
  if (parts.includes("web-dist")) return true;
  const basename = path.basename(relativePath);
  if (excludedBasenames.has(basename)) return true;
  if (/\.generated\./u.test(basename) || basename.endsWith(".min.js")) return true;
  if (relativePath.startsWith("docs/") && basename !== "performance-governance.md") return true;
  return !allowedExtensions.has(path.extname(relativePath));
}

function listFiles(rootDir, relativeDir, output = []) {
  const absoluteDir = path.join(rootDir, relativeDir);
  if (!fs.existsSync(absoluteDir)) return output;
  for (const entry of fs.readdirSync(absoluteDir, { withFileTypes: true })) {
    const absolutePath = path.join(absoluteDir, entry.name);
    const relativePath = relative(rootDir, absolutePath);
    if (entry.isDirectory()) {
      if (!excludedParts.has(entry.name)) listFiles(rootDir, relativePath, output);
    } else if (entry.isFile() && !shouldSkip(relativePath)) {
      output.push(relativePath);
    }
  }
  return output;
}

function statementAt(lines, index) {
  const start = Math.max(0, index - 2);
  const end = Math.min(lines.length - 1, index + 8);
  return lines.slice(start, end + 1).join("\n");
}

function nearbyHasBound(lines, index) {
  const start = Math.max(0, index - 4);
  const end = Math.min(lines.length - 1, index + 4);
  return boundedTerms.test(lines.slice(start, end + 1).join("\n"));
}

function detectRisk(line, statement, lines, index) {
  const trimmed = line.trim();
  if (trimmed.startsWith("//") || trimmed.startsWith("*") || trimmed.startsWith("#")) return null;

  if (
    /\blistRecords\s*\(/u.test(line) &&
    !/\b(?:function|func)\s+listRecords\s*\(/u.test(line) &&
    !/\blistRecords\s*\([^)]*\)\s*(?::|=>)/u.test(line) &&
    !/\blimit\b/u.test(statement)
  ) {
    return "database-list-without-explicit-window";
  }

  if (/\breadFileSync\s*\(/u.test(line) && /\.(?:jsonl|ndjson)\b/iu.test(line) && !nearbyHasBound(lines, index)) {
    return "full-jsonl-read";
  }

  if (
    /\breadFileSync\s*\(/u.test(line) &&
    /\.(?:split|filter|sort|map)\s*\(/u.test(line) &&
    /\b(?:session|rollout|transcript|timeline|import|embedding|search|records?)\b/iu.test(statement) &&
    !nearbyHasBound(lines, index)
  ) {
    return "full-file-split-over-large-source";
  }

  if (
    /\.(?:filter|sort)\s*\(/u.test(line) &&
    highVolumeNames.test(line) &&
    /\.(?:filter|sort)\s*\([^)]*\)\s*\.\s*(?:filter|sort|map|forEach)\s*\(/su.test(statement) &&
    !nearbyHasBound(lines, index)
  ) {
    return "load-all-filter-sort-render";
  }

  if (
    /\bForEach\s*\(/u.test(line) &&
    highVolumeNames.test(line) &&
    !nearbyHasBound(lines, index)
  ) {
    return "ui-foreach-over-unbounded-source";
  }

  return null;
}

function scanFile(rootDir, relativePath) {
  const lines = readText(rootDir, relativePath).split(/\r?\n/u);
  const findings = [];
  for (const [index, line] of lines.entries()) {
    const statement = statementAt(lines, index);
    const riskKind = detectRisk(line, statement, lines, index);
    if (riskKind) findings.push({ path: relativePath, line: index + 1, riskKind, snippet: line.trim().slice(0, 160) });
  }
  return findings;
}

function validateBaseline(rootDir, baseline, failures) {
  if (baseline.schemaVersion !== 1) failures.push("docs/boundedness-baseline.json schemaVersion must be 1");
  if (baseline.program !== "boundedness-guard") failures.push("docs/boundedness-baseline.json program must be boundedness-guard");
  if (!Number.isInteger(baseline.defaultExpiryDays) || baseline.defaultExpiryDays <= 0) failures.push("docs/boundedness-baseline.json defaultExpiryDays must be a positive integer");
  if (!Array.isArray(baseline.entries)) failures.push("docs/boundedness-baseline.json entries must be an array");
  const today = new Date().toISOString().slice(0, 10);
  const keys = new Set();
  const ids = new Set();
  for (const [index, entry] of (baseline.entries ?? []).entries()) {
    const label = entry.id || `entries[${index}]`;
    if (!entry.id) failures.push(`${label} is missing id`);
    if (entry.id && ids.has(entry.id)) failures.push(`${label} duplicates id ${entry.id}`);
    if (entry.id) ids.add(entry.id);
    for (const field of ["path", "riskKind", "ownerArea", "reason", "limitKind", "limitValue", "cleanupPolicy", "reference", "expiresAt"]) {
      if (entry[field] === undefined || entry[field] === "") failures.push(`${label} is missing ${field}`);
    }
    if (typeof entry.blocksRelease !== "boolean") failures.push(`${label} blocksRelease must be boolean`);
    if (entry.path && !fs.existsSync(path.join(rootDir, entry.path))) failures.push(`${label} path does not exist: ${entry.path}`);
    if (entry.expiresAt && !isDate(entry.expiresAt)) failures.push(`${label} expiresAt must be YYYY-MM-DD`);
    if (isDate(entry.expiresAt) && entry.expiresAt < today) failures.push(`${label} expired on ${entry.expiresAt}`);
    const key = `${entry.path}:${entry.riskKind}`;
    if (keys.has(key)) failures.push(`${label} duplicates boundedness baseline key ${key}`);
    keys.add(key);
  }
  return keys;
}

function requireSnippet(rootDir, relativePath, snippet, failures) {
  const filePath = path.join(rootDir, relativePath);
  if (!fs.existsSync(filePath)) {
    failures.push(`missing ${relativePath}`);
    return;
  }
  const content = fs.readFileSync(filePath, "utf8");
  if (!content.includes(snippet)) failures.push(`${relativePath} must include ${JSON.stringify(snippet)}`);
}

function checkRoot(rootDir) {
  const failures = [];
  requireSnippet(rootDir, "docs/governance/performance-governance.md", "Windowing/Pagination by Default", failures);
  requireSnippet(rootDir, "docs/governance/performance-governance.md", "load all -> filter/sort/render", failures);
  requireSnippet(rootDir, "docs/governance/performance-governance.md", "cursor/window/batch/limit", failures);

  const baselinePath = "docs/boundedness-baseline.json";
  if (!fs.existsSync(path.join(rootDir, baselinePath))) failures.push(`missing ${baselinePath}`);
  const baseline = fs.existsSync(path.join(rootDir, baselinePath)) ? readJson(rootDir, baselinePath) : { entries: [] };
  const baselineKeys = validateBaseline(rootDir, baseline, failures);
  const files = [...new Set(scanRoots.flatMap((scanRoot) => listFiles(rootDir, scanRoot)))].sort();
  const findings = files.flatMap((file) => scanFile(rootDir, file));

  for (const finding of findings) {
    if (!baselineKeys.has(`${finding.path}:${finding.riskKind}`)) {
      failures.push(`${finding.path}:${finding.line} has ${finding.riskKind} without an explicit cursor/window/batch/limit or docs/boundedness-baseline.json entry: ${finding.snippet}`);
    }
  }
  return { failures, findings, filesScanned: files.length };
}

function writeFixture(rootDir, relativePath, content) {
  const filePath = path.join(rootDir, relativePath);
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, content);
}

function runGuard(rootDir) {
  return spawnSync(process.execPath, [new URL(import.meta.url).pathname, "--root", rootDir], { encoding: "utf8" });
}

function runSelfTest() {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "boundedness-guard-"));
  const baseline = { schemaVersion: 1, program: "boundedness-guard", defaultExpiryDays: 90, entries: [] };
  writeFixture(tempRoot, "docs/governance/performance-governance.md", "# Performance Governance\n\nNo windowing policy yet.\n");
  writeFixture(tempRoot, "docs/boundedness-baseline.json", JSON.stringify(baseline, null, 2));
  writeFixture(tempRoot, "packages/demo/src/db.ts", "await database.listRecords('sessions');\n");

  let result = runGuard(tempRoot);
  if (result.status === 0 || !result.stderr.includes("Windowing/Pagination by Default")) throw new Error("self-test failed to catch missing policy text");

  writeFixture(tempRoot, "docs/governance/performance-governance.md", "# Performance Governance\n\n## Windowing/Pagination by Default\n\nDo not load all -> filter/sort/render. Use cursor/window/batch/limit by default.\n");
  result = runGuard(tempRoot);
  if (result.status === 0 || !result.stderr.includes("database-list-without-explicit-window")) throw new Error("self-test failed to catch unbounded listRecords");

  writeFixture(tempRoot, "packages/demo/src/db.ts", "await database.listRecords('sessions', { limit: 50, offset: 0 });\n");
  writeFixture(tempRoot, "scripts/reader.mjs", "const content = fs.readFileSync('rollout.jsonl', 'utf8');\n");
  result = runGuard(tempRoot);
  if (result.status === 0 || !result.stderr.includes("full-jsonl-read")) throw new Error("self-test failed to catch full JSONL read");

  writeFixture(tempRoot, "scripts/reader.mjs", "const MAX_ROLLOUT_BYTES = 1024;\nconst content = fs.readFileSync('rollout.jsonl', 'utf8');\n");
  writeFixture(tempRoot, "macos/App.swift", "let messages = store.messages\nForEach(messages) { message in Text(message.text) }\n");
  result = runGuard(tempRoot);
  if (result.status === 0 || !result.stderr.includes("ui-foreach-over-unbounded-source")) throw new Error("self-test failed to catch unbounded UI ForEach");

  writeFixture(tempRoot, "docs/boundedness-baseline.json", JSON.stringify({
    ...baseline,
    entries: [{
      id: "demo-ui-baseline",
      path: "macos/App.swift",
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
  result = runGuard(tempRoot);
  if (result.status !== 0) throw new Error(`self-test baseline should pass: ${result.stderr}`);
  fs.rmSync(tempRoot, { recursive: true, force: true });
}

if (args.selfTest) {
  runSelfTest();
  console.log("boundedness guard self-test passed");
} else {
  const { failures, findings, filesScanned } = checkRoot(args.rootDir);
  if (failures.length > 0) {
    console.error("Boundedness guard failed:");
    for (const failure of failures) console.error(`- ${failure}`);
    process.exit(1);
  }
  console.log(`Boundedness guard passed (${filesScanned} files scanned, ${findings.length} baseline-covered findings).`);
}
