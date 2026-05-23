#!/usr/bin/env node
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const today = new Date().toISOString().slice(0, 10);
const args = new Set(process.argv.slice(2));
const severityValues = new Set(["P0", "P1", "P2", "P3"]);
const releaseEffectModes = new Set(["blocks_release", "blocks_growth", "report_only"]);
const releaseTargets = new Set(["macos-release", "ios-release", "linux-release", "windows-release", "web-release", "changed-work"]);

const baselineSources = [
  { path: "docs/boundedness-baseline.json", selectors: ["entries"] },
  { path: "docs/code-hygiene-baseline.json", selectors: ["entries"] },
  { path: "docs/conceptual-vocabulary-baseline.json", selectors: ["topLevel"] },
  { path: "docs/discoverability-baseline.json", selectors: ["topLevel", "entries"] },
  { path: "docs/hot-path-baseline.json", selectors: ["entries"] },
  { path: "docs/source-size-baseline.json", selectors: ["files"] },
  { path: "docs/surface-evidence-projection-baseline.json", selectors: ["entries"] },
  { path: "docs/surface-narrative-clawix-baseline.json", selectors: ["entries"] },
  { path: "docs/surface-resource-contract-clawix-baseline.json", selectors: ["entries"] },
  { path: "docs/ui/debt.baseline.json", selectors: ["entries"] },
  { path: "docs/governance/no-irreversible-data-loss/baseline.json", selectors: ["entries", "monitoredKeywordBaselines"] },
];

function readJson(relativePath, baseDir = rootDir) {
  return JSON.parse(fs.readFileSync(path.join(baseDir, relativePath), "utf8"));
}

function hasText(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function isRecord(value) {
  return !!value && typeof value === "object" && !Array.isArray(value);
}

function requireNumber(value, label, failures) {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
    failures.push(`${label} must be a non-negative number`);
    return 0;
  }
  return value;
}

function entryLabel(sourcePath, selector, key, index) {
  return `${sourcePath}.${selector}${key ? `.${key}` : `[${index}]`}`;
}

function collectDebtEntries(sourcePath, json, selectors, failures) {
  const entries = [];
  for (const selector of selectors) {
    if (selector === "topLevel") {
      entries.push({ label: `${sourcePath}.debtControl`, value: json, debtControl: json.debtControl });
      continue;
    }
    if (selector === "entries") {
      const rows = json.entries ?? [];
      if (!Array.isArray(rows)) {
        failures.push(`${sourcePath}.entries must be an array`);
        continue;
      }
      rows.forEach((value, index) => entries.push({ label: entryLabel(sourcePath, "entries", "", index), value, debtControl: value?.debtControl }));
      continue;
    }
    if (selector === "files") {
      if (!isRecord(json.files)) {
        failures.push(`${sourcePath}.files must be an object`);
        continue;
      }
      for (const [key, value] of Object.entries(json.files)) {
        entries.push({ label: entryLabel(sourcePath, "files", key, 0), value, debtControl: isRecord(value) ? value.debtControl : undefined });
      }
      continue;
    }
    if (selector === "monitoredKeywordBaselines") {
      const rows = json.monitoredKeywordBaselines ?? [];
      if (!Array.isArray(rows)) {
        failures.push(`${sourcePath}.monitoredKeywordBaselines must be an array`);
        continue;
      }
      rows.forEach((value, index) => entries.push({ label: entryLabel(sourcePath, "monitoredKeywordBaselines", "", index), value, debtControl: value?.debtControl }));
    }
  }
  return entries;
}

function validateDebtControl(control, label, failures, currentDate = today) {
  if (!isRecord(control)) {
    failures.push(`${label} is missing debtControl`);
    return;
  }
  for (const field of ["ownerArea", "expiresAt", "severity"]) {
    if (!hasText(control[field])) failures.push(`${label}.debtControl.${field} must be a non-empty string`);
  }
  if (hasText(control.expiresAt) && !/^\d{4}-\d{2}-\d{2}$/.test(control.expiresAt)) {
    failures.push(`${label}.debtControl.expiresAt must be YYYY-MM-DD`);
  }
  if (hasText(control.expiresAt) && control.expiresAt < currentDate) {
    failures.push(`${label}.debtControl expired on ${control.expiresAt}`);
  }
  if (hasText(control.severity) && !severityValues.has(control.severity)) {
    failures.push(`${label}.debtControl.severity must be P0, P1, P2, or P3`);
  }

  const budget = control.budget;
  if (!isRecord(budget)) {
    failures.push(`${label}.debtControl.budget must be an object`);
  } else {
    for (const field of ["metric", "unit", "cadence"]) {
      if (!hasText(budget[field])) failures.push(`${label}.debtControl.budget.${field} must be a non-empty string`);
    }
    const current = requireNumber(budget.current, `${label}.debtControl.budget.current`, failures);
    const maxAllowed = requireNumber(budget.maxAllowed, `${label}.debtControl.budget.maxAllowed`, failures);
    const nextMaxAllowed = requireNumber(budget.nextMaxAllowed, `${label}.debtControl.budget.nextMaxAllowed`, failures);
    requireNumber(budget.target, `${label}.debtControl.budget.target`, failures);
    if (current > maxAllowed) failures.push(`${label}.debtControl.budget.current must not exceed maxAllowed`);
    if (nextMaxAllowed >= maxAllowed) failures.push(`${label}.debtControl.budget.nextMaxAllowed must be lower than maxAllowed`);
  }

  const releaseEffect = control.releaseEffect;
  if (!isRecord(releaseEffect)) {
    failures.push(`${label}.debtControl.releaseEffect must be an object`);
  } else {
    for (const field of ["mode", "gate", "reason"]) {
      if (!hasText(releaseEffect[field])) failures.push(`${label}.debtControl.releaseEffect.${field} must be a non-empty string`);
    }
    if (hasText(releaseEffect.mode) && !releaseEffectModes.has(releaseEffect.mode)) {
      failures.push(`${label}.debtControl.releaseEffect.mode must be blocks_release, blocks_growth, or report_only`);
    }
    if (!Array.isArray(releaseEffect.targets) || !releaseEffect.targets.every(hasText)) {
      failures.push(`${label}.debtControl.releaseEffect.targets must be an array of non-empty strings`);
    } else {
      for (const target of releaseEffect.targets) {
        if (!releaseTargets.has(target)) failures.push(`${label}.debtControl.releaseEffect.targets has unsupported target ${target}`);
      }
    }
    if ((control.severity === "P0" || control.severity === "P1") && !["blocks_release", "blocks_growth"].includes(releaseEffect.mode)) {
      failures.push(`${label}.debtControl P0/P1 entries must block release or growth`);
    }
    if (releaseEffect.mode === "blocks_release" && (!Array.isArray(releaseEffect.targets) || releaseEffect.targets.length === 0)) {
      failures.push(`${label}.debtControl blocks_release entries must name release targets`);
    }
  }
}

function validateRoot(baseDir = rootDir, currentDate = today) {
  const failures = [];
  let checked = 0;
  for (const source of baselineSources) {
    const absolutePath = path.join(baseDir, source.path);
    if (!fs.existsSync(absolutePath)) {
      failures.push(`missing baseline source ${source.path}`);
      continue;
    }
    const json = readJson(source.path, baseDir);
    const entries = collectDebtEntries(source.path, json, source.selectors, failures);
    for (const entry of entries) {
      checked += 1;
      validateDebtControl(entry.debtControl, entry.label, failures, currentDate);
    }
  }
  if (checked === 0) failures.push("no baseline debtControl entries were checked");
  return { checked, failures };
}

function runSelfTest() {
  const valid = {
    ownerArea: "test",
    expiresAt: "2099-01-01",
    severity: "P1",
    budget: {
      metric: "self_test_debt",
      unit: "item",
      current: 2,
      maxAllowed: 2,
      nextMaxAllowed: 1,
      target: 0,
      cadence: "release",
    },
    releaseEffect: {
      mode: "blocks_growth",
      targets: ["changed-work"],
      gate: "node scripts/debt_control_baseline_check.mjs",
      reason: "Self-test debt must shrink.",
    },
  };
  const failures = [];
  validateDebtControl(valid, "self.valid", failures, "2026-05-21");
  assert.deepEqual(failures, []);

  const flatBudgetFailures = [];
  validateDebtControl({
    ...valid,
    budget: { ...valid.budget, nextMaxAllowed: 2 },
  }, "self.flat", flatBudgetFailures, "2026-05-21");
  assert.match(flatBudgetFailures.join("\n"), /nextMaxAllowed must be lower/);

  const reportOnlyFailures = [];
  validateDebtControl({
    ...valid,
    releaseEffect: { ...valid.releaseEffect, mode: "report_only" },
  }, "self.reportOnly", reportOnlyFailures, "2026-05-21");
  assert.match(reportOnlyFailures.join("\n"), /P0\/P1 entries must block release or growth/);
}

if (args.has("--self-test")) {
  runSelfTest();
  console.log("debt control baseline check self-test passed");
  process.exit(0);
}

const result = validateRoot();
if (args.has("--json")) {
  console.log(JSON.stringify({ ok: result.failures.length === 0, checked: result.checked, failures: result.failures }, null, 2));
}
if (result.failures.length > 0) {
  if (!args.has("--json")) {
    console.error("debt control baseline check failed:");
    for (const failure of result.failures) console.error(`- ${failure}`);
  }
  process.exit(1);
}

if (!args.has("--json")) console.log(`debt control baseline check passed (${result.checked} entries)`);
