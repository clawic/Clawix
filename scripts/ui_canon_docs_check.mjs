#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const rawArgs = process.argv.slice(2);
const args = new Set(rawArgs);
const isSelfTest = process.env.CLAWIX_UI_CANON_DOCS_SELF_TEST === "1";
const errors = [];
const simulationFlags = [
  "--simulate-missing-required-doc",
  "--simulate-adr-missing-docs-ui",
  "--simulate-style-missing-visual-model-allowlist",
  "--simulate-standards-missing-protected-surfaces",
  "--simulate-perf-missing-critical-flow",
  "--simulate-macos-perf-missing-baseline-approval",
  "--simulate-readme-missing-private-visual-verify",
  "--simulate-readme-missing-pattern-registry",
  "--simulate-readme-missing-failure-diagnostics",
  "--simulate-decision-map-missing-interface-governance",
];
const allowedFlags = new Set(simulationFlags);

function fail(message) {
  errors.push(message);
}

for (const arg of rawArgs) {
  if (arg.startsWith("--") && !allowedFlags.has(arg)) {
    console.error(`UI canon docs check received unknown flag ${arg}.`);
    process.exit(1);
  }
}

function read(relativePath) {
  if (args.has("--simulate-missing-required-doc") && relativePath === "docs/ui/README.md") {
    fail(`missing ${relativePath}`);
    return "";
  }
  const file = path.join(rootDir, relativePath);
  if (!fs.existsSync(file)) {
    fail(`missing ${relativePath}`);
    return "";
  }
  let content = fs.readFileSync(file, "utf8");
  if (args.has("--simulate-adr-missing-docs-ui") && relativePath === "docs/adr/0010-interface-governance.md") {
    content = content.replaceAll("docs/ui/", "docs/interface/");
  }
  if (args.has("--simulate-style-missing-visual-model-allowlist") && relativePath === "STYLE.md") {
    content = content.replaceAll("visual-model-allowlist.manifest.json", "visual-model-policy.manifest.json");
  }
  if (args.has("--simulate-standards-missing-protected-surfaces") && relativePath === "STANDARDS.md") {
    content = content.replaceAll("protected-surfaces.registry.json", "surface-freezes.registry.json");
  }
  if (args.has("--simulate-perf-missing-critical-flow") && relativePath === "PERF.md") {
    content = content.replaceAll("right-sidebar/browser use", "right-sidebar use");
  }
  if (args.has("--simulate-macos-perf-missing-baseline-approval") && relativePath === "macos/PERF.md") {
    content = content.replaceAll("baseline approval", "baseline review");
  }
  if (args.has("--simulate-readme-missing-private-visual-verify") && relativePath === "docs/ui/README.md") {
    content = content.replaceAll("ui_private_visual_verify.mjs --require-approved", "ui_private_visual_verify.mjs");
  }
  if (args.has("--simulate-readme-missing-pattern-registry") && relativePath === "docs/ui/README.md") {
    content = content.replaceAll("pattern-registry/", "pattern-library/");
  }
  if (args.has("--simulate-readme-missing-failure-diagnostics") && relativePath === "docs/ui/README.md") {
    content = content.replaceAll("scripts/ui_visual_guard_failure_check.mjs", "scripts/ui_visual_guard_check.mjs");
  }
  if (args.has("--simulate-decision-map-missing-interface-governance") && relativePath === "docs/decision-map.md") {
    content = content.replaceAll("## Interface governance", "## Interface checks");
  }
  return content;
}

function requireSnippet(relativePath, snippet) {
  const content = read(relativePath);
  if (!content.includes(snippet)) {
    fail(`${relativePath} must mention ${snippet}`);
  }
}

const requiredDocs = [
  "docs/adr/0010-interface-governance.md",
  "docs/decision-map.md",
  "STYLE.md",
  "STANDARDS.md",
  "PERF.md",
  "macos/PERF.md",
  "docs/ui/README.md",
];

for (const doc of requiredDocs) read(doc);

for (const snippet of [
  "docs/ui/",
  "visual-ui",
  "copy-ui",
  "visual-model-allowlist.manifest.json",
]) {
  requireSnippet("docs/adr/0010-interface-governance.md", snippet);
  requireSnippet("STYLE.md", snippet);
}

for (const snippet of [
  "pattern registry",
  "geometry",
  "copy",
  "visual mutation permissions",
  "visual-model-allowlist.manifest.json",
  "visual-change-scopes.manifest.json",
  "protected-surfaces.registry.json",
]) {
  requireSnippet("STANDARDS.md", snippet);
}

for (const snippet of [
  "docs/ui/performance-budgets.registry.json",
  "docs/ui/private-baselines.manifest.json",
  "ui_performance_budget_check.mjs",
  "ui_private_performance_budget_verify.mjs",
  "sidebar hover/click/expand",
  "chat scroll",
  "composer typing",
  "dropdown open",
  "terminal/sidebar switch",
  "right-sidebar/browser use",
]) {
  requireSnippet("PERF.md", snippet);
}

for (const snippet of [
  "../docs/ui/performance-budgets.registry.json",
  "../docs/ui/private-baselines.manifest.json",
  "baseline approval",
]) {
  requireSnippet("macos/PERF.md", snippet);
}

for (const snippet of [
  "docs/ui/debt-baseline.*",
  "pattern-registry/",
  "visible-surfaces.inventory.json",
  "visual-change-detectors.manifest.json",
  "visual-model-allowlist.manifest.json",
  "visual-change-scopes.manifest.json",
  "debt.baseline.json",
  "debt-baseline.manifest.json",
  "protected-surfaces.registry.json",
  "inspiration/",
  "performance-budgets.registry.json",
  "private-baselines.manifest.json",
  "scripts/ui_pattern_mutation_guard.mjs",
  "scripts/ui_visual_guard_failure_check.mjs",
  "private-visual-validation.manifest.json",
  "visual-change-proposal.template.md",
  "ui_private_approval_verify.mjs --require-approved",
  "ui_private_visual_verify.mjs --require-approved",
]) {
  requireSnippet("docs/ui/README.md", snippet);
}

for (const snippet of [
  "## Interface governance",
  "pattern registry plus references and contracts",
  "Existing visual drift is frozen in a debt baseline",
  "Approved visual surfaces are protected/frozen",
  "visual/copy/layout decisions",
  "performance-budgets.registry.json",
]) {
  requireSnippet("docs/decision-map.md", snippet);
}

if (errors.length === 0 && !isSelfTest && args.size === 0) {
  for (const [flag, expectedOutput] of [
    ["--simulate-missing-required-doc", "missing docs/ui/README.md"],
    ["--simulate-adr-missing-docs-ui", "docs/adr/0010-interface-governance.md must mention docs/ui/"],
    ["--simulate-style-missing-visual-model-allowlist", "STYLE.md must mention visual-model-allowlist.manifest.json"],
    ["--simulate-standards-missing-protected-surfaces", "STANDARDS.md must mention protected-surfaces.registry.json"],
    ["--simulate-perf-missing-critical-flow", "PERF.md must mention right-sidebar/browser use"],
    ["--simulate-macos-perf-missing-baseline-approval", "macos/PERF.md must mention baseline approval"],
    ["--simulate-readme-missing-private-visual-verify", "docs/ui/README.md must mention ui_private_visual_verify.mjs --require-approved"],
    ["--simulate-readme-missing-pattern-registry", "docs/ui/README.md must mention pattern-registry/"],
    ["--simulate-readme-missing-failure-diagnostics", "docs/ui/README.md must mention scripts/ui_visual_guard_failure_check.mjs"],
    ["--simulate-decision-map-missing-interface-governance", "docs/decision-map.md must mention ## Interface governance"],
  ]) {
    const result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, flag], {
      cwd: rootDir,
      env: { ...process.env, CLAWIX_UI_CANON_DOCS_SELF_TEST: "1" },
      encoding: "utf8",
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status === 0) {
      fail(`self-test ${flag} must fail when required canon doc evidence is removed`);
      continue;
    }
    if (!output.includes(expectedOutput)) {
      fail(`self-test ${flag} output must include ${expectedOutput}`);
    }
  }
}

if (errors.length > 0) {
  console.error("UI canon docs check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI canon docs check passed (${requiredDocs.length} docs)`);
