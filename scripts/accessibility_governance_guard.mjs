#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const rawArgs = process.argv.slice(2);
const isSelfTest = process.env.CLAWIX_ACCESSIBILITY_GOVERNANCE_SELF_TEST === "1";
const allowedFlags = new Set([
  "--self-test",
  "--simulate-missing-axis",
  "--simulate-missing-surface",
  "--simulate-expired-gap",
  "--simulate-missing-generated-field",
  "--simulate-missing-detector-axis",
  "--simulate-private-data-leak",
  "--simulate-private-alias-without-evidence",
]);
const errors = [];

const requiredPlatforms = ["macos", "ios", "android", "web"];
const requiredAxes = [
  "screen-reader",
  "keyboard-navigation",
  "focus-order",
  "visible-focus",
  "contrast",
  "reduced-motion",
  "text-scaling",
  "semantic-labels",
  "time-alternatives",
  "agent-generated-ui",
];
const generatedContractFields = [
  "semanticName",
  "role",
  "keyboardReachability",
  "focusHandoff",
  "screenReaderSummary",
  "contrastContract",
  "reducedMotionBehavior",
  "textScalingBehavior",
  "timeAlternative",
  "validationEvidence",
];
const evidenceStatuses = ["contract_declared", "verified_public", "verified_private", "external_pending"];
const evidenceRefTypes = new Set(["path", "command", "hash", "attestation", "capture", "log", "validation"]);

for (const arg of rawArgs) {
  if (arg.startsWith("--") && !allowedFlags.has(arg)) {
    console.error(`Accessibility governance guard received unknown flag ${arg}.`);
    process.exit(1);
  }
}

function fail(message) {
  errors.push(message);
}

function readText(relativePath, base = rootDir) {
  const file = path.join(base, relativePath);
  if (!fs.existsSync(file)) {
    fail(`missing ${relativePath}`);
    return "";
  }
  return fs.readFileSync(file, "utf8");
}

function readJson(relativePath, base = rootDir) {
  const text = readText(relativePath, base);
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch (error) {
    fail(`${relativePath} is not valid JSON: ${error.message}`);
    return null;
  }
}

function exists(relativePath, base = rootDir) {
  return fs.existsSync(path.join(base, relativePath));
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

function requireUniqueStrings(values, label) {
  const seen = new Set();
  for (const value of values) {
    if (typeof value !== "string" || value.length === 0) {
      fail(`${label} must only include non-empty strings`);
      continue;
    }
    if (seen.has(value)) fail(`${label} duplicates ${value}`);
    seen.add(value);
  }
  return seen;
}

function requireIncludes(values, label, expected) {
  const seen = new Set(values);
  for (const value of expected) {
    if (!seen.has(value)) fail(`${label} must include ${value}`);
  }
}

function requireExactStringSet(values, label, expectedValues) {
  const seen = requireUniqueStrings(values, label);
  const expected = new Set(expectedValues);
  for (const value of seen) {
    if (!expected.has(value)) fail(`${label} must not include ${value}`);
  }
  for (const value of expected) {
    if (!seen.has(value)) fail(`${label} must include ${value}`);
  }
  return seen;
}

function validateEvidenceRef(ref, label) {
  if (!ref || typeof ref !== "object" || Array.isArray(ref)) {
    fail(`${label} entries must be objects`);
    return;
  }
  if (!evidenceRefTypes.has(ref.type)) fail(`${label}.type must be one of ${[...evidenceRefTypes].join(", ")}`);
  if (typeof ref.ref !== "string" || ref.ref.trim() === "") {
    fail(`${label}.ref must be non-empty`);
    return;
  }
  if (ref.ref.includes("/Users/") || ref.ref.includes("file://")) fail(`${label}.${ref.ref} must be public-safe`);
  if (/\bfixture\b|synthetic_templates_not_evidence/iu.test(ref.ref)) fail(`${label}.${ref.ref} cannot cite fixtures or synthetic templates as real evidence`);
  if (ref.type === "path" && !exists(ref.ref)) fail(`${label}.${ref.ref} path does not exist`);
  if (ref.type === "hash" && !/^sha256:[a-f0-9]{64}$/u.test(ref.ref)) fail(`${label}.${ref.ref} must be sha256:<64 lowercase hex>`);
  if ((ref.type === "command" || ref.type === "validation") && !/^(node scripts\/|bash scripts\/|bash macos\/scripts\/|bash ios\/scripts\/|bash linux\/scripts\/|pwsh windows\/scripts\/|npm run |swift test |claw verify )/u.test(ref.ref)) {
    fail(`${label}.${ref.ref} must be a known validation command`);
  }
}

function isFutureOrToday(value) {
  return typeof value === "string"
    && /^\d{4}-\d{2}-\d{2}$/.test(value)
    && value >= new Date().toISOString().slice(0, 10);
}

function validate(base = rootDir) {
  const matrixPath = "docs/accessibility/capability-matrix.manifest.json";
  const surfacePath = "docs/accessibility/surface-coverage.manifest.json";
  const generatedPath = "docs/accessibility/agent-generated-ui.manifest.json";
  const detectorsPath = "docs/accessibility/source-detectors.manifest.json";
  const uiInventoryPath = "docs/ui/visible-surfaces.inventory.json";

  const matrix = readJson(matrixPath, base);
  const surface = readJson(surfacePath, base);
  const generated = readJson(generatedPath, base);
  const detectors = readJson(detectorsPath, base);
  const uiInventory = readJson(uiInventoryPath, base);

  if (rawArgs.includes("--simulate-missing-axis") && Array.isArray(matrix?.requiredAxes)) {
    matrix.requiredAxes = matrix.requiredAxes.filter((axis) => axis.id !== "text-scaling");
  }
  if (rawArgs.includes("--simulate-missing-surface") && Array.isArray(surface?.coverage)) {
    surface.coverage = surface.coverage.filter((entry) => entry.surfaceId !== "web-screens");
  }
  if (rawArgs.includes("--simulate-private-alias-without-evidence") && Array.isArray(surface?.coverage)) {
    surface.coverage.push({
      surfaceId: "private-fixture",
      platform: "macos",
      axes: requiredAxes,
      evidenceAlias: "private-a11y-fixture",
      evidenceStatus: "verified_private",
      checks: ["node scripts/accessibility_governance_guard.mjs"],
      gaps: [],
    });
  }
  if (rawArgs.includes("--simulate-expired-gap") && Array.isArray(surface?.coverage)) {
    surface.coverage[0] = surface.coverage[0] || {};
    surface.coverage[0].gaps = [{ id: "expired", axes: ["screen-reader"], status: "EXTERNAL PENDING", reason: "fixture", expires: "2000-01-01" }];
  }
  if (rawArgs.includes("--simulate-missing-generated-field") && Array.isArray(generated?.requiredContractFields)) {
    generated.requiredContractFields = generated.requiredContractFields.filter((field) => field !== "focusHandoff");
  }
  if (rawArgs.includes("--simulate-missing-detector-axis") && Array.isArray(detectors?.detectors)) {
    detectors.detectors = detectors.detectors.filter((detector) => detector.axis !== "agent-generated-ui");
  }
  if (rawArgs.includes("--simulate-private-data-leak")) {
    matrix.privateDataPolicy = matrix.privateDataPolicy || {};
    matrix.privateDataPolicy.publicRepoMayStore = [...(matrix.privateDataPolicy.publicRepoMayStore || []), "raw screenshot"];
  }

  requireFields(matrix, matrixPath, ["schemaVersion", "status", "policy", "platforms", "constitutionPrinciple", "standardsReferences", "requiredAxes", "publicChecks", "privateDataPolicy"]);
  requireFields(surface, surfacePath, ["schemaVersion", "status", "policy", "capabilityMatrix", "visibleSurfaceInventory", "requiredAxes", "coverage"]);
  requireFields(generated, generatedPath, ["schemaVersion", "status", "policy", "appliesTo", "requiredContractFields", "defaultPolicy", "publicChecks", "externalPendingEvidence"]);
  requireFields(detectors, detectorsPath, ["schemaVersion", "status", "policy", "sourceRoots", "requiredAxes", "detectors"]);

  for (const [label, manifest] of [[matrixPath, matrix], [surfacePath, surface], [generatedPath, generated], [detectorsPath, detectors]]) {
    if (manifest?.schemaVersion !== 1) fail(`${label}.schemaVersion must be 1`);
    if (manifest?.status !== "active") fail(`${label}.status must be active`);
  }

  requireExactStringSet(requireArray(matrix, matrixPath, "platforms"), `${matrixPath}.platforms`, requiredPlatforms);
  requireExactStringSet(
    requireArray(matrix, matrixPath, "requiredAxes").map((axis) => axis?.id).filter(Boolean),
    `${matrixPath}.requiredAxes`,
    requiredAxes,
  );
  for (const axis of requireArray(matrix, matrixPath, "requiredAxes")) {
    requireFields(axis, `${matrixPath}.requiredAxes.${axis?.id || "<missing>"}`, ["id", "summary", "publicEvidence", "externalEvidence"]);
  }
  requireIncludes(requireArray(matrix, matrixPath, "publicChecks"), `${matrixPath}.publicChecks`, ["node scripts/accessibility_governance_guard.mjs"]);
  const mayStore = requireArray(matrix?.privateDataPolicy, `${matrixPath}.privateDataPolicy`, "publicRepoMayStore");
  const mustNotStore = requireArray(matrix?.privateDataPolicy, `${matrixPath}.privateDataPolicy`, "publicRepoMustNotStore");
  requireUniqueStrings(mayStore, `${matrixPath}.privateDataPolicy.publicRepoMayStore`);
  requireUniqueStrings(mustNotStore, `${matrixPath}.privateDataPolicy.publicRepoMustNotStore`);
  for (const privateItem of ["raw screen reader transcript", "raw screenshot", "local absolute path", "external approval artifact", "secret"]) {
    if (mayStore.includes(privateItem)) fail(`${matrixPath}.privateDataPolicy.publicRepoMayStore must not include ${privateItem}`);
    if (!mustNotStore.includes(privateItem)) fail(`${matrixPath}.privateDataPolicy.publicRepoMustNotStore must include ${privateItem}`);
  }

  if (surface?.capabilityMatrix !== matrixPath) fail(`${surfacePath}.capabilityMatrix must point to ${matrixPath}`);
  if (surface?.visibleSurfaceInventory !== uiInventoryPath) fail(`${surfacePath}.visibleSurfaceInventory must point to ${uiInventoryPath}`);
  requireExactStringSet(requireArray(surface, surfacePath, "requiredAxes"), `${surfacePath}.requiredAxes`, requiredAxes);

  const inventoryCoverage = requireArray(uiInventory, uiInventoryPath, "coverage");
  const inventoryIds = new Map(inventoryCoverage.map((entry) => [entry.id, entry.platform]));
  const coveredIds = new Set();
  for (const entry of requireArray(surface, surfacePath, "coverage")) {
    requireFields(entry, `${surfacePath}.coverage.${entry?.surfaceId || "<missing>"}`, ["surfaceId", "platform", "axes", "evidenceAlias", "evidenceStatus", "checks", "gaps"]);
    const syntheticPrivateFixture = isSelfTest && entry.surfaceId === "private-fixture";
    if (!syntheticPrivateFixture && !inventoryIds.has(entry.surfaceId)) fail(`${surfacePath}.coverage references unknown surface ${entry.surfaceId}`);
    if (inventoryIds.has(entry.surfaceId) && inventoryIds.get(entry.surfaceId) !== entry.platform) {
      fail(`${surfacePath}.coverage.${entry.surfaceId}.platform must match visible surface inventory`);
    }
    if (coveredIds.has(entry.surfaceId)) fail(`${surfacePath}.coverage duplicates ${entry.surfaceId}`);
    coveredIds.add(entry.surfaceId);
    requireExactStringSet(requireArray(entry, `${surfacePath}.coverage.${entry.surfaceId}`, "axes"), `${surfacePath}.coverage.${entry.surfaceId}.axes`, requiredAxes);
    requireIncludes(requireArray(entry, `${surfacePath}.coverage.${entry.surfaceId}`, "checks"), `${surfacePath}.coverage.${entry.surfaceId}.checks`, ["node scripts/accessibility_governance_guard.mjs"]);
    if (!evidenceStatuses.includes(entry.evidenceStatus)) {
      fail(`${surfacePath}.coverage.${entry.surfaceId}.evidenceStatus must be one of ${evidenceStatuses.join(", ")}`);
    }
    const gaps = requireArray(entry, `${surfacePath}.coverage.${entry.surfaceId}`, "gaps", { nonEmpty: false });
    if (gaps.length > 0 && entry.evidenceStatus !== "external_pending") {
      fail(`${surfacePath}.coverage.${entry.surfaceId}.evidenceStatus must be external_pending while gaps remain`);
    }
    if ((entry.evidenceStatus === "verified_public" || entry.evidenceStatus === "verified_private") && (!Array.isArray(entry.evidenceRefs) || entry.evidenceRefs.length === 0)) {
      fail(`${surfacePath}.coverage.${entry.surfaceId}.evidenceRefs must be non-empty for ${entry.evidenceStatus}`);
    }
    for (const ref of entry.evidenceRefs ?? []) validateEvidenceRef(ref, `${surfacePath}.coverage.${entry.surfaceId}.evidenceRefs`);
    if (entry.evidenceStatus === "verified_private") {
      const hasHash = (entry.evidenceRefs ?? []).some((ref) => ref.type === "hash");
      const hasVerifier = (entry.evidenceRefs ?? []).some((ref) => ref.type === "validation" || ref.type === "command");
      if (!hasHash || !hasVerifier) fail(`${surfacePath}.coverage.${entry.surfaceId}.verified_private evidence must include hash and verifier refs`);
    }
    for (const gap of gaps) {
      requireFields(gap, `${surfacePath}.coverage.${entry.surfaceId}.gaps.${gap?.id || "<missing>"}`, ["id", "axes", "status", "reason", "expires"]);
      if (gap.status !== "EXTERNAL PENDING") fail(`${surfacePath}.coverage.${entry.surfaceId}.gaps.${gap.id}.status must be EXTERNAL PENDING`);
      if (!isFutureOrToday(gap.expires)) fail(`${surfacePath}.coverage.${entry.surfaceId}.gaps.${gap.id}.expires must be an unexpired YYYY-MM-DD date`);
      requireIncludes(requiredAxes, `${surfacePath}.coverage.${entry.surfaceId}.gaps.${gap.id}.axes`, requireArray(gap, `${surfacePath}.coverage.${entry.surfaceId}.gaps.${gap.id}`, "axes"));
    }
  }
  for (const id of inventoryIds.keys()) {
    if (!coveredIds.has(id)) fail(`${surfacePath}.coverage must include visible surface ${id}`);
  }

  requireExactStringSet(requireArray(generated, generatedPath, "requiredContractFields"), `${generatedPath}.requiredContractFields`, generatedContractFields);
  requireIncludes(requireArray(generated, generatedPath, "publicChecks"), `${generatedPath}.publicChecks`, ["node scripts/accessibility_governance_guard.mjs"]);
  if (generated?.defaultPolicy?.visualCopyLayoutChanges !== "defer-to-docs-ui-governance") {
    fail(`${generatedPath}.defaultPolicy.visualCopyLayoutChanges must defer to docs UI governance`);
  }
  for (const pending of requireArray(generated, generatedPath, "externalPendingEvidence")) {
    requireFields(pending, `${generatedPath}.externalPendingEvidence.${pending?.id || "<missing>"}`, ["id", "status", "reason", "expires"]);
    if (pending.status !== "EXTERNAL PENDING") fail(`${generatedPath}.externalPendingEvidence.${pending.id}.status must be EXTERNAL PENDING`);
    if (!isFutureOrToday(pending.expires)) fail(`${generatedPath}.externalPendingEvidence.${pending.id}.expires must be an unexpired YYYY-MM-DD date`);
  }

  requireExactStringSet(requireArray(detectors, detectorsPath, "requiredAxes"), `${detectorsPath}.requiredAxes`, requiredAxes);
  const detectorAxes = new Set();
  const detectorPlatforms = new Set();
  for (const detector of requireArray(detectors, detectorsPath, "detectors")) {
    requireFields(detector, `${detectorsPath}.detectors.${detector?.id || "<missing>"}`, ["id", "platforms", "axis", "pattern", "reason"]);
    if (!requiredAxes.includes(detector.axis)) fail(`${detectorsPath}.detectors.${detector.id}.axis is not a required axis`);
    detectorAxes.add(detector.axis);
    for (const platform of requireArray(detector, `${detectorsPath}.detectors.${detector.id}`, "platforms")) {
      if (!requiredPlatforms.includes(platform)) fail(`${detectorsPath}.detectors.${detector.id}.platforms includes unknown platform ${platform}`);
      detectorPlatforms.add(platform);
    }
    try {
      new RegExp(detector.pattern);
    } catch (error) {
      fail(`${detectorsPath}.detectors.${detector.id}.pattern is not valid regex: ${error.message}`);
    }
  }
  requireIncludes([...detectorAxes], `${detectorsPath}.detectors axes`, requiredAxes);
  requireIncludes([...detectorPlatforms], `${detectorsPath}.detectors platforms`, requiredPlatforms);

  const readme = readText("docs/accessibility/README.md", base);
  for (const snippet of ["Constitution IX.8", "docs/adr/0010-interface-governance.md", "node scripts/accessibility_governance_guard.mjs"]) {
    if (!readme.includes(snippet)) fail(`docs/accessibility/README.md is missing ${snippet}`);
  }
  const audit = readText("docs/accessibility/completion-audit.md", base);
  if (!audit.includes("EXTERNAL PENDING")) fail("docs/accessibility/completion-audit.md must declare EXTERNAL PENDING evidence");
  const adr = readText("docs/adr/0029-accessibility-governance.md", base);
  for (const snippet of ["Status: accepted", "## Surface Parity", "## Performance Impact", "## Decision Tensions"]) {
    if (!adr.includes(snippet)) fail(`docs/adr/0029-accessibility-governance.md is missing ${snippet}`);
  }
  const skill = readText("skills/accessibility-governance/SKILL.md", base);
  for (const snippet of ["name: accessibility-governance", "Declare the accessibility impact", "docs/adr/0029-accessibility-governance.md"]) {
    if (!skill.includes(snippet)) fail(`skills/accessibility-governance/SKILL.md is missing ${snippet}`);
  }
}

function runSelfTests() {
  const selfTests = [
    ["--unknown-flag", "received unknown flag --unknown-flag"],
    ["--simulate-missing-axis", "capability-matrix.manifest.json.requiredAxes must include text-scaling"],
    ["--simulate-missing-surface", "surface-coverage.manifest.json.coverage must include visible surface web-screens"],
    ["--simulate-expired-gap", "expires must be an unexpired YYYY-MM-DD date"],
    ["--simulate-missing-generated-field", "agent-generated-ui.manifest.json.requiredContractFields must include focusHandoff"],
    ["--simulate-missing-detector-axis", "source-detectors.manifest.json.detectors axes must include agent-generated-ui"],
    ["--simulate-private-data-leak", "publicRepoMayStore must not include raw screenshot"],
    ["--simulate-private-alias-without-evidence", "evidenceRefs must be non-empty for verified_private"],
  ];
  const scriptPath = path.relative(rootDir, new URL(import.meta.url).pathname);
  for (const [flag, expectedOutput] of selfTests) {
    const result = spawnSync(process.execPath, [scriptPath, flag], {
      cwd: rootDir,
      encoding: "utf8",
      env: { ...process.env, CLAWIX_ACCESSIBILITY_GOVERNANCE_SELF_TEST: "1" },
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status === 0 || !output.includes(expectedOutput)) {
      console.error(`Accessibility governance self-test failed for ${flag}.`);
      if (output) console.error(output.trim());
      process.exit(1);
    }
  }
}

validate();

if (errors.length > 0) {
  console.error("Accessibility governance guard failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

if (!isSelfTest && (rawArgs.length === 0 || rawArgs.includes("--self-test"))) {
  runSelfTests();
}

console.log("accessibility governance guard passed");
