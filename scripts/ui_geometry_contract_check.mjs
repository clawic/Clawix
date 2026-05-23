#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const errors = [];
const summaries = [];
const rawArgs = process.argv.slice(2);
const args = new Set(rawArgs);
const isSelfTest = process.env.CLAWIX_UI_GEOMETRY_CONTRACT_SELF_TEST === "1";
const simulationFlags = [
  "--simulate-size-contracts-decision-missing-script",
  "--simulate-size-contracts-decision-missing-rendered-geometry",
  "--simulate-size-contracts-decision-missing-pattern-file",
  "--simulate-size-contracts-decision-missing-evidence-plan",
  "--simulate-size-contracts-decision-missing-private-blocker",
  "--simulate-size-contracts-decision-missing-private-platform",
  "--simulate-size-contracts-decision-missing-sidebar-row-private",
  "--simulate-size-contracts-decision-premature-complete",
  "--simulate-extra-platform-geometry",
  "--simulate-negative-measurement",
  "--simulate-mixed-direct-and-platform-geometry",
  "--simulate-short-pending-source",
  "--simulate-missing-platform-geometry",
  "--simulate-missing-private-validation",
  "--simulate-approved-size-contracts-stale-decision",
];
const allowedFlags = new Set(simulationFlags);

function fail(message) {
  errors.push(message);
}

for (const arg of rawArgs) {
  if (arg.startsWith("--") && !allowedFlags.has(arg)) {
    console.error(`UI geometry contract check received unknown flag ${arg}.`);
    process.exit(1);
  }
}

function readJson(relativePath) {
  const file = path.join(rootDir, relativePath);
  if (!fs.existsSync(file)) {
    fail(`missing ${relativePath}`);
    return null;
  }
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (error) {
    fail(`${relativePath} is not valid JSON: ${error.message}`);
    return null;
  }
}

function requireArray(object, relativePath, field) {
  const value = object?.[field];
  if (!Array.isArray(value)) {
    fail(`${relativePath}.${field} must be an array`);
    return [];
  }
  if (value.length === 0) {
    fail(`${relativePath}.${field} must not be empty`);
  }
  return value;
}

function isPlainObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function classifyGeometryClause(value, label) {
  if (!isPlainObject(value)) {
    fail(`${label} must be an object`);
    return "invalid";
  }

  const entries = Object.entries(value);
  if (entries.length === 0) {
    fail(`${label} must not be empty`);
    return "invalid";
  }

  if (typeof value.source === "string") {
    if (value.source.trim().length < 12) {
      fail(`${label}.source must explain the pending geometry contract`);
    }
    return "pending";
  }

  const numericEntries = entries.filter(([, child]) => typeof child === "number");
  const nestedEntries = entries.filter(([, child]) => isPlainObject(child));
  const invalidEntries = entries.filter(([, child]) => typeof child !== "number" && !isPlainObject(child));

  for (const [key, child] of numericEntries) {
    if (!Number.isFinite(child) || child < 0) fail(`${label}.${key} must be a finite non-negative number`);
  }
  for (const [key] of invalidEntries) {
    fail(`${label}.${key} must be a number, nested geometry object, or pending source object`);
  }

  if (numericEntries.length > 0 && nestedEntries.length > 0) {
    fail(`${label} must not mix direct measurements with nested platform clauses`);
    return "invalid";
  }

  if (numericEntries.length > 0) {
    return "measured";
  }

  if (nestedEntries.length > 0) {
    let hasMeasured = false;
    let hasPending = false;
    for (const [key, child] of nestedEntries) {
      const childType = classifyGeometryClause(child, `${label}.${key}`);
      if (childType === "measured") hasMeasured = true;
      if (childType === "pending") hasPending = true;
    }
    if (hasMeasured && hasPending) return "mixed";
    if (hasMeasured) return "measured";
    if (hasPending) return "pending";
  }

  fail(`${label} must contain measured numeric values or a pending source`);
  return "invalid";
}

function geometryHasDirectMeasurements(value) {
  return isPlainObject(value) && Object.values(value).some((child) => typeof child === "number");
}

function geometryHasPlatformClauses(value) {
  return isPlainObject(value) && Object.values(value).some((child) => isPlainObject(child));
}

const registryPath = "docs/ui/pattern-registry/patterns.registry.json";
const registry = readJson(registryPath);
const patternIds = requireArray(registry, registryPath, "patterns");
const decisionVerificationPath = "docs/ui/decision-verification.json";
const decisionVerification = readJson(decisionVerificationPath);
const sizeContractsDecision = (decisionVerification?.decisions || []).find((decision) => decision?.id === "size_contracts");

if (args.has("--simulate-size-contracts-decision-missing-script") && sizeContractsDecision) {
  sizeContractsDecision.publicEvidence = sizeContractsDecision.publicEvidence.filter((evidence) => evidence !== "scripts/ui_geometry_contract_check.mjs");
}
if (args.has("--simulate-size-contracts-decision-missing-rendered-geometry") && sizeContractsDecision) {
  sizeContractsDecision.publicEvidence = sizeContractsDecision.publicEvidence.filter((evidence) => evidence !== "docs/ui/rendered-geometry.manifest.json");
}
if (args.has("--simulate-size-contracts-decision-missing-pattern-file") && sizeContractsDecision) {
  sizeContractsDecision.publicEvidence = sizeContractsDecision.publicEvidence.filter((evidence) => evidence !== "docs/ui/pattern-registry/patterns/sidebar-row.pattern.json");
}
if (args.has("--simulate-size-contracts-decision-missing-evidence-plan") && sizeContractsDecision) {
  sizeContractsDecision.publicEvidence = sizeContractsDecision.publicEvidence.filter((evidence) => evidence !== "scripts/ui_private_evidence_plan_check.mjs");
}
if (args.has("--simulate-size-contracts-decision-missing-private-blocker") && sizeContractsDecision) {
  sizeContractsDecision.blockingVerifiers = sizeContractsDecision.blockingVerifiers.filter((verifier) => verifier !== "scripts/ui_private_geometry_verify.mjs");
}
if (args.has("--simulate-size-contracts-decision-missing-private-platform") && sizeContractsDecision) {
  sizeContractsDecision.externalEvidence = sizeContractsDecision.externalEvidence.filter((evidence) => evidence !== "external-ui-rendered-geometry:web/*");
}
if (args.has("--simulate-size-contracts-decision-missing-sidebar-row-private") && sizeContractsDecision) {
  sizeContractsDecision.externalEvidence = sizeContractsDecision.externalEvidence.filter((evidence) => evidence !== "external-ui-rendered-geometry:macos/sidebar-row");
}
if (args.has("--simulate-size-contracts-decision-premature-complete") && sizeContractsDecision) {
  sizeContractsDecision.status = "verified-complete";
  sizeContractsDecision.remaining = [];
}

let hasPendingGeometry = false;

for (const patternId of patternIds) {
  const patternPath = `docs/ui/pattern-registry/patterns/${patternId}.pattern.json`;
  const pattern = readJson(patternPath);
  if (!pattern) continue;
  if (args.has("--simulate-extra-platform-geometry") && patternId === patternIds[0]) {
    pattern.geometry = {
      ...pattern.geometry,
      windows: { source: "simulated undeclared platform geometry clause" },
    };
  }
  if (args.has("--simulate-negative-measurement") && patternId === "icon-chip-button") {
    pattern.geometry = { ...pattern.geometry, height: -1 };
  }
  if (args.has("--simulate-mixed-direct-and-platform-geometry") && patternId === "sidebar-section") {
    pattern.geometry = { ...pattern.geometry, extraPadding: 4 };
  }
  if (args.has("--simulate-short-pending-source") && patternId === "sidebar-section") {
    pattern.geometry = { ...pattern.geometry, ios: { source: "pending" } };
  }
  if (args.has("--simulate-missing-platform-geometry") && patternId === "sidebar-section") {
    const { web, ...rest } = pattern.geometry;
    pattern.geometry = rest;
  }
  if (args.has("--simulate-missing-private-validation") && patternId === "sidebar-section") {
    pattern.validation = { ...pattern.validation, private: [] };
  }

  const geometryType = classifyGeometryClause(pattern.geometry, `${patternPath}.geometry`);
  if (["pending", "mixed"].includes(geometryType)) hasPendingGeometry = true;
  const platforms = requireArray(pattern, patternPath, "platforms");
  if (geometryHasPlatformClauses(pattern.geometry) && !geometryHasDirectMeasurements(pattern.geometry)) {
    const platformSet = new Set(platforms);
    for (const geometryPlatform of Object.keys(pattern.geometry || {})) {
      if (!platformSet.has(geometryPlatform)) {
        fail(`${patternPath}.geometry.${geometryPlatform} must be listed in ${patternPath}.platforms`);
      }
    }
    for (const platform of platforms) {
      if (!isPlainObject(pattern.geometry?.[platform])) {
        fail(`${patternPath}.geometry.${platform} must declare measured values or an explicit pending source`);
      }
    }
  }
  const validationPrivate = Array.isArray(pattern.validation?.private) ? pattern.validation.private : [];
  if (validationPrivate.length === 0) {
    fail(`${patternPath}.validation.private must name the private geometry/visual evidence`);
  }
  summaries.push(`${patternId}:${geometryType}`);
}

if (args.has("--simulate-approved-size-contracts-stale-decision") && sizeContractsDecision) {
  hasPendingGeometry = false;
  sizeContractsDecision.status = "open";
  sizeContractsDecision.remaining = ["Simulated stale decision after approved private geometry measurement."];
}

if (!sizeContractsDecision) {
  fail(`${decisionVerificationPath}.decisions must include size_contracts`);
} else {
  const publicEvidence = new Set(Array.isArray(sizeContractsDecision.publicEvidence) ? sizeContractsDecision.publicEvidence : []);
  for (const evidence of [
    registryPath,
    "docs/ui/pattern-registry/patterns/sidebar-row.pattern.json",
    "docs/ui/pattern-registry/patterns/sidebar-section.pattern.json",
    "docs/ui/pattern-registry/patterns/composer-chrome.pattern.json",
    "docs/ui/pattern-registry/README.md",
    "docs/ui/rendered-geometry.manifest.json",
    "scripts/ui_geometry_contract_check.mjs",
    "scripts/ui_rendered_geometry_manifest_check.mjs",
    "scripts/ui_private_evidence_plan_check.mjs",
    "scripts/ui_private_geometry_verify.mjs",
    "scripts/ui_private_evidence_verify.mjs",
  ]) {
    if (!publicEvidence.has(evidence)) {
      fail(`${decisionVerificationPath}.decisions.size_contracts.publicEvidence must include ${evidence}`);
    }
  }
  const externalEvidence = new Set(Array.isArray(sizeContractsDecision.externalEvidence) ? sizeContractsDecision.externalEvidence : []);
  for (const evidence of [
    "external-ui-rendered-geometry:macos/*",
    "external-ui-rendered-geometry:ios/*",
    "external-ui-rendered-geometry:android/*",
    "external-ui-rendered-geometry:web/*",
    "external-ui-rendered-geometry:macos/sidebar-row",
  ]) {
    if (!externalEvidence.has(evidence)) {
      fail(`${decisionVerificationPath}.decisions.size_contracts.externalEvidence must include ${evidence}`);
    }
  }
  const blockingVerifiers = new Set(Array.isArray(sizeContractsDecision.blockingVerifiers) ? sizeContractsDecision.blockingVerifiers : []);
  for (const verifier of [
    "scripts/ui_private_geometry_verify.mjs",
    "scripts/ui_private_evidence_verify.mjs",
  ]) {
    if (!blockingVerifiers.has(verifier)) {
      fail(`${decisionVerificationPath}.decisions.size_contracts.blockingVerifiers must include ${verifier}`);
    }
  }
  if (hasPendingGeometry && !["open", "blocked-external-pending"].includes(sizeContractsDecision.status)) {
    fail(`${decisionVerificationPath}.decisions.size_contracts.status must remain open or blocked-external-pending while geometry clauses are pending private measurement`);
  }
  if (hasPendingGeometry && (!Array.isArray(sizeContractsDecision.remaining) || sizeContractsDecision.remaining.length === 0)) {
    fail(`${decisionVerificationPath}.decisions.size_contracts.remaining must describe pending private geometry measurement`);
  }
  if (!hasPendingGeometry && sizeContractsDecision.status !== "verified-complete") {
    fail(`${decisionVerificationPath}.decisions.size_contracts.status must be verified-complete after geometry clauses have private measurement`);
  }
  if (!hasPendingGeometry && Array.isArray(sizeContractsDecision.remaining) && sizeContractsDecision.remaining.length > 0) {
    fail(`${decisionVerificationPath}.decisions.size_contracts.remaining must be empty after geometry clauses have private measurement`);
  }
}

if (errors.length === 0 && !isSelfTest && args.size === 0) {
  for (const [flag, expectedOutput] of [
    ["--unknown-flag", "received unknown flag --unknown-flag"],
    ["--simulate-size-contracts-decision-missing-script", "decisions.size_contracts.publicEvidence must include scripts/ui_geometry_contract_check.mjs"],
    ["--simulate-size-contracts-decision-missing-rendered-geometry", "decisions.size_contracts.publicEvidence must include docs/ui/rendered-geometry.manifest.json"],
    ["--simulate-size-contracts-decision-missing-pattern-file", "decisions.size_contracts.publicEvidence must include docs/ui/pattern-registry/patterns/sidebar-row.pattern.json"],
    ["--simulate-size-contracts-decision-missing-evidence-plan", "decisions.size_contracts.publicEvidence must include scripts/ui_private_evidence_plan_check.mjs"],
    ["--simulate-size-contracts-decision-missing-private-blocker", "decisions.size_contracts.blockingVerifiers must include scripts/ui_private_geometry_verify.mjs"],
    ["--simulate-size-contracts-decision-missing-private-platform", "decisions.size_contracts.externalEvidence must include external-ui-rendered-geometry:web/*"],
    ["--simulate-size-contracts-decision-missing-sidebar-row-private", "decisions.size_contracts.externalEvidence must include external-ui-rendered-geometry:macos/sidebar-row"],
    ["--simulate-size-contracts-decision-premature-complete", "decisions.size_contracts.status must remain open or blocked-external-pending while geometry clauses are pending private measurement"],
    ["--simulate-extra-platform-geometry", "geometry.windows must be listed in"],
    ["--simulate-negative-measurement", "geometry.height must be a finite non-negative number"],
    ["--simulate-mixed-direct-and-platform-geometry", "must not mix direct measurements with nested platform clauses"],
    ["--simulate-short-pending-source", "geometry.ios.source must explain the pending geometry contract"],
    ["--simulate-missing-platform-geometry", "geometry.web must declare measured values or an explicit pending source"],
    ["--simulate-missing-private-validation", "validation.private must name the private geometry/visual evidence"],
    ["--simulate-approved-size-contracts-stale-decision", "decisions.size_contracts.status must be verified-complete after geometry clauses have private measurement"],
  ]) {
    const result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, flag], {
      cwd: rootDir,
      env: { ...process.env, CLAWIX_UI_GEOMETRY_CONTRACT_SELF_TEST: "1" },
      encoding: "utf8",
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status === 0) {
      fail(`self-test ${flag} must fail when geometry contract evidence is removed`);
      continue;
    }
    if (!output.includes(expectedOutput)) {
      fail(`self-test ${flag} output must include ${expectedOutput}`);
    }
  }
}

if (errors.length > 0) {
  console.error("UI geometry contract check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI geometry contract check passed (${summaries.join(", ")})`);
