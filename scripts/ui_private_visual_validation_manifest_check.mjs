#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = new Set(process.argv.slice(2));
const isSelfTest = process.env.CLAWIX_UI_PRIVATE_VISUAL_VALIDATION_MANIFEST_SELF_TEST === "1";
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

function runEvidencePlan() {
  const result = spawnSync(process.execPath, [path.join(rootDir, "scripts/ui_private_evidence_plan_check.mjs"), "--json"], {
    cwd: rootDir,
    encoding: "utf8",
  });
  if (result.status !== 0) {
    fail("private evidence plan must pass before private visual validation can be verified");
    if (result.stderr) {
      for (const line of result.stderr.trim().split("\n")) fail(`private evidence plan: ${line}`);
    }
    return { counts: {} };
  }
  try {
    return JSON.parse(result.stdout);
  } catch (error) {
    fail(`private evidence plan output is not valid JSON: ${error.message}`);
    return { counts: {} };
  }
}

function runCaptureRunnerCheck() {
  const result = spawnSync(process.execPath, [path.join(rootDir, "scripts/ui_private_capture_runner_check.mjs")], {
    cwd: rootDir,
    env: { ...process.env, CLAWIX_UI_PRIVATE_CAPTURE_RUNNER_SELF_TEST: "1" },
    encoding: "utf8",
  });
  if (result.status !== 0) {
    fail("private capture runner contract must pass before private visual validation can be verified");
    const output = `${result.stdout || ""}${result.stderr || ""}`.trim();
    if (output) {
      for (const line of output.split("\n")) fail(`private capture runner: ${line}`);
    }
  }
}

function approvalRecordCount() {
  const approvalAuthorityPath = "docs/ui/approval-authority.manifest.json";
  const approvalAuthority = readJson(approvalAuthorityPath);
  let count = 0;
  for (const [sourceIndex, source] of requireArray(approvalAuthority, approvalAuthorityPath, "approvalSources").entries()) {
    const sourceLabel = `${approvalAuthorityPath}.approvalSources[${sourceIndex}]`;
    requireFields(source, sourceLabel, ["path", "arrayField"]);
    const registry = readJson(source?.path || "");
    const records = requireArray(registry, source?.path || sourceLabel, source?.arrayField || "items", { nonEmpty: false });
    const approvalRequiredStatuses = Array.isArray(source?.approvalRequiredStatuses)
      ? new Set(source.approvalRequiredStatuses)
      : null;
    for (const record of records) {
      if (approvalRequiredStatuses && !approvalRequiredStatuses.has(record?.[source.statusField])) continue;
      count += 1;
    }
  }
  return count;
}

function withoutPrivateUiEnv() {
  const env = { ...process.env };
  for (const key of Object.keys(env)) {
    if (key.startsWith("CLAWIX_UI_PRIVATE_") || key === "CLAWIX_UI_ALLOW_PENDING_PRIVATE_EVIDENCE") delete env[key];
  }
  return env;
}

const manifestPath = "docs/ui/private-visual-validation.manifest.json";
const manifest = readJson(manifestPath);
if (manifest) {
  if (args.has("--simulate-inactive-private-visual-manifest")) {
    manifest.status = "pending";
  }
  if (args.has("--simulate-missing-required-root") && Array.isArray(manifest.requiredRoots)) {
    manifest.requiredRoots = manifest.requiredRoots.filter((root) => root !== "CLAWIX_UI_PRIVATE_COPY_ROOT");
  }
  if (args.has("--simulate-extra-required-root") && Array.isArray(manifest.requiredRoots)) {
    manifest.requiredRoots.push("CLAWIX_UI_PRIVATE_SCREENSHOT_ROOT");
  }
  if (args.has("--simulate-duplicate-required-root") && Array.isArray(manifest.requiredRoots) && manifest.requiredRoots[0]) {
    manifest.requiredRoots.push(manifest.requiredRoots[0]);
  }
  if (args.has("--simulate-extra-approved-scope-field") && Array.isArray(manifest.requiredApprovedScopeFields)) {
    manifest.requiredApprovedScopeFields.push("localApprovalPath");
  }
  if (args.has("--simulate-duplicate-approved-scope-field") && Array.isArray(manifest.requiredApprovedScopeFields) && manifest.requiredApprovedScopeFields[0]) {
    manifest.requiredApprovedScopeFields.push(manifest.requiredApprovedScopeFields[0]);
  }
  if (args.has("--simulate-delegate-without-approval") && Array.isArray(manifest.delegates)) {
    const delegateIndex = manifest.delegates.findIndex((delegate) => String(delegate).includes("scripts/ui_private_copy_verify.mjs"));
    if (delegateIndex >= 0) {
      manifest.delegates[delegateIndex] = "node scripts/ui_private_copy_verify.mjs";
    }
  }
  if (args.has("--simulate-extra-delegate") && Array.isArray(manifest.delegates)) {
    manifest.delegates.push("node scripts/ui_private_unknown_verify.mjs --require-approved");
  }
  if (args.has("--simulate-duplicate-delegate") && Array.isArray(manifest.delegates) && manifest.delegates[0]) {
    manifest.delegates.push(manifest.delegates[0]);
  }
  if (args.has("--simulate-duplicate-root-alias") && Array.isArray(manifest.rootAliases) && manifest.rootAliases[0]) {
    manifest.rootAliases.push({ ...manifest.rootAliases[0], env: "CLAWIX_UI_PRIVATE_DUPLICATE_ROOT" });
  }
  if (args.has("--simulate-extra-root-alias") && Array.isArray(manifest.rootAliases)) {
    manifest.rootAliases.push({
      alias: "private-codex-ui-screenshots",
      env: "CLAWIX_UI_PRIVATE_SCREENSHOT_ROOT",
      manifestPath: "docs/ui/private-baselines.manifest.json",
      manifestAliasField: "privateRootAlias",
    });
  }
  if (args.has("--simulate-extra-optional-root-alias") && Array.isArray(manifest.optionalRootAliases)) {
    manifest.optionalRootAliases.push({
      alias: "private-codex-ui-local-drafts",
      env: "CLAWIX_UI_PRIVATE_LOCAL_DRAFT_ROOT",
      manifestPath: "docs/ui/approval-authority.manifest.json",
      manifestAliasField: "privateApprovalAlias",
    });
  }
  if (args.has("--simulate-optional-root-required") && Array.isArray(manifest.requiredRoots)) {
    manifest.requiredRoots.push("CLAWIX_UI_PRIVATE_APPROVAL_ROOT");
  }
  if (args.has("--simulate-missing-decision-blocker") && Array.isArray(manifest.decisionBlockers)) {
    manifest.decisionBlockers = manifest.decisionBlockers.filter((decisionId) => decisionId !== "copy_governance");
  }
  if (args.has("--simulate-duplicate-decision-blocker") && Array.isArray(manifest.decisionBlockers)) {
    manifest.decisionBlockers.push("copy_governance");
  }
  if (args.has("--simulate-missing-decision-evidence-types") && Array.isArray(manifest.decisionBlockerEvidenceTypes)) {
    manifest.decisionBlockerEvidenceTypes = manifest.decisionBlockerEvidenceTypes.filter((item) => item?.decisionId !== "copy_governance");
  }
  if (args.has("--simulate-duplicate-decision-evidence-types") && Array.isArray(manifest.decisionBlockerEvidenceTypes)) {
    const entry = manifest.decisionBlockerEvidenceTypes.find((item) => item?.decisionId === "copy_governance");
    if (entry) manifest.decisionBlockerEvidenceTypes.push({ ...entry });
  }
  if (args.has("--simulate-unknown-evidence-type") && Array.isArray(manifest.decisionBlockerEvidenceTypes)) {
    const entry = manifest.decisionBlockerEvidenceTypes.find((item) => item?.decisionId === "copy_governance");
    if (entry && Array.isArray(entry.evidenceTypes)) {
      entry.evidenceTypes = [...entry.evidenceTypes, "unknown-private-evidence"];
    }
  }
  if (args.has("--simulate-wrong-external-pending-code")) {
    manifest.externalPendingExitCode = 1;
  }
  if (args.has("--simulate-missing-candidate-capture-manifest")) {
    delete manifest.candidateCaptureRunnerManifestPath;
  }
  if (args.has("--simulate-wrong-candidate-capture-command")) {
    manifest.candidateCapturePlanCommand = "node scripts/ui_private_capture_plan.mjs --json";
  }
  if (args.has("--simulate-missing-invalid-candidate-report-command")) {
    delete manifest.invalidCandidateReportCommand;
  }
  if (args.has("--simulate-wrong-invalid-candidate-report-command")) {
    manifest.invalidCandidateReportCommand = "node scripts/ui_private_evidence_plan_check.mjs --capture-status";
  }
  if (args.has("--simulate-missing-approval-review-bundle-command")) {
    delete manifest.approvalReviewBundleCommand;
  }
  if (args.has("--simulate-wrong-approval-review-bundle-command")) {
    manifest.approvalReviewBundleCommand = "node scripts/ui_private_review_bundle_check.mjs";
  }
}
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "verificationCommand",
  "evidencePlanCommand",
  "invalidCandidateReportCommand",
  "approvalReviewBundleCommand",
  "candidateCaptureRunnerManifestPath",
  "candidateCapturePlanCommand",
  "requiredApprovedScopeFields",
  "requiredRoots",
  "rootAliases",
  "optionalRootAliases",
  "delegates",
  "decisionBlockers",
  "decisionBlockerEvidenceTypes",
  "externalPendingExitCode",
]);
const evidencePlan = runEvidencePlan();
runCaptureRunnerCheck();

if (manifest?.status !== "active") {
  fail(`${manifestPath}.status must be active`);
}
if (!String(manifest?.verificationCommand || "").includes("scripts/ui_private_visual_verify.mjs")) {
  fail(`${manifestPath}.verificationCommand must run scripts/ui_private_visual_verify.mjs`);
}
if (!String(manifest?.verificationCommand || "").includes("--require-approved")) {
  fail(`${manifestPath}.verificationCommand must require approved private evidence`);
}
if (manifest?.evidencePlanCommand !== "node scripts/ui_private_evidence_plan_check.mjs --json") {
  fail(`${manifestPath}.evidencePlanCommand must run node scripts/ui_private_evidence_plan_check.mjs --json`);
}
if (manifest?.invalidCandidateReportCommand !== "node scripts/ui_private_evidence_plan_check.mjs --capture-invalid-candidates") {
  fail(`${manifestPath}.invalidCandidateReportCommand must run node scripts/ui_private_evidence_plan_check.mjs --capture-invalid-candidates`);
}
if (manifest?.approvalReviewBundleCommand !== "node scripts/ui_private_review_bundle_check.mjs --json") {
  fail(`${manifestPath}.approvalReviewBundleCommand must run node scripts/ui_private_review_bundle_check.mjs --json`);
}
if (manifest?.candidateCaptureRunnerManifestPath !== "docs/ui/private-capture-runners.manifest.json") {
  fail(`${manifestPath}.candidateCaptureRunnerManifestPath must be docs/ui/private-capture-runners.manifest.json`);
}
if (manifest?.candidateCapturePlanCommand !== "node scripts/ui_private_capture_plan.mjs --runner-id <runner-id> --json") {
  fail(`${manifestPath}.candidateCapturePlanCommand must run node scripts/ui_private_capture_plan.mjs --runner-id <runner-id> --json`);
}
if (manifest?.externalPendingExitCode !== 2) {
  fail(`${manifestPath}.externalPendingExitCode must be 2`);
}
requireExactStringSet(
  requireArray(manifest, manifestPath, "requiredApprovedScopeFields"),
  `${manifestPath}.requiredApprovedScopeFields`,
  ["scopeId", "approvedBy", "approvedAt", "privateApprovalReference"],
);

const expectedRoots = [
  "CLAWIX_UI_PRIVATE_BASELINE_ROOT",
  "CLAWIX_UI_PRIVATE_GEOMETRY_ROOT",
  "CLAWIX_UI_PRIVATE_COPY_ROOT",
  "CLAWIX_UI_PRIVATE_DRIFT_ROOT",
  "CLAWIX_UI_PRIVATE_DEBT_AUDIT_ROOT",
];
const roots = requireExactStringSet(requireArray(manifest, manifestPath, "requiredRoots"), `${manifestPath}.requiredRoots`, expectedRoots);
for (const root of expectedRoots) {
  if (!String(manifest?.verificationCommand || "").includes(root)) {
    fail(`${manifestPath}.verificationCommand must include ${root}`);
  }
}

const expectedAliasContracts = [
  {
    alias: "private-codex-ui-baselines",
    env: "CLAWIX_UI_PRIVATE_BASELINE_ROOT",
    manifestPath: "docs/ui/private-baselines.manifest.json",
    manifestAliasField: "privateRootAlias",
  },
  {
    alias: "private-codex-ui-rendered-geometry",
    env: "CLAWIX_UI_PRIVATE_GEOMETRY_ROOT",
    manifestPath: "docs/ui/rendered-geometry.manifest.json",
    manifestAliasField: "privateGeometryAlias",
  },
  {
    alias: "private-codex-ui-copy-snapshots",
    env: "CLAWIX_UI_PRIVATE_COPY_ROOT",
    manifestPath: "docs/ui/copy.inventory.json",
    manifestAliasField: "privateSnapshotAlias",
  },
  {
    alias: "private-codex-ui-rendered-drift",
    env: "CLAWIX_UI_PRIVATE_DRIFT_ROOT",
    manifestPath: "docs/ui/rendered-drift.manifest.json",
    manifestAliasField: "privateDriftAlias",
  },
  {
    alias: "private-codex-ui-debt-audit",
    env: "CLAWIX_UI_PRIVATE_DEBT_AUDIT_ROOT",
    manifestPath: "docs/ui/debt-audit.manifest.json",
    manifestAliasField: "privateDebtAuditAlias",
  },
];
const expectedOptionalAliasContracts = [
  {
    alias: "private-codex-ui-approval",
    env: "CLAWIX_UI_PRIVATE_APPROVAL_ROOT",
    manifestPath: "docs/ui/approval-authority.manifest.json",
    manifestAliasField: "privateApprovalAlias",
  },
  {
    alias: "private-codex-ui-mechanical-equivalence",
    env: "CLAWIX_UI_PRIVATE_MECHANICAL_EQUIVALENCE_ROOT",
    manifestPath: "docs/ui/mechanical-equivalence.manifest.json",
    manifestAliasField: "privateEvidenceAlias",
  },
];
const rootAliases = requireArray(manifest, manifestPath, "rootAliases");
const optionalRootAliases = requireArray(manifest, manifestPath, "optionalRootAliases");
if (rootAliases.length !== expectedAliasContracts.length) {
  fail(`${manifestPath}.rootAliases must exactly match required private aliases`);
}
if (optionalRootAliases.length !== expectedOptionalAliasContracts.length) {
  fail(`${manifestPath}.optionalRootAliases must exactly match optional private aliases`);
}
const aliasesByAlias = new Map();
const aliasesByEnv = new Map();
for (const [index, entry] of [...rootAliases, ...optionalRootAliases].entries()) {
  const isRequiredAlias = index < rootAliases.length;
  const label = isRequiredAlias
    ? `${manifestPath}.rootAliases[${index}]`
    : `${manifestPath}.optionalRootAliases[${index - rootAliases.length}]`;
  requireFields(entry, label, ["alias", "env", "manifestPath", "manifestAliasField"]);
  if (!entry) continue;
  if (aliasesByAlias.has(entry.alias)) fail(`${label}.alias duplicates ${entry.alias}`);
  if (aliasesByEnv.has(entry.env)) fail(`${label}.env duplicates ${entry.env}`);
  aliasesByAlias.set(entry.alias, entry);
  aliasesByEnv.set(entry.env, entry);
  if (isRequiredAlias && !roots.has(entry.env)) fail(`${label}.env must be listed in requiredRoots`);
  const sourceManifest = readJson(entry.manifestPath);
  if (sourceManifest?.[entry.manifestAliasField] !== entry.alias) {
    fail(`${label} must match ${entry.manifestPath}.${entry.manifestAliasField}`);
  }
}
for (const contract of expectedAliasContracts) {
  const entry = aliasesByAlias.get(contract.alias);
  if (!entry) {
    fail(`${manifestPath}.rootAliases must include ${contract.alias}`);
    continue;
  }
  for (const field of ["env", "manifestPath", "manifestAliasField"]) {
    if (entry[field] !== contract[field]) {
      fail(`${manifestPath}.rootAliases entry for ${contract.alias} must set ${field}=${contract[field]}`);
    }
  }
}
for (const entry of rootAliases) {
  if (!expectedAliasContracts.some((contract) => contract.alias === entry?.alias)) {
    fail(`${manifestPath}.rootAliases must not include ${entry?.alias}`);
  }
}
for (const contract of expectedOptionalAliasContracts) {
  const entry = aliasesByAlias.get(contract.alias);
  if (!entry) {
    fail(`${manifestPath}.optionalRootAliases must include ${contract.alias}`);
    continue;
  }
  for (const field of ["env", "manifestPath", "manifestAliasField"]) {
    if (entry[field] !== contract[field]) {
      fail(`${manifestPath}.optionalRootAliases entry for ${contract.alias} must set ${field}=${contract[field]}`);
    }
  }
  if (roots.has(entry.env)) {
    fail(`${manifestPath}.optionalRootAliases entry for ${contract.alias} must not add ${entry.env} to requiredRoots`);
  }
}
for (const entry of optionalRootAliases) {
  if (!expectedOptionalAliasContracts.some((contract) => contract.alias === entry?.alias)) {
    fail(`${manifestPath}.optionalRootAliases must not include ${entry?.alias}`);
  }
}
if (approvalRecordCount() > 0 && !String(manifest?.verificationCommand || "").includes("CLAWIX_UI_PRIVATE_APPROVAL_ROOT")) {
  fail(`${manifestPath}.verificationCommand must include CLAWIX_UI_PRIVATE_APPROVAL_ROOT while public approval records exist`);
}

const delegates = requireArray(manifest, manifestPath, "delegates");
const expectedDelegates = [
  "node scripts/ui_private_evidence_verify.mjs --require-approved",
  "node scripts/ui_private_approval_verify.mjs --require-approved",
  "node scripts/ui_private_baseline_verify.mjs --require-approved",
  "node scripts/ui_private_geometry_verify.mjs --require-approved",
  "node scripts/ui_private_copy_verify.mjs --require-approved",
  "node scripts/ui_private_drift_verify.mjs --require-approved",
  "node scripts/ui_private_debt_audit_verify.mjs --require-approved",
  "node scripts/ui_private_performance_budget_verify.mjs --require-approved",
];
requireExactStringSet(delegates, `${manifestPath}.delegates`, expectedDelegates);
const runnerSource = fs.existsSync(path.join(rootDir, "scripts/ui_private_visual_verify.mjs"))
  ? fs.readFileSync(path.join(rootDir, "scripts/ui_private_visual_verify.mjs"), "utf8")
  : "";
if (!runnerSource) fail("missing scripts/ui_private_visual_verify.mjs");
for (const snippet of ["--require-approved", "EXTERNAL PENDING", "process.exit(2)", "enforcePrivateVerifierArgs"]) {
  if (!runnerSource.includes(snippet)) {
    fail(`scripts/ui_private_visual_verify.mjs must include ${snippet}`);
  }
}
for (const snippet of ["docs/ui/private-visual-validation.manifest.json", "requiredRoots", "delegates", "parseDelegate", "enforcePrivateVerifierArgs"]) {
  if (!runnerSource.includes(snippet)) {
    fail(`scripts/ui_private_visual_verify.mjs must derive private validation from ${snippet}`);
  }
}
const runnerRejectsPendingResult = spawnSync(
  process.execPath,
  [path.join(rootDir, "scripts/ui_private_visual_verify.mjs"), "--require-approved", "--include-pending"],
  {
    cwd: rootDir,
    env: withoutPrivateUiEnv(),
    encoding: "utf8",
  },
);
const runnerRejectsPendingOutput = `${runnerRejectsPendingResult.stdout || ""}${runnerRejectsPendingResult.stderr || ""}`;
if (runnerRejectsPendingResult.status === 0 || runnerRejectsPendingResult.status === manifest?.externalPendingExitCode) {
  fail("scripts/ui_private_visual_verify.mjs must reject pending evidence mode unless explicitly enabled for tests");
}
if (!runnerRejectsPendingOutput.includes("CLAWIX_UI_ALLOW_PENDING_PRIVATE_EVIDENCE")) {
  fail("scripts/ui_private_visual_verify.mjs must explain the test-only pending evidence guard");
}
const runnerRejectsUnknownFlagResult = spawnSync(
  process.execPath,
  [path.join(rootDir, "scripts/ui_private_visual_verify.mjs"), "--require-approved", "--unknown-flag"],
  {
    cwd: rootDir,
    env: withoutPrivateUiEnv(),
    encoding: "utf8",
  },
);
if (runnerRejectsUnknownFlagResult.status === 0 || runnerRejectsUnknownFlagResult.status === manifest?.externalPendingExitCode) {
  fail("scripts/ui_private_visual_verify.mjs must reject unknown flags before private root checks");
}
const evidenceVerifierSource = fs.existsSync(path.join(rootDir, "scripts/ui_private_evidence_verify.mjs"))
  ? fs.readFileSync(path.join(rootDir, "scripts/ui_private_evidence_verify.mjs"), "utf8")
  : "";
if (!evidenceVerifierSource.includes("scripts/ui_private_evidence_plan_check.mjs")) {
  fail("scripts/ui_private_evidence_verify.mjs must consume the derived private evidence plan");
}
for (const snippet of ["docs/ui/private-visual-validation.manifest.json", "rootAliases", "optionalRootAliases", "loadPrivateAliasRoots"]) {
  if (!evidenceVerifierSource.includes(snippet)) {
    fail(`scripts/ui_private_evidence_verify.mjs must derive private aliases from ${snippet}`);
  }
}
const rootContractSource = fs.existsSync(path.join(rootDir, "scripts/ui_private_root_contract.mjs"))
  ? fs.readFileSync(path.join(rootDir, "scripts/ui_private_root_contract.mjs"), "utf8")
  : "";
for (const snippet of ["optionalRootAliases", "includeOptional", "required: false"]) {
  if (!rootContractSource.includes(snippet)) {
    fail(`scripts/ui_private_root_contract.mjs must support optional private root aliases via ${snippet}`);
  }
}
const approvedScopeContractPath = "scripts/ui_private_approved_scope_contract.mjs";
const approvedScopeContractSource = fs.existsSync(path.join(rootDir, approvedScopeContractPath))
  ? fs.readFileSync(path.join(rootDir, approvedScopeContractPath), "utf8")
  : "";
if (!approvedScopeContractSource) fail(`missing ${approvedScopeContractPath}`);
for (const snippet of ["requiredApprovedScopeFields", "privateApprovalAlias", "approvedBy", "privateApprovalReference"]) {
  if (!approvedScopeContractSource.includes(snippet)) {
    fail(`${approvedScopeContractPath} must validate approved scope metadata via ${snippet}`);
  }
}
const privateVerifierArgsPath = "scripts/ui_private_verifier_args.mjs";
const privateVerifierArgsSource = fs.existsSync(path.join(rootDir, privateVerifierArgsPath))
  ? fs.readFileSync(path.join(rootDir, privateVerifierArgsPath), "utf8")
  : "";
for (const snippet of ["CLAWIX_UI_ALLOW_PENDING_PRIVATE_EVIDENCE", "allowedFlags", "optionsWithValues", "testOnlyFlags", "received unexpected argument"]) {
  if (!privateVerifierArgsSource.includes(snippet)) {
    fail(`${privateVerifierArgsPath} must enforce private verifier argument contracts via ${snippet}`);
  }
}
for (const script of [
  "scripts/ui_private_approval_verify.mjs",
  "scripts/ui_private_baseline_verify.mjs",
  "scripts/ui_private_geometry_verify.mjs",
  "scripts/ui_private_copy_verify.mjs",
  "scripts/ui_private_drift_verify.mjs",
  "scripts/ui_private_debt_audit_verify.mjs",
  "scripts/ui_private_performance_budget_verify.mjs",
]) {
  const source = fs.existsSync(path.join(rootDir, script)) ? fs.readFileSync(path.join(rootDir, script), "utf8") : "";
  if (!source.includes("ui_private_root_contract.mjs") || !source.includes("privateRootEnvForAlias")) {
    fail(`${script} must derive its private root env from rootAliases`);
  }
  if (/process\.env\.CLAWIX_UI_PRIVATE_/.test(source)) {
    fail(`${script} must not hard-code CLAWIX_UI_PRIVATE_* env names`);
  }
}
for (const script of [
  "scripts/ui_private_evidence_verify.mjs",
  "scripts/ui_private_baseline_verify.mjs",
  "scripts/ui_private_geometry_verify.mjs",
  "scripts/ui_private_copy_verify.mjs",
  "scripts/ui_private_drift_verify.mjs",
  "scripts/ui_private_debt_audit_verify.mjs",
  "scripts/ui_private_performance_budget_verify.mjs",
]) {
  const source = fs.existsSync(path.join(rootDir, script)) ? fs.readFileSync(path.join(rootDir, script), "utf8") : "";
  if (!source.includes("ui_private_approved_scope_contract.mjs")) {
    fail(`${script} must use ${approvedScopeContractPath}`);
  }
  if (!source.includes("assertApprovedScopeMetadata")) {
    fail(`${script} must use shared approved scope metadata validation`);
  }
}
for (const script of [
  "scripts/ui_private_approval_verify.mjs",
  "scripts/ui_private_visual_verify.mjs",
  "scripts/ui_private_evidence_verify.mjs",
  "scripts/ui_private_baseline_verify.mjs",
  "scripts/ui_private_geometry_verify.mjs",
  "scripts/ui_private_copy_verify.mjs",
  "scripts/ui_private_drift_verify.mjs",
  "scripts/ui_private_debt_audit_verify.mjs",
  "scripts/ui_private_performance_budget_verify.mjs",
]) {
  const source = fs.existsSync(path.join(rootDir, script)) ? fs.readFileSync(path.join(rootDir, script), "utf8") : "";
  if (!source.includes("ui_private_verifier_args.mjs") || !source.includes("enforcePrivateVerifierArgs")) {
    fail(`${script} must use ${privateVerifierArgsPath}`);
  }
  const unknownFlagResult = spawnSync(process.execPath, [path.join(rootDir, script), "--require-approved", "--unknown-flag"], {
    cwd: rootDir,
    env: withoutPrivateUiEnv(),
    encoding: "utf8",
  });
  if (unknownFlagResult.status === 0 || unknownFlagResult.status === manifest?.externalPendingExitCode) {
    fail(`${script} must reject unknown flags before private root checks`);
  }
  const unexpectedArgumentResult = spawnSync(process.execPath, [path.join(rootDir, script), "--require-approved", "unexpected-arg"], {
    cwd: rootDir,
    env: withoutPrivateUiEnv(),
    encoding: "utf8",
  });
  const unexpectedArgumentOutput = `${unexpectedArgumentResult.stdout || ""}${unexpectedArgumentResult.stderr || ""}`;
  if (unexpectedArgumentResult.status === 0 || unexpectedArgumentResult.status === manifest?.externalPendingExitCode) {
    fail(`${script} must reject unexpected positional arguments before private root checks`);
  }
  if (!unexpectedArgumentOutput.includes("received unexpected argument unexpected-arg")) {
    fail(`${script} must explain unexpected positional arguments`);
  }
}
for (const script of [
  "scripts/ui_private_baseline_verify.mjs",
  "scripts/ui_private_geometry_verify.mjs",
  "scripts/ui_private_copy_verify.mjs",
  "scripts/ui_private_drift_verify.mjs",
  "scripts/ui_private_debt_audit_verify.mjs",
  "scripts/ui_private_performance_budget_verify.mjs",
]) {
  const source = fs.existsSync(path.join(rootDir, script)) ? fs.readFileSync(path.join(rootDir, script), "utf8") : "";
  if (!source.includes("optionsWithValues") || !source.includes("--root")) {
    fail(`${script} must declare --root as an option with a required value`);
  }
  const missingRootValueResult = spawnSync(process.execPath, [path.join(rootDir, script), "--require-approved", "--root"], {
    cwd: rootDir,
    env: withoutPrivateUiEnv(),
    encoding: "utf8",
  });
  const missingRootValueOutput = `${missingRootValueResult.stdout || ""}${missingRootValueResult.stderr || ""}`;
  if (missingRootValueResult.status === 0 || missingRootValueResult.status === manifest?.externalPendingExitCode) {
    fail(`${script} must reject --root without a value before private root checks`);
  }
  if (!missingRootValueOutput.includes("requires a value after --root")) {
    fail(`${script} must explain missing --root values`);
  }
}
for (const script of [
  "scripts/ui_private_evidence_verify.mjs",
  "scripts/ui_private_baseline_verify.mjs",
  "scripts/ui_private_geometry_verify.mjs",
  "scripts/ui_private_copy_verify.mjs",
  "scripts/ui_private_drift_verify.mjs",
  "scripts/ui_private_debt_audit_verify.mjs",
  "scripts/ui_private_performance_budget_verify.mjs",
]) {
  const pendingResult = spawnSync(process.execPath, [path.join(rootDir, script), "--require-approved", "--include-pending"], {
    cwd: rootDir,
    env: withoutPrivateUiEnv(),
    encoding: "utf8",
  });
  const pendingOutput = `${pendingResult.stdout || ""}${pendingResult.stderr || ""}`;
  if (pendingResult.status === 0 || pendingResult.status === manifest?.externalPendingExitCode) {
    fail(`${script} must reject pending evidence mode unless explicitly enabled for tests`);
  }
  if (!pendingOutput.includes("CLAWIX_UI_ALLOW_PENDING_PRIVATE_EVIDENCE")) {
    fail(`${script} must explain the pending evidence test-only guard`);
  }
}
for (const script of [
  "scripts/ui_private_evidence_verify.mjs",
  "scripts/ui_private_approval_verify.mjs",
  "scripts/ui_private_baseline_verify.mjs",
  "scripts/ui_private_geometry_verify.mjs",
  "scripts/ui_private_copy_verify.mjs",
  "scripts/ui_private_drift_verify.mjs",
  "scripts/ui_private_debt_audit_verify.mjs",
  "scripts/ui_private_performance_budget_verify.mjs",
]) {
  const delegate = delegates.find((delegate) => String(delegate).includes(script));
  if (!delegate) {
    fail(`${manifestPath}.delegates must include ${script}`);
    continue;
  }
  if (!String(delegate).includes("--require-approved")) {
    fail(`${manifestPath}.delegates entry for ${script} must include --require-approved`);
  }
}

const decisionVerificationPath = "docs/ui/decision-verification.json";
const decisionVerification = readJson(decisionVerificationPath);
const openDecisionIds = requireArray(decisionVerification, decisionVerificationPath, "decisions")
  .filter((decision) => decision?.status === "open")
  .map((decision) => decision.id);
const decisionBlockers = requireArray(manifest, manifestPath, "decisionBlockers");
const blockerSet = new Set(decisionBlockers);
if (blockerSet.size !== decisionBlockers.length) {
  fail(`${manifestPath}.decisionBlockers must not contain duplicate decision ids`);
}
for (const decisionId of openDecisionIds) {
  if (!blockerSet.has(decisionId)) {
    fail(`${manifestPath}.decisionBlockers must include open decision ${decisionId}`);
  }
}
for (const decisionId of decisionBlockers) {
  if (!openDecisionIds.includes(decisionId)) {
    fail(`${manifestPath}.decisionBlockers contains non-open decision ${decisionId}`);
  }
}
const evidenceTypeCounts = evidencePlan?.counts || {};
const decisionBlockerEvidenceTypes = requireArray(manifest, manifestPath, "decisionBlockerEvidenceTypes");
const blockerEvidenceByDecision = new Map();
for (const [index, entry] of decisionBlockerEvidenceTypes.entries()) {
  const label = `${manifestPath}.decisionBlockerEvidenceTypes[${index}]`;
  requireFields(entry, label, ["decisionId", "evidenceTypes"]);
  if (!entry) continue;
  if (!blockerSet.has(entry.decisionId)) {
    fail(`${label}.decisionId must be listed in decisionBlockers`);
  }
  if (blockerEvidenceByDecision.has(entry.decisionId)) {
    fail(`${label}.decisionId duplicates ${entry.decisionId}`);
  }
  blockerEvidenceByDecision.set(entry.decisionId, entry);
  const evidenceTypes = requireArray(entry, label, "evidenceTypes");
  const seenTypes = new Set();
  for (const evidenceType of evidenceTypes) {
    if (seenTypes.has(evidenceType)) fail(`${label}.evidenceTypes duplicates ${evidenceType}`);
    seenTypes.add(evidenceType);
    if (!Number.isInteger(evidenceTypeCounts[evidenceType]) || evidenceTypeCounts[evidenceType] <= 0) {
      fail(`${label}.evidenceTypes includes ${evidenceType}, which is not produced by the private evidence plan`);
    }
  }
}
for (const decisionId of decisionBlockers) {
  if (!blockerEvidenceByDecision.has(decisionId)) {
    fail(`${manifestPath}.decisionBlockerEvidenceTypes must include ${decisionId}`);
  }
}

for (const script of [
  "scripts/ui_private_root_contract.mjs",
  "scripts/ui_private_approved_scope_contract.mjs",
  "scripts/ui_private_verifier_args.mjs",
  "scripts/ui_private_visual_verify.mjs",
  "scripts/ui_private_evidence_plan_check.mjs",
  "scripts/ui_private_capture_plan.mjs",
  "scripts/ui_private_capture_runner_check.mjs",
  "scripts/ui_private_review_bundle_check.mjs",
  "scripts/ui_private_evidence_verify.mjs",
  "scripts/ui_private_approval_verify.mjs",
  "scripts/ui_private_baseline_verify.mjs",
  "scripts/ui_private_geometry_verify.mjs",
  "scripts/ui_private_copy_verify.mjs",
  "scripts/ui_private_drift_verify.mjs",
  "scripts/ui_private_debt_audit_verify.mjs",
  "scripts/ui_private_performance_budget_verify.mjs",
]) {
  if (!fs.existsSync(path.join(rootDir, script))) fail(`missing ${script}`);
}

if (errors.length === 0 && !isSelfTest && args.size === 0) {
  for (const [flag, expectedOutput] of [
    ["--simulate-inactive-private-visual-manifest", "status must be active"],
    ["--simulate-missing-required-root", "requiredRoots must include CLAWIX_UI_PRIVATE_COPY_ROOT"],
    ["--simulate-extra-approved-scope-field", "requiredApprovedScopeFields must not include localApprovalPath"],
    ["--simulate-delegate-without-approval", "delegates must include node scripts/ui_private_copy_verify.mjs --require-approved"],
    ["--simulate-extra-root-alias", "rootAliases must exactly match required private aliases"],
    ["--simulate-extra-optional-root-alias", "optionalRootAliases must exactly match optional private aliases"],
    ["--simulate-missing-decision-blocker", "decisionBlockers must include open decision copy_governance"],
    ["--simulate-unknown-evidence-type", "evidenceTypes includes unknown-private-evidence"],
    ["--simulate-missing-candidate-capture-manifest", "is missing candidateCaptureRunnerManifestPath"],
    ["--simulate-wrong-candidate-capture-command", "candidateCapturePlanCommand must run node scripts/ui_private_capture_plan.mjs --runner-id <runner-id> --json"],
    ["--simulate-missing-invalid-candidate-report-command", "is missing invalidCandidateReportCommand"],
    ["--simulate-wrong-invalid-candidate-report-command", "invalidCandidateReportCommand must run node scripts/ui_private_evidence_plan_check.mjs --capture-invalid-candidates"],
    ["--simulate-missing-approval-review-bundle-command", "is missing approvalReviewBundleCommand"],
    ["--simulate-wrong-approval-review-bundle-command", "approvalReviewBundleCommand must run node scripts/ui_private_review_bundle_check.mjs --json"],
    ["--simulate-wrong-external-pending-code", "externalPendingExitCode must be 2"],
  ]) {
    const result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, flag], {
      cwd: rootDir,
      env: { ...process.env, CLAWIX_UI_PRIVATE_VISUAL_VALIDATION_MANIFEST_SELF_TEST: "1" },
      encoding: "utf8",
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status === 0) {
      fail(`self-test ${flag} must fail when private visual validation manifest evidence is removed`);
      continue;
    }
    if (!output.includes(expectedOutput)) {
      fail(`self-test ${flag} output must include ${expectedOutput}`);
    }
  }
}

if (errors.length > 0) {
  console.error("UI private visual validation manifest check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log("UI private visual validation manifest check passed");
