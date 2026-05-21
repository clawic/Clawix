#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = process.argv.slice(2);
const errors = [];

const releaseTargets = new Set([
  "macos-release",
  "ios-release",
  "linux-release",
  "windows-release",
]);

const ledgerSpecs = [
  {
    path: "docs/governance/legal/external-pending.md",
    defaultTargets: ["macos-release", "ios-release", "linux-release", "windows-release"],
  },
  {
    path: "docs/governance/sdk-first-custom-surfaces/external-pending.md",
    defaultTargets: ["macos-release", "ios-release", "windows-release"],
  },
  {
    path: "docs/governance/system-telemetry/external-pending.md",
    defaultTargets: ["macos-release"],
  },
];

const rowTargetOverrides = new Map([
  ["CLX-SDK-EXT-001", ["macos-release"]],
  ["CLX-SDK-EXT-002", ["macos-release", "ios-release", "windows-release"]],
  ["CLX-SDK-EXT-003", ["macos-release", "ios-release", "windows-release"]],
  ["CLX-SDK-EXT-004", []],
  ["CLX-SYS-TEL-EXT-003", ["macos-release"]],
  ["CLX-SYS-TEL-EXT-004", ["macos-release"]],
  ["CLX-SYS-TEL-EXT-005", ["macos-release"]],
]);

function fail(message) {
  errors.push(message);
}

function read(relativePath) {
  return fs.readFileSync(path.join(rootDir, relativePath), "utf8");
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

function normalizeStatus(status) {
  return String(status || "").trim().toLowerCase().replace(/[_ ]/g, "-");
}

function extractGoalCompletionImpactRows(text, sourcePath) {
  const start = text.indexOf("## Goal Completion Impact");
  if (start === -1) {
    fail(`${sourcePath}: missing ## Goal Completion Impact section`);
    return [];
  }
  const remainder = text.slice(start);
  const nextHeading = remainder.slice(1).search(/\n## /);
  const section = nextHeading === -1 ? remainder : remainder.slice(0, nextHeading + 1);
  const tableLines = section
    .split("\n")
    .filter((line) => line.trim().startsWith("|") && !/^\|\s*-+/.test(line));
  if (tableLines.length < 2) {
    fail(`${sourcePath}: goal completion impact table must include a header and rows`);
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
    fail(`${sourcePath}: goal completion impact table headers must be ${expectedHeaders.join(", ")}`);
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

function inScopeTargets(row, spec) {
  return rowTargetOverrides.get(row.id) ?? spec.defaultTargets;
}

function hasAcceptedReleaseEvidence(row) {
  const status = normalizeStatus(row.currentStatus);
  return ["pass", "passed", "validated", "validated-local", "validated-private", "verified", "verified-complete"].includes(status);
}

function hasScopeRevision(row, ledgerText) {
  if (row.closureEffect !== "requires_scope_revision") return false;
  const escapedId = row.id.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const explicitRevision = new RegExp(`${escapedId}[^\\n]*scope_revision|scope_revision[^\\n]*${escapedId}`);
  return ledgerText
    .split("\n")
    .some((line) => !line.trim().startsWith("|") && explicitRevision.test(line));
}

function blockersForTarget(target, specs = ledgerSpecs) {
  const blockers = [];
  for (const spec of specs) {
    const text = spec.text ?? read(spec.path);
    const rows = extractGoalCompletionImpactRows(text, spec.path);
    for (const row of rows) {
      row.currentStatus = findCurrentStatus(text, row.id);
      const targets = inScopeTargets(row, spec);
      if (!targets.includes(target)) continue;
      if (row.completionImpact !== "central_promise_blocker") continue;
      if (normalizeStatus(row.currentStatus) !== "external-pending") continue;
      if (hasAcceptedReleaseEvidence(row) || hasScopeRevision(row, text)) continue;
      blockers.push({
        id: row.id,
        sourcePath: row.sourcePath,
        closureEffect: row.closureEffect,
        evidenceRequired: row.evidenceRequired.join(", "),
      });
    }
  }
  return blockers;
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
    fail(`unknown argument: ${arg}`);
  }
  return { target, selfTest };
}

function assertFixture(name, specs, target, expectedIds) {
  errors.length = 0;
  const actual = blockersForTarget(target, specs).map((blocker) => blocker.id).sort();
  const expected = [...expectedIds].sort();
  if (actual.join(",") !== expected.join(",")) {
    fail(`${name}: expected blockers ${expected.join(",") || "<none>"}, got ${actual.join(",") || "<none>"}`);
  }
  const fixtureErrors = [...errors];
  errors.length = 0;
  for (const error of fixtureErrors) fail(error);
}

function runSelfTest() {
  const header = `## Goal Completion Impact

| External pending row | linkedPromiseIds | linkedDecisionIds | completionImpact | closureEffect | reentryCondition | evidenceRequired |
| --- | --- | --- | --- | --- | --- | --- |`;
  const rows = {
    central: "| FIX-CENTRAL | promise.native | D1 | central_promise_blocker | blocks_goal | signed host is available. | signed-host receipt |",
    validation: "| FIX-VALIDATION | none | D2 | validation_only | allows_local_completion | UI smoke is available. | smoke result |",
    future: "| FIX-FUTURE | none | D3 | future_extension | allows_local_completion | Future store claim exists. | store receipt |",
    scoped: "| FIX-SCOPED | promise.native | D4 | central_promise_blocker | requires_scope_revision | Scope revision exists. | scope revision audit |",
  };
  const currentRows = `| ID | Requirement | Local evidence | Missing prerequisite | Status |
| --- | --- | --- | --- | --- |
| FIX-CENTRAL | Central native promise | local | host | EXTERNAL PENDING |
| FIX-VALIDATION | Validation-only smoke | local | host | EXTERNAL PENDING |
| FIX-FUTURE | Future release claim | local | store | EXTERNAL PENDING |
| FIX-SCOPED | Rescoped central promise | local | scope | EXTERNAL PENDING |`;

  assertFixture(
    "central pending blocks target",
    [{ path: "fixture.md", text: `${currentRows}\n\n${header}\n${rows.central}`, defaultTargets: ["macos-release"] }],
    "macos-release",
    ["FIX-CENTRAL"],
  );
  assertFixture(
    "validation-only pending is report-only",
    [{ path: "fixture.md", text: `${currentRows}\n\n${header}\n${rows.validation}`, defaultTargets: ["macos-release"] }],
    "macos-release",
    [],
  );
  assertFixture(
    "future-extension pending does not block current release",
    [{ path: "fixture.md", text: `${currentRows}\n\n${header}\n${rows.future}`, defaultTargets: ["macos-release"] }],
    "macos-release",
    [],
  );
  assertFixture(
    "out-of-scope central pending does not block",
    [{ path: "fixture.md", text: `${currentRows}\n\n${header}\n${rows.central}`, defaultTargets: ["linux-release"] }],
    "macos-release",
    [],
  );
  assertFixture(
    "scope revision permits release only when recorded explicitly",
    [{
      path: "fixture.md",
      text: `${currentRows}\n\n${header}\n${rows.scoped}\n\nScope revision: FIX-SCOPED scope_revision decision accepted.`,
      defaultTargets: ["macos-release"],
    }],
    "macos-release",
    [],
  );
  assertFixture(
    "scope revision closure effect without recorded decision still blocks",
    [{ path: "fixture.md", text: `${currentRows}\n\n${header}\n${rows.scoped}`, defaultTargets: ["macos-release"] }],
    "macos-release",
    ["FIX-SCOPED"],
  );

  const strictHost = spawnSync("bash", ["scripts/test.sh", "host"], {
    cwd: rootDir,
    env: { ...process.env, CLAWIX_TEST_STRICT_EXTERNAL_PENDING: "1" },
    encoding: "utf8",
  });
  const strictHostOutput = `${strictHost.stdout || ""}${strictHost.stderr || ""}`;
  if (strictHost.status === 0 || !strictHostOutput.includes("strict release host lane blocked")) {
    fail("strict host lane must fail when CLAWIX_HOST_TEST_COMMAND is missing");
  }
  const strictDevice = spawnSync("bash", ["scripts/test.sh", "device"], {
    cwd: rootDir,
    env: { ...process.env, CLAWIX_TEST_STRICT_EXTERNAL_PENDING: "1", CLAWIX_SKIP_ANDROID_UNIT_TESTS: "1" },
    encoding: "utf8",
  });
  const strictDeviceOutput = `${strictDevice.stdout || ""}${strictDevice.stderr || ""}`;
  if (strictDevice.status === 0 || !strictDeviceOutput.includes("strict release device lane blocked")) {
    fail("strict device lane must fail when CLAWIX_DEVICE_TEST_COMMAND is missing");
  }
}

const { target, selfTest } = parseArgs();
if (selfTest) {
  runSelfTest();
} else {
  if (!target) fail("missing --target <macos-release|ios-release|linux-release|windows-release>");
  if (target && !releaseTargets.has(target)) fail(`unsupported release target: ${target}`);
  if (errors.length === 0) {
    const blockers = blockersForTarget(target);
    for (const blocker of blockers) {
      fail(`${blocker.id} blocks ${target}: ${blocker.sourcePath} remains EXTERNAL PENDING (${blocker.evidenceRequired})`);
    }
  }
}

if (errors.length > 0) {
  console.error("Release external pending gate failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(selfTest
  ? "Release external pending gate self-test passed"
  : `Release external pending gate passed for ${target}`);
