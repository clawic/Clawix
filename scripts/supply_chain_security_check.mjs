#!/usr/bin/env node
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = process.argv.slice(2);
let releaseMode = args.includes("--release");
const selfTest = args.includes("--self-test");
const targetArg = args.find((arg) => arg.startsWith("--target="));
const targetIndex = args.indexOf("--target");
const releaseTarget = targetArg ? targetArg.slice("--target=".length) : (targetIndex >= 0 ? args[targetIndex + 1] : "all");
const errors = [];

function fail(message) {
  errors.push(message);
}

function read(relativePath) {
  return fs.readFileSync(path.join(rootDir, relativePath), "utf8");
}

function readJson(relativePath) {
  return JSON.parse(read(relativePath));
}

function exists(relativePath) {
  return fs.existsSync(path.join(rootDir, relativePath));
}

function requireSnippet(relativePath, snippet) {
  if (!exists(relativePath)) {
    fail(`${relativePath} is missing`);
    return;
  }
  if (!read(relativePath).includes(snippet)) fail(`${relativePath} must mention ${snippet}`);
}

function inReleaseTarget(surface) {
  if (!releaseMode) return false;
  const targets = surface.releaseTargets ?? [];
  return releaseTarget === "all" || targets.includes("all") || targets.includes(releaseTarget);
}

function validateControl(surface, fieldName) {
  const control = surface[fieldName];
  if (!control || typeof control !== "object" || Array.isArray(control)) {
    fail(`${surface.id}.${fieldName} must be an object`);
    return;
  }
  if (!["pass", "baseline_exception", "external_pending"].includes(control.status)) {
    fail(`${surface.id}.${fieldName}.status must be pass, baseline_exception, or external_pending`);
  }
  if (typeof control.evidence !== "string" || control.evidence.trim() === "") {
    fail(`${surface.id}.${fieldName}.evidence must be non-empty`);
  }
  if (control.status !== "pass" && typeof control.exception !== "string") {
    fail(`${surface.id}.${fieldName} with ${control.status} must record an exception`);
  }
  if (inReleaseTarget(surface) && surface.releaseCritical && control.status !== "pass") {
    fail(`${surface.id}.${fieldName} blocks ${releaseTarget}: ${control.status}`);
  }
}

function validateManifest(manifest = readJson("docs/supply-chain-security.manifest.json")) {
  if (manifest.schemaVersion !== 1) fail("manifest schemaVersion must be 1");
  if (manifest.canonicalSource !== "../../../clawjs/docs/supply-chain-security.md") fail("manifest canonicalSource must point to sibling ClawJS policy");
  const policy = manifest.policy ?? {};
  if (policy.mode !== "baseline-plus-release-hard-fail") fail("manifest policy.mode must be baseline-plus-release-hard-fail");
  if (policy.releaseHardFail !== true) fail("manifest policy.releaseHardFail must be true");
  if (policy.sbomFormat !== "CycloneDX JSON") fail("manifest policy.sbomFormat must be CycloneDX JSON");
  if (!String(policy.provenanceTarget ?? "").includes("SLSA Build L2")) fail("manifest policy.provenanceTarget must target SLSA Build L2");
  const sla = policy.vulnerabilitySla ?? {};
  for (const [field, value] of Object.entries({ acknowledgeHours: 48, criticalPlanHours: 24, criticalFixHours: 72, highDays: 7, mediumDays: 30, lowDays: 90 })) {
    if (sla[field] !== value) fail(`manifest vulnerabilitySla.${field} must be ${value}`);
  }
  const surfaces = manifest.surfaces;
  if (!Array.isArray(surfaces) || surfaces.length === 0) fail("manifest.surfaces must be a non-empty array");
  const ids = new Set();
  for (const surface of surfaces ?? []) {
    if (!surface.id || ids.has(surface.id)) fail(`surface id is missing or duplicated: ${surface.id}`);
    ids.add(surface.id);
    if (!surface.path || !exists(surface.path)) fail(`${surface.id}.path does not exist: ${surface.path}`);
    if (!Array.isArray(surface.releaseTargets) || surface.releaseTargets.length === 0) fail(`${surface.id}.releaseTargets must be non-empty`);
    for (const field of ["lockfile", "sbom", "provenance", "dependencyReview", "vulnerabilityTriage", "artifactIntegrity", "malwareReview"]) {
      validateControl(surface, field);
    }
  }
}

function validatePackageManagerPins() {
  const pins = [
    ["web/package.json", /^pnpm@\d+\.\d+\.\d+$/u],
    ["linux/app/package.json", /^npm@\d+\.\d+\.\d+$/u],
    ["cli/package.json", /^npm@\d+\.\d+\.\d+$/u],
  ];
  for (const [file, pattern] of pins) {
    const packageManager = readJson(file).packageManager ?? "";
    if (!pattern.test(packageManager)) fail(`${file} must pin packageManager`);
  }
}

function validateLockfiles() {
  for (const file of [
    "web/pnpm-lock.yaml",
    "linux/app/package-lock.json",
    "linux/app/src-tauri/Cargo.lock",
    "macos/Package.resolved",
    "macos/Helpers/Bridged/Package.resolved",
    "macos/Helpers/Menubar/Package.resolved",
  ]) {
    if (!exists(file)) fail(`missing lockfile/resolved dependency file ${file}`);
  }
}

function validateCodeowners() {
  for (const snippet of ["package.json", "pnpm-lock.yaml", "Package.resolved", "Cargo.lock", "docs/supply-chain-security", "scripts/supply_chain_security_check.mjs"]) {
    requireSnippet(".github/CODEOWNERS", snippet);
  }
}

function validateDocs() {
  for (const [file, snippets] of [
    ["docs/adr/0027-supply-chain-security-governance-mirror.md", ["ClawJS", "release-critical", "scripts/supply_chain_security_check.mjs"]],
    ["docs/supply-chain-security.md", ["CycloneDX JSON", "claw verify release", "claw verify plugin", "72 hours"]],
    ["docs/supply-chain-vulnerability-triage.md", ["CLX-SC-VULN-001"]],
    ["SECURITY.md", ["Supply-chain security"]],
    ["RELEASING.md", ["Supply-chain evidence"]],
    [".github/PULL_REQUEST_TEMPLATE.md", ["Dependency and supply-chain review"]],
    ["docs/decision-map.md", ["Supply-chain security governance", "scripts/supply_chain_security_check.mjs"]],
    ["docs/discoverability.registry.json", ["supply_chain_security_check.mjs"]],
  ]) {
    for (const snippet of snippets) requireSnippet(file, snippet);
  }
}

function validateReleaseWiring() {
  requireSnippet("scripts/test.sh", "supply_chain_security_check.mjs");
  for (const file of [
    "macos/scripts/build_release_app.sh",
    "ios/scripts/build_release_app.sh",
    "linux/scripts/build_release_appimage.sh",
    "linux/scripts/build_release_deb.sh",
    "windows/scripts/build-release.ps1",
  ]) {
    requireSnippet(file, "supply_chain_security_check.mjs");
  }
}

function runCheck() {
  validateManifest();
  validatePackageManagerPins();
  validateLockfiles();
  validateCodeowners();
  validateDocs();
  validateReleaseWiring();
}

function runSelfTest() {
  const manifest = {
    schemaVersion: 1,
    canonicalSource: "../../../clawjs/docs/supply-chain-security.md",
    policy: {
      mode: "baseline-plus-release-hard-fail",
      releaseHardFail: true,
      sbomFormat: "CycloneDX JSON",
      provenanceTarget: "SLSA Build L2 for CI-built official artifacts",
      vulnerabilitySla: { acknowledgeHours: 48, criticalPlanHours: 24, criticalFixHours: 72, highDays: 7, mediumDays: 30, lowDays: 90 },
    },
    surfaces: [{
      id: "fixture",
      kind: "native-app",
      path: "RELEASING.md",
      releaseCritical: true,
      releaseTargets: ["all"],
      lockfile: { status: "pass", evidence: "fixture" },
      sbom: { status: "pass", evidence: "fixture" },
      provenance: { status: "pass", evidence: "fixture" },
      dependencyReview: { status: "pass", evidence: "fixture" },
      vulnerabilityTriage: { status: "pass", evidence: "fixture" },
      artifactIntegrity: { status: "pass", evidence: "fixture" },
      malwareReview: { status: "pass", evidence: "fixture" },
    }],
  };
  errors.length = 0;
  validateManifest(manifest);
  assert.equal(errors.length, 0);
  manifest.surfaces[0].sbom = { status: "baseline_exception", evidence: "fixture", exception: "fixture" };
  const previousReleaseMode = releaseMode;
  releaseMode = true;
  errors.length = 0;
  validateManifest(manifest);
  assert(errors.some((error) => error.includes("fixture.sbom blocks all")));
  releaseMode = previousReleaseMode;
  errors.length = 0;
}

if (selfTest) {
  runSelfTest();
  console.log("Clawix supply-chain security check self-test passed");
  process.exit(0);
}

runCheck();
if (errors.length > 0) {
  console.error("Clawix supply-chain security check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`Clawix supply-chain security check passed${releaseMode ? ` (${releaseTarget})` : ""}`);
