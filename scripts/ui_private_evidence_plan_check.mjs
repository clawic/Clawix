#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = process.argv.slice(2);
const argSet = new Set(args);
const isSelfTest = process.env.CLAWIX_UI_PRIVATE_EVIDENCE_PLAN_SELF_TEST === "1";
const simulationFlags = [
  "--simulate-unsafe-surface-baseline-reference",
  "--simulate-unsafe-flow-baseline-reference",
  "--simulate-path-evidence-filename",
  "--simulate-duplicate-surface-required-field",
  "--simulate-unsafe-surface-required-field",
  "--simulate-empty-pattern-geometry-fields",
  "--simulate-duplicate-pattern-geometry-field",
  "--simulate-missing-rendered-drift-plan",
  "--simulate-missing-performance-budget-fields",
  "--simulate-flow-duplicate-required-field",
  "--simulate-missing-surface-coverage-entry",
  "--simulate-missing-pattern-registry-entry",
  "--simulate-private-validation-wrong-evidence-plan-command",
  "--simulate-private-validation-missing-blocker",
  "--simulate-private-validation-extra-blocker",
  "--simulate-private-validation-wrong-evidence-type",
  "--simulate-duplicate-evidence-record",
];
const optionsWithValues = new Set(["--write-template-root"]);
const allowedFlags = new Set(["--json", "--capture-plan", "--capture-status", "--capture-packages", "--capture-decisions", "--force-template-root", ...optionsWithValues, ...simulationFlags]);
const errors = [];
const plan = [];

function fail(message) {
  errors.push(message);
}

for (const arg of args) {
  if (arg.startsWith("--") && !allowedFlags.has(arg)) {
    console.error(`UI private evidence plan check received unknown flag ${arg}.`);
    process.exit(1);
  }
}

function optionValue(name) {
  const index = args.indexOf(name);
  if (index === -1) return null;
  const value = args[index + 1] || null;
  if (!value || value.startsWith("--")) {
    console.error(`UI private evidence plan check option ${name} requires a value.`);
    process.exit(1);
  }
  return value;
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

function requireArray(object, label, field, { nonEmpty = true } = {}) {
  const value = object?.[field];
  if (!Array.isArray(value)) {
    fail(`${label}.${field} must be an array`);
    return [];
  }
  if (nonEmpty && value.length === 0) fail(`${label}.${field} must not be empty`);
  return value;
}

function requireFields(object, label, fields) {
  if (!object) return;
  for (const field of fields) {
    if (object[field] === undefined || object[field] === null || object[field] === "") {
      fail(`${label} is missing ${field}`);
    }
  }
}

function assertPublicSafeReference(reference, alias, label) {
  if (typeof reference !== "string" || !reference.startsWith(`${alias}:`)) {
    fail(`${label} must use ${alias}:`);
    return null;
  }
  const suffix = reference.slice(alias.length + 1);
  if (!suffix || suffix.startsWith("/") || suffix.startsWith("\\") || suffix.startsWith("~/") || suffix.includes("..") || /^[A-Z]:\\/.test(suffix)) {
    fail(`${label} must use a safe relative private reference`);
  }
  if (/^\/Users\//.test(reference) || reference.startsWith("~/") || reference.startsWith("file://") || /^[A-Z]:\\/.test(reference)) {
    fail(`${label} must not contain a local absolute path`);
  }
  return suffix;
}

function assertSafeEvidenceFilename(filename, label) {
  if (typeof filename !== "string" || filename.trim() !== filename || filename.length === 0) {
    fail(`${label}.evidenceFilename must be a non-empty filename`);
    return;
  }
  if (
    path.isAbsolute(filename) ||
    filename.startsWith("~/") ||
    filename.includes("/") ||
    filename.includes("\\") ||
    filename.includes("..")
  ) {
    fail(`${label}.evidenceFilename must be a safe filename, not a path`);
  }
  if (!filename.endsWith(".json")) {
    fail(`${label}.evidenceFilename must be a JSON evidence file`);
  }
}

function assertSafeIdentifier(value, label) {
  if (typeof value !== "string" || value.length === 0) {
    fail(`${label} must be a non-empty string`);
    return;
  }
  if (/^\/Users\//.test(value) || value.startsWith("~/") || value.startsWith("file://") || /^[A-Z]:\\/.test(value)) {
    fail(`${label} must not contain a local absolute path`);
  }
}

function requireUniqueStringArray(values, label) {
  if (!Array.isArray(values)) {
    fail(`${label} must be an array`);
    return new Set();
  }
  if (values.length === 0) {
    fail(`${label} must not be empty`);
    return new Set();
  }
  const seen = new Set();
  for (const value of values) {
    if (typeof value !== "string" || value.length === 0) {
      fail(`${label} must only include non-empty strings`);
      continue;
    }
    if (value.includes("/") || value.includes("\\") || value.includes("..")) {
      fail(`${label} contains unsafe field name ${value}`);
    }
    if (seen.has(value)) fail(`${label} duplicates ${value}`);
    seen.add(value);
  }
  return seen;
}

function requireExactStringArray(values, label, expectedValues) {
  const seen = requireUniqueStringArray(values, label);
  if (values.length !== expectedValues.length || values.some((value, index) => value !== expectedValues[index])) {
    fail(`${label} must match ${JSON.stringify(expectedValues)}`);
  }
  return seen;
}

function splitPrivateReference(reference) {
  if (typeof reference !== "string" || !reference.includes(":")) return null;
  const [alias, ...suffixParts] = reference.split(":");
  const suffix = suffixParts.join(":");
  if (!alias || !suffix) return null;
  return { alias, suffix };
}

const idFieldByEvidenceType = new Map([
  ["surface-baseline", "coverageId"],
  ["surface-geometry", "coverageId"],
  ["surface-copy", "coverageId"],
  ["critical-flow-baseline", "flowId"],
  ["pattern-geometry", "patternId"],
  ["rendered-drift", "coverageId"],
  ["debt-audit", "debtId"],
  ["performance-budget", "flowId"],
  ["mechanical-equivalence", "recordId"],
]);

const referenceFieldByEvidenceType = new Map([
  ["surface-baseline", "privateBaselineReference"],
  ["surface-geometry", "geometryEvidenceReference"],
  ["surface-copy", "copySnapshotReference"],
  ["critical-flow-baseline", "privateBaselineReference"],
  ["pattern-geometry", "geometryEvidenceReference"],
  ["rendered-drift", "privateDriftReportReference"],
  ["debt-audit", "privateDebtAuditReference"],
  ["performance-budget", "privateBaselineReference"],
  ["mechanical-equivalence", "privateEvidenceReference"],
]);

function approvedScopeTemplate() {
  const fields = Array.isArray(privateValidation?.requiredApprovedScopeFields)
    ? privateValidation.requiredApprovedScopeFields
    : ["scopeId", "approvedBy", "approvedAt", "privateApprovalReference"];
  return Object.fromEntries(fields.map((field) => [field, null]));
}

function debtAuditEntryFor(item) {
  return (debtAudit?.entries || []).find((entry) => entry?.debtId === item.id);
}

function renderedDriftReportFor(item) {
  return (renderedDrift?.reports || []).find((report) => report?.coverageId === item.id && report?.platform === item.platform);
}

function templateValueForField(field, item) {
  if (field === "platform") return item.platform;
  if (field === idFieldByEvidenceType.get(item.type)) return item.id;
  if (field === referenceFieldByEvidenceType.get(item.type)) return item.privateReference;
  if (field === "approvedScope") return approvedScopeTemplate();
  if (["approvedByUserAt", "measuredAt", "auditedAt", "producedAt"].includes(field)) return null;
  if (/Hash$/.test(field)) return null;
  if (field === "captureCommand") return null;
  if (field === "measurements") return {};
  if (field === "metrics") {
    return Object.fromEntries((performanceBudgets?.requiredMetrics || []).map((metric) => [metric, null]));
  }
  if (field === "measurementSamples") {
    return (performanceBudgets?.requiredMetrics || []).map((metric) => ({
      metric,
      value: null,
      sampleHash: null,
    }));
  }
  if (field === "copyItems") {
    return [{
      kind: null,
      textHash: null,
      source: null,
    }];
  }
  if (field === "driftCategories") return renderedDriftReportFor(item)?.driftCategories || [];
  if (field === "driftResults") {
    return Object.fromEntries((renderedDriftReportFor(item)?.driftCategories || []).map((category) => [
      category,
      {
        status: null,
        resultHash: null,
      },
    ]));
  }
  if (field === "status") return renderedDriftReportFor(item)?.status || null;
  if (field === "findingItems") {
    return [{
      category: null,
      source: null,
      itemHash: null,
    }];
  }
  if (field === "scope") return debtAuditEntryFor(item)?.scope || null;
  if (field === "platforms") return debtAuditEntryFor(item)?.platforms || [];
  return null;
}

function evidenceTemplateForItem(item) {
  const template = {
    _templateStatus: "placeholder-not-valid-evidence",
    _templateNote: "Fill from private captured evidence. Do not treat null placeholders as approval.",
  };
  for (const field of item.requiredFields || []) {
    template[field] = templateValueForField(field, item);
  }
  return template;
}

function assertOutsidePublicRepo(outputRootRaw) {
  const outputRoot = path.resolve(outputRootRaw);
  const relativeToRepo = path.relative(rootDir, outputRoot);
  if (!relativeToRepo.startsWith("..") && !path.isAbsolute(relativeToRepo)) {
    fail("--write-template-root must point outside the public repository");
    return null;
  }
  return outputRoot;
}

function writeJsonTemplate(file, value, { force }) {
  if (fs.existsSync(file) && !force) {
    fail(`${file} already exists; pass --force-template-root to overwrite generated templates`);
    return;
  }
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);
}

function writeTemplateRoot(outputRootRaw) {
  const outputRoot = assertOutsidePublicRepo(outputRootRaw);
  if (!outputRoot) return;
  const capturePlan = capturePlanFromEvidencePlan();
  if (errors.length > 0) return;
  const force = args.includes("--force-template-root");
  fs.mkdirSync(outputRoot, { recursive: true });
  writeJsonTemplate(path.join(outputRoot, "capture-template-index.json"), {
    schemaVersion: 1,
    status: "placeholder-not-valid-evidence",
    note: "Templates are field-shape checklists only. Replace null values with approved private evidence before verification.",
    totalRecords: capturePlan.totalRecords,
    roots: capturePlan.roots.map((root) => ({
      alias: root.alias,
      env: root.env,
      required: root.required,
      recordCount: root.recordCount,
      evidenceTypes: root.evidenceTypes,
    })),
    completionBlockers: capturePlan.completionBlockers,
  }, { force });
  for (const root of capturePlan.roots) {
    for (const record of root.records) {
      writeJsonTemplate(path.join(outputRoot, root.alias, record.relativeEvidencePath), {
        _rootAlias: root.alias,
        _rootEnv: root.env,
        _relativeEvidencePath: record.relativeEvidencePath,
        ...record.evidenceTemplate,
      }, { force });
    }
  }
  if (errors.length === 0) {
    console.log(`UI private evidence template root written (${capturePlan.totalRecords} placeholder files): ${outputRoot}`);
  }
}

function emptyCaptureStatusCounts() {
  return {
    missingRoot: 0,
    invalidRoot: 0,
    missingFile: 0,
    invalidJson: 0,
    placeholder: 0,
    candidate: 0,
  };
}

function addCaptureStatus(left, right) {
  for (const key of Object.keys(left)) left[key] += right[key] || 0;
}

function captureStatusForFile(rootPath, relativeEvidencePath) {
  const counts = emptyCaptureStatusCounts();
  const evidencePath = path.join(rootPath, relativeEvidencePath.split("/").join(path.sep));
  if (!fs.existsSync(evidencePath)) {
    counts.missingFile += 1;
    return { state: "missing-file", counts };
  }
  let evidence = null;
  try {
    evidence = JSON.parse(fs.readFileSync(evidencePath, "utf8"));
  } catch {
    counts.invalidJson += 1;
    return { state: "invalid-json", counts };
  }
  if (evidence?._templateStatus === "placeholder-not-valid-evidence") {
    counts.placeholder += 1;
    return { state: "placeholder", counts };
  }
  counts.candidate += 1;
  return { state: "candidate", counts };
}

function privateRootState(root) {
  const counts = emptyCaptureStatusCounts();
  const rootPathRaw = process.env[root.env] || "";
  if (!rootPathRaw) {
    counts.missingRoot = root.recordCount;
    return {
      configured: false,
      status: "external-pending-missing-root",
      rootPath: null,
      counts,
      stateForRecord: () => "missing-root",
    };
  }
  const rootPath = path.resolve(rootPathRaw);
  const relativeToRepo = path.relative(rootDir, rootPath);
  if (!relativeToRepo.startsWith("..") && !path.isAbsolute(relativeToRepo)) {
    counts.invalidRoot = root.recordCount;
    return {
      configured: true,
      status: "invalid-root-inside-public-repo",
      rootPath,
      counts,
      stateForRecord: () => "invalid-root",
    };
  }
  if (!fs.existsSync(rootPath) || !fs.statSync(rootPath).isDirectory()) {
    counts.missingRoot = root.recordCount;
    return {
      configured: true,
      status: "external-pending-root-not-found",
      rootPath,
      counts,
      stateForRecord: () => "missing-root",
    };
  }
  return {
    configured: true,
    status: "configured",
    rootPath,
    counts,
    stateForRecord: (record) => captureStatusForFile(rootPath, record.relativeEvidencePath).state,
  };
}

function captureStatusFromEvidencePlan() {
  const capturePlan = capturePlanFromEvidencePlan();
  if (errors.length > 0) return null;
  const recordStates = new Map();
  const roots = capturePlan.roots.map((root) => {
    const rootState = privateRootState(root);
    const rootStatus = {
      alias: root.alias,
      env: root.env,
      required: root.required,
      recordCount: root.recordCount,
      configured: rootState.configured,
      status: rootState.status,
      counts: rootState.counts,
    };
    for (const record of root.records) {
      if (rootState.status === "configured") {
        const fileStatus = captureStatusForFile(rootState.rootPath, record.relativeEvidencePath);
        addCaptureStatus(rootState.counts, fileStatus.counts);
        recordStates.set(`${record.type}:${record.platform}:${record.id}:${record.privateReference}`, fileStatus.state);
      } else {
        recordStates.set(`${record.type}:${record.platform}:${record.id}:${record.privateReference}`, rootState.stateForRecord(record));
      }
    }
    return rootStatus;
  });
  const completionBlockers = capturePlan.completionBlockers.map((blocker) => {
    const counts = emptyCaptureStatusCounts();
    for (const root of capturePlan.roots) {
      for (const record of root.records) {
        if (!blocker.evidenceTypes.includes(record.type)) continue;
        const state = recordStates.get(`${record.type}:${record.platform}:${record.id}:${record.privateReference}`);
        if (state === "missing-root") counts.missingRoot += 1;
        else if (state === "invalid-root") counts.invalidRoot += 1;
        else if (state === "missing-file") counts.missingFile += 1;
        else if (state === "invalid-json") counts.invalidJson += 1;
        else if (state === "placeholder") counts.placeholder += 1;
        else if (state === "candidate") counts.candidate += 1;
      }
    }
    const completeCandidates = counts.candidate === blocker.recordCount;
    return {
      ...blocker,
      status: completeCandidates ? "candidate-private-evidence-present" : "external-pending",
      counts,
    };
  });
  const totals = emptyCaptureStatusCounts();
  for (const root of roots) addCaptureStatus(totals, root.counts);
  return {
    schemaVersion: 1,
    status: totals.candidate === capturePlan.totalRecords
      ? "candidate-private-evidence-present-run-approved-verifiers"
      : "external-pending-private-evidence-capture",
    note: "Candidate files are not approval. Final completion still requires the private verifiers with --require-approved.",
    totalRecords: capturePlan.totalRecords,
    totals,
    roots,
    completionBlockers,
  };
}

function capturePackagesFromEvidencePlan() {
  const capturePlan = capturePlanFromEvidencePlan();
  if (errors.length > 0) return null;
  const blockersByEvidenceType = new Map();
  for (const blocker of capturePlan.completionBlockers) {
    for (const evidenceType of blocker.evidenceTypes) {
      const blockers = blockersByEvidenceType.get(evidenceType) || [];
      blockers.push(blocker.decisionId);
      blockersByEvidenceType.set(evidenceType, blockers);
    }
  }
  const packageMap = new Map();
  for (const root of capturePlan.roots) {
    const rootState = privateRootState(root);
    for (const record of root.records) {
      const pkg = packageMap.get(record.type) || {
        evidenceType: record.type,
        recordCount: 0,
        rootAliases: [],
        blockers: [],
        verifierCommands: [],
        counts: emptyCaptureStatusCounts(),
        records: [],
      };
      const state = rootState.status === "configured"
        ? captureStatusForFile(rootState.rootPath, record.relativeEvidencePath).state
        : rootState.stateForRecord(record);
      const privateFile = rootState.rootPath
        ? path.join(rootState.rootPath, record.relativeEvidencePath.split("/").join(path.sep))
        : null;
      pkg.recordCount += 1;
      pkg.rootAliases.push(root.alias);
      pkg.blockers.push(...(blockersByEvidenceType.get(record.type) || []));
      pkg.verifierCommands.push(...root.verifierCommands);
      if (state === "missing-root") pkg.counts.missingRoot += 1;
      else if (state === "invalid-root") pkg.counts.invalidRoot += 1;
      else if (state === "missing-file") pkg.counts.missingFile += 1;
      else if (state === "invalid-json") pkg.counts.invalidJson += 1;
      else if (state === "placeholder") pkg.counts.placeholder += 1;
      else if (state === "candidate") pkg.counts.candidate += 1;
      pkg.records.push({
        id: record.id,
        platform: record.platform,
        privateReference: record.privateReference,
        privateFile,
        relativeEvidencePath: record.relativeEvidencePath,
        state,
        requiredFields: record.requiredFields,
      });
      packageMap.set(record.type, pkg);
    }
  }
  const totals = emptyCaptureStatusCounts();
  const packages = [...packageMap.values()].sort((a, b) => a.evidenceType.localeCompare(b.evidenceType)).map((pkg) => {
    addCaptureStatus(totals, pkg.counts);
    return {
      ...pkg,
      rootAliases: [...new Set(pkg.rootAliases)].sort(),
      blockers: [...new Set(pkg.blockers)].sort(),
      verifierCommands: [...new Set(pkg.verifierCommands)].sort(),
    };
  });
  return {
    schemaVersion: 1,
    status: totals.candidate === capturePlan.totalRecords
      ? "candidate-private-evidence-packages-present-run-approved-verifiers"
      : "external-pending-private-evidence-packages",
    note: "Packages are derived from public manifests and current private root env vars. Candidate files are not approval.",
    totalRecords: capturePlan.totalRecords,
    totals,
    packages,
  };
}

function captureDecisionsFromEvidencePlan() {
  const capturePlan = capturePlanFromEvidencePlan();
  if (errors.length > 0) return null;
  const packagesReport = capturePackagesFromEvidencePlan();
  if (errors.length > 0) return null;
  const packagesByType = new Map(packagesReport.packages.map((pkg) => [pkg.evidenceType, pkg]));
  const decisions = capturePlan.completionBlockers.map((blocker) => {
    const counts = emptyCaptureStatusCounts();
    const packages = blocker.evidenceTypes.map((evidenceType) => {
      const pkg = packagesByType.get(evidenceType);
      if (!pkg) {
        fail(`capture decision ${blocker.decisionId} references missing evidence package ${evidenceType}`);
        return null;
      }
      addCaptureStatus(counts, pkg.counts);
      return {
        evidenceType,
        recordCount: pkg.recordCount,
        rootAliases: pkg.rootAliases,
        counts: pkg.counts,
        verifierCommands: pkg.verifierCommands,
      };
    }).filter(Boolean);
    return {
      decisionId: blocker.decisionId,
      status: counts.candidate === blocker.recordCount
        ? "candidate-private-evidence-present-run-approved-verifiers"
        : "external-pending-private-evidence",
      recordCount: blocker.recordCount,
      counts,
      packages,
      requiredAction: "Replace placeholders or missing private files with captured evidence, add explicit user approval metadata, then run the listed verifiers with --require-approved.",
      externalDependency: "private capture plus human approval",
    };
  });
  return {
    schemaVersion: 1,
    status: decisions.every((decision) => decision.status === "candidate-private-evidence-present-run-approved-verifiers")
      ? "candidate-private-evidence-decisions-present-run-approved-verifiers"
      : "external-pending-private-evidence-decisions",
    note: "Decision status is derived from the private evidence plan and current private root env vars. Candidate files are not approval.",
    totalRecords: capturePlan.totalRecords,
    decisionCount: decisions.length,
    totals: packagesReport.totals,
    decisions,
  };
}

function capturePlanFromEvidencePlan() {
  const aliasEntries = [
    ...requireArray(privateValidation, "docs/ui/private-visual-validation.manifest.json", "rootAliases"),
    ...requireArray(privateValidation, "docs/ui/private-visual-validation.manifest.json", "optionalRootAliases", { nonEmpty: false }),
  ];
  const aliases = new Map(aliasEntries.map((entry) => [entry.alias, entry]));
  const roots = new Map();
  for (const item of plan) {
    const parsed = splitPrivateReference(item.privateReference);
    if (!parsed || !aliases.has(parsed.alias)) {
      fail(`${item.label}.privateReference must use a declared private root alias`);
      continue;
    }
    const aliasEntry = aliases.get(parsed.alias);
    const root = roots.get(parsed.alias) || {
      alias: parsed.alias,
      env: aliasEntry.env,
      required: requireArray(privateValidation, "docs/ui/private-visual-validation.manifest.json", "requiredRoots").includes(aliasEntry.env),
      recordCount: 0,
      evidenceTypes: {},
      verifierCommands: [],
      records: [],
    };
    root.recordCount += 1;
    root.evidenceTypes[item.type] = (root.evidenceTypes[item.type] || 0) + 1;
    root.records.push({
      type: item.type,
      id: item.id,
      platform: item.platform,
      privateReference: item.privateReference,
      relativeEvidencePath: `${parsed.suffix}/${item.evidenceFilename}`,
      requiredFields: item.requiredFields,
      evidenceTemplate: evidenceTemplateForItem(item),
    });
    roots.set(parsed.alias, root);
  }
  const verifierByAlias = new Map([
    ["private-codex-ui-baselines", [
      "node scripts/ui_private_baseline_verify.mjs --require-approved",
      "node scripts/ui_private_performance_budget_verify.mjs --require-approved",
    ]],
    ["private-codex-ui-rendered-geometry", ["node scripts/ui_private_geometry_verify.mjs --require-approved"]],
    ["private-codex-ui-copy-snapshots", ["node scripts/ui_private_copy_verify.mjs --require-approved"]],
    ["private-codex-ui-rendered-drift", ["node scripts/ui_private_drift_verify.mjs --require-approved"]],
    ["private-codex-ui-debt-audit", ["node scripts/ui_private_debt_audit_verify.mjs --require-approved"]],
    ["private-codex-ui-mechanical-equivalence", ["node scripts/ui_private_evidence_verify.mjs --require-approved"]],
  ]);
  for (const [alias, root] of roots) {
    root.verifierCommands = verifierByAlias.get(alias) || ["node scripts/ui_private_evidence_verify.mjs --require-approved"];
  }
  const blockers = requireArray(privateValidation, "docs/ui/private-visual-validation.manifest.json", "decisionBlockerEvidenceTypes")
    .map((entry) => {
      const evidenceTypes = requireArray(entry, `docs/ui/private-visual-validation.manifest.json.${entry?.decisionId || "unknown"}`, "evidenceTypes");
      const recordCount = evidenceTypes.reduce((total, type) => total + (counts.get(type) || 0), 0);
      const rootAliases = [...new Set(plan
        .filter((item) => evidenceTypes.includes(item.type))
        .map((item) => splitPrivateReference(item.privateReference)?.alias)
        .filter(Boolean))];
      return {
        decisionId: entry.decisionId,
        evidenceTypes,
        recordCount,
        rootAliases,
      };
    });
  return {
    schemaVersion: 1,
    status: "external-pending-until-approved-private-evidence-exists",
    totalRecords: plan.length,
    roots: [...roots.values()].sort((a, b) => a.alias.localeCompare(b.alias)),
    completionBlockers: blockers,
  };
}

function addPlanItem(item) {
  requireFields(item, item.label, ["type", "id", "platform", "privateReference", "evidenceFilename", "requiredFields"]);
  assertSafeIdentifier(item.type, `${item.label}.type`);
  assertSafeIdentifier(item.id, `${item.label}.id`);
  assertSafeIdentifier(item.platform, `${item.label}.platform`);
  assertSafeEvidenceFilename(item.evidenceFilename, item.label);
  requireUniqueStringArray(item.requiredFields, `${item.label}.requiredFields`);
  plan.push(item);
}

const surfaceCoverage = readJson("docs/ui/surface-baseline-coverage.manifest.json");
const privateBaselines = readJson("docs/ui/private-baselines.manifest.json");
const renderedGeometry = readJson("docs/ui/rendered-geometry.manifest.json");
const patternRegistry = readJson("docs/ui/pattern-registry/patterns.registry.json");
const copyInventory = readJson("docs/ui/copy.inventory.json");
const renderedDrift = readJson("docs/ui/rendered-drift.manifest.json");
const performanceBudgets = readJson("docs/ui/performance-budgets.registry.json");
const debtAudit = readJson("docs/ui/debt-audit.manifest.json");
const mechanicalEquivalence = readJson("docs/ui/mechanical-equivalence.manifest.json");
const privateValidation = readJson("docs/ui/private-visual-validation.manifest.json");

if (argSet.has("--simulate-unsafe-surface-baseline-reference") && Array.isArray(surfaceCoverage?.coverage) && surfaceCoverage.coverage[0]) {
  surfaceCoverage.coverage[0].privateBaselineReference = "/Users/example/private-baseline";
}

if (argSet.has("--simulate-unsafe-flow-baseline-reference") && Array.isArray(privateBaselines?.flows) && privateBaselines.flows[0]) {
  privateBaselines.flows[0].privateBaselineReference = `${privateBaselines.privateRootAlias}:../escape`;
}

if (argSet.has("--simulate-path-evidence-filename") && surfaceCoverage) {
  surfaceCoverage.surfaceEvidenceFilename = "../surface-evidence.json";
}

if (argSet.has("--simulate-duplicate-surface-required-field") && Array.isArray(surfaceCoverage?.requiredEvidenceFields)) {
  surfaceCoverage.requiredEvidenceFields.push(surfaceCoverage.requiredEvidenceFields[0]);
}

if (argSet.has("--simulate-unsafe-surface-required-field") && Array.isArray(surfaceCoverage?.requiredEvidenceFields)) {
  surfaceCoverage.requiredEvidenceFields.push("../localPath");
}

if (argSet.has("--simulate-empty-pattern-geometry-fields") && renderedGeometry) {
  renderedGeometry.requiredEvidenceFields = [];
}

if (argSet.has("--simulate-duplicate-pattern-geometry-field") && Array.isArray(renderedGeometry?.requiredEvidenceFields)) {
  renderedGeometry.requiredEvidenceFields.push(renderedGeometry.requiredEvidenceFields[0]);
}

if (argSet.has("--simulate-missing-rendered-drift-plan") && renderedDrift) {
  renderedDrift.reports = [];
}

if (argSet.has("--simulate-missing-performance-budget-fields") && performanceBudgets) {
  performanceBudgets.requiredEvidenceFields = [];
}

if (argSet.has("--simulate-flow-duplicate-required-field") && Array.isArray(privateBaselines?.flows) && privateBaselines.flows[0]?.requiredEvidence?.[0]) {
  privateBaselines.flows[0].requiredEvidence.push(privateBaselines.flows[0].requiredEvidence[0]);
}

if (argSet.has("--simulate-missing-surface-coverage-entry") && Array.isArray(surfaceCoverage?.coverage)) {
  surfaceCoverage.coverage = surfaceCoverage.coverage.filter((entry) => entry?.coverageId !== "web-screens");
}

if (argSet.has("--simulate-missing-pattern-registry-entry") && Array.isArray(patternRegistry?.patterns)) {
  patternRegistry.patterns = patternRegistry.patterns.filter((patternId) => patternId !== "toast");
}

if (argSet.has("--simulate-private-validation-wrong-evidence-plan-command") && privateValidation) {
  privateValidation.evidencePlanCommand = "node scripts/ui_private_evidence_plan_check.mjs";
}

if (argSet.has("--simulate-private-validation-missing-blocker") && Array.isArray(privateValidation?.decisionBlockers)) {
  privateValidation.decisionBlockers = privateValidation.decisionBlockers.filter((decisionId) => decisionId !== "copy_governance");
}

if (argSet.has("--simulate-private-validation-extra-blocker") && Array.isArray(privateValidation?.decisionBlockers)) {
  privateValidation.decisionBlockers = [...privateValidation.decisionBlockers, "simulated_blocker"];
}

if (argSet.has("--simulate-private-validation-wrong-evidence-type") && Array.isArray(privateValidation?.decisionBlockerEvidenceTypes)) {
  privateValidation.decisionBlockerEvidenceTypes = privateValidation.decisionBlockerEvidenceTypes.map((entry) => (
    entry?.decisionId === "perf_budget_source" ? { ...entry, evidenceTypes: ["critical-flow-baseline"] } : entry
  ));
}

const expectedEvidenceCounts = new Map([
  ["surface-baseline", 14],
  ["surface-geometry", 14],
  ["surface-copy", 14],
  ["critical-flow-baseline", 24],
  ["pattern-geometry", 59],
  ["rendered-drift", 14],
  ["debt-audit", 3],
  ["performance-budget", 24],
]);
const expectedDecisionEvidence = new Map([
  ["initial_scope", ["surface-baseline", "surface-geometry", "surface-copy"]],
  ["enforcement_mode", ["rendered-drift"]],
  ["debt_strategy", ["debt-audit"]],
  ["visual_baselines_location", ["critical-flow-baseline", "surface-baseline", "rendered-drift"]],
  ["alignment_validation", ["surface-geometry", "pattern-geometry", "surface-baseline"]],
  ["copy_governance", ["surface-copy"]],
  ["v1_pattern_set", ["surface-baseline", "pattern-geometry"]],
  ["perf_budget_source", ["performance-budget"]],
  ["size_contracts", ["pattern-geometry"]],
]);

if (privateValidation?.schemaVersion !== 1) fail("docs/ui/private-visual-validation.manifest.json.schemaVersion must be 1");
if (privateValidation?.status !== "active") fail("docs/ui/private-visual-validation.manifest.json.status must be active");
if (privateValidation?.evidencePlanCommand !== "node scripts/ui_private_evidence_plan_check.mjs --json") {
  fail("docs/ui/private-visual-validation.manifest.json.evidencePlanCommand must be node scripts/ui_private_evidence_plan_check.mjs --json");
}
requireExactStringArray(
  requireArray(privateValidation, "docs/ui/private-visual-validation.manifest.json", "decisionBlockers"),
  "docs/ui/private-visual-validation.manifest.json.decisionBlockers",
  [...expectedDecisionEvidence.keys()],
);
const seenDecisionEvidence = new Set();
for (const [index, entry] of requireArray(privateValidation, "docs/ui/private-visual-validation.manifest.json", "decisionBlockerEvidenceTypes").entries()) {
  const label = `docs/ui/private-visual-validation.manifest.json.decisionBlockerEvidenceTypes[${index}]`;
  requireFields(entry, label, ["decisionId", "evidenceTypes"]);
  if (seenDecisionEvidence.has(entry.decisionId)) fail(`${label}.decisionId duplicates ${entry.decisionId}`);
  seenDecisionEvidence.add(entry.decisionId);
  const expectedEvidenceTypes = expectedDecisionEvidence.get(entry.decisionId);
  if (!expectedEvidenceTypes) {
    fail(`${label}.decisionId is not an open private-evidence blocker`);
    continue;
  }
  requireExactStringArray(entry.evidenceTypes, `${label}.evidenceTypes`, expectedEvidenceTypes);
}
for (const decisionId of expectedDecisionEvidence.keys()) {
  if (!seenDecisionEvidence.has(decisionId)) {
    fail(`docs/ui/private-visual-validation.manifest.json.decisionBlockerEvidenceTypes must include ${decisionId}`);
  }
}

const surfaceRequiredFields = requireArray(surfaceCoverage, "docs/ui/surface-baseline-coverage.manifest.json", "requiredEvidenceFields");
for (const [index, entry] of requireArray(surfaceCoverage, "docs/ui/surface-baseline-coverage.manifest.json", "coverage").entries()) {
  const label = `surface-baseline-coverage[${index}]`;
  requireFields(entry, label, [
    "coverageId",
    "platform",
    "privateBaselineReference",
    "geometryEvidenceReference",
    "copySnapshotReference",
    "requiredEvidence",
  ]);
  assertPublicSafeReference(entry.privateBaselineReference, surfaceCoverage?.privateBaselineAlias, `${label}.privateBaselineReference`);
  assertPublicSafeReference(entry.geometryEvidenceReference, surfaceCoverage?.privateGeometryAlias, `${label}.geometryEvidenceReference`);
  assertPublicSafeReference(entry.copySnapshotReference, surfaceCoverage?.privateCopyAlias, `${label}.copySnapshotReference`);
  addPlanItem({
    label,
    type: "surface-baseline",
    id: entry.coverageId,
    platform: entry.platform,
    privateReference: entry.privateBaselineReference,
    evidenceFilename: surfaceCoverage?.surfaceEvidenceFilename || "surface-evidence.json",
    requiredFields: surfaceRequiredFields,
  });
  addPlanItem({
    label,
    type: "surface-geometry",
    id: entry.coverageId,
    platform: entry.platform,
    privateReference: entry.geometryEvidenceReference,
    evidenceFilename: renderedGeometry?.surfaceEvidenceFilename || "surface-geometry.json",
    requiredFields: renderedGeometry?.requiredSurfaceEvidenceFields || [],
  });
  addPlanItem({
    label,
    type: "surface-copy",
    id: entry.coverageId,
    platform: entry.platform,
    privateReference: entry.copySnapshotReference,
    evidenceFilename: copyInventory?.evidenceFilename || "copy-evidence.json",
    requiredFields: copyInventory?.requiredEvidenceFields || [],
  });
}

for (const [index, flow] of requireArray(privateBaselines, "docs/ui/private-baselines.manifest.json", "flows").entries()) {
  const label = `private-baselines[${index}]`;
  requireFields(flow, label, ["id", "platform", "privateBaselineReference", "requiredEvidence"]);
  assertPublicSafeReference(flow.privateBaselineReference, privateBaselines?.privateRootAlias, `${label}.privateBaselineReference`);
  addPlanItem({
    label,
    type: "critical-flow-baseline",
    id: flow.id,
    platform: flow.platform,
    privateReference: flow.privateBaselineReference,
    evidenceFilename: privateBaselines?.evidenceFilename || "evidence.json",
    requiredFields: flow.requiredEvidence,
  });
}

for (const patternId of requireArray(patternRegistry, "docs/ui/pattern-registry/patterns.registry.json", "patterns")) {
  const patternPath = `docs/ui/pattern-registry/patterns/${patternId}.pattern.json`;
  const pattern = readJson(patternPath);
  for (const platform of requireArray(pattern, patternPath, "platforms")) {
    const privateReference = `${renderedGeometry?.privateGeometryAlias}:${platform}/${patternId}`;
    assertPublicSafeReference(privateReference, renderedGeometry?.privateGeometryAlias, `${patternPath}.${platform}.geometryReference`);
    addPlanItem({
      label: `${patternPath}:${platform}`,
      type: "pattern-geometry",
      id: patternId,
      platform,
      privateReference,
      evidenceFilename: renderedGeometry?.evidenceFilename || "geometry-evidence.json",
      requiredFields: renderedGeometry?.requiredEvidenceFields || [],
    });
  }
}

for (const [index, report] of requireArray(renderedDrift, "docs/ui/rendered-drift.manifest.json", "reports").entries()) {
  const label = `rendered-drift[${index}]`;
  requireFields(report, label, ["coverageId", "platform", "privateDriftReportReference"]);
  assertPublicSafeReference(report.privateDriftReportReference, renderedDrift?.privateDriftAlias, `${label}.privateDriftReportReference`);
  addPlanItem({
    label,
    type: "rendered-drift",
    id: report.coverageId,
    platform: report.platform,
    privateReference: report.privateDriftReportReference,
    evidenceFilename: renderedDrift?.evidenceFilename || "drift-report.json",
    requiredFields: renderedDrift?.requiredEvidenceFields || [],
  });
}

for (const [index, entry] of requireArray(debtAudit, "docs/ui/debt-audit.manifest.json", "entries").entries()) {
  const label = `debt-audit[${index}]`;
  requireFields(entry, label, ["debtId", "platforms", "privateDebtAuditReference", "requiredEvidence"]);
  assertPublicSafeReference(entry.privateDebtAuditReference, debtAudit?.privateDebtAuditAlias, `${label}.privateDebtAuditReference`);
  addPlanItem({
    label,
    type: "debt-audit",
    id: entry.debtId,
    platform: entry.platforms?.[0] || "unknown",
    privateReference: entry.privateDebtAuditReference,
    evidenceFilename: debtAudit?.evidenceFilename || "debt-audit-evidence.json",
    requiredFields: entry.requiredEvidence,
  });
}

for (const [index, flow] of requireArray(performanceBudgets, "docs/ui/performance-budgets.registry.json", "flows").entries()) {
  const label = `performance-budgets[${index}]`;
  requireFields(flow, label, ["id", "platform", "privateBaselineReference"]);
  assertPublicSafeReference(flow.privateBaselineReference, privateBaselines?.privateRootAlias, `${label}.privateBaselineReference`);
  addPlanItem({
    label,
    type: "performance-budget",
    id: flow.id,
    platform: flow.platform,
    privateReference: flow.privateBaselineReference,
    evidenceFilename: performanceBudgets?.evidenceFilename || "performance-evidence.json",
    requiredFields: performanceBudgets?.requiredEvidenceFields || [],
  });
}

for (const [index, record] of requireArray(mechanicalEquivalence, "docs/ui/mechanical-equivalence.manifest.json", "records", { nonEmpty: false }).entries()) {
  const label = `mechanical-equivalence[${index}]`;
  requireFields(record, label, ["id", "status", "platforms", "changedFiles"]);
  const platforms = requireArray(record, label, "platforms");
  for (const platform of platforms) {
    const privateReference = `${mechanicalEquivalence?.privateEvidenceAlias}:records/${record.id}/${platform}`;
    assertPublicSafeReference(privateReference, mechanicalEquivalence?.privateEvidenceAlias, `${label}.${platform}.privateEvidenceReference`);
    addPlanItem({
      label: `${label}:${platform}`,
      type: "mechanical-equivalence",
      id: record.id,
      platform,
      privateReference,
      evidenceFilename: mechanicalEquivalence?.evidenceFilename || "mechanical-equivalence-evidence.json",
      requiredFields: [
        ...(mechanicalEquivalence?.requiredPrivateEvidenceFields || ["recordId", "platform", "status", "privateEvidenceReference"]),
        ...(mechanicalEquivalence?.requiredEvidenceFields || []),
      ],
    });
  }
}

if (argSet.has("--simulate-duplicate-evidence-record") && plan.length > 0) {
  plan.push({ ...plan[0], label: `${plan[0].label}:duplicate-simulation` });
}

const counts = new Map();
const logicalKeys = new Set();
const referenceKeys = new Set();
for (const item of plan) {
  counts.set(item.type, (counts.get(item.type) || 0) + 1);
  const logicalKey = `${item.type}:${item.platform}:${item.id}`;
  if (logicalKeys.has(logicalKey)) {
    fail(`private evidence plan duplicates logical record ${logicalKey}`);
  }
  logicalKeys.add(logicalKey);
  const referenceKey = `${item.type}:${item.privateReference}`;
  if (referenceKeys.has(referenceKey)) {
    fail(`private evidence plan duplicates private reference ${referenceKey}`);
  }
  referenceKeys.add(referenceKey);
}

for (const type of [
  "surface-baseline",
  "surface-geometry",
  "surface-copy",
  "critical-flow-baseline",
  "pattern-geometry",
  "rendered-drift",
  "debt-audit",
  "performance-budget",
]) {
  if (!counts.has(type)) fail(`private evidence plan must include ${type}`);
}
for (const [type, expectedCount] of expectedEvidenceCounts.entries()) {
  const actualCount = counts.get(type) || 0;
  if (actualCount !== expectedCount) {
    fail(`private evidence plan ${type} count must be ${expectedCount}, got ${actualCount}`);
  }
}
for (const type of counts.keys()) {
  if (!expectedEvidenceCounts.has(type) && type !== "mechanical-equivalence") {
    fail(`private evidence plan contains unknown evidence type ${type}`);
  }
}
for (const [decisionId, evidenceTypes] of expectedDecisionEvidence.entries()) {
  for (const evidenceType of evidenceTypes) {
    if ((counts.get(evidenceType) || 0) === 0) {
      fail(`private evidence blocker ${decisionId} requires missing evidence type ${evidenceType}`);
    }
  }
}

if (errors.length === 0 && !isSelfTest && args.length === 0) {
  for (const [flag, expectedOutput] of [
    ["--unknown-flag", "received unknown flag --unknown-flag"],
    ["--simulate-unsafe-surface-baseline-reference", "privateBaselineReference must use private-codex-ui-baselines:"],
    ["--simulate-unsafe-flow-baseline-reference", "privateBaselineReference must use a safe relative private reference"],
    ["--simulate-path-evidence-filename", "evidenceFilename must be a safe filename"],
    ["--simulate-duplicate-surface-required-field", "requiredFields duplicates coverageId"],
    ["--simulate-empty-pattern-geometry-fields", "requiredFields must not be empty"],
    ["--simulate-missing-rendered-drift-plan", "private evidence plan rendered-drift count must be 14"],
    ["--simulate-missing-surface-coverage-entry", "private evidence plan surface-baseline count must be 14"],
    ["--simulate-missing-pattern-registry-entry", "private evidence plan pattern-geometry count must be 59"],
    ["--simulate-private-validation-wrong-evidence-plan-command", "evidencePlanCommand must be node scripts/ui_private_evidence_plan_check.mjs --json"],
    ["--simulate-private-validation-missing-blocker", "decisionBlockers must match"],
    ["--simulate-private-validation-extra-blocker", "decisionBlockers must match"],
    ["--simulate-private-validation-wrong-evidence-type", "evidenceTypes must match"],
    ["--simulate-duplicate-evidence-record", "duplicates logical record"],
  ]) {
    const result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, flag], {
      cwd: rootDir,
      env: { ...process.env, CLAWIX_UI_PRIVATE_EVIDENCE_PLAN_SELF_TEST: "1" },
      encoding: "utf8",
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status === 0) {
      fail(`self-test ${flag} must fail when private evidence plan coverage is removed`);
      continue;
    }
    if (!output.includes(expectedOutput)) {
      fail(`self-test ${flag} output must include ${expectedOutput}`);
    }
  }
}

if (errors.length > 0) {
  console.error("UI private evidence plan check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

const templateRoot = optionValue("--write-template-root");
if (templateRoot) {
  writeTemplateRoot(templateRoot);
  if (errors.length > 0) {
    console.error("UI private evidence plan check failed:");
    for (const error of errors) console.error(`- ${error}`);
    process.exit(1);
  }
} else if (args.includes("--capture-status")) {
  const status = captureStatusFromEvidencePlan();
  if (errors.length > 0) {
    console.error("UI private evidence plan check failed:");
    for (const error of errors) console.error(`- ${error}`);
    process.exit(1);
  }
  console.log(JSON.stringify(status, null, 2));
} else if (args.includes("--capture-packages")) {
  const packages = capturePackagesFromEvidencePlan();
  if (errors.length > 0) {
    console.error("UI private evidence plan check failed:");
    for (const error of errors) console.error(`- ${error}`);
    process.exit(1);
  }
  console.log(JSON.stringify(packages, null, 2));
} else if (args.includes("--capture-decisions")) {
  const decisions = captureDecisionsFromEvidencePlan();
  if (errors.length > 0) {
    console.error("UI private evidence plan check failed:");
    for (const error of errors) console.error(`- ${error}`);
    process.exit(1);
  }
  console.log(JSON.stringify(decisions, null, 2));
} else if (args.includes("--capture-plan")) {
  console.log(JSON.stringify(capturePlanFromEvidencePlan(), null, 2));
} else if (args.includes("--json")) {
  console.log(JSON.stringify({ schemaVersion: 1, counts: Object.fromEntries(counts), evidence: plan }, null, 2));
} else {
  const summary = [...counts.entries()].map(([type, count]) => `${type}:${count}`).join(", ");
  console.log(`UI private evidence plan check passed (${plan.length} evidence records; ${summary})`);
}
