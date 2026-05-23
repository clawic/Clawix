#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";
import os from "node:os";
import { fileURLToPath } from "node:url";

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const canonical = path.resolve(rootDir, "../../clawjs/scripts/no-irreversible-data-loss-check.mjs");
const discoveryTerms = "Clawix provider hard delete exact human approval guard";
const sourceActionsPath = "docs/governance/no-irreversible-data-loss/source-actions.json";

const expectedClasses = new Set([
  "recoverable",
  "snapshot_recoverable",
  "rebuildable",
  "external_recoverable",
  "irreversible_external_requires_exact_human_approval",
  "forbidden_for_agents",
]);

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function escapeRegex(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function compileMatcher(entry, field) {
  const source = entry[field];
  if (!source) return null;
  return new RegExp(source, "u");
}

function walkFiles(dir, extensions, excludePatterns, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const fullPath = path.join(dir, entry.name);
    const normalized = fullPath.split(path.sep).join("/");
    if (excludePatterns.some((pattern) => pattern.test(normalized))) continue;
    if (entry.isDirectory()) {
      walkFiles(fullPath, extensions, excludePatterns, out);
    } else if (extensions.includes(path.extname(entry.name))) {
      out.push(fullPath);
    }
  }
  return out;
}

function matchPattern(pattern, relativePath, line) {
  const pathMatcher = pattern.path ? new RegExp(`^${escapeRegex(pattern.path)}$`, "u") : compileMatcher(pattern, "pathPattern");
  const lineMatcher = pattern.line ? new RegExp(escapeRegex(pattern.line), "u") : compileMatcher(pattern, "linePattern");
  return (!pathMatcher || pathMatcher.test(relativePath)) && (!lineMatcher || lineMatcher.test(line));
}

function collectSourceHits(root, config) {
  const extensions = config.extensions ?? [];
  const excludePatterns = (config.excludePathPatterns ?? []).map((pattern) => new RegExp(pattern, "u"));
  const keywordPattern = new RegExp(config.keywordPattern, "u");
  const hits = [];
  for (const rootPath of config.roots ?? []) {
    const absoluteRoot = path.join(root, rootPath);
    for (const filePath of walkFiles(absoluteRoot, extensions, excludePatterns)) {
      const relativePath = path.relative(root, filePath).split(path.sep).join("/");
      const lines = fs.readFileSync(filePath, "utf8").split(/\r?\n/u);
      lines.forEach((line, index) => {
        if (keywordPattern.test(line)) {
          hits.push({ path: relativePath, line: index + 1, text: line.trim() });
        }
      });
    }
  }
  return hits;
}

function validateSourceActions(root, options = {}) {
  const errors = [];
  const manifestPath = path.join(root, sourceActionsPath);
  if (!fs.existsSync(manifestPath)) return [`missing ${sourceActionsPath}`];

  const manifest = readJson(manifestPath);
  if (manifest.schemaVersion !== 1) errors.push(`${sourceActionsPath} schemaVersion must be 1`);
  if (!manifest.sourceScan?.keywordPattern) errors.push(`${sourceActionsPath} must declare sourceScan.keywordPattern`);

  const actions = manifest.classifiedActions ?? [];
  const ignored = manifest.ignoredMatches ?? [];
  const actionIds = new Set();
  const today = new Date().toISOString().slice(0, 10);
  for (const action of actions) {
    if (!action.id) errors.push("classified action missing id");
    if (action.id && actionIds.has(action.id)) errors.push(`duplicate classified action ${action.id}`);
    if (action.id) actionIds.add(action.id);
    if (!expectedClasses.has(action.class)) errors.push(`classified action ${action.id ?? "<missing>"} has invalid class ${action.class}`);
    if (!action.policyId) errors.push(`classified action ${action.id} missing policyId`);
    if (!Array.isArray(action.targets) || action.targets.length === 0) errors.push(`classified action ${action.id} missing targets`);
    if (!["verified", "baseline_gap", "external_pending"].includes(action.status)) errors.push(`classified action ${action.id} has invalid status`);
    if (!action.confirmation) errors.push(`classified action ${action.id} missing confirmation`);
    if (!Array.isArray(action.recoveryOrReport) || action.recoveryOrReport.length === 0) {
      errors.push(`classified action ${action.id} missing recoveryOrReport`);
    }
    if (!Array.isArray(action.sourcePatterns) || action.sourcePatterns.length === 0) {
      errors.push(`classified action ${action.id} missing sourcePatterns`);
    }
    if (action.status === "verified" && /missing|lacks|not verified/i.test(action.confirmation)) {
      errors.push(`classified action ${action.id} cannot be verified with missing confirmation evidence`);
    }
    if (action.class === "irreversible_external_requires_exact_human_approval" && action.status === "verified" && !/exact|confirm|alert|human/i.test(action.confirmation)) {
      errors.push(`classified action ${action.id} needs exact human approval evidence`);
    }
    if (action.status === "baseline_gap") {
      if (!action.debt?.expiresAt || !action.debt?.repair) errors.push(`baseline gap ${action.id} missing debt expiry/repair`);
      else if (action.debt.expiresAt < today) errors.push(`baseline gap ${action.id} expired on ${action.debt.expiresAt}`);
    }
  }

  const hits = collectSourceHits(root, manifest.sourceScan ?? {});
  const matchedActionIds = new Set();
  const unmatched = [];
  for (const hit of hits) {
    const ignoredMatch = ignored.find((entry) => matchPattern(entry, hit.path, hit.text));
    if (ignoredMatch) continue;
    const matchedActions = actions.filter((candidate) => (candidate.sourcePatterns ?? []).some((pattern) => matchPattern(pattern, hit.path, hit.text)));
    if (matchedActions.length > 0) {
      for (const action of matchedActions) matchedActionIds.add(action.id);
    } else {
      unmatched.push(hit);
    }
  }

  for (const action of actions) {
    if (action.required === false) continue;
    if (!matchedActionIds.has(action.id)) {
      errors.push(`classified action ${action.id} did not match any source scan hit`);
    }
  }
  for (const hit of unmatched.slice(0, 50)) {
    errors.push(`unclassified destructive/data-moving source hit: ${hit.path}:${hit.line}: ${hit.text}`);
  }
  if (unmatched.length > 50) {
    errors.push(`and ${unmatched.length - 50} more unclassified destructive/data-moving source hits`);
  }

  if (options.returnStats) {
    return { errors, stats: { hits: hits.length, actions: actions.length, ignored: ignored.length, unmatched: unmatched.length } };
  }
  return errors;
}

function runLocalSelfTest() {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "clawix-no-data-loss-source."));
  fs.mkdirSync(path.join(temp, "docs/governance/no-irreversible-data-loss"), { recursive: true });
  fs.mkdirSync(path.join(temp, "src"), { recursive: true });
  const base = {
    schemaVersion: 1,
    sourceScan: {
      roots: ["src"],
      extensions: [".swift"],
      excludePathPatterns: [],
      keywordPattern: "\\b(delete|trash)\\b",
    },
    ignoredMatches: [],
    classifiedActions: [
      {
        id: "trash-note",
        class: "recoverable",
        policyId: "host-delete-archive-first",
        targets: ["local-delete"],
        status: "verified",
        confirmation: "ordinary_ui_action",
        recoveryOrReport: ["trash list"],
        sourcePatterns: [{ pathPattern: "src/Notes.swift", linePattern: "func trash\\(" }],
      },
    ],
  };
  fs.writeFileSync(path.join(temp, sourceActionsPath), JSON.stringify(base, null, 2));
  fs.writeFileSync(path.join(temp, "src/Notes.swift"), "func trash() {}\n");
  assert.deepEqual(validateSourceActions(temp), []);

  fs.writeFileSync(path.join(temp, "src/Notes.swift"), "func trash() {}\nfunc delete() {}\n");
  assert(validateSourceActions(temp).some((error) => error.includes("unclassified destructive/data-moving source hit")));

  base.classifiedActions[0].status = "baseline_gap";
  base.classifiedActions[0].debt = { expiresAt: "2000-01-01", repair: "repair" };
  fs.writeFileSync(path.join(temp, sourceActionsPath), JSON.stringify(base, null, 2));
  fs.writeFileSync(path.join(temp, "src/Notes.swift"), "func trash() {}\n");
  assert(validateSourceActions(temp).some((error) => error.includes("expired")));
}

if (!fs.existsSync(canonical)) {
  console.error(`ClawJS canonical no irreversible data loss checker not found: ${canonical}`);
  process.exit(1);
}

const result = spawnSync(process.execPath, [canonical, "--root", rootDir, "--profile", "clawix", ...process.argv.slice(2)], {
  cwd: rootDir,
  stdio: "inherit",
  env: process.env,
});

if ((result.status ?? 1) !== 0) {
  process.exitCode = result.status ?? 1;
} else {
  try {
    if (process.argv.includes("--self-test")) {
      runLocalSelfTest();
      console.log("Clawix destructive source classification self-test passed");
    } else {
      const { errors, stats } = validateSourceActions(rootDir, { returnStats: true });
      if (errors.length > 0) {
        console.error("Clawix destructive source classification check failed:");
        for (const error of errors) console.error(`- ${error}`);
        process.exitCode = 1;
      } else {
        console.log(`Clawix destructive source classification check passed (${stats.hits} hits, ${stats.actions} action classes)`);
      }
    }
  } catch (error) {
    console.error("Clawix destructive source classification check crashed:");
    console.error(error);
    console.error(`Discovery terms: ${discoveryTerms}`);
    process.exitCode = 1;
  }
}
