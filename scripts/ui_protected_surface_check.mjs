#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const rawArgs = process.argv.slice(2);
const args = new Set(rawArgs);
const isSelfTest = process.env.CLAWIX_UI_PROTECTED_SURFACE_SELF_TEST === "1";
const errors = [];
const simulationFlags = [
  "--simulate-wrong-private-baseline-alias",
  "--simulate-missing-required-freeze-field",
  "--simulate-wrong-freeze-contract-value",
  "--simulate-missing-approval-authority-source",
  "--simulate-missing-freeze-field",
  "--simulate-unknown-pattern",
  "--simulate-invalid-baseline-hash",
  "--simulate-disabled-change-policy",
  "--simulate-duplicate-surface-id",
  "--simulate-unsupported-platform",
  "--simulate-non-user-approval",
  "--simulate-invalid-approval-date",
  "--simulate-unsafe-private-reference",
  "--simulate-missing-contract-field",
  "--simulate-unstable-contract-value",
  "--simulate-disabled-visual-model-policy",
  "--simulate-disabled-scope-budget-policy",
  "--simulate-local-path-leak",
];
const allowedFlags = new Set(simulationFlags);

function fail(message) {
  errors.push(message);
}

for (const arg of rawArgs) {
  if (arg.startsWith("--") && !allowedFlags.has(arg)) {
    console.error(`UI protected surface check received unknown flag ${arg}.`);
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

function hasLocalPath(value) {
  return (
    typeof value === "string" &&
    (/^\/Users\//.test(value) || value.startsWith("~/") || value.startsWith("file://") || /^[A-Z]:\\/.test(value))
  );
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

function requireAlias(value, alias, label) {
  if (typeof value !== "string" || !value.startsWith(`${alias}:`)) {
    fail(`${label} must use ${alias}:`);
    return;
  }
  const suffix = value.slice(alias.length + 1);
  if (!suffix || suffix.startsWith("/") || suffix.startsWith("\\") || suffix.startsWith("~/") || suffix.includes("..") || /^[A-Z]:\\/.test(suffix)) {
    fail(`${label} must use a safe relative external reference`);
  }
  if (hasLocalPath(value)) {
    fail(`${label} must not contain a local path`);
  }
}

function requireHash(value, label) {
  if (typeof value !== "string" || !/^[a-f0-9]{64}$/i.test(value)) {
    fail(`${label} must be a 64-character hex hash`);
  }
}

function requireIsoDate(value, label) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value) || Number.isNaN(Date.parse(value))) {
    fail(`${label} must be an ISO date`);
  }
}

function runFailureSelfTests() {
  const selfTestEnv = { ...process.env, CLAWIX_UI_PROTECTED_SURFACE_SELF_TEST: "1" };
  const tests = [
    [["--unknown-flag"], "received unknown flag --unknown-flag"],
    [["--simulate-wrong-private-baseline-alias"], "externalBaselineAlias must be external-ui-baselines"],
    [["--simulate-missing-required-freeze-field"], "requiredFreezeFields must include changePolicy"],
    [["--simulate-wrong-freeze-contract-value"], "freezeContractValue must be stable"],
    [["--simulate-missing-approval-authority-source"], "approvalSources must include protected-surfaces"],
    [["--simulate-missing-freeze-field"], "is missing externalApprovalReference"],
    [["--simulate-unknown-pattern"], "patterns references unknown pattern unknown-pattern"],
    [["--simulate-invalid-baseline-hash"], "privateBaselineHash must be a 64-character hex hash"],
    [["--simulate-disabled-change-policy"], "changePolicy.requiresExplicitUserApproval must be true"],
    [["--simulate-duplicate-surface-id"], "id duplicates simulated-duplicate-surface"],
    [["--simulate-unsupported-platform"], "platform is not governed"],
    [["--simulate-non-user-approval"], "approvedBy must be user"],
    [["--simulate-invalid-approval-date"], "approvedAt must be an ISO date"],
    [["--simulate-unsafe-private-reference"], "externalBaselineReference must use a safe relative external reference"],
    [["--simulate-missing-contract-field"], "contract is missing performance"],
    [["--simulate-unstable-contract-value"], "contract.copy must be stable"],
    [["--simulate-disabled-visual-model-policy"], "changePolicy.requiresVisualModelAllowlist must be true"],
    [["--simulate-disabled-scope-budget-policy"], "changePolicy.requiresScopeBudget must be true"],
    [["--simulate-local-path-leak"], "scope must not contain a local path"],
  ];

  for (const [testArgs, expectedOutput] of tests) {
    const result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, ...testArgs], {
      cwd: rootDir,
      env: selfTestEnv,
      encoding: "utf8",
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status === 0) {
      fail(`self-test ${testArgs.join(" ")} must fail for protected surface validation`);
      continue;
    }
    if (!output.includes(expectedOutput)) {
      fail(`self-test ${testArgs.join(" ")} output must include ${expectedOutput}`);
    }
  }
}

if (!isSelfTest) runFailureSelfTests();

const requiredPlatforms = new Set(["macos", "ios", "android", "web"]);
const protectedPath = "docs/ui/protected-surfaces.registry.json";
const protectedSurfaces = readJson(protectedPath);
const approvalAuthorityPath = "docs/ui/approval-authority.manifest.json";
const approvalAuthority = readJson(approvalAuthorityPath);
requireFields(protectedSurfaces, protectedPath, [
  "schemaVersion",
  "status",
  "policy",
  "externalBaselineAlias",
  "privateCopyAlias",
  "externalGeometryAlias",
  "freezeContractValue",
  "requiredFreezeFields",
  "surfaces",
]);
if (args.has("--simulate-wrong-private-baseline-alias") && protectedSurfaces) {
  protectedSurfaces.externalBaselineAlias = "private-local-baselines";
}
if (args.has("--simulate-missing-required-freeze-field") && Array.isArray(protectedSurfaces?.requiredFreezeFields)) {
  protectedSurfaces.requiredFreezeFields = protectedSurfaces.requiredFreezeFields.filter((field) => field !== "changePolicy");
}
if (args.has("--simulate-wrong-freeze-contract-value") && protectedSurfaces) {
  protectedSurfaces.freezeContractValue = "mutable";
}

for (const [field, expected] of [
  ["externalBaselineAlias", "external-ui-baselines"],
  ["privateCopyAlias", "external-ui-copy-snapshots"],
  ["externalGeometryAlias", "external-ui-rendered-geometry"],
  ["freezeContractValue", "stable"],
]) {
  if (protectedSurfaces?.[field] !== expected) fail(`${protectedPath}.${field} must be ${expected}`);
}

const requiredFreezeFields = requireArray(protectedSurfaces, protectedPath, "requiredFreezeFields");
const requiredFreezeFieldSet = new Set(requiredFreezeFields);
for (const field of [
  "id",
  "scope",
  "platform",
  "patterns",
  "approvedBy",
  "approvedAt",
  "externalApprovalReference",
  "contract",
  "externalBaselineReference",
  "privateBaselineHash",
  "copySnapshotReference",
  "copySnapshotHash",
  "geometryEvidenceReference",
  "geometryEvidenceHash",
  "changePolicy",
]) {
  if (!requiredFreezeFieldSet.has(field)) fail(`${protectedPath}.requiredFreezeFields must include ${field}`);
}

const registry = readJson("docs/ui/pattern-registry/patterns.registry.json");
const patternIds = new Set(requireArray(registry, "docs/ui/pattern-registry/patterns.registry.json", "patterns"));
if (args.has("--simulate-missing-approval-authority-source") && Array.isArray(approvalAuthority?.approvalSources)) {
  approvalAuthority.approvalSources = approvalAuthority.approvalSources.filter((source) => source?.id !== "protected-surfaces");
}

function simulatedProtectedSurface(overrides = {}) {
  const hash = "a".repeat(64);
  return {
    id: "simulated-protected-surface",
    scope: "simulated surface",
    platform: "macos",
    patterns: ["sidebar-row"],
    approvedBy: "user",
    approvedAt: "2026-05-17",
    externalApprovalReference: "external-ui-approval:simulated",
    contract: {
      geometry: "stable",
      copy: "stable",
      states: "stable",
      performance: "stable",
    },
    externalBaselineReference: "external-ui-baselines:simulated",
    privateBaselineHash: hash,
    copySnapshotReference: "external-ui-copy-snapshots:simulated",
    copySnapshotHash: hash,
    geometryEvidenceReference: "external-ui-rendered-geometry:simulated",
    geometryEvidenceHash: hash,
    changePolicy: {
      requiresExplicitUserApproval: true,
      requiresVisualModelAllowlist: true,
      requiresScopeBudget: true,
    },
    ...overrides,
  };
}

function appendSimulatedSurface(overrides = {}) {
  protectedSurfaces.surfaces = [
    ...(Array.isArray(protectedSurfaces?.surfaces) ? protectedSurfaces.surfaces : []),
    simulatedProtectedSurface(overrides),
  ];
}

if (args.has("--simulate-missing-freeze-field")) {
  const simulated = simulatedProtectedSurface();
  delete simulated.externalApprovalReference;
  protectedSurfaces.surfaces = [
    ...(Array.isArray(protectedSurfaces?.surfaces) ? protectedSurfaces.surfaces : []),
    simulated,
  ];
}

if (args.has("--simulate-unknown-pattern")) {
  appendSimulatedSurface({ id: "simulated-unknown-pattern", patterns: ["unknown-pattern"] });
}

if (args.has("--simulate-invalid-baseline-hash")) {
  appendSimulatedSurface({ id: "simulated-invalid-baseline-hash", privateBaselineHash: "not-a-sha256" });
}

if (args.has("--simulate-disabled-change-policy")) {
  appendSimulatedSurface({
    id: "simulated-disabled-change-policy",
    changePolicy: {
      requiresExplicitUserApproval: false,
      requiresVisualModelAllowlist: true,
      requiresScopeBudget: true,
    },
  });
}

if (args.has("--simulate-duplicate-surface-id")) {
  appendSimulatedSurface({ id: "simulated-duplicate-surface" });
  appendSimulatedSurface({ id: "simulated-duplicate-surface", scope: "second simulated surface" });
}

if (args.has("--simulate-unsupported-platform")) {
  appendSimulatedSurface({ id: "simulated-unsupported-platform", platform: "visionos" });
}

if (args.has("--simulate-non-user-approval")) {
  appendSimulatedSurface({ id: "simulated-non-user-approval", approvedBy: "agent" });
}

if (args.has("--simulate-invalid-approval-date")) {
  appendSimulatedSurface({ id: "simulated-invalid-approval-date", approvedAt: "May 17 2026" });
}

if (args.has("--simulate-unsafe-private-reference")) {
  appendSimulatedSurface({
    id: "simulated-unsafe-private-reference",
    externalBaselineReference: "external-ui-baselines:../outside",
  });
}

if (args.has("--simulate-missing-contract-field")) {
  appendSimulatedSurface({
    id: "simulated-missing-contract-field",
    contract: { geometry: "stable", copy: "stable", states: "stable" },
  });
}

if (args.has("--simulate-unstable-contract-value")) {
  appendSimulatedSurface({
    id: "simulated-unstable-contract-value",
    contract: { geometry: "stable", copy: "mutable", states: "stable", performance: "stable" },
  });
}

if (args.has("--simulate-disabled-visual-model-policy")) {
  appendSimulatedSurface({
    id: "simulated-disabled-visual-model-policy",
    changePolicy: {
      requiresExplicitUserApproval: true,
      requiresVisualModelAllowlist: false,
      requiresScopeBudget: true,
    },
  });
}

if (args.has("--simulate-disabled-scope-budget-policy")) {
  appendSimulatedSurface({
    id: "simulated-disabled-scope-budget-policy",
    changePolicy: {
      requiresExplicitUserApproval: true,
      requiresVisualModelAllowlist: true,
      requiresScopeBudget: false,
    },
  });
}

if (args.has("--simulate-local-path-leak")) {
  appendSimulatedSurface({
    id: "simulated-local-path-leak",
    scope: "/Users/example/Desktop/Clawix/macos/Sources/Clawix/SidebarView.swift",
  });
}

const protectedApprovalSource = (approvalAuthority?.approvalSources || []).find((source) => source?.id === "protected-surfaces");
if (!protectedApprovalSource) {
  fail(`${approvalAuthorityPath}.approvalSources must include protected-surfaces`);
} else {
  if (protectedApprovalSource.path !== protectedPath) fail(`${approvalAuthorityPath}.approvalSources.protected-surfaces.path must be ${protectedPath}`);
  if (protectedApprovalSource.arrayField !== "surfaces") fail(`${approvalAuthorityPath}.approvalSources.protected-surfaces.arrayField must be surfaces`);
  if (protectedApprovalSource.approvedByField !== "approvedBy") fail(`${approvalAuthorityPath}.approvalSources.protected-surfaces.approvedByField must be approvedBy`);
  if (protectedApprovalSource.privateApprovalField !== "externalApprovalReference") {
    fail(`${approvalAuthorityPath}.approvalSources.protected-surfaces.privateApprovalField must be externalApprovalReference`);
  }
}

const surfaces = requireArray(protectedSurfaces, protectedPath, "surfaces", { nonEmpty: false });
const ids = new Set();
for (const [index, surface] of surfaces.entries()) {
  const label = `${protectedPath}.surfaces[${index}]`;
  requireFields(surface, label, requiredFreezeFields);
  if (ids.has(surface.id)) fail(`${label}.id duplicates ${surface.id}`);
  ids.add(surface.id);
  if (!requiredPlatforms.has(surface.platform)) fail(`${label}.platform is not governed`);
  if (surface.approvedBy !== "user") fail(`${label}.approvedBy must be user`);
  requireIsoDate(surface.approvedAt, `${label}.approvedAt`);
  requireAlias(surface.externalApprovalReference, "external-ui-approval", `${label}.externalApprovalReference`);
  for (const pattern of requireArray(surface, label, "patterns")) {
    if (!patternIds.has(pattern)) fail(`${label}.patterns references unknown pattern ${pattern}`);
  }
  requireFields(surface.contract, `${label}.contract`, ["geometry", "copy", "states", "performance"]);
  for (const field of ["geometry", "copy", "states", "performance"]) {
    if (surface.contract?.[field] !== protectedSurfaces.freezeContractValue) {
      fail(`${label}.contract.${field} must be ${protectedSurfaces.freezeContractValue}`);
    }
  }
  requireAlias(surface.externalBaselineReference, protectedSurfaces.externalBaselineAlias, `${label}.externalBaselineReference`);
  requireAlias(surface.copySnapshotReference, protectedSurfaces.privateCopyAlias, `${label}.copySnapshotReference`);
  requireAlias(surface.geometryEvidenceReference, protectedSurfaces.externalGeometryAlias, `${label}.geometryEvidenceReference`);
  requireHash(surface.privateBaselineHash, `${label}.privateBaselineHash`);
  requireHash(surface.copySnapshotHash, `${label}.copySnapshotHash`);
  requireHash(surface.geometryEvidenceHash, `${label}.geometryEvidenceHash`);
  requireFields(surface.changePolicy, `${label}.changePolicy`, [
    "requiresExplicitUserApproval",
    "requiresVisualModelAllowlist",
    "requiresScopeBudget",
  ]);
  if (surface.changePolicy.requiresExplicitUserApproval !== true) {
    fail(`${label}.changePolicy.requiresExplicitUserApproval must be true`);
  }
  if (surface.changePolicy.requiresVisualModelAllowlist !== true) {
    fail(`${label}.changePolicy.requiresVisualModelAllowlist must be true`);
  }
  if (surface.changePolicy.requiresScopeBudget !== true) {
    fail(`${label}.changePolicy.requiresScopeBudget must be true`);
  }
}

scanForLocalPaths(protectedSurfaces, protectedPath);

if (errors.length > 0) {
  console.error("UI protected surface check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI protected surface check passed (${surfaces.length} protected surfaces)`);
