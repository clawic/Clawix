#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const rawArgs = process.argv.slice(2);
const allowedFlags = new Set(["--runner-id", "--json"]);

for (const arg of rawArgs) {
  if (arg.startsWith("--") && !allowedFlags.has(arg)) {
    console.error(`UI private capture plan received unknown flag ${arg}.`);
    process.exit(1);
  }
}

function optionValue(name) {
  const index = rawArgs.indexOf(name);
  if (index === -1) return null;
  const value = rawArgs[index + 1] || null;
  if (!value || value.startsWith("--")) {
    console.error(`UI private capture plan option ${name} requires a value.`);
    process.exit(1);
  }
  return value;
}

function readJson(relativePath) {
  return JSON.parse(fs.readFileSync(path.join(rootDir, relativePath), "utf8"));
}

function privateReferencePath(reference, evidenceFilename) {
  const [, ...suffixParts] = String(reference || "").split(":");
  const suffix = suffixParts.join(":");
  return suffix ? path.posix.join(suffix, evidenceFilename) : evidenceFilename;
}

function splitPrivateReference(reference) {
  if (typeof reference !== "string" || !reference.includes(":")) return null;
  const [alias, ...suffixParts] = reference.split(":");
  const suffix = suffixParts.join(":");
  if (!alias || !suffix) return null;
  return { alias, suffix };
}

function uniqueSorted(values) {
  return [...new Set(values)].sort();
}

function incrementCount(map, key) {
  map.set(key, (map.get(key) || 0) + 1);
}

function loadEvidencePlan() {
  const result = spawnSync(process.execPath, [path.join(rootDir, "scripts/ui_private_evidence_plan_check.mjs"), "--json"], {
    cwd: rootDir,
    encoding: "utf8",
  });
  if (result.status !== 0) {
    console.error(`${result.stdout || ""}${result.stderr || ""}`.trim());
    process.exit(result.status || 1);
  }
  return JSON.parse(result.stdout);
}

const runnerId = optionValue("--runner-id");
if (!runnerId) {
  console.error("UI private capture plan requires --runner-id.");
  process.exit(1);
}

const manifest = readJson("docs/ui/private-capture-runners.manifest.json");
const runner = (manifest.runners || []).find((candidate) => candidate.id === runnerId);
if (!runner) {
  console.error(`UI private capture plan unknown runner-id ${runnerId}.`);
  process.exit(1);
}

const evidencePlan = loadEvidencePlan();
const privateValidation = readJson("docs/ui/private-visual-validation.manifest.json");
const platforms = new Set(runner.platforms || []);
const evidenceTypes = new Set(runner.evidenceTypes || []);
const records = (evidencePlan.evidence || [])
  .filter((record) => platforms.has(record.platform) && evidenceTypes.has(record.type))
  .map((record) => ({
    evidenceType: record.type,
    id: record.id,
    platform: record.platform,
    privateReference: record.privateReference,
    relativeEvidencePath: privateReferencePath(record.privateReference, record.evidenceFilename),
    evidenceFilename: record.evidenceFilename,
    requiredFields: record.requiredFields,
    candidateStatus: manifest.candidateEvidenceStatus,
  }));

const verifierByAlias = new Map([
  ["external-ui-baselines", [
    "node scripts/ui_private_baseline_verify.mjs --require-approved",
    "node scripts/ui_private_performance_budget_verify.mjs --require-approved",
  ]],
  ["external-ui-rendered-geometry", ["node scripts/ui_private_geometry_verify.mjs --require-approved"]],
  ["external-ui-copy-snapshots", ["node scripts/ui_private_copy_verify.mjs --require-approved"]],
  ["external-ui-rendered-drift", ["node scripts/ui_private_drift_verify.mjs --require-approved"]],
  ["external-ui-debt-audit", ["node scripts/ui_private_debt_audit_verify.mjs --require-approved"]],
  ["external-ui-mechanical-equivalence", ["node scripts/ui_private_evidence_verify.mjs --require-approved"]],
]);

const blockersByEvidenceType = new Map();
for (const blocker of privateValidation.decisionBlockerEvidenceTypes || []) {
  for (const evidenceType of blocker.evidenceTypes || []) {
    const blockers = blockersByEvidenceType.get(evidenceType) || [];
    blockers.push(blocker.decisionId);
    blockersByEvidenceType.set(evidenceType, blockers);
  }
}

const packageMap = new Map();
for (const record of records) {
  const parsed = splitPrivateReference(record.privateReference);
  const pkg = packageMap.get(record.evidenceType) || {
    evidenceType: record.evidenceType,
    recordCount: 0,
    rootAliases: [],
    blockers: [],
    verifierCommands: [],
  };
  pkg.recordCount += 1;
  if (parsed?.alias) {
    pkg.rootAliases.push(parsed.alias);
    pkg.verifierCommands.push(...(verifierByAlias.get(parsed.alias) || ["node scripts/ui_private_evidence_verify.mjs --require-approved"]));
  }
  pkg.blockers.push(...(blockersByEvidenceType.get(record.evidenceType) || []));
  packageMap.set(record.evidenceType, pkg);
}

const packages = [...packageMap.values()]
  .sort((a, b) => a.evidenceType.localeCompare(b.evidenceType))
  .map((pkg) => ({
    ...pkg,
    rootAliases: uniqueSorted(pkg.rootAliases),
    blockers: uniqueSorted(pkg.blockers),
    verifierCommands: uniqueSorted(pkg.verifierCommands),
  }));

const decisionImpacts = (privateValidation.decisionBlockerEvidenceTypes || [])
  .map((blocker) => {
    const blockerEvidenceTypes = new Set(blocker.evidenceTypes || []);
    const relevantRecords = records.filter((record) => blockerEvidenceTypes.has(record.evidenceType));
    if (relevantRecords.length === 0) return null;
    const packageCounts = new Map();
    for (const record of relevantRecords) incrementCount(packageCounts, record.evidenceType);
    return {
      decisionId: blocker.decisionId,
      recordCount: relevantRecords.length,
      evidenceTypes: uniqueSorted([...packageCounts.keys()]),
      packages: [...packageCounts.entries()]
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([evidenceType, recordCount]) => ({ evidenceType, recordCount })),
      status: manifest.candidateEvidenceStatus,
      requiredAction: "Capture these private candidate files, add explicit human approval metadata, then run the listed --require-approved verifiers.",
    };
  })
  .filter(Boolean);

const output = {
  schemaVersion: 1,
  status: records.length > 0 ? "candidate-capture-plan-ready" : "candidate-capture-plan-empty",
  runnerId: runner.id,
  platforms: runner.platforms,
  evidenceTypes: runner.evidenceTypes,
  outputAliases: runner.outputAliases,
  requiresHumanApproval: runner.requiresHumanApproval === true,
  candidateEvidenceStatus: manifest.candidateEvidenceStatus,
  approvalRule: manifest.approvalRule,
  recordCount: records.length,
  packages,
  decisionImpacts,
  records,
};

if (rawArgs.includes("--json")) {
  console.log(JSON.stringify(output, null, 2));
} else {
  console.log(`${output.runnerId}: ${output.recordCount} candidate capture records`);
}
