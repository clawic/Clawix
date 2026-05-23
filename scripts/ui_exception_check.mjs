#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const today = new Date().toISOString().slice(0, 10);
const rawArgs = process.argv.slice(2);
const args = new Set(rawArgs);
const isSelfTest = process.env.CLAWIX_UI_EXCEPTION_SELF_TEST === "1";
const errors = [];
const simulationFlags = [
  "--simulate-missing-exception-status",
  "--simulate-missing-required-exception-field",
  "--simulate-missing-allowed-action-policy",
  "--simulate-missing-approval-authority-source",
  "--simulate-unreferenced-active-exception",
  "--simulate-expired-active-exception",
  "--simulate-duplicate-exception-id",
  "--simulate-unsupported-platform",
  "--simulate-local-private-approval-reference",
  "--simulate-invalid-status",
  "--simulate-non-user-approval",
  "--simulate-invalid-approval-date",
  "--simulate-created-after-review",
  "--simulate-review-after-expires",
  "--simulate-missing-entry-field",
  "--simulate-executable-allowed-action",
  "--simulate-local-path-leak",
];
const allowedFlags = new Set(simulationFlags);

function fail(message) {
  errors.push(message);
}

for (const arg of rawArgs) {
  if (arg.startsWith("--") && !allowedFlags.has(arg)) {
    console.error(`UI exception check received unknown flag ${arg}.`);
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

function requireSafeExternalReference(value, alias, label) {
  if (typeof value !== "string" || !value.startsWith(`${alias}:`)) {
    fail(`${label} must use ${alias}:`);
    return;
  }
  const suffix = value.slice(alias.length + 1);
  if (!suffix || suffix.startsWith("/") || suffix.startsWith("\\") || suffix.startsWith("~/") || suffix.includes("..") || /^[A-Z]:\\/.test(suffix)) {
    fail(`${label} must use a safe relative external reference`);
  }
  if (hasLocalPath(value) || value.includes("/Users/")) {
    fail(`${label} must not contain a local path`);
  }
}

function requireIsoDate(value, label) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    fail(`${label} must be an ISO yyyy-mm-dd date`);
    return null;
  }
  const parsed = new Date(`${value}T00:00:00Z`);
  if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== value) {
    fail(`${label} must be a valid calendar date`);
    return null;
  }
  return value;
}

function runFailureSelfTests() {
  const selfTestEnv = {
    ...process.env,
    CLAWIX_UI_EXCEPTION_SELF_TEST: "1",
  };
  const tests = [
    [["--unknown-flag"], "received unknown flag --unknown-flag"],
    [["--simulate-missing-exception-status"], "exceptionStatuses must include revoked"],
    [["--simulate-missing-required-exception-field"], "requiredExceptionFields must include externalApprovalReference"],
    [["--simulate-missing-allowed-action-policy"], "allowedActionPolicy is missing nonVisualAgentAction"],
    [["--simulate-missing-approval-authority-source"], "approvalSources must include exceptions"],
    [["--simulate-unreferenced-active-exception"], "active exception must be referenced by docs/ui/visible-surfaces.inventory.json"],
    [["--simulate-expired-active-exception"], "active exception expired on 2026-05-16"],
    [["--simulate-duplicate-exception-id"], "id duplicates simulated-duplicate-exception"],
    [["--simulate-unsupported-platform"], "platforms contains unsupported visionos"],
    [["--simulate-local-private-approval-reference"], "externalApprovalReference must use a safe relative external reference"],
    [["--simulate-invalid-status"], "status is invalid"],
    [["--simulate-non-user-approval"], "approvedBy must be user"],
    [["--simulate-invalid-approval-date"], "approvedAt must be a valid calendar date"],
    [["--simulate-created-after-review"], "createdAt must not be after reviewAfter"],
    [["--simulate-review-after-expires"], "reviewAfter must not be after expiresAt"],
    [["--simulate-missing-entry-field"], "is missing reason"],
    [["--simulate-executable-allowed-action"], "allowedAction must not authorize modify presentation"],
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
      fail(`self-test ${testArgs.join(" ")} must fail for UI exception validation`);
      continue;
    }
    if (!output.includes(expectedOutput)) {
      fail(`self-test ${testArgs.join(" ")} output must include ${expectedOutput}`);
    }
  }
}

if (!isSelfTest) {
  runFailureSelfTests();
}

const requiredPlatforms = new Set(["macos", "ios", "android", "web"]);
const registryPath = "docs/ui/exceptions.registry.json";
const registry = readJson(registryPath);
const approvalAuthorityPath = "docs/ui/approval-authority.manifest.json";
const approvalAuthority = readJson(approvalAuthorityPath);
requireFields(registry, registryPath, [
  "schemaVersion",
  "status",
  "policy",
  "exceptionStatuses",
  "allowedActionPolicy",
  "requiredExceptionFields",
  "exceptions",
]);
if (args.has("--simulate-missing-exception-status") && Array.isArray(registry?.exceptionStatuses)) {
  registry.exceptionStatuses = registry.exceptionStatuses.filter((status) => status !== "revoked");
}
if (args.has("--simulate-missing-required-exception-field") && Array.isArray(registry?.requiredExceptionFields)) {
  registry.requiredExceptionFields = registry.requiredExceptionFields.filter((field) => field !== "externalApprovalReference");
}
if (args.has("--simulate-missing-allowed-action-policy")) {
  delete registry.allowedActionPolicy;
}
if (args.has("--simulate-missing-approval-authority-source") && Array.isArray(approvalAuthority?.approvalSources)) {
  approvalAuthority.approvalSources = approvalAuthority.approvalSources.filter((source) => source?.id !== "exceptions");
}

const statuses = new Set(requireArray(registry, registryPath, "exceptionStatuses"));
for (const status of ["active", "expired", "resolved", "revoked"]) {
  if (!statuses.has(status)) fail(`${registryPath}.exceptionStatuses must include ${status}`);
}

const allowedActionPolicy = registry?.allowedActionPolicy || {};
requireFields(allowedActionPolicy, `${registryPath}.allowedActionPolicy`, [
  "nonVisualAgentAction",
  "requiresExplicitUserApprovalForExpansion",
  "forbiddenAllowedActionTerms",
]);
if (allowedActionPolicy.nonVisualAgentAction !== "track-or-conceptual-proposal-only") {
  fail(`${registryPath}.allowedActionPolicy.nonVisualAgentAction must be track-or-conceptual-proposal-only`);
}
if (allowedActionPolicy.requiresExplicitUserApprovalForExpansion !== true) {
  fail(`${registryPath}.allowedActionPolicy.requiresExplicitUserApprovalForExpansion must be true`);
}
const forbiddenAllowedActionTerms = requireArray(
  allowedActionPolicy,
  `${registryPath}.allowedActionPolicy`,
  "forbiddenAllowedActionTerms",
);
for (const term of ["modify presentation", "change layout", "change copy", "change visual", "cleanup now"]) {
  if (!forbiddenAllowedActionTerms.includes(term)) {
    fail(`${registryPath}.allowedActionPolicy.forbiddenAllowedActionTerms must include ${term}`);
  }
}

const requiredExceptionFields = requireArray(registry, registryPath, "requiredExceptionFields");
const requiredExceptionFieldSet = new Set(requiredExceptionFields);
for (const field of [
  "id",
  "status",
  "scope",
  "platforms",
  "owner",
  "approvedBy",
  "approvedAt",
  "reason",
  "createdAt",
  "reviewAfter",
  "expiresAt",
  "allowedAction",
  "externalApprovalReference",
]) {
  if (!requiredExceptionFieldSet.has(field)) fail(`${registryPath}.requiredExceptionFields must include ${field}`);
}

function simulatedException(overrides = {}) {
  return {
    id: "simulated-ui-exception",
    status: "active",
    scope: "simulated",
    platforms: ["macos"],
    owner: "ui-governance-self-test",
    approvedBy: "user",
    approvedAt: "2026-05-17",
    reason: "Synthetic fixture for UI exception contract enforcement.",
    createdAt: "2026-05-17",
    reviewAfter: "2026-08-15",
    expiresAt: "2026-09-15",
    allowedAction: "conceptual proposal only",
    externalApprovalReference: "external-ui-approval:simulated",
    ...overrides,
  };
}

function appendSimulatedException(overrides = {}) {
  registry.exceptions = [
    ...(Array.isArray(registry?.exceptions) ? registry.exceptions : []),
    simulatedException(overrides),
  ];
}

if (args.has("--simulate-unreferenced-active-exception")) {
  appendSimulatedException({
    id: "simulated-unreferenced-active-exception",
    reason: "Synthetic fixture for active exception inventory mapping enforcement.",
  });
}

if (args.has("--simulate-expired-active-exception")) {
  appendSimulatedException({
    id: "simulated-expired-active-exception",
    reviewAfter: "2026-05-16",
    expiresAt: "2026-05-16",
  });
}

if (args.has("--simulate-duplicate-exception-id")) {
  registry.exceptions = [
    ...(Array.isArray(registry?.exceptions) ? registry.exceptions : []),
    simulatedException({ id: "simulated-duplicate-exception", status: "expired" }),
    simulatedException({ id: "simulated-duplicate-exception", status: "expired" }),
  ];
}

if (args.has("--simulate-unsupported-platform")) {
  appendSimulatedException({
    id: "simulated-unsupported-platform-exception",
    status: "expired",
    platforms: ["visionos"],
  });
}

if (args.has("--simulate-local-private-approval-reference")) {
  appendSimulatedException({
    id: "simulated-local-private-approval-reference",
    status: "expired",
    externalApprovalReference: `external-ui-approval:${["", "Users", "example", "private-approval.json"].join("/")}`,
  });
}

if (args.has("--simulate-invalid-status")) {
  appendSimulatedException({ id: "simulated-invalid-status", status: "pending" });
}

if (args.has("--simulate-non-user-approval")) {
  appendSimulatedException({ id: "simulated-non-user-approval", status: "expired", approvedBy: "agent" });
}

if (args.has("--simulate-invalid-approval-date")) {
  appendSimulatedException({ id: "simulated-invalid-approval-date", status: "expired", approvedAt: "2026-02-30" });
}

if (args.has("--simulate-created-after-review")) {
  appendSimulatedException({
    id: "simulated-created-after-review",
    status: "expired",
    createdAt: "2026-08-16",
    reviewAfter: "2026-08-15",
  });
}

if (args.has("--simulate-review-after-expires")) {
  appendSimulatedException({
    id: "simulated-review-after-expires",
    status: "expired",
    reviewAfter: "2026-09-16",
    expiresAt: "2026-09-15",
  });
}

if (args.has("--simulate-missing-entry-field")) {
  const simulated = simulatedException({ id: "simulated-missing-entry-field", status: "expired" });
  delete simulated.reason;
  registry.exceptions = [
    ...(Array.isArray(registry?.exceptions) ? registry.exceptions : []),
    simulated,
  ];
}

if (args.has("--simulate-executable-allowed-action")) {
  appendSimulatedException({
    id: "simulated-executable-allowed-action",
    status: "expired",
    allowedAction: "Modify presentation now.",
  });
}

if (args.has("--simulate-local-path-leak")) {
  appendSimulatedException({
    id: "simulated-local-path-leak",
    status: "expired",
    scope: "/Users/example/Desktop/Clawix/macos/Sources/Clawix/SidebarView.swift",
  });
}

const exceptionApprovalSource = (approvalAuthority?.approvalSources || []).find((source) => source?.id === "exceptions");
if (!exceptionApprovalSource) {
  fail(`${approvalAuthorityPath}.approvalSources must include exceptions`);
} else {
  if (exceptionApprovalSource.path !== registryPath) fail(`${approvalAuthorityPath}.approvalSources.exceptions.path must be ${registryPath}`);
  if (exceptionApprovalSource.arrayField !== "exceptions") fail(`${approvalAuthorityPath}.approvalSources.exceptions.arrayField must be exceptions`);
  if (exceptionApprovalSource.approvedByField !== "approvedBy") fail(`${approvalAuthorityPath}.approvalSources.exceptions.approvedByField must be approvedBy`);
  if (exceptionApprovalSource.privateApprovalField !== "externalApprovalReference") {
    fail(`${approvalAuthorityPath}.approvalSources.exceptions.privateApprovalField must be externalApprovalReference`);
  }
}

const exceptionIds = new Set();
const exceptionRecords = requireArray(registry, registryPath, "exceptions", { nonEmpty: false });
for (const [index, exception] of exceptionRecords.entries()) {
  const label = `${registryPath}.exceptions[${index}]`;
  requireFields(exception, label, requiredExceptionFields);
  if (exceptionIds.has(exception.id)) fail(`${label}.id duplicates ${exception.id}`);
  exceptionIds.add(exception.id);
  if (!statuses.has(exception.status)) fail(`${label}.status is invalid`);
  for (const platform of requireArray(exception, label, "platforms")) {
    if (!requiredPlatforms.has(platform)) fail(`${label}.platforms contains unsupported ${platform}`);
  }
  if (exception.approvedBy !== "user") fail(`${label}.approvedBy must be user`);
  requireIsoDate(exception.approvedAt, `${label}.approvedAt`);
  if (exception.status === "active" && exception.expiresAt < today) {
    fail(`${label} active exception expired on ${exception.expiresAt}`);
  }
  if (exception.reviewAfter < today && exception.status === "active") {
    fail(`${label} active exception reviewAfter expired on ${exception.reviewAfter}`);
  }
  const createdAt = requireIsoDate(exception.createdAt, `${label}.createdAt`);
  const reviewAfter = requireIsoDate(exception.reviewAfter, `${label}.reviewAfter`);
  const expiresAt = requireIsoDate(exception.expiresAt, `${label}.expiresAt`);
  if (createdAt && reviewAfter && createdAt > reviewAfter) {
    fail(`${label}.createdAt must not be after reviewAfter`);
  }
  if (reviewAfter && expiresAt && reviewAfter > expiresAt) {
    fail(`${label}.reviewAfter must not be after expiresAt`);
  }
  requireSafeExternalReference(exception.externalApprovalReference, "external-ui-approval", `${label}.externalApprovalReference`);
  const allowedAction = String(exception.allowedAction || "").toLowerCase();
  for (const term of forbiddenAllowedActionTerms) {
    if (allowedAction.includes(String(term).toLowerCase())) {
      fail(`${label}.allowedAction must not authorize ${term}`);
    }
  }
}

const inventoryPath = "docs/ui/visible-surfaces.inventory.json";
const inventory = readJson(inventoryPath);
const referencedExceptionIds = new Set();
for (const [index, entry] of requireArray(inventory, inventoryPath, "coverage").entries()) {
  if (entry?.classification !== "exception") continue;
  const label = `${inventoryPath}.coverage[${index}]`;
  for (const exceptionId of requireArray(entry, label, "exceptionIds")) {
    if (!exceptionIds.has(exceptionId)) fail(`${label}.exceptionIds references unknown exception ${exceptionId}`);
    referencedExceptionIds.add(exceptionId);
  }
}

for (const [index, exception] of exceptionRecords.entries()) {
  if (exception?.status !== "active") continue;
  if (!referencedExceptionIds.has(exception.id)) {
    fail(`${registryPath}.exceptions[${index}] active exception must be referenced by ${inventoryPath}`);
  }
}

scanForLocalPaths(registry, registryPath);

if (errors.length > 0) {
  console.error("UI exception check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI exception check passed (${exceptionIds.size} exceptions)`);
