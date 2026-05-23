#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const matrixPath = path.join(rootDir, "qa/scenarios/attachment-lifecycle-matrix.json");
const docPath = path.join(rootDir, "qa/scenarios/attachment-lifecycle.md");
const requiredCases = ["happy_path", "error_path", "cancellation", "cleanup", "size_limit"];
const validSupport = new Set(["supported", "unsupported"]);
const validStatus = new Set(["validated", "partial", "external_pending", "blocked"]);
const errors = [];

function fail(message) {
  errors.push(message);
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function assertNonEmptyString(value, label) {
  if (typeof value !== "string" || value.trim() === "") {
    fail(`${label} must be a non-empty string`);
  }
}

function assertEvidence(caseValue, label) {
  if (!Array.isArray(caseValue.evidence) || caseValue.evidence.length === 0) {
    fail(`${label} must list evidence`);
    return;
  }
  for (const [index, evidence] of caseValue.evidence.entries()) {
    assertNonEmptyString(evidence, `${label}.evidence[${index}]`);
  }
}

const matrix = readJson(matrixPath);
if (matrix.schemaVersion !== 1) {
  fail("schemaVersion must be 1");
}
if (JSON.stringify(matrix.requiredCases) !== JSON.stringify(requiredCases)) {
  fail(`requiredCases must be ${requiredCases.join(", ")}`);
}
if (!Array.isArray(matrix.attachmentTypes) || matrix.attachmentTypes.length === 0) {
  fail("attachmentTypes must be a non-empty array");
}

const seen = new Set();
for (const type of matrix.attachmentTypes ?? []) {
  assertNonEmptyString(type.id, "attachmentTypes[].id");
  if (seen.has(type.id)) {
    fail(`${type.id}: duplicate attachment type id`);
  }
  seen.add(type.id);
  if (!validSupport.has(type.support)) {
    fail(`${type.id}: support must be supported or unsupported`);
  }
  if (!validStatus.has(type.validationState)) {
    fail(`${type.id}: validationState must be one of ${Array.from(validStatus).join(", ")}`);
  } else if (type.validationState !== "validated") {
    fail(`${type.id}: validationState must be validated for attachment lifecycle closure`);
  }
  assertNonEmptyString(type.surface, `${type.id}.surface`);
  assertNonEmptyString(type.description, `${type.id}.description`);
  if (!type.cases || typeof type.cases !== "object") {
    fail(`${type.id}: cases must be an object`);
    continue;
  }
  for (const caseId of requiredCases) {
    const caseValue = type.cases[caseId];
    if (!caseValue) {
      fail(`${type.id}: missing required case ${caseId}`);
      continue;
    }
    if (!validStatus.has(caseValue.status)) {
      fail(`${type.id}.${caseId}: status must be one of ${Array.from(validStatus).join(", ")}`);
    } else if (caseValue.status !== "validated") {
      fail(`${type.id}.${caseId}: status must be validated for attachment lifecycle closure`);
    }
    assertEvidence(caseValue, `${type.id}.${caseId}`);
    assertNonEmptyString(caseValue.fixture, `${type.id}.${caseId}.fixture`);
  }
}

for (const section of ["privacy", "simulatedChatSend"]) {
  const value = matrix[section];
  if (!value || typeof value !== "object") {
    fail(`${section} section is required`);
    continue;
  }
  if (!validStatus.has(value.status)) {
    fail(`${section}.status must be one of ${Array.from(validStatus).join(", ")}`);
  }
  assertEvidence(value, section);
}

const realAppValidation = matrix.realAppValidation;
if (!realAppValidation || typeof realAppValidation !== "object") {
  fail("realAppValidation section is required");
} else {
  if (!validStatus.has(realAppValidation.status)) {
    fail(`realAppValidation.status must be one of ${Array.from(validStatus).join(", ")}`);
  }
  assertEvidence(realAppValidation, "realAppValidation");
  if (!Array.isArray(realAppValidation.remaining)) {
    fail("realAppValidation.remaining must be an array");
  } else {
    for (const [index, remaining] of realAppValidation.remaining.entries()) {
      assertNonEmptyString(remaining, `realAppValidation.remaining[${index}]`);
    }
  }
}

const doc = fs.readFileSync(docPath, "utf8");
for (const typeId of seen) {
  if (!doc.includes(`\`${typeId}\``)) {
    fail(`attachment-lifecycle.md must show matrix row for ${typeId}`);
  }
}

if (errors.length > 0) {
  console.error(errors.map((error) => `- ${error}`).join("\n"));
  process.exit(1);
}

console.log(`attachment lifecycle matrix ok (${seen.size} attachment types)`);
