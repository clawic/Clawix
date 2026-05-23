#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const rawArgs = process.argv.slice(2);
const args = new Set(rawArgs);
const errors = [];
const isSelfTest = process.env.CLAWIX_UI_RELEASE_GATE_SELF_TEST === "1";
const simulationFlags = [
  "--simulate-wrong-external-pending-code",
  "--simulate-private-command-mismatch",
  "--simulate-missing-required-lane",
  "--simulate-missing-release-requirement",
  "--simulate-missing-visual-diff",
  "--simulate-private-roots-allowed",
  "--simulate-missing-diff-base-consumer",
  "--simulate-unlisted-coverage-script",
  "--simulate-undeclared-public-check-coverage",
  "--simulate-required-script-uncovered",
  "--simulate-missing-config-public-check",
  "--simulate-missing-test-script-run",
  "--simulate-missing-workflow-run",
  "--simulate-private-root-in-workflow",
];
const allowedFlags = new Set(simulationFlags);

function fail(message) {
  errors.push(message);
}

for (const arg of rawArgs) {
  if (arg.startsWith("--") && !allowedFlags.has(arg)) {
    console.error(`UI release gate check received unknown flag ${arg}.`);
    process.exit(1);
  }
}

function read(relativePath) {
  const file = path.join(rootDir, relativePath);
  if (!fs.existsSync(file)) {
    fail(`missing ${relativePath}`);
    return "";
  }
  return fs.readFileSync(file, "utf8");
}

function readJson(relativePath) {
  const content = read(relativePath);
  if (!content) return null;
  try {
    return JSON.parse(content);
  } catch (error) {
    fail(`${relativePath} is not valid JSON: ${error.message}`);
    return null;
  }
}

function requireFields(object, label, fields) {
  if (!object) return;
  for (const field of fields) {
    if (object[field] === undefined || object[field] === null || object[field] === "") {
      fail(`${label} is missing ${field}`);
    }
  }
}

function requireArray(object, label, field, { nonEmpty = true } = {}) {
  const value = object?.[field];
  if (!Array.isArray(value)) {
    fail(`${label}.${field} must be an array`);
    return [];
  }
  if (nonEmpty && value.length === 0) fail(`${label}.${field} must not be empty`);
  return value;
}

function hasLocalPath(value) {
  return typeof value === "string" && (/^\/Users\//.test(value) || value.startsWith("~/") || value.startsWith("file://") || /^[A-Z]:\\/.test(value));
}

function scanForLocalPaths(value, label) {
  if (Array.isArray(value)) {
    value.forEach((child, index) => scanForLocalPaths(child, `${label}[${index}]`));
    return;
  }
  if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) scanForLocalPaths(child, `${label}.${key}`);
    return;
  }
  if (hasLocalPath(value)) fail(`${label} must not contain a local path`);
}

function scanPublicText(value, label) {
  if (/\/Users\/|~\/|file:\/\/|[A-Z]:\\|BEGIN [A-Z ]*PRIVATE KEY|\bAKIA[0-9A-Z]{16}\b|\bsk-[A-Za-z0-9]{20,}\b|CLAWIX_UI_PRIVATE_[A-Z_]+_ROOT/.test(value)) {
    fail(`${label} must not contain private roots, local paths, or secret-like tokens`);
  }
}

function escapeRegExp(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function hasWorkflowNodeRun(workflowSource, script) {
  return new RegExp(`^\\s*run:\\s+node\\s+${escapeRegExp(script)}\\s*$`, "m").test(workflowSource);
}

function hasTestScriptNodeRun(testScriptSource, script) {
  return new RegExp(`^\\s*run\\s+node\\s+"\\$ROOT_DIR/${escapeRegExp(script)}"\\s*$`, "m").test(testScriptSource);
}

const manifestPath = "docs/ui/gate-surface.manifest.json";
const manifest = readJson(manifestPath);
const privateVisualValidationPath = "docs/ui/private-visual-validation.manifest.json";
const privateVisualValidation = readJson(privateVisualValidationPath);
if (args.has("--simulate-wrong-external-pending-code") && manifest) {
  manifest.externalPendingExitCode = 1;
}
if (args.has("--simulate-private-command-mismatch") && manifest) {
  manifest.externalEvidenceCommand = "node scripts/ui_private_visual_verify.mjs";
}
if (args.has("--simulate-missing-required-lane") && Array.isArray(manifest?.requiredLanes)) {
  manifest.requiredLanes = manifest.requiredLanes.filter((lane) => lane !== "release");
}
if (args.has("--simulate-missing-release-requirement") && Array.isArray(manifest?.releaseLaneRequires)) {
  manifest.releaseLaneRequires = manifest.releaseLaneRequires.filter((lane) => lane !== "host");
}
if (args.has("--simulate-missing-visual-diff") && Array.isArray(manifest?.publicCiStrategy?.validates)) {
  manifest.publicCiStrategy.validates = manifest.publicCiStrategy.validates.filter((item) => item !== "visual-diff");
}
if (args.has("--simulate-private-roots-allowed") && manifest?.publicCiStrategy) {
  manifest.publicCiStrategy.forbidsPrivateRoots = false;
}
if (args.has("--simulate-missing-diff-base-consumer") && Array.isArray(manifest?.publicCiStrategy?.diffBaseConsumers)) {
  manifest.publicCiStrategy.diffBaseConsumers = manifest.publicCiStrategy.diffBaseConsumers.filter((script) => script !== "scripts/ui_pattern_mutation_guard.mjs");
}
if (args.has("--simulate-unlisted-coverage-script") && manifest?.publicCheckCoverage) {
  manifest.publicCheckCoverage["release-gate-contract-check"] = ["scripts/missing-release-gate-check.mjs"];
}
if (args.has("--simulate-undeclared-public-check-coverage") && manifest?.publicCheckCoverage) {
  manifest.publicCheckCoverage["simulated-undeclared-check"] = ["scripts/ui_release_gate_check.mjs"];
}
if (args.has("--simulate-required-script-uncovered") && Array.isArray(manifest?.requiredPublicCheckScripts)) {
  manifest.requiredPublicCheckScripts.push("scripts/simulated-uncovered-check.mjs");
}
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "localTestScript",
  "publicWorkflow",
  "requiredLanes",
  "releaseLaneRequires",
  "publicCiStrategy",
  "requiredPublicCheckScripts",
  "publicCheckCoverage",
  "externalEvidenceCommand",
  "externalPendingExitCode",
]);

if (manifest?.externalPendingExitCode !== 2) {
  fail(`${manifestPath}.externalPendingExitCode must be 2`);
}
if (!String(manifest?.externalEvidenceCommand || "").includes("scripts/ui_private_visual_verify.mjs --require-approved")) {
  fail(`${manifestPath}.externalEvidenceCommand must require the aggregate private visual verifier`);
}
if (manifest?.externalEvidenceCommand !== privateVisualValidation?.verificationCommand) {
  fail(`${manifestPath}.externalEvidenceCommand must match ${privateVisualValidationPath}.verificationCommand`);
}
for (const rootEnv of requireArray(privateVisualValidation, privateVisualValidationPath, "requiredRoots")) {
  if (!String(manifest?.externalEvidenceCommand || "").includes(rootEnv)) {
    fail(`${manifestPath}.externalEvidenceCommand must include ${rootEnv}`);
  }
}

let testScript = read(manifest?.localTestScript || "scripts/test.sh");
let workflow = read(manifest?.publicWorkflow || ".github/workflows/ui-governance.yml");
const config = readJson("docs/ui/interface-governance.config.json");
if (args.has("--simulate-missing-config-public-check") && Array.isArray(config?.publicChecks)) {
  config.publicChecks = config.publicChecks.filter((check) => check !== "release-gate-contract-check");
}
if (args.has("--simulate-missing-test-script-run")) {
  testScript = testScript.replace(/\n\s*run node "\$ROOT_DIR\/scripts\/ui_release_gate_check\.mjs"/, "");
}
if (args.has("--simulate-missing-workflow-run")) {
  workflow = workflow.replace(/\n\s*run: node scripts\/ui_release_gate_check\.mjs/, "");
}
if (args.has("--simulate-private-root-in-workflow")) {
  workflow += "\n# CLAWIX_UI_PRIVATE_BASELINE_ROOT=/Users/example/private-ui\n";
}
scanPublicText(testScript, manifest?.localTestScript || "scripts/test.sh");
scanPublicText(workflow, manifest?.publicWorkflow || ".github/workflows/ui-governance.yml");

const publicCiStrategy = manifest?.publicCiStrategy || {};
requireFields(publicCiStrategy, `${manifestPath}.publicCiStrategy`, [
  "job",
  "validates",
  "forbidsPrivateRoots",
  "externalEvidenceMode",
]);
if (!workflow.includes(`${publicCiStrategy.job}:`)) {
  fail(`${manifest.publicWorkflow} must define ${publicCiStrategy.job}`);
}
const publicCiValidates = new Set(requireArray(publicCiStrategy, `${manifestPath}.publicCiStrategy`, "validates"));
for (const required of ["lints", "geometry", "manifests"]) {
  if (!publicCiValidates.has(required)) fail(`${manifestPath}.publicCiStrategy.validates must include ${required}`);
}
if (!publicCiValidates.has("visual-diff")) {
  fail(`${manifestPath}.publicCiStrategy.validates must include visual-diff`);
}
if (publicCiStrategy.forbidsPrivateRoots !== true) {
  fail(`${manifestPath}.publicCiStrategy.forbidsPrivateRoots must be true`);
}
if (publicCiStrategy.diffBaseEnv !== "CLAWIX_UI_GUARD_DIFF_BASE") {
  fail(`${manifestPath}.publicCiStrategy.diffBaseEnv must be CLAWIX_UI_GUARD_DIFF_BASE`);
}
const diffBaseConsumers = new Set(
  requireArray(publicCiStrategy, `${manifestPath}.publicCiStrategy`, "diffBaseConsumers"),
);
for (const script of ["scripts/ui_governance_guard.mjs", "scripts/ui_pattern_mutation_guard.mjs"]) {
  if (!diffBaseConsumers.has(script)) {
    fail(`${manifestPath}.publicCiStrategy.diffBaseConsumers must include ${script}`);
  }
  const source = read(script);
  if (!source.includes(publicCiStrategy.diffBaseEnv)) {
    fail(`${script} must consume ${publicCiStrategy.diffBaseEnv}`);
  }
}
if (publicCiStrategy.externalEvidenceMode !== "external-pending-contract") {
  fail(`${manifestPath}.publicCiStrategy.externalEvidenceMode must be external-pending-contract`);
}
if (/CLAWIX_UI_PRIVATE_[A-Z_]+_ROOT/.test(workflow)) {
  fail(`${manifest.publicWorkflow} must not require private evidence roots`);
}
for (const snippet of [
  "fetch-depth: 0",
  "CLAWIX_UI_GUARD_DIFF_BASE",
  "github.event.pull_request.base.sha",
  "github.event.before",
]) {
  if (!workflow.includes(snippet)) fail(`${manifest.publicWorkflow} must wire UI visual diff base: ${snippet}`);
}

const lanes = new Set(requireArray(manifest, manifestPath, "requiredLanes"));
for (const lane of ["fast", "changed", "release"]) {
  if (!lanes.has(lane)) fail(`${manifestPath}.requiredLanes must include ${lane}`);
  if (!new RegExp(`\\n\\s*${lane}\\)`).test(testScript)) fail(`${manifest.localTestScript} must expose ${lane} lane`);
}

const releaseRequires = new Set(requireArray(manifest, manifestPath, "releaseLaneRequires"));
for (const required of ["integration", "e2e", "device", "host"]) {
  if (!releaseRequires.has(required)) fail(`${manifestPath}.releaseLaneRequires must include ${required}`);
}
for (const snippet of ['integration "$@"', "e2e_tests", "device_tests", "host_tests"]) {
  if (!testScript.includes(snippet)) fail(`${manifest.localTestScript} release lane must include ${snippet}`);
}

const configChecks = new Set(requireArray(config, "docs/ui/interface-governance.config.json", "publicChecks"));
if (!configChecks.has("release-gate-contract-check")) {
  fail("docs/ui/interface-governance.config.json.publicChecks must include release-gate-contract-check");
}
if (!configChecks.has("pattern-visual-mutation-guard")) {
  fail("docs/ui/interface-governance.config.json.publicChecks must include pattern-visual-mutation-guard");
}
const requiredPublicCheckScripts = new Set(requireArray(manifest, manifestPath, "requiredPublicCheckScripts"));
const publicCheckCoverage = manifest?.publicCheckCoverage || {};
if (!publicCheckCoverage || typeof publicCheckCoverage !== "object" || Array.isArray(publicCheckCoverage)) {
  fail(`${manifestPath}.publicCheckCoverage must be an object`);
}
for (const checkId of configChecks) {
  const scripts = publicCheckCoverage?.[checkId];
  if (!Array.isArray(scripts) || scripts.length === 0) {
    fail(`${manifestPath}.publicCheckCoverage must map ${checkId} to at least one public script`);
    continue;
  }
  for (const script of scripts) {
    if (!requiredPublicCheckScripts.has(script)) {
      fail(`${manifestPath}.publicCheckCoverage.${checkId} references script not listed in requiredPublicCheckScripts: ${script}`);
    }
  }
}
for (const checkId of Object.keys(publicCheckCoverage || {})) {
  if (!configChecks.has(checkId)) {
    fail(`${manifestPath}.publicCheckCoverage contains undeclared public check ${checkId}`);
  }
}
const coveredPublicCheckScripts = new Set(Object.values(publicCheckCoverage || {}).flat());
for (const script of requiredPublicCheckScripts) {
  if (!coveredPublicCheckScripts.has(script)) {
    fail(`${manifestPath}.publicCheckCoverage must cover required public script ${script}`);
  }
}

for (const script of requireArray(manifest, manifestPath, "requiredPublicCheckScripts")) {
  if (typeof script !== "string" || !script.startsWith("scripts/") || script.includes("..")) {
    fail(`${manifestPath}.requiredPublicCheckScripts entries must be repo-relative scripts`);
    continue;
  }
  if (!fs.existsSync(path.join(rootDir, script))) fail(`missing ${script}`);
  if (!hasTestScriptNodeRun(testScript, script)) {
    fail(`${manifest.localTestScript} must run ${script}`);
  }
  if (!hasWorkflowNodeRun(workflow, script)) {
    fail(`${manifest.publicWorkflow} must run ${script}`);
  }
}

scanForLocalPaths(manifest, manifestPath);

if (errors.length === 0 && !isSelfTest && args.size === 0) {
  for (const [flag, expectedOutput] of [
    ["--unknown-flag", "received unknown flag --unknown-flag"],
    ["--simulate-wrong-external-pending-code", "externalPendingExitCode must be 2"],
    ["--simulate-private-command-mismatch", "externalEvidenceCommand must require the aggregate private visual verifier"],
    ["--simulate-missing-required-lane", "requiredLanes must include release"],
    ["--simulate-missing-release-requirement", "releaseLaneRequires must include host"],
    ["--simulate-missing-visual-diff", "publicCiStrategy.validates must include visual-diff"],
    ["--simulate-private-roots-allowed", "publicCiStrategy.forbidsPrivateRoots must be true"],
    ["--simulate-missing-diff-base-consumer", "publicCiStrategy.diffBaseConsumers must include scripts/ui_pattern_mutation_guard.mjs"],
    ["--simulate-unlisted-coverage-script", "publicCheckCoverage.release-gate-contract-check references script not listed in requiredPublicCheckScripts"],
    ["--simulate-undeclared-public-check-coverage", "publicCheckCoverage contains undeclared public check simulated-undeclared-check"],
    ["--simulate-required-script-uncovered", "publicCheckCoverage must cover required public script scripts/simulated-uncovered-check.mjs"],
    ["--simulate-missing-config-public-check", "publicCheckCoverage contains undeclared public check release-gate-contract-check"],
    ["--simulate-missing-test-script-run", "scripts/test.sh must run scripts/ui_release_gate_check.mjs"],
    ["--simulate-missing-workflow-run", ".github/workflows/ui-governance.yml must run scripts/ui_release_gate_check.mjs"],
    ["--simulate-private-root-in-workflow", ".github/workflows/ui-governance.yml must not contain private roots, local paths, or secret-like tokens"],
  ]) {
    const result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, flag], {
      cwd: rootDir,
      env: { ...process.env, CLAWIX_UI_RELEASE_GATE_SELF_TEST: "1" },
      encoding: "utf8",
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status === 0) {
      fail(`self-test ${flag} must fail when release gate evidence is removed`);
      continue;
    }
    if (!output.includes(expectedOutput)) {
      fail(`self-test ${flag} output must include ${expectedOutput}`);
    }
  }
}

if (errors.length > 0) {
  console.error("UI release gate check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI release gate check passed (${manifest.requiredPublicCheckScripts.length} public scripts, ${configChecks.size} public checks)`);
