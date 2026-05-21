#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const releaseTargets = new Set(["macos-release", "ios-release", "linux-release", "windows-release"]);
const acceptedExternalStatuses = new Set([
  "pass",
  "passed",
  "validated",
  "validated-local",
  "validated-private",
  "verified",
  "verified-complete",
]);

function read(relativePath, baseDir = rootDir) {
  return fs.readFileSync(path.join(baseDir, relativePath), "utf8");
}

function readJson(relativePath, baseDir = rootDir) {
  return JSON.parse(read(relativePath, baseDir));
}

function exists(relativePath, baseDir = rootDir) {
  return fs.existsSync(path.join(baseDir, relativePath));
}

function normalizeStatus(status) {
  return String(status || "").trim().toLowerCase().replace(/[_ ]/g, "-");
}

function splitList(value) {
  const trimmed = String(value || "").trim();
  if (!trimmed || trimmed === "none") return [];
  return trimmed
    .split(",")
    .map((item) => item.trim().replace(/^`|`$/g, ""))
    .filter(Boolean);
}

function markdownCells(line) {
  return line
    .trim()
    .replace(/^\|/, "")
    .replace(/\|$/, "")
    .split("|")
    .map((cell) => cell.trim());
}

function sectionBetween(text, heading) {
  const start = text.indexOf(heading);
  if (start === -1) return "";
  const remainder = text.slice(start);
  const nextHeading = remainder.slice(1).search(/\n## /);
  return nextHeading === -1 ? remainder : remainder.slice(0, nextHeading + 1);
}

function extractGoalCompletionImpactRows(text, sourcePath, failures) {
  const section = sectionBetween(text, "## Goal Completion Impact");
  if (!section) {
    failures.push(`${sourcePath}: missing ## Goal Completion Impact section`);
    return [];
  }
  const tableLines = section
    .split("\n")
    .filter((line) => line.trim().startsWith("|") && !/^\|\s*-+/.test(line));
  if (tableLines.length < 2) {
    failures.push(`${sourcePath}: goal completion impact table must include a header and rows`);
    return [];
  }
  const expectedHeaders = [
    "External pending row",
    "linkedPromiseIds",
    "linkedDecisionIds",
    "completionImpact",
    "closureEffect",
    "reentryCondition",
    "evidenceRequired",
  ];
  const headers = markdownCells(tableLines[0]);
  if (headers.join("|") !== expectedHeaders.join("|")) {
    failures.push(`${sourcePath}: goal completion impact table headers must be ${expectedHeaders.join(", ")}`);
  }
  return tableLines.slice(1).map((line) => {
    const cells = markdownCells(line);
    return {
      id: cells[0],
      sourcePath,
      linkedPromiseIds: splitList(cells[1]),
      linkedDecisionIds: splitList(cells[2]),
      completionImpact: cells[3],
      closureEffect: cells[4],
      reentryCondition: cells[5],
      evidenceRequired: splitList(cells[6]),
    };
  });
}

function findCurrentStatus(text, rowId) {
  for (const line of text.split("\n")) {
    if (!line.trim().startsWith("|")) continue;
    const cells = markdownCells(line);
    if (cells[0] !== rowId) continue;
    if (cells.length >= 7 && cells[3] && cells[4] && cells[5] && cells[6]) continue;
    return cells[cells.length - 1] || "";
  }
  return "";
}

function hasScopeRevision(row, ledgerText) {
  if (row.closureEffect !== "requires_scope_revision") return false;
  const escapedId = row.id.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const explicitRevision = new RegExp(`${escapedId}[^\\n]*scope_revision|scope_revision[^\\n]*${escapedId}`);
  return ledgerText
    .split("\n")
    .some((line) => !line.trim().startsWith("|") && explicitRevision.test(line));
}

function loadExternalRows(manifest, baseDir, failures) {
  const rows = new Map();
  for (const sourcePath of manifest.sources?.externalPendingLedgers ?? []) {
    if (!exists(sourcePath, baseDir)) {
      failures.push(`missing external pending ledger: ${sourcePath}`);
      continue;
    }
    const text = read(sourcePath, baseDir);
    for (const row of extractGoalCompletionImpactRows(text, sourcePath, failures)) {
      const currentStatus = findCurrentStatus(text, row.id);
      rows.set(row.id, { ...row, currentStatus, ledgerText: text });
    }
  }
  return rows;
}

function normalizeBlockingRow(row, promise, failures) {
  if (typeof row === "string") {
    return { id: row, targets: promise.releaseTargets ?? [] };
  }
  if (!row || typeof row !== "object") {
    failures.push(`${promise.id}: blockingExternalRows entries must be strings or objects`);
    return { id: "", targets: [] };
  }
  return {
    id: row.id || "",
    targets: Array.isArray(row.targets) ? row.targets : [],
  };
}

function validateManifest(manifest, assertionEnvelope, externalRows, failures, options = {}) {
  if (manifest.schemaVersion !== 1) failures.push("schemaVersion must be 1");
  if (manifest.scope !== "v1-central-promises") failures.push("scope must be v1-central-promises");
  if (!manifest.sources || typeof manifest.sources !== "object") failures.push("sources must be an object");
  if (manifest.sources?.constitutionAssertions !== "docs/constitution.assertions.json") {
    failures.push("sources.constitutionAssertions must be docs/constitution.assertions.json");
  }
  if (manifest.sources?.humanMatrix !== "docs/governance/release-readiness.md") {
    failures.push("sources.humanMatrix must be docs/governance/release-readiness.md");
  }
  if (!Array.isArray(manifest.sources?.externalPendingLedgers)) {
    failures.push("sources.externalPendingLedgers must be an array");
  }
  if (!Array.isArray(manifest.releaseTargets)) failures.push("releaseTargets must be an array");
  for (const target of manifest.releaseTargets ?? []) {
    if (!releaseTargets.has(target)) failures.push(`unsupported release target: ${target}`);
  }
  if (manifest.statusRules?.requiredAssertionStatus !== "enforced") {
    failures.push("statusRules.requiredAssertionStatus must be enforced");
  }
  if (manifest.statusRules?.blockingCompletionImpact !== "central_promise_blocker") {
    failures.push("statusRules.blockingCompletionImpact must be central_promise_blocker");
  }
  if (!Array.isArray(manifest.promises) || manifest.promises.length === 0) {
    failures.push("promises must be a non-empty array");
  }

  const assertionById = new Map((assertionEnvelope.assertions ?? []).map((assertion) => [assertion.id, assertion]));
  const seenPromiseIds = new Set();
  for (const promise of manifest.promises ?? []) {
    if (!promise.id || typeof promise.id !== "string") failures.push("each promise needs an id");
    if (seenPromiseIds.has(promise.id)) failures.push(`duplicate promise id: ${promise.id}`);
    seenPromiseIds.add(promise.id);
    if (!promise.title || typeof promise.title !== "string") failures.push(`${promise.id}: title is required`);
    if (!Array.isArray(promise.constitutionalAssertionIds) || promise.constitutionalAssertionIds.length === 0) {
      failures.push(`${promise.id}: constitutionalAssertionIds must be non-empty`);
    }
    if (!Array.isArray(promise.releaseTargets) || promise.releaseTargets.length === 0) {
      failures.push(`${promise.id}: releaseTargets must be non-empty`);
    }
    for (const target of promise.releaseTargets ?? []) {
      if (!releaseTargets.has(target)) failures.push(`${promise.id}: unsupported release target ${target}`);
    }
    for (const assertionId of promise.constitutionalAssertionIds ?? []) {
      if (!assertionById.has(assertionId)) failures.push(`${promise.id}: missing constitutional assertion ${assertionId}`);
    }
    if (!Array.isArray(promise.blockingExternalRows)) {
      failures.push(`${promise.id}: blockingExternalRows must be an array`);
    }
    for (const rawRow of promise.blockingExternalRows ?? []) {
      const row = normalizeBlockingRow(rawRow, promise, failures);
      if (!row.id) {
        failures.push(`${promise.id}: blocking external row missing id`);
        continue;
      }
      if (!externalRows.has(row.id)) {
        failures.push(`${promise.id}: blocking external row ${row.id} is not present in configured ledgers`);
        continue;
      }
      const externalRow = externalRows.get(row.id);
      if (externalRow.completionImpact !== "central_promise_blocker") {
        failures.push(`${promise.id}: blocking external row ${row.id} is ${externalRow.completionImpact}, expected central_promise_blocker`);
      }
      if (row.targets.length === 0) failures.push(`${promise.id}: blocking external row ${row.id} must list targets`);
      for (const target of row.targets) {
        if (!releaseTargets.has(target)) failures.push(`${promise.id}: blocking external row ${row.id} has unsupported target ${target}`);
        if (!(promise.releaseTargets ?? []).includes(target)) {
          failures.push(`${promise.id}: blocking external row ${row.id} target ${target} is outside the promise targets`);
        }
      }
    }
    if (!Array.isArray(promise.evidenceSources) || promise.evidenceSources.length === 0) {
      failures.push(`${promise.id}: evidenceSources must be non-empty`);
    }
    if (!promise.releaseRule || typeof promise.releaseRule !== "string") {
      failures.push(`${promise.id}: releaseRule is required`);
    }
  }

  if (!options.skipDocs) validateDocRouting(failures);
}

function validateDocRouting(failures) {
  const required = [
    ["docs/governance/release-readiness.md", "release_readiness_check.mjs"],
    ["docs/governance/README.md", "Release Readiness"],
    ["docs/decision-map.md", "release_readiness_check.mjs"],
    ["docs/constitution-map.md", "release-readiness.md"],
    ["RELEASING.md", "release_readiness_check.mjs --target <target>"],
    ["docs/discoverability.md", "guard-scripts-release-readiness-check"],
    ["docs/discoverability.registry.json", "guard-scripts-release-readiness-check"],
    ["scripts/test.sh", "release_readiness_check.mjs"],
  ];
  for (const [relativePath, snippet] of required) {
    if (!exists(relativePath)) {
      failures.push(`missing routed document: ${relativePath}`);
      continue;
    }
    if (!read(relativePath).includes(snippet)) {
      failures.push(`${relativePath} is missing required snippet: ${snippet}`);
    }
  }
}

function targetReadinessFailures(manifest, assertionEnvelope, externalRows, target) {
  const failures = [];
  const assertionById = new Map((assertionEnvelope.assertions ?? []).map((assertion) => [assertion.id, assertion]));
  const requiredStatus = manifest.statusRules.requiredAssertionStatus;

  for (const promise of manifest.promises) {
    if (!promise.releaseTargets.includes(target)) continue;
    for (const assertionId of promise.constitutionalAssertionIds) {
      const assertion = assertionById.get(assertionId);
      if (!assertion) continue;
      if (assertion.status !== requiredStatus) {
        failures.push(`${promise.id} blocks ${target}: ${assertionId} is ${assertion.status}, expected ${requiredStatus}`);
      }
    }
    for (const rawRow of promise.blockingExternalRows ?? []) {
      const row = normalizeBlockingRow(rawRow, promise, failures);
      if (!row.targets.includes(target)) continue;
      const externalRow = externalRows.get(row.id);
      if (!externalRow) continue;
      const status = normalizeStatus(externalRow.currentStatus);
      if (status !== "external-pending") continue;
      if (acceptedExternalStatuses.has(status) || hasScopeRevision(externalRow, externalRow.ledgerText)) continue;
      failures.push(`${promise.id} blocks ${target}: ${row.id} remains EXTERNAL PENDING in ${externalRow.sourcePath}`);
    }
  }

  return failures;
}

function parseArgs() {
  let target = "";
  let selfTest = false;
  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--self-test") {
      selfTest = true;
      continue;
    }
    if (arg === "--target") {
      target = args[index + 1] || "";
      index += 1;
      continue;
    }
    if (arg.startsWith("--target=")) {
      target = arg.slice("--target=".length);
      continue;
    }
    throw new Error(`unknown argument: ${arg}`);
  }
  return { target, selfTest };
}

function fixtureEnvelope() {
  return {
    assertions: [
      { id: "A.enforced", status: "enforced" },
      { id: "B.partial", status: "partial" },
      { id: "C.external", status: "external-pending" },
    ],
  };
}

function fixtureExternalRows(failures) {
  const text = `| ID | Requirement | Local evidence | Missing prerequisite | Status |
| --- | --- | --- | --- | --- |
| FIX-CENTRAL | Central promise | local | signed host | EXTERNAL PENDING |
| FIX-DONE | Complete promise | local | none | VALIDATED LOCAL |

## Goal Completion Impact

| External pending row | linkedPromiseIds | linkedDecisionIds | completionImpact | closureEffect | reentryCondition | evidenceRequired |
| --- | --- | --- | --- | --- | --- | --- |
| FIX-CENTRAL | promise.native | D1 | central_promise_blocker | blocks_goal | signed host available | signed-host receipt |
| FIX-DONE | promise.native | D2 | central_promise_blocker | blocks_goal | none | signed-host receipt |`;
  return new Map(extractGoalCompletionImpactRows(text, "fixture.md", failures).map((row) => [
    row.id,
    { ...row, currentStatus: findCurrentStatus(text, row.id), ledgerText: text },
  ]));
}

function fixtureManifest(overrides = {}) {
  return {
    schemaVersion: 1,
    scope: "v1-central-promises",
    sources: {
      constitutionAssertions: "docs/constitution.assertions.json",
      humanMatrix: "docs/governance/release-readiness.md",
      externalPendingLedgers: ["fixture.md"],
    },
    releaseTargets: ["macos-release"],
    statusRules: {
      requiredAssertionStatus: "enforced",
      blockingExternalStatus: "EXTERNAL PENDING",
      blockingCompletionImpact: "central_promise_blocker",
    },
    promises: [
      {
        id: "fixture-promise",
        title: "Fixture promise",
        constitutionalAssertionIds: ["A.enforced"],
        releaseTargets: ["macos-release"],
        blockingExternalRows: [],
        evidenceSources: ["fixture.md"],
        releaseRule: "Fixture rule.",
        ...(overrides.promise ?? {}),
      },
    ],
    ...overrides.manifest,
  };
}

function expectFailure(name, run, expectedPattern) {
  const failures = run();
  if (!failures.some((failure) => expectedPattern.test(failure))) {
    throw new Error(`${name}: expected failure matching ${expectedPattern}, got ${failures.join("; ") || "<none>"}`);
  }
}

function runSelfTest() {
  const envelope = fixtureEnvelope();
  const setupFailures = [];
  const externalRows = fixtureExternalRows(setupFailures);
  if (setupFailures.length > 0) throw new Error(`fixture setup failed: ${setupFailures.join("; ")}`);

  let failures = [];
  validateManifest(fixtureManifest(), envelope, externalRows, failures, { skipDocs: true });
  if (failures.length > 0) throw new Error(`valid fixture failed shape validation: ${failures.join("; ")}`);
  failures = targetReadinessFailures(fixtureManifest(), envelope, externalRows, "macos-release");
  if (failures.length > 0) throw new Error(`valid fixture failed target readiness: ${failures.join("; ")}`);

  expectFailure("partial assertion blocks release", () => {
    const manifest = fixtureManifest({ promise: { constitutionalAssertionIds: ["B.partial"] } });
    return targetReadinessFailures(manifest, envelope, externalRows, "macos-release");
  }, /B\.partial is partial/);

  expectFailure("external-pending assertion blocks release", () => {
    const manifest = fixtureManifest({ promise: { constitutionalAssertionIds: ["C.external"] } });
    return targetReadinessFailures(manifest, envelope, externalRows, "macos-release");
  }, /C\.external is external-pending/);

  expectFailure("missing assertion fails shape validation", () => {
    const manifest = fixtureManifest({ promise: { constitutionalAssertionIds: ["missing.assertion"] } });
    const shapeFailures = [];
    validateManifest(manifest, envelope, externalRows, shapeFailures, { skipDocs: true });
    return shapeFailures;
  }, /missing constitutional assertion/);

  expectFailure("unresolved central blocker blocks release", () => {
    const manifest = fixtureManifest({
      promise: { blockingExternalRows: [{ id: "FIX-CENTRAL", targets: ["macos-release"] }] },
    });
    return targetReadinessFailures(manifest, envelope, externalRows, "macos-release");
  }, /FIX-CENTRAL remains EXTERNAL PENDING/);
}

function main() {
  const { target, selfTest } = parseArgs();
  if (selfTest) {
    runSelfTest();
    console.log("Release readiness self-test passed");
    return;
  }

  const failures = [];
  if (target && !releaseTargets.has(target)) failures.push(`unsupported release target: ${target}`);
  const manifest = readJson("docs/governance/release-readiness.manifest.json");
  const assertionEnvelope = readJson(manifest.sources?.constitutionAssertions ?? "docs/constitution.assertions.json");
  const externalRows = loadExternalRows(manifest, rootDir, failures);
  validateManifest(manifest, assertionEnvelope, externalRows, failures);
  if (target && failures.length === 0) {
    failures.push(...targetReadinessFailures(manifest, assertionEnvelope, externalRows, target));
  }

  if (failures.length > 0) {
    console.error("Release readiness check failed:");
    for (const failure of failures) console.error(`- ${failure}`);
    process.exit(1);
  }

  console.log(target
    ? `Release readiness passed for ${target}`
    : "Release readiness manifest passed");
}

try {
  main();
} catch (error) {
  console.error("Release readiness check failed:");
  console.error(`- ${error.message}`);
  process.exit(1);
}
