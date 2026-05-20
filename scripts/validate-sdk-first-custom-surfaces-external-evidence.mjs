#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const args = process.argv.slice(2);
const requiredFlows = [
  "installed_app_launch",
  "sidebar_hover_click_expand",
  "chat_scroll",
  "composer_typing",
  "route_switching",
  "web_custom_surface_load",
  "swift_custom_surface_load",
  "rescue_reachability",
];
const expectedRows = {
  "CLX-SDK-EXT-001": ["CLX-SDK-004", "CLJ-SDK-005"],
  "CLX-SDK-EXT-002": ["CLX-SDK-004", "CLJ-SDK-005"],
  "CLX-SDK-EXT-003": ["CLX-SDK-008", "CLJ-SDK-008"],
  "CLX-SDK-EXT-004": ["CLX-SDK-005"],
};
const expectedExecutors = {
  "CLX-SDK-EXT-001": "signed_host_native",
  "CLX-SDK-EXT-002": "live_iot_provider",
  "CLX-SDK-EXT-003": "performance_baseline_review",
  "CLX-SDK-EXT-004": "marketplace_trust_review",
};

function readJson(relativePath) {
  return JSON.parse(fs.readFileSync(path.join(rootDir, relativePath), "utf8"));
}

function fail(message) {
  throw new Error(message);
}

function asArray(value, label) {
  if (!Array.isArray(value)) fail(`${label} must be an array`);
  return value;
}

function requireString(value, label) {
  if (typeof value !== "string" || value.length === 0) fail(`${label} must be a non-empty string`);
}

function requireFalse(value, label) {
  if (value !== false) fail(`${label} must be false`);
}

function requireTrue(value, label) {
  if (value !== true) fail(`${label} must be true`);
}

function includesAll(actual, expected, label) {
  const missing = expected.filter((item) => !actual.includes(item));
  if (missing.length > 0) fail(`${label} is missing ${missing.join(", ")}`);
}

function requireExactSet(actual, expected, label) {
  includesAll(actual, expected, label);
  const unexpected = actual.filter((item) => !expected.includes(item));
  if (unexpected.length > 0) fail(`${label} has unexpected entries ${unexpected.join(", ")}`);
  if (new Set(actual).size !== actual.length) fail(`${label} must not contain duplicates`);
}

function mergePatch(base, patch) {
  if (!patch || typeof patch !== "object" || Array.isArray(patch)) return patch;
  const next = { ...base };
  for (const [key, value] of Object.entries(patch)) {
    next[key] = value && typeof value === "object" && !Array.isArray(value)
      ? mergePatch(base?.[key] ?? {}, value)
      : value;
  }
  return next;
}

export function validatePacket(packet) {
  if (!packet || typeof packet !== "object" || Array.isArray(packet)) fail("packet must be an object");
  if (packet.schemaVersion !== 1) fail("schemaVersion must be 1");
  if (packet.conversationId !== "019e403c-3837-7f02-9b78-532c43cdd997") fail("conversationId mismatch");
  if (packet.goal !== "sdk-first-custom-surfaces") fail("goal mismatch");
  if (packet.status !== "accepted_external_evidence") fail("status must be accepted_external_evidence");
  if (!expectedRows[packet.laneId]) fail("laneId is not a known SDK-first external lane");

  requireString(packet.runAuthorization?.approvalId, "runAuthorization.approvalId");
  requireString(packet.runAuthorization?.approvedBy, "runAuthorization.approvedBy");
  requireString(packet.runAuthorization?.approvedAt, "runAuthorization.approvedAt");
  requireString(packet.runAuthorization?.expiresAt, "runAuthorization.expiresAt");
  requireString(packet.runAuthorization?.exactRunScope, "runAuthorization.exactRunScope");
  requireExactSet(asArray(packet.runAuthorization?.approvedLaneIds, "runAuthorization.approvedLaneIds"), [packet.laneId], "runAuthorization.approvedLaneIds");

  requireTrue(packet.preflight?.failClosedBeforeApproval, "preflight.failClosedBeforeApproval");
  if (asArray(packet.preflight?.checks, "preflight.checks").length < 1) fail("preflight.checks must not be empty");
  if (asArray(packet.preflight?.resultRefs, "preflight.resultRefs").length < 1) fail("preflight.resultRefs must not be empty");

  if (packet.execution?.executor !== expectedExecutors[packet.laneId]) fail(`execution.executor must be ${expectedExecutors[packet.laneId]}`);
  if (asArray(packet.execution?.receiptRefs, "execution.receiptRefs").length < 1) fail("execution.receiptRefs must not be empty");
  requireFalse(packet.execution?.failedApprovedRun, "execution.failedApprovedRun");

  const evidence = packet.evidence ?? {};
  if (asArray(evidence.auditRefs, "evidence.auditRefs").length < 1) fail("evidence.auditRefs must not be empty");
  for (const field of ["sameMachineEvidenceRefs", "nativeGrantRefs", "providerOrDeviceRefs", "performanceBaselineRefs", "marketplaceTrustRefs", "approvedCriticalFlows", "rollbackOrContinuityRefs"]) {
    asArray(evidence[field], `evidence.${field}`);
  }
  if (evidence.sameMachineEvidenceRefs.length < 1) fail("evidence.sameMachineEvidenceRefs must not be empty");

  for (const field of ["containsSecrets", "containsRawCredentials", "containsPrivatePaths", "containsRawTrace", "containsPreciseLocation", "containsDeviceIdentifiers"]) {
    requireFalse(packet.redaction?.[field], `redaction.${field}`);
  }

  requireExactSet(asArray(packet.closureImpact?.publicRows, "closureImpact.publicRows"), expectedRows[packet.laneId], "closureImpact.publicRows");
  if (asArray(packet.closureImpact?.docsToUpdate, "closureImpact.docsToUpdate").length < 1) fail("closureImpact.docsToUpdate must not be empty");
  if (asArray(packet.closureImpact?.verifiersToRerun, "closureImpact.verifiersToRerun").length < 1) fail("closureImpact.verifiersToRerun must not be empty");
  requireTrue(packet.closureImpact?.requiresFinalSourceReread, "closureImpact.requiresFinalSourceReread");
  requireTrue(packet.closureImpact?.requiresUserReviewDecision, "closureImpact.requiresUserReviewDecision");
  if (packet.reviewer?.decision !== "accepted") fail("reviewer.decision must be accepted");

  if (packet.laneId === "CLX-SDK-EXT-001" && evidence.nativeGrantRefs.length < 1) fail("CLX-SDK-EXT-001 requires nativeGrantRefs");
  if (packet.laneId === "CLX-SDK-EXT-002") {
    if (evidence.providerOrDeviceRefs.length < 1) fail("CLX-SDK-EXT-002 requires providerOrDeviceRefs");
    if (evidence.rollbackOrContinuityRefs.length < 1) fail("CLX-SDK-EXT-002 requires rollbackOrContinuityRefs");
  }
  if (packet.laneId === "CLX-SDK-EXT-003") {
    if (evidence.performanceBaselineRefs.length < 1) fail("CLX-SDK-EXT-003 requires performanceBaselineRefs");
    includesAll(evidence.approvedCriticalFlows, requiredFlows, "evidence.approvedCriticalFlows");
  }
  if (packet.laneId === "CLX-SDK-EXT-004") {
    if (evidence.marketplaceTrustRefs.length < 2) fail("CLX-SDK-EXT-004 requires signature/provenance and ficha receipts");
  }
}

function runSelfTest() {
  const fixtures = readJson("docs/governance/sdk-first-custom-surfaces/external-evidence.fixtures.json");
  for (const packet of fixtures.validSyntheticPackets ?? []) validatePacket(packet);
  for (const fixture of fixtures.invalidSyntheticPackets ?? []) {
    const base = fixtures.validSyntheticPackets.find((packet) => packet.laneId === fixture.patch?.laneId);
    if (!base) fail(`invalid fixture ${fixture.name} references an unknown lane`);
    let rejected = false;
    try {
      validatePacket(mergePatch(base, fixture.patch));
    } catch {
      rejected = true;
    }
    if (!rejected) fail(`invalid fixture was accepted: ${fixture.name}`);
  }
}

if (args.includes("--self-test")) {
  runSelfTest();
  console.log("SDK-first custom surfaces external evidence validator self-test passed");
} else {
  const packetPath = args[0];
  if (!packetPath) {
    console.error("usage: validate-sdk-first-custom-surfaces-external-evidence.mjs <packet.json>");
    process.exit(2);
  }
  try {
    validatePacket(JSON.parse(fs.readFileSync(path.resolve(packetPath), "utf8")));
    console.log("SDK-first custom surfaces external evidence packet accepted");
  } catch (error) {
    console.error(`SDK-first custom surfaces external evidence packet rejected: ${error.message}`);
    process.exit(1);
  }
}
