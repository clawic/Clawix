#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const rawArgs = process.argv.slice(2);
const args = new Set(rawArgs);
const isSelfTest = process.env.CLAWIX_UI_SKILL_CONTRACT_SELF_TEST === "1";
const simulationFlags = [
  "--simulate-missing-frontmatter",
  "--simulate-wrong-skill-name",
  "--simulate-missing-keywords",
  "--simulate-private-path",
  "--simulate-missing-canon-snippet",
  "--simulate-missing-implementation-guard",
  "--simulate-missing-private-visual-command",
  "--simulate-missing-performance-flow",
  "--simulate-missing-agents-skill",
  "--simulate-missing-sync-skill",
  "--simulate-duplicate-skill-name",
  "--simulate-duplicate-skill-file",
  "--simulate-extra-skill-contract",
];
const allowedFlags = new Set(simulationFlags);
const errors = [];

for (const arg of rawArgs) {
  if (arg.startsWith("--") && !allowedFlags.has(arg)) {
    console.error(`UI skill contract check received unknown flag ${arg}.`);
    process.exit(1);
  }
}

function fail(message) {
  errors.push(message);
}

function read(relativePath) {
  const file = path.join(rootDir, relativePath);
  if (!fs.existsSync(file)) {
    fail(`missing ${relativePath}`);
    return "";
  }
  let content = fs.readFileSync(file, "utf8");
  if (args.has("--simulate-missing-frontmatter") && relativePath === "skills/ui-canon-review/SKILL.md") {
    content = content.replace(/^---\n[\s\S]*?\n---\n\n/, "");
  }
  if (args.has("--simulate-wrong-skill-name") && relativePath === "skills/ui-implementation/SKILL.md") {
    content = content.replace("name: ui-implementation", "name: visual-implementation");
  }
  if (args.has("--simulate-missing-keywords") && relativePath === "skills/visual-regression/SKILL.md") {
    content = content.replace(/\nkeywords: .*\n/, "\n");
  }
  if (args.has("--simulate-private-path") && relativePath === "skills/ui-performance-budget/SKILL.md") {
    content += "\nPrivate baseline: /Users/private/perf-baseline.json\n";
  }
  if (args.has("--simulate-missing-canon-snippet") && relativePath === "skills/ui-canon-review/SKILL.md") {
    content = content.replace("docs/adr/0010-interface-governance.md", "docs/adr/other.md");
  }
  if (args.has("--simulate-missing-implementation-guard") && relativePath === "skills/ui-implementation/SKILL.md") {
    content = content.replace("node scripts/ui_governance_guard.mjs", "node scripts/other_guard.mjs");
  }
  if (args.has("--simulate-missing-private-visual-command") && relativePath === "skills/visual-regression/SKILL.md") {
    content = content.replace("node scripts/ui_private_visual_verify.mjs --require-approved", "node scripts/ui_private_visual_verify.mjs");
  }
  if (args.has("--simulate-missing-performance-flow") && relativePath === "skills/ui-performance-budget/SKILL.md") {
    content = content.replace("sidebar lag", "sidebar responsiveness");
  }
  if (args.has("--simulate-missing-agents-skill") && relativePath === "AGENTS.md") {
    content = content.replace("visual-regression", "visual-check");
  }
  if (args.has("--simulate-missing-sync-skill") && relativePath === "scripts/check-clawjs-skills-sync.mjs") {
    content = content.replaceAll("\"ui-performance-budget\"", "\"ui-performance\"");
  }
  return content;
}

function requireSnippet(file, snippet) {
  const content = read(file);
  if (!content.includes(snippet)) fail(`${file} must include ${snippet}`);
}

function scanForPrivateContent(file) {
  const content = read(file);
  if (/\/Users\/|~\/|file:\/\/|[A-Z]:\\|BEGIN [A-Z ]*PRIVATE KEY|\bAKIA[0-9A-Z]{16}\b|\bsk-[A-Za-z0-9]{20,}\b/.test(content)) {
    fail(`${file} must not contain private paths or secret-like tokens`);
  }
}

function requireFrontmatterName(file, name) {
  const content = read(file);
  if (!content.startsWith("---\n")) fail(`${file} must start with YAML frontmatter`);
  requireSnippet(file, `name: ${name}`);
  requireSnippet(file, "description:");
  requireSnippet(file, "keywords:");
}

function requireUniqueStrings(values, label) {
  const seen = new Set();
  for (const value of values) {
    if (typeof value !== "string" || value.length === 0) {
      fail(`${label} must only include non-empty strings`);
      continue;
    }
    if (seen.has(value)) fail(`${label} duplicates ${value}`);
    seen.add(value);
  }
  return seen;
}

function requireExactStringSet(values, label, expectedValues) {
  const seen = requireUniqueStrings(values, label);
  const expected = new Set(expectedValues);
  for (const value of seen) {
    if (!expected.has(value)) fail(`${label} must not include ${value}`);
  }
  for (const value of expected) {
    if (!seen.has(value)) fail(`${label} must include ${value}`);
  }
  if (seen.size !== expected.size) fail(`${label} must exactly match approved values`);
  return seen;
}

const expectedSkillNames = ["ui-canon-review", "ui-implementation", "visual-regression", "ui-performance-budget"];

const skillContracts = [
  {
    file: "skills/ui-canon-review/SKILL.md",
    name: "ui-canon-review",
    snippets: [
      "docs/adr/0010-interface-governance.md",
      "docs/ui/README.md",
      "docs/ui/pattern-registry/",
      "visual-ui",
      "copy-ui",
      "conceptual proposal",
      "explicit user OK",
    ],
  },
  {
    file: "skills/ui-implementation/SKILL.md",
    name: "ui-implementation",
    snippets: [
      "docs/ui/visible-surfaces.inventory.json",
      "functional-ui",
      "governance/tooling",
      "visual-change-proposal.template.md",
      "Do not change colors, spacing, typography, icons",
      "node scripts/ui_governance_guard.mjs",
    ],
  },
  {
    file: "skills/visual-regression/SKILL.md",
    name: "visual-regression",
    snippets: [
      "node scripts/ui_private_visual_verify.mjs --require-approved",
      "CLAWIX_UI_PRIVATE_BASELINE_ROOT=<private-root>",
      "CLAWIX_UI_PRIVATE_GEOMETRY_ROOT=<private-root>",
      "CLAWIX_UI_PRIVATE_COPY_ROOT=<private-root>",
      "CLAWIX_UI_PRIVATE_DRIFT_ROOT=<private-root>",
      "CLAWIX_UI_PRIVATE_DEBT_AUDIT_ROOT=<private-root>",
      "CLAWIX_UI_PRIVATE_APPROVAL_ROOT=<private-root>",
      "node scripts/ui_private_geometry_verify.mjs --require-approved",
      "node scripts/ui_private_baseline_verify.mjs --require-approved",
      "Private screenshots/baselines stay outside the public repo",
      "do not repair it unless the active model and task",
      "are explicitly visual-authorized",
    ],
  },
  {
    file: "skills/ui-performance-budget/SKILL.md",
    name: "ui-performance-budget",
    snippets: [
      "macos/PERF.md",
      "docs/ui/performance-budgets.registry.json",
      "sidebar lag",
      "chat scroll performance",
      "composer typing latency",
      "dropdown",
      "terminal/sidebar switching",
      "right-sidebar/browser performance",
      "EXTERNAL PENDING",
    ],
  },
];

if (args.has("--simulate-duplicate-skill-name")) {
  skillContracts.push({ ...skillContracts[0], file: "skills/ui-implementation/SKILL.md" });
}
if (args.has("--simulate-duplicate-skill-file")) {
  skillContracts.push({ ...skillContracts[1], name: "ui-implementation-copy" });
}
if (args.has("--simulate-extra-skill-contract")) {
  skillContracts.push({ file: "skills/style-apply/SKILL.md", name: "style-apply", snippets: [] });
}

requireExactStringSet(
  skillContracts.map((contract) => contract.name),
  "UI skill contract names",
  expectedSkillNames,
);
requireUniqueStrings(
  skillContracts.map((contract) => contract.file),
  "UI skill contract files",
);

for (const contract of skillContracts) {
  requireFrontmatterName(contract.file, contract.name);
  scanForPrivateContent(contract.file);
  for (const snippet of contract.snippets) requireSnippet(contract.file, snippet);
}

for (const skillName of expectedSkillNames) {
  requireSnippet("AGENTS.md", skillName);
  requireSnippet("docs/agent-rules/index.md", skillName);
  requireSnippet("scripts/check-clawjs-skills-sync.mjs", `"${skillName}"`);
}

if (errors.length > 0) {
  console.error("UI skill contract check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

if (errors.length === 0 && !isSelfTest && rawArgs.length === 0) {
  const selfTests = [
    ["--unknown-flag", "received unknown flag --unknown-flag"],
    ["--simulate-missing-frontmatter", "skills/ui-canon-review/SKILL.md must start with YAML frontmatter"],
    ["--simulate-wrong-skill-name", "skills/ui-implementation/SKILL.md must include name: ui-implementation"],
    ["--simulate-missing-keywords", "skills/visual-regression/SKILL.md must include keywords:"],
    ["--simulate-private-path", "skills/ui-performance-budget/SKILL.md must not contain private paths or secret-like tokens"],
    ["--simulate-missing-canon-snippet", "skills/ui-canon-review/SKILL.md must include docs/adr/0010-interface-governance.md"],
    ["--simulate-missing-implementation-guard", "skills/ui-implementation/SKILL.md must include node scripts/ui_governance_guard.mjs"],
    [
      "--simulate-missing-private-visual-command",
      "skills/visual-regression/SKILL.md must include node scripts/ui_private_visual_verify.mjs --require-approved",
    ],
    ["--simulate-missing-performance-flow", "skills/ui-performance-budget/SKILL.md must include sidebar lag"],
    ["--simulate-missing-agents-skill", "AGENTS.md must include visual-regression"],
    ["--simulate-missing-sync-skill", "scripts/check-clawjs-skills-sync.mjs must include \"ui-performance-budget\""],
    ["--simulate-duplicate-skill-name", "UI skill contract names duplicates ui-canon-review"],
    ["--simulate-duplicate-skill-file", "UI skill contract files duplicates skills/ui-implementation/SKILL.md"],
    ["--simulate-extra-skill-contract", "UI skill contract names must not include style-apply"],
  ];
  const scriptPath = path.relative(rootDir, new URL(import.meta.url).pathname);
  for (const [flag, expectedOutput] of selfTests) {
    const result = spawnSync(process.execPath, [scriptPath, flag], {
      cwd: rootDir,
      encoding: "utf8",
      env: { ...process.env, CLAWIX_UI_SKILL_CONTRACT_SELF_TEST: "1" },
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status === 0 || !output.includes(expectedOutput)) {
      console.error(`UI skill contract self-test failed for ${flag}.`);
      if (output) console.error(output.trim());
      process.exit(1);
    }
  }
}

console.log(`UI skill contract check passed (${skillContracts.length} skills)`);
