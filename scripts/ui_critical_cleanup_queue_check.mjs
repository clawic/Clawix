#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const rawArgs = process.argv.slice(2);
const args = new Set(rawArgs);
const errors = [];
const isSelfTest = process.env.CLAWIX_UI_CRITICAL_CLEANUP_QUEUE_SELF_TEST === "1";
const simulationFlags = [
  "--simulate-inactive-queue",
  "--simulate-wrong-source-debt-report",
  "--simulate-wrong-allowlist-path",
  "--simulate-completed-cleanup-with-pending-debt",
  "--simulate-missing-queued-debt",
  "--simulate-wrong-required-model",
  "--simulate-wrong-visual-scope-source",
  "--simulate-missing-blocker",
  "--simulate-duplicate-blocker",
  "--simulate-extra-queue-status",
  "--simulate-duplicate-queue-status",
  "--simulate-extra-required-item-field",
  "--simulate-executable-nonvisual-action",
  "--simulate-wrong-item-authorization",
  "--simulate-item-wrong-scope-source",
  "--simulate-unsupported-platform",
];
const allowedFlags = new Set(simulationFlags);

function fail(message) {
  errors.push(message);
}

for (const arg of rawArgs) {
  if (arg.startsWith("--") && !allowedFlags.has(arg)) {
    console.error(`UI critical cleanup queue check received unknown flag ${arg}.`);
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

function requireExactStringSet(values, label, expectedValues) {
  const seen = requireUniqueStrings(values, label);
  const expected = new Set(expectedValues);
  for (const value of seen) {
    if (!expected.has(value)) fail(`${label} must not include ${value}`);
  }
  for (const value of expected) {
    if (!seen.has(value)) fail(`${label} must include ${value}`);
  }
  if (seen.size !== expected.size) fail(`${label} must exactly match approved values`);
  return seen;
}

function hasLocalPath(value) {
  return typeof value === "string" && (/^\/Users\//.test(value) || value.startsWith("~/") || value.startsWith("file://") || /^[A-Z]:\\/.test(value));
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

const requiredPlatforms = new Set(["macos", "ios", "android", "web"]);
const queuePath = "docs/ui/critical-cleanup.queue.json";
const queue = readJson(queuePath);
requireFields(queue, queuePath, [
  "schemaVersion",
  "status",
  "policy",
  "sourceDebtReport",
  "visualModelAllowlist",
  "visualScopeSource",
  "requiredVisualModel",
  "v1Delivery",
  "queueStatuses",
  "requiredItemFields",
  "items",
]);

if (args.has("--simulate-inactive-queue")) {
  queue.status = "completed";
}
if (args.has("--simulate-wrong-source-debt-report")) {
  queue.sourceDebtReport = "docs/ui/other-debt-report.registry.json";
}
if (args.has("--simulate-wrong-allowlist-path")) {
  queue.visualModelAllowlist = "docs/ui/other-visual-model-allowlist.manifest.json";
}
if (args.has("--simulate-completed-cleanup-with-pending-debt") && Array.isArray(queue?.items) && queue.items[0]) {
  queue.items[0] = {
    ...queue.items[0],
    status: "completed",
  };
}
if (args.has("--simulate-missing-queued-debt") && Array.isArray(queue?.items)) {
  queue.items = queue.items.filter((item) => item?.debtId !== "ui-debt-plan-question-card-raw-visual-values");
}
if (args.has("--simulate-wrong-required-model")) {
  queue.requiredVisualModel = "missing-visual-model";
}
if (args.has("--simulate-wrong-visual-scope-source")) {
  queue.visualScopeSource = "docs/ui/missing-visual-change-scopes.manifest.json";
}
if (args.has("--simulate-missing-blocker") && Array.isArray(queue?.v1Delivery?.blockedUntil)) {
  queue.v1Delivery = {
    ...queue.v1Delivery,
    blockedUntil: queue.v1Delivery.blockedUntil.filter((blocker) => blocker !== "copy-snapshot"),
  };
}
if (args.has("--simulate-duplicate-blocker") && Array.isArray(queue?.v1Delivery?.blockedUntil) && queue.v1Delivery.blockedUntil[0]) {
  queue.v1Delivery.blockedUntil.push(queue.v1Delivery.blockedUntil[0]);
}
if (args.has("--simulate-extra-queue-status") && Array.isArray(queue?.queueStatuses)) {
  queue.queueStatuses.push("ready-for-any-agent");
}
if (args.has("--simulate-duplicate-queue-status") && Array.isArray(queue?.queueStatuses) && queue.queueStatuses[0]) {
  queue.queueStatuses.push(queue.queueStatuses[0]);
}
if (args.has("--simulate-extra-required-item-field") && Array.isArray(queue?.requiredItemFields)) {
  queue.requiredItemFields.push("implementationPatchPath");
}
if (args.has("--simulate-executable-nonvisual-action") && Array.isArray(queue?.items) && queue.items[0]) {
  queue.items[0] = { ...queue.items[0], allowedCurrentAction: "Modify presentation now." };
}
if (args.has("--simulate-wrong-item-authorization") && Array.isArray(queue?.items) && queue.items[0]) {
  queue.items[0] = { ...queue.items[0], requiredAuthorization: "any-agent" };
}
if (args.has("--simulate-item-wrong-scope-source") && Array.isArray(queue?.items) && queue.items[0]) {
  queue.items[0] = { ...queue.items[0], requiredVisualScopeSource: "docs/ui/other-scopes.manifest.json" };
}
if (args.has("--simulate-unsupported-platform") && Array.isArray(queue?.items) && queue.items[0]) {
  queue.items[0] = { ...queue.items[0], platforms: ["visionos"] };
}
const debtReportPath = queue?.sourceDebtReport || "docs/ui/debt-report.registry.json";
const debtReport = readJson(debtReportPath);
const debtItems = new Map();
for (const item of requireArray(debtReport, debtReportPath, "pendingItems")) {
  debtItems.set(item.debtId, item);
}
if (queue?.status !== "queued") {
  fail(`${queuePath}.status must be queued`);
}
if (debtReportPath !== "docs/ui/debt-report.registry.json") {
  fail(`${queuePath}.sourceDebtReport must be docs/ui/debt-report.registry.json`);
}

const allowlistPath = queue?.visualModelAllowlist || "docs/ui/visual-model-allowlist.manifest.json";
const allowlist = readJson(allowlistPath);
if (allowlistPath !== "docs/ui/visual-model-allowlist.manifest.json") {
  fail(`${queuePath}.visualModelAllowlist must be docs/ui/visual-model-allowlist.manifest.json`);
}
const activeModels = new Set(
  requireArray(allowlist, allowlistPath, "allowedVisualModels")
    .filter((model) => model?.status === "active")
    .map((model) => model.id),
);
if (!activeModels.has(queue?.requiredVisualModel)) {
  fail(`${queuePath}.requiredVisualModel must be active in ${allowlistPath}`);
}

const visualScopePath = queue?.visualScopeSource || "docs/ui/visual-change-scopes.manifest.json";
const visualScopes = readJson(visualScopePath);
requireFields(visualScopes, visualScopePath, ["scopeSignal", "scopeStatuses"]);
if (visualScopePath !== "docs/ui/visual-change-scopes.manifest.json") {
  fail(`${queuePath}.visualScopeSource must be docs/ui/visual-change-scopes.manifest.json`);
}
if (visualScopes?.scopeSignal?.requiredForVisualMutation !== true) {
  fail(`${visualScopePath}.scopeSignal.requiredForVisualMutation must be true`);
}
const scopeStatuses = new Set(requireArray(visualScopes, visualScopePath, "scopeStatuses"));
if (!scopeStatuses.has("approved")) {
  fail(`${visualScopePath}.scopeStatuses must include approved`);
}

const v1Delivery = queue?.v1Delivery || {};
requireFields(v1Delivery, `${queuePath}.v1Delivery`, [
  "goal",
  "cleanupDeliveryState",
  "completionCondition",
  "nonVisualAgentAction",
  "blockedUntil",
]);
if (v1Delivery.goal !== "governance-system-plus-critical-cleanup") {
  fail(`${queuePath}.v1Delivery.goal must be governance-system-plus-critical-cleanup`);
}
if (v1Delivery.cleanupDeliveryState !== "tracked-pending-for-allowlisted-model") {
  fail(`${queuePath}.v1Delivery.cleanupDeliveryState must be tracked-pending-for-allowlisted-model`);
}
if (v1Delivery.completionCondition !== "completed-by-allowlisted-visual-model-or-tracked-pending-with-private-approval-required") {
  fail(`${queuePath}.v1Delivery.completionCondition must require completion or tracked pending approval`);
}
if (v1Delivery.nonVisualAgentAction !== "track-only") {
  fail(`${queuePath}.v1Delivery.nonVisualAgentAction must be track-only`);
}
requireExactStringSet(
  requireArray(v1Delivery, `${queuePath}.v1Delivery`, "blockedUntil"),
  `${queuePath}.v1Delivery.blockedUntil`,
  ["approved-visual-scope", "private-baseline", "copy-snapshot", "rendered-geometry"],
);

const statuses = requireExactStringSet(
  requireArray(queue, queuePath, "queueStatuses"),
  `${queuePath}.queueStatuses`,
  ["queued-visual-authorized-lane", "blocked-without-approval", "in-progress", "completed"],
);

const requiredItemFields = requireArray(queue, queuePath, "requiredItemFields");
requireExactStringSet(requiredItemFields, `${queuePath}.requiredItemFields`, [
  "id",
  "debtId",
  "status",
  "scope",
  "platforms",
  "requiredVisualModel",
  "requiredVisualScopeSource",
  "requiredAuthorization",
  "privateApprovalRequired",
  "allowedCurrentAction",
]);

const queuedDebtIds = new Set();
const queueItemIds = new Set();
for (const [index, item] of requireArray(queue, queuePath, "items").entries()) {
  const label = `${queuePath}.items[${index}]`;
  requireFields(item, label, requiredItemFields);
  if (queueItemIds.has(item.id)) fail(`${label}.id duplicates ${item.id}`);
  queueItemIds.add(item.id);
  if (item.id !== `cleanup-${item.debtId}`) fail(`${label}.id must be cleanup-${item.debtId}`);
  if (!statuses.has(item.status)) fail(`${label}.status is invalid`);
  if (item.requiredVisualModel !== queue.requiredVisualModel) fail(`${label}.requiredVisualModel must match ${queuePath}`);
  if (item.requiredVisualScopeSource !== queue.visualScopeSource) {
    fail(`${label}.requiredVisualScopeSource must match ${queuePath}.visualScopeSource`);
  }
  if (item.requiredAuthorization !== "visual-authorized-lane") fail(`${label}.requiredAuthorization must be visual-authorized-lane`);
  if (item.privateApprovalRequired !== true) fail(`${label}.privateApprovalRequired must be true`);
  if (!String(item.allowedCurrentAction || "").includes("Queue only")) {
    fail(`${label}.allowedCurrentAction must keep cleanup non-executable for non-visual agents`);
  }
  for (const platform of requireArray(item, label, "platforms")) {
    if (!requiredPlatforms.has(platform)) fail(`${label}.platforms contains unsupported ${platform}`);
  }
  const debtItem = debtItems.get(item.debtId);
  if (!debtItem) {
    fail(`${label}.debtId must reference ${debtReportPath}`);
    continue;
  }
  const cleanupCompleted = item.status === "completed";
  const debtResolved = debtItem.status === "resolved";
  if (cleanupCompleted !== debtResolved) {
    fail(`${label}.status must be completed only when ${debtReportPath} marks the debt resolved`);
  }
  if (item.status === "blocked-without-approval" && debtItem.status !== "blocked-without-private-baseline") {
    fail(`${label}.status blocked-without-approval requires ${debtReportPath} blocked-without-private-baseline`);
  }
  if (debtItem.status === "blocked-without-private-baseline" && item.status !== "blocked-without-approval") {
    fail(`${label}.status must be blocked-without-approval while ${debtReportPath} blocks without private baseline`);
  }
  if (item.scope !== debtItem.scope) fail(`${label}.scope must match ${debtReportPath}`);
  if (JSON.stringify(item.platforms) !== JSON.stringify(debtItem.platforms)) {
    fail(`${label}.platforms must match ${debtReportPath}`);
  }
  queuedDebtIds.add(item.debtId);
}

for (const debtId of debtItems.keys()) {
  if (!queuedDebtIds.has(debtId)) fail(`${queuePath}.items must include debtId ${debtId}`);
}

scanForLocalPaths(queue, queuePath);

if (errors.length === 0 && !isSelfTest && args.size === 0) {
  for (const [flag, expectedOutput] of [
    ["--unknown-flag", "received unknown flag --unknown-flag"],
    ["--simulate-inactive-queue", "status must be queued"],
    ["--simulate-wrong-source-debt-report", "sourceDebtReport must be docs/ui/debt-report.registry.json"],
    ["--simulate-wrong-allowlist-path", "visualModelAllowlist must be docs/ui/visual-model-allowlist.manifest.json"],
    ["--simulate-completed-cleanup-with-pending-debt", "status must be completed only when docs/ui/debt-report.registry.json marks the debt resolved"],
    ["--simulate-missing-queued-debt", "items must include debtId ui-debt-plan-question-card-raw-visual-values"],
    ["--simulate-wrong-required-model", "requiredVisualModel must be active in docs/ui/visual-model-allowlist.manifest.json"],
    ["--simulate-wrong-visual-scope-source", "visualScopeSource must be docs/ui/visual-change-scopes.manifest.json"],
    ["--simulate-missing-blocker", "blockedUntil must include copy-snapshot"],
    ["--simulate-duplicate-blocker", "blockedUntil duplicates"],
    ["--simulate-extra-queue-status", "queueStatuses must not include ready-for-any-agent"],
    ["--simulate-duplicate-queue-status", "queueStatuses duplicates"],
    ["--simulate-extra-required-item-field", "requiredItemFields must not include implementationPatchPath"],
    ["--simulate-executable-nonvisual-action", "allowedCurrentAction must keep cleanup non-executable for non-visual agents"],
    ["--simulate-wrong-item-authorization", "requiredAuthorization must be visual-authorized-lane"],
    ["--simulate-item-wrong-scope-source", "requiredVisualScopeSource must match docs/ui/critical-cleanup.queue.json.visualScopeSource"],
    ["--simulate-unsupported-platform", "platforms contains unsupported visionos"],
  ]) {
    const result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, flag], {
      cwd: rootDir,
      env: { ...process.env, CLAWIX_UI_CRITICAL_CLEANUP_QUEUE_SELF_TEST: "1" },
      encoding: "utf8",
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status === 0) {
      fail(`self-test ${flag} must fail when critical cleanup queue evidence is removed`);
      continue;
    }
    if (!output.includes(expectedOutput)) {
      fail(`self-test ${flag} output must include ${expectedOutput}`);
    }
  }
}

if (errors.length > 0) {
  console.error("UI critical cleanup queue check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI critical cleanup queue check passed (${queuedDebtIds.size} queued items)`);
