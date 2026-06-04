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
const baselinePath = "docs/hot-path-baseline.json";
const hotPathMarker = /\bhot-path-ok\b/u;
const boundMarker = /\bmax(?:Bytes|Items|Pixels)\s*[:=]\s*[1-9][0-9_]*\b/u;
const reasonMarker = /\b(?:why|reason)\s*[:=]\s*\S+/u;

const excludedParts = new Set([".git", ".next", ".tmp", "build", ".build", "DerivedData", "dist", "coverage", "node_modules", "vendor"]);
const excludedBasenames = new Set(["package-lock.json", "Cargo.lock", "discoverability.registry.json", "discoverability.md"]);
const allowedExtensions = new Set([".swift", ".js", ".jsx", ".mjs", ".ts", ".tsx"]);
const scanRoots = ["macos/Sources", "ios/Sources", "web/src", "linux/app/src"];

const riskRules = [
  {
    kind: "wait-until-exit-main-thread",
    pattern: /\bwaitUntilExit\s*\(/u,
    context: "swift-main",
  },
  {
    kind: "json-decode-hot-path",
    pattern: /\b(?:JSONDecoder\s*\(\)\.decode|JSONSerialization\.jsonObject|JSON\.parse\s*\()/u,
    context: "hot-path",
  },
  {
    kind: "markdown-parse-hot-path",
    pattern: /\b(?:MarkdownParseCache\.parse|AssistantMarkdownParser\.parse|AssistantMarkdown\.parse|renderMarkdown\s*\(|new\s+MarkdownIt\s*\()/u,
    context: "render",
  },
  {
    kind: "image-decode-hot-path",
    pattern: /\b(?:NSImage\s*\(\s*data:|UIImage\s*\(\s*data:|CGImageSourceCreateImageAtIndex\s*\()/u,
    context: "render",
  },
  {
    kind: "buffer-concat-hot-path",
    pattern: /\bBuffer\.concat\s*\(/u,
    context: "web-render",
  },
  {
    kind: "readfile-split-hot-path",
    pattern: /\breadFileSync\s*\([^)]*\)[\s\S]{0,220}\.split\s*\(/u,
    context: "web-render",
    multiline: true,
  },
  {
    kind: "collection-transform-in-body",
    pattern: /\.(?:sorted|sort)\s*\(/u,
    context: "swift-body",
  },
];

function relative(rootDir, absolutePath) {
  return path.relative(rootDir, absolutePath).split(path.sep).join("/");
}

function isDate(value) {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/u.test(value);
}

function shouldSkip(relativePath) {
  const parts = relativePath.split("/");
  if (parts.some((part) => excludedParts.has(part))) return true;
  if (excludedBasenames.has(path.basename(relativePath))) return true;
  if (/\.generated\./u.test(path.basename(relativePath))) return true;
  if (/\.(?:test|spec)\.[cm]?[jt]sx?$/u.test(relativePath)) return true;
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

function readText(rootDir, relativePath) {
  return fs.readFileSync(path.join(rootDir, relativePath), "utf8");
}

function readJson(rootDir, relativePath) {
  return JSON.parse(readText(rootDir, relativePath));
}

function lineNumberForOffset(text, offset) {
  return text.slice(0, offset).split(/\r?\n/u).length;
}

function contextWindow(lines, index, radius = 28) {
  return lines.slice(Math.max(0, index - radius), Math.min(lines.length, index + radius + 1)).join("\n");
}

function lookback(lines, index, radius = 48) {
  return lines.slice(Math.max(0, index - radius), index + 1).join("\n");
}

function markerWindow(lines, index) {
  return lines.slice(Math.max(0, index - 3), Math.min(lines.length, index + 4)).join("\n");
}

function hasInlineException(lines, index) {
  const nearby = markerWindow(lines, index);
  return hotPathMarker.test(nearby) && boundMarker.test(nearby) && reasonMarker.test(nearby);
}

function isSwiftBody(lines, index) {
  return /\bvar\s+body\s*:\s*some\s+View\b/u.test(lookback(lines, index, 36));
}

function isSwiftMain(lines, index) {
  return /@MainActor\b|DispatchQueue\.main|MainActor\.run|Task\s*\{\s*@MainActor/u.test(contextWindow(lines, index, 36));
}

function isSwiftRender(relativePath, lines, index) {
  const nearby = contextWindow(lines, index, 36);
  return isSwiftBody(lines, index) ||
    /\b(?:render|update|receive|apply|body|frame|message|event|realtime|websocket|delta)\b/iu.test(nearby);
}

function isSwiftJsonHotPath(lines, index) {
  const nearby = contextWindow(lines, index, 36);
  return isSwiftBody(lines, index) ||
    (isSwiftMain(lines, index) && /\b(?:render|receive|apply|body|frame|message|event|realtime|websocket|delta)\b/iu.test(nearby));
}

function isWebRender(relativePath, lines, index) {
  if (!/\.[cm]?[jt]sx?$/u.test(relativePath)) return false;
  return /(?:^|\/)(?:views|screens|routes|components)(?:\/|$)/u.test(relativePath);
}

function matchesContext(rule, relativePath, lines, index) {
  const isSwift = relativePath.endsWith(".swift");
  if (rule.context === "swift-body") return isSwift && isSwiftBody(lines, index);
  if (rule.context === "swift-main") return isSwift && isSwiftMain(lines, index);
  if (rule.context === "render") return isSwift ? isSwiftRender(relativePath, lines, index) : isWebRender(relativePath, lines, index);
  if (rule.context === "web-render") return isWebRender(relativePath, lines, index);
  if (rule.context === "hot-path") return isSwift ? isSwiftJsonHotPath(lines, index) : isWebRender(relativePath, lines, index);
  return false;
}

function baselineKey(finding) {
  return `${finding.path}:${finding.riskKind}:${finding.linePattern}`;
}

function validateBaseline(rootDir, failures) {
  if (!fs.existsSync(path.join(rootDir, baselinePath))) {
    failures.push(`missing ${baselinePath}`);
    return new Set();
  }
  const baseline = readJson(rootDir, baselinePath);
  if (baseline.schemaVersion !== 1) failures.push(`${baselinePath} schemaVersion must be 1`);
  if (baseline.program !== "hot-path-guard") failures.push(`${baselinePath} program must be hot-path-guard`);
  if (!Array.isArray(baseline.entries)) failures.push(`${baselinePath}.entries must be an array`);
  const today = new Date().toISOString().slice(0, 10);
  const ids = new Set();
  const keys = new Set();
  for (const [index, entry] of (baseline.entries ?? []).entries()) {
    const label = entry.id || `entries[${index}]`;
    if (!entry.id) failures.push(`${label} is missing id`);
    if (ids.has(entry.id)) failures.push(`${label} duplicates id ${entry.id}`);
    ids.add(entry.id);
    for (const field of ["path", "linePattern", "riskKind", "ownerArea", "limitKind", "limitValue", "reason", "replacementPlan", "expiresAt"]) {
      if (entry[field] === undefined || entry[field] === "") failures.push(`${label} is missing ${field}`);
    }
    if (typeof entry.blocksRelease !== "boolean") failures.push(`${label} blocksRelease must be boolean`);
    if (entry.path && !fs.existsSync(path.join(rootDir, entry.path))) failures.push(`${label} path does not exist: ${entry.path}`);
    if (entry.expiresAt && !isDate(entry.expiresAt)) failures.push(`${label} expiresAt must be YYYY-MM-DD`);
    if (isDate(entry.expiresAt) && entry.expiresAt < today) failures.push(`${label} expired on ${entry.expiresAt}`);
    if (entry.path && entry.linePattern && fs.existsSync(path.join(rootDir, entry.path))) {
      const source = readText(rootDir, entry.path);
      if (!source.includes(entry.linePattern)) failures.push(`${label} linePattern is not present in ${entry.path}`);
    }
    const key = `${entry.path}:${entry.riskKind}:${entry.linePattern}`;
    if (keys.has(key)) failures.push(`${label} duplicates hot-path baseline key ${key}`);
    keys.add(key);
  }
  return keys;
}

function findMultilineRisk(content, rule) {
  const findings = [];
  for (const match of content.matchAll(new RegExp(rule.pattern.source, "gu"))) {
    findings.push({ offset: match.index ?? 0, snippet: match[0].replace(/\s+/gu, " ").trim().slice(0, 180) });
  }
  return findings;
}

// Replace the inside of line comments, block comments, and string literals with
// spaces (preserving newlines and length) so risk rules only fire on real code,
// not on doc comments that DESCRIBE a forbidden operation (e.g. a draw-only row
// documenting that it performs no MarkdownParseCache.parse).
function maskCommentsAndStrings(source) {
  const out = source.split("");
  const length = source.length;
  let index = 0;
  let state = "code"; // code | line | block | string
  while (index < length) {
    const char = source[index];
    const next = source[index + 1];
    if (state === "code") {
      if (char === "/" && next === "/") { out[index] = " "; out[index + 1] = " "; state = "line"; index += 2; continue; }
      if (char === "/" && next === "*") { out[index] = " "; out[index + 1] = " "; state = "block"; index += 2; continue; }
      if (char === '"') { state = "string"; index += 1; continue; }
      index += 1;
      continue;
    }
    if (state === "line") {
      if (char === "\n") { state = "code"; index += 1; continue; }
      out[index] = " "; index += 1; continue;
    }
    if (state === "block") {
      if (char === "*" && next === "/") { out[index] = " "; out[index + 1] = " "; state = "code"; index += 2; continue; }
      if (char !== "\n") out[index] = " ";
      index += 1; continue;
    }
    // string
    if (char === "\\") { out[index] = " "; out[index + 1] = next === "\n" ? "\n" : " "; index += 2; continue; }
    if (char === '"') { state = "code"; index += 1; continue; }
    if (char !== "\n") out[index] = " ";
    index += 1;
  }
  return out.join("");
}

function scanFile(rootDir, relativePath) {
  const raw = readText(rootDir, relativePath);
  // Risk patterns match on masked code (no comments/strings); context windows and
  // the hot-path-ok inline marker live in comments, so they read the RAW lines.
  const masked = maskCommentsAndStrings(raw);
  const rawLines = raw.split(/\r?\n/u);
  const lines = masked.split(/\r?\n/u);
  const findings = [];
  for (const rule of riskRules) {
    if (rule.multiline) {
      for (const match of findMultilineRisk(masked, rule)) {
        const line = lineNumberForOffset(masked, match.offset);
        const index = line - 1;
        if (!matchesContext(rule, relativePath, lines, index) || hasInlineException(rawLines, index)) continue;
        findings.push({ path: relativePath, line, riskKind: rule.kind, linePattern: match.snippet, snippet: match.snippet });
      }
      continue;
    }
    for (const [index, line] of lines.entries()) {
      if (!rule.pattern.test(line)) continue;
      if (/^\s*import\s/u.test(line)) continue;
      if (!matchesContext(rule, relativePath, lines, index) || hasInlineException(rawLines, index)) continue;
      const linePattern = rawLines[index].trim().slice(0, 180);
      findings.push({ path: relativePath, line: index + 1, riskKind: rule.kind, linePattern, snippet: linePattern });
    }
  }
  return findings;
}

function requireSnippet(rootDir, relativePath, snippet, failures) {
  const filePath = path.join(rootDir, relativePath);
  if (!fs.existsSync(filePath)) {
    failures.push(`missing ${relativePath}`);
    return;
  }
  if (!fs.readFileSync(filePath, "utf8").includes(snippet)) failures.push(`${relativePath} must include ${JSON.stringify(snippet)}`);
}

// Dead-mirror check (ADR 0042): a presentation mirror/cache type that is defined
// but has no consumer outside its own defining file is unwired governance debt.
// Either wire it or delete it. Types with no definition at all are skipped.
const deadMirrorTypes = ["TranscriptWindowModel", "ToolTimelinePresentationCache"];

function checkDeadMirrors(rootDir, failures) {
  const files = listFiles(rootDir, "macos/Sources").filter((file) => file.endsWith(".swift"));
  for (const typeName of deadMirrorTypes) {
    const definitionPattern = new RegExp(`\\b(?:final\\s+)?(?:class|struct|enum|actor)\\s+${typeName}\\b`, "u");
    const usagePattern = new RegExp(`\\b${typeName}\\b`, "u");
    let definedIn = null;
    const consumers = [];
    for (const file of files) {
      const text = readText(rootDir, file);
      if (definedIn === null && definitionPattern.test(text)) definedIn = file;
    }
    if (definedIn === null) continue; // not present: nothing to flag
    for (const file of files) {
      if (file === definedIn) continue;
      if (usagePattern.test(readText(rootDir, file))) consumers.push(file);
    }
    if (consumers.length === 0) {
      failures.push(`${typeName} is defined in ${definedIn} but unwired (no consumer outside its file): wire it or delete it (ADR 0042 dead-mirror)`);
    }
  }
}

function checkRoot(rootDir) {
  const failures = [];
  requireSnippet(rootDir, "docs/governance/performance-governance.md", "Hot Path Guard P1", failures);
  requireSnippet(rootDir, "docs/decision-map.md", "scripts/hot_path_guard.mjs", failures);
  requireSnippet(rootDir, "scripts/test.sh", "scripts/hot_path_guard.mjs", failures);
  const baselineKeys = validateBaseline(rootDir, failures);
  const files = [...new Set(scanRoots.flatMap((scanRoot) => listFiles(rootDir, scanRoot)))].sort();
  const findings = files.flatMap((file) => scanFile(rootDir, file));
  for (const finding of findings) {
    if (!baselineKeys.has(baselineKey(finding))) {
      failures.push(`${finding.path}:${finding.line} ${finding.riskKind} needs hot-path-ok with maxBytes/maxItems/maxPixels or ${baselinePath}: ${finding.snippet}`);
    }
  }
  checkDeadMirrors(rootDir, failures);
  return { failures, filesScanned: files.length, findings };
}

function writeFixture(rootDir, relativePath, content) {
  const filePath = path.join(rootDir, relativePath);
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, content);
}

function fixtureDocs(rootDir, entries = []) {
  writeFixture(rootDir, "docs/governance/performance-governance.md", "# Performance Governance\n\n## Hot Path Guard P1\n\nHot path work needs bounded-size proof.\n");
  writeFixture(rootDir, "docs/decision-map.md", "scripts/hot_path_guard.mjs\n");
  writeFixture(rootDir, "scripts/test.sh", "node \"$ROOT_DIR/scripts/hot_path_guard.mjs\"\nnode \"$ROOT_DIR/scripts/hot_path_guard.mjs\" --self-test\n");
  writeFixture(rootDir, baselinePath, JSON.stringify({ schemaVersion: 1, program: "hot-path-guard", entries }, null, 2));
}

function expectFailure(rootDir, needle) {
  const result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, "--root", rootDir], { encoding: "utf8" });
  if (result.status === 0 || !String(result.stderr).includes(needle)) {
    throw new Error(`expected failure containing ${needle}, got status ${result.status}: ${result.stderr}`);
  }
}

function expectPass(rootDir) {
  const result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, "--root", rootDir], { encoding: "utf8" });
  if (result.status !== 0) throw new Error(`expected pass: ${result.stderr}`);
}

function runSelfTest() {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "hot-path-guard-"));
  try {
    fixtureDocs(tempRoot);
    writeFixture(tempRoot, "macos/Sources/Clawix/SlowView.swift", "import SwiftUI\nstruct SlowView: View {\n  var items: [String]\n  var body: some View {\n    ForEach(items.sorted(), id: \\.self) { Text($0) }\n  }\n}\n");
    expectFailure(tempRoot, "collection-transform-in-body");
    writeFixture(tempRoot, "macos/Sources/Clawix/SlowView.swift", "import SwiftUI\nstruct SlowView: View {\n  var items: [String]\n  var body: some View {\n    // hot-path-ok maxItems=32 reason=visible menu entries only\n    ForEach(items.sorted(), id: \\.self) { Text($0) }\n  }\n}\n");
    expectPass(tempRoot);
    writeFixture(tempRoot, "macos/Sources/Clawix/ProcessController.swift", "@MainActor\nfinal class ProcessController {\n  func run(_ process: Process) {\n    process.waitUntilExit()\n  }\n}\n");
    expectFailure(tempRoot, "wait-until-exit-main-thread");
    writeFixture(tempRoot, "macos/Sources/Clawix/ProcessController.swift", "");
    writeFixture(tempRoot, "macos/Sources/Clawix/AvatarView.swift", "import SwiftUI\nstruct AvatarView: View {\n  let data: Data\n  var body: some View {\n    let image = NSImage(data: data)\n    Text(String(describing: image))\n  }\n}\n");
    expectFailure(tempRoot, "image-decode-hot-path");
    writeFixture(tempRoot, "macos/Sources/Clawix/AvatarView.swift", "");
    writeFixture(tempRoot, "macos/Sources/Clawix/MarkdownView.swift", "import SwiftUI\nstruct MarkdownView: View {\n  let text: String\n  var body: some View {\n    let parsed = MarkdownParseCache.parse(text)\n    Text(String(describing: parsed))\n  }\n}\n");
    expectFailure(tempRoot, "markdown-parse-hot-path");
    writeFixture(tempRoot, "macos/Sources/Clawix/MarkdownView.swift", "");
    writeFixture(tempRoot, "web/src/screens/demo/demo-view.tsx", "export function DemoView() {\n  window.addEventListener('message', (event) => {\n    const payload = JSON.parse(event.data);\n  });\n  return null;\n}\n");
    expectFailure(tempRoot, "json-decode-hot-path");
    writeFixture(tempRoot, "web/src/screens/demo/demo-view.tsx", "");
    writeFixture(tempRoot, "linux/app/src/views/LogView.tsx", "export function LogView() {\n  const lines = fs.readFileSync(path, 'utf8').split('\\n');\n  return null;\n}\n");
    expectFailure(tempRoot, "readfile-split-hot-path");
    writeFixture(tempRoot, "linux/app/src/views/LogView.tsx", "");
    writeFixture(tempRoot, "web/src/screens/demo/demo-view.tsx", "export function DemoView() {\n  // hot-path-ok maxBytes=4096 reason=bounded postMessage payload\n  const body = Buffer.concat(chunks);\n  return null;\n}\n");
    expectPass(tempRoot);
    writeFixture(tempRoot, "web/src/screens/demo/demo-view.tsx", "export function DemoView() {\n  const body = Buffer.concat(chunks);\n  return null;\n}\n");
    fixtureDocs(tempRoot, [{
      id: "expired-buffer-concat",
      path: "web/src/screens/demo/demo-view.tsx",
      linePattern: "const body = Buffer.concat(chunks);",
      riskKind: "buffer-concat-hot-path",
      ownerArea: "web",
      limitKind: "maxBytes",
      limitValue: "4096",
      reason: "self-test baseline",
      replacementPlan: "stream payload",
      expiresAt: "2000-01-01",
      blocksRelease: true,
    }]);
    expectFailure(tempRoot, "expired");
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
}

if (args.selfTest) {
  runSelfTest();
  console.log("hot-path guard self-test passed");
  process.exit(0);
}

const result = checkRoot(args.rootDir);
if (result.failures.length > 0) {
  console.error("hot-path guard failed:");
  for (const failure of result.failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log(`hot-path guard passed (${result.filesScanned} files scanned, ${result.findings.length} findings baselined)`);
