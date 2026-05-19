#!/usr/bin/env node
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const args = new Set(process.argv.slice(2));
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
let failed = false;

function fail(message) {
  failed = true;
  console.error(`open-source canonicity check failed: ${message}`);
}

function read(relativePath, base = root) {
  const file = path.join(base, relativePath);
  if (!fs.existsSync(file)) {
    fail(`missing ${relativePath}`);
    return "";
  }
  return fs.readFileSync(file, "utf8");
}

function requireSnippet(relativePath, snippet) {
  const text = read(relativePath).replace(/\s+/g, " ");
  const expected = snippet.replace(/\s+/g, " ");
  if (!text.includes(expected)) {
    fail(`${relativePath} is missing required snippet: ${snippet}`);
  }
}

function listFiles(relativeDir, predicate, output = []) {
  const absoluteDir = path.join(root, relativeDir);
  if (!fs.existsSync(absoluteDir)) return output;
  for (const entry of fs.readdirSync(absoluteDir, { withFileTypes: true })) {
    const relativePath = path.join(relativeDir, entry.name).split(path.sep).join("/");
    if (entry.isDirectory()) {
      if ([".git", ".build", "build", "node_modules", "test-results", "artifacts", "coverage"].includes(entry.name)) continue;
      listFiles(relativePath, predicate, output);
    } else if (entry.isFile() && predicate(relativePath)) {
      output.push(relativePath);
    }
  }
  return output.sort();
}

const forbiddenPublicPhrases = [
  /\banti[- ]fork\b/i,
  /\bblock(?:ing)? forks?\b/i,
  /\bprevent(?:ing)? forks?\b/i,
  /\bforbid(?:den|ding)? commercial use\b/i,
  /\bno commercial use\b/i,
  /\bopen[- ]core\b/i,
  /\bprivate beta ring\b/i,
  /\bprivate benchmark corpus\b/i,
  /\brelease moat scorecard\b/i,
  /\bcompetitive watchlist\b/i,
  /\bdistribution capture\b/i,
  /\bdefensive strategy\b/i,
];

function assertNoPrivateStrategyLanguage() {
  const scanned = [
    "README.md",
    "CONTRIBUTING.md",
    "RELEASING.md",
    "FORKS.md",
    "NOTICE",
    "TRADEMARKS.md",
    "DCO",
    ...listFiles("docs", (file) => file.endsWith(".md") || file.endsWith(".json")),
  ];
  for (const file of scanned) {
    const text = read(file);
    for (const pattern of forbiddenPublicPhrases) {
      if (pattern.test(text)) {
        fail(`${file} contains private or anti-open-source strategy wording: ${pattern}`);
      }
    }
  }
}

function assertOfficialCompatibleSeparation() {
  const docs = [
    "CONSTITUTION.md",
    "docs/adr/0020-open-standard-official-trust-mirror.md",
    "FORKS.md",
    "TRADEMARKS.md",
    "NOTICE",
  ];
  for (const file of docs) {
    const text = read(file);
    if (!/official/i.test(text)) fail(`${file} must mention official identity`);
    if (!/compatible|compatibility/i.test(text)) fail(`${file} must mention compatibility`);
  }
}

function runSelfTest() {
  for (const pattern of forbiddenPublicPhrases) {
    assert.equal(pattern.test("Forks and commercial compatibility are allowed."), false);
  }
  assert.equal(forbiddenPublicPhrases.some((pattern) => pattern.test("This is an anti-fork policy.")), true);
  assert.equal(forbiddenPublicPhrases.some((pattern) => pattern.test("Use a private beta ring.")), true);
  assert.equal(forbiddenPublicPhrases.some((pattern) => pattern.test("No commercial use is allowed.")), true);

  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "clawix-canonicity-"));
  fs.writeFileSync(path.join(tmp, "sample.md"), "official and compatible are separate\n");
  assert.match(fs.readFileSync(path.join(tmp, "sample.md"), "utf8"), /official/);
  fs.rmSync(tmp, { recursive: true, force: true });
  console.error("open-source canonicity self-test passed");
}

if (args.has("--self-test")) {
  runSelfTest();
  process.exit(0);
}

for (const [file, snippets] of [
  ["CONSTITUTION.md", [
    "Compatibility is open; official trust is verifiable",
    "Forks, commercial use, source builds, and compatible implementations are legitimate",
  ]],
  ["docs/adr/0020-open-standard-official-trust-mirror.md", [
    "Status: Accepted",
    "Clawix source code and documentation remain under the repository license",
    "`official Clawix` is reserved",
    "`official`, `source`, `community`, and `compatible`",
    "`claw verify`",
  ]],
  ["FORKS.md", [
    "fork, modify, redistribute, sell, or host your own version",
    "Use compatibility language instead of official language",
  ]],
  ["TRADEMARKS.md", [
    "Compatibility language is allowed when true",
    "Official language is reserved",
  ]],
  ["NOTICE", [
    "official app build, update-channel, download, release, documentation",
    "Limited repository use",
  ]],
  ["DCO", [
    "Signed-off-by: Name <email>",
    "not a Contributor License Agreement",
  ]],
  ["CONTRIBUTING.md", [
    "Signed-off-by: Name <email>",
    "ADR 0020",
  ]],
  ["RELEASING.md", [
    "official/source/community/compatible",
    "ADR 0020",
  ]],
  ["README.md", [
    "Official Clawix builds are maintained by upstream",
    "FORKS.md",
  ]],
  ["docs/decision-map.md", [
    "open-standard and official-trust policy",
    "scripts/open_source_canonicity_check.mjs",
  ]],
  ["AGENTS.md", [
    "docs/adr/0020-open-standard-official-trust-mirror.md",
    "MIT-licensed forks, commercial use, source builds, and compatible implementations are legitimate",
  ]],
  ["docs/discoverability.registry.json", [
    "open-standard-official-trust-mirror",
    "open_source_canonicity_check",
  ]],
]) {
  for (const snippet of snippets) requireSnippet(file, snippet);
}

assertOfficialCompatibleSeparation();
assertNoPrivateStrategyLanguage();

if (failed) process.exit(1);
console.error("open-source canonicity check passed");
