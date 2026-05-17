#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const today = new Date().toISOString().slice(0, 10);
const args = new Set(process.argv.slice(2));
const errors = [];

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

function sameStringArray(left, right) {
  return JSON.stringify(left || []) === JSON.stringify(right || []);
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

const requiredPlatforms = new Set(["macos", "ios", "android", "web"]);
const requiredEvidence = ["private-baseline", "copy-snapshot", "rendered-geometry"];
const reportStatusValues = ["pending-visual-authorized-cleanup", "blocked-without-private-baseline", "resolved"];
const forbiddenWithoutApprovalValues = ["presentation-edit", "copy-edit", "layout-edit", "opportunistic-fix"];

const debtPath = "docs/ui/debt.baseline.json";
const debt = readJson(debtPath);
const decisionVerificationPath = "docs/ui/decision-verification.json";
const decisionVerification = readJson(decisionVerificationPath);
const debtStrategyDecision = (decisionVerification?.decisions || []).find((decision) => decision?.id === "debt_strategy");
if (args.has("--simulate-permissive-debt-action") && Array.isArray(debt?.entries) && debt.entries[0]) {
  debt.entries[0] = {
    ...debt.entries[0],
    allowedAction: "Fix this debt opportunistically from any UI change.",
  };
}
if (args.has("--simulate-duplicate-debt-entry") && Array.isArray(debt?.entries) && debt.entries[0]) {
  debt.entries.push({ ...debt.entries[0] });
}
if (args.has("--simulate-wrong-debt-owner") && Array.isArray(debt?.entries) && debt.entries[0]) {
  debt.entries[0] = { ...debt.entries[0], owner: "visual-cleanup" };
}
if (args.has("--simulate-resolved-baseline-debt") && Array.isArray(debt?.entries) && debt.entries[0]) {
  debt.entries[0] = { ...debt.entries[0], status: "resolved" };
}
if (args.has("--simulate-short-debt-reason") && Array.isArray(debt?.entries) && debt.entries[0]) {
  debt.entries[0] = { ...debt.entries[0], reason: "Too vague." };
}
if (args.has("--simulate-unsupported-debt-platform") && Array.isArray(debt?.entries) && debt.entries[0]) {
  debt.entries[0] = { ...debt.entries[0], platforms: ["visionos"] };
}
if (args.has("--simulate-expired-debt-review") && Array.isArray(debt?.entries) && debt.entries[0]) {
  debt.entries[0] = { ...debt.entries[0], reviewAfter: "2026-01-01" };
}
if (args.has("--simulate-local-debt-path") && Array.isArray(debt?.entries) && debt.entries[0]) {
  debt.entries[0] = { ...debt.entries[0], scope: "/Users/example/Clawix/Design" };
}
const debtEntries = requireArray(debt, debtPath, "entries");
const debtIds = new Set();
for (const [index, entry] of debtEntries.entries()) {
  const label = `${debtPath}.entries[${index}]`;
  requireFields(entry, label, ["id", "scope", "platforms", "reason", "owner", "status", "reviewAfter", "allowedAction"]);
  if (entry?.id) {
    if (debtIds.has(entry.id)) fail(`${label}.id duplicates ${entry.id}`);
    debtIds.add(entry.id);
  }
  if (entry.owner !== "interface-governance") fail(`${label}.owner must be interface-governance`);
  if (entry.status !== "frozen-existing-debt") fail(`${label}.status must be frozen-existing-debt`);
  if (typeof entry.reason !== "string" || entry.reason.trim().length < 24) {
    fail(`${label}.reason must explain the existing drift`);
  }
  if (!String(entry.allowedAction || "").includes("List and plan cleanup for visual-authorized model")) {
    fail(`${label}.allowedAction must only allow listing and planning for a visual-authorized model`);
  }
  for (const platform of requireArray(entry, label, "platforms")) {
    if (!requiredPlatforms.has(platform)) fail(`${label}.platforms contains unsupported ${platform}`);
  }
  if (entry.reviewAfter < today) fail(`${label} expired on ${entry.reviewAfter}`);
}

const aliasPath = "docs/ui/debt-baseline.manifest.json";
const alias = readJson(aliasPath);
requireFields(alias, aliasPath, ["schemaVersion", "status", "policy", "canonicalBaseline", "reportRegistry"]);
if (alias?.canonicalBaseline !== debtPath) fail(`${aliasPath}.canonicalBaseline must be ${debtPath}`);

const reportPath = "docs/ui/debt-report.registry.json";
const report = readJson(reportPath);
const auditPath = "docs/ui/debt-audit.manifest.json";
const audit = readJson(auditPath);
if (report && args.has("--simulate-wrong-report-source-baseline")) {
  report.sourceBaseline = "docs/ui/debt-baseline.json";
}
if (report && args.has("--simulate-missing-report-status")) {
  report.reportStatusValues = report.reportStatusValues.filter((status) => status !== "blocked-without-private-baseline");
}
if (report && args.has("--simulate-extra-report-status")) {
  report.reportStatusValues.push("ready-to-cleanup");
}
if (report && args.has("--simulate-duplicate-report-status") && report.reportStatusValues[0]) {
  report.reportStatusValues.push(report.reportStatusValues[0]);
}
if (report && args.has("--simulate-fix-policy-allows-cleanup")) {
  report.fixPolicy.nonAuthorizedAction = "cleanup";
}
if (report && args.has("--simulate-fix-policy-missing-evidence")) {
  report.fixPolicy.requiredPrivateEvidenceBeforeCleanup =
    report.fixPolicy.requiredPrivateEvidenceBeforeCleanup.filter((evidence) => evidence !== "rendered-geometry");
}
if (report && args.has("--simulate-fix-policy-extra-evidence")) {
  report.fixPolicy.requiredPrivateEvidenceBeforeCleanup.push("local-audit");
}
if (report && args.has("--simulate-fix-policy-duplicate-evidence") && report.fixPolicy.requiredPrivateEvidenceBeforeCleanup[0]) {
  report.fixPolicy.requiredPrivateEvidenceBeforeCleanup.push(report.fixPolicy.requiredPrivateEvidenceBeforeCleanup[0]);
}
if (report && args.has("--simulate-fix-policy-allows-presentation-edit")) {
  report.fixPolicy.forbiddenWithoutApproval =
    report.fixPolicy.forbiddenWithoutApproval.filter((action) => action !== "presentation-edit");
}
if (report && args.has("--simulate-fix-policy-extra-forbidden-action")) {
  report.fixPolicy.forbiddenWithoutApproval.push("style-review");
}
if (report && args.has("--simulate-fix-policy-duplicate-forbidden-action") && report.fixPolicy.forbiddenWithoutApproval[0]) {
  report.fixPolicy.forbiddenWithoutApproval.push(report.fixPolicy.forbiddenWithoutApproval[0]);
}
if (report && args.has("--simulate-pending-item-unknown-debt") && Array.isArray(report.pendingItems) && report.pendingItems[0]) {
  report.pendingItems[0] = { ...report.pendingItems[0], debtId: "missing-debt-id" };
}
if (report && args.has("--simulate-pending-item-invalid-status") && Array.isArray(report.pendingItems) && report.pendingItems[0]) {
  report.pendingItems[0] = { ...report.pendingItems[0], status: "ready-to-fix" };
}
if (report && args.has("--simulate-pending-item-wrong-action") && Array.isArray(report.pendingItems) && report.pendingItems[0]) {
  report.pendingItems[0] = { ...report.pendingItems[0], allowedCurrentAction: "Fix now." };
}
if (report && args.has("--simulate-pending-item-missing-evidence") && Array.isArray(report.pendingItems) && report.pendingItems[0]) {
  report.pendingItems[0] = {
    ...report.pendingItems[0],
    requiredEvidence: report.pendingItems[0].requiredEvidence.filter((evidence) => evidence !== "copy-snapshot"),
  };
}
if (report && args.has("--simulate-pending-item-extra-evidence") && Array.isArray(report.pendingItems) && report.pendingItems[0]) {
  report.pendingItems[0] = {
    ...report.pendingItems[0],
    requiredEvidence: [...report.pendingItems[0].requiredEvidence, "local-audit"],
  };
}
if (report && args.has("--simulate-pending-item-duplicate-evidence") && Array.isArray(report.pendingItems) && report.pendingItems[0]?.requiredEvidence?.[0]) {
  report.pendingItems[0] = {
    ...report.pendingItems[0],
    requiredEvidence: [...report.pendingItems[0].requiredEvidence, report.pendingItems[0].requiredEvidence[0]],
  };
}
if (report && args.has("--simulate-pending-item-scope-mismatch") && Array.isArray(report.pendingItems) && report.pendingItems[0]) {
  report.pendingItems[0] = { ...report.pendingItems[0], scope: "macos/Sources/Clawix/Other.swift" };
}
if (report && args.has("--simulate-pending-item-platform-mismatch") && Array.isArray(report.pendingItems) && report.pendingItems[0]) {
  report.pendingItems[0] = { ...report.pendingItems[0], platforms: ["ios"] };
}
if (report && args.has("--simulate-duplicate-pending-item") && Array.isArray(report.pendingItems) && report.pendingItems[0]) {
  report.pendingItems.push({ ...report.pendingItems[0] });
}
if (report && args.has("--simulate-missing-pending-item") && Array.isArray(report.pendingItems)) {
  report.pendingItems = report.pendingItems.slice(1);
}
if (args.has("--simulate-debt-decision-missing-baseline") && debtStrategyDecision) {
  debtStrategyDecision.publicEvidence = debtStrategyDecision.publicEvidence.filter((evidencePath) => evidencePath !== debtPath);
}
if (args.has("--simulate-debt-decision-missing-alias") && debtStrategyDecision) {
  debtStrategyDecision.publicEvidence = debtStrategyDecision.publicEvidence.filter((evidencePath) => evidencePath !== aliasPath);
}
if (args.has("--simulate-debt-decision-missing-audit") && debtStrategyDecision) {
  debtStrategyDecision.publicEvidence = debtStrategyDecision.publicEvidence.filter((evidencePath) => evidencePath !== auditPath);
}
if (args.has("--simulate-debt-decision-missing-evidence-plan") && debtStrategyDecision) {
  debtStrategyDecision.publicEvidence = debtStrategyDecision.publicEvidence.filter((evidencePath) => evidencePath !== "scripts/ui_private_evidence_plan_check.mjs");
}
if (args.has("--simulate-debt-decision-missing-evidence-verifier") && debtStrategyDecision) {
  debtStrategyDecision.publicEvidence = debtStrategyDecision.publicEvidence.filter((evidencePath) => evidencePath !== "scripts/ui_private_evidence_verify.mjs");
}
if (args.has("--simulate-debt-decision-missing-private-verifier") && debtStrategyDecision) {
  debtStrategyDecision.blockingVerifiers = debtStrategyDecision.blockingVerifiers.filter((verifier) => verifier !== "scripts/ui_private_debt_audit_verify.mjs");
}
if (args.has("--simulate-debt-decision-missing-private-evidence") && debtStrategyDecision) {
  debtStrategyDecision.privateEvidence = [];
}
if (args.has("--simulate-debt-decision-premature-complete") && debtStrategyDecision) {
  debtStrategyDecision.status = "verified-complete";
  debtStrategyDecision.remaining = [];
}
if (args.has("--simulate-approved-debt-audit-stale-decision") && audit && debtStrategyDecision) {
  audit.status = "audited-approved";
  debtStrategyDecision.status = "open";
  debtStrategyDecision.remaining = ["Simulated stale decision after approved private debt audit."];
}
requireFields(report, reportPath, [
  "schemaVersion",
  "status",
  "policy",
  "sourceBaseline",
  "reportStatusValues",
  "fixPolicy",
  "pendingItems",
]);
if (report?.sourceBaseline !== debtPath) fail(`${reportPath}.sourceBaseline must be ${debtPath}`);
if (report?.status !== "active") fail(`${reportPath}.status must be active`);
if (alias?.reportRegistry !== reportPath) fail(`${aliasPath}.reportRegistry must be ${reportPath}`);

const reportStatuses = requireExactStringSet(
  requireArray(report, reportPath, "reportStatusValues"),
  `${reportPath}.reportStatusValues`,
  reportStatusValues,
);

const fixPolicy = report?.fixPolicy || {};
requireFields(fixPolicy, `${reportPath}.fixPolicy`, [
  "nonAuthorizedAction",
  "cleanupActionBeforeApproval",
  "requiredAuthorization",
  "requiredPrivateEvidenceBeforeCleanup",
  "forbiddenWithoutApproval",
]);
if (fixPolicy.nonAuthorizedAction !== "report-only") {
  fail(`${reportPath}.fixPolicy.nonAuthorizedAction must be report-only`);
}
if (fixPolicy.cleanupActionBeforeApproval !== "queue-only") {
  fail(`${reportPath}.fixPolicy.cleanupActionBeforeApproval must be queue-only`);
}
if (fixPolicy.requiredAuthorization !== "visual-authorized-lane") {
  fail(`${reportPath}.fixPolicy.requiredAuthorization must be visual-authorized-lane`);
}
requireExactStringSet(
  requireArray(fixPolicy, `${reportPath}.fixPolicy`, "requiredPrivateEvidenceBeforeCleanup"),
  `${reportPath}.fixPolicy.requiredPrivateEvidenceBeforeCleanup`,
  requiredEvidence,
);
requireExactStringSet(
  requireArray(fixPolicy, `${reportPath}.fixPolicy`, "forbiddenWithoutApproval"),
  `${reportPath}.fixPolicy.forbiddenWithoutApproval`,
  forbiddenWithoutApprovalValues,
);

const reportedDebtIds = new Set();
const pendingItemIds = new Set();
for (const [index, item] of requireArray(report, reportPath, "pendingItems").entries()) {
  const label = `${reportPath}.pendingItems[${index}]`;
  requireFields(item, label, [
    "id",
    "debtId",
    "status",
    "scope",
    "platforms",
    "requiredAuthorization",
    "requiredEvidence",
    "allowedCurrentAction",
  ]);
  const debtEntry = debtEntries.find((entry) => entry.id === item.debtId);
  if (!debtEntry) {
    fail(`${label}.debtId must reference ${debtPath}`);
  } else {
    if (item.scope !== debtEntry.scope) fail(`${label}.scope must match ${debtPath}`);
    if (!sameStringArray(item.platforms, debtEntry.platforms)) fail(`${label}.platforms must match ${debtPath}`);
  }
  if (pendingItemIds.has(item.id)) fail(`${label}.id duplicates ${item.id}`);
  pendingItemIds.add(item.id);
  if (reportedDebtIds.has(item.debtId)) fail(`${label}.debtId duplicates ${item.debtId}`);
  if (!reportStatuses.has(item.status)) fail(`${label}.status is invalid`);
  if (item.requiredAuthorization !== "visual-authorized-lane") {
    fail(`${label}.requiredAuthorization must be visual-authorized-lane`);
  }
  if (item.allowedCurrentAction !== "Report only.") {
    fail(`${label}.allowedCurrentAction must remain Report only.`);
  }
  for (const platform of requireArray(item, label, "platforms")) {
    if (!requiredPlatforms.has(platform)) fail(`${label}.platforms contains unsupported ${platform}`);
  }
  requireExactStringSet(requireArray(item, label, "requiredEvidence"), `${label}.requiredEvidence`, requiredEvidence);
  reportedDebtIds.add(item.debtId);
}

for (const debtId of debtIds) {
  if (!reportedDebtIds.has(debtId)) fail(`${reportPath}.pendingItems must include debtId ${debtId}`);
}

if (!debtStrategyDecision) {
  fail(`${decisionVerificationPath}.decisions must include debt_strategy`);
} else {
  const publicEvidence = new Set(Array.isArray(debtStrategyDecision.publicEvidence) ? debtStrategyDecision.publicEvidence : []);
  for (const evidencePath of [
    debtPath,
    aliasPath,
    reportPath,
    auditPath,
    "scripts/ui_debt_report_check.mjs",
    "scripts/ui_debt_audit_manifest_check.mjs",
    "scripts/ui_private_evidence_plan_check.mjs",
    "scripts/ui_private_evidence_verify.mjs",
    "scripts/ui_private_debt_audit_verify.mjs",
  ]) {
    if (!publicEvidence.has(evidencePath)) {
      fail(`${decisionVerificationPath}.decisions.debt_strategy.publicEvidence must include ${evidencePath}`);
    }
  }
  const privateEvidence = new Set(Array.isArray(debtStrategyDecision.privateEvidence) ? debtStrategyDecision.privateEvidence : []);
  const privateAlias = audit?.privateDebtAuditAlias || "private-codex-ui-debt-audit";
  if (!privateEvidence.has(`${privateAlias}:macos/*`)) {
    fail(`${decisionVerificationPath}.decisions.debt_strategy.privateEvidence must include ${privateAlias}:macos/*`);
  }
  const blockingVerifiers = new Set(Array.isArray(debtStrategyDecision.blockingVerifiers) ? debtStrategyDecision.blockingVerifiers : []);
  for (const verifier of [
    "scripts/ui_private_debt_audit_verify.mjs",
    "scripts/ui_private_evidence_verify.mjs",
  ]) {
    if (!blockingVerifiers.has(verifier)) {
      fail(`${decisionVerificationPath}.decisions.debt_strategy.blockingVerifiers must include ${verifier}`);
    }
  }
  if (audit?.status !== "audited-approved" && debtStrategyDecision.status !== "open") {
    fail(`${decisionVerificationPath}.decisions.debt_strategy.status must remain open until private debt audit is approved`);
  }
  if (audit?.status !== "audited-approved" && (!Array.isArray(debtStrategyDecision.remaining) || debtStrategyDecision.remaining.length === 0)) {
    fail(`${decisionVerificationPath}.decisions.debt_strategy.remaining must describe pending private debt audit`);
  }
  if (audit?.status === "audited-approved" && debtStrategyDecision.status !== "verified-complete") {
    fail(`${decisionVerificationPath}.decisions.debt_strategy.status must be verified-complete after private debt audit is approved`);
  }
  if (audit?.status === "audited-approved" && Array.isArray(debtStrategyDecision.remaining) && debtStrategyDecision.remaining.length > 0) {
    fail(`${decisionVerificationPath}.decisions.debt_strategy.remaining must be empty after private debt audit is approved`);
  }
}

scanForLocalPaths(debt, debtPath);
scanForLocalPaths(alias, aliasPath);
scanForLocalPaths(report, reportPath);
scanForLocalPaths(audit, auditPath);

if (errors.length > 0) {
  console.error("UI debt report check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI debt report check passed (${reportedDebtIds.size} pending items)`);
