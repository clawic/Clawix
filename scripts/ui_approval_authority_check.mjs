#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const rawArgs = process.argv.slice(2);
const args = new Set(rawArgs);
const isSelfTest = process.env.CLAWIX_UI_APPROVAL_AUTHORITY_SELF_TEST === "1";
const errors = [];
const simulationFlags = [
  "--simulate-inactive-approval-authority",
  "--simulate-missing-approval-source",
  "--simulate-duplicate-approval-source",
  "--simulate-unknown-approval-source",
  "--simulate-missing-required-approval-source-id",
  "--simulate-duplicate-required-evidence-field",
  "--simulate-wrong-approval-source-path",
  "--simulate-wrong-approval-source-array-field",
  "--simulate-wrong-private-approval-field",
  "--simulate-missing-required-evidence-field",
  "--simulate-missing-approved-at",
  "--simulate-approved-by-not-user",
  "--simulate-unsafe-private-approval-reference",
  "--simulate-undeclared-required-status",
  "--simulate-visual-proposal-approved-by-not-user",
  "--simulate-approved-drift-by-not-user",
];
const allowedFlags = new Set(simulationFlags);

function fail(message) {
  errors.push(message);
}

for (const arg of rawArgs) {
  if (arg.startsWith("--") && !allowedFlags.has(arg)) {
    console.error(`UI approval authority check received unknown flag ${arg}.`);
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

function requireSafePrivateReference(value, alias, label) {
  if (typeof value !== "string" || !value.startsWith(`${alias}:`)) {
    fail(`${label} must use ${alias}:`);
    return;
  }
  const suffix = value.slice(alias.length + 1);
  if (!suffix || suffix.startsWith("/") || suffix.startsWith("\\") || suffix.startsWith("~/") || suffix.includes("..") || /^[A-Z]:\\/.test(suffix)) {
    fail(`${label} must use a safe relative private reference`);
  }
  if (hasLocalPath(value) || value.includes("/Users/")) {
    fail(`${label} must not contain a local path`);
  }
}

function runFailureSelfTests() {
  const selfTestEnv = {
    ...process.env,
    CLAWIX_UI_APPROVAL_AUTHORITY_SELF_TEST: "1",
  };
  const tests = [
    [["--unknown-flag"], "received unknown flag --unknown-flag"],
    [["--simulate-inactive-approval-authority"], "status must be active"],
    [["--simulate-missing-approval-source"], "approvalSources must include exceptions"],
    [["--simulate-duplicate-approval-source"], "id duplicates canon-promotions"],
    [["--simulate-unknown-approval-source"], "id is not a governed approval source"],
    [["--simulate-missing-required-approval-source-id"], "requiredApprovalSourceIds must include protected-surfaces"],
    [["--simulate-duplicate-required-evidence-field"], "duplicates sourceId"],
    [["--simulate-wrong-approval-source-path"], "path must be docs/ui/canon-promotions.registry.json"],
    [["--simulate-wrong-approval-source-array-field"], "arrayField must be surfaces"],
    [["--simulate-wrong-private-approval-field"], "privateApprovalField must be privateApprovalReference"],
    [["--simulate-missing-required-evidence-field"], "requiredPrivateApprovalEvidenceFields must include approvalHash"],
    [["--simulate-missing-approved-at"], "approvedAt must be an ISO date"],
    [["--simulate-approved-by-not-user"], "approvedBy must be user"],
    [["--simulate-unsafe-private-approval-reference"], "privateApprovalReference must use a safe relative private reference"],
    [["--simulate-undeclared-required-status"], "approvalRequiredStatuses contains status not declared"],
    [["--simulate-visual-proposal-approved-by-not-user"], "approvedBy must be user"],
    [["--simulate-approved-drift-by-not-user"], "approvedBy must be user"],
  ];

  for (const [testArgs, expectedOutput] of tests) {
    const result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, ...testArgs], {
      cwd: rootDir,
      env: selfTestEnv,
      encoding: "utf8",
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status === 0) {
      fail(`self-test ${testArgs.join(" ")} must fail for UI approval authority validation`);
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

const manifestPath = "docs/ui/approval-authority.manifest.json";
const manifest = readJson(manifestPath);
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "privateApprovalAlias",
  "evidenceFilename",
  "requiredPrivateApprovalEvidenceFields",
  "requiredApprovalSourceIds",
  "approvalSources",
]);
if (args.has("--simulate-inactive-approval-authority") && manifest) {
  manifest.status = "draft";
}
if (args.has("--simulate-missing-approval-source") && Array.isArray(manifest?.approvalSources)) {
  manifest.approvalSources = manifest.approvalSources.filter((source) => source?.id !== "exceptions");
}
if (args.has("--simulate-duplicate-approval-source") && Array.isArray(manifest?.approvalSources) && manifest.approvalSources[0]) {
  manifest.approvalSources = [...manifest.approvalSources, { ...manifest.approvalSources[0] }];
}
if (args.has("--simulate-unknown-approval-source") && Array.isArray(manifest?.approvalSources)) {
  manifest.approvalSources = [
    ...manifest.approvalSources,
    {
      id: "agent-approval-shortcut",
      path: "docs/ui/agent-approval-shortcut.registry.json",
      arrayField: "approvals",
      approvedByField: "approvedBy",
      approvedAtField: "approvedAt",
      privateApprovalField: "privateApprovalReference",
    },
  ];
}
if (args.has("--simulate-missing-required-approval-source-id") && Array.isArray(manifest?.requiredApprovalSourceIds)) {
  manifest.requiredApprovalSourceIds = manifest.requiredApprovalSourceIds.filter((sourceId) => sourceId !== "protected-surfaces");
}
if (args.has("--simulate-duplicate-required-evidence-field") && Array.isArray(manifest?.requiredPrivateApprovalEvidenceFields)) {
  manifest.requiredPrivateApprovalEvidenceFields = [...manifest.requiredPrivateApprovalEvidenceFields, manifest.requiredPrivateApprovalEvidenceFields[0]];
}
if (args.has("--simulate-wrong-approval-source-path") && Array.isArray(manifest?.approvalSources)) {
  manifest.approvalSources = manifest.approvalSources.map((source) => (
    source?.id === "canon-promotions" ? { ...source, path: "docs/ui/wrong-canon-promotions.registry.json" } : source
  ));
}
if (args.has("--simulate-wrong-approval-source-array-field") && Array.isArray(manifest?.approvalSources)) {
  manifest.approvalSources = manifest.approvalSources.map((source) => (
    source?.id === "protected-surfaces" ? { ...source, arrayField: "items" } : source
  ));
}
if (args.has("--simulate-wrong-private-approval-field") && Array.isArray(manifest?.approvalSources)) {
  manifest.approvalSources = manifest.approvalSources.map((source) => (
    source?.id === "exceptions" ? { ...source, privateApprovalField: "privateApproval" } : source
  ));
}
if (manifest?.status !== "active") {
  fail(`${manifestPath}.status must be active`);
}
if (manifest?.privateApprovalAlias !== "private-codex-ui-approval") {
  fail(`${manifestPath}.privateApprovalAlias must be private-codex-ui-approval`);
}
if (manifest?.evidenceFilename !== "approval-evidence.json") {
  fail(`${manifestPath}.evidenceFilename must be approval-evidence.json`);
}
const requiredEvidenceFields = requireUniqueStrings(
  requireArray(manifest, manifestPath, "requiredPrivateApprovalEvidenceFields"),
  `${manifestPath}.requiredPrivateApprovalEvidenceFields`,
);
if (args.has("--simulate-missing-required-evidence-field")) {
  requiredEvidenceFields.delete("approvalHash");
}
for (const field of ["sourceId", "privateApprovalReference", "approvedBy", "approvedAt", "approvalHash", "publicRecordHash"]) {
  if (!requiredEvidenceFields.has(field)) {
    fail(`${manifestPath}.requiredPrivateApprovalEvidenceFields must include ${field}`);
  }
}

let checkedRecords = 0;
const canonicalSources = new Map([
  ["canon-promotions", {
    path: "docs/ui/canon-promotions.registry.json",
    arrayField: "promotions",
    approvedByField: "approvedBy",
    approvedAtField: "approvedAt",
    privateApprovalField: "privateApprovalReference",
  }],
  ["protected-surfaces", {
    path: "docs/ui/protected-surfaces.registry.json",
    arrayField: "surfaces",
    approvedByField: "approvedBy",
    approvedAtField: "approvedAt",
    privateApprovalField: "privateApprovalReference",
  }],
  ["visual-change-scopes", {
    path: "docs/ui/visual-change-scopes.manifest.json",
    arrayField: "activeScopes",
    approvedByField: "approvedBy",
    approvedAtField: "approvedAt",
    privateApprovalField: "privateApprovalReference",
  }],
  ["visual-model-allowlist", {
    path: "docs/ui/visual-model-allowlist.manifest.json",
    arrayField: "allowedVisualModels",
    statusField: "status",
    statusValuesField: "modelStatuses",
    approvalRequiredStatuses: ["active"],
    approvedByField: "approvedBy",
    approvedAtField: "approvedAt",
    privateApprovalField: "privateApprovalReference",
  }],
  ["visual-proposals", {
    path: "docs/ui/visual-proposals.registry.json",
    arrayField: "proposals",
    statusField: "status",
    statusValuesField: "proposalStatuses",
    approvalRequiredStatuses: ["user-approved-for-visual-lane"],
    approvedByField: "approvedBy",
    approvedAtField: "approvedAt",
    privateApprovalField: "privateApprovalReference",
  }],
  ["exceptions", {
    path: "docs/ui/exceptions.registry.json",
    arrayField: "exceptions",
    approvedByField: "approvedBy",
    approvedAtField: "approvedAt",
    privateApprovalField: "privateApprovalReference",
  }],
  ["rendered-drift", {
    path: "docs/ui/rendered-drift.manifest.json",
    arrayField: "reports",
    statusField: "status",
    statusValuesField: "reportStatuses",
    approvalRequiredStatuses: ["approved-drift"],
    approvedByField: "approvedBy",
    approvedAtField: "approvedAt",
    privateApprovalField: "privateApprovalReference",
  }],
]);
const canonicalSourceIds = [...canonicalSources.keys()];
const requiredSourceIds = requireUniqueStrings(
  requireArray(manifest, manifestPath, "requiredApprovalSourceIds"),
  `${manifestPath}.requiredApprovalSourceIds`,
);
for (const sourceId of requiredSourceIds) {
  if (!canonicalSourceIds.includes(sourceId)) fail(`${manifestPath}.requiredApprovalSourceIds contains non-governed source ${sourceId}`);
}
for (const sourceId of canonicalSourceIds) {
  if (!requiredSourceIds.has(sourceId)) fail(`${manifestPath}.requiredApprovalSourceIds must include ${sourceId}`);
}
const sourceIds = new Set();
for (const [sourceIndex, source] of requireArray(manifest, manifestPath, "approvalSources").entries()) {
  const sourceLabel = `${manifestPath}.approvalSources[${sourceIndex}]`;
  requireFields(source, sourceLabel, ["id", "path", "arrayField"]);
  if (sourceIds.has(source.id)) fail(`${sourceLabel}.id duplicates ${source.id}`);
  sourceIds.add(source.id);
  const expectedSource = canonicalSources.get(source.id);
  if (!expectedSource) {
    fail(`${sourceLabel}.id is not a governed approval source`);
    continue;
  }
  for (const field of ["path", "arrayField", "approvedByField", "approvedAtField", "privateApprovalField", "statusField", "statusValuesField"]) {
    if (source[field] !== expectedSource[field]) fail(`${sourceLabel}.${field} must be ${expectedSource[field]}`);
  }
  const expectedStatuses = expectedSource.approvalRequiredStatuses || [];
  const actualStatuses = Array.isArray(source.approvalRequiredStatuses) ? source.approvalRequiredStatuses : [];
  if (actualStatuses.length !== expectedStatuses.length || actualStatuses.some((status, index) => status !== expectedStatuses[index])) {
    fail(`${sourceLabel}.approvalRequiredStatuses must match ${JSON.stringify(expectedStatuses)}`);
  }
  const approvalRequiredStatuses = Array.isArray(source.approvalRequiredStatuses)
    ? new Set(source.approvalRequiredStatuses)
    : null;
  if (approvalRequiredStatuses && (typeof source.statusField !== "string" || source.statusField === "")) {
    fail(`${sourceLabel}.statusField must be set when approvalRequiredStatuses is present`);
  }
  if (approvalRequiredStatuses && (typeof source.statusValuesField !== "string" || source.statusValuesField === "")) {
    fail(`${sourceLabel}.statusValuesField must be set when approvalRequiredStatuses is present`);
  }
  const registry = readJson(source.path);
  if (registry && source.id === "visual-model-allowlist" && args.has("--simulate-missing-approved-at")) {
    registry.allowedVisualModels = registry.allowedVisualModels.map((model) => {
      if (model.status !== "active") return model;
      const { approvedAt, ...rest } = model;
      return rest;
    });
  }
  if (registry && source.id === "visual-model-allowlist" && args.has("--simulate-approved-by-not-user")) {
    registry.allowedVisualModels = registry.allowedVisualModels.map((model) => (
      model.status === "active" ? { ...model, approvedBy: "agent" } : model
    ));
  }
  if (registry && source.id === "visual-model-allowlist" && args.has("--simulate-unsafe-private-approval-reference")) {
    registry.allowedVisualModels = registry.allowedVisualModels.map((model) => (
      model.status === "active"
        ? { ...model, privateApprovalReference: `${manifest.privateApprovalAlias}:${path.join(path.sep, "tmp", "approval-evidence")}` }
        : model
    ));
  }
  if (registry && source.id === "visual-model-allowlist" && args.has("--simulate-undeclared-required-status")) {
    registry.modelStatuses = registry.modelStatuses.filter((status) => status !== "active");
  }
  if (registry && source.id === "visual-proposals" && args.has("--simulate-visual-proposal-approved-by-not-user")) {
    registry.proposals = [
      ...(Array.isArray(registry.proposals) ? registry.proposals : []),
      {
        id: "simulated-visual-proposal-approval",
        status: "user-approved-for-visual-lane",
        requestedBy: "non-visual-lane",
        mutationClass: "visual-ui",
        changeKinds: ["color"],
        surfaces: ["simulated-surface"],
        platforms: ["macos"],
        proposalReference: "docs/ui/visual-change-proposal.template.md",
        requiredEvidence: ["private-baseline"],
        outOfScopeDrift: [],
        userApprovalStatus: "approved",
        implementationStatus: "not-started",
        reviewAfter: "2999-12-31",
        approvedBy: "agent",
        approvedAt: "2026-05-15",
        privateApprovalReference: "private-codex-ui-approval:visual-proposals/simulated-visual-proposal-approval",
      },
    ];
  }
  if (registry && source.id === "rendered-drift" && args.has("--simulate-approved-drift-by-not-user")) {
    registry.reports = [
      {
        coverageId: "macos-root-chrome",
        platform: "macos",
        privateDriftReportReference: "private-codex-ui-rendered-drift:surfaces/macos/macos-root-chrome",
        driftCategories: ["geometry", "screenshot", "copy", "performance", "state"],
        status: "approved-drift",
        reviewAfter: "2999-12-31",
        approvedBy: "agent",
        approvedAt: "2026-05-17",
        privateApprovalReference: "private-codex-ui-approval:rendered-drift/macos-root-chrome",
      },
    ];
  }
  if (approvalRequiredStatuses) {
    const allowedStatuses = new Set(requireArray(registry, source.path, source.statusValuesField));
    for (const status of approvalRequiredStatuses) {
      if (!allowedStatuses.has(status)) {
        fail(`${sourceLabel}.approvalRequiredStatuses contains status not declared in ${source.path}.${source.statusValuesField}: ${status}`);
      }
    }
  }
  const records = requireArray(registry, source.path, source.arrayField, { nonEmpty: false });
  for (const [recordIndex, record] of records.entries()) {
    const label = `${source.path}.${source.arrayField}[${recordIndex}]`;
    if (approvalRequiredStatuses && !approvalRequiredStatuses.has(record?.[source.statusField])) {
      continue;
    }
    if (source.approvedByField && record[source.approvedByField] !== "user") {
      fail(`${label}.${source.approvedByField} must be user`);
    }
    if (source.approvedAtField) {
      const approvedAt = record[source.approvedAtField];
      if (typeof approvedAt !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(approvedAt)) {
        fail(`${label}.${source.approvedAtField} must be an ISO date`);
      }
    }
    if (source.privateApprovalField) {
      const reference = record[source.privateApprovalField];
      requireSafePrivateReference(reference, manifest.privateApprovalAlias, `${label}.${source.privateApprovalField}`);
    }
    checkedRecords += 1;
  }
}
for (const sourceId of requiredSourceIds) {
  if (!sourceIds.has(sourceId)) fail(`${manifestPath}.approvalSources must include ${sourceId}`);
}

scanForLocalPaths(manifest, manifestPath);

if (errors.length > 0) {
  console.error("UI approval authority check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI approval authority check passed (${checkedRecords} approval records)`);
