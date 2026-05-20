#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const require = createRequire(import.meta.url);
const Ajv2020Module = require("ajv/dist/2020");
const Ajv2020 = Ajv2020Module.default ?? Ajv2020Module;
const args = new Set(process.argv.slice(2));
const errors = [];

function fail(message) {
  errors.push(message);
}

function read(relativePath) {
  return fs.readFileSync(path.join(rootDir, relativePath), "utf8");
}

function readJson(relativePath) {
  return JSON.parse(read(relativePath));
}

function splitList(value) {
  const trimmed = String(value || "").trim();
  if (!trimmed || trimmed === "none") return [];
  return trimmed
    .split(",")
    .map((item) => item.trim().replace(/^`|`$/g, ""))
    .filter(Boolean);
}

function normalizeStatus(status) {
  return String(status || "").trim().toLowerCase().replace(/[_ ]/g, "-");
}

function markdownCells(line) {
  return line
    .trim()
    .replace(/^\|/, "")
    .replace(/\|$/, "")
    .split("|")
    .map((cell) => cell.trim());
}

function extractGoalCompletionImpactRows(relativePath) {
  const text = read(relativePath);
  const start = text.indexOf("## Goal Completion Impact");
  if (start === -1) {
    fail(`${relativePath}: missing ## Goal Completion Impact section`);
    return [];
  }
  const remainder = text.slice(start);
  const nextHeading = remainder.slice(1).search(/\n## /);
  const section = nextHeading === -1 ? remainder : remainder.slice(0, nextHeading + 1);
  const tableLines = section
    .split("\n")
    .filter((line) => line.trim().startsWith("|") && !/^\|\s*-+/.test(line));
  if (tableLines.length < 2) {
    fail(`${relativePath}: goal completion impact table must include a header and rows`);
    return [];
  }
  const headers = markdownCells(tableLines[0]);
  const expectedHeaders = [
    "External pending row",
    "linkedPromiseIds",
    "linkedDecisionIds",
    "completionImpact",
    "closureEffect",
    "reentryCondition",
    "evidenceRequired",
  ];
  if (headers.join("|") !== expectedHeaders.join("|")) {
    fail(`${relativePath}: goal completion impact table headers must be ${expectedHeaders.join(", ")}`);
  }
  return tableLines.slice(1).map((line) => {
    const cells = markdownCells(line);
    return {
      id: cells[0],
      sourcePath: relativePath,
      linkedPromiseIds: splitList(cells[1]),
      linkedDecisionIds: splitList(cells[2]),
      completionImpact: cells[3],
      closureEffect: cells[4],
      reentryCondition: cells[5],
      evidenceRequired: splitList(cells[6]),
    };
  });
}

function findMarkdownRowStatus(relativePath, id) {
  const text = read(relativePath);
  for (const line of text.split("\n")) {
    if (!line.trim().startsWith("|")) continue;
    const cells = markdownCells(line);
    if (cells[0] !== id) continue;
    if (cells.length === 7 && cells[3] && cells[4] && cells[5] && cells[6]) continue;
    return normalizeStatus(cells[cells.length - 2] === "Status" ? cells[cells.length - 1] : cells[cells.length - 1]);
  }
  return "";
}

function buildPromiseStatusLookup(paths) {
  const statuses = new Map();
  for (const relativePath of paths) {
    if (!relativePath) continue;
    const text = read(relativePath);
    for (const line of text.split("\n")) {
      if (!line.trim().startsWith("|")) continue;
      const cells = markdownCells(line);
      if (cells.length < 4 || cells[0] === "ID" || /^-+$/.test(cells[0])) continue;
      const status = cells.find((cell) =>
        ["verified", "verified-complete", "validated-local", "validated-private", "external-pending", "partial-local", "active-closure-gate"].includes(normalizeStatus(cell)),
      );
      if (status) statuses.set(cells[0], normalizeStatus(status));
    }
  }
  return statuses;
}

function semanticErrors(row, promiseStatuses = new Map()) {
  const rowErrors = [];
  if (row.completionImpact === "central_promise_blocker" && row.closureEffect === "allows_local_completion") {
    rowErrors.push("central_promise_blocker cannot allow local completion");
  }
  if (row.completionImpact === "validation_only") {
    if (row.closureEffect !== "allows_local_completion") {
      rowErrors.push("validation_only must allow local completion");
    }
    if ((row.linkedPromiseIds || []).length > 0) {
      rowErrors.push("validation_only links to a central promise");
    }
  }
  if (row.completionImpact === "future_extension" && row.closureEffect === "blocks_goal") {
    rowErrors.push("future_extension must not block the current goal");
  }
  if (row.humanOverrideAccepted && row.completionImpact === "central_promise_blocker" && row.scopeRevisionDecisionType !== "scope_revision") {
    rowErrors.push("human override cannot close central pending without scope_revision");
  }
  for (const promiseId of row.linkedPromiseIds || []) {
    const status = normalizeStatus(row.linkedPromiseStatuses?.[promiseId] || promiseStatuses.get(promiseId));
    if (row.completionImpact === "central_promise_blocker" && ["verified", "verified-complete", "validated-local", "validated-private"].includes(status)) {
      rowErrors.push(`verified-complete still links to central pending: ${promiseId}`);
    }
  }
  return rowErrors;
}

function validateRows(rows, validate, promiseStatuses = new Map()) {
  const rowIds = new Set();
  for (const row of rows) {
    if (rowIds.has(row.id)) fail(`duplicate goal completion gate row ${row.id}`);
    rowIds.add(row.id);
    if (!validate(row)) {
      fail(`${row.sourcePath || row.id}: ${row.id} does not match goal completion gate schema: ${validate.errors.map((error) => error.message).join("; ")}`);
      continue;
    }
    for (const error of semanticErrors(row, promiseStatuses)) {
      fail(`${row.sourcePath || row.id}: ${row.id}: ${error}`);
    }
  }
}

function validationMessages(validate) {
  return (validate.errors || []).map((error) => {
    if (error.keyword === "required" && error.params?.missingProperty) {
      return `missing ${error.params.missingProperty}`;
    }
    return error.message;
  });
}

function assertFixtureBehavior(validate) {
  const fixtures = readJson("docs/governance/goal-completion-gate.fixtures.json");
  if (fixtures.schemaVersion !== 1) fail("goal completion gate fixtures schemaVersion must be 1");
  if (fixtures.schemaPath !== "docs/governance/goal-completion-gate.schema.json") {
    fail("goal completion gate fixtures must point to the reusable schema");
  }
  for (const row of fixtures.validRows || []) {
    if (!validate(row)) fail(`valid fixture ${row.id} must match schema: ${validate.errors.map((error) => error.message).join("; ")}`);
    for (const error of semanticErrors(row)) fail(`valid fixture ${row.id} failed semantic validation: ${error}`);
  }
  for (const fixture of fixtures.invalidRows || []) {
    const schemaOk = validate(fixture.row);
    const output = [...validationMessages(validate), ...semanticErrors(fixture.row)].join("; ");
    if (schemaOk && output.length === 0) {
      fail(`invalid fixture ${fixture.id} must fail validation`);
      continue;
    }
    if (fixture.expectedError && !output.includes(fixture.expectedError)) {
      fail(`invalid fixture ${fixture.id} output must include ${fixture.expectedError}`);
    }
  }
}

function assertV1AcceptanceImpactRows(validate) {
  const acceptance = readJson("docs/governance/v1-surface-closure/acceptance.json");
  const validation = readJson("docs/governance/v1-surface-closure/validation.json");
  const rows = (acceptance.requiredCategories || [])
    .filter((category) => category.status === "external-pending")
    .map((category) => ({
      id: category.id,
      sourcePath: "docs/governance/v1-surface-closure/acceptance.json",
      ...(category.goalCompletionImpact || {}),
    }));
  validateRows(rows, validate);
  const centralRows = rows.filter((row) => row.completionImpact === "central_promise_blocker");
  const declaredBlockers = new Set(validation.completionBlockers || []);
  const blockingCategoryIds = new Set((validation.results || [])
    .filter((result) => result.completionBlocking === true && declaredBlockers.has(result.id))
    .flatMap((result) => result.acceptanceCategoryIds || []));
  for (const row of centralRows) {
    if (!blockingCategoryIds.has(row.id)) {
      fail(`docs/governance/v1-surface-closure/validation.json: central pending ${row.id} must map to a blocking validation result listed in completionBlockers`);
    }
  }
  if (validation.completionStatus === "complete" && centralRows.length > 0) {
    fail("docs/governance/v1-surface-closure/validation.json: completionStatus cannot be complete with central pending rows");
  }
}

function assertMarkdownLedgers(validate) {
  const ledgerSpecs = [
    {
      path: "docs/governance/system-telemetry/external-pending.md",
      statusPaths: ["docs/governance/system-telemetry/completion.md"],
      expectedRows: ["CLX-SYS-TEL-EXT-003", "CLX-SYS-TEL-EXT-004", "CLX-SYS-TEL-EXT-005"],
    },
    {
      path: "docs/governance/sdk-first-custom-surfaces/external-pending.md",
      statusPaths: ["docs/governance/sdk-first-custom-surfaces/completion.md"],
      expectedRows: ["CLX-SDK-EXT-001", "CLX-SDK-EXT-002", "CLX-SDK-EXT-003", "CLX-SDK-EXT-004"],
    },
    {
      path: "docs/governance/legal/external-pending.md",
      statusPaths: ["docs/governance/legal/source-audit.md"],
      expectedRows: ["LEGAL-EXT-001", "LEGAL-EXT-002", "LEGAL-EXT-003", "LEGAL-EXT-004", "LEGAL-EXT-005", "LEGAL-EXT-006", "LEGAL-EXT-007"],
    },
    {
      path: "docs/governance/v1-surface-closure/completion.md",
      statusPaths: ["docs/governance/v1-surface-closure/completion.md"],
      expectedRows: ["external_integrations_policy", "domain_verticals_policy"],
    },
  ];
  for (const spec of ledgerSpecs) {
    const rows = extractGoalCompletionImpactRows(spec.path);
    const promiseStatuses = buildPromiseStatusLookup(spec.statusPaths);
    validateRows(rows, validate, promiseStatuses);
    const ids = new Set(rows.map((row) => row.id));
    for (const expectedId of spec.expectedRows) {
      if (!ids.has(expectedId)) fail(`${spec.path}: missing goal completion impact row ${expectedId}`);
    }
    for (const row of rows) {
      const rowStatus = findMarkdownRowStatus(spec.path, row.id);
      if (rowStatus && rowStatus !== "external-pending") {
        fail(`${spec.path}: ${row.id} must describe an EXTERNAL PENDING row, found ${rowStatus}`);
      }
    }
  }
}

function assertSystemTelemetryManifest(validate) {
  const manifest = readJson("docs/governance/system-telemetry/external-validation.manifest.json");
  const rows = (manifest.rows || [])
    .filter((row) => row.status === "EXTERNAL PENDING")
    .map((row) => ({
      id: row.id,
      sourcePath: "docs/governance/system-telemetry/external-validation.manifest.json",
      linkedPromiseIds: row.linkedPromiseIds,
      linkedDecisionIds: row.linkedDecisionIds,
      completionImpact: row.completionImpact,
      closureEffect: row.closureEffect,
      reentryCondition: row.reentryCondition,
      evidenceRequired: row.evidenceRequired,
    }));
  validateRows(rows, validate, buildPromiseStatusLookup(["docs/governance/system-telemetry/completion.md"]));
}

function main() {
  for (const arg of args) {
    if (arg !== "--self-test") {
      console.error(`goal completion gate check received unknown flag ${arg}`);
      process.exit(1);
    }
  }
  const schema = readJson("docs/governance/goal-completion-gate.schema.json");
  const ajv = new Ajv2020({ allErrors: true, strict: false, validateFormats: false });
  const validate = ajv.compile(schema);

  assertFixtureBehavior(validate);
  if (!args.has("--self-test")) {
    assertMarkdownLedgers(validate);
    assertSystemTelemetryManifest(validate);
    assertV1AcceptanceImpactRows(validate);
  }

  if (errors.length > 0) {
    console.error("Goal completion gate check failed:");
    for (const error of errors) console.error(`- ${error}`);
    process.exit(1);
  }
  console.log("Goal completion gate check passed");
}

main();
