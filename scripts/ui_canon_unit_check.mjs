#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const rawArgs = process.argv.slice(2);
const args = new Set(rawArgs);
const isSelfTest = process.env.CLAWIX_UI_CANON_UNIT_SELF_TEST === "1";
const errors = [];
const simulationFlags = [
  "--simulate-wrong-primary-unit",
  "--simulate-inactive-canon-units",
  "--simulate-absolute-pattern-registry",
  "--simulate-wrong-promotion-registry",
  "--simulate-wrong-approval-authority",
  "--simulate-missing-allowed-status",
  "--simulate-duplicate-allowed-status",
  "--simulate-missing-required-unit-field",
  "--simulate-duplicate-required-unit-field",
  "--simulate-duplicate-unit",
  "--simulate-unknown-unit",
  "--simulate-wrong-unit-source",
  "--simulate-wrong-unit-kind",
  "--simulate-primary-requires-promotion",
  "--simulate-narrower-no-promotion",
  "--simulate-missing-surface-unit",
  "--simulate-registry-wrong-notes-path",
  "--simulate-registry-missing-platform",
  "--simulate-registry-duplicate-pattern",
  "--simulate-pattern-missing-mutation-class",
  "--simulate-pattern-id-mismatch",
  "--simulate-pattern-unknown-mutation-class",
  "--simulate-pattern-duplicate-mutation-class",
  "--simulate-pattern-empty-canonical-references",
  "--simulate-promotion-unknown-pattern",
];
const allowedFlags = new Set(simulationFlags);

function fail(message) {
  errors.push(message);
}

for (const arg of rawArgs) {
  if (arg.startsWith("--") && !allowedFlags.has(arg)) {
    console.error(`UI canon unit check received unknown flag ${arg}.`);
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
  if (nonEmpty && value.length === 0) fail(`${label}.${field} must not be empty`);
  return value;
}

function requireUniqueStrings(values, label) {
  const seen = new Set();
  for (const [index, value] of values.entries()) {
    const entryLabel = `${label}[${index}]`;
    if (typeof value !== "string" || value === "") {
      fail(`${entryLabel} must be a non-empty string`);
      continue;
    }
    if (seen.has(value)) fail(`${entryLabel} duplicates ${value}`);
    seen.add(value);
  }
  return seen;
}

function requireExactStrings(values, label, expected) {
  const actual = requireArray({ values }, label, "values");
  requireUniqueStrings(actual, `${label}.values`);
  if (actual.length !== expected.length || actual.some((value, index) => value !== expected[index])) {
    fail(`${label} must match ${JSON.stringify(expected)}`);
  }
  return new Set(actual);
}

function requireRepoReference(reference, label) {
  if (typeof reference !== "string" || reference.length === 0) {
    fail(`${label} must be a repo-relative reference`);
    return;
  }
  if (path.isAbsolute(reference) || reference.startsWith("~/") || reference.includes("\\") || reference.includes("/Users/") || reference.includes(":")) {
    fail(`${label} must be public-safe and repo-relative`);
    return;
  }
  if (!fs.existsSync(path.join(rootDir, reference.split("#", 1)[0]))) {
    fail(`${label} points to missing target ${reference}`);
  }
}

function runFailureSelfTests() {
  const selfTestEnv = { ...process.env, CLAWIX_UI_CANON_UNIT_SELF_TEST: "1" };
  const tests = [
    [["--unknown-flag"], "received unknown flag --unknown-flag"],
    [["--simulate-wrong-primary-unit"], "primaryUnit must be pattern"],
    [["--simulate-inactive-canon-units"], "status must be active"],
    [["--simulate-absolute-pattern-registry"], "patternRegistry must be public-safe and repo-relative"],
    [["--simulate-wrong-promotion-registry"], "promotionRegistry must be docs/ui/canon-promotions.registry.json"],
    [["--simulate-wrong-approval-authority"], "approvalAuthority must be docs/ui/approval-authority.manifest.json"],
    [["--simulate-missing-allowed-status"], "allowedUnitStatuses must match"],
    [["--simulate-duplicate-allowed-status"], "allowedUnitStatuses.values[3] duplicates candidate"],
    [["--simulate-missing-required-unit-field"], "requiredUnitFields must match"],
    [["--simulate-duplicate-required-unit-field"], "requiredUnitFields.values[5] duplicates id"],
    [["--simulate-duplicate-unit"], "id duplicates pattern"],
    [["--simulate-unknown-unit"], "id is not a governed canon unit"],
    [["--simulate-wrong-unit-source"], "source must be docs/ui/component-extraction.manifest.json"],
    [["--simulate-wrong-unit-kind"], "unitKind must be narrower-unit"],
    [["--simulate-primary-requires-promotion"], "promotionRequired must be false for the primary canon unit"],
    [["--simulate-narrower-no-promotion"], "promotionRequired must be true for narrower canon units"],
    [["--simulate-missing-surface-unit"], "units must include surface"],
    [["--simulate-registry-wrong-notes-path"], "notesPath must be docs/ui/pattern-registry/patterns/notes.md"],
    [["--simulate-registry-missing-platform"], "platforms must match"],
    [["--simulate-registry-duplicate-pattern"], "patterns[16] duplicates sidebar-section"],
    [["--simulate-pattern-missing-mutation-class"], "mutationClass must be declared"],
    [["--simulate-pattern-id-mismatch"], "id must match sidebar-row"],
    [["--simulate-pattern-unknown-mutation-class"], "mutationClass contains unknown class unknown-ui"],
    [["--simulate-pattern-duplicate-mutation-class"], "mutationClass[1] duplicates visual-ui"],
    [["--simulate-pattern-empty-canonical-references"], "canonicalReferences must not be empty"],
    [["--simulate-promotion-unknown-pattern"], "patterns references unknown pattern unknown-pattern"],
  ];

  for (const [testArgs, expectedOutput] of tests) {
    const result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, ...testArgs], {
      cwd: rootDir,
      env: selfTestEnv,
      encoding: "utf8",
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status === 0) {
      fail(`self-test ${testArgs.join(" ")} must fail for UI canon unit validation`);
      continue;
    }
    if (!output.includes(expectedOutput)) {
      fail(`self-test ${testArgs.join(" ")} output must include ${expectedOutput}`);
    }
  }
}

if (!isSelfTest) runFailureSelfTests();

const manifestPath = "docs/ui/canon-units.manifest.json";
const manifest = readJson(manifestPath);
if (manifest) {
  if (args.has("--simulate-wrong-primary-unit")) {
    manifest.primaryUnit = "component";
  }
  if (args.has("--simulate-inactive-canon-units")) {
    manifest.status = "draft";
  }
  if (args.has("--simulate-absolute-pattern-registry")) {
    manifest.patternRegistry = "/Users/private/patterns.registry.json";
  }
  if (args.has("--simulate-wrong-promotion-registry")) {
    manifest.promotionRegistry = "docs/ui/promotions.registry.json";
  }
  if (args.has("--simulate-wrong-approval-authority")) {
    manifest.approvalAuthority = "docs/ui/approval.manifest.json";
  }
  if (args.has("--simulate-missing-allowed-status") && Array.isArray(manifest.allowedUnitStatuses)) {
    manifest.allowedUnitStatuses = manifest.allowedUnitStatuses.filter((status) => status !== "revoked");
  }
  if (args.has("--simulate-duplicate-allowed-status") && Array.isArray(manifest.allowedUnitStatuses)) {
    manifest.allowedUnitStatuses = [...manifest.allowedUnitStatuses, manifest.allowedUnitStatuses[0]];
  }
  if (args.has("--simulate-missing-required-unit-field") && Array.isArray(manifest.requiredUnitFields)) {
    manifest.requiredUnitFields = manifest.requiredUnitFields.filter((field) => field !== "promotionRequired");
  }
  if (args.has("--simulate-duplicate-required-unit-field") && Array.isArray(manifest.requiredUnitFields)) {
    manifest.requiredUnitFields = [...manifest.requiredUnitFields, manifest.requiredUnitFields[0]];
  }
  if (args.has("--simulate-duplicate-unit") && Array.isArray(manifest.units) && manifest.units[0]) {
    manifest.units.push({ ...manifest.units[0] });
  }
  if (args.has("--simulate-unknown-unit") && Array.isArray(manifest.units)) {
    manifest.units.push({
      id: "sub-pattern",
      unitKind: "narrower-unit",
      status: "candidate",
      source: "docs/ui/pattern-registry/patterns.registry.json",
      promotionRequired: true,
    });
  }
  if (args.has("--simulate-wrong-unit-source") && Array.isArray(manifest.units) && manifest.units[1]) {
    manifest.units[1] = { ...manifest.units[1], source: "docs/ui/pattern-registry/patterns.registry.json" };
  }
  if (args.has("--simulate-wrong-unit-kind") && Array.isArray(manifest.units) && manifest.units[1]) {
    manifest.units[1] = { ...manifest.units[1], unitKind: "primary-canon-unit" };
  }
  if (args.has("--simulate-primary-requires-promotion") && Array.isArray(manifest.units) && manifest.units[0]) {
    manifest.units[0] = { ...manifest.units[0], promotionRequired: true };
  }
  if (args.has("--simulate-narrower-no-promotion") && Array.isArray(manifest.units) && manifest.units[1]) {
    manifest.units[1] = { ...manifest.units[1], promotionRequired: false };
  }
  if (args.has("--simulate-missing-surface-unit") && Array.isArray(manifest.units)) {
    manifest.units = manifest.units.filter((unit) => unit.id !== "surface");
  }
}
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "primaryUnit",
  "patternRegistry",
  "promotionRegistry",
  "approvalAuthority",
  "allowedUnitStatuses",
  "requiredUnitFields",
  "units",
]);
if (manifest?.schemaVersion !== 1) fail(`${manifestPath}.schemaVersion must be 1`);
if (manifest?.status !== "active") fail(`${manifestPath}.status must be active`);
if (manifest?.primaryUnit !== "pattern") fail(`${manifestPath}.primaryUnit must be pattern`);
if (manifest?.patternRegistry !== "docs/ui/pattern-registry/patterns.registry.json") {
  fail(`${manifestPath}.patternRegistry must be docs/ui/pattern-registry/patterns.registry.json`);
}
if (manifest?.promotionRegistry !== "docs/ui/canon-promotions.registry.json") {
  fail(`${manifestPath}.promotionRegistry must be docs/ui/canon-promotions.registry.json`);
}
if (manifest?.approvalAuthority !== "docs/ui/approval-authority.manifest.json") {
  fail(`${manifestPath}.approvalAuthority must be docs/ui/approval-authority.manifest.json`);
}
for (const field of ["patternRegistry", "promotionRegistry", "approvalAuthority"]) {
  requireRepoReference(manifest?.[field], `${manifestPath}.${field}`);
}

const statuses = requireExactStrings(manifest?.allowedUnitStatuses || [], `${manifestPath}.allowedUnitStatuses`, ["candidate", "promoted", "revoked"]);
const requiredFields = [...requireExactStrings(
  manifest?.requiredUnitFields || [],
  `${manifestPath}.requiredUnitFields`,
  ["id", "unitKind", "status", "source", "promotionRequired"],
)];

const expectedUnits = new Map([
  ["pattern", { unitKind: "primary-canon-unit", status: "promoted", source: "docs/ui/pattern-registry/patterns.registry.json", promotionRequired: false }],
  ["component", { unitKind: "narrower-unit", status: "candidate", source: "docs/ui/component-extraction.manifest.json", promotionRequired: true }],
  ["surface", { unitKind: "narrower-unit", status: "candidate", source: "docs/ui/protected-surfaces.registry.json", promotionRequired: true }],
]);
const unitsById = new Map();
for (const [index, unit] of requireArray(manifest, manifestPath, "units").entries()) {
  const label = `${manifestPath}.units[${index}]`;
  requireFields(unit, label, requiredFields);
  if (unitsById.has(unit.id)) fail(`${label}.id duplicates ${unit.id}`);
  unitsById.set(unit.id, unit);
  const expectedUnit = expectedUnits.get(unit.id);
  if (!expectedUnit) {
    fail(`${label}.id is not a governed canon unit`);
    continue;
  }
  for (const field of ["unitKind", "status", "source", "promotionRequired"]) {
    if (unit[field] !== expectedUnit[field]) fail(`${label}.${field} must be ${expectedUnit[field]}`);
  }
  if (!statuses.has(unit.status)) fail(`${label}.status is invalid`);
  requireRepoReference(unit.source, `${label}.source`);
  if (unit.id === manifest.primaryUnit && unit.promotionRequired !== false) {
    fail(`${label}.promotionRequired must be false for the primary canon unit`);
  }
  if (unit.id !== manifest.primaryUnit && unit.promotionRequired !== true) {
    fail(`${label}.promotionRequired must be true for narrower canon units`);
  }
}
for (const requiredUnit of expectedUnits.keys()) {
  if (!unitsById.has(requiredUnit)) fail(`${manifestPath}.units must include ${requiredUnit}`);
}

const registry = readJson(manifest?.patternRegistry || "docs/ui/pattern-registry/patterns.registry.json");
if (registry && args.has("--simulate-registry-wrong-notes-path")) {
  registry.notesPath = "docs/ui/pattern-registry/notes.md";
}
if (registry && args.has("--simulate-registry-missing-platform") && Array.isArray(registry.platforms)) {
  registry.platforms = registry.platforms.filter((platform) => platform !== "web");
}
if (registry && args.has("--simulate-registry-duplicate-pattern") && Array.isArray(registry.patterns) && registry.patterns[0]) {
  registry.patterns = [...registry.patterns, registry.patterns[0]];
}
if (registry && args.has("--simulate-pattern-missing-mutation-class") && Array.isArray(registry.patterns)) {
  registry.patterns = ["sidebar-row", ...registry.patterns.filter((patternId) => patternId !== "sidebar-row")];
}
if (registry?.schemaVersion !== 1) fail(`${manifest.patternRegistry}.schemaVersion must be 1`);
if (registry?.notesPath !== "docs/ui/pattern-registry/patterns/notes.md") {
  fail(`${manifest.patternRegistry}.notesPath must be docs/ui/pattern-registry/patterns/notes.md`);
}
requireRepoReference(registry?.notesPath, `${manifest.patternRegistry}.notesPath`);
requireExactStrings(registry?.platforms || [], `${manifest.patternRegistry}.platforms`, ["macos", "ios", "android", "web"]);
const registryPatternIds = requireUniqueStrings(requireArray(registry, manifest.patternRegistry, "patterns"), `${manifest.patternRegistry}.patterns`);
const governanceConfig = readJson("docs/ui/interface-governance.config.json");
const allowedMutationClasses = new Set(requireArray(governanceConfig, "docs/ui/interface-governance.config.json", "mutationClasses"));
for (const patternId of registryPatternIds) {
  const pattern = readJson(`docs/ui/pattern-registry/patterns/${patternId}.pattern.json`);
  if (pattern && args.has("--simulate-pattern-id-mismatch") && patternId === "sidebar-row") {
    pattern.id = "sidebar-row-copy";
  }
  if (pattern && args.has("--simulate-pattern-missing-mutation-class") && patternId === "sidebar-row") {
    delete pattern.mutationClass;
  }
  if (pattern && args.has("--simulate-pattern-unknown-mutation-class") && patternId === "sidebar-row") {
    pattern.mutationClass = ["visual-ui", "unknown-ui"];
  }
  if (pattern && args.has("--simulate-pattern-duplicate-mutation-class") && patternId === "sidebar-row") {
    pattern.mutationClass = ["visual-ui", "visual-ui"];
  }
  if (pattern && args.has("--simulate-pattern-empty-canonical-references") && patternId === "sidebar-row") {
    pattern.canonicalReferences = [];
  }
  requireFields(pattern, `docs/ui/pattern-registry/patterns/${patternId}.pattern.json`, [
    "schemaVersion",
    "id",
    "status",
    "platforms",
    "mutationClass",
    "canonicalReferences",
  ]);
  if (pattern?.schemaVersion !== 1) fail(`docs/ui/pattern-registry/patterns/${patternId}.pattern.json.schemaVersion must be 1`);
  if (pattern?.id !== patternId) fail(`docs/ui/pattern-registry/patterns/${patternId}.pattern.json.id must match ${patternId}`);
  for (const platform of requireUniqueStrings(requireArray(pattern, `docs/ui/pattern-registry/patterns/${patternId}.pattern.json`, "platforms"), `docs/ui/pattern-registry/patterns/${patternId}.pattern.json.platforms`)) {
    if (!["macos", "ios", "android", "web"].includes(platform)) {
      fail(`docs/ui/pattern-registry/patterns/${patternId}.pattern.json.platforms contains unknown platform ${platform}`);
    }
  }
  for (const [referenceIndex, reference] of requireArray(pattern, `docs/ui/pattern-registry/patterns/${patternId}.pattern.json`, "canonicalReferences").entries()) {
    requireRepoReference(reference, `docs/ui/pattern-registry/patterns/${patternId}.pattern.json.canonicalReferences[${referenceIndex}]`);
  }
  const mutationClasses = Array.isArray(pattern?.mutationClass)
    ? pattern.mutationClass
    : typeof pattern?.mutationClass === "string"
      ? [pattern.mutationClass]
      : [];
  if (mutationClasses.length === 0) {
    fail(`docs/ui/pattern-registry/patterns/${patternId}.pattern.json.mutationClass must be declared`);
  }
  for (const mutationClass of requireUniqueStrings(mutationClasses, `docs/ui/pattern-registry/patterns/${patternId}.pattern.json.mutationClass`)) {
    if (!allowedMutationClasses.has(mutationClass)) {
      fail(`docs/ui/pattern-registry/patterns/${patternId}.pattern.json.mutationClass contains unknown class ${mutationClass}`);
    }
  }
}

const promotions = readJson(manifest?.promotionRegistry || "docs/ui/canon-promotions.registry.json");
if (promotions && args.has("--simulate-promotion-unknown-pattern")) {
  promotions.promotions = [
    ...(Array.isArray(promotions.promotions) ? promotions.promotions : []),
    {
      patterns: ["unknown-pattern"],
      externalApprovalReference: "external-ui-approvals:canon/unknown-pattern",
    },
  ];
}
for (const [index, promotion] of requireArray(promotions, manifest.promotionRegistry, "promotions", { nonEmpty: false }).entries()) {
  const label = `${manifest.promotionRegistry}.promotions[${index}]`;
  requireFields(promotion, label, ["patterns", "externalApprovalReference"]);
  for (const patternId of requireArray(promotion, label, "patterns")) {
    if (!registryPatternIds.has(patternId)) fail(`${label}.patterns references unknown pattern ${patternId}`);
  }
}

if (errors.length > 0) {
  console.error("UI canon unit check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI canon unit check passed (${unitsById.size} units)`);
