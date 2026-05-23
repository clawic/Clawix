#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { execFileSync, spawnSync } from "node:child_process";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const rawArgs = process.argv.slice(2);
const isSelfTest = process.env.CLAWIX_UI_GOVERNANCE_GUARD_SELF_TEST === "1";
const simulationFlags = [
  "--simulate-unauthorized-visual-diff",
  "--simulate-cross-platform-visual-diff",
  "--simulate-approved-visual-scope",
  "--simulate-overbudget-visual-scope",
  "--simulate-wrong-file-visual-scope",
  "--simulate-layout-only-visual-scope",
  "--simulate-revoked-visual-scope",
  "--simulate-expired-visual-scope",
  "--simulate-budget-kind-visual-scope",
  "--simulate-missing-pattern-visual-scope",
  "--simulate-duplicate-pattern-visual-scope",
  "--simulate-invalid-budget-visual-scope",
  "--simulate-unsafe-file-visual-scope",
  "--simulate-report-only-functional-diff",
];
const allowedFlags = new Set(simulationFlags);
const today = new Date().toISOString().slice(0, 10);
const simulateUnauthorizedVisualDiff = rawArgs.includes("--simulate-unauthorized-visual-diff");
const simulateCrossPlatformVisualDiff = rawArgs.includes("--simulate-cross-platform-visual-diff");
const simulateApprovedVisualScope = rawArgs.includes("--simulate-approved-visual-scope");
const simulateOverbudgetVisualScope = rawArgs.includes("--simulate-overbudget-visual-scope");
const simulateWrongFileVisualScope = rawArgs.includes("--simulate-wrong-file-visual-scope");
const simulateLayoutOnlyVisualScope = rawArgs.includes("--simulate-layout-only-visual-scope");
const simulateRevokedVisualScope = rawArgs.includes("--simulate-revoked-visual-scope");
const simulateExpiredVisualScope = rawArgs.includes("--simulate-expired-visual-scope");
const simulateBudgetKindVisualScope = rawArgs.includes("--simulate-budget-kind-visual-scope");
const simulateMissingPatternVisualScope = rawArgs.includes("--simulate-missing-pattern-visual-scope");
const simulateDuplicatePatternVisualScope = rawArgs.includes("--simulate-duplicate-pattern-visual-scope");
const simulateInvalidBudgetVisualScope = rawArgs.includes("--simulate-invalid-budget-visual-scope");
const simulateUnsafeFileVisualScope = rawArgs.includes("--simulate-unsafe-file-visual-scope");
const simulateReportOnlyFunctionalDiff = rawArgs.includes("--simulate-report-only-functional-diff");
const errors = [];

function fail(message) {
  errors.push(message);
}

for (const arg of rawArgs) {
  if (arg.startsWith("--") && !allowedFlags.has(arg)) {
    console.error(`UI governance guard received unknown flag ${arg}.`);
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

function requireFields(object, relativePath, fields) {
  if (!object) return;
  for (const field of fields) {
    if (object[field] === undefined || object[field] === null || object[field] === "") {
      fail(`${relativePath} is missing ${field}`);
    }
  }
}

function requireArray(object, relativePath, field, { nonEmpty = true } = {}) {
  if (!object) return [];
  const value = object[field];
  if (!Array.isArray(value)) {
    fail(`${relativePath}.${field} must be an array`);
    return [];
  }
  if (nonEmpty && value.length === 0) {
    fail(`${relativePath}.${field} must not be empty`);
  }
  return value;
}

function git(args) {
  try {
    return execFileSync("git", ["-C", rootDir, ...args], { encoding: "utf8" });
  } catch {
    return "";
  }
}

const configPath = "docs/ui/interface-governance.config.json";
const config = readJson(configPath);
requireFields(config, configPath, [
  "schemaVersion",
  "status",
  "platforms",
  "visualAuthorizationPolicy",
  "mutationClasses",
  "restrictedChangeKinds",
  "requiredInteractiveStates",
]);

const requiredPlatforms = ["macos", "ios", "android", "web"];
const platforms = new Set(requireArray(config, configPath, "platforms"));
for (const platform of requiredPlatforms) {
  if (!platforms.has(platform)) fail(`${configPath}.platforms must include ${platform}`);
}

const visualAuthorization = config?.visualAuthorizationPolicy || {};
requireFields(visualAuthorization, `${configPath}.visualAuthorizationPolicy`, [
  "mode",
  "privateAssignment",
  "publicSignalEnv",
  "publicSignalValue",
]);
if (visualAuthorization.mode !== "private-allowlist") {
  fail(`${configPath}.visualAuthorizationPolicy.mode must be private-allowlist`);
}
if (visualAuthorization.privateAssignment !== "outside-public-repo") {
  fail(`${configPath}.visualAuthorizationPolicy.privateAssignment must stay outside-public-repo`);
}

const visualModelAllowlistPath = "docs/ui/visual-model-allowlist.manifest.json";
const visualModelAllowlist = readJson(visualModelAllowlistPath);
requireFields(visualModelAllowlist, visualModelAllowlistPath, [
  "schemaVersion",
  "status",
  "policy",
  "privateAssignment",
  "authorizationSignal",
  "modelSignal",
  "proposalPath",
  "allowedVisualModels",
]);
if (visualModelAllowlist?.privateAssignment !== "outside-public-repo") {
  fail(`${visualModelAllowlistPath}.privateAssignment must stay outside-public-repo`);
}
if (visualModelAllowlist?.authorizationSignal?.env !== visualAuthorization.publicSignalEnv) {
  fail(`${visualModelAllowlistPath}.authorizationSignal.env must match ${configPath}.visualAuthorizationPolicy.publicSignalEnv`);
}
if (visualModelAllowlist?.authorizationSignal?.value !== visualAuthorization.publicSignalValue) {
  fail(`${visualModelAllowlistPath}.authorizationSignal.value must match ${configPath}.visualAuthorizationPolicy.publicSignalValue`);
}
const activeVisualModelIds = new Set(
  requireArray(visualModelAllowlist, visualModelAllowlistPath, "allowedVisualModels")
    .filter((model) => model?.status === "active")
    .map((model) => model.id),
);
if (!activeVisualModelIds.has("approved-visual-model")) {
  fail(`${visualModelAllowlistPath}.allowedVisualModels must include active approved-visual-model`);
}

const requiredStates = [
  "idle",
  "hover-or-highlight",
  "focused",
  "pressed",
  "disabled",
  "selected",
  "busy",
  "error",
];
const configuredStates = new Set(requireArray(config, configPath, "requiredInteractiveStates"));
for (const state of requiredStates) {
  if (!configuredStates.has(state)) fail(`${configPath}.requiredInteractiveStates must include ${state}`);
}

const componentExtractionPath = "docs/ui/component-extraction.manifest.json";
const componentExtraction = readJson(componentExtractionPath);
requireFields(componentExtraction, componentExtractionPath, [
  "schemaVersion",
  "status",
  "policy",
  "minimumCallSites",
  "requiredRiskSignals",
  "mechanicalEquivalence",
  "allowedPolicies",
  "allowedApis",
]);
const allowedExtractionApis = new Set(
  requireArray(componentExtraction, componentExtractionPath, "allowedApis").map((api) => api?.id).filter(Boolean),
);
const extractionPolicyApis = new Map();
for (const policy of requireArray(componentExtraction, componentExtractionPath, "allowedPolicies")) {
  if (!policy?.id) continue;
  extractionPolicyApis.set(policy.id, new Set(Array.isArray(policy.allowedApis) ? policy.allowedApis : []));
}

const indexPath = "docs/ui/pattern-registry/patterns.registry.json";
const registry = readJson(indexPath);
requireFields(registry, indexPath, ["schemaVersion", "platforms", "notesPath", "patterns"]);
const registryPatterns = requireArray(registry, indexPath, "patterns");
const registryPlatforms = new Set(requireArray(registry, indexPath, "platforms"));
for (const platform of requiredPlatforms) {
  if (!registryPlatforms.has(platform)) fail(`${indexPath}.platforms must include ${platform}`);
}

const notesPath = registry?.notesPath || "";
const notesAbsolutePath = path.join(rootDir, notesPath);
const patternNotes = fs.existsSync(notesAbsolutePath) ? fs.readFileSync(notesAbsolutePath, "utf8") : "";
if (!patternNotes) fail(`${indexPath}.notesPath must point to a Markdown notes file`);

for (const patternId of registryPatterns) {
  const patternPath = `docs/ui/pattern-registry/patterns/${patternId}.pattern.json`;
  const pattern = readJson(patternPath);
  requireFields(pattern, patternPath, [
    "schemaVersion",
    "id",
    "status",
    "platforms",
    "mutationClass",
    "canonicalReferences",
    "states",
    "geometry",
    "copy",
    "performance",
    "componentExtraction",
    "validation",
  ]);
  if (!pattern) continue;
  if (pattern.id !== patternId) fail(`${patternPath}.id must be ${patternId}`);
  const states = new Set(requireArray(pattern, patternPath, "states"));
  for (const state of requiredStates) {
    if (!states.has(state)) fail(`${patternPath}.states must include ${state}`);
  }
  const patternPlatforms = requireArray(pattern, patternPath, "platforms");
  if (!patternPlatforms.some((platform) => requiredPlatforms.includes(platform))) {
    fail(`${patternPath}.platforms must include at least one governed platform`);
  }
  const extraction = pattern.componentExtraction || {};
  if (!extractionPolicyApis.has(extraction.policy)) {
    fail(`${patternPath}.componentExtraction.policy must be defined in ${componentExtractionPath}`);
  }
  if (!allowedExtractionApis.has(extraction.api)) {
    fail(`${patternPath}.componentExtraction.api must encode a governed component API strategy`);
  }
  const allowedForPolicy = extractionPolicyApis.get(extraction.policy);
  if (allowedForPolicy && !allowedForPolicy.has(extraction.api)) {
    fail(`${patternPath}.componentExtraction.api ${extraction.api} is not allowed for policy ${extraction.policy}`);
  }
  if (!patternNotes.includes(`## ${patternId}`)) {
    fail(`${notesPath} must include a Markdown note for ${patternId}`);
  }
}

const decisionPath = "docs/ui/decision-verification.json";
const decisionVerification = readJson(decisionPath);
requireFields(decisionVerification, decisionPath, [
  "schemaVersion",
  "conversationId",
  "goalReference",
  "sourceSession",
  "completionRule",
  "decisions",
]);
const expectedDecisionIds = [
  "initial_scope",
  "enforcement_mode",
  "canonical_source",
  "debt_strategy",
  "canon_approval",
  "visual_baselines_location",
  "canon_unit",
  "agent_ui_workflow",
  "performance_budget_style",
  "alignment_validation",
  "state_coverage",
  "human_visual_review",
  "governance_location",
  "skills_shape",
  "external_references_policy",
  "gate_surface",
  "exception_policy",
  "copy_governance",
  "v1_pattern_set",
  "ci_visual_strategy",
  "perf_budget_source",
  "v1_delivery_goal",
  "registry_format",
  "skill_naming_style",
  "component_extraction_rule",
  "component_api_style",
  "size_contracts",
  "visual_mutation_permission",
  "approved_surface_protection",
  "ui_debt_fix_policy",
  "visual_model_gate",
  "mechanical_refactor_visual_safety",
  "visual_change_scope_limit",
  "ui_change_classification",
  "visual_guard_behavior",
  "visual_proposal_flow",
  "implementation_split",
  "approved_baseline_authority",
  "critical_cleanup_owner",
];
const decisions = requireArray(decisionVerification, decisionPath, "decisions");
if (decisions.length !== expectedDecisionIds.length) {
  fail(`${decisionPath}.decisions must contain ${expectedDecisionIds.length} decision records`);
}
for (const [index, expectedId] of expectedDecisionIds.entries()) {
  const decision = decisions[index];
  const label = `${decisionPath}.decisions[${index}]`;
  requireFields(decision, label, ["index", "id", "choice", "status", "publicEvidence", "remaining"]);
  if (!decision) continue;
  if (decision.index !== index + 1) fail(`${label}.index must be ${index + 1}`);
  if (decision.id !== expectedId) fail(`${label}.id must be ${expectedId}`);
  if (!["open", "blocked-external-pending", "verified-complete"].includes(decision.status)) fail(`${label}.status is invalid`);
  if (decision.status === "verified-complete" && decision.remaining?.length > 0) {
    fail(`${label} cannot be verified-complete while remaining work is listed`);
  }
  if (decision.status === "blocked-external-pending") {
    requireFields(decision.externalPendingLedger, `${label}.externalPendingLedger`, [
      "reason",
      "risk",
      "nextPhase",
      "reentryCondition",
      "blockingCommand",
    ]);
  }
}

const debtPath = "docs/ui/debt.baseline.json";
const debt = readJson(debtPath);
requireFields(debt, debtPath, ["schemaVersion", "status", "policy", "entries"]);
for (const [index, entry] of requireArray(debt, debtPath, "entries").entries()) {
  const label = `${debtPath}.entries[${index}]`;
  requireFields(entry, label, ["id", "scope", "platforms", "reason", "owner", "status", "reviewAfter", "allowedAction"]);
  if (entry.reviewAfter && entry.reviewAfter < today) {
    fail(`${label} expired on ${entry.reviewAfter}`);
  }
}

const debtAliasPath = "docs/ui/debt-baseline.manifest.json";
const debtAlias = readJson(debtAliasPath);
requireFields(debtAlias, debtAliasPath, ["schemaVersion", "status", "policy", "canonicalBaseline", "reportRegistry"]);
if (debtAlias?.canonicalBaseline !== debtPath) fail(`${debtAliasPath}.canonicalBaseline must be ${debtPath}`);

const debtReportPath = "docs/ui/debt-report.registry.json";
const debtReport = readJson(debtReportPath);
requireFields(debtReport, debtReportPath, [
  "schemaVersion",
  "status",
  "policy",
  "sourceBaseline",
  "reportStatusValues",
  "pendingItems",
]);

const debtAuditPath = "docs/ui/debt-audit.manifest.json";
const debtAudit = readJson(debtAuditPath);
requireFields(debtAudit, debtAuditPath, [
  "schemaVersion",
  "status",
  "policy",
  "sourceBaseline",
  "sourceReport",
  "privateDebtAuditAlias",
  "entries",
]);

const exceptionsPath = "docs/ui/exceptions.registry.json";
const exceptions = readJson(exceptionsPath);
requireFields(exceptions, exceptionsPath, [
  "schemaVersion",
  "status",
  "policy",
  "exceptionStatuses",
  "requiredExceptionFields",
  "exceptions",
]);

const protectedPath = "docs/ui/protected-surfaces.registry.json";
const protectedSurfaces = readJson(protectedPath);
requireFields(protectedSurfaces, protectedPath, [
  "schemaVersion",
  "status",
  "policy",
  "externalBaselineAlias",
  "privateCopyAlias",
  "externalGeometryAlias",
  "requiredFreezeFields",
  "surfaces",
]);
for (const [index, surface] of requireArray(protectedSurfaces, protectedPath, "surfaces", { nonEmpty: false }).entries()) {
  const label = `${protectedPath}.surfaces[${index}]`;
  requireFields(surface, label, protectedSurfaces.requiredFreezeFields || []);
}

const promotionPath = "docs/ui/canon-promotions.registry.json";
const promotions = readJson(promotionPath);
requireFields(promotions, promotionPath, [
  "schemaVersion",
  "status",
  "policy",
  "externalApprovalAlias",
  "externalBaselineAlias",
  "privateCopyAlias",
  "externalGeometryAlias",
  "promotionStatuses",
  "requiredPromotionFields",
  "promotions",
]);

const mechanicalEquivalencePath = "docs/ui/mechanical-equivalence.manifest.json";
const mechanicalEquivalence = readJson(mechanicalEquivalencePath);
requireFields(mechanicalEquivalence, mechanicalEquivalencePath, [
  "schemaVersion",
  "status",
  "policy",
  "externalEvidenceAlias",
  "requiredEvidenceFields",
  "allowedTokenDiffStatuses",
  "equivalenceStatuses",
  "records",
]);

const budgetsPath = "docs/ui/performance-budgets.registry.json";
const budgets = readJson(budgetsPath);
requireFields(budgets, budgetsPath, ["schemaVersion", "status", "policy", "flows"]);
const patternPerformancePath = "docs/ui/pattern-performance.manifest.json";
const patternPerformance = readJson(patternPerformancePath);
requireFields(patternPerformance, patternPerformancePath, [
  "schemaVersion",
  "status",
  "policy",
  "patternRegistryPath",
  "performanceBudgetRegistryPath",
  "externalBaselineAlias",
  "requiredFlowMappings",
]);
const requiredFlows = [
  "sidebar-hover-click-expand",
  "chat-scroll",
  "composer-typing",
  "dropdown-open",
  "terminal-sidebar-switch",
  "right-sidebar-browser-use",
];
const seenFlows = new Set();
const seenFlowPlatforms = new Set();
const requiredPerformanceMetrics = new Set([
  "interactionLatencyMs",
  "p95FrameTimeMs",
  "hitchCount",
  "memoryDeltaMb",
]);
for (const [index, flow] of requireArray(budgets, budgetsPath, "flows").entries()) {
  const label = `${budgetsPath}.flows[${index}]`;
  requireFields(flow, label, [
    "id",
    "platform",
    "baselineStatus",
    "measurementSource",
    "externalBaselineReference",
    "requiredMetrics",
    "budgetStatus",
  ]);
  seenFlows.add(flow.id);
  seenFlowPlatforms.add(`${flow.platform}:${flow.id}`);
  if (!requiredPlatforms.includes(flow.platform)) fail(`${label}.platform is not governed`);
  if (flow.measurementSource !== "private-baseline") fail(`${label}.measurementSource must be private-baseline`);
  if (!String(flow.externalBaselineReference || "").startsWith("external-ui-baselines:")) {
    fail(`${label}.externalBaselineReference must use the private baseline alias`);
  }
  const metrics = new Set(requireArray(flow, label, "requiredMetrics"));
  for (const metric of requiredPerformanceMetrics) {
    if (!metrics.has(metric)) fail(`${label}.requiredMetrics must include ${metric}`);
  }
}
for (const flow of requiredFlows) {
  if (!seenFlows.has(flow)) fail(`${budgetsPath}.flows must include ${flow}`);
}
for (const platform of requiredPlatforms) {
  for (const flow of requiredFlows) {
    if (!seenFlowPlatforms.has(`${platform}:${flow}`)) {
      fail(`${budgetsPath}.flows must include ${platform}:${flow}`);
    }
  }
}

const privateBaselinesPath = "docs/ui/private-baselines.manifest.json";
const privateBaselines = readJson(privateBaselinesPath);
requireFields(privateBaselines, privateBaselinesPath, [
  "schemaVersion",
  "status",
  "policy",
  "externalRootAlias",
  "privateArtifactPolicy",
  "requiredEvidenceFields",
  "flows",
]);
if (privateBaselines?.externalRootAlias !== "external-ui-baselines") {
  fail(`${privateBaselinesPath}.externalRootAlias must be external-ui-baselines`);
}
const baselineCoverage = new Set();
for (const [index, flow] of requireArray(privateBaselines, privateBaselinesPath, "flows").entries()) {
  const label = `${privateBaselinesPath}.flows[${index}]`;
  requireFields(flow, label, [
    "id",
    "platform",
    "baselineStatus",
    "externalBaselineReference",
    "runnerId",
    "requiredEvidence",
    "tolerance",
  ]);
  baselineCoverage.add(`${flow.platform}:${flow.id}`);
}
for (const platform of requiredPlatforms) {
  for (const flow of requiredFlows) {
    if (!baselineCoverage.has(`${platform}:${flow}`)) {
      fail(`${privateBaselinesPath}.flows must include ${platform}:${flow}`);
    }
  }
}

const privateVisualValidationPath = "docs/ui/private-visual-validation.manifest.json";
const privateVisualValidation = readJson(privateVisualValidationPath);
requireFields(privateVisualValidation, privateVisualValidationPath, [
  "schemaVersion",
  "status",
  "policy",
  "verificationCommand",
  "requiredRoots",
  "delegates",
  "externalPendingExitCode",
]);

const inspirationPath = "docs/ui/inspiration/references.registry.json";
const inspiration = readJson(inspirationPath);
requireFields(inspiration, inspirationPath, ["schemaVersion", "policy", "references"]);
for (const [index, reference] of requireArray(inspiration, inspirationPath, "references").entries()) {
  const label = `${inspirationPath}.references[${index}]`;
  requireFields(reference, label, ["id", "url", "use", "canonical"]);
  if (reference.canonical !== false) {
    fail(`${label}.canonical must be false until explicitly approved`);
  }
}

const changedBase = process.env.CLAWIX_UI_GUARD_DIFF_BASE;
const visualDetectorsPath = "docs/ui/visual-change-detectors.manifest.json";
const visualDetectors = readJson(visualDetectorsPath);
requireFields(visualDetectors, visualDetectorsPath, [
  "schemaVersion",
  "status",
  "policy",
  "sourceRoots",
  "requiredChangeKinds",
  "detectors",
]);
const sourcePaths = requireArray(visualDetectors, visualDetectorsPath, "sourceRoots");
const compiledVisualDetectors = [];
for (const [index, detector] of requireArray(visualDetectors, visualDetectorsPath, "detectors").entries()) {
  const label = `${visualDetectorsPath}.detectors[${index}]`;
  requireFields(detector, label, ["id", "changeKind", "pattern", "reason"]);
  try {
    compiledVisualDetectors.push({
      id: detector.id,
      platforms: Array.isArray(detector.platforms) ? detector.platforms : [],
      changeKind: detector.changeKind,
      severity: detector.severity === "report-only" ? "report-only" : "blocking",
      reason: detector.reason,
      regex: new RegExp(detector.pattern),
    });
  } catch (error) {
    fail(`${label}.pattern is not a valid regex: ${error.message}`);
  }
}
const diffArgs = changedBase
  ? ["diff", "--unified=0", changedBase, "--", ...sourcePaths]
  : ["diff", "--unified=0", "--", ...sourcePaths];
const stagedDiffArgs = ["diff", "--cached", "--unified=0", "--", ...sourcePaths];

const visualAuthorizationEnv = String(visualAuthorization.publicSignalEnv || "");
const visualAuthorizationValue = String(visualAuthorization.publicSignalValue || "");
const visualModelEnv = String(visualModelAllowlist?.modelSignal?.env || "");
const requestedVisualModel = visualModelEnv ? String(process.env[visualModelEnv] || "") : "";
const visualAuthorized =
  Boolean(visualAuthorizationEnv) &&
  process.env[visualAuthorizationEnv] === visualAuthorizationValue &&
  Boolean(visualModelEnv) &&
  activeVisualModelIds.has(requestedVisualModel);
const visualScopesPath = "docs/ui/visual-change-scopes.manifest.json";
const visualScopes = readJson(visualScopesPath);
const visualScopeEnv = String(visualScopes?.scopeSignal?.env || "CLAWIX_UI_VISUAL_SCOPE_ID");
const requestedVisualScopeId = visualScopeEnv ? String(process.env[visualScopeEnv] || "") : "";
const simulatedScopeApproval = {
  approvedBy: "user",
  approvedAt: "2026-05-17",
  externalApprovalReference: "external-ui-approval:simulated",
};
const simulatedSourceScope = {
  platforms: ["web"],
  surfaces: ["web-components-and-shell"],
  patterns: ["icon-chip-button"],
};
if (simulateApprovedVisualScope) {
  visualScopes.activeScopes = [
    ...(Array.isArray(visualScopes.activeScopes) ? visualScopes.activeScopes : []),
    {
      id: "simulated-approved-scope",
      status: "approved",
      ...simulatedScopeApproval,
      ...simulatedSourceScope,
      files: ["web/src/simulated-visual-diff.tsx"],
      changeKinds: ["layout", "microcopy"],
      changeBudget: { maxFiles: 1, maxLines: 3, allowedChangeKinds: ["layout", "microcopy"] },
      expiresAt: "2099-12-31",
    },
  ];
}
if (simulateOverbudgetVisualScope) {
  visualScopes.activeScopes = [
    ...(Array.isArray(visualScopes.activeScopes) ? visualScopes.activeScopes : []),
    {
      id: "simulated-overbudget-scope",
      status: "approved",
      ...simulatedScopeApproval,
      ...simulatedSourceScope,
      files: ["web/src/simulated-visual-diff.tsx"],
      changeKinds: ["layout", "microcopy"],
      changeBudget: { maxFiles: 1, maxLines: 1, allowedChangeKinds: ["layout", "microcopy"] },
      expiresAt: "2099-12-31",
    },
  ];
}
if (simulateWrongFileVisualScope) {
  visualScopes.activeScopes = [
    ...(Array.isArray(visualScopes.activeScopes) ? visualScopes.activeScopes : []),
    {
      id: "simulated-wrong-file-scope",
      status: "approved",
      ...simulatedScopeApproval,
      ...simulatedSourceScope,
      files: ["web/src/other-visual-file.tsx"],
      changeKinds: ["layout", "microcopy"],
      changeBudget: { maxFiles: 1, maxLines: 3, allowedChangeKinds: ["layout", "microcopy"] },
      expiresAt: "2099-12-31",
    },
  ];
}
if (simulateLayoutOnlyVisualScope) {
  visualScopes.activeScopes = [
    ...(Array.isArray(visualScopes.activeScopes) ? visualScopes.activeScopes : []),
    {
      id: "simulated-layout-only-scope",
      status: "approved",
      ...simulatedScopeApproval,
      ...simulatedSourceScope,
      files: ["web/src/simulated-visual-diff.tsx"],
      changeKinds: ["layout"],
      changeBudget: { maxFiles: 1, maxLines: 3, allowedChangeKinds: ["layout"] },
      expiresAt: "2099-12-31",
    },
  ];
}
if (simulateRevokedVisualScope) {
  visualScopes.activeScopes = [
    ...(Array.isArray(visualScopes.activeScopes) ? visualScopes.activeScopes : []),
    {
      id: "simulated-revoked-scope",
      status: "revoked",
      ...simulatedScopeApproval,
      ...simulatedSourceScope,
      files: ["web/src/simulated-visual-diff.tsx"],
      changeKinds: ["layout", "microcopy"],
      changeBudget: { maxFiles: 1, maxLines: 3, allowedChangeKinds: ["layout", "microcopy"] },
      expiresAt: "2099-12-31",
    },
  ];
}
if (simulateExpiredVisualScope) {
  visualScopes.activeScopes = [
    ...(Array.isArray(visualScopes.activeScopes) ? visualScopes.activeScopes : []),
    {
      id: "simulated-expired-scope",
      status: "approved",
      ...simulatedScopeApproval,
      ...simulatedSourceScope,
      files: ["web/src/simulated-visual-diff.tsx"],
      changeKinds: ["layout", "microcopy"],
      changeBudget: { maxFiles: 1, maxLines: 3, allowedChangeKinds: ["layout", "microcopy"] },
      expiresAt: "2000-01-01",
    },
  ];
}
if (simulateBudgetKindVisualScope) {
  visualScopes.activeScopes = [
    ...(Array.isArray(visualScopes.activeScopes) ? visualScopes.activeScopes : []),
    {
      id: "simulated-budget-kind-scope",
      status: "approved",
      ...simulatedScopeApproval,
      ...simulatedSourceScope,
      files: ["web/src/simulated-visual-diff.tsx"],
      changeKinds: ["layout", "microcopy"],
      changeBudget: { maxFiles: 1, maxLines: 3, allowedChangeKinds: ["layout"] },
      expiresAt: "2099-12-31",
    },
  ];
}
if (simulateMissingPatternVisualScope) {
  visualScopes.activeScopes = [
    ...(Array.isArray(visualScopes.activeScopes) ? visualScopes.activeScopes : []),
    {
      id: "simulated-missing-pattern-scope",
      status: "approved",
      ...simulatedScopeApproval,
      platforms: ["web"],
      surfaces: ["web-components-and-shell"],
      patterns: ["composer-chrome"],
      files: ["web/src/simulated-visual-diff.tsx"],
      changeKinds: ["layout", "microcopy"],
      changeBudget: { maxFiles: 1, maxLines: 3, allowedChangeKinds: ["layout", "microcopy"] },
      expiresAt: "2099-12-31",
    },
  ];
}
if (simulateDuplicatePatternVisualScope) {
  visualScopes.activeScopes = [
    ...(Array.isArray(visualScopes.activeScopes) ? visualScopes.activeScopes : []),
    {
      id: "simulated-duplicate-pattern-scope",
      status: "approved",
      ...simulatedScopeApproval,
      ...simulatedSourceScope,
      patterns: ["icon-chip-button", "icon-chip-button"],
      files: ["web/src/simulated-visual-diff.tsx"],
      changeKinds: ["layout", "microcopy"],
      changeBudget: { maxFiles: 1, maxLines: 3, allowedChangeKinds: ["layout", "microcopy"] },
      expiresAt: "2099-12-31",
    },
  ];
}
if (simulateInvalidBudgetVisualScope) {
  visualScopes.activeScopes = [
    ...(Array.isArray(visualScopes.activeScopes) ? visualScopes.activeScopes : []),
    {
      id: "simulated-invalid-budget-scope",
      status: "approved",
      ...simulatedScopeApproval,
      ...simulatedSourceScope,
      files: ["web/src/simulated-visual-diff.tsx"],
      changeKinds: ["layout", "microcopy"],
      changeBudget: { maxFiles: 0, maxLines: "3", allowedChangeKinds: ["layout", "microcopy"] },
      expiresAt: "2099-12-31",
    },
  ];
}
if (simulateUnsafeFileVisualScope) {
  visualScopes.activeScopes = [
    ...(Array.isArray(visualScopes.activeScopes) ? visualScopes.activeScopes : []),
    {
      id: "simulated-unsafe-file-scope",
      status: "approved",
      ...simulatedScopeApproval,
      ...simulatedSourceScope,
      files: ["../web/src/simulated-visual-diff.tsx"],
      changeKinds: ["layout", "microcopy"],
      changeBudget: { maxFiles: 1, maxLines: 3, allowedChangeKinds: ["layout", "microcopy"] },
      expiresAt: "2099-12-31",
    },
  ];
}

function fileMatchesScope(file, scopeFiles = []) {
  return scopeFiles.some((scopeFile) => {
    if (scopeFile === file) return true;
    if (scopeFile.endsWith("/**")) return file.startsWith(scopeFile.slice(0, -3));
    return false;
  });
}

function globToRegExp(glob) {
  let output = "^";
  for (let index = 0; index < glob.length; index += 1) {
    const char = glob[index];
    const next = glob[index + 1];
    if (char === "*" && next === "*") {
      output += ".*";
      index += 1;
    } else if (char === "*") {
      output += "[^/]*";
    } else {
      output += char.replace(/[|\\{}()[\]^$+?.]/g, "\\$&");
    }
  }
  return new RegExp(`${output}$`);
}

const visibleInventoryPath = "docs/ui/visible-surfaces.inventory.json";
const visibleInventory = readJson(visibleInventoryPath);
const visibleCoverage = requireArray(visibleInventory, visibleInventoryPath, "coverage").map((entry) => ({
  id: entry?.id,
  platform: entry?.platform,
  classification: entry?.classification,
  patterns: Array.isArray(entry?.patterns) ? entry.patterns : [],
  scopes: Array.isArray(entry?.scopes) ? entry.scopes.map((scope) => globToRegExp(scope)) : [],
  excludeScopes: Array.isArray(entry?.excludeScopes) ? entry.excludeScopes.map((scope) => globToRegExp(scope)) : [],
}));

function inventoryMatchesForFile(file) {
  const platform = platformForPath(file);
  return visibleCoverage.filter((entry) => {
    if (entry.platform !== platform) return false;
    if (entry.excludeScopes.some((scope) => scope.test(file))) return false;
    return entry.scopes.some((scope) => scope.test(file));
  });
}

function isIsoDate(value) {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value) && !Number.isNaN(Date.parse(value));
}

function isSafePrivateApprovalReference(value) {
  if (typeof value !== "string" || !value.startsWith("external-ui-approval:")) return false;
  const suffix = value.slice("external-ui-approval:".length);
  return Boolean(
    suffix &&
      !suffix.startsWith("/") &&
      !suffix.startsWith("\\") &&
      !suffix.startsWith("~/") &&
      !suffix.includes("..") &&
      !/^[A-Z]:\\/.test(suffix) &&
      !value.includes("/Users/") &&
      !value.startsWith("file://"),
  );
}

function requireScopeStringSet(values, fieldName) {
  if (!Array.isArray(values) || values.length === 0) {
    return { ok: false, reason: `scope ${requestedVisualScopeId} must declare ${fieldName}` };
  }
  const seen = new Set();
  for (const value of values) {
    if (typeof value !== "string" || value.length === 0) {
      return { ok: false, reason: `scope ${requestedVisualScopeId} ${fieldName} must only include non-empty strings` };
    }
    if (seen.has(value)) {
      return { ok: false, reason: `scope ${requestedVisualScopeId} ${fieldName} duplicates ${value}` };
    }
    seen.add(value);
  }
  return { ok: true, values: seen, list: values };
}

function isSafeScopeFile(value) {
  return (
    typeof value === "string" &&
    value.length > 0 &&
    !value.startsWith("/") &&
    !value.startsWith("\\") &&
    !value.startsWith("~/") &&
    !value.includes("..") &&
    !value.includes("\\") &&
    !value.includes(":")
  );
}

function approvedScopeForHits(hits) {
  if (!requestedVisualScopeId) return { ok: false, reason: `${visualScopeEnv}=<approved visual scope id> is required` };
  const scope = (visualScopes?.activeScopes || []).find((candidate) => candidate?.id === requestedVisualScopeId);
  if (!scope) return { ok: false, reason: `scope ${requestedVisualScopeId} is not listed in ${visualScopesPath}.activeScopes` };
  if (scope.status !== "approved") return { ok: false, reason: `scope ${requestedVisualScopeId} is ${scope.status}, not approved` };
  if (scope.expiresAt && scope.expiresAt < today) return { ok: false, reason: `scope ${requestedVisualScopeId} expired on ${scope.expiresAt}` };
  if (scope.approvedBy !== "user") return { ok: false, reason: `scope ${requestedVisualScopeId} must be approvedBy user` };
  if (!isIsoDate(scope.approvedAt)) return { ok: false, reason: `scope ${requestedVisualScopeId} must include approvedAt ISO date` };
  if (!isSafePrivateApprovalReference(scope.externalApprovalReference)) {
    return { ok: false, reason: `scope ${requestedVisualScopeId} must include safe external approval reference` };
  }

  const files = new Set(hits.map((hit) => hit.path));
  const changeKinds = new Set(hits.map((hit) => hit.changeKind));
  const hitPlatforms = new Set([...files].map(platformForPath).filter(Boolean));
  const scopePlatformsResult = requireScopeStringSet(scope.platforms, "platforms");
  if (!scopePlatformsResult.ok) return scopePlatformsResult;
  const scopeSurfacesResult = requireScopeStringSet(scope.surfaces, "surfaces");
  if (!scopeSurfacesResult.ok) return scopeSurfacesResult;
  const scopePatternsResult = requireScopeStringSet(scope.patterns, "patterns");
  if (!scopePatternsResult.ok) return scopePatternsResult;
  const scopeFilesResult = requireScopeStringSet(scope.files, "files");
  if (!scopeFilesResult.ok) return scopeFilesResult;
  const scopeChangeKindsResult = requireScopeStringSet(scope.changeKinds, "changeKinds");
  if (!scopeChangeKindsResult.ok) return scopeChangeKindsResult;
  const scopePlatforms = scopePlatformsResult.values;
  const scopeSurfaces = scopeSurfacesResult.values;
  const scopePatterns = scopePatternsResult.values;
  const scopeFiles = scopeFilesResult.list;
  const scopeChangeKinds = scopeChangeKindsResult.values;
  const changeBudget = scope.changeBudget || {};
  for (const scopeFile of scopeFiles) {
    if (!isSafeScopeFile(scopeFile)) {
      return { ok: false, reason: `scope ${requestedVisualScopeId} files must use safe repo-relative paths` };
    }
  }
  if (!Number.isInteger(changeBudget.maxFiles) || changeBudget.maxFiles < 1) {
    return { ok: false, reason: `scope ${requestedVisualScopeId} changeBudget.maxFiles must be a positive integer` };
  }
  if (!Number.isInteger(changeBudget.maxLines) || changeBudget.maxLines < 1) {
    return { ok: false, reason: `scope ${requestedVisualScopeId} changeBudget.maxLines must be a positive integer` };
  }
  const budgetChangeKindsResult = requireScopeStringSet(changeBudget.allowedChangeKinds, "changeBudget.allowedChangeKinds");
  if (!budgetChangeKindsResult.ok) return budgetChangeKindsResult;
  const budgetChangeKinds = budgetChangeKindsResult.values;

  for (const file of files) {
    if (!fileMatchesScope(file, scopeFiles)) return { ok: false, reason: `scope ${requestedVisualScopeId} does not include ${file}` };
  }
  for (const platform of hitPlatforms) {
    if (!scopePlatforms.has(platform)) return { ok: false, reason: `scope ${requestedVisualScopeId} does not include platform ${platform}` };
  }
  for (const file of files) {
    const matches = inventoryMatchesForFile(file);
    if (matches.length === 0) return { ok: false, reason: `scope ${requestedVisualScopeId} cannot map ${file} to a visible surface` };
    for (const match of matches) {
      if (!scopeSurfaces.has(match.id)) return { ok: false, reason: `scope ${requestedVisualScopeId} does not include surface ${match.id}` };
      if (match.patterns.length > 0 && !match.patterns.some((pattern) => scopePatterns.has(pattern))) {
        return { ok: false, reason: `scope ${requestedVisualScopeId} does not include a pattern for surface ${match.id}` };
      }
    }
  }
  for (const changeKind of changeKinds) {
    if (!scopeChangeKinds.has(changeKind)) {
      return { ok: false, reason: `scope ${requestedVisualScopeId} does not allow ${changeKind}` };
    }
  }
  for (const changeKind of changeKinds) {
    if (!budgetChangeKinds.has(changeKind)) {
      return { ok: false, reason: `scope ${requestedVisualScopeId} changeBudget does not allow ${changeKind}` };
    }
  }
  if (Number.isInteger(changeBudget.maxFiles) && files.size > changeBudget.maxFiles) {
    return { ok: false, reason: `scope ${requestedVisualScopeId} maxFiles budget exceeded` };
  }
  if (Number.isInteger(changeBudget.maxLines) && hits.length > changeBudget.maxLines) {
    return { ok: false, reason: `scope ${requestedVisualScopeId} maxLines budget exceeded` };
  }
  return { ok: true, scope };
}

function platformForPath(file) {
  if (file.startsWith("macos/Sources/") || file.startsWith("apps/macos/Sources/")) return "macos";
  if (file.startsWith("ios/Sources/") || file.startsWith("apps/ios/Sources/")) return "ios";
  if (file.startsWith("android/app/src/main/")) return "android";
  if (file.startsWith("web/src/")) return "web";
  return null;
}

function matchingVisualDetector(line, file) {
  const platform = platformForPath(file);
  return compiledVisualDetectors.find((detector) => {
    if (platform && !detector.platforms.includes(platform)) return false;
    return detector.regex.test(line);
  });
}

function visualDiffHits(diffText, sourceLabel) {
  const hits = [];
  let currentPath = "<unknown>";
  let nextOldLine = 0;
  let nextNewLine = 0;

  for (const line of diffText.split("\n")) {
    if (line.startsWith("--- a/")) {
      currentPath = line.slice("--- a/".length);
      continue;
    }

    if (line.startsWith("+++ b/")) {
      currentPath = line.slice("+++ b/".length);
      continue;
    }

    if (line.startsWith("@@ ")) {
      const oldMatch = /-(\d+)(?:,\d+)?/.exec(line);
      const newMatch = /\+(\d+)(?:,\d+)?/.exec(line);
      nextOldLine = oldMatch ? Number(oldMatch[1]) : 0;
      nextNewLine = newMatch ? Number(newMatch[1]) : 0;
      continue;
    }

    if (line.startsWith("+") && !line.startsWith("+++")) {
      const detector = matchingVisualDetector(line, currentPath);
      if (detector) {
        hits.push({
          path: currentPath,
          line: nextNewLine || "?",
          source: sourceLabel,
          operation: "added",
          detector: detector.id,
          changeKind: detector.changeKind,
          severity: detector.severity,
          reason: detector.reason,
          text: line.slice(1, 241),
        });
      }
      nextNewLine += 1;
      continue;
    }

    if (line.startsWith("-") && !line.startsWith("---")) {
      const detector = matchingVisualDetector(line, currentPath);
      if (detector) {
        hits.push({
          path: currentPath,
          line: nextOldLine || "?",
          source: sourceLabel,
          operation: "removed",
          detector: detector.id,
          changeKind: detector.changeKind,
          severity: detector.severity,
          reason: detector.reason,
          text: line.slice(1, 241),
        });
      }
      nextOldLine += 1;
      continue;
    }

    if (line.startsWith(" ") || line === "\\ No newline at end of file") {
      nextOldLine += 1;
      nextNewLine += 1;
    }
  }

  return hits;
}

const simulatedVisualDiff = [
  "diff --git a/web/src/simulated-visual-diff.tsx b/web/src/simulated-visual-diff.tsx",
  "+++ b/web/src/simulated-visual-diff.tsx",
  "@@ -1,3 +1,2 @@",
  '+<button className="gap-2 text-red-500" aria-label="Rename">Rename</button>',
  '+const visibleModelOptions = ["visible-model-alpha", "visible-model-beta"];',
  '-<div className="gap-2 text-blue-500">Legacy</div>',
].join("\n");
const simulatedCrossPlatformVisualDiff = [
  "diff --git a/macos/Sources/SimulatedVisual.swift b/macos/Sources/SimulatedVisual.swift",
  "+++ b/macos/Sources/SimulatedVisual.swift",
  "@@ -1,0 +1,3 @@",
  '+Text("Rename").font(.headline).foregroundColor(.red)',
  '+HStack { Image(systemName: "square.and.pencil") }.padding(8)',
  "diff --git a/ios/Sources/SimulatedVisual.swift b/ios/Sources/SimulatedVisual.swift",
  "+++ b/ios/Sources/SimulatedVisual.swift",
  "@@ -1,0 +1,2 @@",
  '+VStack { Text("Rename") }.background(Color.blue)',
  '+Image(systemName: "chevron.right").accessibilityLabel("Open")',
  "diff --git a/android/app/src/main/SimulatedVisual.kt b/android/app/src/main/SimulatedVisual.kt",
  "+++ b/android/app/src/main/SimulatedVisual.kt",
  "@@ -1,0 +1,3 @@",
  '+Text("Rename", modifier = Modifier.padding(8.dp), fontSize = 14.sp)',
  "+Icon(Icons.Default.Edit, contentDescription = \"Rename\")",
  "diff --git a/web/src/simulated-visual-diff.tsx b/web/src/simulated-visual-diff.tsx",
  "+++ b/web/src/simulated-visual-diff.tsx",
  "@@ -1,0 +1,2 @@",
  '+<button className="gap-2 text-red-500" aria-label="Rename">Rename</button>',
  '+const visibleModelOptions = ["visible-model-alpha", "visible-model-beta"];',
].join("\n");
const simulatedReportOnlyFunctionalDiff = [
  "diff --git a/macos/Sources/SimulatedFunctional.swift b/macos/Sources/SimulatedFunctional.swift",
  "+++ b/macos/Sources/SimulatedFunctional.swift",
  "@@ -1,0 +1,8 @@",
  "+private var order: [String] = []",
  "+let offset = max(0, cursor - limit)",
  '+let title = metadata.title',
  "+// sidebar and chat are mentioned here as technical routing context.",
  "+// header and section are internal parser terms, not visible UI.",
].join("\n");
const visualHits = simulateCrossPlatformVisualDiff
  ? visualDiffHits(simulatedCrossPlatformVisualDiff, "simulated cross-platform visual diff")
  : simulateUnauthorizedVisualDiff
  ? visualDiffHits(simulatedVisualDiff, "simulated unauthorized visual diff")
  : simulateReportOnlyFunctionalDiff
  ? visualDiffHits(simulatedReportOnlyFunctionalDiff, "simulated report-only functional diff")
  : [
      ...visualDiffHits(git(diffArgs), changedBase ? `diff against ${changedBase}` : "working tree"),
      ...(changedBase ? [] : visualDiffHits(git(stagedDiffArgs), "staged")),
    ];
const blockingVisualHits = visualHits.filter((hit) => hit.severity !== "report-only");
const reportOnlyVisualHits = visualHits.filter((hit) => hit.severity === "report-only");
function visualHitLine(hit) {
  return `  ${hit.path}:${hit.line} [${hit.source}/${hit.operation}/${hit.detector}/${hit.changeKind}/${hit.severity}] reason=${hit.reason} text=${hit.text}`;
}
if (blockingVisualHits.length > 0 && !visualAuthorized) {
  fail(
    [
      "unauthorized visual/copy/layout source edit detected",
      `required permission: ${visualAuthorizationEnv}=${visualAuthorizationValue} and ${visualModelEnv}=<active visual model from ${visualModelAllowlistPath}>`,
      `current model signal: ${visualModelEnv || "<unset>"}=${requestedVisualModel || "<unset>"}`,
      `proposal route: ${visualModelAllowlist?.proposalPath || "docs/ui/visual-change-proposal.template.md"}`,
      "non-authorized agents must leave a conceptual proposal instead of editing visible presentation",
      ...blockingVisualHits
        .slice(0, 20)
        .map(visualHitLine),
      ...reportOnlyVisualHits
        .slice(0, 10)
        .map((hit) => `  report-only ${visualHitLine(hit).trimStart()}`),
    ].join("\n"),
  );
}
if (blockingVisualHits.length > 0 && visualAuthorized) {
  const scopeResult = approvedScopeForHits(blockingVisualHits);
  if (!scopeResult.ok) {
    fail(
      [
        "authorized visual/copy/layout source edit missing approved scope",
        `required scope: ${visualScopeEnv}=<approved scope from ${visualScopesPath}>`,
        `current scope signal: ${visualScopeEnv}=${requestedVisualScopeId || "<unset>"}`,
        `reason: ${scopeResult.reason}`,
        `proposal route: ${visualModelAllowlist?.proposalPath || "docs/ui/visual-change-proposal.template.md"}`,
        ...blockingVisualHits
          .slice(0, 20)
          .map(visualHitLine),
        ...reportOnlyVisualHits
          .slice(0, 10)
          .map((hit) => `  report-only ${visualHitLine(hit).trimStart()}`),
      ].join("\n"),
    );
  }
}

const requiredDocs = [
  "docs/adr/0010-interface-governance.md",
  "docs/ui/README.md",
  "docs/ui/decision-verification.json",
  "docs/ui/pattern-registry/README.md",
  "docs/ui/pattern-registry/patterns/notes.md",
  "docs/ui/interface-governance.config.json",
  "docs/ui/implementation-evidence.manifest.json",
  "docs/ui/implementation-phases.manifest.json",
  "docs/ui/state-coverage.manifest.json",
  "docs/ui/surface-references.manifest.json",
  "docs/ui/surface-baseline-coverage.manifest.json",
  "docs/ui/rendered-drift.manifest.json",
  "docs/ui/gate-surface.manifest.json",
  "docs/ui/visual-model-allowlist.manifest.json",
  "docs/ui/component-extraction.manifest.json",
  "docs/ui/mechanical-equivalence.manifest.json",
  "docs/ui/visible-surfaces.inventory.json",
  "docs/ui/rendered-geometry.manifest.json",
  "docs/ui/copy.inventory.json",
  "docs/ui/pattern-performance.manifest.json",
  "docs/ui/visual-change-scopes.manifest.json",
  "docs/ui/visual-change-detectors.manifest.json",
  "docs/ui/visual-proposals.registry.json",
  "docs/ui/debt.baseline.json",
  "docs/ui/debt-baseline.manifest.json",
  "docs/ui/debt-report.registry.json",
  "docs/ui/debt-audit.manifest.json",
  "docs/ui/critical-cleanup.queue.json",
  "docs/ui/exceptions.registry.json",
  "docs/ui/protected-surfaces.registry.json",
  "docs/ui/approval-authority.manifest.json",
  "docs/ui/canon-units.manifest.json",
  "docs/ui/canon-promotions.registry.json",
  "docs/ui/performance-budgets.registry.json",
  "docs/ui/private-baselines.manifest.json",
  "docs/ui/private-visual-validation.manifest.json",
  "docs/ui/visual-change-proposal.template.md",
  "docs/ui/inspiration/references.registry.json",
];
for (const relativePath of requiredDocs) {
  if (!fs.existsSync(path.join(rootDir, relativePath))) {
    fail(`missing required UI governance file ${relativePath}`);
  }
}

if (errors.length === 0 && !isSelfTest && rawArgs.length === 0) {
  const visualAuthEnv = visualAuthorizationEnv ? { [visualAuthorizationEnv]: visualAuthorizationValue } : {};
  const visualModelEnvObject = visualModelEnv && activeVisualModelIds.size > 0 ? { [visualModelEnv]: [...activeVisualModelIds][0] } : {};
  const sanitizedSelfTestEnv = { ...process.env };
  if (visualAuthorizationEnv) delete sanitizedSelfTestEnv[visualAuthorizationEnv];
  if (visualModelEnv) delete sanitizedSelfTestEnv[visualModelEnv];
  if (visualScopeEnv) delete sanitizedSelfTestEnv[visualScopeEnv];
  const baseSelfTestEnv = {
    ...sanitizedSelfTestEnv,
    CLAWIX_UI_GOVERNANCE_GUARD_SELF_TEST: "1",
  };
  const authorizedEnv = {
    ...baseSelfTestEnv,
    ...visualAuthEnv,
    ...visualModelEnvObject,
  };
  const runFailingSelfTest = (selfTestArgs, expectedOutput, env = baseSelfTestEnv) => {
    const result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, ...selfTestArgs], {
      cwd: rootDir,
      env,
      encoding: "utf8",
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status === 0) {
      fail(`self-test ${selfTestArgs.join(" ")} must fail when UI governance authorization is invalid`);
      return;
    }
    if (!output.includes(expectedOutput)) {
      fail(`self-test ${selfTestArgs.join(" ")} output must include ${expectedOutput}`);
    }
  };
  const runPassingSelfTest = (selfTestArgs, env, expectedOutput = "") => {
    const result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, ...selfTestArgs], {
      cwd: rootDir,
      env,
      encoding: "utf8",
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status !== 0) {
      fail(`self-test ${selfTestArgs.join(" ")} must pass; output: ${output}`);
      return;
    }
    if (expectedOutput && !output.includes(expectedOutput)) {
      fail(`self-test ${selfTestArgs.join(" ")} output must include ${expectedOutput}`);
    }
  };

  for (const [selfTestArgs, expectedOutput, env] of [
    [["--unknown-flag"], "received unknown flag --unknown-flag"],
    [["--simulate-unauthorized-visual-diff"], "unauthorized visual/copy/layout source edit detected"],
    [["--simulate-cross-platform-visual-diff"], "simulated cross-platform visual diff"],
    [["--simulate-unauthorized-visual-diff"], `${visualScopeEnv}=<approved visual scope id> is required`, authorizedEnv],
    [
      ["--simulate-unauthorized-visual-diff", "--simulate-overbudget-visual-scope"],
      "scope simulated-overbudget-scope maxLines budget exceeded",
      { ...authorizedEnv, [visualScopeEnv]: "simulated-overbudget-scope" },
    ],
    [
      ["--simulate-unauthorized-visual-diff", "--simulate-wrong-file-visual-scope"],
      "scope simulated-wrong-file-scope does not include web/src/simulated-visual-diff.tsx",
      { ...authorizedEnv, [visualScopeEnv]: "simulated-wrong-file-scope" },
    ],
    [
      ["--simulate-unauthorized-visual-diff", "--simulate-layout-only-visual-scope"],
      "scope simulated-layout-only-scope does not allow microcopy",
      { ...authorizedEnv, [visualScopeEnv]: "simulated-layout-only-scope" },
    ],
    [
      ["--simulate-unauthorized-visual-diff", "--simulate-revoked-visual-scope"],
      "scope simulated-revoked-scope is revoked, not approved",
      { ...authorizedEnv, [visualScopeEnv]: "simulated-revoked-scope" },
    ],
    [
      ["--simulate-unauthorized-visual-diff", "--simulate-expired-visual-scope"],
      "scope simulated-expired-scope expired on 2000-01-01",
      { ...authorizedEnv, [visualScopeEnv]: "simulated-expired-scope" },
    ],
    [
      ["--simulate-unauthorized-visual-diff", "--simulate-budget-kind-visual-scope"],
      "scope simulated-budget-kind-scope changeBudget does not allow microcopy",
      { ...authorizedEnv, [visualScopeEnv]: "simulated-budget-kind-scope" },
    ],
    [
      ["--simulate-unauthorized-visual-diff", "--simulate-missing-pattern-visual-scope"],
      "scope simulated-missing-pattern-scope does not include a pattern for surface web-components-and-shell",
      { ...authorizedEnv, [visualScopeEnv]: "simulated-missing-pattern-scope" },
    ],
    [
      ["--simulate-unauthorized-visual-diff", "--simulate-duplicate-pattern-visual-scope"],
      "scope simulated-duplicate-pattern-scope patterns duplicates icon-chip-button",
      { ...authorizedEnv, [visualScopeEnv]: "simulated-duplicate-pattern-scope" },
    ],
    [
      ["--simulate-unauthorized-visual-diff", "--simulate-invalid-budget-visual-scope"],
      "scope simulated-invalid-budget-scope changeBudget.maxFiles must be a positive integer",
      { ...authorizedEnv, [visualScopeEnv]: "simulated-invalid-budget-scope" },
    ],
    [
      ["--simulate-unauthorized-visual-diff", "--simulate-unsafe-file-visual-scope"],
      "scope simulated-unsafe-file-scope files must use safe repo-relative paths",
      { ...authorizedEnv, [visualScopeEnv]: "simulated-unsafe-file-scope" },
    ],
  ]) {
    runFailingSelfTest(selfTestArgs, expectedOutput, env);
  }
  runPassingSelfTest(
    ["--simulate-unauthorized-visual-diff", "--simulate-approved-visual-scope"],
    { ...authorizedEnv, [visualScopeEnv]: "simulated-approved-scope" },
  );
  runPassingSelfTest(
    ["--simulate-report-only-functional-diff"],
    baseSelfTestEnv,
    "report-only visual/copy/layout source findings",
  );
}

if (errors.length > 0) {
  console.error("UI governance guard failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

if (reportOnlyVisualHits.length > 0) {
  console.error("UI governance guard report-only visual/copy/layout source findings:");
  for (const hit of reportOnlyVisualHits.slice(0, 20)) {
    console.error(visualHitLine(hit));
  }
}

console.log("UI governance guard passed");
