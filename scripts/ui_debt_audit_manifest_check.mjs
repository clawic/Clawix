#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const rawArgs = process.argv.slice(2);
const args = new Set(rawArgs);
const isSelfTest = process.env.CLAWIX_UI_DEBT_AUDIT_MANIFEST_SELF_TEST === "1";
const errors = [];
const simulationFlags = [
  "--simulate-inactive-debt-audit-manifest",
  "--simulate-wrong-private-debt-audit-alias",
  "--simulate-wrong-evidence-filename",
  "--simulate-missing-required-evidence-field",
  "--simulate-extra-required-evidence-field",
  "--simulate-duplicate-required-evidence-field",
  "--simulate-missing-audit-status",
  "--simulate-extra-audit-status",
  "--simulate-duplicate-audit-status",
  "--simulate-duplicate-audit-entry",
  "--simulate-unreferenced-audit-debt",
  "--simulate-unknown-debt-id",
  "--simulate-scope-mismatch",
  "--simulate-mismatched-surface-coverage",
  "--simulate-unsafe-private-reference",
  "--simulate-entry-extra-required-evidence",
  "--simulate-entry-duplicate-required-evidence",
  "--simulate-approved-manifest-with-pending-entry",
  "--simulate-pending-manifest-with-all-approved",
  "--simulate-missing-pending-report",
];
const allowedFlags = new Set(simulationFlags);

function fail(message) {
  errors.push(message);
}

for (const arg of rawArgs) {
  if (arg.startsWith("--") && !allowedFlags.has(arg)) {
    console.error(`UI debt audit manifest check received unknown flag ${arg}.`);
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

function assertPublicSafeReference(reference, alias, label) {
  if (typeof reference !== "string" || !reference.startsWith(`${alias}:`)) {
    fail(`${label} must use ${alias}:`);
    return;
  }
  const suffix = reference.slice(alias.length + 1);
  if (!suffix || suffix.startsWith("/") || suffix.startsWith("\\") || suffix.startsWith("~/") || suffix.includes("..") || /^[A-Z]:\\/.test(suffix)) {
    fail(`${label} must use a safe relative external reference`);
  }
  if (/^\/Users\//.test(reference) || reference.startsWith("~/") || reference.startsWith("file://") || /^[A-Z]:\\/.test(reference)) {
    fail(`${label} must not contain a local absolute path`);
  }
}

function sameStringArray(left, right) {
  return JSON.stringify(left || []) === JSON.stringify(right || []);
}

function runFailureSelfTests() {
  const selfTestEnv = {
    ...process.env,
    CLAWIX_UI_DEBT_AUDIT_MANIFEST_SELF_TEST: "1",
  };
  const tests = [
    [["--unknown-flag"], "received unknown flag --unknown-flag"],
    [["--simulate-inactive-debt-audit-manifest"], "status must be pending-private-visual-inventory or audited-approved"],
    [["--simulate-wrong-private-debt-audit-alias"], "privateDebtAuditAlias must be external-ui-debt-audit"],
    [["--simulate-wrong-evidence-filename"], "evidenceFilename must be debt-audit-evidence.json"],
    [["--simulate-unknown-debt-id"], "debtId must reference"],
    [["--simulate-mismatched-surface-coverage"], "surfaceCoverageId must map the debt entry"],
    [["--simulate-unsafe-private-reference"], "privateDebtAuditReference must use external-ui-debt-audit:"],
    [["--simulate-approved-manifest-with-pending-entry"], "status cannot be audited-approved while"],
    [["--simulate-pending-manifest-with-all-approved"], "status must be audited-approved when all debt audit entries are approved"],
  ];

  for (const [testArgs, expectedOutput] of tests) {
    const result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, ...testArgs], {
      cwd: rootDir,
      env: selfTestEnv,
      encoding: "utf8",
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status === 0) {
      fail(`self-test ${testArgs.join(" ")} must fail for UI debt audit manifest validation`);
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

const manifestPath = "docs/ui/debt-audit.manifest.json";
const manifest = readJson(manifestPath);
if (manifest) {
  if (args.has("--simulate-inactive-debt-audit-manifest")) {
    manifest.status = "inactive";
  }
  if (args.has("--simulate-wrong-private-debt-audit-alias")) {
    manifest.privateDebtAuditAlias = "private-other-debt-audit";
  }
  if (args.has("--simulate-wrong-evidence-filename")) {
    manifest.evidenceFilename = "visual-debt-evidence.json";
  }
  if (args.has("--simulate-missing-required-evidence-field") && Array.isArray(manifest.requiredEvidenceFields)) {
    manifest.requiredEvidenceFields = manifest.requiredEvidenceFields.filter((field) => field !== "approvedScope");
  }
  if (args.has("--simulate-extra-required-evidence-field") && Array.isArray(manifest.requiredEvidenceFields)) {
    manifest.requiredEvidenceFields.push("localAuditPath");
  }
  if (args.has("--simulate-duplicate-required-evidence-field") && Array.isArray(manifest.requiredEvidenceFields) && manifest.requiredEvidenceFields[0]) {
    manifest.requiredEvidenceFields.push(manifest.requiredEvidenceFields[0]);
  }
  if (args.has("--simulate-missing-audit-status") && Array.isArray(manifest.auditStatuses)) {
    manifest.auditStatuses = manifest.auditStatuses.filter((status) => status !== "pending-private-visual-inventory");
  }
  if (args.has("--simulate-extra-audit-status") && Array.isArray(manifest.auditStatuses)) {
    manifest.auditStatuses.push("needs-follow-up");
  }
  if (args.has("--simulate-duplicate-audit-status") && Array.isArray(manifest.auditStatuses) && manifest.auditStatuses[0]) {
    manifest.auditStatuses.push(manifest.auditStatuses[0]);
  }
  if (args.has("--simulate-duplicate-audit-entry") && Array.isArray(manifest.entries) && manifest.entries[0]) {
    manifest.entries.push({ ...manifest.entries[0] });
  }
  if (args.has("--simulate-unreferenced-audit-debt") && Array.isArray(manifest.entries) && manifest.entries[0]) {
    manifest.entries = manifest.entries.slice(1);
  }
  if (args.has("--simulate-unknown-debt-id") && Array.isArray(manifest.entries) && manifest.entries[0]) {
    manifest.entries[0] = { ...manifest.entries[0], debtId: "ui-debt-unknown" };
  }
  if (args.has("--simulate-scope-mismatch") && Array.isArray(manifest.entries) && manifest.entries[0]) {
    manifest.entries[0] = { ...manifest.entries[0], scope: "macos/Sources/Clawix/Other.swift" };
  }
  if (args.has("--simulate-mismatched-surface-coverage") && Array.isArray(manifest.entries) && manifest.entries[0]) {
    manifest.entries[0] = { ...manifest.entries[0], surfaceCoverageId: "macos-unknown-debt" };
  }
  if (args.has("--simulate-unsafe-private-reference") && Array.isArray(manifest.entries) && manifest.entries[0]) {
    manifest.entries[0] = {
      ...manifest.entries[0],
      privateDebtAuditReference: "/Users/private/debt-audit-evidence.json",
    };
  }
  if (args.has("--simulate-entry-extra-required-evidence") && Array.isArray(manifest.entries) && manifest.entries[0]) {
    manifest.entries[0] = {
      ...manifest.entries[0],
      requiredEvidence: [...(manifest.entries[0].requiredEvidence || []), "localAuditPath"],
    };
  }
  if (args.has("--simulate-entry-duplicate-required-evidence") && Array.isArray(manifest.entries) && manifest.entries[0]?.requiredEvidence?.[0]) {
    manifest.entries[0] = {
      ...manifest.entries[0],
      requiredEvidence: [...manifest.entries[0].requiredEvidence, manifest.entries[0].requiredEvidence[0]],
    };
  }
  if (args.has("--simulate-approved-manifest-with-pending-entry")) {
    manifest.status = "audited-approved";
  }
  if (args.has("--simulate-pending-manifest-with-all-approved") && Array.isArray(manifest.entries)) {
    manifest.status = "pending-private-visual-inventory";
    manifest.entries = manifest.entries.map((entry) => ({
      ...entry,
      auditStatus: "audited-approved",
    }));
  }
}
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "sourceBaseline",
  "sourceReport",
  "surfaceCoverageSource",
  "privateDebtAuditAlias",
  "evidenceFilename",
  "verificationCommand",
  "auditStatuses",
  "requiredEvidenceFields",
  "entries",
]);

if (!["pending-private-visual-inventory", "audited-approved"].includes(manifest?.status)) {
  fail(`${manifestPath}.status must be pending-private-visual-inventory or audited-approved`);
}
if (manifest?.privateDebtAuditAlias !== "external-ui-debt-audit") {
  fail(`${manifestPath}.privateDebtAuditAlias must be external-ui-debt-audit`);
}
if (manifest?.evidenceFilename !== "debt-audit-evidence.json") {
  fail(`${manifestPath}.evidenceFilename must be debt-audit-evidence.json`);
}
if (!String(manifest?.verificationCommand || "").includes("scripts/ui_private_debt_audit_verify.mjs")) {
  fail(`${manifestPath}.verificationCommand must run scripts/ui_private_debt_audit_verify.mjs`);
}
if (!String(manifest?.verificationCommand || "").includes("--require-approved")) {
  fail(`${manifestPath}.verificationCommand must require approved private debt audit evidence`);
}

const expectedEvidenceFields = [
  "debtId",
  "platform",
  "scope",
  "platforms",
  "privateDebtAuditReference",
  "findingItems",
  "findingHash",
  "visualInventoryHash",
  "auditedAt",
  "approvedByUserAt",
  "approvedScope",
];
const requiredEvidence = requireExactStringSet(
  requireArray(manifest, manifestPath, "requiredEvidenceFields"),
  `${manifestPath}.requiredEvidenceFields`,
  expectedEvidenceFields,
);

const auditStatuses = requireExactStringSet(
  requireArray(manifest, manifestPath, "auditStatuses"),
  `${manifestPath}.auditStatuses`,
  ["pending-private-visual-inventory", "audited-approved"],
);

const debtBaseline = readJson(manifest?.sourceBaseline || "docs/ui/debt.baseline.json");
const debtReport = readJson(manifest?.sourceReport || "docs/ui/debt-report.registry.json");
if (debtReport && args.has("--simulate-missing-pending-report") && Array.isArray(debtReport.pendingItems)) {
  debtReport.pendingItems = debtReport.pendingItems.filter(
    (item) => item.debtId !== "ui-debt-design-surface-raw-visual-values",
  );
}
const surfaceCoverage = readJson(manifest?.surfaceCoverageSource || "docs/ui/surface-baseline-coverage.manifest.json");

const debtById = new Map();
for (const entry of requireArray(debtBaseline, manifest?.sourceBaseline || "docs/ui/debt.baseline.json", "entries")) {
  debtById.set(entry.id, entry);
}

const pendingDebtIds = new Set(
  requireArray(debtReport, manifest?.sourceReport || "docs/ui/debt-report.registry.json", "pendingItems").map((item) => item.debtId),
);

const coverageDebtIds = new Map();
for (const coverage of requireArray(surfaceCoverage, manifest?.surfaceCoverageSource || "docs/ui/surface-baseline-coverage.manifest.json", "coverage")) {
  if (coverage.classification !== "debt") continue;
  for (const debtId of coverage.debtIds || []) coverageDebtIds.set(debtId, coverage.coverageId);
}

const auditDebtIds = new Set();
let auditedEntryCount = 0;
let pendingAuditEntryCount = 0;
for (const [index, entry] of requireArray(manifest, manifestPath, "entries").entries()) {
  const label = `${manifestPath}.entries[${index}]`;
  requireFields(entry, label, [
    "debtId",
    "scope",
    "platforms",
    "surfaceCoverageId",
    "auditStatus",
    "privateDebtAuditReference",
    "requiredEvidence",
  ]);
  const debt = debtById.get(entry.debtId);
  if (!debt) {
    fail(`${label}.debtId must reference ${manifest?.sourceBaseline}`);
  } else {
    if (entry.scope !== debt.scope) fail(`${label}.scope must match ${manifest?.sourceBaseline}`);
    if (!sameStringArray(entry.platforms, debt.platforms)) fail(`${label}.platforms must match ${manifest?.sourceBaseline}`);
  }
  if (!pendingDebtIds.has(entry.debtId)) fail(`${label}.debtId must be present in ${manifest?.sourceReport}`);
  if (coverageDebtIds.get(entry.debtId) !== entry.surfaceCoverageId) {
    fail(`${label}.surfaceCoverageId must map the debt entry in ${manifest?.surfaceCoverageSource}`);
  }
  if (!auditStatuses.has(entry.auditStatus)) fail(`${label}.auditStatus is invalid`);
  if (entry.auditStatus === "audited-approved") auditedEntryCount += 1;
  if (entry.auditStatus === "pending-private-visual-inventory") pendingAuditEntryCount += 1;
  assertPublicSafeReference(entry.privateDebtAuditReference, manifest?.privateDebtAuditAlias, `${label}.privateDebtAuditReference`);
  requireExactStringSet(requireArray(entry, label, "requiredEvidence"), `${label}.requiredEvidence`, [...requiredEvidence]);
  if (auditDebtIds.has(entry.debtId)) fail(`${label}.debtId must be unique`);
  auditDebtIds.add(entry.debtId);
}

if (manifest?.status === "audited-approved" && pendingAuditEntryCount > 0) {
  fail(`${manifestPath}.status cannot be audited-approved while ${pendingAuditEntryCount} debt audit entries are pending`);
}
if (manifest?.status === "pending-private-visual-inventory" && auditDebtIds.size > 0 && auditedEntryCount === auditDebtIds.size) {
  fail(`${manifestPath}.status must be audited-approved when all debt audit entries are approved`);
}

for (const debtId of debtById.keys()) {
  if (!auditDebtIds.has(debtId)) fail(`${manifestPath}.entries must include debtId ${debtId}`);
}

if (errors.length > 0) {
  console.error("UI debt audit manifest check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI debt audit manifest check passed (${auditDebtIds.size} debt audit entries)`);
