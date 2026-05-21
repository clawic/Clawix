#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const rawArgs = process.argv.slice(2);
const args = new Set(rawArgs);
const isSelfTest = process.env.CLAWIX_UI_VISUAL_DETECTOR_SELF_TEST === "1";
const simulationFlags = [
  "--simulate-unsafe-source-root",
  "--simulate-missing-required-source-root",
  "--simulate-missing-required-change-kind",
  "--simulate-missing-classification-bucket",
  "--simulate-unregistered-bucket-kind",
  "--simulate-duplicate-bucket-kind",
  "--simulate-duplicate-detector-id",
  "--simulate-unclassified-change-kind",
  "--simulate-missing-detector-kind",
  "--simulate-unsupported-detector-platform",
  "--simulate-invalid-detector-regex",
  "--simulate-invalid-detector-severity",
  "--simulate-missing-report-only-severity",
  "--simulate-unknown-copy-kind",
  "--simulate-missing-governance-guard-platform-scope",
];
const allowedFlags = new Set(simulationFlags);
const errors = [];

function fail(message) {
  errors.push(message);
}

for (const arg of rawArgs) {
  if (arg.startsWith("--") && !allowedFlags.has(arg)) {
    console.error(`UI visual detector check received unknown flag ${arg}.`);
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
  if (nonEmpty && value.length === 0) {
    fail(`${label}.${field} must not be empty`);
  }
  return value;
}

const configPath = "docs/ui/interface-governance.config.json";
const config = readJson(configPath);
const requiredPlatforms = new Set(requireArray(config, configPath, "platforms"));
const detectorPath = "docs/ui/visual-change-detectors.manifest.json";
const manifest = readJson(detectorPath);
const copyInventory = readJson("docs/ui/copy.inventory.json");
if (manifest && args.has("--simulate-unsafe-source-root") && Array.isArray(manifest.sourceRoots)) {
  manifest.sourceRoots[0] = "/Users/example/Clawix/macos/Sources";
}
if (manifest && args.has("--simulate-missing-required-source-root") && Array.isArray(manifest.sourceRoots)) {
  manifest.sourceRoots = manifest.sourceRoots.filter((sourceRoot) => sourceRoot !== "web/src");
}
if (manifest && args.has("--simulate-missing-required-change-kind") && Array.isArray(manifest.requiredChangeKinds)) {
  manifest.requiredChangeKinds = manifest.requiredChangeKinds.filter((kind) => kind !== "typography");
}
if (manifest && args.has("--simulate-missing-classification-bucket") && Array.isArray(manifest.classificationBuckets)) {
  manifest.classificationBuckets = manifest.classificationBuckets.filter((bucket) => bucket?.id !== "hierarchy");
}
if (manifest && args.has("--simulate-unregistered-bucket-kind") && Array.isArray(manifest.classificationBuckets)) {
  manifest.classificationBuckets[0].changeKinds.push("shadow");
}
if (manifest && args.has("--simulate-duplicate-bucket-kind") && Array.isArray(manifest.classificationBuckets)) {
  manifest.classificationBuckets[1].changeKinds.push("color");
}
if (manifest && args.has("--simulate-duplicate-detector-id") && Array.isArray(manifest.detectors)) {
  manifest.detectors = [...manifest.detectors, { ...manifest.detectors[0] }];
}
if (manifest && args.has("--simulate-unclassified-change-kind")) {
  manifest.classificationBuckets = manifest.classificationBuckets.map((bucket) => {
    if (bucket.id !== "presentation") return bucket;
    return {
      ...bucket,
      changeKinds: bucket.changeKinds.filter((kind) => kind !== "typography"),
    };
  });
}
if (manifest && args.has("--simulate-missing-detector-kind") && Array.isArray(manifest.detectors)) {
  manifest.detectors = manifest.detectors.filter((detector) => detector?.changeKind !== "spacing");
}
if (manifest && args.has("--simulate-unsupported-detector-platform") && Array.isArray(manifest.detectors)) {
  manifest.detectors[0].platforms = ["visionos"];
}
if (manifest && args.has("--simulate-invalid-detector-regex") && Array.isArray(manifest.detectors)) {
  manifest.detectors[0].pattern = "(";
}
if (manifest && args.has("--simulate-invalid-detector-severity") && Array.isArray(manifest.detectors)) {
  manifest.detectors[0].severity = "warning";
}
if (manifest && args.has("--simulate-missing-report-only-severity") && Array.isArray(manifest.detectors)) {
  const detector = manifest.detectors.find((candidate) => candidate?.id === "cross-ordering");
  if (detector) delete detector.severity;
}
if (copyInventory && args.has("--simulate-unknown-copy-kind") && Array.isArray(copyInventory.restrictedCopyKinds)) {
  copyInventory.restrictedCopyKinds.push("confirmation-text");
}
requireFields(manifest, detectorPath, [
  "schemaVersion",
  "status",
  "policy",
  "sourceRoots",
  "requiredChangeKinds",
  "classificationBuckets",
  "detectors",
]);

const sourceRoots = requireArray(manifest, detectorPath, "sourceRoots");
const sourceRootSet = new Set(sourceRoots);
for (const [index, sourceRoot] of sourceRoots.entries()) {
  const label = `${detectorPath}.sourceRoots[${index}]`;
  if (typeof sourceRoot !== "string" || sourceRoot === "") {
    fail(`${label} must be a non-empty string`);
    continue;
  }
  if (sourceRoot.startsWith("/") || sourceRoot.startsWith("~/") || sourceRoot.includes("\\") || sourceRoot.includes("..") || sourceRoot.startsWith("file://") || /^[A-Z]:\\/.test(sourceRoot)) {
    fail(`${label} must be a safe relative path`);
    continue;
  }
  if (!fs.existsSync(path.join(rootDir, sourceRoot))) fail(`${label} does not exist`);
}
for (const root of ["macos/Sources", "ios/Sources", "apps/macos/Sources", "apps/ios/Sources", "android/app/src/main", "web/src"]) {
  if (!sourceRootSet.has(root)) fail(`${detectorPath}.sourceRoots must include ${root}`);
}

const requiredKinds = new Set(requireArray(manifest, detectorPath, "requiredChangeKinds"));
for (const kind of requireArray(config, configPath, "restrictedChangeKinds")) {
  if (!requiredKinds.has(kind)) fail(`${detectorPath}.requiredChangeKinds must include ${kind}`);
}

const requiredBuckets = new Map([
  ["presentation", ["color", "spacing", "size", "icon", "layout", "animation", "typography"]],
  ["copy", ["microcopy", "visible-name"]],
  ["hierarchy", ["ordering", "hierarchy"]],
]);
const bucketsById = new Map();
const bucketCoverage = new Map();
for (const [index, bucket] of requireArray(manifest, detectorPath, "classificationBuckets").entries()) {
  const label = `${detectorPath}.classificationBuckets[${index}]`;
  requireFields(bucket, label, ["id", "changeKinds"]);
  if (bucket?.id) bucketsById.set(bucket.id, bucket);
  for (const kind of requireArray(bucket, label, "changeKinds")) {
    if (!requiredKinds.has(kind)) fail(`${label}.changeKinds contains unregistered ${kind}`);
    bucketCoverage.set(kind, [...(bucketCoverage.get(kind) || []), bucket.id]);
  }
}
for (const [bucketId, kinds] of requiredBuckets.entries()) {
  const bucket = bucketsById.get(bucketId);
  if (!bucket) {
    fail(`${detectorPath}.classificationBuckets must include ${bucketId}`);
    continue;
  }
  const bucketKinds = new Set(bucket.changeKinds || []);
  for (const kind of kinds) {
    if (!bucketKinds.has(kind)) fail(`${detectorPath}.classificationBuckets.${bucketId} must include ${kind}`);
  }
}
for (const kind of requiredKinds) {
  const bucketIds = bucketCoverage.get(kind) || [];
  if (bucketIds.length === 0) fail(`${detectorPath}.classificationBuckets must classify ${kind}`);
  if (bucketIds.length > 1) fail(`${detectorPath}.classificationBuckets must classify ${kind} exactly once`);
}

const seenKinds = new Set();
const seenPlatforms = new Set();
const seenSeverities = new Set();
const detectorPatternsByKind = new Map();
const detectorIds = new Set();
const reportOnlyDetectorIds = new Set(["cross-ordering", "cross-visible-name", "cross-hierarchy", "cross-spacing"]);
const allowedDetectorSeverities = new Set(["blocking", "report-only"]);
for (const [index, detector] of requireArray(manifest, detectorPath, "detectors").entries()) {
  const label = `${detectorPath}.detectors[${index}]`;
  requireFields(detector, label, ["id", "platforms", "changeKind", "pattern", "reason"]);
  if (detectorIds.has(detector.id)) fail(`${label}.id duplicates ${detector.id}`);
  detectorIds.add(detector.id);
  const severity = detector.severity || "blocking";
  if (!allowedDetectorSeverities.has(severity)) fail(`${label}.severity must be blocking or report-only`);
  seenSeverities.add(severity);
  if (reportOnlyDetectorIds.has(detector.id) && severity !== "report-only") {
    fail(`${label}.severity must be report-only for broad lexical detector ${detector.id}`);
  }
  if (!requiredKinds.has(detector.changeKind)) fail(`${label}.changeKind is not registered`);
  seenKinds.add(detector.changeKind);
  detectorPatternsByKind.set(
    detector.changeKind,
    `${detectorPatternsByKind.get(detector.changeKind) || ""}\n${detector.pattern || ""}`,
  );
  for (const platform of requireArray(detector, label, "platforms")) {
    if (!requiredPlatforms.has(platform)) fail(`${label}.platforms contains unsupported ${platform}`);
    seenPlatforms.add(platform);
  }
  try {
    new RegExp(detector.pattern);
  } catch (error) {
    fail(`${label}.pattern is not a valid regex: ${error.message}`);
  }
}

for (const kind of requiredKinds) {
  if (!seenKinds.has(kind)) fail(`${detectorPath}.detectors must cover ${kind}`);
}
for (const platform of requiredPlatforms) {
  if (!seenPlatforms.has(platform)) fail(`${detectorPath}.detectors must cover ${platform}`);
}
for (const severity of allowedDetectorSeverities) {
  if (!seenSeverities.has(severity)) fail(`${detectorPath}.detectors must include ${severity} severity`);
}

const copySignalsByKind = {
  "visible-name": ["title", "label"],
  label: ["label", "aria-label", "accessibilityLabel"],
  placeholder: ["placeholder"],
  tooltip: ["tooltip", "help", "aria-label", "accessibilityLabel"],
  microcopy: ["help", "accessibilityLabel", "aria-label"],
  "empty-state": ["emptyState"],
  "loading-state": ["loadingState"],
  "error-state": ["errorMessage"],
  "copy-hierarchy": ["section", "header", "footer"],
};
const combinedDetectorPatterns = [...detectorPatternsByKind.values()].join("\n");
for (const copyKind of requireArray(copyInventory, "docs/ui/copy.inventory.json", "restrictedCopyKinds")) {
  const signals = copySignalsByKind[copyKind];
  if (!signals) {
    fail(`scripts/ui_visual_detector_check.mjs must declare copy detector signals for ${copyKind}`);
    continue;
  }
  if (!signals.some((signal) => combinedDetectorPatterns.includes(signal))) {
    fail(`${detectorPath}.detectors must cover restricted copy kind ${copyKind}`);
  }
}

let governanceGuardSource = fs.existsSync(path.join(rootDir, "scripts/ui_governance_guard.mjs"))
  ? fs.readFileSync(path.join(rootDir, "scripts/ui_governance_guard.mjs"), "utf8")
  : "";
if (args.has("--simulate-missing-governance-guard-platform-scope")) {
  governanceGuardSource = governanceGuardSource.replace("detector.platforms.includes(platform)", "");
}
for (const snippet of ["platformForPath", "detector.platforms.includes(platform)", "--simulate-cross-platform-visual-diff", "blockingVisualHits", "reportOnlyVisualHits"]) {
  if (!governanceGuardSource.includes(snippet)) {
    fail(`scripts/ui_governance_guard.mjs must enforce detector platform/severity handling via ${snippet}`);
  }
}

if (errors.length === 0 && !isSelfTest && args.size === 0) {
  for (const [flag, expectedOutput] of [
    ["--unknown-flag", "received unknown flag --unknown-flag"],
    ["--simulate-unsafe-source-root", "sourceRoots[0] must be a safe relative path"],
    ["--simulate-missing-required-source-root", "sourceRoots must include web/src"],
    ["--simulate-missing-required-change-kind", "requiredChangeKinds must include typography"],
    ["--simulate-missing-classification-bucket", "classificationBuckets must include hierarchy"],
    ["--simulate-unregistered-bucket-kind", "changeKinds contains unregistered shadow"],
    ["--simulate-duplicate-bucket-kind", "classificationBuckets must classify color exactly once"],
    ["--simulate-unclassified-change-kind", "classificationBuckets must classify typography"],
    ["--simulate-missing-detector-kind", "detectors must cover spacing"],
    ["--simulate-unsupported-detector-platform", "platforms contains unsupported visionos"],
    ["--simulate-invalid-detector-regex", "pattern is not a valid regex"],
    ["--simulate-invalid-detector-severity", "severity must be blocking or report-only"],
    ["--simulate-missing-report-only-severity", "severity must be report-only for broad lexical detector cross-ordering"],
    ["--simulate-unknown-copy-kind", "must declare copy detector signals for confirmation-text"],
    ["--simulate-missing-governance-guard-platform-scope", "ui_governance_guard.mjs must enforce detector platform/severity handling"],
  ]) {
    const result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, flag], {
      cwd: rootDir,
      env: { ...process.env, CLAWIX_UI_VISUAL_DETECTOR_SELF_TEST: "1" },
      encoding: "utf8",
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status === 0) {
      fail(`self-test ${flag} must fail when visual detector evidence is removed`);
      continue;
    }
    if (!output.includes(expectedOutput)) {
      fail(`self-test ${flag} output must include ${expectedOutput}`);
    }
  }
}

if (errors.length > 0) {
  console.error("UI visual detector check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI visual detector check passed (${seenKinds.size} change kinds, ${seenPlatforms.size} platforms)`);
