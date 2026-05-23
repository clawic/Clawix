#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const manifestPath = "docs/governance/adoption-canonicity.manifest.json";
const args = new Set(process.argv.slice(2));
const isSelfTestChild = process.env.CLAWIX_ADOPTION_CANONICITY_SELF_TEST === "1";
const errors = [];

function fail(message) {
  errors.push(message);
}

function readJson(relativePath) {
  try {
    return JSON.parse(fs.readFileSync(path.join(rootDir, relativePath), "utf8"));
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

function scanForLocalPaths(value, label) {
  if (Array.isArray(value)) {
    value.forEach((child, index) => scanForLocalPaths(child, `${label}[${index}]`));
    return;
  }
  if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) scanForLocalPaths(child, `${label}.${key}`);
    return;
  }
  if (typeof value === "string" && (/^\/Users\//.test(value) || value.startsWith("~/") || value.startsWith("file://") || /^[A-Z]:\\/.test(value))) {
    fail(`${label} must not contain a local path`);
  }
}

function isIsoDate(value) {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value) && !Number.isNaN(Date.parse(value));
}

function validateManifest(manifest, { mutation } = {}) {
  if (!manifest) return;
  if (mutation === "missing-feedback-loop") delete manifest.packets[0].feedbackLoop;
  if (mutation === "silent-telemetry") manifest.packets[0].telemetryDefault = "enabled";
  if (mutation === "local-private-path") manifest.packets[0].evidenceRefs[0].ref = "/Users/example/research.json";

  requireFields(manifest, manifestPath, ["schemaVersion", "status", "canonicalSource", "policy", "externalEvidenceAliases", "packets"]);
  if (manifest.schemaVersion !== 1) fail(`${manifestPath}.schemaVersion must be 1`);
  if (manifest.canonicalSource !== "../../clawjs/docs/governance/adoption-canonicity.manifest.json") {
    fail(`${manifestPath}.canonicalSource must point at the sibling ClawJS manifest`);
  }

  const packetIds = new Set();
  for (const [index, packet] of requireArray(manifest, manifestPath, "packets").entries()) {
    const label = `${manifestPath}.packets[${index}]`;
    requireFields(packet, label, [
      "id",
      "targetType",
      "targetId",
      "claimType",
      "stage",
      "targetAudience",
      "evidenceRefs",
      "feedbackLoop",
      "privacyMode",
      "telemetryDefault",
      "promotionDecision",
      "reviewCadence",
      "reviewedAt",
      "expiresAt",
    ]);
    if (packet.id) {
      if (packetIds.has(packet.id)) fail(`${label}.id duplicates another packet`);
      packetIds.add(packet.id);
    }
    if (packet.telemetryDefault !== "disabled") fail(`${label}.telemetryDefault must be disabled`);
    if (!isIsoDate(packet.reviewedAt)) fail(`${label}.reviewedAt must be an ISO date`);
    if (!isIsoDate(packet.expiresAt)) fail(`${label}.expiresAt must be an ISO date`);
    requireArray(packet, label, "evidenceRefs");
    requireFields(packet.feedbackLoop, `${label}.feedbackLoop`, ["mechanism", "cadence", "evidenceRefs"]);
    requireArray(packet.feedbackLoop, `${label}.feedbackLoop`, "evidenceRefs");
    requireFields(packet.promotionDecision, `${label}.promotionDecision`, ["state", "decidedBy", "decidedAt", "refs"]);
  }
  if (!packetIds.has("clawix-ui-canon-promotion-gate-2026-05-21")) {
    fail("missing seed packet clawix-ui-canon-promotion-gate-2026-05-21");
  }
  scanForLocalPaths(manifest, manifestPath);
}

function validateSiblingCanonicalScript() {
  const siblingScript = path.resolve(rootDir, "../../clawjs/scripts/adoption-canonicity-check.mjs");
  if (!fs.existsSync(siblingScript)) return;
  const result = spawnSync(process.execPath, [siblingScript], {
    cwd: path.resolve(rootDir, "../../clawjs"),
    encoding: "utf8",
  });
  if (result.status !== 0) {
    fail(`sibling ClawJS adoption/canonicity check failed: ${(result.stderr || result.stdout).trim()}`);
  }
}

function runSelfTests() {
  for (const [flag, expected] of [
    ["--simulate-missing-feedback-loop", "feedbackLoop"],
    ["--simulate-silent-telemetry", "telemetryDefault must be disabled"],
    ["--simulate-local-private-path", "must not contain a local path"],
  ]) {
    const result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, flag], {
      cwd: rootDir,
      env: { ...process.env, CLAWIX_ADOPTION_CANONICITY_SELF_TEST: "1" },
      encoding: "utf8",
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status === 0) fail(`self-test ${flag} must fail`);
    if (!output.includes(expected)) fail(`self-test ${flag} output must include ${expected}`);
  }
}

if (args.has("--self-test") && !isSelfTestChild) runSelfTests();

let mutation = null;
if (args.has("--simulate-missing-feedback-loop")) mutation = "missing-feedback-loop";
if (args.has("--simulate-silent-telemetry")) mutation = "silent-telemetry";
if (args.has("--simulate-local-private-path")) mutation = "local-private-path";

validateManifest(readJson(manifestPath), { mutation });
if (!isSelfTestChild) validateSiblingCanonicalScript();

if (errors.length > 0) {
  console.error("Clawix adoption/canonicity check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("Clawix adoption/canonicity check passed.");
