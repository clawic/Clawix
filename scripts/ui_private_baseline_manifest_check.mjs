#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const manifestPath = "docs/ui/private-baselines.manifest.json";
const args = new Set(process.argv.slice(2));
const errors = [];

const requiredPlatforms = ["macos", "ios", "android", "web"];
const requiredFlows = [
  "sidebar-hover-click-expand",
  "chat-scroll",
  "composer-typing",
  "dropdown-open",
  "terminal-sidebar-switch",
  "right-sidebar-browser-use",
];
const requiredEvidence = [
  "flowId",
  "platform",
  "privateBaselineReference",
  "captureCommand",
  "geometryHash",
  "screenshotHash",
  "baselineArtifactHash",
  "approvedByUserAt",
  "approvedScope",
];

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

function requireFields(object, label, fields) {
  if (!object) return;
  for (const field of fields) {
    if (object[field] === undefined || object[field] === null || object[field] === "") {
      fail(`${label} is missing ${field}`);
    }
  }
}

function requireArray(object, label, field) {
  const value = object?.[field];
  if (!Array.isArray(value)) {
    fail(`${label}.${field} must be an array`);
    return [];
  }
  if (value.length === 0) {
    fail(`${label}.${field} must not be empty`);
  }
  return value;
}

function requireExactStringSet(values, label, expectedValues) {
  const expected = new Set(expectedValues);
  const seen = new Set();
  for (const value of values) {
    if (typeof value !== "string" || value.length === 0) {
      fail(`${label} must only include non-empty strings`);
      continue;
    }
    if (seen.has(value)) fail(`${label} duplicates ${value}`);
    seen.add(value);
    if (!expected.has(value)) fail(`${label} must not include ${value}`);
  }
  for (const value of expected) {
    if (!seen.has(value)) fail(`${label} must include ${value}`);
  }
  if (seen.size !== expected.size) fail(`${label} must exactly match approved values`);
  return seen;
}

function hasAbsolutePath(value) {
  return typeof value === "string" && (/^\/Users\//.test(value) || value.startsWith("~/") || /^[A-Z]:\\/.test(value) || value.startsWith("file://"));
}

function scanForAbsolutePaths(value, label) {
  if (Array.isArray(value)) {
    value.forEach((item, index) => scanForAbsolutePaths(item, `${label}[${index}]`));
    return;
  }
  if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) scanForAbsolutePaths(child, `${label}.${key}`);
    return;
  }
  if (hasAbsolutePath(value)) fail(`${label} must not contain a local absolute path`);
}

function assertPublicSafeReference(reference, alias, label) {
  if (typeof reference !== "string" || !reference.startsWith(`${alias}:`)) {
    fail(`${label} must use ${alias}:`);
    return null;
  }
  const suffix = reference.slice(alias.length + 1);
  if (!suffix || suffix.startsWith("/") || suffix.startsWith("\\") || suffix.startsWith("~/") || suffix.includes("..") || /^[A-Z]:\\/.test(suffix)) {
    fail(`${label} must use a safe relative private reference`);
  }
  if (hasAbsolutePath(reference) || reference.includes("/Users/")) {
    fail(`${label} must not contain a local absolute path`);
  }
  return suffix;
}

const manifest = readJson(manifestPath);
const decisionVerificationPath = "docs/ui/decision-verification.json";
const decisionVerification = readJson(decisionVerificationPath);
const visualBaselinesDecision = (decisionVerification?.decisions || []).find((decision) => decision?.id === "visual_baselines_location");
if (manifest) {
  if (args.has("--simulate-wrong-manifest-status")) {
    manifest.status = "active";
  }
  if (args.has("--simulate-wrong-private-root-alias")) {
    manifest.privateRootAlias = "private-codex-ui-rendered-geometry";
  }
  if (args.has("--simulate-verifier-without-approval")) {
    manifest.verificationCommand = "CLAWIX_UI_PRIVATE_BASELINE_ROOT=<private-root> node scripts/ui_private_baseline_verify.mjs";
  }
  if (args.has("--simulate-missing-required-evidence-field") && Array.isArray(manifest.requiredEvidenceFields)) {
    manifest.requiredEvidenceFields = manifest.requiredEvidenceFields.filter((field) => field !== "approvedScope");
  }
  if (args.has("--simulate-extra-required-evidence-field") && Array.isArray(manifest.requiredEvidenceFields)) {
    manifest.requiredEvidenceFields.push("localBaselinePath");
  }
  if (args.has("--simulate-duplicate-required-evidence-field") && Array.isArray(manifest.requiredEvidenceFields) && manifest.requiredEvidenceFields[0]) {
    manifest.requiredEvidenceFields.push(manifest.requiredEvidenceFields[0]);
  }
  if (args.has("--simulate-missing-critical-flow") && Array.isArray(manifest.flows)) {
    manifest.flows = manifest.flows.filter((flow) => !(flow?.platform === "web" && flow?.id === "right-sidebar-browser-use"));
  }
  if (args.has("--simulate-duplicate-critical-flow") && Array.isArray(manifest.flows) && manifest.flows[0]) {
    manifest.flows.push({ ...manifest.flows[0] });
  }
  if (args.has("--simulate-flow-extra-required-evidence") && Array.isArray(manifest.flows) && manifest.flows[0]) {
    manifest.flows[0].requiredEvidence = [...manifest.flows[0].requiredEvidence, "localBaselinePath"];
  }
  if (args.has("--simulate-flow-duplicate-required-evidence") && Array.isArray(manifest.flows) && manifest.flows[0]?.requiredEvidence?.[0]) {
    manifest.flows[0].requiredEvidence = [...manifest.flows[0].requiredEvidence, manifest.flows[0].requiredEvidence[0]];
  }
  if (args.has("--simulate-wrong-runner-id") && Array.isArray(manifest.flows) && manifest.flows[0]) {
    manifest.flows[0].runnerId = "shared-private-visual-baseline";
  }
  if (args.has("--simulate-wrong-geometry-tolerance") && Array.isArray(manifest.flows) && manifest.flows[0]) {
    manifest.flows[0].tolerance = { ...manifest.flows[0].tolerance, geometryPixels: 1 };
  }
  if (args.has("--simulate-wrong-screenshot-tolerance") && Array.isArray(manifest.flows) && manifest.flows[0]) {
    manifest.flows[0].tolerance = { ...manifest.flows[0].tolerance, screenshotDiff: "public-threshold" };
  }
  if (args.has("--simulate-unsafe-baseline-reference") && Array.isArray(manifest.flows) && manifest.flows[0]) {
    manifest.flows[0].privateBaselineReference = `${manifest.privateRootAlias}:../baseline`;
  }
  if (args.has("--simulate-invalid-baseline-status") && Array.isArray(manifest.flows) && manifest.flows[0]) {
    manifest.flows[0].baselineStatus = "captured-without-user";
  }
  if (args.has("--simulate-approved-pending-reference") && Array.isArray(manifest.flows) && manifest.flows[0]) {
    manifest.flows[0].baselineStatus = "approved";
    manifest.flows[0].privateBaselineReference = `${manifest.privateRootAlias}:${manifest.flows[0].platform}/pending-${manifest.flows[0].id}`;
  }
  if (args.has("--simulate-approved-manifest-with-pending-flow")) {
    manifest.status = "approved-private-baselines";
  }
  if (args.has("--simulate-pending-manifest-with-all-approved") && Array.isArray(manifest.flows)) {
    manifest.status = "pending-private-capture";
    manifest.flows = manifest.flows.map((flow) => ({
      ...flow,
      baselineStatus: "approved",
    }));
  }
  if (args.has("--simulate-local-private-artifact-path")) {
    manifest.privateArtifactPolicy = manifest.privateArtifactPolicy || {};
    manifest.privateArtifactPolicy.example = "/Users/example/private-baseline.png";
  }
  if (args.has("--simulate-extra-public-store") && Array.isArray(manifest.privateArtifactPolicy?.publicRepoMayStore)) {
    manifest.privateArtifactPolicy.publicRepoMayStore.push("raw-screenshot");
  }
  if (args.has("--simulate-duplicate-public-store") && Array.isArray(manifest.privateArtifactPolicy?.publicRepoMayStore) && manifest.privateArtifactPolicy.publicRepoMayStore[0]) {
    manifest.privateArtifactPolicy.publicRepoMayStore.push(manifest.privateArtifactPolicy.publicRepoMayStore[0]);
  }
  if (args.has("--simulate-extra-public-forbidden-store") && Array.isArray(manifest.privateArtifactPolicy?.publicRepoMustNotStore)) {
    manifest.privateArtifactPolicy.publicRepoMustNotStore.push("workspace-id");
  }
  if (args.has("--simulate-duplicate-public-forbidden-store") && Array.isArray(manifest.privateArtifactPolicy?.publicRepoMustNotStore) && manifest.privateArtifactPolicy.publicRepoMustNotStore[0]) {
    manifest.privateArtifactPolicy.publicRepoMustNotStore.push(manifest.privateArtifactPolicy.publicRepoMustNotStore[0]);
  }
  if (args.has("--simulate-baselines-decision-missing-manifest") && visualBaselinesDecision) {
    visualBaselinesDecision.publicEvidence = visualBaselinesDecision.publicEvidence.filter((evidencePath) => evidencePath !== manifestPath);
  }
  if (args.has("--simulate-baselines-decision-missing-private-visual") && visualBaselinesDecision) {
    visualBaselinesDecision.publicEvidence = visualBaselinesDecision.publicEvidence.filter(
      (evidencePath) =>
        evidencePath !== "docs/ui/private-visual-validation.manifest.json" &&
        evidencePath !== "scripts/ui_private_visual_verify.mjs",
    );
    visualBaselinesDecision.blockingVerifiers = visualBaselinesDecision.blockingVerifiers.filter(
      (verifier) => verifier !== "scripts/ui_private_visual_verify.mjs",
    );
  }
  if (args.has("--simulate-baselines-decision-missing-private-baseline-verifier") && visualBaselinesDecision) {
    visualBaselinesDecision.publicEvidence = visualBaselinesDecision.publicEvidence.filter(
      (evidencePath) => evidencePath !== "scripts/ui_private_baseline_verify.mjs",
    );
    visualBaselinesDecision.blockingVerifiers = visualBaselinesDecision.blockingVerifiers.filter(
      (verifier) => verifier !== "scripts/ui_private_baseline_verify.mjs",
    );
  }
  if (args.has("--simulate-baselines-decision-missing-platform-evidence") && visualBaselinesDecision) {
    visualBaselinesDecision.privateEvidence = visualBaselinesDecision.privateEvidence.filter(
      (evidenceReference) => evidenceReference !== "private-codex-ui-baselines:web/*",
    );
  }
  if (args.has("--simulate-baselines-decision-premature-complete") && visualBaselinesDecision) {
    visualBaselinesDecision.status = "verified-complete";
    visualBaselinesDecision.remaining = [];
  }
}
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "privateRootAlias",
  "evidenceFilename",
  "verificationCommand",
  "privateArtifactPolicy",
  "requiredEvidenceFields",
  "flows",
]);

if (!["pending-private-capture", "approved-private-baselines"].includes(manifest?.status)) {
  fail(`${manifestPath}.status must be pending-private-capture or approved-private-baselines`);
}
if (manifest?.privateRootAlias !== "private-codex-ui-baselines") {
  fail(`${manifestPath}.privateRootAlias must use the public-safe private alias`);
}
if (manifest?.evidenceFilename !== "evidence.json") {
  fail(`${manifestPath}.evidenceFilename must be evidence.json`);
}
if (!String(manifest?.verificationCommand || "").includes("scripts/ui_private_baseline_verify.mjs")) {
  fail(`${manifestPath}.verificationCommand must run scripts/ui_private_baseline_verify.mjs`);
}
if (!String(manifest?.verificationCommand || "").includes("--require-approved")) {
  fail(`${manifestPath}.verificationCommand must require approved private baseline evidence`);
}

const artifactPolicy = manifest?.privateArtifactPolicy || {};
requireExactStringSet(
  requireArray(artifactPolicy, `${manifestPath}.privateArtifactPolicy`, "publicRepoMayStore"),
  `${manifestPath}.privateArtifactPolicy.publicRepoMayStore`,
  ["manifest", "metadata", "hash", "tolerance", "runner-id", "approval-record-reference"],
);
requireExactStringSet(
  requireArray(artifactPolicy, `${manifestPath}.privateArtifactPolicy`, "publicRepoMustNotStore"),
  `${manifestPath}.privateArtifactPolicy.publicRepoMustNotStore`,
  ["raw-screenshot", "raw-video", "raw-trace", "local-absolute-path", "secret", "signing-identity"],
);

const evidenceFields = requireExactStringSet(
  requireArray(manifest, manifestPath, "requiredEvidenceFields"),
  `${manifestPath}.requiredEvidenceFields`,
  requiredEvidence,
);

const coverage = new Set();
let approvedFlowCount = 0;
let pendingFlowCount = 0;
for (const [index, flow] of requireArray(manifest, manifestPath, "flows").entries()) {
  const label = `${manifestPath}.flows[${index}]`;
  requireFields(flow, label, [
    "id",
    "platform",
    "baselineStatus",
    "privateBaselineReference",
    "runnerId",
    "requiredEvidence",
    "tolerance",
  ]);
  if (!requiredFlows.includes(flow.id)) fail(`${label}.id is not a required critical flow`);
  if (!requiredPlatforms.includes(flow.platform)) fail(`${label}.platform is not governed`);
  if (coverage.has(`${flow.platform}:${flow.id}`)) fail(`${label} duplicates ${flow.platform}:${flow.id}`);
  coverage.add(`${flow.platform}:${flow.id}`);
  const referenceSuffix = assertPublicSafeReference(flow.privateBaselineReference, manifest.privateRootAlias, `${label}.privateBaselineReference`);
  if (referenceSuffix && referenceSuffix !== `${flow.platform}/${flow.id}`) {
    fail(`${label}.privateBaselineReference must target ${flow.platform}/${flow.id}`);
  }
  requireExactStringSet(requireArray(flow, label, "requiredEvidence"), `${label}.requiredEvidence`, [...evidenceFields]);
  if (flow.runnerId !== `${flow.platform}-private-visual-baseline`) {
    fail(`${label}.runnerId must be ${flow.platform}-private-visual-baseline`);
  }
  if (flow.baselineStatus !== "pending-user-approved-capture" && flow.baselineStatus !== "approved") {
    fail(`${label}.baselineStatus must be pending-user-approved-capture or approved`);
  }
  if (flow.baselineStatus === "approved") approvedFlowCount += 1;
  if (flow.baselineStatus === "pending-user-approved-capture") pendingFlowCount += 1;
  if (flow.baselineStatus === "approved" && String(flow.privateBaselineReference).includes("pending")) {
    fail(`${label}.privateBaselineReference cannot be pending when approved`);
  }
  if (flow?.tolerance?.geometryPixels !== 0) {
    fail(`${label}.tolerance.geometryPixels must be 0`);
  }
  if (flow?.tolerance?.screenshotDiff !== "private-threshold") {
    fail(`${label}.tolerance.screenshotDiff must be private-threshold`);
  }
}

if (manifest?.status === "approved-private-baselines" && pendingFlowCount > 0) {
  fail(`${manifestPath}.status cannot be approved-private-baselines while ${pendingFlowCount} baseline flows are pending`);
}
if (manifest?.status === "pending-private-capture" && coverage.size > 0 && approvedFlowCount === coverage.size) {
  fail(`${manifestPath}.status must be approved-private-baselines when all baseline flows are approved`);
}

for (const platform of requiredPlatforms) {
  for (const flow of requiredFlows) {
    if (!coverage.has(`${platform}:${flow}`)) {
      fail(`${manifestPath}.flows must include ${platform}:${flow}`);
    }
  }
}

scanForAbsolutePaths(manifest, manifestPath);

const privateRootAlias = manifest?.privateRootAlias || "private-codex-ui-baselines";
if (!visualBaselinesDecision) {
  fail(`${decisionVerificationPath}.decisions must include visual_baselines_location`);
} else {
  const publicEvidence = new Set(Array.isArray(visualBaselinesDecision.publicEvidence) ? visualBaselinesDecision.publicEvidence : []);
  for (const evidencePath of [
    "docs/ui/interface-governance.config.json",
    manifestPath,
    "docs/ui/private-visual-validation.manifest.json",
    "scripts/ui_private_baseline_manifest_check.mjs",
    "scripts/ui_private_evidence_plan_check.mjs",
    "scripts/ui_private_evidence_verify.mjs",
    "scripts/ui_private_visual_validation_manifest_check.mjs",
    "scripts/ui_private_visual_verify.mjs",
    "scripts/ui_private_baseline_verify.mjs",
    "scripts/ui_private_drift_verify.mjs",
  ]) {
    if (!publicEvidence.has(evidencePath)) {
      fail(`${decisionVerificationPath}.decisions.visual_baselines_location.publicEvidence must include ${evidencePath}`);
    }
  }
  const privateEvidence = new Set(Array.isArray(visualBaselinesDecision.privateEvidence) ? visualBaselinesDecision.privateEvidence : []);
  for (const evidenceReference of [
    `${privateRootAlias}:macos/*`,
    `${privateRootAlias}:ios/*`,
    `${privateRootAlias}:android/*`,
    `${privateRootAlias}:web/*`,
    `${privateRootAlias}:surfaces/*`,
    "private-codex-ui-rendered-drift:surfaces/*",
  ]) {
    if (!privateEvidence.has(evidenceReference)) {
      fail(`${decisionVerificationPath}.decisions.visual_baselines_location.privateEvidence must include ${evidenceReference}`);
    }
  }
  const blockingVerifiers = new Set(Array.isArray(visualBaselinesDecision.blockingVerifiers) ? visualBaselinesDecision.blockingVerifiers : []);
  for (const verifier of [
    "scripts/ui_private_evidence_verify.mjs",
    "scripts/ui_private_baseline_verify.mjs",
    "scripts/ui_private_drift_verify.mjs",
    "scripts/ui_private_visual_verify.mjs",
  ]) {
    if (!blockingVerifiers.has(verifier)) {
      fail(`${decisionVerificationPath}.decisions.visual_baselines_location.blockingVerifiers must include ${verifier}`);
    }
  }
  if (manifest?.status !== "approved-private-baselines" && visualBaselinesDecision.status !== "open") {
    fail(`${decisionVerificationPath}.decisions.visual_baselines_location.status must remain open until private baselines are captured and approved`);
  }
  if (manifest?.status !== "approved-private-baselines" && (!Array.isArray(visualBaselinesDecision.remaining) || visualBaselinesDecision.remaining.length === 0)) {
    fail(`${decisionVerificationPath}.decisions.visual_baselines_location.remaining must describe pending private baseline evidence`);
  }
}

const forbiddenPrivateAssets = [];
for (const file of fs.readdirSync(path.join(rootDir, "docs/ui"), { recursive: true, withFileTypes: true })) {
  if (!file.isFile()) continue;
  const name = file.name.toLowerCase();
  if (/\.(png|jpg|jpeg|gif|webp|mov|mp4|trace)$/.test(name)) {
    forbiddenPrivateAssets.push(file.name);
  }
}
if (forbiddenPrivateAssets.length > 0) {
  fail(`docs/ui must not contain private baseline media: ${forbiddenPrivateAssets.join(", ")}`);
}

if (errors.length > 0) {
  console.error("UI private baseline manifest check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("UI private baseline manifest check passed");
