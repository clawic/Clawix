#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const platforms = ["macos", "ios", "linux", "windows", "web"];
const statuses = new Set(["complete", "partial", "blocked", "dev-only", "not-applicable", "removed"]);
const releaseEffects = new Set(["allowed-for-v1", "blocks-parity-claim", "blocks-release"]);
const commandPrefixes = [
  "node scripts/",
  "npm --prefix ",
  "swift test ",
  "dotnet test ",
  "bash scripts/",
  "bash macos/scripts/",
  "qa/",
  "docs/",
];

function read(relativePath) {
  return fs.readFileSync(path.join(rootDir, relativePath), "utf8");
}

function readJson(relativePath) {
  return JSON.parse(read(relativePath));
}

function existsRef(ref) {
  const withoutAnchor = String(ref).split("#")[0];
  if (!withoutAnchor || /^[a-z]+ /u.test(withoutAnchor)) return true;
  if (withoutAnchor.startsWith("npm --prefix ") || withoutAnchor.startsWith("swift test ") || withoutAnchor.startsWith("dotnet test ")) return true;
  return fs.existsSync(path.join(rootDir, withoutAnchor));
}

function isPublicSafe(ref) {
  const text = String(ref);
  return !text.includes("/Users/")
    && !text.includes("file://")
    && !text.includes([".signing", "env"].join("."))
    && !text.includes(["scripts", "dev"].join("-"))
    && !text.includes(["clawix", "launcher"].join("-"));
}

function validateRefs(refs, label, failures, { commandAllowed = false } = {}) {
  if (!Array.isArray(refs) || refs.length === 0) {
    failures.push(`${label} must be a non-empty array`);
    return;
  }
  const seen = new Set();
  for (const ref of refs) {
    if (typeof ref !== "string" || ref.trim() === "") {
      failures.push(`${label} entries must be non-empty strings`);
      continue;
    }
    if (seen.has(ref)) failures.push(`${label} duplicate ref: ${ref}`);
    seen.add(ref);
    if (!isPublicSafe(ref)) failures.push(`${label}.${ref} must be public-safe`);
    if (commandAllowed && !existsRef(ref) && !commandPrefixes.some((prefix) => ref.startsWith(prefix))) {
      failures.push(`${label}.${ref} must be a known command or existing public path`);
    }
    if (!commandAllowed && !existsRef(ref)) failures.push(`${label}.${ref} does not exist`);
  }
}

function validateException(cell, label, failures) {
  const exception = cell.exceptionAccepted;
  if (!exception || typeof exception !== "object" || Array.isArray(exception)) {
    failures.push(`${label}: non-complete cells require exceptionAccepted`);
    return;
  }
  for (const field of ["id", "ownerArea", "acceptedBy", "acceptedOn", "reviewBy", "releaseEffect", "reason"]) {
    if (typeof exception[field] !== "string" || exception[field].trim() === "") {
      failures.push(`${label}.exceptionAccepted.${field} must be a non-empty string`);
    }
  }
  if (exception.acceptedBy !== "public-canon") {
    failures.push(`${label}.exceptionAccepted.acceptedBy must be public-canon`);
  }
  if (!/^\d{4}-\d{2}-\d{2}$/u.test(exception.acceptedOn || "")) {
    failures.push(`${label}.exceptionAccepted.acceptedOn must be YYYY-MM-DD`);
  }
  if (!/^\d{4}-\d{2}-\d{2}$/u.test(exception.reviewBy || "")) {
    failures.push(`${label}.exceptionAccepted.reviewBy must be YYYY-MM-DD`);
  }
  if (exception.reviewBy && exception.reviewBy < new Date().toISOString().slice(0, 10)) {
    failures.push(`${label}.exceptionAccepted.reviewBy is expired`);
  }
  if (!releaseEffects.has(exception.releaseEffect)) {
    failures.push(`${label}.exceptionAccepted.releaseEffect must be one of ${[...releaseEffects].join(", ")}`);
  }
  if (exception.releaseEffect === "blocks-release") {
    failures.push(`${label}.exceptionAccepted.releaseEffect blocks release readiness`);
  }
}

function validateManifest(manifest, failures, options = {}) {
  if (manifest.schemaVersion !== 1) failures.push("schemaVersion must be 1");
  if (manifest.scope !== "v1-platform-product-parity") failures.push("scope must be v1-platform-product-parity");
  if (manifest.canonicalDoc !== "docs/platform-feature-parity.md") failures.push("canonicalDoc must be docs/platform-feature-parity.md");
  if (manifest.sourcePlatform !== "macos") failures.push("sourcePlatform must be macos");
  if (JSON.stringify(manifest.releasePlatforms) !== JSON.stringify(platforms)) {
    failures.push(`releasePlatforms must be ${platforms.join(", ")}`);
  }
  if (!Array.isArray(manifest.statusVocabulary) || manifest.statusVocabulary.some((status) => !statuses.has(status))) {
    failures.push("statusVocabulary contains an unsupported status");
  }
  if (!Array.isArray(manifest.releaseEffects) || manifest.releaseEffects.some((effect) => !releaseEffects.has(effect))) {
    failures.push("releaseEffects contains an unsupported value");
  }
  if (!String(manifest.claimRule || "").includes("100% product parity")) {
    failures.push("claimRule must explain 100% product parity blocking");
  }

  const features = manifest.features;
  if (!Array.isArray(features) || features.length === 0) failures.push("features must be a non-empty array");
  const seenFeatureIds = new Set();
  const seenExceptionIds = new Set();
  for (const feature of features ?? []) {
    const label = `features.${feature?.id || "<missing>"}`;
    if (!feature || typeof feature !== "object" || Array.isArray(feature)) {
      failures.push("features entries must be objects");
      continue;
    }
    for (const field of ["id", "macosFeature", "category", "ownerArea"]) {
      if (typeof feature[field] !== "string" || feature[field].trim() === "") failures.push(`${label}.${field} is required`);
    }
    if (seenFeatureIds.has(feature.id)) failures.push(`duplicate feature id: ${feature.id}`);
    seenFeatureIds.add(feature.id);
    validateRefs(feature.sourceRefs, `${label}.sourceRefs`, failures);
    const platformKeys = Object.keys(feature.platforms || {});
    if (JSON.stringify(platformKeys.sort()) !== JSON.stringify([...platforms].sort())) {
      failures.push(`${label}.platforms must include exactly ${platforms.join(", ")}`);
    }
    for (const platform of platforms) {
      const cell = feature.platforms?.[platform];
      const cellLabel = `${label}.platforms.${platform}`;
      if (!cell || typeof cell !== "object" || Array.isArray(cell)) {
        failures.push(`${cellLabel} must be an object`);
        continue;
      }
      if (!statuses.has(cell.status)) failures.push(`${cellLabel}.status is unsupported: ${cell.status}`);
      validateRefs(cell.evidence, `${cellLabel}.evidence`, failures);
      validateRefs(cell.tests, `${cellLabel}.tests`, failures, { commandAllowed: true });
      if (platform === "macos" && cell.status !== "complete") {
        failures.push(`${cellLabel}.status must be complete because macos is the source feature platform`);
      }
      if (cell.status === "complete") {
        if (cell.exceptionAccepted !== undefined) failures.push(`${cellLabel}: complete cells must not carry exceptionAccepted`);
      } else {
        validateException(cell, cellLabel, failures);
        if (cell.exceptionAccepted?.id) {
          if (seenExceptionIds.has(cell.exceptionAccepted.id)) failures.push(`duplicate exception id: ${cell.exceptionAccepted.id}`);
          seenExceptionIds.add(cell.exceptionAccepted.id);
        }
      }
    }
  }

  if (!options.skipDocs) validateDocRouting(manifest, failures);
}

function validateDocRouting(manifest, failures) {
  const required = [
    ["docs/platform-feature-parity.md", "macOS feature"],
    ["docs/platform-feature-parity.md", "blocks-parity-claim"],
    ["docs/decision-map.md", "platform-feature-parity.manifest.json"],
    ["docs/governance/release-readiness.md", "Platform product parity"],
    ["docs/governance/release-readiness.manifest.json", "scripts/platform_feature_parity_check.mjs"],
    ["docs/agent-rules/index.md", "Platform product parity"],
    ["docs/discoverability.md", "platform_feature_parity_check"],
    ["docs/discoverability.registry.json", "platform_feature_parity_check"],
    ["scripts/test.sh", "platform_feature_parity_check.mjs"],
  ];
  for (const [relativePath, snippet] of required) {
    if (!fs.existsSync(path.join(rootDir, relativePath))) {
      failures.push(`missing routed document: ${relativePath}`);
      continue;
    }
    if (!read(relativePath).includes(snippet)) failures.push(`${relativePath} is missing required snippet: ${snippet}`);
  }
  const doc = read("docs/platform-feature-parity.md");
  for (const feature of manifest.features ?? []) {
    if (!doc.includes(`\`${feature.id}\``)) failures.push(`docs/platform-feature-parity.md missing feature id ${feature.id}`);
  }
}

function runSelfTest() {
  const manifest = readJson("docs/platform-feature-parity.manifest.json");
  const normalFailures = [];
  validateManifest(manifest, normalFailures, { skipDocs: true });
  if (normalFailures.length) {
    console.error(`self-test base manifest unexpectedly failed:\n- ${normalFailures.join("\n- ")}`);
    process.exit(1);
  }

  const missingException = structuredClone(manifest);
  delete missingException.features[0].platforms.ios.exceptionAccepted;
  const missingFailures = [];
  validateManifest(missingException, missingFailures, { skipDocs: true });
  if (!missingFailures.some((failure) => failure.includes("non-complete cells require exceptionAccepted"))) {
    console.error("self-test failed to catch missing non-complete exception");
    process.exit(1);
  }

  const falseComplete = structuredClone(manifest);
  falseComplete.features[0].platforms.macos.exceptionAccepted = {
    id: "PFPM-INVALID",
    ownerArea: "test",
    acceptedBy: "public-canon",
    acceptedOn: "2026-05-23",
    reviewBy: "2026-08-31",
    releaseEffect: "allowed-for-v1",
    reason: "invalid",
  };
  const falseCompleteFailures = [];
  validateManifest(falseComplete, falseCompleteFailures, { skipDocs: true });
  if (!falseCompleteFailures.some((failure) => failure.includes("complete cells must not carry exceptionAccepted"))) {
    console.error("self-test failed to catch complete cell exception");
    process.exit(1);
  }

  console.log("platform feature parity self-test passed");
}

if (args.includes("--self-test")) {
  runSelfTest();
  process.exit(0);
}

const failures = [];
validateManifest(readJson("docs/platform-feature-parity.manifest.json"), failures);
if (failures.length) {
  console.error(`platform feature parity check failed:\n- ${failures.join("\n- ")}`);
  process.exit(1);
}

console.log("platform feature parity check passed");
