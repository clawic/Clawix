#!/usr/bin/env node
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";

const defaultRootDir = path.resolve(new URL("..", import.meta.url).pathname);
const manifestPath = "docs/idle-quiescence.manifest.json";

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

const scanRoots = [
  "android",
  "apps",
  "ios",
  "linux",
  "macos",
  "packages",
  "web",
  "windows",
];

const excludedParts = new Set([
  ".git",
  ".next",
  ".tmp",
  ".build",
  "artifacts",
  "build",
  "checkouts",
  "coverage",
  "dist",
  "fixtures",
  "__fixtures__",
  "node_modules",
  "output",
  "test-results",
  "tests",
]);

const excludedBasenames = new Set([
  "package-lock.json",
  "pnpm-lock.yaml",
  "yarn.lock",
]);

const allowedExtensions = new Set([".html", ".js", ".jsx", ".mjs", ".ts", ".tsx", ".swift", ".kt"]);

function relative(rootDir, absolutePath) {
  return path.relative(rootDir, absolutePath).split(path.sep).join("/");
}

function shouldSkip(relativePath) {
  const parts = relativePath.split("/");
  if (parts.some((part) => excludedParts.has(part))) return true;
  const basename = path.basename(relativePath);
  if (excludedBasenames.has(basename)) return true;
  if (basename.endsWith(".min.js") || /\.generated\./u.test(basename)) return true;
  if (/\.(test|spec)\.[cm]?[jt]sx?$/u.test(basename)) return true;
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

function lineWindow(lines, index) {
  const start = Math.max(0, index - 4);
  const end = Math.min(lines.length - 1, index + 4);
  return lines.slice(start, end + 1).join("\n");
}

function classify(line, context) {
  if (/^\s*(?:import\b|\/\/|\*)/u.test(line)) return null;
  const text = `${context}\n${line}`;
  const trigger = line;
  const lower = text.toLowerCase();
  const hasTimer = /\b(?:setInterval|setTimeout|Timer\.scheduledTimer|DispatchSourceTimer|makeTimerSource|TimelineView\s*\(|asyncAfter|await\s+delay\s*\()/u.test(trigger);
  const hasWatcher = /\b(?:fs\.watch|watchFile|chokidar\.watch|FSEventStreamStart|FileSystemWatcher|DirectoryWatcher)\b/u.test(trigger);
  if (!hasTimer && !hasWatcher) return null;
  if (lower.includes("diagnostic") || lower.includes("probe") || lower.includes("hitch")) return "diagnostic-probe";
  if (lower.includes("heartbeat") || lower.includes("keepalive")) return "protocol-heartbeat";
  if (lower.includes("reconnect") || lower.includes("restart")) return "reconnect-backoff";
  if (lower.includes("poll")) return "poller";
  if (lower.includes("refresh") || lower.includes("invalidate")) return "refresh";
  if (hasWatcher) return "watcher";
  if (/\bTimelineView\s*\(/u.test(trigger)) return "timeline";
  if (/\b(?:setInterval|Timer\.scheduledTimer|DispatchSourceTimer|makeTimerSource)\b/u.test(trigger)) return "timer";
  return "timeout";
}

function scanFile(rootDir, relativePath) {
  const content = fs.readFileSync(path.join(rootDir, relativePath), "utf8");
  const lines = content.split(/\r?\n/u);
  const findings = [];
  for (const [index, line] of lines.entries()) {
    const mechanism = classify(line, lineWindow(lines, index));
    if (!mechanism) continue;
    findings.push({
      path: relativePath,
      line: index + 1,
      mechanism,
      snippet: line.trim().slice(0, 140),
    });
  }
  return findings;
}

function readJson(rootDir, relativePath, failures) {
  const filePath = path.join(rootDir, relativePath);
  if (!fs.existsSync(filePath)) {
    failures.push(`missing ${relativePath}`);
    return null;
  }
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch (error) {
    failures.push(`${relativePath} is not valid JSON: ${error.message}`);
    return null;
  }
}

function isDate(value) {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/u.test(value);
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

function mechanismMatches(entryMechanism, findingMechanism) {
  const text = String(entryMechanism ?? "").toLowerCase();
  const mechanism = findingMechanism.toLowerCase();
  if (text.includes(mechanism)) return true;
  if (["timer", "timeout", "timeline"].includes(mechanism) && text.includes("periodic")) return true;
  if (mechanism === "protocol-heartbeat" && text.includes("heartbeat")) return true;
  if (mechanism === "reconnect-backoff" && (text.includes("reconnect") || text.includes("restart"))) return true;
  if (mechanism === "poller" && text.includes("poll")) return true;
  return false;
}

function isUiEntry(entry) {
  const text = `${entry.path} ${entry.surface} ${entry.ownerArea}`.toLowerCase();
  return text.startsWith("apps/") || text.includes(" ui") || text.includes("-ui") || /\/views\//u.test(text);
}

function validatesBackoff(entry) {
  const mechanism = String(entry.mechanism ?? "").toLowerCase();
  if (!/(reconnect|restart|poll|refresh|health)/u.test(mechanism)) return true;
  const backoff = String(entry.backoff ?? "").toLowerCase();
  return /(adaptive|exponential|server-provided|visibility|visible|bounded|debounced|lease|tolerance|fixed.*debt)/u.test(backoff);
}

function validateEntry(entry, index, rootDir, failures) {
  const label = entry?.id || `entries[${index}]`;
  const required = [
    "id",
    "surface",
    "ownerArea",
    "path",
    "mechanism",
    "activation",
    "visibleOnly",
    "inactivityShutdown",
    "backoff",
    "sharedTimer",
    "diagnosticsOptIn",
    "releaseBehavior",
    "debugBehavior",
    "evidence",
    "blocksRelease",
    "expiresAt",
  ];
  for (const field of required) {
    if (!(field in entry) || entry[field] === "") failures.push(`${label} is missing ${field}`);
  }
  if (typeof entry.visibleOnly !== "boolean") failures.push(`${label}.visibleOnly must be boolean`);
  if (typeof entry.diagnosticsOptIn !== "boolean") failures.push(`${label}.diagnosticsOptIn must be boolean`);
  if (typeof entry.blocksRelease !== "boolean") failures.push(`${label}.blocksRelease must be boolean`);
  if (entry.path && !fs.existsSync(path.join(rootDir, entry.path))) failures.push(`${label}.path does not exist: ${entry.path}`);
  if (entry.expiresAt !== null && !isDate(entry.expiresAt)) failures.push(`${label}.expiresAt must be null or YYYY-MM-DD`);
  if (isDate(entry.expiresAt) && entry.expiresAt < new Date().toISOString().slice(0, 10)) failures.push(`${label} expired on ${entry.expiresAt}`);
  if (entry.blocksRelease && !isDate(entry.expiresAt)) failures.push(`${label}.expiresAt is required for release-blocking debt`);
  if (isUiEntry(entry) && entry.visibleOnly !== true) failures.push(`${label} is UI-visible work and must set visibleOnly true`);
  if (!validatesBackoff(entry)) failures.push(`${label} reconnect, poller, health, or refresh work must declare adaptive/backoff behavior`);
  if (/dedicated/i.test(String(entry.sharedTimer)) && !/(rationale|lease|protocol|ui|request|service)/i.test(String(entry.sharedTimer))) {
    failures.push(`${label}.sharedTimer uses a dedicated timer but does not include a rationale`);
  }
  const release = String(entry.releaseBehavior ?? "").toLowerCase();
  const debug = String(entry.debugBehavior ?? "").toLowerCase();
  if (release === debug) failures.push(`${label}.releaseBehavior must be distinct from debugBehavior`);
  if (release.includes("debug")) failures.push(`${label}.releaseBehavior must not enable debug behavior`);
  if (!entry.diagnosticsOptIn && /diagnostic|probe|hitch|sampler/u.test(release)) {
    failures.push(`${label}.releaseBehavior mixes diagnostics into release without diagnosticsOptIn`);
  }
  if (entry.diagnosticsOptIn && !/(opt-in|manual|disabled|explicit)/u.test(release)) {
    failures.push(`${label}.releaseBehavior for diagnostics must be explicit opt-in or disabled`);
  }
}

function checkRoot(rootDir) {
  const failures = [];
  requireSnippet(rootDir, "docs/governance/performance-governance.md", "## Idle Quiescence Contract P1", failures);
  requireSnippet(rootDir, "docs/governance/performance-governance.md", "docs/idle-quiescence.manifest.json", failures);
  requireSnippet(rootDir, "scripts/performance_governance_check.mjs", "idle_quiescence_check.mjs", failures);
  const manifest = readJson(rootDir, manifestPath, failures);
  if (manifest?.schemaVersion !== 1) failures.push(`${manifestPath}.schemaVersion must be 1`);
  if (manifest?.program !== "idle-quiescence-check") failures.push(`${manifestPath}.program must be idle-quiescence-check`);
  if (manifest?.severity !== "P1") failures.push(`${manifestPath}.severity must be P1`);
  if (!Array.isArray(manifest?.entries)) failures.push(`${manifestPath}.entries must be an array`);
  const entries = manifest?.entries ?? [];
  const ids = new Set();
  for (const [index, entry] of entries.entries()) {
    if (ids.has(entry.id)) failures.push(`${entry.id} duplicates id`);
    ids.add(entry.id);
    validateEntry(entry, index, rootDir, failures);
  }
  const files = [...new Set(scanRoots.flatMap((scanRoot) => listFiles(rootDir, scanRoot)))].sort();
  const findings = files.flatMap((file) => scanFile(rootDir, file));
  for (const finding of findings) {
    const matched = entries.some((entry) => entry.path === finding.path && mechanismMatches(entry.mechanism, finding.mechanism));
    if (!matched) {
      failures.push(`${finding.path}:${finding.line} declares ${finding.mechanism} without a matching ${manifestPath} entry: ${finding.snippet}`);
    }
  }
  return { failures, findings, filesScanned: files.length };
}

function writeFixture(rootDir, relativePath, content) {
  const filePath = path.join(rootDir, relativePath);
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, content);
}

function baseManifest(entries) {
  return JSON.stringify({
    schemaVersion: 1,
    program: "idle-quiescence-check",
    severity: "P1",
    policy: "test",
    entries,
  }, null, 2);
}

function validEntry(overrides = {}) {
  return {
    id: "demo-loop",
    surface: "Demo UI",
    ownerArea: "demo-ui",
    path: "apps/demo/src/app.ts",
    mechanism: "refresh,poller,timer,reconnect-backoff,diagnostic-probe",
    activation: "Only while visible.",
    visibleOnly: true,
    inactivityShutdown: "Clears on unmount.",
    backoff: "adaptive visibility-gated backoff.",
    sharedTimer: "dedicated UI timer with visible UI rationale.",
    diagnosticsOptIn: true,
    releaseBehavior: "Diagnostics disabled unless explicit opt-in.",
    debugBehavior: "Debug mode may run the probe.",
    evidence: "fixture",
    blocksRelease: false,
    expiresAt: null,
    ...overrides,
  };
}

function expectFail(rootDir, expected) {
  const result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, "--root", rootDir], { encoding: "utf8" });
  if (result.status === 0 || !result.stderr.includes(expected)) {
    throw new Error(`self-test expected failure containing ${expected}, got status ${result.status}: ${result.stderr}`);
  }
}

function runSelfTest() {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "idle-quiescence-check-"));
  writeFixture(tempRoot, "docs/governance/performance-governance.md", "# Performance Governance\n\n## Idle Quiescence Contract P1\n\nSee docs/idle-quiescence.manifest.json.\n");
  writeFixture(tempRoot, "scripts/performance_governance_check.mjs", "idle_quiescence_check.mjs\n");
  writeFixture(tempRoot, "apps/demo/src/app.ts", "setInterval(() => refresh(), 1000);\n");
  writeFixture(tempRoot, manifestPath, JSON.stringify({
    schemaVersion: 1,
    program: "idle-quiescence-check",
    severity: "P1",
    policy: "test",
    entries: null,
  }, null, 2));
  expectFail(tempRoot, "entries must be an array");
  writeFixture(tempRoot, manifestPath, baseManifest([validEntry({ visibleOnly: false })]));
  expectFail(tempRoot, "visibleOnly true");
  writeFixture(tempRoot, "apps/demo/src/app.ts", "function reconnect(){ setTimeout(reconnect, 1000); }\n");
  writeFixture(tempRoot, manifestPath, baseManifest([validEntry({ backoff: "none" })]));
  expectFail(tempRoot, "must declare adaptive/backoff");
  writeFixture(tempRoot, "apps/demo/src/app.ts", "setInterval(() => runDiagnosticProbe(), 1000);\n");
  writeFixture(tempRoot, manifestPath, baseManifest([validEntry({ diagnosticsOptIn: false, releaseBehavior: "Always run diagnostics in release." })]));
  expectFail(tempRoot, "mixes diagnostics");
  writeFixture(tempRoot, manifestPath, baseManifest([validEntry({ expiresAt: "2000-01-01" })]));
  expectFail(tempRoot, "expired");
  writeFixture(tempRoot, manifestPath, baseManifest([validEntry()]));
  const pass = spawnSync(process.execPath, [new URL(import.meta.url).pathname, "--root", tempRoot], { encoding: "utf8" });
  if (pass.status !== 0) throw new Error(`self-test valid fixture failed: ${pass.stderr}`);
  fs.rmSync(tempRoot, { recursive: true, force: true });
}

if (args.selfTest) {
  runSelfTest();
  console.log("idle quiescence check self-test passed");
  process.exit(0);
}

const result = checkRoot(args.rootDir);
if (result.failures.length > 0) {
  console.error("idle quiescence check failed:");
  for (const failure of result.failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log(`idle quiescence check passed (${result.filesScanned} files scanned, ${result.findings.length} findings covered)`);
