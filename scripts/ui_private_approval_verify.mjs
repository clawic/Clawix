#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import crypto from "node:crypto";
import { privateRootEnvForAlias } from "./ui_private_root_contract.mjs";
import { enforcePrivateVerifierArgs } from "./ui_private_verifier_args.mjs";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = process.argv.slice(2);
const isSelfTest = process.env.CLAWIX_UI_APPROVAL_VERIFY_SELF_TEST === "1";
const errors = [];

function fail(message) {
  errors.push(message);
}

function hasFlag(name) {
  return args.includes(name);
}

const optionsWithValues = ["--write-approval-template-root"];

enforcePrivateVerifierArgs(args, {
  label: "UI private approval verification",
  allowedFlags: ["--require-approved", "--approval-plan", "--approval-status", "--force-approval-template-root", ...optionsWithValues],
  optionsWithValues,
});

function optionValue(name) {
  const index = args.indexOf(name);
  return index === -1 ? null : args[index + 1];
}

function readJsonFile(file, label) {
  if (!fs.existsSync(file)) {
    fail(`missing ${label}`);
    return null;
  }
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (error) {
    fail(`${label} is not valid JSON: ${error.message}`);
    return null;
  }
}

function readRepoJson(relativePath) {
  return readJsonFile(path.join(rootDir, relativePath), relativePath);
}

function requireField(object, label, field) {
  if (object?.[field] === undefined || object[field] === null || object[field] === "") {
    fail(`${label} is missing ${field}`);
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

function splitReference(reference) {
  if (typeof reference !== "string" || !reference.includes(":")) return null;
  const [alias, ...suffixParts] = reference.split(":");
  const suffix = suffixParts.join(":");
  if (!alias || !suffix || suffix.startsWith("/") || suffix.startsWith("\\") || suffix.startsWith("~/") || suffix.includes("..") || /^[A-Z]:\\/.test(suffix)) return null;
  if (reference.includes("/Users/") || reference.startsWith("file://")) return null;
  return { alias, suffix };
}

function assertIsoDate(value, label) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}(?:T.+)?$/.test(value) || Number.isNaN(Date.parse(value))) {
    fail(`${label} must be an ISO date or timestamp`);
  }
}

function assertHash(value, label) {
  if (typeof value !== "string" || !/^[a-f0-9]{64}$/i.test(value)) {
    fail(`${label} must be a 64-character hex hash`);
  }
}

function stableValue(value) {
  if (Array.isArray(value)) return value.map((entry) => stableValue(entry));
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map((key) => [key, stableValue(value[key])]),
    );
  }
  return value;
}

function publicRecordHash(record) {
  return crypto.createHash("sha256").update(JSON.stringify(stableValue(record))).digest("hex");
}

function approvalRecords(manifest) {
  const records = [];
  for (const [sourceIndex, source] of requireArray(manifest, "docs/ui/approval-authority.manifest.json", "approvalSources").entries()) {
    const sourceLabel = `docs/ui/approval-authority.manifest.json.approvalSources[${sourceIndex}]`;
    for (const field of ["id", "path", "arrayField", "privateApprovalField"]) requireField(source, sourceLabel, field);
    if (!source?.path || !source?.arrayField || !source?.privateApprovalField) continue;
    const registry = readRepoJson(source.path);
    const approvalRequiredStatuses = Array.isArray(source.approvalRequiredStatuses)
      ? new Set(source.approvalRequiredStatuses)
      : null;
    for (const [recordIndex, record] of requireArray(registry, source.path, source.arrayField, { nonEmpty: false }).entries()) {
      if (approvalRequiredStatuses && !approvalRequiredStatuses.has(record?.[source.statusField])) continue;
      records.push({
        source,
        record,
        label: `${source.path}.${source.arrayField}[${recordIndex}]`,
      });
    }
  }
  return records;
}

function runFailureSelfTests(privateRootEnv) {
  const selfTestEnv = {
    ...process.env,
    CLAWIX_UI_APPROVAL_VERIFY_SELF_TEST: "1",
  };
  delete selfTestEnv[privateRootEnv];
  const missingRoot = path.join(os.tmpdir(), `clawix-ui-private-approval-missing-${process.pid}`);
  const tests = [
    [[], {}, "requires --require-approved"],
    [["--require-approved", "--unknown-flag"], {}, "received unknown flag --unknown-flag"],
    [["--require-approved"], { [privateRootEnv]: rootDir }, `${privateRootEnv} must point outside the public repository`],
    [["--require-approved"], { [privateRootEnv]: missingRoot }, `${privateRootEnv} does not point to an existing directory`],
  ];

  for (const [testArgs, extraEnv, expectedOutput] of tests) {
    const result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, ...testArgs], {
      cwd: rootDir,
      env: { ...selfTestEnv, ...extraEnv },
      encoding: "utf8",
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status === 0) {
      fail(`self-test ${testArgs.join(" ") || "<no args>"} must fail for private approval verification`);
      continue;
    }
    if (!output.includes(expectedOutput)) {
      fail(`self-test ${testArgs.join(" ") || "<no args>"} output must include ${expectedOutput}`);
    }
  }

  const templateRoot = fs.mkdtempSync(path.join(os.tmpdir(), `clawix-ui-private-approval-template-${process.pid}-`));
  const templateWrite = spawnSync(process.execPath, [
    new URL(import.meta.url).pathname,
    "--write-approval-template-root",
    templateRoot,
  ], {
    cwd: rootDir,
    env: selfTestEnv,
    encoding: "utf8",
  });
  const templateWriteOutput = `${templateWrite.stdout || ""}${templateWrite.stderr || ""}`;
  if (templateWrite.status !== 0) {
    fail("self-test --write-approval-template-root must scaffold outside the public repository");
  } else if (!templateWriteOutput.includes("UI private approval template root written")) {
    fail("self-test --write-approval-template-root output must confirm template root write");
  }

  const templateStatus = spawnSync(process.execPath, [
    new URL(import.meta.url).pathname,
    "--approval-status",
  ], {
    cwd: rootDir,
    env: {
      ...selfTestEnv,
      [privateRootEnv]: path.join(templateRoot, "private-codex-ui-approval"),
    },
    encoding: "utf8",
  });
  if (templateStatus.status !== 0) {
    fail("self-test --approval-status must read generated approval templates");
  } else {
    try {
      const status = JSON.parse(templateStatus.stdout);
      if (status.counts?.placeholder !== approvals.length || status.counts?.candidate !== 0) {
        fail("self-test generated approval templates must remain placeholders, not candidates");
      }
    } catch (error) {
      fail(`self-test --approval-status output must be JSON: ${error.message}`);
    }
  }

  const overwrite = spawnSync(process.execPath, [
    new URL(import.meta.url).pathname,
    "--write-approval-template-root",
    templateRoot,
  ], {
    cwd: rootDir,
    env: selfTestEnv,
    encoding: "utf8",
  });
  const overwriteOutput = `${overwrite.stdout || ""}${overwrite.stderr || ""}`;
  if (overwrite.status === 0) {
    fail("self-test --write-approval-template-root must not overwrite existing approval templates without force");
  } else if (!overwriteOutput.includes("already exists")) {
    fail("self-test --write-approval-template-root overwrite output must include already exists");
  }

  const forceOverwrite = spawnSync(process.execPath, [
    new URL(import.meta.url).pathname,
    "--write-approval-template-root",
    templateRoot,
    "--force-approval-template-root",
  ], {
    cwd: rootDir,
    env: selfTestEnv,
    encoding: "utf8",
  });
  if (forceOverwrite.status !== 0) {
    fail("self-test --force-approval-template-root must allow regenerating approval templates");
  }
}

const approvalPlanMode = hasFlag("--approval-plan");
const approvalStatusMode = hasFlag("--approval-status");
const writeTemplateRoot = optionValue("--write-approval-template-root");
if (!hasFlag("--require-approved") && !approvalPlanMode && !approvalStatusMode && !writeTemplateRoot) {
  console.error("UI private approval verification requires --require-approved.");
  process.exit(1);
}

const manifest = readRepoJson("docs/ui/approval-authority.manifest.json");
const alias = manifest?.privateApprovalAlias;
const evidenceFilename = manifest?.evidenceFilename || "approval-evidence.json";
const requiredEvidenceFields = manifest?.requiredPrivateApprovalEvidenceFields || [];
const approvalEntries = approvalRecords(manifest);
const approvals = [];

for (const { source, record, label } of approvalEntries) {
  const reference = record?.[source.privateApprovalField];
  if (!reference) {
    fail(`${label}.${source.privateApprovalField} is required for private approval verification`);
    continue;
  }
  approvals.push({ source, record, label });
}

if (errors.length > 0) {
  console.error("UI private approval verification failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

let privateRootEnv;
try {
  privateRootEnv = privateRootEnvForAlias(rootDir, alias);
} catch (error) {
  fail(error.message);
}

if (errors.length > 0) {
  console.error("UI private approval verification failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

function approvalPlanRecords() {
  return approvals.map(({ source, record, label }) => {
    const reference = record[source.privateApprovalField];
    const parsed = splitReference(reference);
    return {
      sourceId: source.id,
      sourcePath: source.path,
      label,
      privateApprovalReference: reference,
      relativeEvidencePath: parsed?.alias === alias ? `${parsed.suffix}/${evidenceFilename}` : null,
      requiredFields: requiredEvidenceFields,
      publicRecordHash: publicRecordHash(record),
    };
  });
}

function approvalPlan() {
  return {
    schemaVersion: 1,
    status: approvals.length === 0 ? "no-private-approval-records" : "external-pending-until-approved-private-approval-evidence-exists",
    privateApprovalAlias: alias,
    env: privateRootEnv,
    evidenceFilename,
    requiredFields: requiredEvidenceFields,
    totalRecords: approvals.length,
    records: approvalPlanRecords(),
  };
}

function approvalStateForFile(privateRoot, relativeEvidencePath) {
  if (!relativeEvidencePath) return "invalid-reference";
  const evidencePath = path.join(privateRoot, relativeEvidencePath.split("/").join(path.sep));
  if (!fs.existsSync(evidencePath)) return "missing-file";
  let evidence = null;
  try {
    evidence = JSON.parse(fs.readFileSync(evidencePath, "utf8"));
  } catch {
    return "invalid-json";
  }
  if (evidence?._templateStatus === "placeholder-not-valid-evidence") return "placeholder";
  return "candidate";
}

function approvalStatus() {
  const plan = approvalPlan();
  const counts = {
    missingRoot: 0,
    invalidRoot: 0,
    invalidReference: 0,
    missingFile: 0,
    invalidJson: 0,
    placeholder: 0,
    candidate: 0,
  };
  const rootPathRaw = privateRootEnv ? process.env[privateRootEnv] : "";
  if (!rootPathRaw) {
    counts.missingRoot = plan.totalRecords;
    return {
      ...plan,
      status: plan.totalRecords === 0 ? "no-private-approval-records" : "external-pending-missing-approval-root",
      note: "Candidate approval evidence is not completion. Final closure requires --require-approved.",
      counts,
      records: plan.records.map((record) => ({ ...record, state: "missing-root", privateFile: null })),
    };
  }
  const privateRoot = path.resolve(rootPathRaw);
  const relativeToRepo = path.relative(rootDir, privateRoot);
  if (!relativeToRepo.startsWith("..") && !path.isAbsolute(relativeToRepo)) {
    counts.invalidRoot = plan.totalRecords;
    return {
      ...plan,
      status: "invalid-approval-root-inside-public-repo",
      note: "Candidate approval evidence is not completion. Final closure requires --require-approved.",
      counts,
      records: plan.records.map((record) => ({ ...record, state: "invalid-root", privateFile: privateRoot })),
    };
  }
  if (!fs.existsSync(privateRoot) || !fs.statSync(privateRoot).isDirectory()) {
    counts.missingRoot = plan.totalRecords;
    return {
      ...plan,
      status: "external-pending-approval-root-not-found",
      note: "Candidate approval evidence is not completion. Final closure requires --require-approved.",
      counts,
      records: plan.records.map((record) => ({ ...record, state: "missing-root", privateFile: privateRoot })),
    };
  }
  const records = plan.records.map((record) => {
    const state = approvalStateForFile(privateRoot, record.relativeEvidencePath);
    if (state === "invalid-reference") counts.invalidReference += 1;
    else if (state === "missing-file") counts.missingFile += 1;
    else if (state === "invalid-json") counts.invalidJson += 1;
    else if (state === "placeholder") counts.placeholder += 1;
    else if (state === "candidate") counts.candidate += 1;
    return {
      ...record,
      state,
      privateFile: record.relativeEvidencePath ? path.join(privateRoot, record.relativeEvidencePath.split("/").join(path.sep)) : null,
    };
  });
  return {
    ...plan,
    status: plan.totalRecords === 0
      ? "no-private-approval-records"
      : counts.candidate === plan.totalRecords
      ? "candidate-private-approval-evidence-present-run-approved-verifier"
      : "external-pending-private-approval-evidence",
    note: "Candidate approval evidence is not completion. Final closure requires --require-approved.",
    counts,
    records,
  };
}

function assertOutsidePublicRepo(outputRootRaw) {
  const outputRoot = path.resolve(outputRootRaw);
  const relativeToRepo = path.relative(rootDir, outputRoot);
  if (!relativeToRepo.startsWith("..") && !path.isAbsolute(relativeToRepo)) {
    fail("--write-approval-template-root must point outside the public repository");
    return null;
  }
  return outputRoot;
}

function approvalTemplateForRecord(record) {
  const template = {
    _templateStatus: "placeholder-not-valid-evidence",
    _templateNote: "Fill from private user approval evidence. Do not treat null placeholders as approval.",
  };
  for (const field of requiredEvidenceFields) {
    if (field === "sourceId") template[field] = record.sourceId;
    else if (field === "privateApprovalReference") template[field] = record.privateApprovalReference;
    else if (field === "publicRecordHash") template[field] = record.publicRecordHash;
    else template[field] = null;
  }
  return template;
}

function writeJsonTemplate(file, value, { force }) {
  if (fs.existsSync(file) && !force) {
    fail(`${file} already exists; pass --force-approval-template-root to overwrite generated approval templates`);
    return;
  }
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);
}

function writeApprovalTemplateRoot(outputRootRaw) {
  const outputRoot = assertOutsidePublicRepo(outputRootRaw);
  if (!outputRoot) return;
  const plan = approvalPlan();
  const force = hasFlag("--force-approval-template-root");
  fs.mkdirSync(outputRoot, { recursive: true });
  writeJsonTemplate(path.join(outputRoot, "approval-template-index.json"), {
    schemaVersion: 1,
    status: "placeholder-not-valid-evidence",
    note: "Templates are field-shape checklists only. Replace null values with approved private user approval evidence before verification.",
    privateApprovalAlias: plan.privateApprovalAlias,
    env: plan.env,
    evidenceFilename: plan.evidenceFilename,
    totalRecords: plan.totalRecords,
    records: plan.records.map((record) => ({
      sourceId: record.sourceId,
      sourcePath: record.sourcePath,
      privateApprovalReference: record.privateApprovalReference,
      relativeEvidencePath: record.relativeEvidencePath,
      requiredFields: record.requiredFields,
      publicRecordHash: record.publicRecordHash,
    })),
  }, { force });
  for (const record of plan.records) {
    if (!record.relativeEvidencePath) {
      fail(`${record.label}.privateApprovalReference must use ${alias}:`);
      continue;
    }
    writeJsonTemplate(path.join(outputRoot, alias, record.relativeEvidencePath), {
      _rootAlias: alias,
      _rootEnv: privateRootEnv,
      _relativeEvidencePath: record.relativeEvidencePath,
      ...approvalTemplateForRecord(record),
    }, { force });
  }
  if (errors.length === 0) {
    console.log(`UI private approval template root written (${plan.totalRecords} placeholder files): ${outputRoot}`);
  }
}

if (writeTemplateRoot) {
  writeApprovalTemplateRoot(writeTemplateRoot);
  if (errors.length > 0) {
    console.error("UI private approval verification failed:");
    for (const error of errors) console.error(`- ${error}`);
    process.exit(1);
  }
  process.exit(0);
}

if (approvalPlanMode) {
  console.log(JSON.stringify(approvalPlan(), null, 2));
  process.exit(0);
}

if (approvalStatusMode) {
  console.log(JSON.stringify(approvalStatus(), null, 2));
  process.exit(0);
}

if (approvals.length === 0) {
  console.log("UI private approval verification passed (0 approval records)");
  process.exit(0);
}

if (!isSelfTest && privateRootEnv) {
  runFailureSelfTests(privateRootEnv);
}
if (!privateRootEnv || !process.env[privateRootEnv]) {
  console.error(`EXTERNAL PENDING: set ${privateRootEnv} to verify private approval evidence.`);
  process.exit(2);
}

const privateRoot = path.resolve(process.env[privateRootEnv]);
const relativeToRepo = path.relative(rootDir, privateRoot);
if (!relativeToRepo.startsWith("..") && !path.isAbsolute(relativeToRepo)) {
  fail(`${privateRootEnv} must point outside the public repository`);
}
if (!fs.existsSync(privateRoot) || !fs.statSync(privateRoot).isDirectory()) {
  fail(`${privateRootEnv} does not point to an existing directory`);
}

let verified = 0;
for (const { source, record, label } of approvals) {
  const reference = record[source.privateApprovalField];
  const parsed = splitReference(reference);
  if (!parsed || parsed.alias !== alias) {
    fail(`${label}.${source.privateApprovalField} must use ${alias}:`);
    continue;
  }

  const evidencePath = path.join(privateRoot, parsed.suffix.split("/").join(path.sep), evidenceFilename);
  const evidence = readJsonFile(evidencePath, `${label} ${evidenceFilename}`);
  if (!evidence) continue;
  for (const field of requiredEvidenceFields) requireField(evidence, `${label} evidence`, field);
  if (evidence.sourceId !== source.id) fail(`${label}.sourceId must match ${source.id}`);
  if (evidence.privateApprovalReference !== reference) {
    fail(`${label}.privateApprovalReference must match public approval reference`);
  }
  if (evidence.approvedBy !== "user") fail(`${label}.approvedBy must be user`);
  if (record.approvedBy !== undefined && evidence.approvedBy !== record.approvedBy) {
    fail(`${label}.approvedBy must match public approval record`);
  }
  assertIsoDate(evidence.approvedAt, `${label}.approvedAt`);
  if (record.approvedAt !== undefined && evidence.approvedAt !== record.approvedAt) {
    fail(`${label}.approvedAt must match public approval record`);
  }
  assertHash(evidence.approvalHash, `${label}.approvalHash`);
  assertHash(evidence.publicRecordHash, `${label}.publicRecordHash`);
  if (evidence.publicRecordHash !== publicRecordHash(record)) {
    fail(`${label}.publicRecordHash must match the public approval record`);
  }
  verified += 1;
}

if (errors.length > 0) {
  console.error("UI private approval verification failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI private approval verification passed (${verified} approval records)`);
