#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const rawArgs = process.argv.slice(2);
const args = new Set(rawArgs);
const isSelfTest = process.env.CLAWIX_UI_CANON_PROMOTION_SELF_TEST === "1";
const errors = [];
const simulationFlags = [
  "--simulate-wrong-private-approval-alias",
  "--simulate-missing-approved-status",
  "--simulate-missing-required-promotion-field",
  "--simulate-invalid-promotion-status",
  "--simulate-unsupported-platform",
  "--simulate-approved-by-agent",
  "--simulate-invalid-approved-at",
  "--simulate-local-private-reference",
  "--simulate-invalid-baseline-hash",
  "--simulate-missing-adoption-canonicity-packet",
  "--simulate-approved-without-protected-surface",
  "--simulate-approved-without-adoption-canonicity-packet",
  "--simulate-approved-protected-hash-mismatch",
  "--simulate-approved-platform-mismatch",
  "--simulate-duplicate-promotion-id",
];
const allowedFlags = new Set(simulationFlags);

function fail(message) {
  errors.push(message);
}

for (const arg of rawArgs) {
  if (arg.startsWith("--") && !allowedFlags.has(arg)) {
    console.error(`UI canon promotion check received unknown flag ${arg}.`);
    process.exit(1);
  }
}

function readJson(relativePath) {
  const file = path.join(rootDir, relativePath);
  if (!fs.existsSync(file)) {
    fail(`missing ${relativePath}`);
    return null;
  }
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (error) {
    fail(`${relativePath} is not valid JSON: ${error.message}`);
    return null;
  }
}

function requireFields(object, label, fields) {
  if (!object) return;
  for (const field of fields) {
    if (object[field] === undefined || object[field] === null || object[field] === "") {
      fail(`${label} is missing ${field}`);
    }
  }
}

function requireArray(object, label, field, { nonEmpty = true } = {}) {
  const value = object?.[field];
  if (!Array.isArray(value)) {
    fail(`${label}.${field} must be an array`);
    return [];
  }
  if (nonEmpty && value.length === 0) {
    fail(`${label}.${field} must not be empty`);
  }
  return value;
}

function hasLocalPath(value) {
  return (
    typeof value === "string" &&
    (/^\/Users\//.test(value) || value.startsWith("~/") || value.startsWith("file://") || /^[A-Z]:\\/.test(value))
  );
}

function scanForLocalPaths(value, label) {
  if (Array.isArray(value)) {
    value.forEach((child, index) => scanForLocalPaths(child, `${label}[${index}]`));
    return;
  }
  if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) scanForLocalPaths(child, `${label}.${key}`);
    return;
  }
  if (hasLocalPath(value)) fail(`${label} must not contain a local path`);
}

function requireAlias(value, alias, label) {
  if (typeof value !== "string" || !value.startsWith(`${alias}:`)) {
    fail(`${label} must use ${alias}:`);
    return;
  }
  const suffix = value.slice(alias.length + 1);
  if (!suffix || suffix.startsWith("/") || suffix.startsWith("\\") || suffix.startsWith("~/") || suffix.includes("..") || /^[A-Z]:\\/.test(suffix)) {
    fail(`${label} must use a safe relative private reference`);
  }
  if (hasLocalPath(value)) {
    fail(`${label} must not contain a local path`);
  }
}

function requireHash(value, label) {
  if (typeof value !== "string" || !/^[a-f0-9]{64}$/i.test(value)) {
    fail(`${label} must be a 64-character hex hash`);
  }
}

function requireIsoDate(value, label) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value) || Number.isNaN(Date.parse(value))) {
    fail(`${label} must be an ISO date`);
  }
}

function runFailureSelfTests() {
  const selfTestEnv = {
    ...process.env,
    CLAWIX_UI_CANON_PROMOTION_SELF_TEST: "1",
  };
  const tests = [
    [["--unknown-flag"], "received unknown flag --unknown-flag"],
    [["--simulate-wrong-private-approval-alias"], "privateApprovalAlias must be private-codex-ui-approval"],
    [["--simulate-missing-approved-status"], "promotionStatuses must include approved"],
    [["--simulate-missing-required-promotion-field"], "requiredPromotionFields must include geometryEvidenceHash"],
    [["--simulate-invalid-promotion-status"], "status is invalid"],
    [["--simulate-approved-by-agent"], "approvedBy must be user"],
    [["--simulate-local-private-reference"], "privateBaselineReference must use private-codex-ui-baselines:"],
    [["--simulate-invalid-baseline-hash"], "privateBaselineHash must be a 64-character hex hash"],
    [["--simulate-missing-adoption-canonicity-packet"], "requiredPromotionFields must include adoptionCanonicityPacketId"],
    [["--simulate-approved-without-protected-surface"], "protectedSurfaceId must reference an approved protected surface"],
    [["--simulate-approved-without-adoption-canonicity-packet"], "adoptionCanonicityPacketId must reference an adoption/canonicity packet"],
    [["--simulate-approved-protected-hash-mismatch"], "privateBaselineHash must match protected surface simulated-protected-surface"],
    [["--simulate-approved-platform-mismatch"], "platform must match protected surface simulated-protected-surface"],
    [["--simulate-duplicate-promotion-id"], "id duplicates another promotion"],
  ];

  for (const [testArgs, expectedOutput] of tests) {
    const result = spawnSync(process.execPath, [new URL(import.meta.url).pathname, ...testArgs], {
      cwd: rootDir,
      env: selfTestEnv,
      encoding: "utf8",
    });
    const output = `${result.stdout || ""}${result.stderr || ""}`;
    if (result.status === 0) {
      fail(`self-test ${testArgs.join(" ")} must fail for UI canon promotion validation`);
      continue;
    }
    if (!output.includes(expectedOutput)) {
      fail(`self-test ${testArgs.join(" ")} output must include ${expectedOutput}`);
    }
  }
}

if (!isSelfTest) {
  runFailureSelfTests();
}

const requiredPlatforms = new Set(["macos", "ios", "android", "web"]);
const manifestPath = "docs/ui/canon-promotions.registry.json";
const manifest = readJson(manifestPath);
if (manifest && args.has("--simulate-wrong-private-approval-alias")) {
  manifest.privateApprovalAlias = "private-codex-ui-baselines";
}
if (manifest && args.has("--simulate-missing-approved-status")) {
  manifest.promotionStatuses = manifest.promotionStatuses.filter((status) => status !== "approved");
}
if (manifest && args.has("--simulate-missing-required-promotion-field")) {
  manifest.requiredPromotionFields = manifest.requiredPromotionFields.filter((field) => field !== "geometryEvidenceHash");
}
if (manifest && args.has("--simulate-missing-adoption-canonicity-packet")) {
  manifest.requiredPromotionFields = manifest.requiredPromotionFields.filter((field) => field !== "adoptionCanonicityPacketId");
}
requireFields(manifest, manifestPath, [
  "schemaVersion",
  "status",
  "policy",
  "privateApprovalAlias",
  "privateBaselineAlias",
  "privateCopyAlias",
  "privateGeometryAlias",
  "promotionStatuses",
  "requiredPromotionFields",
  "promotions",
]);

for (const [field, expected] of [
  ["privateApprovalAlias", "private-codex-ui-approval"],
  ["privateBaselineAlias", "private-codex-ui-baselines"],
  ["privateCopyAlias", "private-codex-ui-copy-snapshots"],
  ["privateGeometryAlias", "private-codex-ui-rendered-geometry"],
]) {
  if (manifest?.[field] !== expected) fail(`${manifestPath}.${field} must be ${expected}`);
}

const statuses = new Set(requireArray(manifest, manifestPath, "promotionStatuses"));
for (const status of ["approved", "revoked", "superseded"]) {
  if (!statuses.has(status)) fail(`${manifestPath}.promotionStatuses must include ${status}`);
}

const requiredPromotionFields = requireArray(manifest, manifestPath, "requiredPromotionFields");
const requiredPromotionFieldSet = new Set(requiredPromotionFields);
for (const field of [
  "id",
  "status",
  "surfaceId",
  "platform",
  "patterns",
  "approvedBy",
  "approvedAt",
  "privateApprovalReference",
  "privateBaselineReference",
  "privateBaselineHash",
  "copySnapshotReference",
  "copySnapshotHash",
  "geometryEvidenceReference",
  "geometryEvidenceHash",
  "protectedSurfaceId",
  "adoptionCanonicityPacketId",
]) {
  if (!requiredPromotionFieldSet.has(field)) fail(`${manifestPath}.requiredPromotionFields must include ${field}`);
}

const protectedPath = "docs/ui/protected-surfaces.registry.json";
const protectedSurfaces = readJson(protectedPath);
const simulatedHash = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
const simulatedOtherHash = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789";
const simulatedProtectedSurface = {
  id: "simulated-protected-surface",
  scope: "simulated sidebar surface",
  platform: args.has("--simulate-approved-platform-mismatch") ? "ios" : "macos",
  patterns: ["sidebar-row"],
  approvedBy: "user",
  approvedAt: "2026-05-15",
  privateApprovalReference: "private-codex-ui-approval:records/simulated/approval-evidence.json",
  contract: "docs/ui/protected-surfaces.registry.json#simulated-protected-surface",
  privateBaselineReference: "private-codex-ui-baselines:surfaces/simulated/baseline.png",
  privateBaselineHash: args.has("--simulate-approved-protected-hash-mismatch") ? simulatedOtherHash : simulatedHash,
  copySnapshotReference: "private-codex-ui-copy-snapshots:surfaces/simulated/copy.json",
  copySnapshotHash: simulatedHash,
  geometryEvidenceReference: "private-codex-ui-rendered-geometry:surfaces/simulated/geometry.json",
  geometryEvidenceHash: simulatedHash,
  changePolicy: "explicit-user-approval-required",
};
const simulatedPromotion = {
  id: "simulated-canon-promotion",
  status: "approved",
  surfaceId: "simulated-sidebar-surface",
  platform: "macos",
  patterns: ["sidebar-row"],
  approvedBy: "user",
  approvedAt: "2026-05-15",
  privateApprovalReference: "private-codex-ui-approval:records/simulated/approval-evidence.json",
  privateBaselineReference: "private-codex-ui-baselines:surfaces/simulated/baseline.png",
  privateBaselineHash: simulatedHash,
  copySnapshotReference: "private-codex-ui-copy-snapshots:surfaces/simulated/copy.json",
  copySnapshotHash: simulatedHash,
  geometryEvidenceReference: "private-codex-ui-rendered-geometry:surfaces/simulated/geometry.json",
  geometryEvidenceHash: simulatedHash,
  protectedSurfaceId: "simulated-protected-surface",
  adoptionCanonicityPacketId: "simulated-ui-canon-promotion-packet",
};
if (manifest && args.has("--simulate-invalid-promotion-status")) {
  manifest.promotions = [{ ...simulatedPromotion, status: "pending" }];
}
if (manifest && args.has("--simulate-unsupported-platform")) {
  manifest.promotions = [{ ...simulatedPromotion, status: "revoked", platform: "visionos" }];
}
if (manifest && args.has("--simulate-approved-by-agent")) {
  manifest.promotions = [{ ...simulatedPromotion, status: "revoked", approvedBy: "agent" }];
}
if (manifest && args.has("--simulate-invalid-approved-at")) {
  manifest.promotions = [{ ...simulatedPromotion, status: "revoked", approvedAt: "2026/05/15" }];
}
if (manifest && args.has("--simulate-local-private-reference")) {
  manifest.promotions = [{ ...simulatedPromotion, status: "revoked", privateBaselineReference: "/Users/example/baseline.png" }];
}
if (manifest && args.has("--simulate-invalid-baseline-hash")) {
  manifest.promotions = [{ ...simulatedPromotion, status: "revoked", privateBaselineHash: "short" }];
}
if (manifest && args.has("--simulate-approved-without-protected-surface")) {
  manifest.promotions = [simulatedPromotion];
}
if (manifest && args.has("--simulate-approved-without-adoption-canonicity-packet")) {
  manifest.promotions = [simulatedPromotion];
  protectedSurfaces.surfaces = [simulatedProtectedSurface];
}
if (manifest && args.has("--simulate-approved-protected-hash-mismatch")) {
  manifest.promotions = [simulatedPromotion];
  protectedSurfaces.surfaces = [simulatedProtectedSurface];
}
if (manifest && args.has("--simulate-approved-platform-mismatch")) {
  manifest.promotions = [simulatedPromotion];
  protectedSurfaces.surfaces = [simulatedProtectedSurface];
}
if (manifest && args.has("--simulate-duplicate-promotion-id")) {
  manifest.promotions = [
    { ...simulatedPromotion, status: "revoked" },
    { ...simulatedPromotion, status: "superseded" },
  ];
}
const protectedSurfaceById = new Map(
  requireArray(protectedSurfaces, protectedPath, "surfaces", { nonEmpty: false }).map((surface) => [surface.id, surface]),
);
const adoptionCanonicityPath = "docs/governance/adoption-canonicity.manifest.json";
const adoptionCanonicityManifest = readJson(adoptionCanonicityPath);
const simulatedAdoptionPacket = {
  id: "simulated-ui-canon-promotion-packet",
  targetType: "ui_promotion",
  targetId: "simulated-canon-promotion",
  claimType: "ui_canon_promotion",
  stage: "understandable",
  targetAudience: "simulated",
  evidenceRefs: [{ kind: "public_test", ref: "scripts/ui_canon_promotion_check.mjs", summary: "simulated" }],
  feedbackLoop: { mechanism: "simulated", cadence: "per_promotion_review", evidenceRefs: ["scripts/ui_canon_promotion_check.mjs"] },
  privacyMode: "hybrid_private",
  telemetryDefault: "disabled",
  promotionDecision: { state: "approved", decidedBy: "user", decidedAt: "2026-05-15", refs: ["scripts/ui_canon_promotion_check.mjs"] },
  reviewCadence: "per_promotion_review",
  reviewedAt: "2026-05-15",
  expiresAt: "2026-08-15",
};
if (adoptionCanonicityManifest && !args.has("--simulate-approved-without-adoption-canonicity-packet")) {
  adoptionCanonicityManifest.packets = [...(adoptionCanonicityManifest.packets ?? []), simulatedAdoptionPacket];
}
const adoptionPacketIds = new Set(
  requireArray(adoptionCanonicityManifest, adoptionCanonicityPath, "packets", { nonEmpty: false }).map((packet) => packet.id),
);

const promotions = requireArray(manifest, manifestPath, "promotions", { nonEmpty: false });
const promotionIds = new Set();
for (const [index, promotion] of promotions.entries()) {
  const label = `${manifestPath}.promotions[${index}]`;
  requireFields(promotion, label, requiredPromotionFields);
  if (promotion.id) {
    if (promotionIds.has(promotion.id)) fail(`${label}.id duplicates another promotion`);
    promotionIds.add(promotion.id);
  }
  if (!statuses.has(promotion.status)) fail(`${label}.status is invalid`);
  if (!requiredPlatforms.has(promotion.platform)) fail(`${label}.platform is not governed`);
  if (promotion.approvedBy !== "user") fail(`${label}.approvedBy must be user`);
  requireIsoDate(promotion.approvedAt, `${label}.approvedAt`);
  requireArray(promotion, label, "patterns");
  requireAlias(promotion.privateApprovalReference, manifest.privateApprovalAlias, `${label}.privateApprovalReference`);
  requireAlias(promotion.privateBaselineReference, manifest.privateBaselineAlias, `${label}.privateBaselineReference`);
  requireAlias(promotion.copySnapshotReference, manifest.privateCopyAlias, `${label}.copySnapshotReference`);
  requireAlias(promotion.geometryEvidenceReference, manifest.privateGeometryAlias, `${label}.geometryEvidenceReference`);
  requireHash(promotion.privateBaselineHash, `${label}.privateBaselineHash`);
  requireHash(promotion.copySnapshotHash, `${label}.copySnapshotHash`);
  requireHash(promotion.geometryEvidenceHash, `${label}.geometryEvidenceHash`);
  if (promotion.status === "approved") {
    const protectedSurface = protectedSurfaceById.get(promotion.protectedSurfaceId);
    if (!protectedSurface) {
      fail(`${label}.protectedSurfaceId must reference an approved protected surface`);
      continue;
    }
    for (const field of [
      "privateBaselineReference",
      "privateBaselineHash",
      "copySnapshotReference",
      "copySnapshotHash",
      "geometryEvidenceReference",
      "geometryEvidenceHash",
    ]) {
      if (promotion[field] !== protectedSurface[field]) {
        fail(`${label}.${field} must match protected surface ${promotion.protectedSurfaceId}`);
      }
    }
    if (promotion.platform !== protectedSurface.platform) {
      fail(`${label}.platform must match protected surface ${promotion.protectedSurfaceId}`);
    }
  }
  if (!adoptionPacketIds.has(promotion.adoptionCanonicityPacketId)) {
    fail(`${label}.adoptionCanonicityPacketId must reference an adoption/canonicity packet`);
  }
}

scanForLocalPaths(manifest, manifestPath);

if (errors.length > 0) {
  console.error("UI canon promotion check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI canon promotion check passed (${promotions.length} promotion records)`);
