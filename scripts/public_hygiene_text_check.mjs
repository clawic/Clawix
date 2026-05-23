#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const args = new Set(process.argv.slice(2));

const allowedSyntheticUsernames = new Set(["alice", "demo", "example", "me", "person", "private", "tester"]);

const textExtensions = new Set([
  ".c",
  ".cc",
  ".cpp",
  ".cs",
  ".css",
  ".h",
  ".html",
  ".java",
  ".js",
  ".json",
  ".jsx",
  ".kt",
  ".m",
  ".md",
  ".mjs",
  ".mm",
  ".plist",
  ".ps1",
  ".py",
  ".rs",
  ".sh",
  ".swift",
  ".toml",
  ".ts",
  ".tsx",
  ".txt",
  ".xml",
  ".xaml",
  ".xcstrings",
  ".yml",
  ".yaml",
]);

const ignoredPathParts = new Set([
  ".build",
  ".build-test",
  ".git",
  ".next",
  "artifacts",
  "build",
  "dist",
  "node_modules",
  "test-results",
]);

const selfFiles = new Set([
  "scripts/public_hygiene_text_check.mjs",
  "macos/scripts/public_hygiene_check.sh",
  "linux/scripts/public_hygiene_check.sh",
  "windows/scripts/public_hygiene_check.ps1",
  "scripts/privacy-redaction.mjs",
  "scripts/privacy_artifact_safety_check.mjs",
]);

const patterns = [
  {
    id: "private-user-path",
    description: "private local user path",
    regex: /(?:file:\/\/)?\/Users\/[A-Za-z0-9._-]+(?=\/|\b)/g,
    allow(match) {
      const username = match.match(/\/Users\/([^/\s"'`<>]+)/u)?.[1] ?? "";
      return allowedSyntheticUsernames.has(username);
    },
  },
  {
    id: "codex-private-path",
    description: "private Codex session or goal path",
    regex: /(?:~|\/[A-Za-z0-9._-]+|\/Users\/[A-Za-z0-9._-]+)\/\.codex\/(?:sessions|goals)\b/g,
  },
  {
    id: "codex-rollout-session-id",
    description: "private Codex rollout session identifier",
    regex: /\brollout-\d{4}-\d{2}-\d{2}T\d{2}[-:]\d{2}[-:]\d{2}(?:-\d{3})?-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jsonl\b/gi,
  },
  {
    id: "private-source-reference",
    description: "private source conversation or plan reference",
    regex: /\b(?:Source conversation|sourceConversationId|conversationId|sourcePlanId|planId|Reference plan item|Binding plan item|Plan item|source session|sourceSession)[^\n]{0,160}\b019e[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(?:-plan)?\b/gi,
  },
  {
    id: "contextual-team-id",
    description: "private Team ID in signing or release context",
    regex: /\b(?:DEVELOPMENT_TEAM|TEAM_ID|team_id|teamId|Team ID|team identifier)\b[^\n]{0,60}\b[A-Z0-9]{10}\b/g,
  },
  {
    id: "private-bundle-id",
    description: "private bundle identifier in app or release context",
    regex: /\b(?:bundle_id|bundleId|bundle identifier|withBundleIdentifier)\b[^\n]{0,80}\bcom\.(?:claw|clawix)(?:\.[A-Za-z0-9_-]+)+\b/gi,
  },
  {
    id: "signing-identity",
    description: "private Apple signing identity",
    regex: /\b(?:Apple Development|Apple Distribution|Developer ID Application):[^\n"']+/g,
    allow: (match) => /:\s*Example\b/u.test(match),
  },
  {
    id: "secret-looking-literal",
    description: "secret-looking literal",
    regex: /\b(?:sk-[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|gh[pousr]_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16})\b/g,
  },
  {
    id: "private-key",
    description: "private key material",
    regex: /-----BEGIN [A-Z ]+PRIVATE KEY-----/g,
    allow: (match) => match === "-----BEGIN TEST PRIVATE KEY-----",
  },
  {
    id: "release-artifact-output-reference",
    description: "private release output reference",
    regex: /(^|[/"'`\s])release-output([/"'`\s]|$)/g,
  },
];

function isTextFile(filePath) {
  return textExtensions.has(path.extname(filePath).toLowerCase()) || ["AGENTS.md", "CLAUDE.md", "README.md"].includes(path.basename(filePath));
}

function isIgnored(filePath) {
  if (selfFiles.has(filePath)) return true;
  return filePath.split(/[\\/]/u).some((part) => ignoredPathParts.has(part));
}

export function scanText(text, filePath = "<input>") {
  const findings = [];
  for (const pattern of patterns) {
    pattern.regex.lastIndex = 0;
    for (const match of text.matchAll(pattern.regex)) {
      if (pattern.allow?.(match[0], text)) continue;
      const index = match.index ?? 0;
      const line = text.slice(0, index).split(/\r?\n/u).length;
      findings.push({ filePath, line, rule: pattern.id, description: pattern.description });
    }
  }
  return findings;
}

function repoFiles() {
  return execFileSync("git", ["ls-files", "--cached", "--modified", "--others", "--exclude-standard"], {
    cwd: repoRoot,
    encoding: "utf8",
  })
    .split("\n")
    .map((entry) => entry.trim())
    .filter(Boolean)
    .filter((entry) => !isIgnored(entry))
    .filter(isTextFile);
}

export function scanRepository() {
  const findings = [];
  for (const relativePath of repoFiles()) {
    const absolutePath = path.join(repoRoot, relativePath);
    let text = "";
    try {
      text = fs.readFileSync(absolutePath, "utf8");
    } catch {
      continue;
    }
    findings.push(...scanText(text, relativePath));
  }
  return findings;
}

function selfTest() {
  const privatePath = ["/Users", "trabajo", "Desktop", "private"].join("/");
  const codexPrivatePath = ["~", ".codex", "sessions", "session.jsonl"].join("/");
  const privateSessionId = ["019e2b2c", "ec6d", "7ea0", "943f", "4cad5b2ad6a1"].join("-");
  const privateSourceId = ["019e3b2e", "3f4a", "7753", "a2ce", "c92fce7c4436"].join("-");
  const privatePlanId = `${["019e3b8a", "fab7", "75e0", "8a23", "a49524afe727"].join("-")}-plan`;
  const privateKeyMarker = ["-----BEGIN RSA", "PRIVATE KEY-----"].join(" ");
  const privateDevelopmentTeam = ["DEVELOPMENT_TEAM", "ABCDE12345"].join(" = ");
  const privateBundleId = ["bundle_id=com", "clawix", "private"].join(".");
  const privateSigningIdentity = ["Apple Distribution", "Private Org (ABCDE12345)"].join(": ");
  const privateText = [
    privatePath,
    codexPrivatePath,
    `rollout-2026-05-15T12-27-04-${privateSessionId}.jsonl`,
    `Source conversation: \`${privateSourceId}\``,
    `Reference plan item: \`${privatePlanId}\``,
    privateDevelopmentTeam,
    privateBundleId,
    privateSigningIdentity,
    "sk-" + "a".repeat(24),
    privateKeyMarker,
    "release-output",
  ].join("\n");
  const safeText = [
    "/Users/example/project",
    "/Users/demo/.claw",
    "/Users/me/code/foo",
    "/Users/tester/project",
    "bundle_id=com.example.app",
    "Developer ID Application: Example",
    "~/.codex is external read-only",
  ].join("\n");
  const privateFindings = scanText(privateText);
  const safeFindings = scanText(safeText);
  const requiredRules = new Set(patterns.map((pattern) => pattern.id));
  for (const finding of privateFindings) requiredRules.delete(finding.rule);
  if (requiredRules.size > 0) {
    throw new Error(`self-test did not exercise rules: ${[...requiredRules].join(", ")}`);
  }
  if (safeFindings.length > 0) {
    throw new Error(`self-test flagged safe placeholders: ${safeFindings.map((finding) => finding.rule).join(", ")}`);
  }
}

if (args.has("--self-test")) {
  selfTest();
  console.log("public hygiene text self-test passed");
} else {
  const findings = scanRepository();
  if (findings.length > 0) {
    console.error("public hygiene text check failed. Replace private material with public placeholders:");
    for (const finding of findings) {
      console.error(`${finding.filePath}:${finding.line} ${finding.rule}`);
    }
    process.exit(1);
  }
  console.log("public hygiene text check passed");
}
