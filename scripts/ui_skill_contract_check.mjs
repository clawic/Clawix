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

const skillNames = new Set();
for (const contract of skillContracts) {
  if (skillNames.has(contract.name)) fail(`skill contract name ${contract.name} must be unique`);
  skillNames.add(contract.name);
  requireFrontmatterName(contract.file, contract.name);
  scanForPrivateContent(contract.file);
  for (const snippet of contract.snippets) requireSnippet(contract.file, snippet);
}

if (errors.length > 0) {
  console.error("UI skill contract check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI skill contract check passed (${skillContracts.length} skills)`);
