#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const errors = [];
const summaries = [];
const args = new Set(process.argv.slice(2));

function fail(message) {
  errors.push(message);
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
if (args.has("--simulate-size-contracts-decision-missing-private-blocker") && sizeContractsDecision) {
  sizeContractsDecision.blockingVerifiers = sizeContractsDecision.blockingVerifiers.filter((verifier) => verifier !== "scripts/ui_private_geometry_verify.mjs");
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

if (!sizeContractsDecision) {
  fail(`${decisionVerificationPath}.decisions must include size_contracts`);
} else {
  const publicEvidence = new Set(Array.isArray(sizeContractsDecision.publicEvidence) ? sizeContractsDecision.publicEvidence : []);
  for (const evidence of [
    registryPath,
    "docs/ui/pattern-registry/README.md",
    "docs/ui/rendered-geometry.manifest.json",
    "scripts/ui_geometry_contract_check.mjs",
    "scripts/ui_private_geometry_verify.mjs",
  ]) {
    if (!publicEvidence.has(evidence)) {
      fail(`${decisionVerificationPath}.decisions.size_contracts.publicEvidence must include ${evidence}`);
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
  if (hasPendingGeometry && sizeContractsDecision.status !== "open") {
    fail(`${decisionVerificationPath}.decisions.size_contracts.status must remain open while geometry clauses are pending private measurement`);
  }
  if (hasPendingGeometry && (!Array.isArray(sizeContractsDecision.remaining) || sizeContractsDecision.remaining.length === 0)) {
    fail(`${decisionVerificationPath}.decisions.size_contracts.remaining must describe pending private geometry measurement`);
  }
}

if (errors.length > 0) {
  console.error("UI geometry contract check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI geometry contract check passed (${summaries.join(", ")})`);
