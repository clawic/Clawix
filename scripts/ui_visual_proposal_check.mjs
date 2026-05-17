#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const rootDir = path.resolve(new URL("..", import.meta.url).pathname);
const today = new Date().toISOString().slice(0, 10);
const args = new Set(process.argv.slice(2));
const errors = [];

function fail(message) {
  errors.push(message);
}

function readText(relativePath) {
  const file = path.join(rootDir, relativePath);
  if (!fs.existsSync(file)) {
    fail(`missing ${relativePath}`);
    return "";
  }
  return fs.readFileSync(file, "utf8");
}

function readJson(relativePath) {
  const text = readText(relativePath);
  if (!text) return null;
  try {
    return JSON.parse(text);
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
  if (nonEmpty && value.length === 0) fail(`${label}.${field} must not be empty`);
  return value;
}

function requireExactStringSet(values, label, expectedValues) {
  const expected = new Set(expectedValues);
  const seen = new Set();
  for (const value of values) {
    if (typeof value !== "string" || value.length === 0) {
      fail(`${label} must only include non-empty strings`);
      continue;
    }
    if (seen.has(value)) fail(`${label} duplicates ${value}`);
    seen.add(value);
    if (!expected.has(value)) fail(`${label} must not include ${value}`);
  }
  for (const value of expected) {
    if (!seen.has(value)) fail(`${label} must include ${value}`);
  }
  if (seen.size !== expected.size) fail(`${label} must exactly match approved values`);
  return seen;
}

function requireStringSet(values, label, { nonEmpty = true } = {}) {
  const seen = new Set();
  if (nonEmpty && values.length === 0) fail(`${label} must not be empty`);
  for (const value of values) {
    if (typeof value !== "string" || value.length === 0) {
      fail(`${label} must only include non-empty strings`);
      continue;
    }
    if (seen.has(value)) fail(`${label} duplicates ${value}`);
    seen.add(value);
    if (hasLocalPath(value) || value.includes("/Users/") || value.startsWith("/") || value.startsWith("~/") || value.startsWith("file://") || value.includes("..") || value.includes("\\")) {
      fail(`${label} must only include safe public identifiers`);
    }
  }
  return seen;
}

function hasLocalPath(value) {
  return typeof value === "string" && (/^\/Users\//.test(value) || value.startsWith("~/") || value.startsWith("file://") || /^[A-Z]:\\/.test(value));
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

function requireSafePrivateReference(value, alias, label) {
  if (typeof value !== "string" || !value.startsWith(`${alias}:`)) {
    fail(`${label} must use ${alias}:`);
    return null;
  }
  const suffix = value.slice(alias.length + 1);
  if (!suffix || suffix.startsWith("/") || suffix.startsWith("\\") || suffix.startsWith("~/") || suffix.includes("..") || /^[A-Z]:\\/.test(suffix)) {
    fail(`${label} must use a safe relative private reference`);
    return null;
  }
  if (hasLocalPath(value) || value.includes("/Users/")) {
    fail(`${label} must not contain a local path`);
    return null;
  }
  return suffix;
}

function requireIsoDate(value, label) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    fail(`${label} must be an ISO yyyy-mm-dd date`);
    return null;
  }
  const parsed = new Date(`${value}T00:00:00Z`);
  if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== value) {
    fail(`${label} must be a valid calendar date`);
    return null;
  }
  return value;
}

function requirePublicReference(value, label) {
  if (typeof value !== "string" || value === "" || value.startsWith("/") || value.startsWith("~/") || value.includes("\\") || value.includes("..") || value.startsWith("file://") || /^[A-Z]:\\/.test(value)) {
    fail(`${label} must be a safe public repo-relative reference`);
    return;
  }
  const target = value.split("#", 1)[0];
  if (!fs.existsSync(path.join(rootDir, target))) {
    fail(`${label} points to missing target ${target}`);
  }
}

const registryPath = "docs/ui/visual-proposals.registry.json";
const registry = readJson(registryPath);
if (registry) {
  if (args.has("--simulate-inactive-visual-proposals")) {
    registry.status = "pending";
  }
  if (args.has("--simulate-extra-proposal-status") && Array.isArray(registry.proposalStatuses)) {
    registry.proposalStatuses.push("implemented");
  }
  if (args.has("--simulate-duplicate-proposal-status") && Array.isArray(registry.proposalStatuses) && registry.proposalStatuses[0]) {
    registry.proposalStatuses.push(registry.proposalStatuses[0]);
  }
  if (args.has("--simulate-extra-approval-required-status") && Array.isArray(registry.approvalRequiredForStatuses)) {
    registry.approvalRequiredForStatuses.push("conceptual-only");
  }
  if (args.has("--simulate-duplicate-approval-required-status") && Array.isArray(registry.approvalRequiredForStatuses) && registry.approvalRequiredForStatuses[0]) {
    registry.approvalRequiredForStatuses.push(registry.approvalRequiredForStatuses[0]);
  }
  if (args.has("--simulate-extra-allowed-required-evidence") && Array.isArray(registry.allowedRequiredEvidence)) {
    registry.allowedRequiredEvidence.push("local-screenshot");
  }
  if (args.has("--simulate-duplicate-allowed-required-evidence") && Array.isArray(registry.allowedRequiredEvidence) && registry.allowedRequiredEvidence[0]) {
    registry.allowedRequiredEvidence.push(registry.allowedRequiredEvidence[0]);
  }
  if (args.has("--simulate-extra-required-proposal-field") && Array.isArray(registry.requiredProposalFields)) {
    registry.requiredProposalFields.push("localDraftPath");
  }
  if (args.has("--simulate-duplicate-required-proposal-field") && Array.isArray(registry.requiredProposalFields) && registry.requiredProposalFields[0]) {
    registry.requiredProposalFields.push(registry.requiredProposalFields[0]);
  }
}
if (
  registry &&
  (args.has("--simulate-conceptual-implemented") ||
    args.has("--simulate-approved-without-private-reference") ||
    args.has("--simulate-approved-mismatched-private-reference") ||
    args.has("--simulate-unknown-required-evidence") ||
    args.has("--simulate-duplicate-proposal-change-kind") ||
    args.has("--simulate-duplicate-proposal-platform") ||
    args.has("--simulate-duplicate-proposal-evidence") ||
    args.has("--simulate-unsafe-proposal-surface"))
) {
  const simulatedProposal = {
    id: "simulated-proposal",
    status: args.has("--simulate-approved-without-private-reference")
      ? "user-approved-for-visual-lane"
      : "conceptual-only",
    requestedBy: "non-visual-lane",
    mutationClass: "visual-ui",
    changeKinds: ["color"],
    surfaces: ["simulated-surface"],
    platforms: ["macos"],
    proposalReference: "docs/ui/visual-change-proposal.template.md",
    requiredEvidence: args.has("--simulate-unknown-required-evidence")
      ? ["private-baseline", "invented-evidence"]
      : ["private-baseline", "rendered-geometry"],
    outOfScopeDrift: [],
    userApprovalStatus: args.has("--simulate-approved-without-private-reference") ? "approved" : "not-approved",
    implementationStatus: args.has("--simulate-conceptual-implemented") ? "implemented" : "not-approved",
    reviewAfter: "2999-12-31",
  };
  if (args.has("--simulate-approved-without-private-reference")) {
    simulatedProposal.approvedBy = "user";
    simulatedProposal.approvedAt = "2026-05-15";
  }
  if (args.has("--simulate-approved-mismatched-private-reference")) {
    simulatedProposal.status = "user-approved-for-visual-lane";
    simulatedProposal.userApprovalStatus = "approved";
    simulatedProposal.approvedBy = "user";
    simulatedProposal.approvedAt = "2026-05-15";
    simulatedProposal.privateApprovalReference = `${registry.privateApprovalAlias}:visual-proposals/wrong-proposal`;
  }
  if (args.has("--simulate-duplicate-proposal-change-kind")) {
    simulatedProposal.changeKinds.push(simulatedProposal.changeKinds[0]);
  }
  if (args.has("--simulate-duplicate-proposal-platform")) {
    simulatedProposal.platforms.push(simulatedProposal.platforms[0]);
  }
  if (args.has("--simulate-duplicate-proposal-evidence")) {
    simulatedProposal.requiredEvidence.push(simulatedProposal.requiredEvidence[0]);
  }
  if (args.has("--simulate-unsafe-proposal-surface")) {
    simulatedProposal.surfaces.push("../local-surface");
  }
  registry.proposals = [...(registry.proposals || []), simulatedProposal];
}
requireFields(registry, registryPath, [
  "schemaVersion",
  "status",
  "policy",
  "templatePath",
  "privateApprovalAlias",
  "approvalRequiredForStatuses",
  "proposalStatuses",
  "allowedRequiredEvidence",
  "requiredProposalFields",
  "proposals",
]);
if (registry?.status !== "active") fail(`${registryPath}.status must be active`);
if (registry?.templatePath !== "docs/ui/visual-change-proposal.template.md") {
  fail(`${registryPath}.templatePath must point to docs/ui/visual-change-proposal.template.md`);
}

let template = readText(registry?.templatePath || "docs/ui/visual-change-proposal.template.md");
if (args.has("--simulate-template-allows-visible-edit")) {
  template = template.replace("Do not edit visible source code from this lane.", "");
}
for (const snippet of [
  "Status: conceptual-only",
  "A proposal does not approve implementation",
  "Do not edit visible source code from this lane.",
  "User approval needed before implementation",
  "## Required Evidence",
  "Drift found but not fixed",
]) {
  if (!template.includes(snippet)) fail(`${registry?.templatePath} is missing required snippet: ${snippet}`);
}

const approvalAuthority = readJson("docs/ui/approval-authority.manifest.json");
if (registry?.privateApprovalAlias !== approvalAuthority?.privateApprovalAlias) {
  fail(`${registryPath}.privateApprovalAlias must match docs/ui/approval-authority.manifest.json.privateApprovalAlias`);
}

const configPath = "docs/ui/interface-governance.config.json";
const config = readJson(configPath);
const allowedMutationClasses = new Set(requireArray(config, configPath, "mutationClasses"));
const allowedChangeKinds = new Set(requireArray(config, configPath, "restrictedChangeKinds"));
const allowedPlatforms = new Set(requireArray(config, configPath, "platforms"));
const proposalStatuses = ["conceptual-only", "user-approved-for-visual-lane", "rejected", "expired"];
const allowedStatuses = requireExactStringSet(
  requireArray(registry, registryPath, "proposalStatuses"),
  `${registryPath}.proposalStatuses`,
  proposalStatuses,
);
const approvalRequiredStatuses = requireExactStringSet(
  requireArray(registry, registryPath, "approvalRequiredForStatuses"),
  `${registryPath}.approvalRequiredForStatuses`,
  ["user-approved-for-visual-lane"],
);
const requiredEvidenceValues = [
  "private-baseline",
  "rendered-geometry",
  "copy-snapshot",
  "rendered-drift",
  "debt-audit",
  "performance-budget",
  "private-approval",
];
const allowedRequiredEvidence = requireExactStringSet(
  requireArray(registry, registryPath, "allowedRequiredEvidence"),
  `${registryPath}.allowedRequiredEvidence`,
  requiredEvidenceValues,
);

const requiredProposalFieldValues = [
  "id",
  "status",
  "requestedBy",
  "mutationClass",
  "changeKinds",
  "surfaces",
  "platforms",
  "proposalReference",
  "requiredEvidence",
  "outOfScopeDrift",
  "userApprovalStatus",
  "implementationStatus",
  "reviewAfter",
];
requireExactStringSet(
  requireArray(registry, registryPath, "requiredProposalFields"),
  `${registryPath}.requiredProposalFields`,
  requiredProposalFieldValues,
);

const ids = new Set();
for (const [index, proposal] of requireArray(registry, registryPath, "proposals", { nonEmpty: false }).entries()) {
  const label = `${registryPath}.proposals[${index}]`;
  requireFields(proposal, label, requiredProposalFieldValues);
  if (ids.has(proposal.id)) fail(`${label}.id duplicates ${proposal.id}`);
  ids.add(proposal.id);
  if (!allowedStatuses.has(proposal.status)) fail(`${label}.status is not allowed`);
  if (!allowedMutationClasses.has(proposal.mutationClass)) fail(`${label}.mutationClass is not allowed`);
  for (const kind of requireStringSet(requireArray(proposal, label, "changeKinds"), `${label}.changeKinds`)) {
    if (!allowedChangeKinds.has(kind)) fail(`${label}.changeKinds contains ${kind}`);
  }
  requireStringSet(requireArray(proposal, label, "surfaces"), `${label}.surfaces`);
  for (const platform of requireStringSet(requireArray(proposal, label, "platforms"), `${label}.platforms`)) {
    if (!allowedPlatforms.has(platform)) fail(`${label}.platforms contains ${platform}`);
  }
  for (const evidence of requireStringSet(requireArray(proposal, label, "requiredEvidence"), `${label}.requiredEvidence`)) {
    if (!allowedRequiredEvidence.has(evidence)) fail(`${label}.requiredEvidence contains unsupported ${evidence}`);
  }
  requireArray(proposal, label, "outOfScopeDrift", { nonEmpty: false });
  requirePublicReference(proposal.proposalReference, `${label}.proposalReference`);
  const reviewAfter = requireIsoDate(proposal.reviewAfter, `${label}.reviewAfter`);
  if (proposal.status === "conceptual-only" && proposal.implementationStatus !== "not-approved") {
    fail(`${label}.implementationStatus must be not-approved while conceptual-only`);
  }
  if (proposal.status !== "user-approved-for-visual-lane" && proposal.userApprovalStatus === "approved") {
    fail(`${label}.userApprovalStatus cannot be approved unless status is user-approved-for-visual-lane`);
  }
  if (approvalRequiredStatuses.has(proposal.status)) {
    if (proposal.userApprovalStatus !== "approved") {
      fail(`${label}.userApprovalStatus must be approved for ${proposal.status}`);
    }
    if (proposal.approvedBy !== "user") fail(`${label}.approvedBy must be user for ${proposal.status}`);
    requireIsoDate(proposal.approvedAt, `${label}.approvedAt`);
    const approvalSuffix = requireSafePrivateReference(proposal.privateApprovalReference, registry.privateApprovalAlias, `${label}.privateApprovalReference`);
    const expectedApprovalSuffix = `visual-proposals/${proposal.id}`;
    if (approvalSuffix && approvalSuffix !== expectedApprovalSuffix) {
      fail(`${label}.privateApprovalReference must target ${expectedApprovalSuffix}`);
    }
  }
  if (reviewAfter && reviewAfter < today) fail(`${label}.reviewAfter expired on ${proposal.reviewAfter}`);
}

scanForLocalPaths(registry, registryPath);

if (errors.length > 0) {
  console.error("UI visual proposal check failed:");
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(`UI visual proposal check passed (${ids.size} proposals)`);
