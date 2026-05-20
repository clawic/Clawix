#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const require = createRequire(import.meta.url);
const Ajv2020Module = require("ajv/dist/2020");
const Ajv2020 = Ajv2020Module.default ?? Ajv2020Module;

const approvalSchemaPath = path.join(rootDir, "docs/system-telemetry-external-approval.schema.json");
const approvalFixturesPath = path.join(rootDir, "docs/system-telemetry-external-approval.fixtures.json");
const evidenceSchemaPath = path.join(rootDir, "docs/system-telemetry-external-evidence.schema.json");
const evidenceFixturesPath = path.join(rootDir, "docs/system-telemetry-external-evidence.fixtures.json");
const closureFixturesPath = path.join(rootDir, "docs/system-telemetry-external-closure.fixtures.json");

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
}

function compileSchema(schemaPath) {
  const schema = readJson(schemaPath);
  const ajv = new Ajv2020({ allErrors: true, validateFormats: false, strict: false });
  const validate = ajv.compile(schema);
  return { ajv, validate };
}

const approvalSchema = compileSchema(approvalSchemaPath);
const evidenceSchema = compileSchema(evidenceSchemaPath);

function validatePacket(packet, compiled, label) {
  assertPublicSafe(packet, label);
  assert(compiled.validate(packet), `${label}: ${compiled.ajv.errorsText(compiled.validate.errors)}`);
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

  assert(
    bundle.approvalPacket.closureImpact?.externalPendingRows?.includes(bundle.laneId),
    `${label}: approval packet does not authorize closure for ${bundle.laneId}`,
  );
  assert(
    bundle.evidencePacket.closureImpact?.rowsToReplace?.includes(bundle.laneId),
    `${label}: evidence packet does not replace ${bundle.laneId}`,
  );
  assert(
    bundle.approvalPacket.preflight?.command === bundle.evidencePacket.preflight?.command,
    `${label}: approval and evidence preflight commands must match`,
  );
  assert(
    bundle.approvalPacket.authorization?.networkAccessApproved === bundle.evidencePacket.runAuthorization?.networkAccessApproved,
    `${label}: approval and evidence network authorization must match`,
  );
  assert(
    bundle.approvalPacket.approval?.approvalId === bundle.evidencePacket.runAuthorization?.approvalId,
    `${label}: approval id must match evidence run authorization`,
  );
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
    default:
      throw new Error(`unknown closure fixture mutation ${mutation}`);
  }
  return mutated;
}

function validateFixtures() {
  const fixtures = readJson(closureFixturesPath);
  assert(fixtures.status === "synthetic_templates_not_closure", "fixtures must remain synthetic closure templates only");
  assert(fixtures.approvalFixturesPath === "docs/system-telemetry-external-approval.fixtures.json", "fixtures reference wrong approval fixtures path");
  assert(fixtures.evidenceFixturesPath === "docs/system-telemetry-external-evidence.fixtures.json", "fixtures reference wrong evidence fixtures path");
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
