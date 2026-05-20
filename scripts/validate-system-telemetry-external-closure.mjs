#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const require = createRequire(import.meta.url);
const Ajv2020Module = require("ajv/dist/2020");
const Ajv2020 = Ajv2020Module.default ?? Ajv2020Module;

const approvalSchemaPath = path.join(rootDir, "docs/governance/system-telemetry/external-approval.schema.json");
const approvalFixturesPath = path.join(rootDir, "docs/governance/system-telemetry/external-approval.fixtures.json");
const evidenceSchemaPath = path.join(rootDir, "docs/governance/system-telemetry/external-evidence.schema.json");
const evidenceFixturesPath = path.join(rootDir, "docs/governance/system-telemetry/external-evidence.fixtures.json");
const closureFixturesPath = path.join(rootDir, "docs/governance/system-telemetry/external-closure.fixtures.json");

function usage() {
  return [
    "System telemetry external closure validator",
    "Usage:",
    "  node scripts/validate-system-telemetry-external-closure.mjs <bundle.json>",
    "  node scripts/validate-system-telemetry-external-closure.mjs --fixtures",
  ].join("\n");
}

function readJson(absolutePath) {
  return JSON.parse(fs.readFileSync(absolutePath, "utf8"));
}

function fail(message, details = undefined) {
  console.error(JSON.stringify({ ok: false, message, details }, null, 2));
  process.exit(1);
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function assertPublicSafe(value, label) {
  const serialized = JSON.stringify(value);
  assert(!serialized.includes("/Users/"), `${label}: contains a private filesystem path`);
  assert(!serialized.includes("file://"), `${label}: contains a file URL`);
  assert(!serialized.includes("secret://"), `${label}: contains a raw secret reference`);
  assert(!serialized.includes("-----BEGIN"), `${label}: contains key material marker`);
  assert(!serialized.includes("sk-"), `${label}: contains raw API key marker`);
  assert(!serialized.includes("AKIA"), `${label}: contains raw access key marker`);
}

function compileSchema(schemaPath) {
  const schema = readJson(schemaPath);
  const ajv = new Ajv2020({ allErrors: true, validateFormats: false, strict: false });
  const validate = ajv.compile(schema);
  return { ajv, validate };
}

const approvalSchema = compileSchema(approvalSchemaPath);
const evidenceSchema = compileSchema(evidenceSchemaPath);
const expectedClosureRowsByLane = new Map([
  ["CLX-SYS-TEL-EXT-003", {
    rowsToReplace: ["CLX-SYS-TEL-EXT-003"],
    manifestRows: ["CLX-SYS-TEL-EXT-003"],
    completionAuditRows: ["CLX-STA-014"],
    sourceQaRows: ["CLX-STQA-003"],
  }],
  ["CLX-SYS-TEL-EXT-004", {
    rowsToReplace: ["CLX-SYS-TEL-EXT-004"],
    manifestRows: ["CLX-SYS-TEL-EXT-004"],
    completionAuditRows: ["CLX-STA-015"],
    sourceQaRows: ["CLX-STQA-003"],
  }],
  ["CLX-SYS-TEL-EXT-005", {
    rowsToReplace: ["CLX-SYS-TEL-EXT-005"],
    manifestRows: ["CLX-SYS-TEL-EXT-005"],
    completionAuditRows: ["CLX-STA-016"],
    sourceQaRows: ["CLX-STQA-003"],
  }],
]);

function validatePacket(packet, compiled, label) {
  assertPublicSafe(packet, label);
  assert(compiled.validate(packet), `${label}: ${compiled.ajv.errorsText(compiled.validate.errors)}`);
}

function parseTime(value, label) {
  const time = Date.parse(value);
  assert(Number.isFinite(time), `${label}: must be a parseable timestamp`);
  return time;
}

function assertWithinApprovalWindow(bundle, label) {
  const approvedAt = parseTime(bundle.approvalPacket.approval?.approvedAt, `${label}.approvalPacket.approval.approvedAt`);
  const expiresAt = parseTime(bundle.approvalPacket.approval?.expiresAt, `${label}.approvalPacket.approval.expiresAt`);
  assert(expiresAt > approvedAt, `${label}: approval expiry must be after approval time`);
  const checks = [
    ["evidencePacket.runAuthorization.approvedAt", bundle.evidencePacket.runAuthorization?.approvedAt],
    ["evidencePacket.preflight.completedAt", bundle.evidencePacket.preflight?.completedAt],
    ["evidencePacket.execution.startedAt", bundle.evidencePacket.execution?.startedAt],
    ["evidencePacket.execution.completedAt", bundle.evidencePacket.execution?.completedAt],
    ["evidencePacket.reviewer.reviewedAt", bundle.evidencePacket.reviewer?.reviewedAt],
  ];
  for (const [field, value] of checks) {
    const time = parseTime(value, `${label}.${field}`);
    assert(time >= approvedAt && time <= expiresAt, `${label}: ${field} must be within the exact approval window`);
  }
}

function assertEvidenceTimeline(bundle, label) {
  const preflightCompletedAt = parseTime(bundle.evidencePacket.preflight?.completedAt, `${label}.evidencePacket.preflight.completedAt`);
  const executionStartedAt = parseTime(bundle.evidencePacket.execution?.startedAt, `${label}.evidencePacket.execution.startedAt`);
  const executionCompletedAt = parseTime(bundle.evidencePacket.execution?.completedAt, `${label}.evidencePacket.execution.completedAt`);
  const reviewedAt = parseTime(bundle.evidencePacket.reviewer?.reviewedAt, `${label}.evidencePacket.reviewer.reviewedAt`);
  assert(executionStartedAt >= preflightCompletedAt, `${label}: evidence execution must start at or after preflight completion`);
  assert(executionCompletedAt >= executionStartedAt, `${label}: evidence execution must complete at or after execution start`);
  assert(reviewedAt >= executionCompletedAt, `${label}: evidence review must happen at or after execution completion`);
}

function assertSameStringSet(actual, expected, label) {
  assert(Array.isArray(actual), `${label}: must be an array`);
  assert(actual.every((value) => typeof value === "string"), `${label}: must contain only strings`);
  const actualSorted = [...actual].sort();
  const expectedSorted = [...expected].sort();
  assert(new Set(actualSorted).size === actualSorted.length, `${label}: must not contain duplicates`);
  assert(actualSorted.length === expectedSorted.length, `${label}: wrong row count`);
  for (let index = 0; index < expectedSorted.length; index += 1) {
    assert(actualSorted[index] === expectedSorted[index], `${label}: expected ${expectedSorted.join(", ")}, got ${actualSorted.join(", ")}`);
  }
}

function assertExactClosureImpact(bundle, label) {
  const expected = expectedClosureRowsByLane.get(bundle.laneId);
  assert(expected, `${label}: missing expected closure rows for ${bundle.laneId}`);
  assertSameStringSet(
    bundle.approvalPacket.closureImpact?.externalPendingRows,
    expected.rowsToReplace,
    `${label}.approvalPacket.closureImpact.externalPendingRows`,
  );
  assertSameStringSet(
    bundle.evidencePacket.closureImpact?.rowsToReplace,
    expected.rowsToReplace,
    `${label}.evidencePacket.closureImpact.rowsToReplace`,
  );
  assertSameStringSet(
    bundle.evidencePacket.closureImpact?.manifestRows,
    expected.manifestRows,
    `${label}.evidencePacket.closureImpact.manifestRows`,
  );
  assertSameStringSet(
    bundle.evidencePacket.closureImpact?.completionAuditRows,
    expected.completionAuditRows,
    `${label}.evidencePacket.closureImpact.completionAuditRows`,
  );
  assertSameStringSet(
    bundle.evidencePacket.closureImpact?.sourceQaRows,
    expected.sourceQaRows,
    `${label}.evidencePacket.closureImpact.sourceQaRows`,
  );
}

function assertAuthorizationBindings(bundle, label) {
  assert(
    bundle.approvalPacket.approval?.approvedBy === bundle.evidencePacket.runAuthorization?.approvedBy,
    `${label}: approval reviewer must match evidence run authorization`,
  );
  assertSameStringSet(
    bundle.evidencePacket.runAuthorization?.credentialLeaseRefs,
    bundle.approvalPacket.authorization?.credentialLeaseRefs ?? [],
    `${label}.evidencePacket.runAuthorization.credentialLeaseRefs`,
  );
  assertSameStringSet(
    bundle.evidencePacket.runAuthorization?.nativeGrantRefs,
    bundle.approvalPacket.authorization?.nativeGrantRefs ?? [],
    `${label}.evidencePacket.runAuthorization.nativeGrantRefs`,
  );
}

function buildFixtureBundle(laneId) {
  const approvalFixtures = readJson(approvalFixturesPath);
  const evidenceFixtures = readJson(evidenceFixturesPath);
  const approvalPacket = approvalFixtures.validSyntheticPackets?.find((packet) => packet.laneId === laneId);
  const evidencePacket = evidenceFixtures.validSyntheticPackets?.find((packet) => packet.laneId === laneId);
  assert(approvalPacket, `fixture bundle references unknown approval lane ${laneId}`);
  assert(evidencePacket, `fixture bundle references unknown evidence lane ${laneId}`);
  return {
    schemaVersion: 1,
    conversationId: approvalPacket.conversationId,
    planId: approvalPacket.planId,
    repoScope: approvalPacket.repoScope,
    laneId,
    approvalPacket,
    evidencePacket,
  };
}

function validateClosureBundle(bundle, label) {
  assert(bundle && typeof bundle === "object" && !Array.isArray(bundle), `${label}: bundle must be an object`);
  assertPublicSafe(bundle, label);
  for (const field of ["schemaVersion", "conversationId", "planId", "repoScope", "laneId", "approvalPacket", "evidencePacket"]) {
    assert(Object.hasOwn(bundle, field), `${label}: missing ${field}`);
  }
  assert(bundle.schemaVersion === 1, `${label}: schemaVersion must be 1`);
  validatePacket(bundle.approvalPacket, approvalSchema, `${label}.approvalPacket`);
  validatePacket(bundle.evidencePacket, evidenceSchema, `${label}.evidencePacket`);

  for (const field of ["conversationId", "planId", "repoScope", "laneId"]) {
    assert(bundle[field] === bundle.approvalPacket[field], `${label}: ${field} does not match approval packet`);
    assert(bundle[field] === bundle.evidencePacket[field], `${label}: ${field} does not match evidence packet`);
  }

  assertExactClosureImpact(bundle, label);
  assert(
    bundle.approvalPacket.preflight?.command === bundle.evidencePacket.preflight?.command,
    `${label}: approval and evidence preflight commands must match`,
  );
  assert(
    bundle.approvalPacket.authorization?.networkAccessApproved === bundle.evidencePacket.runAuthorization?.networkAccessApproved,
    `${label}: approval and evidence network authorization must match`,
  );
  assertAuthorizationBindings(bundle, label);
  assert(
    bundle.approvalPacket.approval?.approvalId === bundle.evidencePacket.runAuthorization?.approvalId,
    `${label}: approval id must match evidence run authorization`,
  );
  assert(
    bundle.approvalPacket.approval?.exactRunScope === bundle.evidencePacket.runAuthorization?.exactRunScope,
    `${label}: approval exact run scope must match evidence run authorization`,
  );
  assert(
    bundle.approvalPacket.approval?.approvedAt === bundle.evidencePacket.runAuthorization?.approvedAt,
    `${label}: approval timestamp must match evidence run authorization`,
  );
  assertWithinApprovalWindow(bundle, label);
  assertEvidenceTimeline(bundle, label);
  return { laneId: bundle.laneId, repoScope: bundle.repoScope };
}

function mutateBundle(bundle, mutation) {
  const mutated = JSON.parse(JSON.stringify(bundle));
  switch (mutation) {
    case "evidencePacket.laneId=CLX-SYS-TEL-EXT-004":
      mutated.evidencePacket.laneId = "CLX-SYS-TEL-EXT-004";
      break;
    case "evidencePacket.repoScope=wrong-scope":
      mutated.evidencePacket.repoScope = "wrong-scope";
      break;
    case "approvalPacket.approval.exactRunApproved=false":
      mutated.approvalPacket.approval.exactRunApproved = false;
      break;
    case "approvalPacket.preflight.command=mismatch":
      mutated.approvalPacket.preflight.command = "claw system providers plan mismatched.template --json";
      break;
    case "evidencePacket.runAuthorization.approvalId=mismatch":
      mutated.evidencePacket.runAuthorization.approvalId = "approval_mismatched_template";
      break;
    case "evidencePacket.runAuthorization.exactRunScope=mismatch":
      mutated.evidencePacket.runAuthorization.exactRunScope = "mismatched exact run template";
      break;
    case "evidencePacket.runAuthorization.approvedAt=mismatch":
      mutated.evidencePacket.runAuthorization.approvedAt = "2026-05-20T00:00:01Z";
      break;
    case "evidencePacket.execution.completedAt=afterApprovalExpiry":
      mutated.evidencePacket.execution.completedAt = "2026-05-22T00:00:00Z";
      break;
    case "evidencePacket.closureImpact.completionAuditRows=wrong":
      mutated.evidencePacket.closureImpact.completionAuditRows = ["CLX-STA-999"];
      break;
    case "approvalPacket.closureImpact.externalPendingRows=extra":
      mutated.approvalPacket.closureImpact.externalPendingRows = [mutated.laneId, "CLX-SYS-TEL-EXT-999"];
      break;
    case "evidencePacket.runAuthorization.approvedBy=mismatch":
      mutated.evidencePacket.runAuthorization.approvedBy = "other-reviewer-template";
      break;
    case "evidencePacket.runAuthorization.credentialLeaseRefs=wrong":
      mutated.evidencePacket.runAuthorization.credentialLeaseRefs = ["wrong_credential_lease_template"];
      break;
    case "evidencePacket.runAuthorization.nativeGrantRefs=wrong":
      mutated.evidencePacket.runAuthorization.nativeGrantRefs = ["wrong_native_grant_template"];
      break;
    case "evidencePacket.execution.completedAt=beforeExecutionStart":
      mutated.evidencePacket.execution.completedAt = "2026-05-19T23:59:59Z";
      break;
    case "evidencePacket.reviewer.reviewedAt=beforeExecutionCompleted":
      mutated.evidencePacket.reviewer.reviewedAt = "2026-05-19T23:59:59Z";
      break;
    default:
      throw new Error(`unknown closure fixture mutation ${mutation}`);
  }
  return mutated;
}

function validateFixtures() {
  const fixtures = readJson(closureFixturesPath);
  assert(fixtures.status === "synthetic_templates_not_closure", "fixtures must remain synthetic closure templates only");
  assert(fixtures.approvalFixturesPath === "docs/governance/system-telemetry/external-approval.fixtures.json", "fixtures reference wrong approval fixtures path");
  assert(fixtures.evidenceFixturesPath === "docs/governance/system-telemetry/external-evidence.fixtures.json", "fixtures reference wrong evidence fixtures path");
  assert(fixtures.validatorPath === "scripts/validate-system-telemetry-external-closure.mjs", "fixtures reference wrong validator path");
  assertPublicSafe(fixtures, "closure fixtures");
  const accepted = [];
  for (const fixture of fixtures.validSyntheticBundles ?? []) {
    const result = validateClosureBundle(buildFixtureBundle(fixture.laneId), `valid fixture ${fixture.laneId}`);
    accepted.push(result.laneId);
  }
  for (const fixture of fixtures.invalidSyntheticMutations ?? []) {
    const base = buildFixtureBundle(fixture.baseLaneId);
    let rejected = false;
    try {
      validateClosureBundle(mutateBundle(base, fixture.mutation), `invalid fixture ${fixture.id}`);
    } catch {
      rejected = true;
    }
    assert(rejected, `invalid fixture ${fixture.id} unexpectedly validated`);
  }
  return {
    status: fixtures.status,
    validSyntheticBundles: fixtures.validSyntheticBundles?.length ?? 0,
    invalidSyntheticMutations: fixtures.invalidSyntheticMutations?.length ?? 0,
    accepted,
  };
}

const args = process.argv.slice(2);
if (args.length !== 1 || args.includes("--help")) {
  console.error(usage());
  process.exit(args.includes("--help") ? 0 : 1);
}

try {
  if (args[0] === "--fixtures") {
    console.log(JSON.stringify({ ok: true, ...validateFixtures() }, null, 2));
  } else {
    const bundlePath = path.resolve(process.cwd(), args[0]);
    const result = validateClosureBundle(readJson(bundlePath), path.relative(rootDir, bundlePath));
    console.log(JSON.stringify({ ok: true, ...result }, null, 2));
  }
} catch (error) {
  fail(error.message);
}
