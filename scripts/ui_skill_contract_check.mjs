#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = new Set(process.argv.slice(2));
const errors = [];

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
  requireSnippet("scripts/check-clawjs-skills-sync.mjs", `"${skillName}"`);
}

if (errors.length > 0) {
  console.error("UI skill contract check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI skill contract check passed (${skillContracts.length} skills)`);
