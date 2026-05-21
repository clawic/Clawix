#!/usr/bin/env node
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

const excludedParts = new Set([".git", ".next", ".tmp", ".turbo", "build", ".build", "dist", "coverage", "node_modules", "vendor", "fixtures", "__fixtures__", "generated", "DerivedData", "target"]);
const excludedBasenames = new Set(["package-lock.json", "Cargo.lock", "codebase-manifest.json", "conceptual-vocabulary-baseline.json", "discoverability.registry.json", "discoverability.md", "discoverability-baseline.json"]);
const allowedExtensions = new Set([".cjs", ".cs", ".js", ".jsx", ".kt", ".mjs", ".md", ".sh", ".swift", ".ts", ".tsx", ".yaml", ".yml"]);
const scanRoots = ["apps", "bridge", "cli", "docs", "macos", "ios", "android", "linux", "packages", "publishing", "scripts", "skills", "tests", "web", "windows"];
const boundPattern = /\b(?:bounded|bound|limit|limited|max(?:imum)?|capacity|cap|bytes?|size|count|age|ttl|expires?|expiry|retention|cleanup|clean-up|prune|trim|evict|eviction|compact|compaction|window|active window|lease|backpressure|pagination|pageSize|batchSize|watermark|rotate|rotation|drop oldest|drop-oldest|ring buffer|lru|cleanupPolicy|stream|streaming)\b/iu;
const retainedCollection = /(?:new\s+(?:Map|Set|Array)|NSCache|Map\(|Set\(|\[\]|\{\}|Cache\(|Queue\(|Deque|Array|List<|String\s*=\s*["'])/u;
const riskPatterns = [
  { riskKind: "buffer-concat", applies: (line) => /\bBuffer\.concat\s*\(/u.test(line) },
  { riskKind: "whole-data-buffer", applies: (line) => /\bData\s*\([^)]*(?:contentsOf|count:|bytes:)/u.test(line) && /\b(?:upload|attachment|payload|audio|image|video|archive|transcript)\b/iu.test(line) },
  { riskKind: "eventbus", applies: (line) => /\b(?:class|struct|actor|interface|type|const|let|var|private|public|static|final)\s+\w*EventBus\w*\b/u.test(line) },
  { riskKind: "fanout", applies: (line) => /\b(?:fanout|fanOut|subscribers?|connections?|clients?)\w*\s*(?:[:=]|=|=>)\s*(?:new\s+(?:Map|Set|Array)|\[\]|\{\}|Set\(|Map\()/u.test(line) },
  { riskKind: "cache", applies: (line) => /\b(?:class|actor|final class)\s+\w*[Cc]ache\w*\b/u.test(line) || (/\b(?:const|let|var|private|public|static|final|val)\s+\w*[Cc]ache\w*\s*(?:[:=]|=)/u.test(line) && retainedCollection.test(line)) },
  { riskKind: "queue", applies: (line) => /\b(?:class|actor|final class)\s+\w*[Qq]ueue\w*\b/u.test(line) || (/\b(?:const|let|var|private|public|static|final|val)\s+\w*[Qq]ueue\w*\s*(?:[:=]|=)/u.test(line) && retainedCollection.test(line)) },
  { riskKind: "log", applies: (line) => /\b(?:class|actor|final class)\s+\w*(?:LogStore|AuditStore|AuditLog)\w*\b/u.test(line) || (/\b(?:const|let|var|private|public|static|final|val)\s+\w*(?:logs|auditLog|ledger)\w*\s*(?:[:=]|=)/iu.test(line) && retainedCollection.test(line)) },
  { riskKind: "snapshot", applies: (line) => /\b(?:const|let|var|private|public|static|final|val)\s+\w*[Ss]napshots?\w*\s*(?:[:=]|=)/u.test(line) && retainedCollection.test(line) },
  { riskKind: "checkpoint", applies: (line) => /\b(?:const|let|var|private|public|static|final|val)\s+\w*[Cc]heckpoints?\w*\s*(?:[:=]|=)/u.test(line) && retainedCollection.test(line) },
  { riskKind: "timeline", applies: (line) => /\b(?:const|let|var|private|public|static|final|val)\s+\w*[Tt]imeline\w*\s*(?:[:=]|=)/u.test(line) && retainedCollection.test(line) },
  { riskKind: "transcript", applies: (line) => /\b(?:const|let|var|private|public|static|final|val|@State)\s+\w*[Tt]ranscripts?\w*\s*(?:[:=]|=)/u.test(line) && retainedCollection.test(line) },
  { riskKind: "session-state", applies: (line) => /\b(?:const|let|var|private|public|static|final|val|@State)\s+\w*(?:SessionState|sessionState)\w*\s*(?:[:=]|=)/u.test(line) && retainedCollection.test(line) },
  { riskKind: "ranking-cache", applies: (line) => /\b(?:class|actor|final class)\s+\w*(?:RankingCache|rankingCache)\w*\b/u.test(line) || /\b(?:const|let|var|private|public|static|final|val)\s+\w*(?:RankingCache|rankingCache)\w*\s*(?:[:=]|=)/u.test(line) },
];
function relative(rootDir, absolutePath) { return path.relative(rootDir, absolutePath).split(path.sep).join("/"); }
function readText(rootDir, relativePath) { return fs.readFileSync(path.join(rootDir, relativePath), "utf8"); }
function readJson(rootDir, relativePath) { return JSON.parse(readText(rootDir, relativePath)); }
function isDate(value) { return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/u.test(value); }
function shouldSkip(relativePath) {
  const parts = relativePath.split("/");
  if (parts.some((part) => excludedParts.has(part))) return true;
  const basename = path.basename(relativePath);
  if (excludedBasenames.has(basename)) return true;
  if (/\.generated\./u.test(basename) || basename.endsWith(".min.js")) return true;
  if (relativePath.startsWith("docs/") && basename !== "boundedness-baseline.json" && (basename.includes("baseline") || basename.includes("projection") || basename.includes("registry") || basename.includes("surface-evidence") || basename.includes("manifest"))) return true;
  return !allowedExtensions.has(path.extname(relativePath));
}
function listFiles(rootDir, relativeDir, output = []) {
  const absoluteDir = path.join(rootDir, relativeDir);
  if (!fs.existsSync(absoluteDir)) return output;
  for (const entry of fs.readdirSync(absoluteDir, { withFileTypes: true })) {
    const absolutePath = path.join(absoluteDir, entry.name);
    const relativePath = relative(rootDir, absolutePath);
    if (entry.isDirectory()) { if (!excludedParts.has(entry.name)) listFiles(rootDir, relativePath, output); }
    else if (entry.isFile() && !shouldSkip(relativePath)) output.push(relativePath);
  }
  return output;
}
function nearbyHasBound(lines, index) {
  const start = Math.max(0, index - 8);
  const end = Math.min(lines.length - 1, index + 8);
  return boundPattern.test(lines.slice(start, end + 1).join("\n"));
}
function scanFile(rootDir, relativePath) {
  const lines = readText(rootDir, relativePath).split(/\r?\n/u);
  const findings = [];
  for (const [index, line] of lines.entries()) {
    for (const risk of riskPatterns) {
      if (!risk.applies(line) || nearbyHasBound(lines, index)) continue;
      findings.push({ path: relativePath, line: index + 1, riskKind: risk.riskKind, snippet: line.trim().slice(0, 160) });
    }
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
    if (ids.has(entry.id)) failures.push(`${label} duplicates id ${entry.id}`);
    ids.add(entry.id);
    for (const field of ["path", "riskKind", "ownerArea", "reason", "limitKind", "limitValue", "cleanupPolicy", "reference", "expiresAt"]) if (entry[field] === undefined || entry[field] === "") failures.push(`${label} is missing ${field}`);
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
  if (!fs.existsSync(filePath)) { failures.push(`missing ${relativePath}`); return; }
  const content = fs.readFileSync(filePath, "utf8");
  if (!content.includes(snippet)) failures.push(`${relativePath} must include ${JSON.stringify(snippet)}`);
}
function checkRoot(rootDir) {
  const failures = [];
  requireSnippet(rootDir, "docs/governance/performance-governance.md", "Boundedness Guard P0", failures);
  requireSnippet(rootDir, "docs/governance/performance-governance.md", "bytes, count, age, or active-window limit", failures);
  const baselinePath = "docs/boundedness-baseline.json";
  if (!fs.existsSync(path.join(rootDir, baselinePath))) failures.push(`missing ${baselinePath}`);
  const baseline = fs.existsSync(path.join(rootDir, baselinePath)) ? readJson(rootDir, baselinePath) : { entries: [] };
  const baselineKeys = validateBaseline(rootDir, baseline, failures);
  const files = [...new Set(scanRoots.flatMap((scanRoot) => listFiles(rootDir, scanRoot)))].sort();
  const findings = files.flatMap((file) => scanFile(rootDir, file));
  for (const finding of findings) if (!baselineKeys.has(`${finding.path}:${finding.riskKind}`)) failures.push(`${finding.path}:${finding.line} declares ${finding.riskKind} without a nearby bound or docs/boundedness-baseline.json entry: ${finding.snippet}`);
  return { failures, findings, filesScanned: files.length };
}
function writeFixture(rootDir, relativePath, content) {
  const filePath = path.join(rootDir, relativePath);
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, content);
}
function runSelfTest() {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "boundedness-guard-"));
  writeFixture(tempRoot, "docs/governance/performance-governance.md", "# Performance Governance\n\nNo boundedness policy yet.\n");
  writeFixture(tempRoot, "docs/boundedness-baseline.json", JSON.stringify({ schemaVersion: 1, program: "boundedness-guard", defaultExpiryDays: 90, entries: [] }, null, 2));
  writeFixture(tempRoot, "packages/demo/src/cache.ts", "const resultCache = new Map();\n");
  let result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, "--root", tempRoot], { encoding: "utf8" });
  if (result.status === 0 || !result.stderr.includes("Boundedness Guard P0")) throw new Error("self-test failed to catch missing policy text");
  writeFixture(tempRoot, "docs/governance/performance-governance.md", "# Performance Governance\n\n## Boundedness Guard P0\n\nRisk state needs a bytes, count, age, or active-window limit plus cleanup.\n");
  result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, "--root", tempRoot], { encoding: "utf8" });
  if (result.status === 0 || !result.stderr.includes("cache")) throw new Error("self-test failed to catch unbounded cache");
  writeFixture(tempRoot, "packages/demo/src/cache.ts", "// max count cleanup\nconst resultCache = new Map();\nfunction cleanupResultCache() {}\n");
  result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, "--root", tempRoot], { encoding: "utf8" });
  if (result.status !== 0) throw new Error(`self-test bounded cache should pass: ${result.stderr}`);
  writeFixture(tempRoot, "packages/demo/src/upload.ts", "const body = Buffer.concat(chunks);\n");
  result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, "--root", tempRoot], { encoding: "utf8" });
  if (result.status === 0 || !result.stderr.includes("buffer-concat")) throw new Error("self-test failed to catch Buffer.concat");
  writeFixture(tempRoot, "docs/boundedness-baseline.json", JSON.stringify({ schemaVersion: 1, program: "boundedness-guard", defaultExpiryDays: 90, entries: [{ id: "expired-buffer", path: "packages/demo/src/upload.ts", riskKind: "buffer-concat", ownerArea: "demo", reason: "self-test", limitKind: "count", limitValue: "temporary", cleanupPolicy: "replace with streaming", reference: "self-test", expiresAt: "2000-01-01", blocksRelease: true }] }, null, 2));
  result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, "--root", tempRoot], { encoding: "utf8" });
  if (result.status === 0 || !result.stderr.includes("expired")) throw new Error("self-test failed to catch expired baseline");
  writeFixture(tempRoot, "docs/boundedness-baseline.json", JSON.stringify({ schemaVersion: 1, program: "boundedness-guard", defaultExpiryDays: 90, entries: [{ id: "missing-cleanup", path: "packages/demo/src/upload.ts", riskKind: "buffer-concat", ownerArea: "demo", reason: "self-test", limitKind: "count", limitValue: "temporary", reference: "self-test", expiresAt: "2099-01-01", blocksRelease: true }] }, null, 2));
  result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, "--root", tempRoot], { encoding: "utf8" });
  if (result.status === 0 || !result.stderr.includes("cleanupPolicy")) throw new Error("self-test failed to catch missing cleanup policy");
  fs.rmSync(tempRoot, { recursive: true, force: true });
}
if (args.selfTest) { runSelfTest(); console.log("boundedness guard self-test passed"); process.exit(0); }
const result = checkRoot(args.rootDir);
if (result.failures.length > 0) {
  console.error("boundedness guard failed:");
  for (const failure of result.failures) console.error(`- ${failure}`);
  process.exit(1);
}
console.log(`boundedness guard passed (${result.filesScanned} files scanned, ${result.findings.length} findings baselined)`);
