#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const require = createRequire(import.meta.url);
const Ajv2020Module = require("ajv/dist/2020");
const Ajv2020 = Ajv2020Module.default ?? Ajv2020Module;
const schemaPath = path.join(rootDir, "docs/governance/system-telemetry/external-evidence.schema.json");
const fixturesPath = path.join(rootDir, "docs/governance/system-telemetry/external-evidence.fixtures.json");

function usage() {
  return [
    "Usage:",
    "  node scripts/validate-system-telemetry-external-evidence.mjs <packet.json>",
    "  node scripts/validate-system-telemetry-external-evidence.mjs --fixtures",
  ].join("\n");
}

function readJson(absolutePath) {
  return JSON.parse(fs.readFileSync(absolutePath, "utf8"));
}

function fail(message, details = undefined) {
  console.error(JSON.stringify({ ok: false, message, details }, null, 2));
  process.exit(1);
}

function publicSafetyErrors(value) {
  const serialized = JSON.stringify(value);
  const checks = [
    ["/Users/", "packet contains a private filesystem path"],
    ["file://", "packet contains a file URL"],
    ["secret://", "packet contains a raw secret reference"],
    ["-----BEGIN", "packet contains key material marker"],
    ["sk-", "packet contains raw API key marker"],
    ["AKIA", "packet contains raw access key marker"],
  ];
  return checks
    .filter(([pattern]) => serialized.includes(pattern))
    .map(([, message]) => message);
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

function parseTime(value) {
  const time = Date.parse(value);
  return Number.isFinite(time) ? time : undefined;
}

function evidencePacketErrors(packet, compiled) {
  const errors = [];
  errors.push(...publicSafetyErrors(packet));
  if (!compiled.validate(packet)) {
    errors.push(`schema: ${compiled.ajv.errorsText(compiled.validate.errors)}`);
  }
  const preflightCompletedAt = parseTime(packet.preflight?.completedAt);
  const approvedAt = parseTime(packet.runAuthorization?.approvedAt);
  const executionStartedAt = parseTime(packet.execution?.startedAt);
  const executionCompletedAt = parseTime(packet.execution?.completedAt);
  const reviewedAt = parseTime(packet.reviewer?.reviewedAt);
  if (approvedAt === undefined) errors.push("runAuthorization.approvedAt must be a parseable timestamp");
  if (preflightCompletedAt === undefined) errors.push("preflight.completedAt must be a parseable timestamp");
  if (executionStartedAt === undefined) errors.push("execution.startedAt must be a parseable timestamp");
  if (executionCompletedAt === undefined) errors.push("execution.completedAt must be a parseable timestamp");
  if (reviewedAt === undefined) errors.push("reviewer.reviewedAt must be a parseable timestamp");
  if (approvedAt !== undefined && preflightCompletedAt !== undefined && preflightCompletedAt < approvedAt) {
    errors.push("preflight.completedAt must be at or after runAuthorization.approvedAt");
  }
  if (preflightCompletedAt !== undefined && executionStartedAt !== undefined && executionStartedAt < preflightCompletedAt) {
    errors.push("execution.startedAt must be at or after preflight.completedAt");
  }
  if (executionStartedAt !== undefined && executionCompletedAt !== undefined && executionCompletedAt < executionStartedAt) {
    errors.push("execution.completedAt must be at or after execution.startedAt");
  }
  if (executionCompletedAt !== undefined && reviewedAt !== undefined && reviewedAt < executionCompletedAt) {
    errors.push("reviewer.reviewedAt must be at or after execution.completedAt");
  }
  return errors;
}

function mutateTemplate(packet, mutation) {
  const mutated = JSON.parse(JSON.stringify(packet));
  switch (mutation) {
    case "execution.completedAt before execution.startedAt":
      mutated.execution.completedAt = "2026-05-19T23:59:59Z";
      break;
    case "preflight.completedAt before runAuthorization.approvedAt":
      mutated.preflight.completedAt = "2026-05-19T23:59:59Z";
      break;
    case "runAuthorization.grants is empty":
      mutated.runAuthorization.grants = [];
      break;
    case "reviewer.reviewedAt before execution.completedAt":
      mutated.reviewer.reviewedAt = "2026-05-19T23:59:59Z";
      break;
    case "evidence.appMenuEvidenceRefs=privatePath":
      mutated.evidence.appMenuEvidenceRefs = ["file://private/menu-evidence-template.png"];
      break;
    default:
      fail(`unknown evidence fixture mutation ${mutation}`);
  }
  return mutated;
}

function validatePacket(packet, label) {
  const compiled = compileSchema();
  const errors = evidencePacketErrors(packet, compiled);
  if (errors.length > 0) {
    fail(`${label}: packet does not conform to system telemetry external evidence requirements`, errors.join("; "));
  }
  return { laneId: packet.laneId, repoScope: packet.repoScope };
}

function validateFixtures() {
  const fixtures = readJson(fixturesPath);
  if (fixtures.status !== "synthetic_templates_not_evidence") {
    fail("fixtures must remain synthetic templates only");
  }
  const compiled = compileSchema();
  const validSyntheticPackets = fixtures.validSyntheticPackets ?? [];
  const invalidSyntheticPackets = fixtures.invalidSyntheticPackets ?? [];
  const validByLaneId = new Map();
  const accepted = [];
  for (const packet of validSyntheticPackets) {
    const errors = evidencePacketErrors(packet, compiled);
    if (errors.length > 0) {
      fail(`valid fixture ${packet.laneId} did not validate`, errors.join("; "));
    }
    validByLaneId.set(packet.laneId, packet);
    accepted.push(packet.laneId);
  }
  for (const fixture of invalidSyntheticPackets) {
    const packet = fixture.packet ?? mutateTemplate(validByLaneId.get(fixture.baseLaneId), fixture.mutation);
    if (!packet) {
      fail(`invalid fixture ${fixture.id} references unknown lane ${fixture.baseLaneId}`);
    }
    if (evidencePacketErrors(packet, compiled).length === 0) {
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
