#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const require = createRequire(import.meta.url);
const Ajv2020Module = require("ajv/dist/2020");
const Ajv2020 = Ajv2020Module.default ?? Ajv2020Module;
const schemaPath = path.join(rootDir, "docs/system-telemetry-external-approval.schema.json");
const fixturesPath = path.join(rootDir, "docs/system-telemetry-external-approval.fixtures.json");

function usage() {
  return [
    "System telemetry external approval validator",
    "Usage:",
    "  node scripts/validate-system-telemetry-external-approval.mjs <packet.json>",
    "  node scripts/validate-system-telemetry-external-approval.mjs --fixtures",
  ].join("\n");
}

function readJson(absolutePath) {
  return JSON.parse(fs.readFileSync(absolutePath, "utf8"));
}

function fail(message, details = undefined) {
  console.error(JSON.stringify({ ok: false, message, details }, null, 2));
  process.exit(1);
}

function compileSchema() {
  const schema = readJson(schemaPath);
  const ajv = new Ajv2020({ allErrors: true, validateFormats: false, strict: false });
  return { ajv, validate: ajv.compile(schema) };
}

function assertPublicSafePacket(packet, label) {
  const serialized = JSON.stringify(packet);
  if (serialized.includes("/Users/")) {
    fail(`${label}: packet contains a private filesystem path`);
  }
}

function mutateTemplate(packet, mutation) {
  const mutated = JSON.parse(JSON.stringify(packet));
  switch (mutation) {
    case "approval.exactRunApproved=false":
      mutated.approval.exactRunApproved = false;
      break;
    case "authorization.signedAppRefs=[]":
      mutated.authorization.signedAppRefs = [];
      break;
    case "risk.appMenuValidationPlanRef=\"\"":
      mutated.risk.appMenuValidationPlanRef = "";
      break;
    default:
      fail(`unknown approval fixture mutation ${mutation}`);
  }
  return mutated;
}

function validatePacket(packet, label) {
  assertPublicSafePacket(packet, label);
  const { ajv, validate } = compileSchema();
  const ok = validate(packet);
  if (!ok) {
    fail(`${label}: packet does not conform to Clawix system telemetry external approval schema`, ajv.errorsText(validate.errors));
  }
  return { laneId: packet.laneId, repoScope: packet.repoScope };
}

function validateFixtures() {
  const fixtures = readJson(fixturesPath);
  if (fixtures.status !== "synthetic_templates_not_approval") {
    fail("fixtures must remain synthetic approval templates only");
  }
  const { ajv, validate } = compileSchema();
  const validSyntheticPackets = fixtures.validSyntheticPackets ?? [];
  const invalidSyntheticPackets = fixtures.invalidSyntheticPackets ?? [];
  const validByLaneId = new Map();
  const accepted = [];
  for (const packet of validSyntheticPackets) {
    assertPublicSafePacket(packet, `valid fixture ${packet.laneId}`);
    if (!validate(packet)) {
      fail(`valid fixture ${packet.laneId} did not validate`, ajv.errorsText(validate.errors));
    }
    validByLaneId.set(packet.laneId, packet);
    accepted.push(packet.laneId);
  }
  for (const fixture of invalidSyntheticPackets) {
    const base = validByLaneId.get(fixture.packetRef);
    if (!base) {
      fail(`invalid fixture ${fixture.id} references unknown lane ${fixture.packetRef}`);
    }
    const mutated = mutateTemplate(base, fixture.mutation);
    assertPublicSafePacket(mutated, `invalid fixture ${fixture.id}`);
    if (validate(mutated)) {
      fail(`invalid fixture ${fixture.id} unexpectedly validated`);
    }
  }
  return {
    status: fixtures.status,
    validSyntheticPackets: validSyntheticPackets.length,
    invalidSyntheticPackets: invalidSyntheticPackets.length,
    accepted,
  };
}

const args = process.argv.slice(2);
if (args.length !== 1 || args.includes("--help")) {
  console.error(usage());
  process.exit(args.includes("--help") ? 0 : 1);
}

if (args[0] === "--fixtures") {
  console.log(JSON.stringify({ ok: true, ...validateFixtures() }, null, 2));
} else {
  const packetPath = path.resolve(process.cwd(), args[0]);
  const result = validatePacket(readJson(packetPath), path.relative(rootDir, packetPath));
  console.log(JSON.stringify({ ok: true, ...result }, null, 2));
}
