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
  records,
};

if (rawArgs.includes("--json")) {
  console.log(JSON.stringify(output, null, 2));
} else {
  console.log(`${output.runnerId}: ${output.recordCount} candidate capture records`);
}
